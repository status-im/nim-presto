#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import std/[options, strutils]
import chronos, chronos/apps/http/shttpserver
import chronicles
import stew/results
import route, common, segpath, servercommon, serverprivate, agent
export options, chronos, shttpserver, servercommon, chronicles, agent

type
  SecureRestServer* = object of RootObj
    server*: SecureHttpServerRef
    router*: RestRouter

  SecureRestServerRef* = ref SecureRestServer

proc new*(t: typedesc[SecureRestServerRef],
          router: RestRouter,
          address: TransportAddress,
          tlsPrivateKey: TLSPrivateKey,
          tlsCertificate: TLSCertificate,
          serverIdent: string = PrestoIdent,
          secureFlags: set[TLSFlags] = {},
          serverFlags = {HttpServerFlags.NotifyDisconnect},
          socketFlags: set[ServerFlags] = {ReuseAddr},
          serverUri = Uri(),
          maxConnections: int = -1,
          backlogSize: int = 100,
          bufferSize: int = 4096,
          httpHeadersTimeout = 10.seconds,
          maxHeadersSize: int = 8192,
          maxRequestBodySize: int = 1_048_576
         ): RestResult[SecureRestServerRef] =
  var server = SecureRestServerRef(router: router)

  proc processCallback(rf: RequestFence): Future[HttpResponseRef] =
    processRestRequest(server, rf)

  let sres = SecureHttpServerRef.new(address, processCallback, tlsPrivateKey,
                                     tlsCertificate, serverFlags, socketFlags,
                                     serverUri, serverIdent, secureFlags,
                                     maxConnections, bufferSize, backlogSize,
                                     httpHeadersTimeout, maxHeadersSize,
                                     maxRequestBodySize)
  if sres.isOk():
    server.server = sres.get()
    ok(server)
  else:
    err("Could not create HTTPS server instance")

proc state*(rs: SecureRestServerRef): RestServerState {.raises: [Defect].} =
  ## Returns current REST server's state.
  case rs.server.state
  of HttpServerState.ServerClosed:
    RestServerState.Closed
  of HttpServerState.ServerStopped:
    RestServerState.Stopped
  of HttpServerState.ServerRunning:
    RestServerState.Running

proc start*(rs: SecureRestServerRef) =
  ## Starts REST server.
  rs.server.start()
  notice "Secure REST service started", address = $rs.server.address

proc stop*(rs: SecureRestServerRef) {.async.} =
  ## Stop REST server from accepting new connections.
  await rs.server.stop()
  notice "Secure REST service stopped", address = $rs.server.address

proc drop*(rs: SecureRestServerRef): Future[void] =
  ## Drop all pending connections.
  rs.server.drop()

proc closeWait*(rs: SecureRestServerRef) {.async.} =
  ## Stop REST server and drop all the pending connections.
  await rs.server.closeWait()
  notice "Secure REST service closed", address = $rs.server.address

proc join*(rs: SecureRestServerRef): Future[void] =
  ## Wait until REST server will not be closed.
  rs.server.join()
