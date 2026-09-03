import pkg/presto

proc decodeString*(t: typedesc[int], value: string): RestResult[int] =
  try:
    ok(parseInt(value))
  except ValueError:
    err("not an integer")

proc validate(pattern: string, value: string): int = 0

var router = RestRouter.init(validate)

# ANCHOR: metrics
router.metricsApi(MethodGet, "/items/{id}",
                  {RestServerMetricsType.Status}) do (
    id: int) -> RestApiResponse:
  RestApiResponse.response("item")

# record both status counts and response timing
router.metricsApi(MethodGet, "/report", RestServerMetrics) do () -> RestApiResponse:
  RestApiResponse.response("ok")
# ANCHOR_END: metrics
