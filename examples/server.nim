import pkg/presto/[route, server]
import stew/byteutils

proc validate(pattern: string, value: string): int = 0

when isMainModule:
  var router = RestRouter.init(validate)

  router.api(MethodPost, "/hello/world") do (
             contentBody: Option[ContentBody]) -> RestApiResponse:
    echo "Client says: ", string.fromBytes(contentBody.get().data)

    RestApiResponse.response("Hello Client, I am Server", Http200, "textt/plain")

  let restServer = RestServerRef.new(router, initTAddress("127.0.0.1:9000")).get
  restServer.start()

  runForever()
