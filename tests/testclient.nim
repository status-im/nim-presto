import std/[unittest, strutils]
import helpers
import chronos, chronos/apps
import stew/byteutils
import ../presto/[route, segpath, server, client]

when defined(nimHasUsed): {.used.}


template asyncTest*(name: string, body: untyped): untyped =
  test name:
    waitFor((
      proc() {.async, gcsafe.} =
        body
    )())

suite "REST API client test suite":
  let serverAddress = initTAddress("127.0.0.1:30180")
  asyncTest "Simple requests (without arguments) test":
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

    router.api(MethodGet, "/test/simple/5") do () -> RestApiResponse:
      return RestApiResponse.redirect(location = "/test/redirect/5")

    router.api(MethodGet, "/test/redirect/5") do () -> RestApiResponse:
      return RestApiResponse.response("ok-5-redirect")

    router.api(MethodPost, "/test/simple/6") do (
      contentBody: Option[ContentBody]) -> RestApiResponse:
      return RestApiResponse.redirect(location = "/test/redirect/6")

    router.api(MethodPost, "/test/redirect/6") do (
      contentBody: Option[ContentBody]) -> RestApiResponse:
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response(obody)

    var sres = RestServerRef.new(router, serverAddress)
    let server = sres.get()
    server.start()

    proc testSimple1(): string {.rest, endpoint: "/test/simple/1".}
    proc testSimple2(body: string): string {.rest, endpoint: "/test/simple/2",
                                             meth: MethodPost.}
    proc testSimple3(): string {.rest, endpoint: "/test/simple/3".}
    proc testSimple4(body: string): string {.rest, endpoint: "/test/simple/4",
                                             meth: MethodPost.}
    proc testSimple5(): string {.rest, endpoint: "/test/simple/5",
                                 meth: HttpMethod.MethodGet.}
    proc testSimple6(body: string): string {.rest, endpoint: "/test/simple/6",
                                             meth: HttpMethod.MethodPost.}

    var client = RestClientRef.new(serverAddress, HttpClientScheme.NonSecure)
    let res1 = await client.testSimple1()
    let res2 = await client.testSimple2("ok-2", restContentType = "text/text")
    let res5 = await client.testSimple5()
    let res6 = await client.testSimple6("ok-6", restContentType = "text/html")
    check:
      res1 == "ok-1"
      res2 == "text/text,ok-2"
      res5 == "ok-5-redirect"
      res6 == "text/html,ok-6"

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

  asyncTest "Requests [path] arguments test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet, "/test/path/{smp1}") do (
      smp1: int) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      return RestApiResponse.response("ok:" & $smp1.get())

    router.api(MethodPost, "/test/path/{smp1}/{smp2}",) do (
      smp1: int, smp2: string,
      contentBody: Option[ContentBody]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      if smp2.isErr():
        return RestApiResponse.error(Http412, $smp2.error())
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response($smp1.get() & ":" & smp2.get() & ":" &
                                      obody)

    router.api(MethodGet, "/test/path/{smp1}/{smp2}/{smp3}") do (
      smp1: int, smp2: string, smp3: seq[byte]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      if smp2.isErr():
        return RestApiResponse.error(Http412, $smp2.error())
      if smp3.isErr():
        return RestApiResponse.error(Http413, $smp3.error())
      return RestApiResponse.response($smp1.get() & ":" & smp2.get() & ":" &
                                      bytesToString(smp3.get()))

    router.api(MethodPost, "/test/path/{smp1}/{smp2}/{smp3}") do (
      smp1: int, smp2: string, smp3: seq[byte],
      contentBody: Option[ContentBody]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      if smp2.isErr():
        return RestApiResponse.error(Http412, $smp2.error())
      if smp3.isErr():
        return RestApiResponse.error(Http413, $smp3.error())
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response($smp1.get() & ":" & smp2.get() & ":" &
                                      bytesToString(smp3.get()) & ":" & obody)

    router.api(MethodGet, "/test/path/redirect/{smp1}") do (
      smp1: int) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      let location = "/test/redirect/" & $smp1.get()
      return RestApiResponse.redirect(location = location)

    router.api(MethodGet, "/test/redirect/{smp1}") do (
      smp1: int) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      return RestApiResponse.response("ok-redirect-" & $smp1.get())

    router.api(MethodPost, "/test/path/redirect/{smp1}") do (
      smp1: int, contentBody: Option[ContentBody]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      let location = "/test/redirect/" & $smp1.get()
      return RestApiResponse.redirect(location = location)

    router.api(MethodPost, "/test/redirect/{smp1}") do (
      smp1: int, contentBody: Option[ContentBody]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response("ok-redirect-" & $smp1.get() & ":" &
                                      obody)

    var sres = RestServerRef.new(router, serverAddress)
    let server = sres.get()
    server.start()

    proc testPath1(smp1: int): string {.rest, endpoint: "/test/path/{smp1}".}
    proc testPath2(smp1: int, smp2: string, body: string): string {.
         rest, endpoint: "/test/path/{smp1}/{smp2}", meth: MethodPost.}
    proc testGetPath3(smp1: int, smp2: string, smp3: seq[byte]): string {.
         rest, endpoint: "/test/path/{smp1}/{smp2}/{smp3}".}
    proc testPostPath3(smp1: int, smp2: string, smp3: seq[byte],
                       body: string): string {.
         rest, endpoint: "/test/path/{smp1}/{smp2}/{smp3}", meth: MethodPost.}
    proc testGetRedirect(smp1: int): string {.
         rest, endpoint: "/test/redirect/{smp1}", meth: MethodGet.}
    proc testPostRedirect(smp1: int, body: string): string {.
         rest, endpoint: "/test/redirect/{smp1}", meth: MethodPost.}

    var client = RestClientRef.new(serverAddress, HttpClientScheme.NonSecure)

    let res1 = await client.testPath1(123456)
    let res2 = await client.testPath2(234567, "argstr1", "ok-2",
                                      restContentType = "text/text")
    let res3 = await client.testGetPath3(345678, "argstr2",
                                         stringToBytes("876543"))
    let res4 = await client.testPostPath3(456789, "argstr3",
                                          stringToBytes("987654"),
                                          "ok-post-4",
                                          restContentType = "text/html")
    let res5 = await client.testGetRedirect(567890)
    let res6 = await client.testPostRedirect(678901, "ok-post-6",
                                             restContentType = "text/text")
    let res7 = await client.testGetPath3(345678, "запрос",
                                         stringToBytes("876543"))

    check:
      res1 == "ok:123456"
      res2 == "234567:argstr1:text/text,ok-2"
      res3 == "345678:argstr2:876543"
      res4 == "456789:argstr3:987654:text/html,ok-post-4"
      res5 == "ok-redirect-567890"
      res6 == "ok-redirect-678901:text/text,ok-post-6"
      res7 == "345678:запрос:876543"

    await client.closeWait()
    await server.stop()
    await server.closeWait()

  asyncTest "Requests [query] arguments test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet, "/test/query/1") do (
      q1: Option[int]) -> RestApiResponse:
      let o1 =
        if q1.isSome():
          let res = q1.get()
          if res.isErr():
            return RestApiResponse.error(Http411, $res.error())
          $res.get()
        else:
          ""
      return RestApiResponse.response("ok-1:[" & o1 & "]")

    router.api(MethodGet, "/test/query/2") do (
      q1: seq[int]) -> RestApiResponse:
      let o1 =
        if q1.isErr():
          return RestApiResponse.error(Http411, $q1.error())
        else:
          q1.get().join(",")
      return RestApiResponse.response("ok-2:[" & o1 & "]")

    router.api(MethodPost, "/test/query/3",) do (
      q1: Option[int], q2: Option[string],
      contentBody: Option[ContentBody]) -> RestApiResponse:
      let o1 =
        if q1.isSome():
          let res = q1.get()
          if res.isErr():
            return RestApiResponse.error(Http411, $res.error())
          $res.get()
        else:
          ""
      let o2 =
        if q2.isSome():
          let res = q2.get()
          if res.isErr():
            return RestApiResponse.error(Http412, $res.error())
          res.get()
        else:
          ""
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response("ok-3:" &
                                      "[" & o1 & "]:" &
                                      "[" & o2 & "]:" & obody)

    router.api(MethodPost, "/test/query/4",) do (
      q1: seq[int], q2: seq[string],
      contentBody: Option[ContentBody]) -> RestApiResponse:
      let o1 =
        if q1.isErr():
          return RestApiResponse.error(Http411, $q1.error())
        else:
          q1.get.join(",")
      let o2 =
        if q2.isErr():
          return RestApiResponse.error(Http412, $q2.error())
        else:
          q2.get.join(",")
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response("ok-4:" &
                                      "[" & o1 & "]:" &
                                      "[" & o2 & "]:" & obody)

    router.api(MethodGet, "/test/query/5") do (
      q1: Option[int]) -> RestApiResponse:
        return RestApiResponse.redirect(location = "/test/query/redirect/5",
                                        preserveQuery = true)

    router.api(MethodGet, "/test/query/redirect/5") do (
      q1: Option[int]) -> RestApiResponse:
      let o1 =
        if q1.isSome():
          let res = q1.get()
          if res.isErr():
            return RestApiResponse.error(Http411, $res.error())
          $res.get()
        else:
          ""
      return RestApiResponse.response("ok-5:[" & o1 & "]")

    router.api(MethodGet, "/test/query/6") do (
      q1: seq[int]) -> RestApiResponse:
        return RestApiResponse.redirect(location = "/test/query/redirect/6",
                                        preserveQuery = true)

    router.api(MethodGet, "/test/query/redirect/6") do (
      q1: seq[int]) -> RestApiResponse:
      let o1 =
        if q1.isErr():
          return RestApiResponse.error(Http411, $q1.error())
        else:
          q1.get.join(",")
      return RestApiResponse.response("ok-6:[" & o1 & "]")

    router.api(MethodPost, "/test/query/7") do (
      q1: Option[int], contentBody: Option[ContentBody]) -> RestApiResponse:
        return RestApiResponse.redirect(location = "/test/query/redirect/7",
                                        preserveQuery = true)

    router.api(MethodPost, "/test/query/redirect/7",) do (
      q1: Option[int], contentBody: Option[ContentBody]) -> RestApiResponse:
      let o1 =
        if q1.isSome():
          let res = q1.get()
          if res.isErr():
            return RestApiResponse.error(Http411, $res.error())
          $res.get()
        else:
          ""
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response("ok-7:[" & o1 & "]:" & obody)

    router.api(MethodPost, "/test/query/8") do (
      q1: seq[int], contentBody: Option[ContentBody]) -> RestApiResponse:
        return RestApiResponse.redirect(location = "/test/query/redirect/8",
                                        preserveQuery = true)

    router.api(MethodPost, "/test/query/redirect/8",) do (
      q1: seq[int], contentBody: Option[ContentBody]) -> RestApiResponse:
      let o1 =
        if q1.isErr():
          return RestApiResponse.error(Http411, $q1.error())
        else:
          q1.get.join(",")
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response("ok-8:[" & o1 & "]:" & obody)

    var sres = RestServerRef.new(router, serverAddress)
    let server = sres.get()
    server.start()

    proc testQuery1(): string {.rest, endpoint: "/test/query/1".}
    proc testQuery1(q1: Option[int]): string {.rest, endpoint: "/test/query/1".}
    proc testQuery2(): string {.rest, endpoint: "/test/query/2".}
    proc testQuery2(q1: seq[int]): string {.rest, endpoint: "/test/query/2".}
    proc testQuery3(body: string): string {.
         rest, endpoint: "/test/query/3", meth: MethodPost.}
    proc testQuery3(q1: Option[int], q2: Option[string],
                    body: string): string {.
         rest, endpoint: "/test/query/3", meth: MethodPost.}
    proc testQuery4(body: string): string {.
         rest, endpoint: "/test/query/4", meth: MethodPost.}
    proc testQuery4(q1: seq[int], q2: seq[string], body: string): string {.
         rest, endpoint: "/test/query/4", meth: MethodPost.}
    proc testQueryGetRedirect(q1: Option[int]): string {.
         rest, endpoint: "/test/query/5", meth: MethodGet.}
    proc testQueryGetRedirect(q1: seq[int]): string {.
         rest, endpoint: "/test/query/6", meth: MethodGet.}
    proc testQueryPostRedirect(q1: Option[int], body: string): string {.
         rest, endpoint: "/test/query/7", meth: MethodPost.}
    proc testQueryPostRedirect(q1: seq[int], body: string): string {.
         rest, endpoint: "/test/query/8", meth: MethodPost.}

    var client = RestClientRef.new(serverAddress, HttpClientScheme.NonSecure)

    let res1 = await client.testQuery1()
    let res2 = await client.testQuery1(none[int]())
    let res3 = await client.testQuery1(some(123456))
    let res4 = await client.testQuery2()
    let res5 = await client.testQuery2(newSeq[int]())
    let res6 = await client.testQuery2(@[1,2,3,4,5,6])
    let res7 = await client.testQuery3("body3", restContentType = "text/text")
    let res8 = await client.testQuery3(none[int](), some("запрос"),
      "body4", restContentType = "text/text")
    let res9 = await client.testQuery3(some(234567), none[string](),
      "body5", restContentType = "text/text")
    let res10 = await client.testQuery3(some(345678), some("запрос"),
      "body6", restContentType = "text/text")
    let res11 = await client.testQuery4("body4", restContentType = "text/text")
    let res12 = await client.testQuery4(@[1, 2, 3], newSeq[string](),
      "body5", restContentType = "text/text")
    let res13 = await client.testQuery4(newSeq[int](),
      @["запрос1", "запрос2", "запрос3"],
      "body6", restContentType = "text/text")
    let res14 = await client.testQuery4(@[1, 2, 3],
      @["запрос1", "запрос2", "запрос3"],
      "body7", restContentType = "text/text")
    let res15 = await client.testQueryGetRedirect(none[int]())
    let res16 = await client.testQueryGetRedirect(some(123456))
    let res17 = await client.testQueryGetRedirect(newSeq[int]())
    let res18 = await client.testQueryGetRedirect(@[11, 22, 33, 44, 55])
    let res19 = await client.testQueryPostRedirect(none[int](),
      "bodyPost1", restContentType = "text/text")
    let res20 = await client.testQueryPostRedirect(some(123456),
      "bodyPost2", restContentType = "text/text")
    let res21 = await client.testQueryPostRedirect(newSeq[int](),
      "bodyPost3", restContentType = "text/text")
    let res22 = await client.testQueryPostRedirect(@[11, 22, 33, 44, 55],
      "bodyPost4", restContentType = "text/text")

    check:
      res1 == "ok-1:[]"
      res2 == "ok-1:[]"
      res3 == "ok-1:[123456]"
      res4 == "ok-2:[]"
      res5 == "ok-2:[]"
      res6 == "ok-2:[1,2,3,4,5,6]"
      res7 == "ok-3:[]:[]:text/text,body3"
      res8 == "ok-3:[]:[запрос]:text/text,body4"
      res9 == "ok-3:[234567]:[]:text/text,body5"
      res10 == "ok-3:[345678]:[запрос]:text/text,body6"
      res11 == "ok-4:[]:[]:text/text,body4"
      res12 == "ok-4:[1,2,3]:[]:text/text,body5"
      res13 == "ok-4:[]:[запрос1,запрос2,запрос3]:text/text,body6"
      res14 == "ok-4:[1,2,3]:[запрос1,запрос2,запрос3]:text/text,body7"
      res15 == "ok-5:[]"
      res16 == "ok-5:[123456]"
      res17 == "ok-6:[]"
      res18 == "ok-6:[11,22,33,44,55]"
      res19 == "ok-7:[]:text/text,bodyPost1"
      res20 == "ok-7:[123456]:text/text,bodyPost2"
      res21 == "ok-8:[]:text/text,bodyPost3"
      res22 == "ok-8:[11,22,33,44,55]:text/text,bodyPost4"

    await client.closeWait()
    await server.stop()
    await server.closeWait()

  asyncTest "Requests [path + query] arguments test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet, "/test/1/full/{smp1}") do (
      smp1: int, q1: seq[int]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      let o1 =
        if q1.isErr():
          return RestApiResponse.error(Http412, $q1.error())
        else:
          q1.get.join(",")
      return RestApiResponse.response("ok-1:" & $smp1.get() & ":[" & o1 & "]")

    router.api(MethodPost, "/test/2/full/{smp1}/{smp2}") do (
      smp1: int, smp2: string, q1: seq[int], q2: seq[string],
      contentBody: Option[ContentBody]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      if smp2.isErr():
        return RestApiResponse.error(Http412, $smp2.error())
      let o1 =
        if q1.isErr():
          return RestApiResponse.error(Http413, $q1.error())
        else:
          q1.get.join(",")
      let o2 =
        if q2.isErr():
          return RestApiResponse.error(Http414, $q2.error())
        else:
          q2.get.join(",")
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response("ok-2:" &
        $smp1.get() & ":" & smp2.get() & ":[" & o1 & "]:[" & o2 & "]:" & obody)

    router.api(MethodGet, "/test/3/full/{smp1}/{smp2}/{smp3}") do (
      smp1: int, smp2: string, smp3: seq[byte],
      q1: seq[int], q2: seq[string], q3: Option[seq[byte]]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      if smp2.isErr():
        return RestApiResponse.error(Http412, $smp2.error())
      if smp3.isErr():
        return RestApiResponse.error(Http413, $smp3.error())
      let o1 =
        if q1.isErr():
          return RestApiResponse.error(Http413, $q1.error())
        else:
          q1.get.join(",")
      let o2 =
        if q2.isErr():
          return RestApiResponse.error(Http414, $q2.error())
        else:
          q2.get.join(",")
      let o3 =
        if q3.isSome():
          let res = q3.get()
          if res.isErr():
            return RestApiResponse.error(Http412, $res.error())
          bytesToString(res.get())
        else:
          ""
      return RestApiResponse.response("ok-3:" &
        $smp1.get() & ":" & smp2.get() & ":" & bytesToString(smp3.get()) &
        ":[" & o1 & "]:[" & o2 & "]:[" & o3 & "]")

    router.api(MethodPost, "/test/3/full/{smp1}/{smp2}/{smp3}") do (
      smp1: int, smp2: string, smp3: seq[byte],
      q1: seq[int], q2: seq[string], q3: Option[seq[byte]],
      contentBody: Option[ContentBody]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      if smp2.isErr():
        return RestApiResponse.error(Http412, $smp2.error())
      if smp3.isErr():
        return RestApiResponse.error(Http413, $smp3.error())
      let o1 =
        if q1.isErr():
          return RestApiResponse.error(Http413, $q1.error())
        else:
          q1.get.join(",")
      let o2 =
        if q2.isErr():
          return RestApiResponse.error(Http414, $q2.error())
        else:
          q2.get.join(",")
      let o3 =
        if q3.isSome():
          let res = q3.get()
          if res.isErr():
            return RestApiResponse.error(Http412, $res.error())
          bytesToString(res.get())
        else:
          ""
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response("ok-3:" &
        $smp1.get() & ":" & smp2.get() & ":" & bytesToString(smp3.get()) &
        ":[" & o1 & "]:[" & o2 & "]:[" & o3 & "]:" & obody)

    router.api(MethodGet, "/test/4/full/redirect/{smp1}") do (
      smp1: int, q1: seq[int]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      let location = "/test/redirect/" & $smp1.get()
      return RestApiResponse.redirect(location = location, preserveQuery = true)

    router.api(MethodGet, "/test/redirect/{smp1}") do (
      smp1: int, q1: seq[int]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      let o1 =
        if q1.isErr():
          return RestApiResponse.error(Http413, $q1.error())
        else:
          q1.get.join(",")
      return RestApiResponse.response(
        "ok-redirect-" & $smp1.get() & ":[" & o1 & "]")

    router.api(MethodPost, "/test/5/full/redirect/{smp1}") do (
      smp1: int, q1: seq[int],
      contentBody: Option[ContentBody]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      let location = "/test/redirect/" & $smp1.get()
      return RestApiResponse.redirect(location = location, preserveQuery = true)

    router.api(MethodPost, "/test/redirect/{smp1}") do (
      smp1: int, q1: seq[int],
      contentBody: Option[ContentBody]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      let o1 =
        if q1.isErr():
          return RestApiResponse.error(Http413, $q1.error())
        else:
          q1.get.join(",")
      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"
      return RestApiResponse.response(
        "ok-redirect-" & $smp1.get() & ":[" & o1 & "]:" & obody)

    var sres = RestServerRef.new(router, serverAddress)
    let server = sres.get()
    server.start()

    proc testFull1(smp1: int): string {.
         rest, endpoint: "/test/1/full/{smp1}".}
    proc testFull1(smp1: int, q1: seq[int]): string {.
         rest, endpoint: "/test/1/full/{smp1}".}
    proc testFull2(smp1: int, smp2: string, body: string): string {.
         rest, endpoint: "/test/2/full/{smp1}/{smp2}", meth: MethodPost.}
    proc testFull2(smp1: int, smp2: string, q1: seq[int],
                   body: string): string {.
         rest, endpoint: "/test/2/full/{smp1}/{smp2}", meth: MethodPost.}
    proc testFull2(smp1: int, smp2: string, q2: seq[string],
                   body: string): string {.
         rest, endpoint: "/test/2/full/{smp1}/{smp2}", meth: MethodPost.}
    proc testFull2(smp1: int, smp2: string, q1: seq[int], q2: seq[string],
                   body: string): string {.
         rest, endpoint: "/test/2/full/{smp1}/{smp2}", meth: MethodPost.}
    proc testFull3Get(smp1: int, smp2: string, smp3: seq[byte]): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodGet.}
    proc testFull3Get(smp1: int, smp2: string, smp3: seq[byte],
                      q1: seq[int]): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodGet.}
    proc testFull3Get(smp1: int, smp2: string, smp3: seq[byte],
                      q2: seq[string]): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodGet.}
    proc testFull3Get(smp1: int, smp2: string, smp3: seq[byte],
                      q3: Option[seq[byte]]): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodGet.}
    proc testFull3Get(smp1: int, smp2: string, smp3: seq[byte],
                      q1: seq[int], q3: Option[seq[byte]]): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodGet.}
    proc testFull3Get(smp1: int, smp2: string, smp3: seq[byte],
                      q1: seq[int], q2: seq[string],
                      q3: Option[seq[byte]]): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodGet.}
    proc testFull3Post(smp1: int, smp2: string, smp3: seq[byte],
                       body: string): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodPost.}
    proc testFull3Post(smp1: int, smp2: string, smp3: seq[byte],
                       q1: seq[int], body: string): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodPost.}
    proc testFull3Post(smp1: int, smp2: string, smp3: seq[byte],
                       q2: seq[string], body: string): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodPost.}
    proc testFull3Post(smp1: int, smp2: string, smp3: seq[byte],
                       q3: Option[seq[byte]], body: string): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodPost.}
    proc testFull3Post(smp1: int, smp2: string, smp3: seq[byte],
                       q1: seq[int], q3: Option[seq[byte]],
                       body: string): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodPost.}
    proc testFull3Post(smp1: int, smp2: string, smp3: seq[byte],
                       q1: seq[int], q2: seq[string],
                       q3: Option[seq[byte]], body: string): string {.
         rest, endpoint: "/test/3/full/{smp1}/{smp2}/{smp3}", meth: MethodPost.}
    proc testFull4Redirect(smp1: int): string {.
         rest, endpoint: "/test/4/full/redirect/{smp1}", meth: MethodGet.}
    proc testFull4Redirect(smp1: int, q1: seq[int]): string {.
         rest, endpoint: "/test/4/full/redirect/{smp1}", meth: MethodGet.}
    proc testFull5Redirect(smp1: int, body: string): string {.
         rest, endpoint: "/test/5/full/redirect/{smp1}", meth: MethodPost.}
    proc testFull5Redirect(smp1: int, q1: seq[int], body: string): string {.
         rest, endpoint: "/test/5/full/redirect/{smp1}", meth: MethodPost.}

    var client = RestClientRef.new(serverAddress, HttpClientScheme.NonSecure)

    let res1 = await client.testFull1(123)
    let res2 = await client.testFull1(124, newSeq[int]())
    let res3 = await client.testFull1(125, @[16, 32, 64, 128, 256, 512, 1024])
    let res4 = await client.testFull2(126, "textarg1", "bodydata1",
                                      restContentType = "text/text")
    let res5 = await client.testFull2(127, "textarg2", newSeq[int](),
                                      "bodydata2",
                                      restContentType = "text/text")
    let res6 = await client.testFull2(128, "textarg3",
                                      @[16, 32, 64, 128, 256],
                                      "bodydata3",
                                      restContentType = "text/text")
    let res7 = await client.testFull2(129, "textarg4", newSeq[string](),
                                      "bodydata4",
                                      restContentType = "text/text")
    let res8 = await client.testFull2(130, "textarg5",
                                      @["запрос1", "запрос2", "запрос3"],
                                      "bodydata5",
                                      restContentType = "text/text")
    let res9 = await client.testFull2(131, "textarg6", newSeq[int](),
                                      newSeq[string](),
                                      "bodydata6",
                                      restContentType = "text/text")
    let res10 = await client.testFull2(132, "textarg7",
                                       @[16, 32, 64, 128, 256],
                                       @["запрос1", "запрос2", "запрос3"],
                                       "bodydata7",
                                       restContentType = "text/text")
    let res11 = await client.testFull3Get(133, "textarg1",
                                          stringToBytes("133"))
    let res12 = await client.testFull3Get(134, "textarg2",
                                          stringToBytes("134"), newSeq[int]())
    let res13 = await client.testFull3Get(135, "textarg3",
                                          stringToBytes("135"),
                                          @[16, 32, 64, 128, 256])
    let res14 = await client.testFull3Get(136, "textarg4",
                                          stringToBytes("136"),
                                          newSeq[string]())
    let res15 = await client.testFull3Get(137, "textarg5",
                                          stringToBytes("137"),
                                          @["запрос1", "запрос2", "запрос3"])
    let res16 = await client.testFull3Get(138, "textarg6",
                                          stringToBytes("138"),
                                          none[seq[byte]]())
    let res17 = await client.testFull3Get(139, "textarg7",
                                          stringToBytes("139"),
                                          some(stringToBytes("byteArg1")))
    let res18 = await client.testFull3Get(140, "textarg8",
                                          stringToBytes("140"),
                                          newSeq[int](),
                                          none[seq[byte]]())
    let res19 = await client.testFull3Get(141, "textarg9",
                                          stringToBytes("141"),
                                          @[16, 32, 64, 128, 256],
                                          none[seq[byte]]())
    let res20 = await client.testFull3Get(142, "textarg10",
                                          stringToBytes("142"),
                                          newSeq[int](),
                                          some(stringToBytes("byteArg2")))
    let res21 = await client.testFull3Get(143, "textarg11",
                                          stringToBytes("143"),
                                          @[16, 32, 64, 128, 256],
                                          some(stringToBytes("byteArg3")))
    let res22 = await client.testFull3Get(144, "textarg12",
                                          stringToBytes("144"),
                                          newSeq[int](),
                                          newSeq[string](),
                                          none[seq[byte]]())
    let res23 = await client.testFull3Get(145, "textarg13",
                                          stringToBytes("145"),
                                          @[16, 32, 64, 128, 256],
                                          @["запрос1", "запрос2", "запрос3"],
                                          some(stringToBytes("byteArg4")))
    let res24 = await client.testFull3Post(146, "textarg1",
                                          stringToBytes("146"),
                                          "bodyArg1",
                                          restContentType = "text/text1")
    let res25 = await client.testFull3Post(147, "textarg2",
                                          stringToBytes("147"), newSeq[int](),
                                          "bodyArg2",
                                          restContentType = "text/text2")
    let res26 = await client.testFull3Post(148, "textarg3",
                                          stringToBytes("148"),
                                          @[16, 32, 64, 128, 256],
                                          "bodyArg3",
                                          restContentType = "text/text3")
    let res27 = await client.testFull3Post(149, "textarg4",
                                          stringToBytes("149"),
                                          newSeq[string](),
                                          "bodyArg4",
                                          restContentType = "text/text4")
    let res28 = await client.testFull3Post(150, "textarg5",
                                          stringToBytes("150"),
                                          @["запрос1", "запрос2", "запрос3"],
                                          "bodyArg5",
                                          restContentType = "text/text5")
    let res29 = await client.testFull3Post(151, "textarg6",
                                          stringToBytes("151"),
                                          none[seq[byte]](),
                                          "bodyArg6",
                                          restContentType = "text/text6")
    let res30 = await client.testFull3Post(152, "textarg7",
                                          stringToBytes("152"),
                                          some(stringToBytes("byteArg1")),
                                          "bodyArg7",
                                          restContentType = "text/text7")
    let res31 = await client.testFull3Post(153, "textarg8",
                                          stringToBytes("153"),
                                          newSeq[int](),
                                          none[seq[byte]](),
                                          "bodyArg8",
                                          restContentType = "text/text8")
    let res32 = await client.testFull3Post(154, "textarg9",
                                          stringToBytes("154"),
                                          @[16, 32, 64, 128, 256],
                                          none[seq[byte]](),
                                          "bodyArg9",
                                          restContentType = "text/text9")
    let res33 = await client.testFull3Post(155, "textarg10",
                                          stringToBytes("155"),
                                          newSeq[int](),
                                          some(stringToBytes("byteArg2")),
                                          "bodyArg10",
                                          restContentType = "text/text10")
    let res34 = await client.testFull3Post(156, "textarg11",
                                          stringToBytes("156"),
                                          @[16, 32, 64, 128, 256],
                                          some(stringToBytes("byteArg3")),
                                          "bodyArg11",
                                          restContentType = "text/text11")
    let res35 = await client.testFull3Post(157, "textarg12",
                                          stringToBytes("157"),
                                          newSeq[int](),
                                          newSeq[string](),
                                          none[seq[byte]](),
                                          "bodyArg12",
                                          restContentType = "text/text12")
    let res36 = await client.testFull3Post(158, "textarg13",
                                          stringToBytes("158"),
                                          @[16, 32, 64, 128, 256],
                                          @["запрос1", "запрос2", "запрос3"],
                                          some(stringToBytes("byteArg4")),
                                          "bodyArg13",
                                          restContentType = "text/text13")
    let res37 = await client.testFull4Redirect(159)
    let res38 = await client.testFull4Redirect(160, newSeq[int]())
    let res39 = await client.testFull4Redirect(161, @[16, 32, 64, 128, 256])
    let res40 = await client.testFull5Redirect(162, "bodyArg14",
                                               restContentType = "text/text")
    let res41 = await client.testFull5Redirect(163, newSeq[int](), "bodyArg15",
                                               restContentType = "text/text")
    let res42 = await client.testFull5Redirect(164, @[256, 512, 1024, 2048],
                                               "bodyArg16",
                                               restContentType = "text/text")

    check:
      res1 == "ok-1:123:[]"
      res2 == "ok-1:124:[]"
      res3 == "ok-1:125:[16,32,64,128,256,512,1024]"
      res4 == "ok-2:126:textarg1:[]:[]:text/text,bodydata1"
      res5 == "ok-2:127:textarg2:[]:[]:text/text,bodydata2"
      res6 == "ok-2:128:textarg3:[16,32,64,128,256]:[]:text/text,bodydata3"
      res7 == "ok-2:129:textarg4:[]:[]:text/text,bodydata4"
      res8 == "ok-2:130:textarg5:[]:[запрос1,запрос2,запрос3]:text/text," &
              "bodydata5"
      res9 == "ok-2:131:textarg6:[]:[]:text/text,bodydata6"
      res10 == "ok-2:132:textarg7:[16,32,64,128,256]:[запрос1,запрос2," &
               "запрос3]:text/text,bodydata7"
      res11 == "ok-3:133:textarg1:133:[]:[]:[]"
      res12 == "ok-3:134:textarg2:134:[]:[]:[]"
      res13 == "ok-3:135:textarg3:135:[16,32,64,128,256]:[]:[]"
      res14 == "ok-3:136:textarg4:136:[]:[]:[]"
      res15 == "ok-3:137:textarg5:137:[]:[запрос1,запрос2,запрос3]:[]"
      res16 == "ok-3:138:textarg6:138:[]:[]:[]"
      res17 == "ok-3:139:textarg7:139:[]:[]:[byteArg1]"
      res18 == "ok-3:140:textarg8:140:[]:[]:[]"
      res19 == "ok-3:141:textarg9:141:[16,32,64,128,256]:[]:[]"
      res20 == "ok-3:142:textarg10:142:[]:[]:[byteArg2]"
      res21 == "ok-3:143:textarg11:143:[16,32,64,128,256]:[]:[byteArg3]"
      res22 == "ok-3:144:textarg12:144:[]:[]:[]"
      res23 == "ok-3:145:textarg13:145:[16,32,64,128,256]:[запрос1,запрос2," &
               "запрос3]:[byteArg4]"
      res24 == "ok-3:146:textarg1:146:[]:[]:[]:text/text1,bodyArg1"
      res25 == "ok-3:147:textarg2:147:[]:[]:[]:text/text2,bodyArg2"
      res26 == "ok-3:148:textarg3:148:[16,32,64,128,256]:[]:[]:text/text3," &
               "bodyArg3"
      res27 == "ok-3:149:textarg4:149:[]:[]:[]:text/text4,bodyArg4"
      res28 == "ok-3:150:textarg5:150:[]:[запрос1,запрос2,запрос3]:[]:" &
               "text/text5,bodyArg5"
      res29 == "ok-3:151:textarg6:151:[]:[]:[]:text/text6,bodyArg6"
      res30 == "ok-3:152:textarg7:152:[]:[]:[byteArg1]:text/text7,bodyArg7"
      res31 == "ok-3:153:textarg8:153:[]:[]:[]:text/text8,bodyArg8"
      res32 == "ok-3:154:textarg9:154:[16,32,64,128,256]:[]:[]:text/text9," &
               "bodyArg9"
      res33 == "ok-3:155:textarg10:155:[]:[]:[byteArg2]:text/text10,bodyArg10"
      res34 == "ok-3:156:textarg11:156:[16,32,64,128,256]:[]:[byteArg3]:" &
               "text/text11,bodyArg11"
      res35 == "ok-3:157:textarg12:157:[]:[]:[]:text/text12,bodyArg12"
      res36 == "ok-3:158:textarg13:158:[16,32,64,128,256]:[запрос1,запрос2," &
               "запрос3]:[byteArg4]:text/text13,bodyArg13"
      res37 == "ok-redirect-159:[]"
      res38 == "ok-redirect-160:[]"
      res39 == "ok-redirect-161:[16,32,64,128,256]"
      res40 == "ok-redirect-162:[]:text/text,bodyArg14"
      res41 == "ok-redirect-163:[]:text/text,bodyArg15"
      res42 == "ok-redirect-164:[256,512,1024,2048]:text/text,bodyArg16"

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
