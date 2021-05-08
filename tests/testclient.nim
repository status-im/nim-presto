import std/[unittest, strutils]
import helpers
import chronos, chronos/apps
import stew/byteutils
import ../presto/route, ../presto/segpath, ../presto/server, ../presto/client

when defined(nimHasUsed): {.used.}


template asyncTest*(name: string, body: untyped): untyped =
  test name:
    waitFor((
      proc() {.async, gcsafe.} =
        body
    )())

suite "REST API client test suite":
  let serverAddress = initTAddress("127.0.0.1:30180")
  asyncTest "Responses test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet, "/test/simple/1") do () -> RestApiResponse:
      return RestApiResponse.response("ok-1")

    router.api(MethodPost, "/test/simple/2",) do (
      contentBody: Option[ContentBody]) -> RestApiResponse:
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response(obody)

    router.api(MethodGet, "/test/simple/3") do () -> RestApiResponse:
      return RestApiResponse.error(Http504, "Some error", "text/error")

    router.api(MethodPost, "/test/simple/4") do (
      contentBody: Option[ContentBody]) -> RestApiResponse:
      return RestApiResponse.error(Http505, "Different error",
                                   "application/error")

    var sres = RestServerRef.new(router, serverAddress)
    let server = sres.get()
    server.start()

    proc testSimple1(): string {.rest, endpoint: "/test/simple/1".}
    proc testSimple2(body: string): string {.rest, endpoint: "/test/simple/2",
                                             meth: MethodPost.}
    proc testSimple3(): string {.rest, endpoint: "/test/simple/3".}
    proc testSimple4(body: string): string {.rest, endpoint: "/test/simple/4",
                                             meth: MethodPost.}

    var client = RestClientRef.new(serverAddress, HttpClientScheme.NonSecure)
    let res1 = await client.testSimple1()
    let res2 = await client.testSimple2("ok-2", restContentType = "text/text")
    check:
      res1 == "ok-1"
      res2 == "text/text,ok-2"

    block:
      let (code, message, contentType) =
        try:
          let res3 {.used.} = await client.testSimple3()
          (0, "", "")
        except RestResponseError as exc:
          (exc.status, exc.message, exc.contentType)
        except CatchableError:
          (0, "", "")

      check:
        code == 504
        message == "Some error"
        contentType == "text/error"

    block:
      let (code, message, contentType) =
        try:
          let res3 {.used.} = await client.testSimple4("ok-4",
                                                  restContentType = "text/text")
          (0, "", "")
        except RestResponseError as exc:
          (exc.status, exc.message, exc.contentType)
        except CatchableError:
          (0, "", "")

      check:
        code == 505
        message == "Different error"
        contentType == "application/error"

    await client.closeWait()
    await server.stop()
    await server.closeWait()


  test "Leaks test":
    proc getTrackerLeaks(tracker: string): bool =
      let tracker = getTracker(tracker)
      if isNil(tracker): false else: tracker.isLeaked()

    check:
      getTrackerLeaks("http.body.reader") == false
      getTrackerLeaks("http.body.writer") == false
      getTrackerLeaks("httpclient.connection") == false
      getTrackerLeaks("httpclient.request") == false
      getTrackerLeaks("httpclient.response") == false
      getTrackerLeaks("async.stream.reader") == false
      getTrackerLeaks("async.stream.writer") == false
      getTrackerLeaks("stream.server") == false
      getTrackerLeaks("stream.transport") == false
