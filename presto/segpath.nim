#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import std/[uri, strutils]
import stew/bitops2
import chronos/apps
import common
export common, apps

{.push raises: [Defect].}

type
  PatternCallback* = proc(pattern: string,
                          value: string): int {.gcsafe, raises: [Defect].}

  SegmentedPath* = object
    data*: seq[string]
    patternCb: PatternCallback
    patterns*: uint64

template isPattern*(spath: SegmentedPath, pos: int): bool =
  (spath.patterns and (1'u64 shl pos)) != 0'u64

template hasPatterns*(spath: SegmentedPath): bool =
  spath.patterns != 0'u64

proc patternsCount*(spath: SegmentedPath): int =
  ## Returns number of patterns inside path ``spath``.
  spath.patterns.countOnes()

iterator keys*(spath: SegmentedPath): string =
  ## Iterate over all patterns in path ``spath``.
  var pats = spath.patterns
  while pats != 0'u64:
    let index = firstOne(pats) - 1
    doAssert(index < len(spath.data))
    doAssert(len(spath.data[index]) > 2)
    yield spath.data[index][1 .. ^2]
    pats = pats and not(1'u64 shl index)

proc getPatterns*(spath: SegmentedPath): seq[string] =
  ## Returns all the patterns in path ``spath``.
  var res = newSeq[string]()
  for item in spath.keys():
    res.add(item)
  res

proc `==`*(s1, s2: SegmentedPath): bool =
  if len(s1.data) == len(s2.data):
    if not(s1.hasPatterns()) and not(s2.hasPatterns()):
      s1.data == s2.data
    else:
      for i in 0 ..< len(s1.data):
        if s1.isPattern(i):
          if s2.isPattern(i):
            # comparison of segments with patterns
            if s1.data[i] != s2.data[i]:
              return false
          else:
            # comparison of pattern segment with value segment
            if s1.patternCb(s1.data[i], s2.data[i]) != 0:
              return false
        else:
          if s2.isPattern(i):
            # comparison of pattern segment with value segment
            if s2.patternCb(s2.data[i], s1.data[i]) != 0:
              return false
          else:
            # comparison of value segments
            if s1.data[i] != s2.data[i]:
              return false
      true
  else:
    false

proc `<`*(s1, s2: SegmentedPath): bool =
  let ls1 = len(s1.data)
  let ls2 = len(s2.data)
  if ls1 < ls2:
    # `s1` has less segments than `s2`
    true
  elif ls1 > ls2:
    # `s1` has more segments than `s2`
    false
  else:
    # `s1` and `s2` has equal number of segments.
    for i in 0 ..< ls1:
      if s1.isPattern(i):
        if s2.isPattern(i):
          # comparison of segments with patterns
          let res = cmp(s1.data[i], s2.data[i])
          if res != 0:
            return (res < 0)
        else:
          # comparison of pattern segment with value segment
          if s1.patternCb(s1.data[i], s2.data[i]) != 0:
            return false
      else:
        if s2.isPattern(i):
          # comparison of pattern segment with value segment
          if s2.patternCb(s2.data[i], s1.data[i]) != 0:
            return false
        else:
          # comparison of value segments
          let res = cmp(s1.data[i], s2.data[i])
          if res != 0:
            return (res < 0)
    false

proc init*(st: typedesc[SegmentedPath],
           upath: string): RestResult[SegmentedPath] =
  let res = SegmentedPath(patternCb: nil, patterns: 0'u64,
                          data: upath.split("/"))
  if len(res.data) <= 64:
    ok(res)
  else:
    err("Path has too many segments (more then 64)")

proc init*(st: typedesc[SegmentedPath],
           request: HttpMethod, upath: string): RestResult[SegmentedPath] =
  let path =
    if upath.startsWith('/'):
      $request & upath
    else:
      $request & "/" & upath
  init(st, path)

proc init*(st: typedesc[SegmentedPath],
           upath: string, patternCb: PatternCallback): SegmentedPath =
  var res = SegmentedPath(patternCb: patternCb, patterns: 0'u64)
  var counter = 0
  for item in upath.split("/"):
    doAssert(counter < 64, "Path has too many segments (more then 64)")
    if len(item) >= 2:
      if item[0] == '{' and item[^1] == '}':
        doAssert(len(item) > 2, "Patterns with empty names are not allowed")
        res.patterns = res.patterns or (1'u64 shl counter)
        res.data.add(item)
        inc(counter)
        continue
    res.data.add(encodeUrl(item))
    inc(counter)
  res

proc init*(st: typedesc[SegmentedPath], request: HttpMethod,
           upath: string, patternCb: PatternCallback): SegmentedPath =
  let path =
    if upath.startsWith('/'):
      $request & upath
    else:
      $request & "/" & upath
  SegmentedPath.init(path, patternCb)

proc `$`*(seg: SegmentedPath): string =
  seg.data.join("/")
