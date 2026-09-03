import pkg/presto/[common, client]
import pkg/stew/base10

# Encoders for path/query parameters and bodies, and a decoder for responses.
proc encodeString*(value: int): RestResult[string] =
  if value < 0: err("Negative integer") else: ok(Base10.toString(uint64(value)))

proc encodeString*(value: string): RestResult[string] =
  ok(value)

proc encodeBytes*(value: string, contentType: string): RestResult[seq[byte]] =
  var res: seq[byte]
  if len(value) > 0:
    res = newSeq[byte](len(value))
    copyMem(addr res[0], unsafeAddr value[0], len(value))
  ok(res)

proc decodeBytes*(t: typedesc[string], value: openArray[byte],
                  contentType: Opt[ContentTypeData]): RestResult[string] =
  var res: string
  if len(value) > 0:
    res = newString(len(value))
    copyMem(addr res[0], unsafeAddr value[0], len(value))
  ok(res)

proc decodeBytes*(t: typedesc[int], value: openArray[byte],
                  contentType: Opt[ContentTypeData]): RestResult[int] =
  let res = Base10.decode(uint16, value)
  if res.isErr(): err(res.error()) else: ok(int(res.get()))

# ANCHOR: declare
proc getUser(id: int): string {.rest, endpoint: "/users/{id}".}
proc createUser(body: string): string {.
     rest, endpoint: "/users", meth: MethodPost.}
# ANCHOR_END: declare

# ANCHOR: returns
proc getStatus(): RestStatus {.rest, endpoint: "/health".}
proc getRaw(): RestPlainResponse {.rest, endpoint: "/blob".}
proc getTyped(): RestResponse[int] {.rest, endpoint: "/count".}
proc getStream(body: string): RestHttpResponseRef {.
     rest, endpoint: "/download", meth: MethodPost, accept: "*/*".}
# ANCHOR_END: returns

# ANCHOR: conn
proc oneShot(): RestPlainResponse {.
     rest, endpoint: "/once", connection: {Close}.}
# ANCHOR_END: conn

proc createClients() =
  # ANCHOR: create
  # from a transport address
  let client = RestClientRef.new(initTAddress("127.0.0.1:8080"))

  # from a URL (returns a Result)
  let client2 = RestClientRef.new("http://api.example.com/").get()

  # with flags
  let client3 = RestClientRef.new(
    initTAddress("127.0.0.1:8080"),
    HttpClientScheme.NonSecure,
    flags = {RestClientFlag.CommaSeparatedArray})
  # ANCHOR_END: create
  discard (client, client2, client3)

proc callEndpoints() {.async.} =
  # ANCHOR: call
  let client = RestClientRef.new(initTAddress("127.0.0.1:8080"))

  let user = await client.getUser(42)

  let created = await client.createUser(
    body = "{\"name\":\"Ada\"}",
    restContentType = "application/json",
    extraHeaders = @[("Authorization", "Bearer secret")])

  await client.closeWait()
  # ANCHOR_END: call
  discard (user, created)

proc streamResponse() {.async.} =
  let client = RestClientRef.new(initTAddress("127.0.0.1:8080"))
  # ANCHOR: stream
  let resp = await client.getStream("query")
  let reader = resp.getBodyReader()
  let chunk = await reader.read()
  await reader.closeWait()
  await resp.closeWait()
  # ANCHOR_END: stream
  discard chunk
  await client.closeWait()

proc handleErrors() {.async.} =
  let client = RestClientRef.new(initTAddress("127.0.0.1:8080"))
  # ANCHOR: errors
  try:
    let user = await client.getUser(99999)
    discard user
  except RestResponseError as exc:
    echo exc.status        # e.g. 404
    echo exc.message       # response body as text
    echo exc.contentType
  # ANCHOR_END: errors
  await client.closeWait()
