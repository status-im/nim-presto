# Quickstart

<!-- toc -->

Presto is an asynchronous REST framework for [Nim](https://nim-lang.org/),
built on top of the [Chronos](https://github.com/status-im/nim-chronos) async
I/O library. It gives you a request router, an HTTP (and HTTPS) server to run it
on, and an HTTP client that is generated for you at compile time.

A typical Presto program does three things:

- declares routes on a [`RestRouter`](api/presto/route.html#RestRouter), where
  request parameters are automatically unmarshalled into Nim types;
- serves that router with a [`RestServerRef`](api/presto/server.html#RestServerRef)
  (or embeds it into an existing Chronos HTTP server as
  [middleware](./middleware.md));
- optionally talks to a server using client procedures produced by the
  [`rest`](api/client.html#rest-macros-all) macro.

## Installation

Install Presto with Nim's package manager, Nimble:

```sh
nimble install presto
```

To depend on Presto from your own package, add it to your `.nimble` file:

```nim
requires "presto"
```

Presto requires Nim `1.6.18` or newer and pulls in `chronos`, `chronicles`,
`metrics`, `results` and `stew` as dependencies.

## A minimal server

The following program starts a server that answers `GET /` with a plain-text
greeting.

Presto calls a user-supplied `decodeString` to turn path and query parameters
into Nim values. Provide one for every type you accept as a parameter.

```nim
{{#shiftinclude auto:../../examples/quickstart_server.nim:decode}}
```

[`RestRouter.init`](api/presto/route.html#init%2Ctypedesc%5BRestRouter%5D%2CPatternCallback)
always takes a validation callback. It is invoked for every `{pattern}` segment
in a route; returning `0` accepts the value and any other value rejects the
request. If you don't need validation, return `0` for everything.

```nim
{{#shiftinclude auto:../../examples/quickstart_server.nim:validate}}
```

With those in place, declare a route with the
[`api`](api/presto/route.html#api-macros-all) macro and serve the router:

```nim
{{#shiftinclude auto:../../examples/quickstart_server.nim:server}}
```

```admonish note
`RestRouter.init` always requires a validation callback — see
[Routing](./routing.md) for details on patterns and validation.
```

## Calling it from a client

Presto can generate a client procedure straight from a signature. The
[`rest`](api/client.html#rest-macros-all) macro reads the `endpoint` and `meth`
pragmas and produces an async proc that performs the request and decodes the
response.

The client lives in the [`presto/client`](api/client.html) module, and calls a
user-supplied `decodeBytes` to turn the response body into a Nim value.

```nim
{{#shiftinclude auto:../../examples/quickstart_client.nim}}
```

## API Docs

- [API Index](./api/theindex.html)
- Modules:
  - [presto](./api/presto.html)
  - [presto/client](./api/presto.html)
  - [presto/secureserver](./api/secureserver.html)
  - [presto/middleware](./api/middleware.html)

## Where to go next

- [Routing](./routing.md) — declaring routes, path/query/body parameters,
  responses, and the encode/decode contract.
- [Server](./server.md) — server options, lifecycle, error handling, and TLS.
- [Middleware](./middleware.md) — embedding a router into an existing Chronos
  HTTP server.
- [Client](./client.md) — the `rest` macro in depth.
- [CORS and metrics](./advanced.md) — cross-origin support and Prometheus
  metrics.
