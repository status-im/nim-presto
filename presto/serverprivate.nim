#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import std/[options, strutils]
import chronos, chronicles, stew/[base10, results]
import route, common, segpath, servercommon

when defined(metrics):
  import metrics

  declareGauge presto_server_response_status_count,
               "Number of HTTP server responses with specific status",
               labels = ["endpoint", "status"]
  declareGauge presto_server_processed_request_count,
               "Number of HTTP(s) processed requests"
  declareGauge presto_server_missing_requests_count,
               "Number of HTTP(s) requests to unrecognized API endpoints"
  declareGauge presto_server_invalid_requests_count,
               "Number of HTTP(s) requests invalid API endpoints"
  declareGauge presto_server_prepare_response_time,
               "Time taken to prepare response",
               labels = ["endpoint"]

proc getContentBody*(r: HttpRequestRef): Future[Option[ContentBody]] {.
     async.} =
  if r.meth notin PostMethods:
    return none[ContentBody]()
  if not(r.hasBody()):
    return none[ContentBody]()
  if (HttpRequestFlags.BoundBody in r.requestFlags) and (r.contentLength == 0):
    return none[ContentBody]()
  if r.contentTypeData.isNone():
    raise newException(RestBadRequestError,
                       "Incorrect/missing Content-Type header")
  let data = await r.getBody()
  return some[ContentBody](
    ContentBody(contentType: r.contentTypeData.get(), data: data))

proc originsMatch(requestOrigin, allowedOrigin: string): bool =
  if allowedOrigin.startsWith("http://") or
     allowedOrigin.startsWith("https://"):
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

