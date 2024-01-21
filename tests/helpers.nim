import std/[strutils, parseutils, uri]
import stew/[byteutils, base10]
import chronos, chronos/apps
import ../presto/common

const
  testMediaType1* = MediaType.init("app/type1")
  testMediaType2* = MediaType.init("app/type2")

type
  CustomKind* {.pure.} = enum
    Level1, Level2, Level3

  CustomType1* = object
    case kind*: CustomKind
    of Level1:
      level1*: int
    of Level2:
      level2*: string
    of Level3:
      level3*: seq[byte]

  GenericType*[T] = object
    data*: T

  ClientResponse* = object
    status*: int
    data*: string
    headers*: HttpTable

proc decodeString*(t: typedesc[GenericType[int]],
                   value: string): RestResult[GenericType[int]] =
  var v: int
  if parseSaturatedNatural(value, v) == 0:
    err("Unable to decode decimal string")
  else:
    if v == high(int):
      err("Integer overflow")
    else:
      ok(GenericType[int](data: v))

proc decodeString*(t: typedesc[GenericType[string]],
                   value: string): RestResult[GenericType[string]] =
  ok(GenericType[string](data: value))

proc decodeString*(t: typedesc[GenericType[seq[byte]]],
                   value: string): RestResult[GenericType[seq[byte]]] =
  try:
    let bytes = hexToSeqByte(value)
    let res = GenericType[seq[byte]](data: bytes)
    return ok(res)
  except ValueError:
    discard
  err("Unable to decode hex string")

proc decodeString*(t: typedesc[CustomType1],
                   value: string): RestResult[CustomType1] =
  if value.startsWith("p1_"):
    let res = value[3 .. ^1]
    var v: int
    if parseSaturatedNatural(res, v) == 0:
      err("Unable to decode decimal string")
    else:
      if v == high(int):
        err("Integer overflow")
      else:
        ok(CustomType1(kind: CustomKind.Level1, level1: v))
  elif value.startsWith("p2_"):
    let res = value[3 .. ^1]
    ok(CustomType1(kind: CustomKind.Level2, level2: res))
  elif value.startsWith("p3_"):
    let res = value[3 .. ^1]
    try:
      return ok(CustomType1(kind: CustomKind.Level3, level3: hexToSeqByte(res)))
    except ValueError:
      discard
    err("Unable to decode hex string")
  else:
    err("Unable to decode value")

proc decodeBytes*(t: typedesc[CustomType1], value: openArray[byte],
                  contentType: Opt[ContentTypeData]): RestResult[CustomType1] =
  discard

proc decodeBytes*(t: typedesc[string], value: openArray[byte],
                  contentType: Opt[ContentTypeData]): RestResult[string] =
  var res: string
  if len(value) > 0:
    res = newString(len(value))
    copyMem(addr res[0], unsafeAddr value[0], len(value))
  ok(res)

proc decodeBytes*(t: typedesc[int], value: openArray[byte],
                  contentType: Opt[ContentTypeData]): RestResult[int] =
  if len(value) == 0:
    err("Could not find any integer")
  else:
    let res = Base10.decode(uint16, value)
    if res.isErr():
      err(res.error())
    else:
      ok(int(res.get()))

proc encodeBytes*(value: CustomType1,
                  contentType: string): RestResult[seq[byte]] =
  discard

proc encodeBytes*(value: string,
                  contentType: string): RestResult[seq[byte]] =
  var res: seq[byte]
  if len(value) > 0:
    res = newSeq[byte](len(value))
    copyMem(addr res[0], unsafeAddr value[0], len(value))
  ok(res)

proc encodeString*(value: CustomType1): RestResult[string] =
  case value.kind
  of CustomKind.Level1:
    ok("p1_" & Base10.toString(uint64(value.level1)))
  of CustomKind.Level2:
    ok("p2_" & value.level2)
  of CustomKind.Level3:
    ok("p3_" & toHex(value.level3))

proc encodeString*(value: int): RestResult[string] =
  if value < 0:
    err("Negative integer")
  else:
    ok(Base10.toString(uint64(value)))

proc encodeString*(value: string): RestResult[string] =
  ok(value)

proc encodeString*(value: openArray[byte]): RestResult[string] =
  ok(toHex(value))

