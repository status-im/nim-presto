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
import chronicles except error
import httputils, stew/base10
import segpath, common, macrocommon, agent
export httpclient, httptable, httpcommon, options, agent, httputils

template endpoint*(v: string) {.pragma.}
template meth*(v: HttpMethod) {.pragma.}
template accept*(v: string) {.pragma.}

type
  RestClient* = object of RootObj
    session*: HttpSessionRef
    address*: HttpAddress
    agent: string
    flags: RestClientFlags

  RestClientRef* = ref RestClient

  RestPlainResponse* = object
    status*: int
    contentType*: string
    data*: seq[byte]

  RestResponse*[T] = object
    status*: int
    contentType*: string
    data*: T

  RestStatus* = distinct int

  RestClientFlag* {.pure.} = enum
    CommaSeparatedArray

  RestClientFlags* = set[RestClientFlag]

  RestRequestFlag* {.pure.} = enum
    ConsumeBody

  RestReturnKind {.pure.} = enum
    Status, PlainResponse, GenericResponse, Value

const
  DefaultAcceptContentType = "application/json"
  RestContentTypeArg = "restContentType"
  RestAcceptTypeArg = "restAcceptType"
  RestClientArg = "restClient"
  ExtraHeadersArg = "extraHeaders"
  NotAllowedArgumentNames = [RestClientArg, RestContentTypeArg,
                             RestAcceptTypeArg]

chronicles.expandIt(HttpAddress):
  remote = it.hostname & ":" & Base10.toString(it.port)
  request = if len(it.query) == 0: it.path else: it.path & "?" & it.query

