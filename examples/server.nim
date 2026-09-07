import pkg/presto

proc decodeString*(t: typedesc[string], value: string): RestResult[string] =
  ok(value)

proc validate(pattern: string, value: string): int = 0

proc main() {.async.} =
  var router = RestRouter.init(validate)
  router.api(MethodGet, "/") do () -> RestApiResponse:
    RestApiResponse.response("ok")

  let address = initTAddress("127.0.0.1:8080")

  # ANCHOR: create
  let server = RestServerRef.new(router, address).get()
  # ANCHOR_END: create

  # ANCHOR: errortype
  let res = RestServerRef.new(router, address, errorType = string)
  if res.isErr():
    echo "failed to start: ", res.error()
  # ANCHOR_END: errortype

  # ANCHOR: lifecycle
  server.start()              # begin accepting connections
  echo server.state           # Running | Stopped | Closed
  echo server.localAddress()  # actual bound address (useful with port 0)
  # ANCHOR_END: lifecycle

  # ANCHOR: shutdown
  await server.stop()         # stop accepting new connections
  await server.drop()         # drop pending connections
  await server.closeWait()    # stop and release all resources
  # ANCHOR_END: shutdown

waitFor main()
