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

type
  RestServer* = object of RootObj
    server*: HttpServerRef
    router*: RestRouter

  RestServerRef* = ref RestServer

proc new*(t: typedesc[RestServerRef],
          router: RestRouter,
          address: TransportAddress,
          serverIdent: string = PrestoIdent,
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
