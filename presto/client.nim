#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import std/[macros, options, uri, sequtils]
import chronos, chronos/apps/http/[httpcommon, httptable, httpclient]
import httputils, stew/base10
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
  RestDecodingError* = object of RestError
  RestCommunicationError* = object of RestError
    exc*: ref HttpError
  RestResponseError* = object of RestError
    status*: int
    contentType*: string
    message*: string

const
  RestContentTypeArg = "restContentType"
  RestAcceptTypeArg = "restAcceptType"
  RestClientArg = "restClient"
  NotAllowedArgumentNames = [RestClientArg, RestContentTypeArg,
                             RestAcceptTypeArg]

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

proc createRequest*(client: RestClientRef, path: string, query: string,
                    contentType: string, acceptType: string,
                    meth: HttpMethod): HttpClientRequestRef =
  var address = client.address
  address.path = path
  address.query = query
  HttpClientRequestRef.new(client.session, address, meth,
                           headers = [("content-type", contentType),
                                      ("accept", acceptType)])

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
  var msg = "Unable to encode object to string, field "
  msg.add("[")
  msg.add(field)
  msg.add("]")
  let error = newException(RestEncodingError, msg)
  error.field = field
  raise error

proc raiseRestEncodingBytesError*(field: static string) {.
     noreturn, noinline.} =
  var msg = "Unable to encode object to bytes, field "
  msg.add("[")
  msg.add(field)
  msg.add("]")
  let error = newException(RestEncodingError, msg)
  error.field = field
  raise error

proc raiseRestCommunicationError*(exc: ref HttpError) {.
     noreturn, noinline.} =
  var msg = "Communication failed while sending/receiving request"
  msg.add(", http error [")
  msg.add(exc.name)
  msg.add("]")
  let error = newException(RestCommunicationError, msg)
  error.exc = exc
  raise error

proc raiseRestResponseError*(status: int, contentType: string,
                             message: openarray[byte]) {.
     noreturn, noinline.} =
  var msg = "Unsuccessfull response received"
  msg.add(", http code [")
  msg.add(Base10.toString(uint64(status)))
  msg.add("]")
  let error = newException(RestResponseError, msg)
  error.status = status
  error.contentType = contentType
  error.message = bytesToString(message)
  raise error

proc raiseRestDecodingBytesError*(message: cstring) {.noreturn, noinline.} =
  var msg = "Unable to decode REST response"
  msg.add(", error [")
  msg.add(message)
  msg.add("]")
  let error = newException(RestDecodingError, msg)
  raise error

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

proc transformProcDefinition(prc: NimNode, clientIdent: NimNode,
                             contentIdent: NimNode,
                             acceptIdent: NimNode,
                             stmtList: NimNode): NimNode {.compileTime.} =
  var procdef = copyNimTree(prc)
  var parameters = copyNimTree(prc.findChild(it.kind == nnkFormalParams))
  var pragmas = copyNimTree(prc.pragma())
  let clientArg =
    newTree(nnkIdentDefs, clientIdent, newIdentNode("RestClientRef"),
            newEmptyNode())
  let contentTypeArg =
    newTree(nnkIdentDefs, contentIdent, newIdentNode("string"),
            newStrLitNode("application/json"))
  let acceptTypeArg =
    newTree(nnkIdentDefs, acceptIdent, newIdentNode("string"),
            newStrLitNode("application/json"))

  let asyncPragmaArg = newIdentNode("async")

  var newParams =
    block:
      var res: seq[NimNode]
      for item in parameters:
        let includeParam =
          case item.kind
          of nnkIdentDefs:
            item[0].expectKind(nnkIdent)
            case item[0].strVal().toLowerAscii()
              of RestContentTypeArg, RestAcceptTypeArg, RestClientArg:
                false
              else:
                true
          else:
            true
        if includeParam:
          res.add(item)

      res[0] = newTree(nnkBracketExpr, newIdentNode("Future"), res[0])
      res.insert(clientArg, 1)
      res.add(contentTypeArg)
      res.add(acceptTypeArg)
      res

  var newPragmas =
    block:
      var res: seq[NimNode]
      res.add(asyncPragmaArg)
      for item in pragmas:
        let includePragma =
          case item.kind
          of nnkIdent:
            case item.strVal().toLowerAscii()
            of "rest", "async", "endpoint", "meth":
              false
            else:
              true
          of nnkExprColonExpr:
            item[0].expectKind(nnkIdent)
            case item[0].strVal().toLowerAscii()
            of "endpoint", "meth":
              false
            else:
              true
          else:
            true
        if includePragma:
           # We do not copy here, because we already copied original tree with
           # copyNimTree().
          res.add(item)
      res

  for index, item in procdef.pairs():
    case item.kind
    of nnkFormalParams:
      procdef[index] = newTree(nnkFormalParams, newParams)
    of nnkPragma:
      procdef[index] = newTree(nnkPragma, newPragmas)
    else:
      discard

  # We accept only `nnkProcDef` definitions, so we can use numeric index here
  procdef[6] = stmtList

  procdef

