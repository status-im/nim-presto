#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import std/[options, strutils]
import chronos
import chronicles
import stew/results
import route, common, segpath, servercommon

proc getContentBody*(r: HttpRequestRef): Future[Option[ContentBody]] {.
     async.} =
  if r.meth notin PostMethods:
    return none[ContentBody]()
  else:
    var default: seq[byte]
    if r.contentTypeData.isNone():
      raise newException(RestBadRequestError,
                         "Incorrect/missing Content-Type header")
    let data =
      if r.hasBody():
        await r.getBody()
      else:
        default
    let cbody = ContentBody(contentType: r.contentTypeData.get(),
                                   data: data)
    return some[ContentBody](cbody)

proc originsMatch(requestOrigin, allowedOrigin: string): bool =
  if allowedOrigin.startsWith("http://") or allowedOrigin.startsWith("https://"):
    requestOrigin == allowedOrigin
  elif requestOrigin.startsWith("http://"):
    requestOrigin.toOpenArray(7, requestOrigin.len - 1) == allowedOrigin
  elif requestOrigin.startsWith("https://"):
    requestOrigin.toOpenArray(8, requestOrigin.len - 1) == allowedOrigin
  else:
    false

proc mergeHttpHeaders(a: var HttpTable, b: HttpTable) =
  # Copy headers from table ``b`` to table ``a`` whose keys are not present in
  # ``a``.
  for key, items in b.items():
    if key notin a:
      for item in items:
        a.add(key, item)

