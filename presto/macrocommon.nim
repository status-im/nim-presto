#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import std/[macros, strutils]

proc makeProcName*(m, s: string): string =
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
    of Letters + Digits:
      if toUpper:
        res.add(toUpperAscii(c))
        toUpper = false
      else:
        res.add(c)
    else:
      discard
    inc(k, 1)
  res

proc getRestReturnType*(params: NimNode): NimNode =
  if not(isNil(params)) and (len(params) > 0) and not(isNil(params[0])) and
     (params[0].kind == nnkIdent):
    params[0]
  else:
    nil

iterator paramsIter*(params: NimNode): tuple[name, ntype: NimNode] =
  for i in 1 ..< params.len:
    let arg = params[i]
    let argType = arg[^2]
    for j in 0 ..< arg.len-2:
      yield (arg[j], argType)

proc isSimpleType*(typeNode: NimNode): bool =
  typeNode.kind == nnkIdent

proc isOptionalArg*(typeNode: NimNode): bool =
  (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
    (typeNode[0].strVal == "Option")

proc isBytesArg*(typeNode: NimNode): bool =
  (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
    (typeNode[0].strVal == "seq") and (typeNode[1].kind == nnkIdent) and
    ((typeNode[1].strVal == "byte") or (typeNode[1].strVal == "uint8"))

proc isSequenceArg*(typeNode: NimNode): bool =
  (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
    (typeNode[0].strVal == "seq")

proc isContentBodyArg*(typeNode: NimNode): bool =
  (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
    (typeNode[0].strVal == "Option") and (typeNode[1].kind == nnkIdent) and
    (typeNode[1].strVal == "ContentBody")

proc isResponseArg*(typeNode: NimNode): bool =
  (typeNode.kind == nnkIdent) and (typeNode.strVal == "HttpResponseRef")

proc getSequenceType*(typeNode: NimNode): NimNode =
  if (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
     (typeNode[0].strVal == "seq"):
    typeNode[1]
  else:
    nil

proc getOptionType*(typeNode: NimNode): NimNode =
  if (typeNode.kind == nnkBracketExpr) and (typeNode[0].kind == nnkIdent) and
     (typeNode[0].strVal == "Option"):
    typeNode[1]
  else:
    nil

proc isPathArg*(typeNode: NimNode): bool =
  isBytesArg(typeNode) or (not(isOptionalArg(typeNode)) and
                           not(isSequenceArg(typeNode)))
