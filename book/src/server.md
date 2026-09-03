# Server

<!-- toc -->

Once you have a [router](./routing.md), you serve it with a
[`RestServerRef`](api/presto/server.html#RestServerRef). The server owns a
Chronos HTTP server, dispatches incoming requests through the router, and turns
the [`RestApiResponse`](api/presto/common.html#RestApiResponse) your handlers
return into real HTTP responses.

## Creating a server

[`RestServerRef.new`](api/presto/server.html#new-procs-all) returns a `Result`,
so unwrap it with `get()` (or handle the error). At minimum it needs a router
and an address to bind to.

```nim
{{#shiftinclude auto:../../examples/server.nim:create}}
```

### Common options

`new` accepts many keyword arguments; the most useful ones are:

| Argument | Default | Description |
|----------|---------|-------------|
| `serverIdent` | `PrestoIdent` | value of the `Server` response header |
| `serverFlags` | `{NotifyDisconnect}` | Chronos `HttpServerFlags` |
| `socketFlags` | `{ReuseAddr}` | listening socket flags |
| `maxConnections` | `-1` (unlimited) | connection cap |
| `bufferSize` | `4096` | per-connection buffer |
| `httpHeadersTimeout` | `10.seconds` | header read timeout |
| `maxHeadersSize` | `8192` | max request header bytes |
| `maxRequestBodySize` | `1_048_576` | max request body bytes |
| `requestErrorHandler` | `nil` | custom error handler (see below) |
| `errorType` | `cstring` | error type of the returned `Result` |

The `errorType` parameter lets you choose whether construction failures are
reported as `cstring` (the default) or `string`:

```nim
{{#shiftinclude auto:../../examples/server.nim:errortype}}
```

## Lifecycle

```nim
{{#shiftinclude auto:../../examples/server.nim:lifecycle}}
```

```nim
{{#shiftinclude auto:../../examples/server.nim:shutdown}}
```

The relevant procedures are
[`start`](api/presto/server.html#start-procs-all),
[`stop`](api/presto/server.html#stop-procs-all),
[`drop`](api/presto/server.html#drop-procs-all),
[`closeWait`](api/presto/server.html#closeWait-procs-all),
[`join`](api/presto/server.html#join-procs-all),
[`state`](api/presto/server.html#state-procs-all) and
[`localAddress`](api/presto/server.html#localAddress-procs-all).

A typical test or short-lived program brackets its work with `start` and
`closeWait`:

```nim
{{#shiftinclude auto:../../examples/server_bracket.nim:bracket}}
```

## Handling errors

Some failures happen before or around your handler: a malformed request, an
unknown route, or an undecodable body. By default Presto answers these with a
bare status code (`400`, `404`, …). Supply a `requestErrorHandler` to customize
them.

The handler receives a
[`RestRequestError`](api/presto/servercommon.html#RestRequestError) describing
what went wrong and the `HttpRequestRef`, and returns an `HttpResponseRef`.

```nim
{{#shiftinclude auto:../../examples/server_errorhandler.nim:handler}}
```

```nim
{{#shiftinclude auto:../../examples/server_errorhandler.nim:register}}
```

The `RestRequestError` cases are:

- `Invalid` — the request line or path could not be parsed.
- `NotFound` — no route matched.
- `InvalidContentBody` — the body could not be read.
- `InvalidContentType` — a body was sent without a usable `Content-Type`.
- `Unexpected` — a catch-all.

`defaultResponse()` returns Presto's built-in response and is handy as a
fallback.

```admonish note
The error handler covers *framework* errors. Errors your own handler wants to
report should be returned as `RestApiResponse.error(...)` instead (see
[Building responses](./routing.md#building-responses)).
```

## Serving over HTTPS

For TLS, use [`SecureRestServerRef`](api/secureserver.html#SecureRestServerRef)
from `presto/secureserver`. It behaves exactly like `RestServerRef`—same
routing, same responses—but additionally takes a TLS private key and
certificate.

```nim
{{#shiftinclude auto:../../examples/secureserver.nim:secure}}
```

[`SecureRestServerRef`](api/secureserver.html#SecureRestServerRef) supports the
same lifecycle procedures (`start`, `stop`, `drop`, `closeWait`, `join`,
`state`, `localAddress`) and the same `errorType` option as the plain server,
plus a `secureFlags: set[TLSFlags]` argument for TLS-specific behavior.
