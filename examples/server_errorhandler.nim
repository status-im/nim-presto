import pkg/presto

proc decodeString*(t: typedesc[string], value: string): RestResult[string] =
  ok(value)

proc validate(pattern: string, value: string): int = 0

# ANCHOR: handler
proc onError(kind: RestRequestError,
             request: HttpRequestRef): Future[HttpResponseRef] {.
    async: (raises: [CancelledError]).} =
  try:
    case kind
    of RestRequestError.Invalid:
      await request.respond(Http400, "invalid request")
    of RestRequestError.NotFound:
      await request.respond(Http404, "no such endpoint")
    of RestRequestError.InvalidContentBody:
      await request.respond(Http400, "bad body")
    of RestRequestError.InvalidContentType:
      await request.respond(Http400, "bad content-type")
    of RestRequestError.Unexpected:
      defaultResponse()
  except HttpError:
    defaultResponse()
# ANCHOR_END: handler

proc main() {.async.} =
  var router = RestRouter.init(validate)
  router.api(MethodGet, "/") do () -> RestApiResponse:
    RestApiResponse.response("ok")

  # ANCHOR: register
  let server = RestServerRef.new(
    router, initTAddress("127.0.0.1:8080"), requestErrorHandler = onError).get()
  # ANCHOR_END: register
  server.start()
  await server.closeWait()

waitFor main()
