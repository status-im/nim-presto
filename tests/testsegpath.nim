import std/[unittest, strutils]
import ../rest/segpath

when defined(nimHasUsed): {.used.}

proc validate(pattern: string, value: string): int =
  if len(value) > 0: 0 else: 1

proc createPatternsOnly(num: int, name = "pattern"): string =
  var res = ""
  for i in 0 .. num:
    res.add("/{" & name & $(i + 1) & "}")
  res

proc createPathOnly(num: int, name = "path"): string =
  var res = ""
  for i in 0 .. num:
    res.add("/" & name & $(i + 1))
  res

proc createNamesArray(num: int, name = "name"): seq[string] =
  var res: seq[string]
  for i in 0 .. num:
    res.add(name & $(i + 1))
  res

suite "SegmentedPath test suite":
  test "Empty patterns test":
    const EmptyVectors = [
      "/{}", "/path/{}", "{}", "/path1/path2/{}/path3",
      "/path1/path2/path3/{}/"
    ]
    for item in EmptyVectors:
      expect AssertionError:
        let path {.used.} = SegmentedPath.init(HttpMethod.MethodGet, item,
                                               validate)
  test "Too many segments path test":
    for i in 63 .. 128:
      expect AssertionError:
        let path {.used.} = SegmentedPath.init(createPatternsOnly(i), validate)
      expect AssertionError:
        let path {.used.} = SegmentedPath.init(createPathOnly(i), validate)

      let rpath1 = SegmentedPath.init(createPathOnly(i))
      check rpath1.isErr()
      let rpath2 = SegmentedPath.init(createPatternsOnly(i))
      check rpath2.isErr()

  test "Patterns bit test":
    for i in 0 .. 62:
      let names = createNamesArray(i, "pattern")
      let path = SegmentedPath.init(createPatternsOnly(i), validate)
      check:
        len(path.data) == (i + 2)
        path.getPatterns() == names
