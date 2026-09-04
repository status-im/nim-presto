# Client

<!-- toc -->

Presto ships with an HTTP client that is generated from your procedure
signatures. You describe _what_ a request looks like (its endpoint, method, and
parameters) and the [`rest`](api/client.html#rest-macros-all) macro writes the
code that builds the request, sends it, follows redirects, and decodes the
response into a Nim value. The client lives in the
[`presto/client`](api/client.html) module.

## Declaring client procedures

Annotate a procedure with `{.rest.}` and describe the request with pragmas. The
proc must have no body; the macro supplies one.

```nim
{{#shiftinclude auto:../../examples/client.nim:declare}}
```

Parameter names drive how each argument is used:

- a name that matches a `{pattern}` in `endpoint` fills that path segment;
- an argument named `body` (or starting with `body`) becomes the request body —
  only allowed for `POST`/`PUT`/`PATCH`/`DELETE`;
- any other argument becomes a query-string parameter. `Option[T]` makes it
  optional; `seq[T]` repeats the key.

Client-side values are converted with your `encodeString` (path/query) and
`encodeBytes` (body) procedures, and responses are decoded with `decodeBytes`.
See [the encode/decode contract](./routing.md#encoding-and-decoding-parameters).

### Pragmas

| Pragma                                                                                                                      | Purpose                                                                            |
| --------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| [`endpoint`](api/client.html#endpoint-templates-all) `: "/path/{x}"`                                                        | request path, with optional patterns                                               |
| [`meth`](api/client.html#meth-templates-all) `: MethodGet`                                                                  | HTTP method (defaults to `GET`)                                                    |
| [`accept`](api/client.html#accept-templates-all) `: "application/json"`                                                     | value of the `Accept` header (defaults to `application/json`)                      |
| [`connection`](api/client.html#connection-templates-all) `: {Dedicated}`                                                    | connection handling (see [Connection handling](#connection-handling))                                                    |
| [`metrics`](api/client.html#metrics-templates-all) / [`metricsTypes`](api/client.html#metricsTypes-templates-all) `: {...}` | enable client metrics for the call (see [CORS and metrics](./cors_metrics.md#metrics)) |

## Creating a client

[`RestClientRef.new`](api/client.html#new-procs-all) can be constructed from a
`TransportAddress`, from an `HttpAddress`, or from a URL string. The URL form
returns a `Result` because it resolves the host up front.

```nim
{{#shiftinclude auto:../../examples/client.nim:create}}
```

Two [`RestClientFlag`](api/client.html#RestClientFlag)s tune behavior:

- `CommaSeparatedArray` — encode `seq[T]` query parameters as a single
  comma-delimited value instead of repeating the key.
- `ResolveAlways` — perform DNS resolution on every request rather than caching
  the resolved address.

## Calling an endpoint

The generated proc is `async` and takes your declared parameters plus three
extra keyword arguments: `restContentType`, `restAcceptType`, and
`extraHeaders`.

```nim
{{#shiftinclude auto:../../examples/client.nim:call}}
```

`restAcceptType` overrides the `accept` pragma at the call site and understands
quality weights, e.g. `"app/type1;q=1.0,app/type2;q=0.1"`.

## Return types

The proc's return type selects how much of the response you get back and how
errors are handled.

| Return type                                                  | Result                                                                                                    |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| a value type `T` (e.g. `string`, `int`, a custom type)       | the decoded body; a non-2xx status raises [`RestResponseError`](api/presto/common.html#RestResponseError) |
| [`RestStatus`](api/client.html#RestStatus)                   | just the HTTP status code; the body is consumed                                                           |
| [`RestPlainResponse`](api/client.html#RestPlainResponse)     | status, content type, headers, and raw `data: seq[byte]`                                                  |
| [`RestResponse[T]`](api/client.html#RestResponse)            | status, content type, and the decoded `data: T`                                                           |
| [`RestHttpResponseRef`](api/client.html#RestHttpResponseRef) | the raw response for manual/streaming reads                                                               |

Examples:

```nim
{{#shiftinclude auto:../../examples/client.nim:returns}}
```

Reading a streaming response:

```nim
{{#shiftinclude auto:../../examples/client.nim:stream}}
```

## Error handling

When a value-returning proc receives a non-2xx status it raises
[`RestResponseError`](api/presto/common.html#RestResponseError), which carries
the details of the failed response.

```nim
{{#shiftinclude auto:../../examples/client.nim:errors}}
```

Other exceptions the generated procs may raise include `RestEncodingError`
(a parameter or body failed to encode), `RestDnsResolveError` (host resolution
failed), `RestCommunicationError` (transport/HTTP failure), and
`RestDecodingError` (the response body failed to decode). `CancelledError`
propagates as usual.

## Connection handling

By default connections are pooled and reused. The
[`connection`](api/client.html#connection-templates-all) pragma changes this per
call:

- `{}` or `{Dedicated}` — keep the connection open for reuse.
- `{Close}` — close the connection after the request.

```nim
{{#shiftinclude auto:../../examples/client.nim:conn}}
```

## Overloading

Because the macro produces ordinary procedures, you can overload the same
endpoint with different parameter sets, e.g. a queryless variant and
one that takes filters, and let Nim's overload resolution pick between them at
the call site.
