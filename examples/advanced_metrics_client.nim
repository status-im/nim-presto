import pkg/presto/[common, client]
import pkg/stew/base10

proc encodeString*(value: int): RestResult[string] =
  if value < 0: err("Negative integer") else: ok(Base10.toString(uint64(value)))

proc decodeBytes*(t: typedesc[string], value: openArray[byte],
                  contentType: Opt[ContentTypeData]): RestResult[string] =
  ok("")

# ANCHOR: metrics
# use the endpoint path as the metric label
proc getItem(id: int): RestPlainResponse {.
     rest, endpoint: "/items/{id}", metrics.}

# override the label
proc getItem2(id: int): RestPlainResponse {.
     rest, endpoint: "/items/{id}", metrics: "items_by_id".}

# select which metrics to collect
proc getItem3(id: int): RestPlainResponse {.
     rest, endpoint: "/items/{id}", metrics,
     metricsTypes: {RestClientMetricsType.ResponseTime,
                    RestClientMetricsType.Status}.}
# ANCHOR_END: metrics
