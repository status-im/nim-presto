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

proc getContentBody*(r: HttpRequestRef): Future[Option[ContentBody]] {.async.} =
  if r.meth notin PostMethods:
    return none[ContentBody]()
  else:
    var default: seq[byte]
    let cres = getContentType(r.headers.getList("content-type"))
    if not(cres.isOk()):
      raise newException(RestBadRequestError, "Incorrect Content-Type header")
    let data =
      if r.hasBody():
        await r.getBody()
      else:
        default
    let cbody = ContentBody(contentType: cres.get(), data: data)
    return some[ContentBody](cbody)

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
              let headers = HttpTable.init([("Content-Type",
                                            restRes.content.contentType)])
              debug "Received response from handler",
                    status = restRes.status,
                    meth = $request.meth, peer = $request.remoteAddress(),
                    uri = $request.uri,
                    content_type = restRes.content.contentType,
                    content_size = len(restRes.content.data)
              return await request.respond(restRes.status,
                                           restRes.content.data, headers)
            of RestApiResponseKind.Error:
              let error = restRes.errobj
              debug "Received error response from handler",
                    status = restRes.status,
                    meth = $request.meth, peer = $request.remoteAddress(),
                    uri = $request.uri, error
              let headers = HttpTable.init([("Content-Type",
                                            error.contentType)])
              return await request.respond(error.status, error.message,
                                           headers)
            of RestApiResponseKind.Redirect:
              debug "Received redirection from handler",
                    status = restRes.status,
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
              return await request.redirect(restRes.status, location)
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
