import pkg/presto

proc decodeString*(t: typedesc[string], value: string): RestResult[string] =
  ok(value)

proc validate(pattern: string, value: string): int = 0

proc run() {.async.} =
  var router = RestRouter.init(validate)
  router.api(MethodGet, "/") do () -> RestApiResponse:
    RestApiResponse.response("ok")

  let server = RestServerRef.new(router, initTAddress("127.0.0.1:8080")).get()
  # ANCHOR: bracket
  server.start()
  try:
    # … issue requests …
    discard
  finally:
    await server.closeWait()
  # ANCHOR_END: bracket

waitFor run()