proc decodeString*(t: typedesc[int], value: string): RestResult[int] =
  var v: int
  if parseSaturatedNatural(value, v) == 0:
    err("Unable to decode decimal string")
  else:
    if v == high(int):
      err("Integer overflow")
    else:
      ok(v)

proc decodeString*(t: typedesc[string], value: string): RestResult[string] =
  return ok(value)

proc decodeString*(t: typedesc[seq[byte]],
                   value: string): RestResult[seq[byte]] =
  try:
    return ok(hexToSeqByte(value))
  except ValueError:
    discard
  err("Unable to decode hex string")

proc match*(value: string, charset: set[char]): bool =
  for ch in value:
    if ch notin charset:
      return false
  true

proc testValidate*(pattern: string, value: string): int =
  let res =
    case pattern
    of "{pat1}":
      if value.startsWith("p1_"): 0 else: 1
    of "{pat2}":
      if value.startsWith("p2_"): 0 else: 1
    of "{pat3}":
      if value.startsWith("p3_"): 0 else: 1
    of "{smp1}":
      if value.match({'0' .. '9'}): 0 else: 1
    of "{smp2}":
      0
    of "{smp3}":
      if value.match({'0' .. '9', 'a' .. 'f', 'A' .. 'F', 'x'}): 0 else: 1
    of "{let}":
      if value.match({'0' .. '9'}): 0 else: 1
    else:
      1
  res

proc `==`*(a, b: CustomType1): bool =
  (a.kind == b.kind) and
  (
    case a.kind
    of Level1:
      a.level1 == b.level1
    of Level2:
      a.level2 == b.level2
    of Level3:
      a.level3 == b.level3
  )

proc init*(t: typedesc[ClientResponse], status: int): ClientResponse =
  ClientResponse(status: status)

proc init*(t: typedesc[ClientResponse], status: int,
           headers: openArray[tuple[key, value: string]]): ClientResponse =
  let table = HttpTable.init(headers)
  ClientResponse(status: status, headers: table)

proc init*(t: typedesc[ClientResponse], status: int,
           data: string): ClientResponse =
  ClientResponse(status: status, data: data)

proc init*(t: typedesc[ClientResponse], status: int, data: string,
           headers: HttpTable): ClientResponse =
  ClientResponse(status: status, data: data, headers: headers)

proc init*(t: typedesc[ClientResponse], status: int, data: string,
           headers: openArray[tuple[key, value: string]]): ClientResponse =
  let table = HttpTable.init(headers)
  ClientResponse(status: status, data: data, headers: table)

proc httpClient*(server: TransportAddress, meth: HttpMethod, url: string,
                 body: string, ctype = "",
                 accept = "", encoding = "",
                 length = -1): Future[ClientResponse] {.async.} =
  var request = $meth & " " & $parseUri(url) & " HTTP/1.1\r\n"
  request.add("Host: " & $server & "\r\n")
  if len(encoding) == 0:
    if length >= 0:
      request.add("Content-Length: " & $length & "\r\n")
    else:
      request.add("Content-Length: " & $len(body) & "\r\n")
  if len(ctype) > 0:
    request.add("Content-Type: " & ctype & "\r\n")
  if len(accept) > 0:
    request.add("Accept: " & accept & "\r\n")
  if len(encoding) > 0:
    request.add("Transfer-Encoding: " & encoding & "\r\n")
  request.add("\r\n")

  if len(body) > 0:
    request.add(body)

  var headersBuf = newSeq[byte](4096)
  let transp = await connect(server)
  let wres {.used.} = await transp.write(request)
  let rlen = await transp.readUntil(addr headersBuf[0], len(headersBuf),
                                    HeadersMark)
  headersBuf.setLen(rlen)
  let resp = parseResponse(headersBuf, true)
  doAssert(resp.success())

  let headers =
    block:
      var res = HttpTable.init()
      for key, value in resp.headers(headersBuf):
        res.add(key, value)
      res

  let length = resp.contentLength()
  doAssert(length >= 0)
  let cresp =
    if length > 0:
      var dataBuf = newString(length)
      await transp.readExactly(addr dataBuf[0], len(dataBuf))
      ClientResponse.init(resp.code, dataBuf, headers)
    else:
      ClientResponse.init(resp.code, "", headers)
  await transp.closeWait()
  return cresp
