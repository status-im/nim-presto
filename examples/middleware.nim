import pkg/chronos/apps/http/httpserver
import pkg/presto
import pkg/presto/middleware

proc decodeString*(t: typedesc[int], value: string): RestResult[int] =
  try:
    ok(parseInt(value))
  except ValueError:
    err("not an integer")

proc validate(pattern: string, value: string): int = 0

# ANCHOR: wrap
var router = RestRouter.init(validate)
router.api(MethodGet, "/api/{id}") do (id: int) -> RestApiResponse:
  RestApiResponse.response("item " & $id.get())

let restMiddleware = RestServerMiddlewareRef.new(router)
# ANCHOR_END: wrap

# ANCHOR: process
proc process(r: RequestFence): Future[HttpResponseRef] {.
    async: (raises: [CancelledError]).} =
  if r.isOk():
    let request = r.get()
    if request.uri.path == "/health":
      try:
        await request.respond(Http200, "ok")
      except HttpWriteError as exc:
        defaultResponse(exc)
    else:
      defaultResponse()   # -> 404
  else:
    defaultResponse()

let server = HttpServerRef.new(
  initTAddress("127.0.0.1:8080"), process,
  middlewares = [restMiddleware]).get()
server.start()
# ANCHOR_END: process
discard server
