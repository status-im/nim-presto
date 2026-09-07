import pkg/presto

# ANCHOR: decode
proc decodeString*(t: typedesc[string], value: string): RestResult[string] =
  ok(value)
# ANCHOR_END: decode

# ANCHOR: validate
proc validate(pattern: string, value: string): int = 0
# ANCHOR_END: validate

# ANCHOR: server
var router = RestRouter.init(validate)

router.api(MethodGet, "/") do () -> RestApiResponse:
  RestApiResponse.response("Hello World", Http200, "text/plain")

let server = RestServerRef.new(router, initTAddress("127.0.0.1:9000")).get()
server.start()
runForever()
# ANCHOR_END: server
