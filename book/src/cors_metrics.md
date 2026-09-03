# CORS and metrics

<!-- toc -->

## CORS

Browsers restrict cross-origin requests unless the server opts in with the
appropriate `Access-Control-Allow-Origin` header. Presto handles this at the
router level: pass an `allowedOrigin` when you initialize the router with
[`RestRouter.init`](api/presto/route.html#init%2Ctypedesc%5BRestRouter%5D%2CPatternCallback).

```nim
{{#shiftinclude auto:../../examples/advanced_cors.nim:cors}}
```

When `allowedOrigin` is set, Presto:

- automatically registers an `OPTIONS` handler for every route you add, so
  CORS preflight requests are answered without any extra code;
- adds `Access-Control-Allow-Origin` to responses when the request's `Origin`
  matches the configured value.

The matching rules are:

- `allowedOrigin = some("*")` allows any origin and echoes `*` back.
- Otherwise the request `Origin` must match the configured value. A matching
  response also sets `Vary: Origin` to avoid cache poisoning. The configured
  value may be given with or without an `http://` / `https://` scheme.
- A request carrying more than one `Origin` header is rejected with
  `400 Bad Request`.

```admonish note
`allowedOrigin` is applied by the router and the server together. If you serve a
router as [middleware](./middleware.md), the same CORS behavior applies.
```

## Metrics

Presto can expose operational metrics through the
[nim-metrics](https://github.com/status-im/nim-metrics) library. Metrics
collection is a compile-time feature: build with `-d:metrics` to enable it.
Without that flag, all the metrics machinery compiles away to nothing.

### Server metrics

The server can record, per endpoint:

- the number of responses, labelled by HTTP status;
- the time taken to prepare each response.

It also maintains global counters for processed, missing (404), and invalid
(400) requests.

Per-route recording is opt-in through the metrics variants of the routing
macros. Pass a set of
[`RestServerMetricsType`](api/presto/common.html#RestServerMetricsType) values
(`Status`, `Response`, or the combined `RestServerMetrics`) to
[`metricsApi`](api/presto/route.html#metricsApi-macros-all):

```nim
{{#shiftinclude auto:../../examples/advanced_metrics_server.nim:metrics}}
```

A [`rawMetricsApi`](api/presto/route.html#rawMetricsApi-macros-all) variant
exists for raw handlers, mirroring [`rawApi`](./routing.md#raw-routes).

### Client metrics

On the client, metrics are enabled per procedure with the
[`metrics`](api/client.html#metrics-templates-all) pragma. The client can record
DNS resolution time, connection time, request time, response time, and response
status, each labelled by an endpoint name.

```nim
{{#shiftinclude auto:../../examples/advanced_metrics_client.nim:metrics}}
```

The available [`RestClientMetricsType`](api/client.html#RestClientMetricsType)
values are `ResolveTime`, `ConnectTime`, `RequestTime`, `ResponseTime`, and
`Status`; `RestClientMetricsAllTypes` is the full set and is used when
`metricsTypes` is omitted.
