import std/parseutils
import pkg/presto
import pkg/stew/byteutils

# Decoders for the types used as parameters in this file.

# ANCHOR: decode_int
proc decodeString*(t: typedesc[int], value: string): RestResult[int] =
  var v: int
  if parseSaturatedNatural(value, v) == 0:
    err("Unable to decode decimal string")
  else:
    ok(v)
# ANCHOR_END: decode_int

proc decodeString*(t: typedesc[string], value: string): RestResult[string] =
  ok(value)

proc decodeString*(t: typedesc[seq[byte]],
                   value: string): RestResult[seq[byte]] =
  try:
    ok(hexToSeqByte(value))
  except ValueError:
    err("Unable to decode hex string")

# ANCHOR: validate
proc validate(pattern: string, value: string): int =
  case pattern
  of "{id}":
    # only accept numeric ids
    if value.allCharsInSet({'0' .. '9'}): 0 else: 1
  else:
    1
# ANCHOR_END: validate

var router = RestRouter.init(validate)

# ANCHOR: ping
router.api(MethodGet, "/ping") do () -> RestApiResponse:
  RestApiResponse.response("pong", Http200, "text/plain")
# ANCHOR_END: ping

# ANCHOR: path
router.api(MethodGet, "/users/{id}") do (id: int) -> RestApiResponse:
  if id.isErr():
    return RestApiResponse.error(Http400, $id.error())
  RestApiResponse.response("user " & $id.get())
# ANCHOR_END: path

# ANCHOR: query
router.api(MethodGet, "/search") do (
    q: Option[string], tag: seq[string]) -> RestApiResponse:
  # q is Option[Result[string]]: present? then decoded?
  let query =
    if q.isSome(): q.get().get() else: ""
  # tag collects ?tag=a&tag=b&tag=c into @["a", "b", "c"]
  RestApiResponse.response("searching " & query & " in " & $tag)
# ANCHOR_END: query

# ANCHOR: body
router.api(MethodPost, "/echo") do (
    contentBody: Option[ContentBody]) -> RestApiResponse:
  if contentBody.isNone():
    return RestApiResponse.error(Http400, "body required")
  let body = contentBody.get()
  echo "content-type: ", body.contentType
  RestApiResponse.response(string.fromBytes(body.data))
# ANCHOR_END: body

# ANCHOR: resp
router.api(MethodGet, "/stream") do (
    resp: HttpResponseRef) -> RestApiResponse:
  await resp.sendBody("streamed")
  RestApiResponse.response("")  # ignored: already responded
# ANCHOR_END: resp

# ANCHOR: keyword
router.api(MethodGet, "/kw/{type}") do (`type`: string) -> RestApiResponse:
  RestApiResponse.response(`type`.get())
# ANCHOR_END: keyword

# ANCHOR: responses
discard RestApiResponse.response("hello")                       # 200, text/plain
discard RestApiResponse.response("{}", Http201, "application/json")
discard RestApiResponse.response("body", Http200,
                                 headers = [("X-Custom", "1")])  # extra headers
discard RestApiResponse.response(Http204)                        # no body
# ANCHOR_END: responses

# ANCHOR: errors
discard RestApiResponse.error(Http404, "not found")
discard RestApiResponse.error(Http500, "boom", "text/plain",
                              headers = [("Retry-After", "5")])
# ANCHOR_END: errors

# ANCHOR: redirects
discard RestApiResponse.redirect(Http307, "/new/location")
discard RestApiResponse.redirect(Http307, "/new/location", preserveQuery = true)
# ANCHOR_END: redirects

# ANCHOR: negotiate
const
  typeJson = MediaType.init("application/json")
  typeText = MediaType.init("text/plain")

router.api(MethodGet, "/negotiate") do () -> RestApiResponse:
  let preferred = preferredContentType(typeJson, typeText)
  if preferred.isErr():
    return RestApiResponse.error(Http406, "")
  if preferred.get() == typeJson:
    RestApiResponse.response("{}", Http200, "application/json")
  else:
    RestApiResponse.response("ok", Http200, "text/plain")
# ANCHOR_END: negotiate

# ANCHOR: raw
router.rawApi(MethodPost, "/raw") do () -> RestApiResponse:
  let contentType = request.headers.getString("content-type")
  let body = await request.getBody()
  RestApiResponse.response("got " & $len(body) & " bytes of " & contentType)
# ANCHOR_END: raw

# ANCHOR: route_redirect
router.redirect(MethodGet, "/old/{id}", "/api/v2/items/{id}")
# ANCHOR_END: route_redirect
