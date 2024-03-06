import pkg/presto/[route, client]
import ../tests/helpers

proc hello() {.async.} =
  var restClient = RestClientRef.new(initTAddress("127.0.0.1:9000"))
  proc helloCall(body: string): string {.
      rest, endpoint: "/hello/world", meth: MethodPost.}
  let res = await restClient.helloCall("Hello Server!", restContentType = "text/plain")
  echo "Server response: ", res

when isMainModule:
  waitFor hello()
