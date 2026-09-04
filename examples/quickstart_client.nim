import pkg/presto/[common, client]

proc decodeBytes*(t: typedesc[string], value: openArray[byte],
                  contentType: Opt[ContentTypeData]): RestResult[string] =
  var res: string
  if len(value) > 0:
    res = newString(len(value))
    copyMem(addr res[0], unsafeAddr value[0], len(value))
  ok(res)

proc getRoot(): string {.rest, endpoint: "/", meth: MethodGet.}

proc main() {.async.} =
  let client = RestClientRef.new(initTAddress("127.0.0.1:9000"))
  echo await client.getRoot()
  await client.closeWait()

waitFor main()
