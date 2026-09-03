# Routing

<!-- toc -->

Routing is the core of Presto. A [`RestRouter`](api/presto/route.html#RestRouter)
maps incoming HTTP requests identified by method and path to handler
procedures, unmarshalling request parameters into Nim types along the way.

## Creating a router

[`RestRouter.init`](api/presto/route.html#init%2Ctypedesc%5BRestRouter%5D%2CPatternCallback)
takes a _pattern-validation callback_. This callback is invoked for every path
segment that corresponds to a `{pattern}` in a route, letting you reject
malformed input before the handler runs. It returns `0` when the value is
acceptable and any non-zero value to reject the request.

```nim
{{#shiftinclude auto:../../examples/routing.nim:validate}}
```

If you don't need validation, provide a callback that always returns `0`.

## Declaring routes

Routes are declared with the [`api`](api/presto/route.html#api-macros-all) macro
using Nim's `do` notation. The handler's return type must be
[`RestApiResponse`](api/presto/common.html#RestApiResponse).

```nim
{{#shiftinclude auto:../../examples/routing.nim:ping}}
```

The handler's _parameters_ describe what Presto should extract from the request.
Presto inspects their names and types and generates the extraction and decoding
code for you.

### Path parameters

A segment written as `{name}` in the route path becomes a required parameter of
the same name. Path parameters are decoded into a `Result[T, cstring]`, so you
can check them with`isErr()` / `error()` and read the value with `get()`.

```nim
{{#shiftinclude auto:../../examples/routing.nim:path}}
```

### Query parameters

Parameters that are _not_ part of the path become query-string parameters. Use
`Option[T]` for an optional value and `seq[T]` to collect a repeated key.

```nim
{{#shiftinclude auto:../../examples/routing.nim:query}}
```

```admonish note
Optional query parameters have type `Option[Result[T, cstring]]`: the outer
`Option` tells you whether the key was present, and the inner `Result` tells you
whether decoding succeeded. A `seq[T]` parameter is instead a single
`Result[seq[T], cstring]`, and is empty when the key is absent.
```

### The request body

Add an argument of type [`Option[ContentBody]`](api/presto/common.html#ContentBody)
to receive the raw request body (available for `POST`, `PUT`, `PATCH` and
`DELETE`). The name of the argument is up to you.

```nim
{{#shiftinclude auto:../../examples/routing.nim:body}}
```

### The response object

Add an argument of type `HttpResponseRef` to take over the response yourself, e.g. to stream a body with `sendBody`. You may still return a `RestApiResponse`; if you have already responded, Presto will not send anything further.

```nim
{{#shiftinclude auto:../../examples/routing.nim:resp}}
```

### Reserved keywords as parameter names

Parameter names coming from the URL may collide with Nim keywords. Quote them with backticks:

```nim
{{#shiftinclude auto:../../examples/routing.nim:keyword}}
```

```admonish warning title="Path length limit"
A path may contain at most 64 segments. Requests with more segments are rejected
with `400 Bad Request`.
```

## Encoding and decoding parameters

Presto does not assume any particular serialization format. Instead, it calls
user-supplied procedures to convert between wire representations and Nim values.
You must provide these for every type you use as a parameter, body, or response.

| Procedure                                                                                               | Used by | Purpose                       |
| ------------------------------------------------------------------------------------------------------- | ------- | ----------------------------- |
| `decodeString(t: typedesc[T], value: string): RestResult[T]`                                            | server  | decode a path/query parameter |
| `decodeBytes(t: typedesc[T], value: openArray[byte], contentType: Opt[ContentTypeData]): RestResult[T]` | client  | decode a response body        |
| `encodeString(value: T): RestResult[string]`                                                            | client  | encode a path/query parameter |
| `encodeBytes(value: T, contentType: string): RestResult[seq[byte]]`                                     | client  | encode a request body         |

A minimal `decodeString` for `int` on the server side:

```nim
{{#shiftinclude auto:../../examples/routing.nim:decode_int}}
```

```admonish tip
By convention, `seq[byte]` values are encoded as hex strings (for example
`0x7465737431` decodes to `"test1"`). This lets you pass binary data safely
through URLs.
```

Custom and generic types work the same way: you decide how they map to
strings and bytes. See `tests/helpers.nim` in the repository for a complete set
of encoders/decoders covering integers, strings, byte sequences, and custom
variant objects.

## Building responses

[`RestApiResponse`](api/presto/common.html#RestApiResponse) has three
constructors, each with several overloads.

### Content responses

The [`response`](api/presto/common.html#response-procs-all) constructor sends a
body:

```nim
{{#shiftinclude auto:../../examples/routing.nim:responses}}
```

### Error responses

The [`error`](api/presto/common.html#error-procs-all) constructor sends an error
status with an optional message:

```nim
{{#shiftinclude auto:../../examples/routing.nim:errors}}
```

### Redirects

The [`redirect`](api/presto/common.html#redirect-procs-all) constructor issues an
HTTP redirect:

```nim
{{#shiftinclude auto:../../examples/routing.nim:redirects}}
```

When `preserveQuery` is `true`, the original request's query string is merged
into the redirect target.

```admonish note
When you pass headers and a `contentType`, the explicit `contentType` argument
wins over any `Content-Type` present in the headers table. The same applies to
the `Location` header for redirects.
```

## Content negotiation

Inside a handler you can inspect the client's `Accept` header and pick a
supported media type with `preferredContentType`. It returns a `Result`; when
nothing matches, respond with `406 Not Acceptable`.

```nim
{{#shiftinclude auto:../../examples/routing.nim:negotiate}}
```

## Raw routes

Sometimes you want the request untouched: no body decoding, direct access to
`HttpRequestRef`. Use [`rawApi`](api/presto/route.html#rawApi-macros-all) instead
of `api`. Raw handlers receive the `request` symbol in scope.

```nim
{{#shiftinclude auto:../../examples/routing.nim:raw}}
```

## Redirecting routes

You can register a redirect from one route pattern to another compatible one
with the [`redirect`](api/presto/route.html#redirect-macros-all) macro. Both
patterns must contain the same set of `{names}` (they may appear in a different
order).

```nim
{{#shiftinclude auto:../../examples/routing.nim:route_redirect}}
```

At the lower level,
[`addRoute`](api/presto/route.html#addRoute-procs-all) and
[`addRedirect`](api/presto/route.html#addRedirect-procs-all) register routes and
redirects directly. Registering the same route twice raises a `Defect`.
