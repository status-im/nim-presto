#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import std/[options, json, strutils]
import chronos, chronos/apps/http/httpserver
import chronicles
import stew/results
import route, common, segpath, servercommon, serverprivate

export options, chronos, httpserver, servercommon

type
  RestServer* = object of RootObj
    server*: HttpServerRef
    router*: RestRouter

  RestServerRef* = ref RestServer

# proc getContentBody(r: HttpRequestRef): Future[Option[ContentBody]] {.async.} =
#   if r.meth notin PostMethods:
#     return none[ContentBody]()
#   else:
#     var default: seq[byte]
#     let cres = getContentType(r.headers.getList("content-type"))
#     if not(cres.isOk()):
#       raise newException(RestBadRequestError, "Incorrect Content-Type header")
#     let data =
#       if r.hasBody():
#         await r.getBody()
#       else:
#         default
#     let cbody = ContentBody(contentType: cres.get(), data: data)
#     return some[ContentBody](cbody)

# proc processRestRequest(server: RestServerRef,
#                         rf: RequestFence): Future[HttpResponseRef] {.
#      gcsafe, async.} =
#   if rf.isOk():
#     let request = rf.get()
#     let sres = SegmentedPath.init(request.meth, request.uri.path)
#     if sres.isOk():
#       debug "Received request", peer = $request.remoteAddress(),
#             meth = $request.meth, uri = $request.uri
#       let rres = server.router.getRoute(sres.get())
#       if rres.isSome():
#         let route = rres.get()
#         let pathParams = route.getParamsTable()
#         let queryParams = request.query

#         let optBody =
#           try:
#             await request.getContentBody()
#           except HttpCriticalError as exc:
#             debug "Unable to obtain request body", uri = $request.uri,
#                   peer = $request.remoteAddress(), meth = $request.meth,
#                   error_msg = $exc.msg
#             return await request.respond(Http400)
#           except RestBadRequestError as exc:
#             debug "Request has incorrect content type", uri = $request.uri,
#                    peer = $request.remoteAddress(), meth = $request.meth,
#                    error_msg = $exc.msg
#             return await request.respond(Http400)
#           except CatchableError as exc:
#             warn "Unexpected exception while getting request body",
#                   uri = $request.uri, peer = $request.remoteAddress(),
#                   meth = $request.meth, error_name = $exc.name,
#                   error_msg = $exc.msg
#             return await request.respond(Http400)

#         debug "Serving API request", peer = $request.remoteAddress(),
#               meth = $request.meth, uri = $request.uri,
#               path_params = pathParams, query_params = queryParams,
#               content_body = optBody

#         let restRes =
#           try:
#             await route.callback(request, pathParams, queryParams, optBody)
#           except HttpCriticalError as exc:
#             debug "Critical error occurred while processing a request",
#                   meth = $request.meth, peer = $request.remoteAddress(),
#                   uri = $request.uri, code = exc.code,
#                   path_params = pathParams, query_params = queryParams,
#                   content_body = optBody, error_msg = $exc.msg
#             return await request.respond(exc.code)
#           except CatchableError as exc:
#             warn "Unexpected error occured while processing a request",
#                   meth = $request.meth, peer = $request.remoteAddress(),
#                   uri = $request.uri, path_params = pathParams,
#                   query_params = queryParams, content_body = optBody,
#                   error_msg = $exc.msg, error_name = $exc.name
#             return await request.respond(Http503)