chronicles.formatIt(HttpClientConnectionRef):
  if isNil(it): Base10.toString(0'u64) else: Base10.toString(it.id)

proc `==`*(x, y: RestStatus): bool {.borrow.}
proc `<=`*(x, y: RestStatus): bool {.borrow.}
proc `<`*(x, y: RestStatus): bool {.borrow.}
proc `$`*(x: RestStatus): string {.borrow.}

proc new*(t: typedesc[RestClientRef],
          url: string,
          flags: RestClientFlags = {},
          httpFlags: HttpClientFlags = {},
          maxConnections: int = -1,
          maxRedirections: int = HttpMaxRedirections,
          connectTimeout = HttpConnectTimeout,
          headersTimeout = HttpHeadersTimeout,
          bufferSize: int = 4096,
          userAgent = PrestoIdent
         ): RestResult[RestClientRef] =
  let session = HttpSessionRef.new(httpFlags, maxRedirections, connectTimeout,
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
  ok(RestClientRef(session: session, address: address, agent: userAgent,
                   flags: flags))

proc new*(t: typedesc[RestClientRef],
          ta: TransportAddress,
          scheme: HttpClientScheme = HttpClientScheme.NonSecure,
          flags: RestClientFlags = {},
          httpFlags: HttpClientFlags = {},
          maxConnections: int = -1,
          maxRedirections: int = HttpMaxRedirections,
          connectTimeout = HttpConnectTimeout,
          headersTimeout = HttpHeadersTimeout,
          bufferSize: int = 4096,
          userAgent = PrestoIdent
         ): RestClientRef =
  let session = HttpSessionRef.new(httpFlags, maxRedirections, connectTimeout,
                                   headersTimeout, bufferSize, maxConnections)
  let address = ta.getAddress(scheme, "")
  RestClientRef(session: session, address: address, agent: userAgent,
                flags: flags)

proc closeWait*(client: RestClientRef) {.async.} =
  await client.session.closeWait()

proc createPostRequest*(client: RestClientRef, path: string, query: string,
                        contentType: string, acceptType: string,
                        extraHeaders: openArray[HttpHeaderTuple],
                        httpMethod: HttpMethod,
                        contentLength: uint64): HttpClientRequestRef =
  var address = client.address
  address.path = path
  address.query = query

  var headers = newSeqOfCap[HttpHeaderTuple](4 + extraHeaders.len)
  headers.add(("content-type", contentType))
  headers.add(("content-length", Base10.toString(contentLength)))
  headers.add(("accept", acceptType))
  headers.add(("user-agent", client.agent))
  headers.add extraHeaders

  HttpClientRequestRef.new(client.session, address, httpMethod,
                           headers = headers)

proc createGetRequest*(client: RestClientRef, path: string, query: string,
                       contentType: string, acceptType: string,
                       extraHeaders: openArray[HttpHeaderTuple],
                       httpMethod: HttpMethod): HttpClientRequestRef =
  var address = client.address
  address.path = path
  address.query = query

  var headers = newSeqOfCap[HttpHeaderTuple](2 + extraHeaders.len)
  headers.add(("accept", acceptType))
  headers.add(("user-agent", client.agent))
  headers.add extraHeaders

  HttpClientRequestRef.new(client.session, address, httpMethod,
                           headers = headers)

proc getEndpointOrDefault(prc: NimNode,
                          default: string): string {.compileTime.} =
  let pragmaNode = prc.pragma()
  for node in pragmaNode.items():
    if node.kind == nnkExprColonExpr:
      if (node[0].kind == nnkIdent) and (node[0].strVal() == "endpoint"):
        if node[1].kind != nnkStrLit:
          error("REST procedure {.endpoint.} pragma's value should be " &
                "string literal only", node[1])
        if len(node[1].strVal) == 0:
          error("REST procedure should have non-empty {.endpoint.} pragma",
                node[1])
        return node[1].strVal
  return default

proc getMethodOrDefault(prc: NimNode,
                        default: NimNode): NimNode {.compileTime.} =
  let pragmaNode = prc.pragma()
  for node in pragmaNode.items():
    if node.kind == nnkExprColonExpr:
      if node[0].kind == nnkIdent and node[0].strVal == "meth":
        return copyNimTree(node[1])
  return default

proc getAcceptOrDefault(prc: NimNode,
                        default: string): NimNode {.compileTime.} =
  let pragmaNode = prc.pragma()
  for node in pragmaNode.items():
    if node.kind == nnkExprColonExpr:
      if (node[0].kind == nnkIdent) and (node[0].strVal == "accept"):
        case node[1].kind
        of nnkStrLit:
          if len(node[1].strVal) > 0:
            return copyNimTree(node[1])
          error("REST procedure should have non-empty {.accept.} pragma",
                node[1])
        else:
          return copyNimTree(node[1])
  return newStrLitNode(default)

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
  var error = newException(RestEncodingError, msg)
  error.field = field
  raise error

proc raiseRestEncodingBytesError*(field: static string) {.
     noreturn, noinline.} =
  var msg = "Unable to encode object to bytes, field "
  msg.add("[")
  msg.add(field)
  msg.add("]")
  var error = newException(RestEncodingError, msg)
  error.field = field
  raise error

proc raiseRestCommunicationError*(exc: ref HttpError) {.
     noreturn, noinline.} =
  var msg = "Communication failed while sending/receiving request"
  msg.add(", http error [")
  msg.add(exc.name)
  msg.add("]: ")
  msg.add(exc.msg)
  var error = newException(RestCommunicationError, msg)
  error.exc = exc
  raise error

proc raiseRestCommunicationError*(exc: ref AsyncStreamError) {.
     noreturn, noinline.} =
  var msg = "Communication failed while sending request's body"
  msg.add(", stream error [")
  msg.add(exc.name)
  msg.add("]: ")
  msg.add(exc.msg)
  var error = newException(RestCommunicationError, msg)
  error.exc = exc
  raise error

proc raiseRestResponseError*(resp: RestPlainResponse) {.
     noreturn, noinline.} =
  var msg = "Unsuccessfull response received"
  msg.add(", http code [")
  msg.add(Base10.toString(uint64(resp.status)))
  msg.add("]")
  var error = newException(RestResponseError, msg)
  error.status = resp.status
  error.contentType = resp.contentType
  error.message = bytesToString(resp.data)
  raise error

proc raiseRestRedirectionError*(msg: string) {.
     noreturn, noinline.} =
  var msg = "Unable to follow redirect location, "
  msg.add(msg)
  raise (ref RestRedirectionError)(msg: msg)

proc raiseRestDecodingBytesError*(message: cstring) {.noreturn, noinline.} =
  var msg = "Unable to decode REST response"
  msg.add(", error [")
  msg.add(message)
  msg.add("]")
  raise (ref RestDecodingError)(msg: msg)

proc newArrayNode(nodes: openArray[NimNode]): NimNode =
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
                             extraHeadersIdent: NimNode,
                             acceptValue: NimNode,
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
  let extraHeadersArg =
    newTree(nnkIdentDefs, extraHeadersIdent,
            newTree(nnkBracketExpr, ident"seq", ident"HttpHeaderTuple"),
            newTree(nnkPrefix, ident"@", newTree(nnkBracket)))
  let acceptTypeArg =
    newTree(nnkIdentDefs, acceptIdent, newIdentNode("string"),
            acceptValue)

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
      res.add(extraHeadersArg)
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

template closeObjects(o1, o2, o3: untyped): untyped =
  if not(isNil(o1)):
    await o1.closeWait()
    o1 = nil
  if not(isNil(o2)):
    await o2.closeWait()
    o2 = nil
  if not(isNil(o3)):
    await o3.closeWait()
    o3 = nil

template closeObjects(o1, o2, o3, o4: untyped): untyped =
  if not(isNil(o1)):
    await o1.closeWait()
    o1 = nil
  if not(isNil(o2)):
    await o2.closeWait()
    o2 = nil
  if not(isNil(o3)):
    await o3.closeWait()
    o3 = nil
  if not(isNil(o4)):
    await o4.closeWait()
    o4 = nil

proc requestWithoutBody*(req: HttpClientRequestRef,
                         flags: set[RestRequestFlag]
                        ): Future[RestPlainResponse] {.
     async.} =
  var
    request = req
    redirect: HttpClientRequestRef = nil
    response: HttpClientResponseRef = nil
    address = request.address
  while true:
    try:
      debug "Sending REST request to remote server", address,
            http_method = $request.meth
      response = await request.send()
      debug "Got REST response headers from remote server",
            status = response.status, http_method = $request.meth, address,
            connection = request.connection
      if response.status >= 300 and response.status < 400:
        redirect =
          block:
            if "location" in response.headers:
              let location = response.headers.getString("location")
              if len(location) > 0:
                let res = request.redirect(parseUri(location))
                if res.isErr():
                  raiseRestRedirectionError(res.error())
                res.get()
              else:
                raiseRestRedirectionError("Location header with an empty value")
            else:
              raiseRestRedirectionError("Location header missing")
        discard await response.consumeBody()
        let redirectAddress = redirect.address
        debug "Got HTTP redirection from remote server",
              status = response.status, http_method = $request.meth,
              connection = request.connection, redirectAddress
        await request.closeWait()
        request = nil
        await response.closeWait()
        response = nil
        request = redirect
        redirect = nil
      else:
        let res =
          block:
            let status = response.status
            let contentType = response.headers.getString("content-type")
            let data =
              block:
                var default: seq[byte]
                if RestRequestFlag.ConsumeBody in flags:
                  discard await response.consumeBody()
                  default
                else:
                  await response.getBodyBytes()
            debug "Received REST response body from remote server",
                  status = response.status, http_method = $request.meth,
                  address, connection = request.connection,
                  contentType = contentType, size = len(data)
            await request.closeWait()
            request = nil
            await response.closeWait()
            response = nil
            RestPlainResponse(status: status, contentType: contentType,
                              data: data)
        return res
    except CancelledError as exc:
      # TODO: when `finally` proved to work inside loops, move closeWait() logic
      # to `finally` handler.
      debug "REST client request was interrupted", address,
            connection = request.connection
      closeObjects(request, redirect, response)
      raise exc
    except RestError as exc:
      debug "REST client redirection error", address,
            connection = request.connection, errorName = exc.name,
            errorMsg = exc.msg
      closeObjects(request, redirect, response)
      raise exc
    except HttpError as exc:
      debug "REST client communication error", address,
            connection = request.connection, errorName = exc.name,
            errorMsg = exc.msg
      closeObjects(request, redirect, response)
      raiseRestCommunicationError(exc)

proc requestWithBody*(req: HttpClientRequestRef, pbytes: pointer,
                      nbytes: uint64, chunkSize: int,
                      flags: set[RestRequestFlag]): Future[RestPlainResponse] {.
     async.} =
  doAssert(chunkSize > 0 and chunkSize <= high(int))
  var
    request = req
    redirect: HttpClientRequestRef = nil
    response: HttpClientResponseRef = nil
    writer: HttpBodyWriter = nil
    address = request.address
    pbuffer = cast[ptr UncheckedArray[byte]](pbytes)

  while true:
    try:
      debug "Sending REST request to remote server", address,
            http_method = $request.meth
      # Sending HTTP request headers and obtain HTTP request body writer
      writer = await request.open()
      debug "Opened connection to remote server", address,
            http_method = $request.meth, connection = request.connection
      # Sending HTTP request body
      var offset = 0'u64
      while offset < nbytes:
        let toWrite = int(min(nbytes - offset, uint64(chunkSize)))
        await writer.write(unsafeAddr pbuffer[offset], toWrite)
        offset = offset + uint64(toWrite)
      # Finishing HTTP request body
      debug "REST request body has been sent", address, size = nbytes,
             http_method = $request.meth, connection = request.connection
      await writer.finish()
      await writer.closeWait()
      writer = nil
      # Waiting for response headers
      response = await request.finish()
      debug "Got REST response headers from remote server",
            status = response.status, http_method = $request.meth,
            address, connection = request.connection
      if response.status >= 300 and response.status < 400:
        # Handling redirection
        redirect =
          block:
            if "location" in response.headers:
              let location = response.headers.getString("location")
              if len(location) > 0:
                let res = request.redirect(parseUri(location))
                if res.isErr():
                  raiseRestRedirectionError(res.error())
                res.get()
              else:
                raiseRestRedirectionError("Location header with an empty value")
            else:
              raiseRestRedirectionError("Location header missing")
        # We do not care about response body in redirection.
        discard await response.consumeBody()
        await request.closeWait()
        request = nil
        await response.closeWait()
        response = nil
        request = redirect
        redirect = nil
      else:
        let res =
          block:
            let status = response.status
            let contentType = response.headers.getString("content-type")
            let data =
              block:
                var default: seq[byte]
                if RestRequestFlag.ConsumeBody in flags:
                  discard await response.consumeBody()
                  default
                else:
                  await response.getBodyBytes()
            debug "Received REST response body from remote server",
                  contentType = contentType, size = len(data),
                  address, connection = request.connection
            await request.closeWait()
            request = nil
            await response.closeWait()
            response = nil
            RestPlainResponse(status: status, contentType: contentType,
                              data: data)
        return res
    except CancelledError as exc:
      # TODO: when `finally` proved to work inside loops, move closeWait() logic
      # to `finally` handler.
      debug "REST request was interrupted", address,
            connection = request.connection
      closeObjects(writer, request, redirect, response)
      raise exc
    except RestError as exc:
      debug "REST client redirection error", address,
            connection = request.connection, errorName = exc.name,
            errorMsg = exc.msg
      closeObjects(writer, request, redirect, response)
      raise exc
    except HttpError as exc:
      debug "REST client communication error", address,
            connection = request.connection, errorName = exc.name,
            errorMsg = exc.msg
      closeObjects(writer, request, redirect, response)
      raiseRestCommunicationError(exc)
    except AsyncStreamError as exc:
      # Because `HttpBodyWriter` is actually `AsyncStream` it could raise
      # `AsyncStreamError` exception. This can happen when we sending request's
      # body.
      debug "REST client communication error", address,
            connection = request.connection, errorName = exc.name,
            errorMsg = exc.msg
      closeObjects(writer, request, redirect, response)
      raiseRestCommunicationError(exc)
    except CatchableError as exc:
      debug "REST client got an unexpected error",
            address, connection = request.connection,
            errorName = exc.name, errorMsg = exc.msg
      closeObjects(writer, request, redirect, response)
      raise(exc)

proc restSingleProc(prc: NimNode): NimNode {.compileTime.} =
  if prc.kind notin {nnkProcDef}:
    error("Cannot transform this node kind into an REST client procedure." &
          " Only `proc` definition expected.")
  let
    parameters = prc.findChild(it.kind == nnkFormalParams)
    requestPath = newIdentNode("requestPath")
    requestQuery = newIdentNode("requestQuery")
    requestIdent = newIdentNode("request")
    requestFlagsIdent = newIdentNode("requestFlags")
    responseResultIdent = newIdentNode("responseResult")
    responseObjectIdent = newIdentNode("responseObject")
    clientIdent = newIdentNode(RestClientArg)
    contentTypeIdent = newIdentNode(RestContentTypeArg)
    acceptTypeIdent = newIdentNode(RestAcceptTypeArg)
    extraHeadersIdent = newIdentNode(ExtraHeadersArg)

  var statements = newStmtList()

  block:
    let ares = prc.getAsyncPragma()
    if not(isNil(ares)):
      error("REST procedure should not have {.async.} pragma", ares)

  block:
    let bres = prc.findChild(it.kind == nnkStmtList)
    if not(isNil(bres)):
      error("REST procedure should not have body code", prc)

  let (returnType, returnKind) =
    block:
      parameters.expectMinLen(1)
      if parameters[0].kind == nnkEmpty:
        error("REST procedure should non have empty return value", parameters)
      let node = copyNimTree(parameters[0])
      case node.kind
      of nnkIdent:
        case node.strVal()
        of "RestStatus":
          (node, RestReturnKind.Status)
        of "RestPlainResponse":
          (node, RestReturnKind.PlainResponse)
        else:
          (node, RestReturnKind.Value)
      of nnkBracketExpr:
        case node[0].strVal()
        of "RestResponse":
          (node[1], RestReturnKind.GenericResponse)
        else:
          (node, RestReturnKind.Value)
      else:
        (node, RestReturnKind.Value)

  let endpointValue = prc.getEndpointOrDefault("")
  let acceptValue = prc.getAcceptOrDefault(DefaultAcceptContentType)
  let methodValue = prc.getMethodOrDefault(newDotExpr(ident("HttpMethod"),
                                           ident("MethodGet")))
  let spath = SegmentedPath.init(HttpMethod.MethodGet, endpointValue, nil)
  var patterns = spath.getPatterns()

  let isPostMethod = methodValue.isPostMethod()

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
          res.get()

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
              if RestClientFlag.CommaSeparatedArray in `clientIdent`.flags:
                var res: seq[string]
                for item in `paramName`.items():
                  let eres = encodeString(item)
                  if eres.isErr():
                    raiseRestEncodingStringError(`paramLiteral`)
                  res.add(encodeUrl(eres.get(), true))
                if len(res) > 0:
                  var sres = `paramLiteral`
                  sres.add('=')
                  sres.add(res.join(","))
                  sres
                else:
                  ""
              else:
                var res: seq[string]
                for item in `paramName`.items():
                  let eres = encodeString(item)
                  if eres.isErr():
                    raiseRestEncodingStringError(`paramLiteral`)
                  var sres = `paramLiteral`
                  sres.add('=')
                  sres.add(encodeUrl(eres.get(), true))
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
    let pathLiteral = newStrLitNode(endpointValue)
    let arrayItems = newArrayNode(
      pathArguments.mapIt(newPar(it.literal, it.ename))
    )
    statements.add quote do:
      let `requestPath` = createPath(`pathLiteral`, `arrayItems`)
  else:
    let pathLiteral = newStrLitNode(endpointValue)
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

  case returnKind
  of RestReturnKind.Status:
    statements.add quote do:
      let `requestFlagsIdent`: set[RestRequestFlag] = {
        RestRequestFlag.ConsumeBody
      }
  else:
    statements.add quote do:
      let `requestFlagsIdent`: set[RestRequestFlag] = {}

  if isPostMethod:
    let bodyIdent = bodyArgument.get().ename
    statements.add quote do:
      let `responseObjectIdent` =
        block:
          let chunkSize = `clientIdent`.session.connectionBufferSize
          let `requestIdent` = createPostRequest(
            `clientIdent`, `requestPath`, `requestQuery`,
            `contentTypeIdent`, `acceptTypeIdent`,
            `extraHeadersIdent`, `methodValue`,
            uint64(len(`bodyIdent`))
          )
          await requestWithBody(`requestIdent`,
                                cast[pointer](unsafeAddr `bodyIdent`[0]),
                                uint64(len(`bodyIdent`)), chunkSize,
                                `requestFlagsIdent`)
  else:
    statements.add quote do:
      let `responseObjectIdent` =
        block:
          let `requestIdent` = createGetRequest(
            `clientIdent`, `requestPath`, `requestQuery`,
            `contentTypeIdent`, `acceptTypeIdent`,
            `extraHeadersIdent`, `methodValue`
          )
          await requestWithoutBody(`requestIdent`, `requestFlagsIdent`)

  case returnKind
  of RestReturnKind.Status:
    # Result will contain only HTTP status.
    statements.add quote do:
      return RestStatus(`responseObjectIdent`.status)
  of RestReturnKind.PlainResponse:
    # Result will contain HTTP status, HTTP content-type and sequence of bytes.
    statements.add quote do:
      return `responseObjectIdent`
  of RestReturnKind.GenericResponse:
    # Result will contain HTTP status, HTTP content-type and decoded value.
    statements.add quote do:
      let `responseResultIdent` =
        block:
          let res = decodeBytes(`returnType`, `responseObjectIdent`.data,
                                `responseObjectIdent`.contentType)
          if res.isErr():
            raiseRestDecodingBytesError(res.error())
          res.get()
      return RestResponse[`returnType`](
        status: `responseObjectIdent`.status,
        contentType: `responseObjectIdent`.contentType,
        data: `responseResultIdent`
      )
  of RestReturnKind.Value:
    # Result will be only decoded value, if HTTP status is not in [200, 299]
    # exception `RestResponseError` will be raised.
    statements.add quote do:
      if `responseObjectIdent`.status < 200 or
         `responseObjectIdent`.status >= 300:
        raiseRestResponseError(`responseObjectIdent`)
      let `responseResultIdent` =
        block:
          let res = decodeBytes(`returnType`, `responseObjectIdent`.data,
                                `responseObjectIdent`.contentType)
          if res.isErr():
            raiseRestDecodingBytesError(res.error())
          res.get()
      return `responseResultIdent`

  let res = transformProcDefinition(prc, clientIdent, contentTypeIdent,
                                    acceptTypeIdent, extraHeadersIdent,
                                    acceptValue, statements)
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
