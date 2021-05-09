import std/[unittest, strutils, uri]
import ../presto/segpath

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

  test "Non-unique patterns test":
    const NonUniqueVectors = [
      "/{item1}/{item2}/{item1}",
      "/{i1}/{i1}",
      "/{a}/{b}/{a}"
    ]
    for item in NonUniqueVectors:
      expect AssertionError:
        let path {.used.} = SegmentedPath.init(HttpMethod.MethodGet, item,
                                               validate)
  test "Url-encoded path test":
    let path = encodeUrl("запрос1") & "/" & encodeUrl("запрос2") & "/" &
               encodeUrl("запрос3")
    let sres = SegmentedPath.init(path)
    check $sres.get() == "запрос1/запрос2/запрос3"

  test "createPath() test":
    const GoodVectors = [
      (
        "/{item1}/{item2}/data/path",
        @[("item1", "path1"), ("item2", "path2")],
        "/path1/path2/data/path"
      ),
      (
        "/data/path/{epoch}/{slot}",
        @[("epoch", "1"), ("slot", "2")],
        "/data/path/1/2"
      ),
      (
        "/data/path",
        @[],
        "/data/path"
      ),
      ("", @[], "")
    ]

    const BadVectors = [
      (
        "/{item1}/{item2}/{item1}",
        @[("item1", "path1"), ("item2", "path2")]
      ),
      (
        "/{item1}/data",
        @[("item1", "path1"), ("item2", "path2")]
      ),
      (
        "/{item1}/{item2}/data",
        @[("item1", "path1")]
      ),
      (
        "/{}/data",
        @[("", "path1")]
      )
    ]

    for item in GoodVectors:
      check createPath(item[0], item[1]) == item[2]

    for item in BadVectors:
      expect AssertionError:
        let path {.used.} = createPath(item[0], item[1])
