#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import chronos, chronos/apps
import std/[macros, options]
import stew/bitops2
import btrees
import common, segpath

export chronos, apps, options, common

type
  RestApiCallback* = proc(request: HttpRequestRef, pathParams: HttpTable,
                          queryParams: HttpTable,
                          body: Option[ContentBody]): Future[RestApiResponse] {.
                     gcsafe.}
  RestRoute* = object
    requestPath*: SegmentedPath
    routePath*: SegmentedPath
    callback*: RestApiCallback

  RestRouteItem* = object
    path: SegmentedPath
    callback: RestApiCallback

  RestRouter* = object
    patternCallback*: PatternCallback
    routes*: BTree[SegmentedPath, RestRouteItem]

proc init*(t: typedesc[RestRouter],
           patternCallback: PatternCallback): RestRouter {.raises: [Defect].} =
  doAssert(not(isNil(patternCallback)),
           "Pattern validation callback must not be nil")
  RestRouter(patternCallback: patternCallback,
             routes: initBTree[SegmentedPath, RestRouteItem]())

proc addRoute*(rr: var RestRouter, request: HttpMethod, path: string,
               handler: RestApiCallback) {.raises: [Defect].} =
  let spath = SegmentedPath.init(request, path, rr.patternCallback)
  let route = rr.routes.getOrDefault(spath)
  doAssert(isNil(route.callback), "The route is already in the routing table")
  rr.routes.add(spath, RestRouteItem(path: spath, callback: handler))

proc getRoute*(rr: RestRouter,
               spath: SegmentedPath): Option[RestRoute] {.raises: [Defect].} =
  let route = rr.routes.getOrDefault(spath)
  if isNil(route.callback):
    none[RestRoute]()
  else:
    some[RestRoute](RestRoute(requestPath: spath, routePath: route.path,
                              callback: route.callback))

