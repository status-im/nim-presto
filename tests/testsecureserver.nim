import std/[unittest, strutils]
import helpers
import chronos, chronos/apps
import stew/byteutils
import ../presto/route, ../presto/segpath, ../presto/secureserver

when defined(nimHasUsed): {.used.}

type
  ClientResponse = object
    status*: int
    data*: string

const RestSelfSignedRsaCert = """
-----BEGIN CERTIFICATE-----
MIIDbTCCAlWgAwIBAgIUXt7sUWAxsChC9lOZb15IwNWO514wDQYJKoZIhvcNAQEL
BQAwRTELMAkGA1UEBhMCQVUxEzARBgNVBAgMClNvbWUtU3RhdGUxITAfBgNVBAoM
GEludGVybmV0IFdpZGdpdHMgUHR5IEx0ZDAgFw0yMTAzMjQxMzI3MDFaGA8zMDIw
MDcyNTEzMjcwMVowRTELMAkGA1UEBhMCQVUxEzARBgNVBAgMClNvbWUtU3RhdGUx
ITAfBgNVBAoMGEludGVybmV0IFdpZGdpdHMgUHR5IEx0ZDCCASIwDQYJKoZIhvcN
AQEBBQADggEPADCCAQoCggEBAKL5rge7XWBZsIjWLAfyXaz/VxZec41Rt803oOK+
5/FeixxPwzQVAWRQVZuYEnx9SlDG0ApSbeuS9zV2lI8NhrWcGGaFYOxwaIN0x/qG
buWDK+XDUxEhWXfJvwWPDh1oq40M/DCmExNHTnQX2Ep75KGz9fxlqpBGn3V0S15+
HoX9zXn6p7IMrw7pdAtN3pEGwAAD6wV+RBr66ylpRw+u1WeBpouq6O/hECT1qvgi
ku6jDpSuqKDTnfCNNmoaUGPGfHO8t0XCCrre1FkQcJQTYoLuz3p35gOyPtmRluWn
uzIILKhm3koofHbrwiPDZrHaBFE9zACjWMu9IvwbWuectJsCAwEAAaNTMFEwHQYD
VR0OBBYEFD0j7UYWOb/bFunmDa389UTgoGQ4MB8GA1UdIwQYMBaAFD0j7UYWOb/b
FunmDa389UTgoGQ4MA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEB
AA6yZ7r9YwXvNO31lRwUyAYyjoN6eXvinRTn9Hcq+B7mnaPRgMw0O0EcLKTrD4XU
ZCVq1zxAuGDL/EY8FGRRnnhhQoP4XngWTc72StjbolQJu8QlcXnvdRRuk5ExEhPP
0PhSoVzNRJnsFKisiYldDdFFHVmLJng62qan2fGou4KVkaAdrNuhzNyBy1rUIXfw
eCQnwP85i2057ErXu88ZJxbJC//JwOs39xp9UK/QtzY91nHjU95VhpCNz5htY0s7
aArk38SknwUElPtCKRpkIECZAnLxnJQZS5AodwlaDBSTa8hMtwTxHyAI0OZKkqcI
gTVPzfifd3YFR/gZ9LzI5gM=
-----END CERTIFICATE-----
"""
const RestSelfSignedRsaKey = """
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCi+a4Hu11gWbCI
1iwH8l2s/1cWXnONUbfNN6DivufxXoscT8M0FQFkUFWbmBJ8fUpQxtAKUm3rkvc1
dpSPDYa1nBhmhWDscGiDdMf6hm7lgyvlw1MRIVl3yb8Fjw4daKuNDPwwphMTR050
F9hKe+Shs/X8ZaqQRp91dEtefh6F/c15+qeyDK8O6XQLTd6RBsAAA+sFfkQa+usp
aUcPrtVngaaLqujv4RAk9ar4IpLuow6Urqig053wjTZqGlBjxnxzvLdFwgq63tRZ
EHCUE2KC7s96d+YDsj7ZkZblp7syCCyoZt5KKHx268Ijw2ax2gRRPcwAo1jLvSL8
G1rnnLSbAgMBAAECggEARAAr5hv+hSJHL4E1lAdDoNhVrQax7ihHqb/pSFLhkmuh
XanGSCfvkbyXS7mzFPBuHrAlw/jK1n1W2p7ks5+wMny0DarfWyg344nJmzWWdfs6
SL8sHLyuiPXL13TuLcUrt0nQvDe/Q87/5B7C56k0J2hgXfTJqzNce3SPshirgbpO
+WDDI5iXt3Qsp0mPVfr81UclfMUcQndgNROB//xbzqxARUGdLA9n4tqQNc9kV9lr
1T+b08VbJQB26Sw1FZp9Lf9SsN6kwiv1pG6X8q4ZVIeWf9McbmkzWCxgO4wBgZKj
bpH95hDJNcNiUsjCAh7MUWdpgQQ6GBylV593l3AJ8QKBgQDUYYoSApT0unX3Z5GX
Iyx0o6+8SI30kCsVonZBj7533MNRYkMo4y5aIlTjRNojEggE4udq6rwyzJ2TCNoX
ZA6Nswpy4oFNAVtnyfYEn7AbtL6QOHg3U8u2gX9igzfPr+51IDf0qmaSJE60Chj6
kXyfV/aGAGxV0wS8hI4+hKpmcwKBgQDEcoM/VnBd0y8A/kM71YXcjR0ZfyxF7BXA
YkNKEhyS83la4u4nhRh0xj/MzI3o7VGY2YZMEZ7iqOzInYpFxS7K9TFlDKcPcjAi
I07+jKYLlfZAB+5JH/JZfAOPEtTBiv4snmeCjw8Su5K1nENLSUJc1h4oMrJQyyPN
+oG0xTZHOQKBgQCaF4MT+ieVQMxiixSJMg4JOtJAq+vDK+72rX9bpi2tzdEw9TiB
LAPvhcVNeCFFHMoQsYjyfAm8WdViXyPNoN0mVmcYX9sswfVN4qzLQgmGsKcrAK3I
htXhPyfrlAUkfSNoe83diN0O36Ty3/irpG9lNW86Xog75PUkypBiL+NqnQKBgGsl
TiKgob767VssUz1yU4Wcze9XJq2oe6Cnt63RvRYFh/4jYePaOyGN88RfGVOfBO9K
TW51+eQEYMl267DsQH5gR6WmxgOts0UbXv2FdxdAnsQDz1rA+u0Fr+c8TSCXD9UE
PM6/+mesOPOnHCkW9wQtoNsp84oPkiLJbC9NlTI5AoGBAIYTVvr4AavxWWYkZ+Nw
qzb7UdXA+9cF5eyBWpaUSlj1oiirU0f4dM+bDVvmjWTi06I651h7RuU4Ig4V1SkX
5HM9UDYqJg+fUuCNzVHwzhqCyZUkabM/m/Ii7s0fBlTCF1u3MhXUVgrcl8TZgkea
7hxiycMFjHlJW2mRwa5ak+PY
-----END PRIVATE KEY-----
"""

