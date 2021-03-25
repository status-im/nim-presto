import std/[strutils, parseutils]
import stew/byteutils
import ../presto/common

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
