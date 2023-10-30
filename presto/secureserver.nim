#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import std/options
import chronos, chronos/apps/http/shttpserver
import chronicles
import stew/results
import route, common, segpath, servercommon, serverprivate, agent
export options, chronos, shttpserver, servercommon, chronicles, agent

type
  SecureRestServer* = object of RootObj
    server*: SecureHttpServerRef
    router*: RestRouter
    errorHandler*: RestRequestErrorHandler

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
          backlogSize: int = DefaultBacklogSize,
          bufferSize: int = 4096,
          httpHeadersTimeout = 10.seconds,
          maxHeadersSize: int = 8192,
          maxRequestBodySize: int = 1_048_576,
          requestErrorHandler: RestRequestErrorHandler = nil,
          errorType: type = cstring
         ): Result[SecureRestServerRef, errorType] =
  var server = SecureRestServerRef(
    router: router,
    errorHandler: requestErrorHandler
  )

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
    when errorType is cstring:
      error "REST service could not be started", address = address,
            reason = sres.error
      err("Could not create HTTP server instance")
    elif errorType is string:
      err(sres.error)
    else:
      {.fatal: "Error type is not supported".}

proc localAddress*(rs: SecureRestServerRef): TransportAddress {.raises: [].} =
  ## Returns `rs` bound local socket address.
  rs.server.instance.localAddress()

proc state*(rs: SecureRestServerRef): RestServerState {.raises: [].} =
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
  notice "Secure REST service started", address = $rs.localAddress()

proc stop*(rs: SecureRestServerRef) {.async.} =
  ## Stop REST server from accepting new connections.
  await rs.server.stop()
  notice "Secure REST service stopped", address = $rs.localAddress()

proc drop*(rs: SecureRestServerRef): Future[void] =
  ## Drop all pending connections.
  rs.server.drop()

proc closeWait*(rs: SecureRestServerRef) {.async.} =
  ## Stop REST server and drop all the pending connections.
  await rs.server.closeWait()
  notice "Secure REST service closed", address = $rs.localAddress()

proc join*(rs: SecureRestServerRef): Future[void] =
  ## Wait until REST server will not be closed.
  rs.server.join()
