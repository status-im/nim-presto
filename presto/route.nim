#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)

import std/[macros, options]
import chronos, chronos/apps/http/[httpcommon, httptable, httpclient]
import httputils
import stew/bitops2
import btrees
import common, segpath, macrocommon

export chronos, options, common, httpcommon, httptable

type
  RestApiCallback* =
    proc(request: HttpRequestRef, pathParams: HttpTable,
         queryParams: HttpTable,
         body: Option[ContentBody]): Future[RestApiResponse] {.
      raises: [Defect], gcsafe.}

  RestRouteKind* {.pure.} = enum
    None, Handler, Redirect

  RestRouterFlag* {.pure.} = enum
    Raw

  RestRoute* = object
    requestPath*: SegmentedPath
    routePath*: SegmentedPath
    callback*: RestApiCallback
    flags*: set[RestRouterFlag]

  RestRouteItem* = object
    case kind*: RestRouteKind
    of RestRouteKind.None:
      discard
    of RestRouteKind.Handler:
      callback: RestApiCallback
    of RestRouteKind.Redirect:
      redirectPath*: SegmentedPath
    path: SegmentedPath
    flags*: set[RestRouterFlag]

  RestRouter* = object
    patternCallback*: PatternCallback
    routes*: BTree[SegmentedPath, RestRouteItem]
    allowedOrigin*: Option[string]

proc init*(t: typedesc[RestRouter],
           patternCallback: PatternCallback,
           allowedOrigin = none(string)): RestRouter {.raises: [Defect].} =
  doAssert(not(isNil(patternCallback)),
           "Pattern validation callback must not be nil")
  RestRouter(patternCallback: patternCallback,
             routes: initBTree[SegmentedPath, RestRouteItem](),
             allowedOrigin: allowedOrigin)

proc optionsRequestHandler(
       request: HttpRequestRef,
       pathParams: HttpTable,
       queryParams: HttpTable,
       body: Option[ContentBody]
     ): Future[RestApiResponse] {.async.} =
  return RestApiResponse.response("", Http200)

proc addRoute*(rr: var RestRouter, request: HttpMethod, path: string,
               flags: set[RestRouterFlag], handler: RestApiCallback) {.
     raises: [Defect].} =
  let spath = SegmentedPath.init(request, path, rr.patternCallback)
  let route = rr.routes.getOrDefault(spath,
                                     RestRouteItem(kind: RestRouteKind.None))
  case route.kind
  of RestRouteKind.None:
    let item = RestRouteItem(kind: RestRouteKind.Handler,
                             path: spath, flags: flags, callback: handler)
    rr.routes.add(spath, item)

    if rr.allowedOrigin.isSome:
      let
        optionsPath = SegmentedPath.init(
          MethodOptions, path, rr.patternCallback)
        optionsRoute = rr.routes.getOrDefault(
          optionsPath, RestRouteItem(kind: RestRouteKind.None))
      case route.kind
      of RestRouteKind.None:
        let optionsHandler = RestRouteItem(kind: RestRouteKind.Handler,
                                           path: optionsPath,
                                           flags: {RestRouterFlag.Raw},
                                           callback: optionsRequestHandler)
        rr.routes.add(optionsPath, optionsHandler)
      else:
        # This may happen if we use the same URL path in separate GET and
        # POST handlers. Reusing the previously installed OPTIONS handler
        # is perfectly fine.
        discard
  else:
    raiseAssert("The route is already in the routing table")

proc addRoute*(rr: var RestRouter, request: HttpMethod, path: string,
               handler: RestApiCallback) {.raises: [Defect].} =
  addRoute(rr, request, path, {}, handler)

proc addRedirect*(rr: var RestRouter, request: HttpMethod, srcPath: string,
                  dstPath: string) {.raises: [Defect].} =
  let spath = SegmentedPath.init(request, srcPath, rr.patternCallback)
  let dpath = SegmentedPath.init(request, dstPath, rr.patternCallback)
  let route = rr.routes.getOrDefault(spath,
                                     RestRouteItem(kind: RestRouteKind.None))
  case route.kind
  of RestRouteKind.None:
    let item = RestRouteItem(kind: RestRouteKind.Redirect,
                             path: spath, redirectPath: dpath)
    rr.routes.add(spath, item)
  else:
    raiseAssert("The route is already in the routing table")