proc httpsClient(server: TransportAddress, meth: HttpMethod, url: string,
                body: string, ctype = "",
                flags = {TLSFlags.NoVerifyHost, TLSFlags.NoVerifyServerName}
                ): Future[ClientResponse] {.async.} =
  var request = $meth & " " & $parseUri(url) & " HTTP/1.1\r\n"
  request.add("Host: " & $server & "\r\n")
  request.add("Content-Length: " & $len(body) & "\r\n")
  if len(ctype) > 0:
    request.add("Content-Type: " & ctype & "\r\n")
  request.add("\r\n")

  if len(body) > 0:
    request.add(body)

  var headersBuf = newSeq[byte](4096)

  var
    transp: StreamTransport
    tlsstream: TLSAsyncStream
    reader: AsyncStreamReader
    writer: AsyncStreamWriter

  try:
    transp = await connect(server)
    reader = newAsyncStreamReader(transp)
    writer = newAsyncStreamWriter(transp)
    tlsstream = newTLSClientAsyncStream(reader, writer, "", flags = flags)

    await tlsstream.writer.write(request)
    let rlen = await tlsstream.reader.readUntil(addr headersBuf[0],
                                                len(headersBuf), HeadersMark)
    headersBuf.setLen(rlen)
    let resp = parseResponse(headersBuf, true)
    doAssert(resp.success())
    let length = resp.contentLength()
    doAssert(length >= 0)
    let cresp =
      if length > 0:
        var dataBuf = newString(length)
        await tlsstream.reader.readExactly(addr dataBuf[0], len(dataBuf))
        ClientResponse(status: resp.code, data: dataBuf)
      else:
        ClientResponse(status: resp.code, data: "")
    return cresp
  finally:
    if not(isNil(tlsstream)):
      await allFutures(tlsstream.reader.closeWait(),
                       tlsstream.writer.closeWait())
    if not(isNil(reader)):
      await allFutures(reader.closeWait(), writer.closeWait(),
                       transp.closeWait())

