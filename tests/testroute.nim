import std/[unittest, strutils, parseutils]
import helpers
import chronos, chronos/apps
import stew/byteutils
import ../rest/route, ../rest/segpath

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
  let contentBody = ContentBody(contentType: "text/text",
                                data: stringToBytes(data))
  sendMockRequest(router, meth, url, some[ContentBody](contentBody))

suite "REST API router & macro tests":
  test "No parameters test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet, "/test/empty/1") do (
      ) -> RestApiResponse:
      return ok(ContentBody(contentType: "test/test", data: "ok-1".toBytes()))
    router.api(MethodGet, "/test/empty/p1/2") do (
      resp: HttpResponseRef) -> RestApiResponse:
      # To avoid warning about unused `resp`
      let testResp {.used.} = resp
      return ok(ContentBody(contentType: "test/test", data: "ok-2".toBytes()))
    router.api(MethodPost, "/test/empty/p1/p2/3") do (
      contentBody: Option[ContentBody]) -> RestApiResponse:
      if contentBody.isSome():
        return ok(ContentBody(contentType: "test/test", data: "ok-3".toBytes()))
    router.api(MethodGet, "/test/empty/p1/p2/p3/4") do (
      resp: HttpResponseRef,
      contentBody: Option[ContentBody]) -> RestApiResponse:
      # To avoid warning about unused `resp`
      let testResp {.used.} = resp
      if contentBody.isSome():
        return ok(ContentBody(contentType: "test/test", data: "ok-4".toBytes()))

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
      r1.isOk()
      r2.isOk()
      r3.isOk()
      r4.isOk()
      bytesToString(r1.get().data) == "ok-1"
      bytesToString(r2.get().data) == "ok-2"
      bytesToString(r3.get().data) == "ok-3"
      bytesToString(r4.get().data) == "ok-4"

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
          return ok(ContentBody(contentType: "test/test",
                                data: "ok-1".toBytes()))

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
          return ok(ContentBody(contentType: "test/test",
                                data: "ok-2".toBytes()))

    let r1 = router.sendMockRequest(MethodGet,
      "http://l.to/test/basic_args/1/999999/test1/0x7465737431")
    let r2 = router.sendMockRequest(MethodGet,
      "http://l.to/test/basic_args/2/888888/test2/0x7465737432" &
      "?opt1=777777&opt2=testopt2&opt3=0x7465737432")
    check:
      r1.isOk()
      bytesToString(r1.get().data) == "ok-1"
      r2.isOk()
      bytesToString(r2.get().data) == "ok-2"

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
          return ok(ContentBody(contentType: "test/test",
                                data: "ok-1".toBytes()))
    router.api(MethodPost,
               "/test/custom_args/2/{pat1}/{pat2}/{pat3}") do (
      pat1: CustomType1, pat2: CustomType1, pat3: CustomType1,
      opt1: Option[CustomType1], opt2: Option[CustomType1],
      opt3: Option[CustomType1], body: Option[ContentBody]) -> RestApiResponse:
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
          return ok(ContentBody(contentType: "test/test",
                                data: "ok-2".toBytes()))

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
        return ok(ContentBody(contentType: "test/test",
                              data: "ok-3".toBytes()))

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
      r1.isOk()
      bytesToString(r1.get().data) == "ok-1"
      r2.isOk()
      bytesToString(r2.get().data) == "ok-2"
      r3.isOk()
      bytesToString(r3.get().data) == "ok-3"

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
        return ok(ContentBody(contentType: "test/test",
                              data: "ok-1".toBytes()))

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
          return ok(ContentBody(contentType: "test/test",
                                data: "ok-2".toBytes()))

    let r1 = router.sendMockRequest(MethodPost,
      "http://l.to/test/basic_seq/1?opt1=1&opt2=test1&opt3=0x3130" &
      "&opt1=2&opt2=test2&opt3=0x3230&opt1=3&opt2=test3&opt3=0x3330", "123456")

    let r2 = router.sendMockRequest(MethodPost,
      "http://l.to/test/basic_seq/1/0x313233343536" &
      "?opt1=1&opt2=test1&opt3=0x30&opt1=2&opt2=test2&opt3=0x31" &
      "&opt1=3&opt2=test3&opt3=0x32&opt1=4&opt2=test4&opt3=0x33" &
      "&opt1=5&opt2=test5&opt3=0x34", "654321")
    check:
      r1.isOk()
      r2.isOk()
      bytesToString(r1.get().data) == "ok-1"
      bytesToString(r2.get().data) == "ok-2"

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
        return ok(ContentBody(contentType: "test/test", data: "ok-1".toBytes()))

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
        return ok(ContentBody(contentType: "test/test", data: "ok-2".toBytes()))

    let r1 = router.sendMockRequest(MethodPost,
      "http://l.to/test/custom_seq/1?opt1=p1_1&opt2=p2_test1&opt3=p3_0x303132" &
      "&opt1=p1_2&opt2=p2_test2&opt3=p3_0x333435" &
      "&opt1=p1_3&opt2=p2_test3&opt3=p3_0x363738", "123456")

    let r2 = router.sendMockRequest(MethodPost,
      "http://l.to/test/custom_seq/2?opt1=1&opt2=test1&opt3=0x393837" &
      "&opt1=2&opt2=test2&opt3=0x363534&opt1=3&opt2=test3&opt3=0x333231",
      "654321")

    check:
      r1.isOk()
      r2.isOk()
      bytesToString(r1.get().data) == "ok-1"
      bytesToString(r2.get().data) == "ok-2"

  test "Unique routes test":
    var router = RestRouter.init(testValidate)
    proc apiCallback(request: HttpRequestRef, pathParams: HttpTable,
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

    expect AssertionError:
      router.addRoute(MethodGet, "/unique/path/1", apiCallback)
    expect AssertionError:
      router.addRoute(MethodGet, "/unique/path/2", apiCallback)
    expect AssertionError:
      router.addRoute(MethodGet, "/unique/path/{pattern1}", apiCallback)
    expect AssertionError:
      router.addRoute(MethodGet, "/unique/path/{pattern2}", apiCallback)

    expect AssertionError:
      router.addRoute(MethodPost, "/unique/path/1", apiCallback)
    expect AssertionError:
      router.addRoute(MethodPost, "/unique/path/2", apiCallback)
    expect AssertionError:
      router.addRoute(MethodPost, "/unique/path/{pattern1}", apiCallback)
    expect AssertionError:
      router.addRoute(MethodPost, "/unique/path/{pattern2}", apiCallback)