#         try:
#           if not(request.responded()):
#             if restRes.isOk():
#               let restResponse = restRes.get()
#               let headers = HttpTable.init([("Content-Type",
#                                             restResponse.contentType)])
#               debug "Received response from handler",
#                     meth = $request.meth, peer = $request.remoteAddress(),
#                     uri = $request.uri, content_type = restResponse.contentType,
#                     content_size = len(restResponse.data)
#               return await request.respond(Http200, restResponse.data, headers)
#             else:
#               let error = restRes.error()
#               if isEmpty(error):
#                 debug "Received empty response from handler",
#                       meth = $request.meth, peer = $request.remoteAddress(),
#                       uri = $request.uri
#                 return await request.respond(Http410)
#               else:
#                 debug "Received error response from handler",
#                       meth = $request.meth, peer = $request.remoteAddress(),
#                       uri = $request.uri, error
#                 let headers = HttpTable.init([("Content-Type",
#                                                error.contentType)])
#                 return await request.respond(error.status, error.message,
#                                              headers)
#           else:
#             debug "Response was sent in request handler", meth = $request.meth,
#                   peer = $request.remoteAddress(), uri = $request.uri,
#                   path_params = pathParams, query_params = queryParams,
#                   content_body = optBody
#             return request.getResponse()
#         except HttpCriticalError as exc:
#           debug "Critical error occured while sending response",
#                 meth = $request.meth, peer = $request.remoteAddress(),
#                 uri = $request.uri, code = exc.code, error_msg = $exc.msg
#           return dumbResponse()
#         except CatchableError as exc:
#           warn "Unexpected error occured while sending response",
#                meth = $request.meth, peer = $request.remoteAddress(),
#                uri = $request.uri,  error_msg = $exc.msg,
#                error_name = $exc.name
#           return dumbResponse()
#       else:
#         debug "Request it not part of api", peer = $request.remoteAddress(),
#               meth = $request.meth, uri = $request.uri
#         return await request.respond(Http404, "", HttpTable.init())
#     else:
#       debug "Received invalid request", peer = $request.remoteAddress(),
#             meth = $request.meth, uri = $request.uri
#       return await request.respond(Http400, "", HttpTable.init())
#   else:
#     let httpErr = rf.error()
#     if httpErr.error == HttpServerError.DisconnectError:
#       debug "Remote peer disconnected", peer = $httpErr.remote,
#             reason = $httpErr.error
#     else:
#       debug "Remote peer dropped connection", peer = $httpErr.remote,
#             reason = $httpErr.error, code = $httpErr.code

#     return dumbResponse()

proc new*(t: typedesc[RestServerRef],
          router: RestRouter,
          address: TransportAddress,
          serverIdent: string = "",
          serverFlags = {HttpServerFlags.NotifyDisconnect},
          socketFlags: set[ServerFlags] = {ReuseAddr},
          serverUri = Uri(),
          maxConnections: int = -1,
          backlogSize: int = 100,
          bufferSize: int = 4096,
          httpHeadersTimeout = 10.seconds,
          maxHeadersSize: int = 8192,
          maxRequestBodySize: int = 1_048_576): RestResult[RestServerRef] =
  var server = RestServerRef(router: router)

  proc processCallback(rf: RequestFence): Future[HttpResponseRef] =
    processRestRequest[RestServerRef](server, rf)

  let sres = HttpServerRef.new(address, processCallback, serverFlags,
                               socketFlags, serverUri, serverIdent,
                               maxConnections, bufferSize, backlogSize,
                               httpHeadersTimeout, maxHeadersSize,
                               maxRequestBodySize)
  if sres.isOk():
    server.server = sres.get()
    ok(server)
  else:
    err("Could not create HTTP server instance")

proc state*(rs: RestServerRef): RestServerState {.raises: [Defect].} =
  ## Returns current REST server's state.
  case rs.server.state
  of HttpServerState.ServerClosed:
    RestServerState.Closed
  of HttpServerState.ServerStopped:
    RestServerState.Stopped
  of HttpServerState.ServerRunning:
    RestServerState.Running

proc start*(rs: RestServerRef) =
  ## Starts REST server.
  rs.server.start()
  notice "REST service started", address = $rs.server.address

proc stop*(rs: RestServerRef) {.async.} =
  ## Stop REST server from accepting new connections.
  await rs.server.stop()
  notice "REST service stopped", address = $rs.server.address

proc drop*(rs: RestServerRef): Future[void] =
  ## Drop all pending connections.
  rs.server.drop()

proc closeWait*(rs: RestServerRef) {.async.} =
  ## Stop REST server and drop all the pending connections.
  await rs.server.closeWait()
  notice "REST service closed", address = $rs.server.address

proc join*(rs: RestServerRef): Future[void] =
  ## Wait until REST server will not be closed.
  rs.server.join()
