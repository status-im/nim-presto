import pkg/chronos/apps/http/httpserver
import pkg/presto
import pkg/presto/middleware

proc decodeString*(t: typedesc[int], value: string): RestResult[int] =
  try:
    ok(parseInt(value))
  except ValueError:
    err("not an integer")

proc validate(pattern: string, value: string): int = 0

proc process(r: RequestFence): Future[HttpResponseRef] {.
    async: (raises: [CancelledError]).} =
  defaultResponse()

# ANCHOR: chain
var
  apiRouter = RestRouter.init(validate)
  adminRouter = RestRouter.init(validate)

apiRouter.api(MethodGet, "/api/{id}") do (id: int) -> RestApiResponse:
  RestApiResponse.response("api")

adminRouter.api(MethodPost, "/admin/{id}") do (
    id: int, contentBody: Option[ContentBody]) -> RestApiResponse:
  RestApiResponse.response("admin")

let server = HttpServerRef.new(
  initTAddress("127.0.0.1:8080"), process,
  middlewares = [
    RestServerMiddlewareRef.new(apiRouter),
    RestServerMiddlewareRef.new(adminRouter)
  ]).get()
# ANCHOR_END: chain
discard server