proc processRestRequest*[T](server: T,
                            rf: RequestFence): Future[HttpResponseRef] {.
     gcsafe, async.} =
  if rf.isOk():
    let request = rf.get()
    let sres = SegmentedPath.init(request.meth, request.uri.path)
    if sres.isOk():
      debug "Received request", peer = $request.remoteAddress(),
            meth = $request.meth, uri = $request.uri
      let rres = server.router.getRoute(sres.get())
      if rres.isSome():
        let route = rres.get()
        let pathParams = route.getParamsTable()
        let queryParams = request.query

        let optBody =
          if RestRouterFlag.Raw notin route.flags:
            try:
              await request.getContentBody()
            except HttpCriticalError as exc:
              debug "Unable to obtain request body", uri = $request.uri,
                    peer = $request.remoteAddress(), meth = $request.meth,
                    error_msg = $exc.msg
              return await request.respond(Http400)
            except RestBadRequestError as exc:
              debug "Request has incorrect content type", uri = $request.uri,
                     peer = $request.remoteAddress(), meth = $request.meth,
                     error_msg = $exc.msg
              return await request.respond(Http400)
            except CatchableError as exc:
              warn "Unexpected exception while getting request body",
                    uri = $request.uri, peer = $request.remoteAddress(),
                    meth = $request.meth, error_name = $exc.name,
                    error_msg = $exc.msg
              return await request.respond(Http400)
          else:
            none[ContentBody]()

        debug "Serving API request", peer = $request.remoteAddress(),
              meth = $request.meth, uri = $request.uri,
              path_params = pathParams, query_params = queryParams,
              content_body = optBody

        let restRes =
          try:
            await route.callback(request, pathParams, queryParams, optBody)
          except HttpCriticalError as exc:
            debug "Critical error occurred while processing a request",
                  meth = $request.meth, peer = $request.remoteAddress(),
                  uri = $request.uri, code = exc.code,
                  path_params = pathParams, query_params = queryParams,
                  content_body = optBody, error_msg = $exc.msg
            return await request.respond(exc.code)
          except CatchableError as exc:
            warn "Unexpected error occured while processing a request",
                  meth = $request.meth, peer = $request.remoteAddress(),
                  uri = $request.uri, path_params = pathParams,
                  query_params = queryParams, content_body = optBody,
                  error_msg = $exc.msg, error_name = $exc.name
            return await request.respond(Http503)

        try:
          if not(request.responded()):
            case restRes.kind
            of RestApiResponseKind.Empty:
              debug "Received empty response from handler",
                      meth = $request.meth, peer = $request.remoteAddress(),
                      uri = $request.uri
              return await request.respond(Http410)
            of RestApiResponseKind.Content:
              var headers = HttpTable.init([("Content-Type",
                                            restRes.content.contentType)])
              if server.router.allowedOrigin.isSome:
                let origin = request.headers.getList("Origin")
                let everyOriginAllowed = server.router.allowedOrigin.get == "*"
                if origin.len == 1:
                  if everyOriginAllowed:
                    headers.add("Access-Control-Allow-Origin", "*")
                  elif originsMatch(origin[0], server.router.allowedOrigin.get):
                    # The Vary: Origin header to must be set to prevent
                    # potential cache poisoning attacks:
                    # https://textslashplain.com/2018/08/02/cors-and-vary/
                    headers.add("Vary", "Origin")
                    headers.add("Access-Control-Allow-Origin", origin[0])
                elif origin.len > 1:
                  return await request.respond(Http400,
                    "Only a single Origin header must be specified")

              debug "Received response from handler",
                    status = restRes.status.toInt(),
                    meth = $request.meth, peer = $request.remoteAddress(),
                    uri = $request.uri,
                    content_type = restRes.content.contentType,
                    content_size = len(restRes.content.data)

              headers.mergeHttpHeaders(restRes.headers)
              return await request.respond(restRes.status,
                                           restRes.content.data, headers)
            of RestApiResponseKind.Error:
              let error = restRes.errobj
              debug "Received error response from handler",
                    status = restRes.status.toInt(),
                    meth = $request.meth, peer = $request.remoteAddress(),
                    uri = $request.uri, error
              var headers = HttpTable.init([("Content-Type",
                                            error.contentType)])

              headers.mergeHttpHeaders(restRes.headers)
              return await request.respond(error.status, error.message,
                                           headers)
            of RestApiResponseKind.Redirect:
              debug "Received redirection from handler",
                    status = restRes.status.toInt(),
                    meth = $request.meth, peer = $request.remoteAddress(),
                    uri = $request.uri, location = restRes.location
              let location =
                block:
                  var uri = parseUri(restRes.location)
                  if restRes.preserveQuery:
                    if len(uri.query) == 0:
                      uri.query = request.uri.query
                    else:
                      uri.query = uri.query & "&" & request.uri.query
                  $uri
              return await request.redirect(restRes.status, location,
                                            restRes.headers)
          else:
            debug "Response was sent in request handler", meth = $request.meth,
                  peer = $request.remoteAddress(), uri = $request.uri,
                  path_params = pathParams, query_params = queryParams,
                  content_body = optBody
            return request.getResponse()
        except HttpCriticalError as exc:
          debug "Critical error occured while sending response",
                meth = $request.meth, peer = $request.remoteAddress(),
                uri = $request.uri, code = exc.code, error_msg = $exc.msg
          return dumbResponse()
        except CatchableError as exc:
          warn "Unexpected error occured while sending response",
               meth = $request.meth, peer = $request.remoteAddress(),
               uri = $request.uri,  error_msg = $exc.msg,
               error_name = $exc.name
          return dumbResponse()
      else:
        debug "Request is not part of API", peer = $request.remoteAddress(),
              meth = $request.meth, uri = $request.uri
        return await request.respond(Http404, "", HttpTable.init())
    else:
      debug "Received invalid request", peer = $request.remoteAddress(),
            meth = $request.meth, uri = $request.uri
      return await request.respond(Http400, "", HttpTable.init())
  else:
    let httpErr = rf.error()
    if httpErr.error == HttpServerError.DisconnectError:
      debug "Remote peer disconnected", peer = $httpErr.remote,
            reason = $httpErr.error
    else:
      debug "Remote peer dropped connection", peer = $httpErr.remote,
            reason = $httpErr.error, code = $httpErr.code

    return dumbResponse()
