# Middleware

<!-- toc -->

Instead of running a Presto router with a dedicated
[`RestServerRef`](api/presto/server.html#RestServerRef), you can plug it into an
existing Chronos HTTP server as *middleware*. This is useful when you already
have a Chronos `HttpServerRef` (perhaps serving static files or a non-REST
protocol) and want to add REST endpoints to it, or when you want to compose
several routers into one server.

A [`RestServerMiddlewareRef`](api/middleware.html) wraps a router and behaves
like any other Chronos `HttpServerMiddlewareRef`: for each request it tries to
match a route, and if none matches it passes the request on to the next handler
in the chain.

## Wrapping a router

Create the middleware from a router with
[`RestServerMiddlewareRef.new`](api/middleware.html#new-procs-all), then pass it
to `HttpServerRef.new` via the `middlewares` argument.

```nim
{{#shiftinclude auto:../../examples/middleware.nim:wrap}}
```

The middleware also accepts an optional `errorHandler` of the same
[`RestRequestErrorHandler`](api/presto/servercommon.html#RestRequestErrorHandler)
type used by the [server](./server.md#handling-errors).

## The fall-through handler

The plain Chronos `HttpServerRef` still needs a *process callback*—the final
handler that runs when no middleware matched the request. This is where you
serve everything that isn't a REST route (or return a 404).

```nim
{{#shiftinclude auto:../../examples/middleware.nim:process}}
```

## Chaining multiple routers

You can install several middlewares. They are tried in order; the first router
that has a matching route handles the request, and anything unmatched falls
through to the next middleware and finally to the process callback.

```nim
{{#shiftinclude auto:../../examples/middleware_chain.nim:chain}}
```

```admonish tip
Because matching considers the HTTP method as well as the path, two routers can
share the same path and be selected by the request method — for example one
router handling `GET /resource` and another handling `POST /resource`.
```