proc createServer(address: TransportAddress,
                  router: RestRouter): SecureRestServerRef =
  let secureKey = TLSPrivateKey.init(RestSelfSignedRsaKey)
  let secureCert = TLSCertificate.init(RestSelfSignedRsaCert)
  let sres = SecureRestServerRef.new(router, address, secureKey,
                                     secureCert)
  sres.get()

template asyncTest*(name: string, body: untyped): untyped =
  test name:
    waitFor((
      proc() {.async, gcsafe.} =
        body
    )())

suite "Secure REST API server test suite":
  let serverAddress = initTAddress("127.0.0.1:30180")
  asyncTest "Responses test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet, "/test/simple/1") do () -> RestApiResponse:
      discard

    router.api(MethodGet, "/test/simple/2") do () -> RestApiResponse:
      return RestApiResponse.response("ok-1")

    router.api(MethodGet, "/test/simple/3") do () -> RestApiResponse:
      return RestApiResponse.error(Http505, "Some error", "text/error")

    router.api(MethodGet, "/test/simple/4") do () -> RestApiResponse:
      if true:
        raise newException(ValueError, "Some exception")

    let server = createServer(serverAddress, router)
    server.start()
    try:
      # Handler returned empty response.
      let res1 = await httpsClient(serverAddress, MethodGet, "/test/simple/1",
                                  "")
      # Handler returned good response.
      let res2 = await httpsClient(serverAddress, MethodGet, "/test/simple/2",
                                  "")
      # Handler returned via RestApiResponse.
      let res3 = await httpsClient(serverAddress, MethodGet, "/test/simple/3",
                                  "")
      # Exception generated by handler.
      let res4 = await httpsClient(serverAddress, MethodGet, "/test/simple/4",
                                  "")
      # Missing handler response
      let res5 = await httpsClient(serverAddress, MethodGet, "/test/simple/5",
                                  "")
      # URI with more than 64 segments response
      let res6 = await httpsClient(serverAddress, MethodGet,
                                  "//////////////////////////////////////////" &
                                  "//////////////////////////test", "")
      check:
        res1 == ClientResponse(status: 410)
        res2 == ClientResponse(status: 200, data: "ok-1")
        res3.status == 505
        res4 == ClientResponse(status: 503)
        res5 == ClientResponse(status: 404)
        res6 == ClientResponse(status: 400)
    finally:
      await server.closeWait()

  asyncTest "Requests [path] arguments test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet, "/test/{smp1}") do (
        smp1: int) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      return RestApiResponse.response($smp1.get())

    router.api(MethodGet, "/test/{smp1}/{smp2}") do (
        smp1: int, smp2: string) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      if smp2.isErr():
        return RestApiResponse.error(Http412, $smp2.error())
      return RestApiResponse.response($smp1.get() & ":" &
                                         smp2.get())

    router.api(MethodGet, "/test/{smp1}/{smp2}/{smp3}") do (
        smp1: int, smp2: string, smp3: seq[byte]) -> RestApiResponse:
      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      if smp2.isErr():
        return RestApiResponse.error(Http412, $smp2.error())
      if smp3.isErr():
        return RestApiResponse.error(Http413, $smp3.error())
      return RestApiResponse.response($smp1.get() & ":" & smp2.get() & ":" &
                                      toHex(smp3.get()))

    const TestVectors = [
      ("/test/1234", ClientResponse(status: 200, data: "1234")),
      ("/test/12345678", ClientResponse(status: 200, data: "12345678")),
      ("/test/00000001", ClientResponse(status: 200, data: "1")),
      ("/test/0000000", ClientResponse(status: 200, data: "0")),
      ("/test/99999999999999999999999", ClientResponse(status: 411)),
      ("/test/nondec", ClientResponse(status: 404)),

      ("/test/1234/text1", ClientResponse(status: 200, data: "1234:text1")),
      ("/test/12345678/texttext2",
       ClientResponse(status: 200, data: "12345678:texttext2")),
      ("/test/00000001/texttexttext3",
       ClientResponse(status: 200, data: "1:texttexttext3")),
      ("/test/0000000/texttexttexttext4",
       ClientResponse(status: 200, data: "0:texttexttexttext4")),
      ("/test/nondec/texttexttexttexttext5", ClientResponse(status: 404)),
      ("/test/99999999999999999999999/texttexttexttexttext5",
       ClientResponse(status: 411)),

      ("/test/1234/text1/0xCAFE",
       ClientResponse(status: 200, data: "1234:text1:cafe")),
      ("/test/12345678/text2text2/0xdeadbeaf",
       ClientResponse(status: 200, data: "12345678:text2text2:deadbeaf")),
      ("/test/00000001/text3text3text3/0xabcdef012345",
       ClientResponse(status: 200, data: "1:text3text3text3:abcdef012345")),
      ("/test/00000000/text4text4text4text4/0xaa",
       ClientResponse(status: 200, data: "0:text4text4text4text4:aa")),
      ("/test/nondec/text5/0xbb", ClientResponse(status: 404)),
      ("/test/99999999999999999999999/text6/0xcc", ClientResponse(status: 411)),
      ("/test/1234/text7/0xxx", ClientResponse(status: 413))
    ]

    let server = createServer(serverAddress, router)
    server.start()
    try:
      for item in TestVectors:
        let res = await httpsClient(serverAddress, MethodGet,
                                   item[0], "")
        check res.status == item[1].status
        if len(item[1].data) > 0:
          check res.data == item[1].data
    finally:
      await server.closeWait()

  asyncTest "Requests [path + query] arguments test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet, "/test/{smp1}/{smp2}/{smp3}") do (
        smp1: int, smp2: string, smp3: seq[byte],
        opt1: Option[int], opt2: Option[string], opt3: Option[seq[byte]],
        opt4: seq[int], opt5: seq[string],
        opt6: seq[seq[byte]]) -> RestApiResponse:

      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      if smp2.isErr():
        return RestApiResponse.error(Http412, $smp2.error())
      if smp3.isErr():
        return RestApiResponse.error(Http413, $smp3.error())

      let o1 =
        if opt1.isSome():
          let res = opt1.get()
          if res.isErr():
            return RestApiResponse.error(Http414, $res.error())
          $res.get()
        else:
          ""
      let o2 =
        if opt2.isSome():
          let res = opt2.get()
          if res.isErr():
            return RestApiResponse.error(Http415, $res.error())
          res.get()
        else:
          ""
      let o3 =
        if opt3.isSome():
          let res = opt3.get()
          if res.isErr():
            return RestApiResponse.error(Http416, $res.error())
          toHex(res.get())
        else:
          ""
      let o4 =
        if opt4.isErr():
          return RestApiResponse.error(Http417, $opt4.error())
        else:
          opt4.get().join(",")
      let o5 =
        if opt5.isErr():
          return RestApiResponse.error(Http418, $opt5.error())
        else:
          opt5.get().join(",")
      let o6 =
        if opt6.isErr():
          return RestApiResponse.error(Http421, $opt6.error())
        else:
          let binres = opt6.get()
          var res = newSeq[string]()
          for item in binres:
            res.add(toHex(item))
          res.join(",")

      let body = $smp1.get() & ":" & smp2.get() & ":" & toHex(smp3.get()) &
                 ":" & o1 & ":" & o2 & ":" & o3 &
                 ":" & o4 & ":" & o5 & ":" & o6
      return RestApiResponse.response(body)

    const TestVectors = [
      ("/test/1/2/0xaa?opt1=1&opt2=2&opt3=0xbb&opt4=2&opt4=3&opt4=4&opt5=t&" &
        "opt5=e&opt5=s&opt5=t&opt6=0xCA&opt6=0xFE",
        ClientResponse(status: 200, data: "1:2:aa:1:2:bb:2,3,4:t,e,s,t:ca,fe")),
      # Optional argument will not pass decoding procedure `opt1=a`.
      ("/test/1/2/0xaa?opt1=a&opt2=2&opt3=0xbb&opt4=2&opt4=3&opt4=4&opt5=t&" &
        "opt5=e&opt5=s&opt5=t&opt6=0xCA&opt6=0xFE",
        ClientResponse(status: 414)),
      # Sequence argument will not pass decoding procedure `opt4=a`.
      ("/test/1/2/0xaa?opt1=1&opt2=2&opt3=0xbb&opt4=2&opt4=3&opt4=a&opt5=t&" &
        "opt5=e&opt5=s&opt5=t&opt6=0xCA&opt6=0xFE",
        ClientResponse(status: 417)),
      # Optional argument will not pass decoding procedure `opt3=0xxx`.
      ("/test/1/2/0xaa?opt1=1&opt2=2&opt3=0xxx&opt4=2&opt4=3&opt4=4&opt5=t&" &
        "opt5=e&opt5=s&opt5=t&opt6=0xCA&opt6=0xFE",
        ClientResponse(status: 416)),
      # Sequence argument will not pass decoding procedure `opt6=0xxx`.
      ("/test/1/2/0xaa?opt1=1&opt2=2&opt3=0xbb&opt4=2&opt4=3&opt4=5&opt5=t&" &
        "opt5=e&opt5=s&opt5=t&opt6=0xCA&opt6=0xxx",
        ClientResponse(status: 421)),
      # All optional arguments are missing
      ("/test/1/2/0xaa", ClientResponse(status: 200, data: "1:2:aa::::::"))
    ]

    let server = createServer(serverAddress, router)
    server.start()
    try:
      for item in TestVectors:
        let res = await httpsClient(serverAddress, MethodGet,
                                   item[0], "")
        check res.status == item[1].status
        if len(item[1].data) > 0:
          check res.data == item[1].data
    finally:
      await server.closeWait()

  asyncTest "Requests [path + query + request body] test":
    var router = RestRouter.init(testValidate)
    router.api(MethodPost, "/test/{smp1}/{smp2}/{smp3}") do (
        smp1: int, smp2: string, smp3: seq[byte],
        opt1: Option[int], opt2: Option[string], opt3: Option[seq[byte]],
        opt4: seq[int], opt5: seq[string],
        opt6: seq[seq[byte]],
        contentBody: Option[ContentBody]) -> RestApiResponse:

      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      if smp2.isErr():
        return RestApiResponse.error(Http412, $smp2.error())
      if smp3.isErr():
        return RestApiResponse.error(Http413, $smp3.error())

      let o1 =
        if opt1.isSome():
          let res = opt1.get()
          if res.isErr():
            return RestApiResponse.error(Http414, $res.error())
          $res.get()
        else:
          ""
      let o2 =
        if opt2.isSome():
          let res = opt2.get()
          if res.isErr():
            return RestApiResponse.error(Http415, $res.error())
          res.get()
        else:
          ""
      let o3 =
        if opt3.isSome():
          let res = opt3.get()
          if res.isErr():
            return RestApiResponse.error(Http416, $res.error())
          toHex(res.get())
        else:
          ""
      let o4 =
        if opt4.isErr():
          return RestApiResponse.error(Http417, $opt4.error())
        else:
          opt4.get().join(",")
      let o5 =
        if opt5.isErr():
          return RestApiResponse.error(Http418, $opt5.error())
        else:
          opt5.get().join(",")
      let o6 =
        if opt6.isErr():
          return RestApiResponse.error(Http421, $opt6.error())
        else:
          let binres = opt6.get()
          var res = newSeq[string]()
          for item in binres:
            res.add(toHex(item))
          res.join(",")

      let obody =
        if contentBody.isSome():
          let body = contentBody.get()
          $body.contentType & "," & bytesToString(body.data)
        else:
          "nobody"

      let body = $smp1.get() & ":" & smp2.get() & ":" & toHex(smp3.get()) &
                 ":" & o1 & ":" & o2 & ":" & o3 &
                 ":" & o4 & ":" & o5 & ":" & o6 &
                 ":" & obody

      return RestApiResponse.response(body)

    const PostVectors = [
      (
        ("/test/1/2/0xaa", "text/plain", "textbody"),
        ClientResponse(status: 200,
                       data: "1:2:aa:::::::text/plain,textbody")
      ),
      (
        ("/test/1/2/0xaa", "", ""),
        ClientResponse(status: 400)
      ),
      (
        ("/test/1/2/0xaa", "text/plain", ""),
        ClientResponse(status: 200,
                       data: "1:2:aa:::::::text/plain,")
      ),
      (
        ("/test/1/2/0xaa?opt1=1&opt2=2&opt3=0xbb&opt4=2&opt4=3&opt4=4&opt5=t&" &
         "opt5=e&opt5=s&opt5=t&opt6=0xCA&opt6=0xFE", "text/plain", "textbody"),
        ClientResponse(status: 200, data:
                       "1:2:aa:1:2:bb:2,3,4:t,e,s,t:ca,fe:text/plain,textbody")
      )
    ]

    let server = createServer(serverAddress, router)
    server.start()
    try:
      for item in PostVectors:
        let req = item[0]
        let res = await httpsClient(serverAddress, MethodPost,
                                   req[0], req[2], req[1])
        check res.status == item[1].status
        if len(item[1].data) > 0:
          check res.data == item[1].data

    finally:
      await server.closeWait()

  asyncTest "Direct response manipulation test":
    var router = RestRouter.init(testValidate)
    router.api(MethodGet, "/test/{smp1}") do (
      smp1: int, opt1: Option[int], opt4: seq[int],
      resp: HttpResponseRef) -> RestApiResponse:

      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())

      let o1 =
        if opt1.isSome():
          let res = opt1.get()
          if res.isErr():
            return RestApiResponse.error(Http414, $res.error())
          $res.get()
        else:
          ""
      let o4 =
        if opt4.isErr():
          return RestApiResponse.error(Http417, $opt4.error())
        else:
          opt4.get().join(",")

      let path = smp1.get()
      let restResp = $smp1.get() & ":" & o1 & ":" & o4
      case path
      of 1:
        await resp.sendBody(restResp)
      of 2:
        await resp.sendBody(restResp)
        return RestApiResponse.response("")
      of 3:
        await resp.sendBody(restResp)
        return RestApiResponse.error(Http422, "error")
      else:
        return RestApiResponse.error(Http426, "error")

    router.api(MethodPost, "/test/{smp1}") do (
      smp1: int, opt1: Option[int], opt4: seq[int],
      body: Option[ContentBody],
      resp: HttpResponseRef) -> RestApiResponse:

      if smp1.isErr():
        return RestApiResponse.error(Http411, $smp1.error())
      let o1 =
        if opt1.isSome():
          let res = opt1.get()
          if res.isErr():
            return RestApiResponse.error(Http414, $res.error())
          $res.get()
        else:
          ""
      let o4 =
        if opt4.isErr():
          return RestApiResponse.error(Http417, $opt4.error())
        else:
          opt4.get().join(",")

      let obody =
        if body.isSome():
          let b = body.get()
          $b.contentType & "," & bytesToString(b.data)
        else:
          "nobody"

      let path = smp1.get()
      let restResp = $smp1.get() & ":" & o1 & ":" & o4 & ":" & obody

      case path
      of 1:
        await resp.sendBody(restResp)
      of 2:
        await resp.sendBody(restResp)
        return RestApiResponse.response("some result")
      of 3:
        await resp.sendBody(restResp)
        return RestApiResponse.error(Http422, "error")
      else:
        return RestApiResponse.error(Http426, "error")

    const PostVectors = [
      (
        # Empty result with response sent via `resp`.
        ("/test/1?opt1=2345&opt4=3456&opt4=4567&opt4=5678&opt4=6789",
         "text/plain", "somebody"),
         ClientResponse(status: 200,
                        data: "1:2345:3456,4567,5678,6789:text/plain,somebody")
      ),
      (
        # Result with response sent via `resp`.
        ("/test/2?opt1=2345&opt4=3456&opt4=4567&opt4=5678&opt4=6789",
         "text/plain", "somebody"),
        ClientResponse(status: 200,
                       data: "2:2345:3456,4567,5678,6789:text/plain,somebody")
      ),
      (
        # Error with response sent via `resp`.
        ("/test/3?opt1=2345&opt4=3456&opt4=4567&opt4=5678&opt4=6789",
         "text/plain", "somebody"),
         ClientResponse(status: 200,
                        data: "3:2345:3456,4567,5678,6789:text/plain,somebody")
      )
    ]

    const GetVectors = [
      (
        # Empty result with response sent via `resp`.
        "/test/1?opt1=2345&opt4=3456&opt4=4567&opt4=5678&opt4=6789",
        ClientResponse(status: 200, data: "1:2345:3456,4567,5678,6789")
      ),
      (
        # Result with response sent via `resp`.
        "/test/2?opt1=2345&opt4=3456&opt4=4567&opt4=5678&opt4=6789",
        ClientResponse(status: 200, data: "2:2345:3456,4567,5678,6789")
      ),
      (
        # Error with response sent via `resp`.
        "/test/3?opt1=2345&opt4=3456&opt4=4567&opt4=5678&opt4=6789",
        ClientResponse(status: 200, data: "3:2345:3456,4567,5678,6789")
      )
    ]

    let server = createServer(serverAddress, router)
    server.start()
    try:
      for item in GetVectors:
        let res = await httpsClient(serverAddress, MethodGet, item[0], "")
        check res.status == item[1].status
        if len(item[1].data) > 0:
          check res.data == item[1].data

      for item in PostVectors:
        let req = item[0]
        let res = await httpsClient(serverAddress, MethodPost,
                                   req[0], req[2], req[1])
        check res.status == item[1].status
        if len(item[1].data) > 0:
          check res.data == item[1].data

    finally:
      await server.closeWait()

  test "Leaks test":
    check:
      getTracker("async.stream.reader").isLeaked() == false
      getTracker("async.stream.writer").isLeaked() == false
      getTracker("stream.server").isLeaked() == false
      getTracker("stream.transport").isLeaked() == false
