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
     (params[0].kind in {nnkIdent, nnkSym}):
    params[0]
  else:
    nil

iterator paramsIter*(params: NimNode): tuple[name, ntype: NimNode] =
  for i in 1 ..< params.len:
    let arg = params[i]
    let argType = arg[^2]
    for j in 0 ..< arg.len-2:
      yield (arg[j], argType)

proc isKnownType*(typeNode: NimNode, typeNames: varargs[string]): bool =
  typeNode.kind in {nnkIdent, nnkSym} and
  $typeNode in typeNames

proc isBracketExpr(n: NimNode, nodes: varargs[string]): bool =
  let leadingIdx = if n.kind == nnkBracketExpr:
    0
  elif n.kind == nnkCall and
       n[0].kind in {nnkOpenSymChoice, nnkClosedSymChoice} and
       n[0].len > 0 and
       $n[0][0] == "[]":
    1
  else:
    return false

  for idx, types in nodes:
    let actualIdx = leadingIdx + idx
    if actualIdx > n.len:
      return false
    if not isKnownType(n[actualIdx], types.split("|")):
      return false

  return true

proc isOptionalArg*(typeNode: NimNode): bool =
  typeNode.isBracketExpr "Option"

proc isBytesArg*(typeNode: NimNode): bool =
  typeNode.isBracketExpr("seq", "byte|uint8")

proc isSequenceArg*(typeNode: NimNode): bool =
  typeNode.isBracketExpr("seq")

proc isContentBodyArg*(typeNode: NimNode): bool =
  typeNode.isBracketExpr("Option", "ContentBody")

proc isResponseArg*(typeNode: NimNode): bool =
  typeNode.isKnownType "HttpResponseRef"

proc getSequenceType*(typeNode: NimNode): NimNode =
  if typeNode.isBracketExpr("seq"):
    typeNode[1]
  else:
    nil

proc getOptionType*(typeNode: NimNode): NimNode =
  if typeNode.isBracketExpr("Option"):
    typeNode[1]
  else:
    nil

proc isPathArg*(typeNode: NimNode): bool =
  isBytesArg(typeNode) or (not(isOptionalArg(typeNode)) and
                           not(isSequenceArg(typeNode)))