proc getRoute*(rr: RestRouter,
               spath: SegmentedPath): Option[RestRoute] {.raises: [Defect].} =
  var path = spath
  while true:
    let route = rr.routes.getOrDefault(path,
                                       RestRouteItem(kind: RestRouteKind.None))
    case route.kind
    of RestRouteKind.None:
      return none[RestRoute]()
    of RestRouteKind.Handler:
      # Route handler was found
      let item = RestRoute(requestPath: path, routePath: route.path,
                           flags: route.flags, callback: route.callback)
      return some(item)
    of RestRouteKind.Redirect:
      # Route redirection was found, so we perform path transformation
      path = rewritePath(route.path, route.redirectPath, path)

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

macro redirect*(router: RestRouter, meth: static[HttpMethod],
                fromPath: static[string], toPath: static[string]): untyped =
  ## Define REST API endpoint which redirects request to different compatible
  ## endpoint ("/somecall" will be redirected to "/api/somecall").
  let
    srcPathStr = $fromPath
    dstPathStr = $toPath
    srcSegPath = SegmentedPath.init(meth, srcPathStr, nil)
    dstSegPath = SegmentedPath.init(meth, dstPathStr, nil)
    # Not sure about this, it creates HttpMethod(int).
    methIdent = newLit(meth)

  if not(isEqual(srcSegPath, dstSegPath)):
    error("Source and destination path patterns should be equal", router)

  var res = newStmtList()
  res.add quote do:
    `router`.addRedirect(`methIdent`, `fromPath`, `toPath`)

  when defined(nimDumpRest):
    echo "\n", fromPath, ": ", repr(res)
  return res

proc processApiCall(router: NimNode, meth: HttpMethod,
                    path: string, flags: set[RestRouterFlag],
                    body: NimNode): NimNode {.compileTime.} =
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
          if paramType.isKnownType("HttpResponseRef"):
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
    if not returnType.isKnownType("RestApiResponse"):
      error("Return value must be equal to [RestApiResponse]", returnType)

  # "path" (required) arguments unmarshalling code.
  let pathDecoder =
    block:
      var res = newStmtList()
      for (paramName, paramType) in pathArguments:
        let strName = newStrLitNode($paramName)
        res.add(quote do:
          let `paramName` {.used.}: Result[`paramType`, cstring] =
            decodeString(`paramType`, `pathParams`.getString(`strName`))
        )
      res

  # "query" (optional) arguments unmarshalling code.
  let optDecoder =
    block:
      var res = newStmtList()
      for (paramName, paramType) in optionalArguments:
        let strName = newStrLitNode($paramName)
        if isOptionalArg(paramType):
          # Optional arguments which has type `Option[T]`.
          let optType = getOptionType(paramType)
          res.add(quote do:
            let `paramName` {.used.}: Option[Result[`optType`, cstring]] =
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
            let `paramName` {.used.}: Result[`paramType`, cstring] =
              block:
                var sres: seq[`seqType`]
                var errorMsg: cstring = nil
                for item in `queryParams`.getList(`strName`).items():
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
          let `bodyArgument` {.used.}: Option[ContentBody] = `bodyParam`
        )
      res

  # `HttpResponseRef` argument unmarshalling code.
  let respDecoder =
    block:
      var res = newStmtList()
      if not(isNil(respArgument)):
        res.add(quote do:
          let `respArgument` {.used.}: HttpResponseRef =
            `requestParam`.getResponse()
        )
      res

  var res = newStmtList()
  res.add quote do:
    proc `doMain`(`requestParam`: HttpRequestRef, `pathParams`: HttpTable,
                  `queryParams`: HttpTable,
                  `bodyParam`: Option[ContentBody]
                 ): Future[RestApiResponse] {.raises: [Defect], async.} =
      template preferredContentType(
        t: varargs[MediaType]): Result[MediaType, cstring] {.used.} =
        `requestParam`.preferredContentType(t)
      `pathDecoder`
      `optDecoder`
      `respDecoder`
      `bodyDecoder`
      block:
        `procBody`

    `router`.addRoute(`methIdent`, `path`, `flags`, `doMain`)

  when defined(nimDumpRest):
    echo "\n", path, ": ", repr(res)
  return res

macro api*(router: RestRouter, meth: static[HttpMethod],
           path: static[string], body: untyped): untyped =
  return processApiCall(router, meth, path, {}, body)

macro rawApi*(router: RestRouter, meth: static[HttpMethod],
              path: static[string], body: untyped): untyped =
  return processApiCall(router, meth, path, {RestRouterFlag.Raw}, body)
