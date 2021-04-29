#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import chronos, chronos/apps/http/[httpcommon, httptable, httpclient]
import httputils
import std/[macros, options, uri]
import segpath, common, macrocommon
export httpclient, httptable, httpcommon, options, httputils

template endpoint*(v: string) {.pragma.}
template meth*(v: HttpMethod) {.pragma.}

type
  RestClient* = object of RootObj
    session: HttpSessionRef
    address: HttpAddress

  RestClientRef* = ref RestClient

  RestDefect* = object of Defect
  RestError* = object of CatchableError
  RestEncodingError* = object of RestError
    field*: cstring

proc new*(t: typedesc[RestClientRef],
          url: string,
          flags: HttpClientFlags = {},
          maxConnections: int = -1,
          maxRedirections: int = HttpMaxRedirections,
          connectTimeout = HttpConnectTimeout,
          headersTimeout = HttpHeadersTimeout,
          bufferSize: int = 4096
         ): RestResult[RestClientRef] =
  let session = HttpSessionRef.new(flags, maxRedirections, connectTimeout,
                                   headersTimeout, bufferSize, maxConnections)
  var uri = parseUri(url)
  uri.path = ""
  uri.query = ""
  uri.anchor = ""

  let address =
    block:
      let res = session.getAddress(uri)
      if res.isErr():
        return err("Unable to resolve remote hostname")
      res.get()
  var res = RestClientRef(session: session, address: address)
  ok(res)

proc getEndpointOrDefault(prc: NimNode,
                          default: string): string {.compileTime.} =
  let pragmaNode = prc.pragma()
  for node in pragmaNode.items():
    if node.kind == nnkExprColonExpr:
      if node[0].kind == nnkIdent and node[0].strVal() == "endpoint":
        return node[1].strVal()
  return default

proc getMethodOrDefault(prc: NimNode,
                        default: NimNode): NimNode {.compileTime.} =
  let pragmaNode = prc.pragma()
  for node in pragmaNode.items():
    if node.kind == nnkExprColonExpr:
      if node[0].kind == nnkIdent and node[0].strVal == "meth":
        return node[1]
  return default

proc getAsyncPragma(prc: NimNode): NimNode {.compileTime.} =
  let pragmaNode = prc.pragma()
  for node in pragmaNode.items():
    if node.kind == nnkIdent and node.strVal == "async":
      return node

proc raiseRestEncodingError*(field, message: cstring) {.
     noreturn, noinline.} =
  let exc = newException(RestEncodingError, message)
  exc.field = field
  raise exc

proc restSingleProc(prc: NimNode): NimNode {.compileTime.} =
  if prc.kind notin {nnkProcDef, nnkLambda, nnkMethodDef, nnkDo}:
    error("Cannot transform this node kind into an async proc." &
          " proc/method definition or lambda node expected.")
  block:
    let res = prc.getAsyncPragma()
    if not(isNil(res)):
      error("REST procedure should not have {.async.} pragma", res)
  let endpoint =
    block:
      let res = prc.getEndpointOrDefault("")
      if len(res) == 0:
        error("REST procedure should have non-empty {.endpoint.} pragma",
              prc.pragma())
      res
  let meth = prc.getMethodOrDefault(newDotExpr(ident("HttpMethod"),
                                               ident("MethodGet")))
  let spath = SegmentedPath.init(HttpMethod.MethodGet, endpoint, nil)
  var patterns = spath.getPatterns()

  echo patterns



  # echo treeRepr prc
  # echo "endpoint = ", prc.getEndpoint()
  # echo treeRepr prc.getMethod()

  # let prcName = prc.name.getName
  newStmtList()


template aa(f, v) =
  let res = encodeString(v)
  if res.isErr():
    raiseRestEncodingError(f, "Unable to stringify object")
  encodeUrl(res.get(), true)

template ab(f, v) =
  if v.isSome():
    let res = encodeString(v.get())
    if res.isErr():
      raiseRestEncodingError(f, "Unable to stringify object")
    f & "=" & encodeUrl(res.get(), true)
  else:
    ""



proc raiseTLSStreamProtocolError[T](message: T) {.noreturn, noinline.} =
  raise newTLSStreamProtocolImpl(message)

macro rest*(prc: untyped): untyped =
  let res =
    if prc.kind == nnkStmtList:
      var statements = newStmtList()
      for oneProc in prc:
        statements.add restSingleProc(oneProc)
      statements
    else:
      restSingleProc(prc)
  when defined(nimDumpRest):
    echo repr res
  res

proc someProc() {.rest, endpoint: "/api/eth/{epoch}".} =
  discard
