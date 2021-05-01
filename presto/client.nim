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
import std/[macros, options, uri, sequtils]
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

proc raiseRestEncodingStringError*(field: static string) {.
     noreturn, noinline.} =
  let exc = newException(RestEncodingError, "Unable to encode object to string")
  exc.field = field
  raise exc

proc raiseRestEncodingBytesError*(field: static string) {.
     noreturn, noinline.} =
  let exc = newException(RestEncodingError, "Unable to encode object to bytes")
  exc.field = field
  raise exc

proc newArrayNode(nodes: openarray[NimNode]): NimNode =
  newTree(nnkBracket, @nodes)

proc isPostMethod(node: NimNode): bool {.compileTime.} =
  let methodName =
    if node.kind == nnkDotExpr:
      node.expectLen(2)
      node[1].expectKind(nnkIdent)
      node[1].strVal
    elif node.kind == nnkIdent:
      node.strVal
    else:
      ""
  case methodName
  of "MethodGet", "MethodHead", "MethodTrace", "MethodOptions", "MethodConnect":
    false
  of "MethodPost", "MethodPut", "MethodPatch", "MethodDelete":
    true
  else:
    false

proc restSingleProc(prc: NimNode): NimNode {.compileTime.} =
  let parameters = prc.findChild(it.kind == nnkFormalParams)
  let requestPath = newIdentNode("requestPath")
  let requestQuery = newIdentNode("requestQuery")
  var statements = newStmtList()

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

  let (bodyArgument, optionalArguments, pathArguments) =
    block:
      var bodyRes: Option[tuple[name, ntype, ename, literal: NimNode]]
      var optionalRes: seq[tuple[name, ntype, ename, literal: NimNode]]
      var pathRes: seq[tuple[name, ntype, ename, literal: NimNode]]
      for paramName, paramType in parameters.paramsIter():
        let literal = newStrLitNode($paramName)
        let index = patterns.find($paramName)
        if index >= 0:
          if isOptionalArg(paramType):
            error("Path argument could not be of Option[T] type",
                  paramName)
          if isSequenceArg(paramType) and not(isBytesArg(paramType)):
            error("Path argument could not be of iterable type")
          patterns.delete(index)
          let decodedName = newIdentNode($paramName & "PathEncoded")
          pathRes.add((paramName, paramType, decodedName, literal))
        else:
          let name = $paramName
          if name.startsWith("body"):
            if bodyRes.isSome():
              error("More then one body argument (starts with `body`) present",
                    paramName)
            let decodedName = newIdentNode($paramName & "BodyEncoded")
            bodyRes = some((paramName, paramType, decodedName, literal))
          else:
            let decodedName = newIdentNode($paramName & "OptEncoded")
            optionalRes.add((paramName, paramType, decodedName, literal))
      (bodyRes, optionalRes, pathRes)

  if len(patterns) != 0:
    error("Some of the arguments that are present in the path are missing: [" &
          patterns.join(", ") & "]", parameters)

  for item in pathArguments:
    let paramName = item.name
    let paramLiteral = item.literal
    let encodedName = item.ename

    statements.add quote do:
      let `encodedName` =
        block:
          let res = encodeString(`paramName`)
          if res.isErr():
            raiseRestEncodingStringError(`paramLiteral`)
          encodeUrl(res.get(), true)

  for item in optionalArguments:
    let paramName = item.name
    let paramLiteral = item.literal
    let encodedName = item.ename

    if isOptionalArg(item.ntype):
      statements.add quote do:
        let `encodedName` =
          block:
            if `paramName`.isSome():
              let res = encodeString(`paramName`.get())
              if res.isErr():
                raiseRestEncodingStringError(`paramLiteral`)
              var sres = `paramLiteral`
              sres.add('=')
              sres.add(encodeUrl(res.get(), true))
              sres
            else:
              ""
    elif isSequenceArg(item.ntype):
      if isBytesArg(item.ntype):
        statements.add quote do:
          let `encodedName` =
            block:
              let res = encodeString(`paramName`)
              if res.isErr():
                raiseRestEncodingStringError(`paramLiteral`)
              var sres = `paramLiteral`
              sres.add('=')
              sres.add(encodeUrl(res.get(), true))
              sres
      else:
        statements.add quote do:
          let `encodedName` =
            block:
              var res: seq[string]
              for item in `paramName`.items():
                let res = encodeString(item)
                if res.isErr():
                  raiseRestEncodingStringError(`paramLiteral`)
                var sres = `paramLiteral`
                sres.add('=')
                sres.add(encodeUrl(res.get(), true))
                res.add(sres)
              res.join("&")
    else:
      statements.add quote do:
        let `encodedName` =
          block:
            let res = encodeString(`paramName`)
            if res.isErr():
              raiseRestEncodingStringError(`paramLiteral`)
            var sres = `paramLiteral`
            sres.add('=')
            sres.add(encodeUrl(res.get(), true))
            sres

    if bodyArgument.isSome():
      let paramName = item.name
      let paramLiteral = item.literal
      let encodedName = item.ename

      if not(meth.isPostMethod()):
        error("Non-post method should not contain `body` argument", paramName)

      statements.add quote do:
        let `encodedName` =
          block:
            let res = encodeBytes(`paramName`, contentType)
            if res.isErr():
              raiseRestEncodingBytesError(`paramLiteral`)
            res.get()
    else:
      if meth.isPostMethod():
        error("POST/PUT/PATCH/DELETE methods must have `body` argument",
              parameters)

    if len(pathArguments) > 0:
      let pathLiteral = newStrLitNode(endpoint)
      let arrayItems = newArrayNode(
        pathArguments.mapIt(newPar(it.literal, it.ename))
      )
      statements.add quote do:
        let `requestPath` = createPath(`pathLiteral`, `arrayItems`)
    else:
      let pathLiteral = newStrLitNode(endpoint)
      statements.add quote do:
        let `requestPath` = `pathLiteral`

    if len(optionalArguments) > 0:
      let optionLiteral = newStrLitNode("")
      let arrayItems = newArrayNode(
        optionalArguments.mapIt(it.ename)
      )
      statements.add quote do:
        let `requestQuery` =
          block:
            let queryArgs = `arrayItems`
            var res: string
            for item in queryArgs:
              if len(item) > 0:
                if len(res) > 0:
                  res.add("&")
                res.add(item)
            res
    else:
      let optionLiteral = newStrLitNode("")
      statements.add quote do:
        let `requestQuery` = `optionLiteral`

  # echo treeRepr getAst(ac())
  # echo "endpoint = ", prc.getEndpoint()
  # echo treeRepr prc.getMethod()

  # let prcName = prc.name.getName
  echo repr statements
  # echo treeRepr statements
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

proc someProc(epoch: seq[byte], slot: uint64, data: int) {.
     rest, endpoint: "/api/eth/{epoch}/data/{slot}".} =
  discard

proc someProc(epoch: seq[byte], slot: uint64, data: int, body: int) {.
     rest, meth: MethodPost, endpoint: "/api/eth/{epoch}/data/{slot}".} =
  discard

proc someProc(epoch: seq[byte], slot: uint64, data: int, body: string) {.
     rest, meth: HttpMethod.MethodPost, endpoint: "/api/eth/{epoch}/data/{slot}".} =
  discard
