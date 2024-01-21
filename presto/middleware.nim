#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)

{.push raises: [].}

import chronos, chronos/apps/http/httpserver
import route, servercommon, serverprivate
export httpserver, servercommon, serverprivate

proc new*(
    t: typedesc[RestServerMiddlewareRef],
    router: RestRouter,
    errorHandler: RestRequestErrorHandler = nil): HttpServerMiddlewareRef =

  proc middlewareCallback(
      middleware: HttpServerMiddlewareRef,
      request: RequestFence,
      handler: HttpProcessCallback2): Future[HttpResponseRef] {.
      async: (raises: [CancelledError], raw: true).} =
    let restmw = RestServerMiddlewareRef(middleware)
    restmw.nextHandler = handler
    processRestRequest[RestServerMiddlewareRef](restmw, request)

  let middleware =
    RestServerMiddlewareRef(router: router, errorHandler: errorHandler,
                            handler: middlewareCallback)
  HttpServerMiddlewareRef(middleware)
