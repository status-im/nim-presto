import std/[unittest, strutils, parseutils, typetraits]
import helpers
import chronos, chronos/apps
import stew/byteutils
import ../presto/route, ../presto/segpath

when defined(nimHasUsed): {.used.}

proc sendMockRequest(router: RestRouter, meth: HttpMethod, url: string,
                     body: Option[ContentBody]): RestApiResponse =
  var uri = parseUri(url)
  var req = HttpRequestRef(meth: meth, version: HttpVersion11)
  let spath =
    if uri.path.startsWith("/"):
      SegmentedPath.init($meth & uri.path).get()
    else:
      SegmentedPath.init($meth & "/" & uri.path).get()
  let queryTable =
    block:
      var res = HttpTable.init()
      for key, value in queryParams(uri.query):
        res.add(key, value)
      res
  let route = router.getRoute(spath).get()
  let paramsTable = route.getParamsTable()
  return waitFor(route.callback(req, paramsTable, queryTable, body))

proc sendMockRequest(router: RestRouter, meth: HttpMethod,
                     url: string): RestApiResponse =
  sendMockRequest(router, meth, url, none[ContentBody]())

proc sendMockRequest(router: RestRouter, meth: HttpMethod,
                     url: string, data: string): RestApiResponse =
  let contentBody = ContentBody.init(
    MediaType.init("text/plain"), stringToBytes(data))
  sendMockRequest(router, meth, url, some[ContentBody](contentBody))