when defined(metrics):
  proc processStatusMetrics(route: RestRoute, code: HttpCode) =
    if RestServerMetricsType.Status in route.metrics:
      let
        endpoint = $route.routePath
        scode = Base10.toString(uint64(toInt(code)))
      presto_server_response_status_count.inc(1, @[endpoint, scode])

  proc processStatusMetrics(route: RestRoute, code: HttpCode,
                            duration: Duration) =
    if RestServerMetricsType.Status in route.metrics:
      processStatusMetrics(route, code)
    if RestServerMetricsType.Response in route.metrics:
      let endpoint = $route.routePath
      presto_server_prepare_response_time.set(duration.milliseconds(),
                                              @[endpoint])

  proc processMetrics(route: RestRoute, duration: Duration) =
    if RestServerMetricsType.Response in route.metrics:
      let endpoint = $route.routePath
      presto_server_prepare_response_time.set(duration.milliseconds(),
                                              @[endpoint])

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
        let
          route = rres.get()
          pathParams = route.getParamsTable()
          queryParams = request.query

        when defined(metrics):
          presto_server_processed_request_count.inc()

        let optBody =
          if RestRouterFlag.Raw notin route.flags:
            try:
              await request.getContentBody()
            except HttpCriticalError as exc:
              debug "Unable to obtain request body", uri = $request.uri,
                    peer = $request.remoteAddress(), meth = $request.meth,
                    error_msg = $exc.msg

              when defined(metrics):
                processStatusMetrics(route, Http400)

              return
                if isNil(server.errorHandler):
                  await request.respond(Http400)
                else:
                  await server.errorHandler(
                    RestRequestError.InvalidContentBody, request)
            except RestBadRequestError as exc:
              debug "Request has incorrect content type", uri = $request.uri,
                     peer = $request.remoteAddress(), meth = $request.meth,
                     error_msg = $exc.msg

              when defined(metrics):
                processStatusMetrics(route, Http400)

              return
                if isNil(server.errorHandler):
                  await request.respond(Http400)
                else:
                  await server.errorHandler(
                    RestRequestError.InvalidContentType, request)
            except CatchableError as exc:
              warn "Unexpected exception while getting request body",
                    uri = $request.uri, peer = $request.remoteAddress(),
                    meth = $request.meth, error_name = $exc.name,
                    error_msg = $exc.msg

              when defined(metrics):
                processStatusMetrics(route, Http400)

              return
                if isNil(server.errorHandler):
                  await request.respond(Http400)
                else:
                  await server.errorHandler(
                    RestRequestError.Unexpected, request)
          else:
            none[ContentBody]()

        debug "Serving API request", peer = $request.remoteAddress(),
              meth = $request.meth, uri = $request.uri,
              path_params = pathParams, query_params = queryParams,
              content_body = optBody

        let
          responseStart = Moment.now()
          restRes =
            try:
              let res = await route.callback(request, pathParams, queryParams,
                                             optBody)

              when defined(metrics):
                processMetrics(route, Moment.now() - responseStart)

              res

            except HttpCriticalError as exc:
              debug "Critical error occurred while processing a request",
                    meth = $request.meth, peer = $request.remoteAddress(),
                    uri = $request.uri, code = exc.code,
                    path_params = pathParams, query_params = queryParams,
                    content_body = optBody, error_msg = $exc.msg

              when defined(metrics):
                processStatusMetrics(route, exc.code,
                                     Moment.now() - responseStart)

              return await request.respond(exc.code)
            except CatchableError as exc:
              warn "Unexpected error occured while processing a request",
                    meth = $request.meth, peer = $request.remoteAddress(),
                    uri = $request.uri, path_params = pathParams,
                    query_params = queryParams, content_body = optBody,
                    error_msg = $exc.msg, error_name = $exc.name

              when defined(metrics):
                processStatusMetrics(route, Http503,
                                     Moment.now() - responseStart)

              return await request.respond(Http503)

        try:
          if not(request.responded()):
            case restRes.kind
            of RestApiResponseKind.Empty:
              debug "Received empty response from handler",
                      meth = $request.meth, peer = $request.remoteAddress(),
                      uri = $request.uri

              when defined(metrics):
                processStatusMetrics(route, Http400)

              return await request.respond(Http410)
            of RestApiResponseKind.Status:
              var headers = HttpTable.init()
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

                  when defined(metrics):
                    processStatusMetrics(route, Http400)

                  return await request.respond(Http400,
                    "Only a single Origin header must be specified")

              debug "Received status response from handler",
                    status = restRes.status.toInt(),
                    meth = $request.meth, peer = $request.remoteAddress(),
                    uri = $request.uri

              headers.mergeHttpHeaders(restRes.headers)

              when defined(metrics):
                processStatusMetrics(route, restRes.status)

              return await request.respond(restRes.status, "", headers)
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

                  when defined(metrics):
                    processStatusMetrics(route, Http400)

                  return await request.respond(Http400,
                    "Only a single Origin header must be specified")

              debug "Received response from handler",
                    status = restRes.status.toInt(),
                    meth = $request.meth, peer = $request.remoteAddress(),
                    uri = $request.uri,
                    content_type = restRes.content.contentType,
                    content_size = len(restRes.content.data)

              headers.mergeHttpHeaders(restRes.headers)

              when defined(metrics):
                processStatusMetrics(route, restRes.status)

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

              when defined(metrics):
                processStatusMetrics(route, error.status)

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

              when defined(metrics):
                processStatusMetrics(route, restRes.status)

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
          return defaultResponse()
        except CatchableError as exc:
          warn "Unexpected error occured while sending response",
               meth = $request.meth, peer = $request.remoteAddress(),
               uri = $request.uri,  error_msg = $exc.msg,
               error_name = $exc.name
          return defaultResponse()
      else:
        debug "Request is not part of API", peer = $request.remoteAddress(),
              meth = $request.meth, uri = $request.uri

        when defined(metrics):
          presto_server_missing_requests_count.inc()

        return
          if isNil(server.errorHandler):
            await request.respond(Http404, "", HttpTable.init())
          else:
            await server.errorHandler(RestRequestError.NotFound, request)
    else:
      debug "Received invalid request", peer = $request.remoteAddress(),
            meth = $request.meth, uri = $request.uri

      when defined(metrics):
        presto_server_invalid_requests_count.inc()

      return
        if isNil(server.errorHandler):
          await request.respond(Http400, "", HttpTable.init())
        else:
          await server.errorHandler(RestRequestError.Invalid, request)
  else:
    let httpErr = rf.error()
    if httpErr.error == HttpServerError.DisconnectError:
      debug "Remote peer disconnected", peer = $httpErr.remote,
            reason = $httpErr.error
    else:
      debug "Remote peer dropped connection", peer = $httpErr.remote,
            reason = $httpErr.error, code = $httpErr.code

    return defaultResponse()
