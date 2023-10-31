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
import route, common, segpath, servercommon, serverprivate, agent
export options, chronos, httpserver, servercommon, chronicles, agent

{.push raises: [].}

type
  RestServer* = object of RootObj
    server*: HttpServerRef
    router*: RestRouter
    errorHandler*: RestRequestErrorHandler

  RestServerRef* = ref RestServer

proc new*(t: typedesc[RestServerRef],
          router: RestRouter,
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
          ): Result[RestServerRef, errorType] =
  var server = RestServerRef(router: router, errorHandler: requestErrorHandler)

  proc processCallback(rf: RequestFence): Future[HttpResponseRef] =
    processRestRequest[RestServerRef](server, rf)

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

proc localAddress*(rs: RestServerRef): TransportAddress =
  ## Returns `rs` bound local socket address.
  rs.server.instance.localAddress()

proc state*(rs: RestServerRef): RestServerState =
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
  notice "REST service started", address = $rs.localAddress()

proc stop*(rs: RestServerRef) {.async.} =
  ## Stop REST server from accepting new connections.
  await rs.server.stop()
  notice "REST service stopped", address = $rs.localAddress()

proc drop*(rs: RestServerRef): Future[void] =
  ## Drop all pending connections.
  rs.server.drop()

proc closeWait*(rs: RestServerRef) {.async.} =
  ## Stop REST server and drop all the pending connections.
  await rs.server.closeWait()
  notice "REST service closed", address = $rs.localAddress()

proc join*(rs: RestServerRef): Future[void] =
  ## Wait until REST server will not be closed.
  rs.server.join()