suite "REST API router & macro tests":
  test "No parameters test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet, "/test/empty/1") do (
      ) -> RestApiResponse:
      return RestApiResponse.response("ok-1", contentType = "test/test")
    router.api(MethodGet, "/test/empty/p1/2") do (
      resp: HttpResponseRef) -> RestApiResponse:
      # To avoid warning about unused `resp`
      let testResp {.used.} = resp
      return RestApiResponse.response("ok-2", contentType = "test/test")
    router.api(MethodPost, "/test/empty/p1/p2/3") do (
      contentBody: Option[ContentBody]) -> RestApiResponse:
      if contentBody.isSome():
        return RestApiResponse.response("ok-3", contentType = "test/test")
    router.api(MethodGet, "/test/empty/p1/p2/p3/4") do (
      resp: HttpResponseRef,
      contentBody: Option[ContentBody]) -> RestApiResponse:
      # To avoid warning about unused `resp`
      let testResp {.used.} = resp
      if contentBody.isSome():
        return RestApiResponse.response("ok-4", contentType = "test/test")

    let r1 = router.sendMockRequest(MethodGet,
                                    "http://l.to/test/empty/1")
    let r2 = router.sendMockRequest(MethodGet,
                                    "http://l.to/test/empty/p1/2")
    let r3 = router.sendMockRequest(MethodPost,
                                    "http://l.to/test/empty/p1/p2/3",
                                    "this is content body")
    let r4 = router.sendMockRequest(MethodGet,
                                    "http://l.to/test/empty/p1/p2/p3/4",
                                    "this is content body")
    check:
      r1.kind == RestApiResponseKind.Content
      r2.kind == RestApiResponseKind.Content
      r3.kind == RestApiResponseKind.Content
      r4.kind == RestApiResponseKind.Content
      bytesToString(r1.content.data) == "ok-1"
      bytesToString(r2.content.data) == "ok-2"
      bytesToString(r3.content.data) == "ok-3"
      bytesToString(r4.content.data) == "ok-4"

  test "Reserved keywords as parameters test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet,
               "/test/keyword_args/1/{let}") do (
      `let`: int) -> RestApiResponse:
        let l = `let`.get()
        if (l == 999999):
          return RestApiResponse.response("ok-1", contentType = "test/test")

    router.api(MethodGet,
               "/test/keyword_args/2/{let}") do (
      `let`: int,
      `var`, `block`, `addr`, `custom`: Option[int]) -> RestApiResponse:
        let l = `let`.get()
        let v = `var`.get().get()
        let b = `block`.get().get()
        let a = `addr`.get().get()
        let c = custom.get().get()
        if (l == 888888) and (v == 777777) and (b == 666666) and
           (a == 555555) and (c == 444444):
          return RestApiResponse.response("ok-2", contentType = "test/test")

    let r1 = router.sendMockRequest(MethodGet,
      "http://l.to/test/keyword_args/1/999999")
    let r2 = router.sendMockRequest(MethodGet,
      "http://l.to/test/keyword_args/2/888888" &
      "?var=777777&block=666666&addr=555555&custom=444444")
    check:
      r1.kind == RestApiResponseKind.Content
      bytesToString(r1.content.data) == "ok-1"
      r2.kind == RestApiResponseKind.Content
      bytesToString(r2.content.data) == "ok-2"

  test "Basic types as parameters test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet,
               "/test/basic_args/1/{smp1}/{smp2}/{smp3}") do (
      smp1: int, smp2: string, smp3: seq[byte]) -> RestApiResponse:
        let s1 = smp1.get()
        let s2 = smp2.get()
        let s3 = smp3.get()
        if (s1 == 999999) and (s2 == "test1") and
           (bytesToString(s3) == "test1"):
          return RestApiResponse.response("ok-1", contentType = "test/test")

    router.api(MethodGet,
               "/test/basic_args/2/{smp1}/{smp2}/{smp3}") do (
      smp1: int, smp2: string, smp3: seq[byte],
      opt1: Option[int], opt2: Option[string],
      opt3: Option[seq[byte]]) -> RestApiResponse:
        let s1 = smp1.get()
        let s2 = smp2.get()
        let s3 = smp3.get()
        let o1 = opt1.get().get()
        let o2 = opt2.get().get()
        let o3 = opt3.get().get()
        if (s1 == 888888) and (s2 == "test2") and
           (bytesToString(s3) == "test2") and
           (o1 == 777777) and (o2 == "testopt2") and
           (bytesToString(o3) == "test2"):
          return RestApiResponse.response("ok-2", contentType = "test/test")

    let r1 = router.sendMockRequest(MethodGet,
      "http://l.to/test/basic_args/1/999999/test1/0x7465737431")
    let r2 = router.sendMockRequest(MethodGet,
      "http://l.to/test/basic_args/2/888888/test2/0x7465737432" &
      "?opt1=777777&opt2=testopt2&opt3=0x7465737432")
    check:
      r1.kind == RestApiResponseKind.Content
      bytesToString(r1.content.data) == "ok-1"
      r2.kind == RestApiResponseKind.Content
      bytesToString(r2.content.data) == "ok-2"

  test "Routes installation from generic proc":
    proc addGenericRoute(router: var RestRouter, T: type) =
      const typeName = typetraits.name(T)
      router.api(MethodGet, "/test/" & typeName) do () -> RestApiResponse:
        return RestApiResponse.response(typeName, contentType = "text/plain")

    var router = RestRouter.init(testValidate)
    router.addGenericRoute(string)
    router.addGenericRoute(int)

    let r1 = router.sendMockRequest(MethodGet, "http://l.to/test/string")
    let r2 = router.sendMockRequest(MethodGet, "http://l.to/test/int")
    
    check:
      r1.kind == RestApiResponseKind.Content
      r2.kind == RestApiResponseKind.Content
      bytesToString(r1.content.data) == "string"
      bytesToString(r2.content.data) == "int"

  test "Custom types as parameters test":
    var router = RestRouter.init(testValidate)
    router.api(MethodPost,
               "/test/custom_args/1/{pat1}/{pat2}/{pat3}") do (
      pat1: CustomType1, pat2: CustomType1,
      pat3: CustomType1, body: Option[ContentBody]) -> RestApiResponse:
        let p1 = pat1.get()
        let p2 = pat2.get()
        let p3 = pat3.get()
        let cbody = body.get()
        if (p1.level1 == 123456) and (p2.level2 == "123456") and
           (bytesToString(p3.level3) == "123456") and
           (bytesToString(cbody.data) == "123456"):
          return RestApiResponse.response("ok-1", contentType = "test/test")

    router.api(MethodPost,
               "/test/custom_args/2/{pat1}/{pat2}/{pat3}") do (
      pat1: CustomType1, pat2: CustomType1, pat3: CustomType1,
      opt1: Option[CustomType1], opt2: Option[CustomType1],
      opt3: Option[CustomType1],
      body: Option[ContentBody]) -> RestApiResponse:
        let p1 = pat1.get()
        let p2 = pat2.get()
        let p3 = pat3.get()
        let o1 = opt1.get().get()
        let o2 = opt2.get().get()
        let o3 = opt3.get().get()
        let cbody = body.get()
        if (p1.level1 == 765432) and (p2.level2 == "765432") and
           (bytesToString(p3.level3) == "765432") and
           (o1.level1 == 234567) and (o2.level2 == "234567") and
           (bytesToString(o3.level3) == "234567") and
           (bytesToString(cbody.data) == "234567"):
          return RestApiResponse.response("ok-2", contentType = "test/test")

    router.api(MethodPost,
               "/test/custom_args/3/{smp1}/{smp2}/{smp3}") do (
      smp1: GenericType[int], smp2: GenericType[string],
      smp3: GenericType[seq[byte]],
      opt1: Option[GenericType[int]], opt2: Option[GenericType[string]],
      opt3: Option[GenericType[seq[byte]]],
      body: Option[ContentBody]) -> RestApiResponse:

      let p1 = smp1.get()
      let p2 = smp2.get()
      let p3 = smp3.get()
      let o1 = opt1.get().get()
      let o2 = opt2.get().get()
      let o3 = opt3.get().get()
      let cbody = body.get()

      if (p1.data == 765432) and (p2.data == "765432") and
         (bytesToString(p3.data) == "765432") and
         (o1.data == 234567) and (o2.data == "234567") and
         (bytesToString(o3.data) == "234567") and
         (bytesToString(cbody.data) == "234567"):
        return RestApiResponse.response("ok-3", contentType = "test/test")

    let r1 = router.sendMockRequest(MethodPost,
      "http://l.to/test/custom_args/1/p1_123456/p2_123456/p3_0x313233343536",
      "123456")
    let r2 = router.sendMockRequest(MethodPost,
      "http://l.to/test/custom_args/2/p1_765432/p2_765432/p3_0x373635343332" &
      "?opt1=p1_234567&opt2=p2_234567&opt3=p3_0x323334353637", "234567")
    let r3 = router.sendMockRequest(MethodPost,
      "http://l.to/test/custom_args/3/765432/765432/0x373635343332" &
      "?opt1=234567&opt2=234567&opt3=0x323334353637", "234567")
    check:
      r1.kind == RestApiResponseKind.Content
      bytesToString(r1.content.data) == "ok-1"
      r2.kind == RestApiResponseKind.Content
      bytesToString(r2.content.data) == "ok-2"
      r3.kind == RestApiResponseKind.Content
      bytesToString(r3.content.data) == "ok-3"

  test "seq[basic] types parameters test":
    var router = RestRouter.init(testValidate)
    router.api(MethodPost, "/test/basic_seq/1") do (
      opt1: seq[int], opt2: seq[string],
      opt3: seq[seq[byte]], opt4: seq[int],
      body: Option[ContentBody]) -> RestApiResponse:
      let o1 = opt1.get()
      let o2 = opt2.get()
      let o3 = opt3.get()
      let o4 = opt4.get()
      let cbody = body.get()
      if (o1 == @[1, 2, 3]) and (o2 == @["test1", "test2", "test3"]) and
         (o3 == @[@[0x31'u8, 0x30'u8], @[0x32'u8, 0x30'u8],
                @[0x33'u8, 0x30'u8]]) and (len(o4) == 0) and
         (bytesToString(cbody.data) == "123456"):
        return RestApiResponse.response("ok-1", contentType = "test/test")

    router.api(MethodPost, "/test/basic_seq/1/{smp3}") do (
      opt1: seq[int], opt2: seq[string], opt3: seq[seq[byte]], opt4: seq[int],
      smp3: seq[byte], body: Option[ContentBody]) -> RestApiResponse:
        let p1 = smp3.get()
        let o1 = opt1.get()
        let o2 = opt2.get()
        let o3 = opt3.get()
        let o4 = opt4.get()
        let cbody = body.get()
        if (bytesToString(p1) == "123456") and
           (bytesToString(cbody.data) == "654321") and
           (o1 == @[1, 2, 3, 4, 5]) and
           (o2 == @["test1", "test2", "test3", "test4", "test5"]) and
           (o3 == @[@[0x30'u8], @[0x31'u8], @[0x32'u8],
                    @[0x33'u8], @[0x34'u8]]) and
           (len(o4) == 0):
          return RestApiResponse.response("ok-2", contentType = "test/test")

    let r1 = router.sendMockRequest(MethodPost,
      "http://l.to/test/basic_seq/1?opt1=1&opt2=test1&opt3=0x3130" &
      "&opt1=2&opt2=test2&opt3=0x3230&opt1=3&opt2=test3&opt3=0x3330", "123456")

    let r2 = router.sendMockRequest(MethodPost,
      "http://l.to/test/basic_seq/1/0x313233343536" &
      "?opt1=1&opt2=test1&opt3=0x30&opt1=2&opt2=test2&opt3=0x31" &
      "&opt1=3&opt2=test3&opt3=0x32&opt1=4&opt2=test4&opt3=0x33" &
      "&opt1=5&opt2=test5&opt3=0x34", "654321")
    check:
      r1.kind == RestApiResponseKind.Content
      bytesToString(r1.content.data) == "ok-1"
      r2.kind == RestApiResponseKind.Content
      bytesToString(r2.content.data) == "ok-2"

  test "seq[custom] types parameters test":
    var router = RestRouter.init(testValidate)
    router.api(MethodPost, "/test/custom_seq/1") do (
      opt1: seq[CustomType1], opt2: seq[CustomType1],
      opt3: seq[CustomType1], opt4: seq[CustomType1],
      body: Option[ContentBody]) -> RestApiResponse:

      let o1 = opt1.get()
      let o2 = opt2.get()
      let o3 = opt3.get()
      let o4 = opt4.get()
      let cbody = body.get()

      let cto1 = @[
        CustomType1(kind: Level1, level1: 1),
        CustomType1(kind: Level1, level1: 2),
        CustomType1(kind: Level1, level1: 3)
      ]
      let cto2 = @[
        CustomType1(kind: Level2, level2: "test1"),
        CustomType1(kind: Level2, level2: "test2"),
        CustomType1(kind: Level2, level2: "test3")
      ]
      let cto3 = @[
        CustomType1(kind: Level3, level3: @[0x30'u8, 0x31'u8, 0x32'u8]),
        CustomType1(kind: Level3, level3: @[0x33'u8, 0x34'u8, 0x35'u8]),
        CustomType1(kind: Level3, level3: @[0x36'u8, 0x37'u8, 0x38'u8])
      ]
      if (o1 == cto1) and (o2 == cto2) and (o3 == cto3) and (len(o4) == 0) and
         (bytesToString(cbody.data) == "123456"):
        return RestApiResponse.response("ok-1", contentType = "test/test")

    router.api(MethodPost, "/test/custom_seq/2") do (
      opt1: seq[GenericType[int]], opt2: seq[GenericType[string]],
      opt3: seq[GenericType[seq[byte]]], opt4: seq[GenericType[int]],
      body: Option[ContentBody]) -> RestApiResponse:

      let o1 = opt1.get()
      let o2 = opt2.get()
      let o3 = opt3.get()
      let o4 = opt4.get()
      let cbody = body.get()

      let cto1 = @[
        GenericType[int](data: 1),
        GenericType[int](data: 2),
        GenericType[int](data: 3)
      ]
      let cto2 = @[
        GenericType[string](data: "test1"),
        GenericType[string](data: "test2"),
        GenericType[string](data: "test3")
      ]
      let cto3 = @[
        GenericType[seq[byte]](data: @[0x39'u8, 0x38'u8, 0x37'u8]),
        GenericType[seq[byte]](data: @[0x36'u8, 0x35'u8, 0x34'u8]),
        GenericType[seq[byte]](data: @[0x33'u8, 0x32'u8, 0x31'u8]),
      ]
      if (o1 == cto1) and (o2 == cto2) and (o3 == cto3) and (len(o4) == 0) and
         (bytesToString(cbody.data) == "654321"):
        return RestApiResponse.response("ok-2", contentType = "test/test")

    let r1 = router.sendMockRequest(MethodPost,
      "http://l.to/test/custom_seq/1?opt1=p1_1&opt2=p2_test1&opt3=p3_0x303132" &
      "&opt1=p1_2&opt2=p2_test2&opt3=p3_0x333435" &
      "&opt1=p1_3&opt2=p2_test3&opt3=p3_0x363738", "123456")

    let r2 = router.sendMockRequest(MethodPost,
      "http://l.to/test/custom_seq/2?opt1=1&opt2=test1&opt3=0x393837" &
      "&opt1=2&opt2=test2&opt3=0x363534&opt1=3&opt2=test3&opt3=0x333231",
      "654321")

    check:
      r1.kind == RestApiResponseKind.Content
      bytesToString(r1.content.data) == "ok-1"
      r2.kind == RestApiResponseKind.Content
      bytesToString(r2.content.data) == "ok-2"

  test "Unique routes test":
    var router = RestRouter.init(testValidate)
    proc apiCallback(
      request: HttpRequestRef, pathParams: HttpTable,
      queryParams: HttpTable,
      body: Option[ContentBody]): Future[RestApiResponse] =
      discard

    # Use HTTP method GET
    router.addRoute(MethodGet, "/unique/path/1", apiCallback)
    router.addRoute(MethodGet, "/unique/path/2", apiCallback)
    router.addRoute(MethodGet, "/unique/path/{pattern1}", apiCallback)
    router.addRoute(MethodGet, "/unique/path/{pattern2}", apiCallback)

    # Use HTTP method POST
    router.addRoute(MethodPost, "/unique/path/1", apiCallback)
    router.addRoute(MethodPost, "/unique/path/2", apiCallback)
    router.addRoute(MethodPost, "/unique/path/{pattern1}", apiCallback)
    router.addRoute(MethodPost, "/unique/path/{pattern2}", apiCallback)

    # Use HTTP method GET and redirect
    router.addRedirect(MethodGet, "/redirect/path/1", "/unique/path/1")
    router.addRedirect(MethodGet, "/redirect/path/2", "/unique/path/2")
    router.addRedirect(MethodGet, "/redirect/path/{pattern1}",
                                  "/unique/path/{pattern1}")
    router.addRedirect(MethodGet, "/redirect/path/{pattern2}",
                                  "/unique/path/{pattern2")

    # Use HTTP method POST and redirect
    router.addRedirect(MethodPost, "/redirect/path/1", "/unique/path/1")
    router.addRedirect(MethodPost, "/redirect/path/2", "/unique/path/2")
    router.addRedirect(MethodPost, "/redirect/path/{pattern1}",
                                   "/unique/path/{pattern1}")
    router.addRedirect(MethodPost, "/redirect/path/{pattern2}",
                                   "/unique/path/{pattern2")

    expect AssertionError:
      router.addRoute(MethodGet, "/unique/path/1", apiCallback)
    expect AssertionError:
      router.addRoute(MethodGet, "/unique/path/2", apiCallback)
    expect AssertionError:
      router.addRoute(MethodGet, "/unique/path/{pattern1}", apiCallback)
    expect AssertionError:
      router.addRoute(MethodGet, "/unique/path/{pattern2}", apiCallback)

    expect AssertionError:
      router.addRoute(MethodGet, "/redirect/path/1", apiCallback)
    expect AssertionError:
      router.addRoute(MethodGet, "/redirect/path/2", apiCallback)
    expect AssertionError:
      router.addRoute(MethodGet, "/redirect/path/{pattern1}", apiCallback)
    expect AssertionError:
      router.addRoute(MethodGet, "/redirect/path/{pattern2}", apiCallback)

    expect AssertionError:
      router.addRoute(MethodPost, "/unique/path/1", apiCallback)
    expect AssertionError:
      router.addRoute(MethodPost, "/unique/path/2", apiCallback)
    expect AssertionError:
      router.addRoute(MethodPost, "/unique/path/{pattern1}", apiCallback)
    expect AssertionError:
      router.addRoute(MethodPost, "/unique/path/{pattern2}", apiCallback)

    expect AssertionError:
      router.addRoute(MethodPost, "/redirect/path/1", apiCallback)
    expect AssertionError:
      router.addRoute(MethodPost, "/redirect/path/2", apiCallback)
    expect AssertionError:
      router.addRoute(MethodPost, "/redirect/path/{pattern1}", apiCallback)
    expect AssertionError:
      router.addRoute(MethodPost, "/redirect/path/{pattern2}", apiCallback)

    expect AssertionError:
      router.addRedirect(MethodGet, "/unique/path/1", "/unique/1")
    expect AssertionError:
      router.addRedirect(MethodGet, "/unique/path/2", "/unique/2")
    expect AssertionError:
      router.addRedirect(MethodGet, "/unique/path/{pattern1}",
                                    "/unique/{pattern1}")
    expect AssertionError:
      router.addRedirect(MethodGet, "/unique/path/{pattern2}",
                                    "/unique/{pattern2}")

    expect AssertionError:
      router.addRedirect(MethodGet, "/redirect/path/1", "/another/1")
    expect AssertionError:
      router.addRedirect(MethodGet, "/redirect/path/2", "/another/2")
    expect AssertionError:
      router.addRedirect(MethodGet, "/redirect/path/{pattern1}",
                                    "/another/{pattern1}")
    expect AssertionError:
      router.addRedirect(MethodGet, "/redirect/path/{pattern2}",
                                    "/another/{pattern2}")

    expect AssertionError:
      router.addRedirect(MethodPost, "/unique/path/1", "/unique/1")
    expect AssertionError:
      router.addRedirect(MethodPost, "/unique/path/2", "/unique/2")
    expect AssertionError:
      router.addRedirect(MethodPost, "/unique/path/{pattern1}",
                                     "/unique/{pattern1}")
    expect AssertionError:
      router.addRedirect(MethodPost, "/unique/path/{pattern2}",
                                     "/unique/{pattern2}")

    expect AssertionError:
      router.addRedirect(MethodPost, "/redirect/path/1", "/another/1")
    expect AssertionError:
      router.addRedirect(MethodPost, "/redirect/path/2", "/another/2")
    expect AssertionError:
      router.addRedirect(MethodPost, "/redirect/path/{pattern1}",
                                     "/another/{pattern1}")
    expect AssertionError:
      router.addRedirect(MethodPost, "/redirect/path/{pattern2}",
                                     "/another/{pattern2}")

  test "Redirection test":
    var router = RestRouter.init(testValidate)

    router.api(MethodGet, "/test/empty/1") do (
      ) -> RestApiResponse:
      return RestApiResponse.response("ok-1", contentType = "test/test")
    router.api(MethodGet, "/test/empty/p1/p2/p3/1") do (
      ) -> RestApiResponse:
      return RestApiResponse.response("ok-2", contentType = "test/test")
    router.api(MethodGet, "/test/empty/p1/p2/p3/p5/p6/p7/p8/p9/1") do (
      ) -> RestApiResponse:
      return RestApiResponse.response("ok-3", contentType = "test/test")
    router.api(MethodGet, "/test/basic/path1/{smp1}") do (
      smp1: int) -> RestApiResponse:
      let s1 = smp1.get()
      if s1 == 999999:
        return RestApiResponse.response("ok-1", contentType = "test/test")
    router.api(MethodGet, "/test/basic/path1/path2/{smp1}/{smp2}") do (
      smp1: int, smp2: string) -> RestApiResponse:
      let s1 = smp1.get()
      let s2 = smp2.get()
      if (s1 == 999999) and (s2 == "string1"):
        return RestApiResponse.response("ok-2", contentType = "test/test")
    router.api(MethodGet,
               "/test/basic/path1/path2/path3/{smp1}/{smp2}/{smp3}") do (
      smp1: int, smp2: string, smp3: seq[byte]) -> RestApiResponse:
      let s1 = smp1.get()
      let s2 = smp2.get()
      let s3 = smp3.get()
      if (s1 == 999999) and (s2 == "string1") and
         (bytesToString(s3) == "bytes1"):
        return RestApiResponse.response("ok-3", contentType = "test/test")

    router.redirect(MethodGet, "/api/1", "/test/empty/1")
    router.redirect(MethodGet, "/api/2", "/test/empty/p1/p2/p3/1")
    router.redirect(MethodGet, "/api/3",
                    "/test/empty/p1/p2/p3/p5/p6/p7/p8/p9/1")
    router.redirect(MethodGet, "/api/basic/{smp1}",
                    "/test/basic/path1/{smp1}")
    router.redirect(MethodGet, "/api/basic/{smp1}/{smp2}",
                    "/test/basic/path1/path2/{smp1}/{smp2}")
    router.redirect(MethodGet, "/api/basic/{smp1}/{smp2}/{smp3}",
                    "/test/basic/path1/path2/path3/{smp1}/{smp2}/{smp3}")
    # Patterns with mixed order
    router.redirect(MethodGet, "/api/basic/{smp3}/{smp1}/{smp2}",
                    "/test/basic/path1/path2/path3/{smp1}/{smp2}/{smp3}")
    router.redirect(MethodGet, "/api/basic/{smp2}/{smp3}/{smp1}",
                    "/test/basic/path1/path2/path3/{smp1}/{smp2}/{smp3}")
    router.redirect(MethodGet, "/api/basic/{smp2}/{smp1}/{smp3}",
                    "/test/basic/path1/path2/path3/{smp1}/{smp2}/{smp3}")
    router.redirect(MethodGet, "/api/basic/{smp2}/p1/p2/p3/{smp1}",
                    "/test/basic/path1/path2/{smp1}/{smp2}")
    router.redirect(MethodGet, "/api/basic/{smp2}/p1/p2/p3/p4/p5/p6/{smp1}",
                    "/test/basic/path1/path2/{smp1}/{smp2}")
    router.redirect(MethodGet,
                    "/api/basic/{smp2}/p1/p2/p3/p4/p5/p6/p7/{smp1}/p8",
                    "/test/basic/path1/path2/{smp1}/{smp2}")

    let r1 = router.sendMockRequest(MethodGet, "http://l.to/api/1")
    let r2 = router.sendMockRequest(MethodGet, "http://l.to/api/2")
    let r3 = router.sendMockRequest(MethodGet, "http://l.to/api/3")
    let r4 = router.sendMockRequest(MethodGet,
                                    "http://l.to/api/basic/999999")
    let r5 = router.sendMockRequest(MethodGet,
                                    "http://l.to/api/basic/999999/string1")
    let r6 = router.sendMockRequest(MethodGet,
                          "http://l.to/api/basic/999999/string1/0x627974657331")
    let r7 = router.sendMockRequest(MethodGet,
                          "http://l.to/api/basic/0x627974657331/999999/string1")
    let r8 = router.sendMockRequest(MethodGet,
                          "http://l.to/api/basic/string1/0x627974657331/999999")
    let r9 = router.sendMockRequest(MethodGet,
                          "http://l.to/api/basic/string1/999999/0x627974657331")
    let r10 = router.sendMockRequest(MethodGet,
                                "http://l.to/api/basic/string1/p1/p2/p3/999999")
    let r11 = router.sendMockRequest(MethodGet,
                       "http://l.to/api/basic/string1/p1/p2/p3/p4/p5/p6/999999")
    let r12 = router.sendMockRequest(MethodGet,
                 "http://l.to/api/basic/string1/p1/p2/p3/p4/p5/p6/p7/999999/p8")
    check:
      r1.kind == RestApiResponseKind.Content
      r2.kind == RestApiResponseKind.Content
      r3.kind == RestApiResponseKind.Content
      r4.kind == RestApiResponseKind.Content
      r5.kind == RestApiResponseKind.Content
      r6.kind == RestApiResponseKind.Content
      r7.kind == RestApiResponseKind.Content
      r8.kind == RestApiResponseKind.Content
      r9.kind == RestApiResponseKind.Content
      r10.kind == RestApiResponseKind.Content
      r11.kind == RestApiResponseKind.Content
      r12.kind == RestApiResponseKind.Content
      bytesToString(r1.content.data) == "ok-1"
      bytesToString(r2.content.data) == "ok-2"
      bytesToString(r3.content.data) == "ok-3"
      bytesToString(r4.content.data) == "ok-1"
      bytesToString(r5.content.data) == "ok-2"
      bytesToString(r6.content.data) == "ok-3"
      bytesToString(r7.content.data) == "ok-3"
      bytesToString(r8.content.data) == "ok-3"
      bytesToString(r9.content.data) == "ok-3"
      bytesToString(r10.content.data) == "ok-2"
      bytesToString(r11.content.data) == "ok-2"
      bytesToString(r12.content.data) == "ok-2"
