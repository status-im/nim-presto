import stew/byteutils
import chronos, chronos/apps, chronos/unittest2/asynctests
import helpers, ../presto/route, ../presto/segpath, ../presto/middleware

when defined(nimHasUsed): {.used.}

suite "REST API server middleware test suite":
  asyncTest "Multiple REST filtering middlewares test":
    var
      router1 = RestRouter.init(testValidate)
      router2 = RestRouter.init(testValidate)
      middleware1 = RestServerMiddlewareRef.new(router1)
      middleware2 = RestServerMiddlewareRef.new(router2)

    router1.api(MethodGet, "/test1/{smp1}") do (smp1: int) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      RestApiResponse.response("router1:test1:" & $smp1.get())

    router2.api(MethodGet, "/test2/{smp1}") do (smp1: int) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      RestApiResponse.response("router2:test2:" & $smp1.get())

    router1.api(MethodGet, "/test3/{smp1}") do (smp1: int) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      RestApiResponse.response("router1:test3:" & $smp1.get())

    router2.api(MethodPost, "/test3/{smp1}") do (
      smp1: int, contentBody: Option[ContentBody]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          $body.contentType & ":" & string.fromBytes(body.data)
        else:
          "nobody"
      RestApiResponse.response("router2:test3:" & $smp1.get() & ":" & obody)

    proc process(r: RequestFence): Future[HttpResponseRef] {.
         async: (raises: [CancelledError]).} =
      if r.isOk():
        let request = r.get()
        if request.uri.path == "/test0":
          try:
            await request.respond(Http200, "original:test0")
          except HttpWriteError as exc:
            defaultResponse(exc)
        else:
          defaultResponse()
      else:
        defaultResponse()

    let
      socketFlags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr}
      middlewares = [middleware1, middleware2]
      res = HttpServerRef.new(initTAddress("127.0.0.1:0"), process,
                              middlewares = middlewares,
                              socketFlags = socketFlags)

    check res.isOk()

    let server = res.get()
    server.start()
    try:
      let address = server.instance.localAddress()

      block:
        # Requesting original handler.
        let res = await httpClient(address, MethodGet, "/test0", "")
        check:
          res.status == 200
          res.data == "original:test0"

      block:
        # Requesting missing handler
        let res = await httpClient(address, MethodGet, "/test100", "")
        check:
          res.status == 404

      block:
        # Requesting missing handler
        let res = await httpClient(address, MethodGet, "/test100", "")
        check:
          res.status == 404

      block:
        # Requesting middleware#1 handler
        let res = await httpClient(address, MethodGet, "/test1/65535", "")
        check:
          res.status == 200
          res.data == "router1:test1:65535"

      block:
        # Requesting middleware#2 handler
        let res = await httpClient(address, MethodGet, "/test2/31337", "")
        check:
          res.status == 200
          res.data == "router2:test2:31337"

      block:
        # Requesting middleware#1 GET handler with same name
        let res = await httpClient(address, MethodGet, "/test3/100500", "")
        check:
          res.status == 200
          res.data == "router1:test3:100500"

      block:
        # Requesting middleware#2 POST handler with same name
        let res = await httpClient(address, MethodPost, "/test3/123456",
                                   "body", "text/plain")
        check:
          res.status == 200
          res.data == "router2:test3:123456:text/plain:body"

    finally:
      await server.stop()
      await server.closeWait()