proc restSingleProc(prc: NimNode): NimNode {.compileTime.} =
  if prc.kind notin {nnkProcDef}:
    error("Cannot transform this node kind into an REST client procedure." &
          " Only `proc` definition expected.")
  let
    parameters = prc.findChild(it.kind == nnkFormalParams)
    requestPath = newIdentNode("requestPath")
    requestQuery = newIdentNode("requestQuery")
    requestIdent = newIdentNode("request")
    responseIdent = newIdentNode("response")
    responseCodeIdent = newIdentNode("responseCode")
    responseContentTypeIdent = newIdentNode("responseContentType")
    responseBytesIdent = newIdentNode("responseBytes")
    responseResultIdent = newIdentNode("responseResult")
    clientIdent = newIdentNode(RestClientArg)
    contentTypeIdent = newIdentNode(RestContentTypeArg)
    acceptTypeIdent = newIdentNode(RestAcceptTypeArg)

  var statements = newStmtList()

  block:
    let ares = prc.getAsyncPragma()
    if not(isNil(ares)):
      error("REST procedure should not have {.async.} pragma", ares)

  block:
    let bres = prc.findChild(it.kind == nnkStmtList)
    if not(isNil(bres)):
      error("REST procedure should not have body code", prc)

  let returnType =
    block:
      parameters.expectMinLen(1)
      if parameters[0].kind == nnkEmpty:
        error("REST procedure should not have empty return value", parameters)
      copyNimNode(parameters[0])

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

  let isPostMethod = meth.isPostMethod()

  let (bodyArgument, optionalArguments, pathArguments) =
    block:
      var bodyRes: Option[tuple[name, ntype, ename, literal: NimNode]]
      var optionalRes: seq[tuple[name, ntype, ename, literal: NimNode]]
      var pathRes: seq[tuple[name, ntype, ename, literal: NimNode]]
      for paramName, paramType in parameters.paramsIter():
        if $paramName in NotAllowedArgumentNames:
          error("Argument name is reserved name, please choose another one",
                paramName)
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
    let bodyItem = bodyArgument.get()
    let paramName = bodyItem.name
    let paramLiteral = bodyItem.literal
    let encodedName = bodyItem.ename

    if not(isPostMethod):
      error("Non-post method should not contain `body` argument", paramName)

    statements.add quote do:
      let `encodedName` =
        block:
          let res = encodeBytes(`paramName`, `contentTypeIdent`)
          if res.isErr():
            raiseRestEncodingBytesError(`paramLiteral`)
          res.get()
  else:
    if isPostMethod:
      error("POST/PUT/PATCH/DELETE requests must have `body` argument",
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
    let arrayItems = newArrayNode(optionalArguments.mapIt(it.ename))
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

  statements.add quote do:
    var `requestIdent` = createRequest(`clientIdent`, `requestPath`,
                                       `requestQuery`, `contentTypeIdent`,
                                       `acceptTypeIdent`, `meth`)
    var `responseIdent`: HttpClientResponseRef = nil

  if isPostMethod:
    let bodyIdent = bodyArgument.get().ename
    statements.add quote do:
      let (`responseCodeIdent`, `responseContentTypeIdent`,
           `responseBytesIdent`) =
        try:
          let chunkSize = `clientIdent`.session.connectionBufferSize
          # Sending request headers
          let writer = await `requestIdent`.open()
          # Writing request body
          var offset = 0
          while offset < len(`bodyIdent`):
            let toWrite = min(len(`bodyIdent`) - offset, chunkSize)
            await writer.write(unsafeAddr `bodyIdent`[offset], toWrite)
            offset = offset + toWrite
          # Receiving response
          `responseIdent` = await writer.finish()
          # Closing request object
          await `requestIdent`.closeWait()
          `requestIdent` = nil
          # Receiving response body
          let data = await `responseIdent`.getBodyBytes()
          let res = (
            `responseIdent`.status,
            `responseIdent`.headers.getString("content-type"),
            data
          )
          # Closing response object
          await `responseIdent`.closeWait()
          `responseIdent` = nil
          # Returning value
          res
        except CancelledError as exc:
          # Closing request and/or response objects to avoid connection leaks.
          if not(isNil(`requestIdent`)):
            await `requestIdent`.closeWait()
          if not(isNil(`responseIdent`)):
            await `responseIdent`.closeWait()
          raise exc
        except HttpError as exc:
          # Closing request and/or response objects to avoid connection leaks.
          if not(isNil(`requestIdent`)):
            await `requestIdent`.closeWait()
          if not(isNil(`responseIdent`)):
            await `responseIdent`.closeWait()
          raiseRestCommunicationError(exc)
  else:
    statements.add quote do:
      let (`responseCodeIdent`, `responseContentTypeIdent`,
           `responseBytesIdent`) =
        try:
          # Sending request headers and receiving response headers
          `responseIdent` = await `requestIdent`.send()
          # Closing request object
          await `requestIdent`.closeWait()
          `requestIdent` = nil
          # Receiving response body
          let data = await `responseIdent`.getBodyBytes()
          let res = (`responseIdent`.status,
                     `responseIdent`.headers.getString("content-type"),
                     data)
          # Closing response object
          await `responseIdent`.closeWait()
          `responseIdent` = nil
          # Returning value
          res
        except CancelledError as exc:
          # Closing request and/or response objects to avoid connection leaks.
          if not(isNil(`requestIdent`)):
            await `requestIdent`.closeWait()
          if not(isNil(`responseIdent`)):
            await `responseIdent`.closeWait()
          raise exc
        except HttpError as exc:
          # Closing request and/or response objects to avoid connection leaks.
          if not(isNil(`requestIdent`)):
            await `requestIdent`.closeWait()
          if not(isNil(`responseIdent`)):
            await `responseIdent`.closeWait()
          raiseRestCommunicationError(exc)

  statements.add quote do:
    if `responseCodeIdent` >= 200 and `responseCodeIdent` < 300:
      let `responseResultIdent` =
        block:
          let res = decodeBytes(`returnType`, `responseBytesIdent`,
                                `responseContentTypeIdent`)
          if res.isErr():
            raiseRestDecodingBytesError(res.error())
          res.get()
      return `responseResultIdent`
    else:
      raiseRestResponseError(`responseCodeIdent`, `responseContentTypeIdent`,
                             `responseBytesIdent`)

  let res = transformProcDefinition(prc, clientIdent, contentTypeIdent,
                                    acceptTypeIdent, statements)
  res

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