iterator params*(route: RestRoute): string {.raises: [Defect].} =
  var pats = route.routePath.patterns
  while pats != 0'u64:
    let index = firstOne(pats) - 1
    if index >= len(route.requestPath.data):
      break
    yield route.requestPath.data[index]
    pats = pats and not(1'u64 shl index)

iterator pairs*(route: RestRoute): tuple[key: string, value: string] {.
  raises: [Defect].} =
  var pats = route.routePath.patterns
  while pats != 0'u64:
    let index = firstOne(pats) - 1
    if index >= len(route.requestPath.data):
      break
    let key = route.routePath.data[index][1 .. ^2]
    yield (key, route.requestPath.data[index])
    pats = pats and not(1'u64 shl index)

proc getParamsTable*(route: RestRoute): HttpTable {.raises: [Defect].} =
  var res = HttpTable.init()
  for key, value in route.pairs():
    res.add(key, value)
  res

proc getParamsList*(route: RestRoute): seq[string] {.raises: [Defect].} =
  var res: seq[string]
  for item in route.params():
    res.add(item)
  res

proc makeProcName(m, s: string): string =
  let path =
    if s.endsWith("/"):
      s & m.toLowerAscii()
    else:
      s & "/" & m.toLowerAscii()
  var res = "rest"
  var k = 0
  var toUpper = false
  while k < len(path):
    let c = path[k]
    case c
    of {'/', '{', '_'}:
      toUpper = true
      inc(k, 1)
    of Letters + Digits:
      if toUpper:
        res.add(toUpperAscii(c))
        toUpper = false
      else:
        res.add(c)
      inc(k, 1)
    else:
      inc(k, 1)
  res

proc getRestReturnType(params: NimNode): NimNode =
  if not(isNil(params)) and (len(params) > 0) and not(isNil(params[0])) and
     (params[0].kind == nnkIdent):
    params[0]
  else:
    nil

iterator paramsIter(params: NimNode): tuple[name, ntype: NimNode] =
  for i in 1 ..< params.len:
    let arg = params[i]
    let argType = arg[^2]
    for j in 0 ..< arg.len-2:
      yield (arg[j], argType)

proc isSimpleType(typeNode: NimNode): bool =
  typeNode.kind == nnkIdent

proc isOptionalArg(typeNode: NimNode): bool =
  (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
    (typeNode[0].strVal == "Option")

proc isBytesArg(typeNode: NimNode): bool =
  (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
    (typeNode[0].strVal == "seq") and (typeNode[1].kind == nnkIdent) and
    ((typeNode[1].strVal == "byte") or (typeNode[1].strVal == "uint8"))

proc isSequenceArg(typeNode: NimNode): bool =
  (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
    (typeNode[0].strVal == "seq")

proc isContentBodyArg(typeNode: NimNode): bool =
  (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
    (typeNode[0].strVal == "Option") and (typeNode[1].kind == nnkIdent) and
    (typeNode[1].strVal == "ContentBody")

proc isResponseArg(typeNode: NimNode): bool =
  (typeNode.kind == nnkIdent) and (typeNode.strVal == "HttpResponseRef")

proc getSequenceType(typeNode: NimNode): NimNode =
  if (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
     (typeNode[0].strVal == "seq"):
    typeNode[1]
  else:
    nil

proc getOptionType(typeNode: NimNode): NimNode =
  if (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
     (typeNode[0].strVal == "Option"):
    typeNode[1]
  else:
    nil

proc isPathArg(typeNode: NimNode): bool =
  isBytesArg(typeNode) or (not(isOptionalArg(typeNode)) and
                           not(isSequenceArg(typeNode)))

macro api*(router: RestRouter, meth: static[HttpMethod],
           path: static[string], body: untyped): untyped =
  ## Define REST API endpoint and implementation.
  ## Input and return parameters are defined using the ``do`` notation.
  ## For example:
  ## .. code-block:: nim
  ##    myServer.api(MethodGet, "path") do(p1: int, p2: float) -> string:
  ##      result = $param1 & " " & $param2
  ##    ```
  ## Input parameters are automatically marshalled to Nim types,
  ## and output parameters are automatically marshalled to json for transport.
  let
    parameters = body.findChild(it.kind == nnkFormalParams)
    pathStr = $path
    procNameStr = makeProcName($meth, pathStr)
    doMain = newIdentNode(procNameStr & "Handler")
    procBody =
      if body.kind == nnkStmtList:
        body
      else:
        body.body
    pathParams = newIdentNode("pathParams")
    queryParams = newIdentNode("queryParams")
    requestParam = newIdentNode("request")
    bodyParam = newIdentNode("bodyArg")
    spath = SegmentedPath.init(meth, pathStr, nil)
    # Not sure about this, it creates HttpMethod(int).
    methIdent = newLit(meth)

  var patterns = spath.getPatterns()

  # Validating and retrieve arguments.
  #
  # `bodyArgument` will hold name of `Option[ContentBody]` argument which
  # used to obtain request's content body.
  # `respArgument` will hold name of `HttpResponseRef` argument which used
  # to manipulate response.
  # `optionalArguments` will hold sequence of all the optional arguments.
  # `pathArguments` will hold sequence of all the path (required) arguments.
  let (bodyArgument, respArgument, optionalArguments, pathArguments) =
    block:
      var
        bodyRes: NimNode = nil
        respRes: NimNode = nil
        optionalRes: seq[tuple[name, ntype: NimNode]]
        pathRes: seq[tuple[name, ntype: NimNode]]

      for paramName, paramType in parameters.paramsIter():
        let index = patterns.find($paramName)
        if isPathArg(paramType):
          if isSimpleType(paramType) and
             (paramType.strVal == "HttpResponseRef"):
            if isNil(respRes):
              respRes = paramName
            else:
              error("There should be only one argument of " &
                    paramType.strVal & " type", paramType)
          else:
            let index = patterns.find($paramName)
            if index < 0:
              error("Argument \"" & $paramName & "\" not in the path!",
                    paramName)
            pathRes.add((paramName, paramType))
            patterns.del(index)
        else:
          if index >= 0:
            error("Argument \"" & $paramName & "\" has incorrect type",
                  paramName)

          if isContentBodyArg(paramType):
            if isNil(bodyRes):
              bodyRes = paramName
            else:
              error("There should be only one argument of " &
                    paramType.strVal & " type", paramType)
          elif isResponseArg(paramType):
            if isNil(respRes):
              respRes = paramName
            else:
              error("There should be only one argument of " &
                    paramType.strVal & " type", paramType)
          elif isOptionalArg(paramType) or isSequenceArg(paramType):
            optionalRes.add((paramName, paramType))

      (bodyRes, respRes, optionalRes, pathRes)

  # All "path" arguments should be present
  if len(patterns) != 0:
    error("Some of the arguments that are present in the path are missing: [" &
          patterns.join(", ") & "]", parameters)

  # Return type of the api call should be `RestApiResponse`.
  let returnType = parameters.getRestReturnType()
  if isNil(returnType):
    error("Return value must not be empty and equal to [RestApiResponse]",
           parameters)
  else:
    if returnType.strVal != "RestApiResponse":
      error("Return value must be equal to [RestApiResponse]", returnType)

  # "path" (required) arguments unmarshalling code.
  let pathDecoder =
    block:
      var res = newStmtList()
      for (paramName, paramType) in pathArguments:
        let strName = newStrLitNode(paramName.strVal)
        res.add(quote do:
          let `paramName`: Result[`paramType`, cstring] =
            decodeString(`paramType`, `pathParams`.getString(`strName`))
        )
      res

  # "query" (optional) arguments unmarshalling code.
  let optDecoder =
    block:
      var res = newStmtList()
      for (paramName, paramType) in optionalArguments:
        let strName = newStrLitNode(paramName.strVal)
        if isOptionalArg(paramType):
          # Optional arguments which has type `Option[T]`.
          let optType = getOptionType(paramType)
          res.add(quote do:
            let `paramName`: Option[Result[`optType`, cstring]] =
              if `strName` notin `queryParams`:
                none[Result[`optType`, cstring]]()
              else:
                some[Result[`optType`, cstring]](
                  decodeString(`optType`, `queryParams`.getString(`strName`))
                )
          )
        else:
          # Optional arguments which has type `seq[T]`.
          let seqType = getSequenceType(paramType)
          res.add(quote do:
            let `paramName`: Result[`paramType`, cstring] =
              block:
                var sres: seq[`seqType`]
                var errorMsg: cstring = nil
                for index, item in `queryParams`.getList(`strName`).pairs():
                  let res = decodeString(`seqType`, item)
                  if res.isErr():
                    errorMsg = res.error()
                    break
                  else:
                    sres.add(res.get())
                if isNil(errorMsg):
                  ok(Result[`paramType`, cstring], sres)
                else:
                  err(Result[`paramType`, cstring], errorMsg)
          )
      res

  # `ContentBody` unmarshalling code.
  let bodyDecoder =
    block:
      var res = newStmtList()
      if not(isNil(bodyArgument)):
        res.add(quote do:
          let `bodyArgument`: Option[ContentBody] = `bodyParam`
        )
      res

  # `HttpResponseRef` argument unmarshalling code.
  let respDecoder =
    block:
      var res = newStmtList()
      if not(isNil(respArgument)):
        res.add(quote do:
          let `respArgument`: HttpResponseRef = `requestParam`.getResponse()
        )
      res

  var res = newStmtList()
  res.add quote do:
    proc `doMain`(`requestParam`: HttpRequestRef, `pathParams`: HttpTable,
                  `queryParams`: HttpTable, `bodyParam`: Option[ContentBody]
                 ): Future[RestApiResponse] {.async.} =

      `pathDecoder`
      `optDecoder`
      `respDecoder`
      `bodyDecoder`
      `procBody`

    `router`.addRoute(`methIdent`, `path`, `doMain`)

  when defined(nimDumpRestAPI):
    echo "\n", path, ": ", repr(res)
  return res
