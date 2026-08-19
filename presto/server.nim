#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)

{.push raises: [].}

import std/[options, json]
import chronos, chronos/apps/http/httpserver
import chronicles
import results
import "."/[route, common, segpath, servercommon, serverprivate, agent]
export options, results, chronos, httpserver, servercommon, chronicles, agent

type
  RestServerGen*[B: BodyType] = object of RootObj
    server*: HttpServerRef
    router*: RestRouterGen[B]
    errorHandler*: RestRequestErrorHandler

  RestServerRefGen*[B: BodyType] = ref RestServerGen[B]

  RestServer* = RestServerGen[Option[ContentBody]]
  RestServerRef* = RestServerRefGen[Option[ContentBody]]

proc new*[B: BodyType](t: typedesc[RestServerRefGen[B]],
          router: RestRouterGen[B],
          address: TransportAddress,
          serverIdent: string = PrestoIdent,
          serverFlags = {HttpServerFlags.NotifyDisconnect},
          socketFlags: set[ServerFlags] = {ReuseAddr},
          serverUri = Uri(),
          maxConnections: int = -1,
          backlogSize: int = DefaultBacklogSize,
          bufferSize: int = 4096,
          httpHeadersTimeout = 10.seconds,
          maxHeadersSize: int = 8192,
          maxRequestBodySize: int = 1_048_576,
          requestErrorHandler: RestRequestErrorHandler = nil,
          dualstack = DualStackType.Auto,
          errorType: type = cstring
          ): Result[RestServerRefGen[B], errorType] =
  var server = RestServerRefGen[B](router: router,
                                   errorHandler: requestErrorHandler)

  proc processCallback(rf: RequestFence): Future[HttpResponseRef] {.
       async: (raw: true, raises: [CancelledError]).} =
    processRestRequest[RestServerRefGen[B]](server, rf)

  let sres = HttpServerRef.new(address, processCallback, serverFlags,
                               socketFlags, serverUri, serverIdent,
                               maxConnections, bufferSize, backlogSize,
                               httpHeadersTimeout, maxHeadersSize,
                               maxRequestBodySize, dualstack = dualstack)
  if sres.isOk():
    server.server = sres.get()
    ok(server)
  else:
    when errorType is cstring:
      error "REST service could not be started", address = address,
            reason = sres.error
      err("Could not create HTTP server instance")
    elif errorType is string:
      err(sres.error)
    else:
      {.fatal: "Error type is not supported".}

proc localAddress*[B: BodyType](rs: RestServerRefGen[B]): TransportAddress =
  ## Returns `rs` bound local socket address.
  rs.server.instance.localAddress()

proc state*[B: BodyType](rs: RestServerRefGen[B]): RestServerState =
  ## Returns current REST server's state.
  case rs.server.state
  of HttpServerState.ServerClosed:
    RestServerState.Closed
  of HttpServerState.ServerStopped:
    RestServerState.Stopped
  of HttpServerState.ServerRunning:
    RestServerState.Running

proc start*[B: BodyType](rs: RestServerRefGen[B]) =
  ## Starts REST server.
  rs.server.start()
  notice "REST service started", address = $rs.localAddress()

proc stop*[B: BodyType](rs: RestServerRefGen[B]) {.async: (raises: []).} =
  ## Stop REST server from accepting new connections.
  await rs.server.stop()
  notice "REST service stopped", address = $rs.localAddress()

proc drop*[B: BodyType](rs: RestServerRefGen[B]): Future[void] {.
     async: (raw: true, raises: []).} =
  ## Drop all pending connections.
  rs.server.drop()

proc closeWait*[B: BodyType](rs: RestServerRefGen[B]) {.async: (raises: []).} =
  ## Stop REST server and drop all the pending connections.
  await rs.server.closeWait()
  notice "REST service closed", address = $rs.localAddress()

proc join*[B: BodyType](rs: RestServerRefGen[B]): Future[void] {.
     async: (raw: true, raises: [CancelledError]).} =
  ## Wait until REST server will not be closed.
  rs.server.join()
