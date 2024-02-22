import pkg/presto/[route, server]

proc decodeString*(t: typedesc[string], value: string): RestResult[string] =
  ok(value)

when isMainModule:
  var router = RestRouter.init(proc(pattern: string, value: string): int = 0)

  router.api(MethodGet, "/") do () -> RestApiResponse:
    RestApiResponse.response("Hello World", Http200, "textt/plain")

  let restServer = RestServerRef.new(router, initTAddress("127.0.0.1:9000")).get
  restServer.start()

  runForever()
