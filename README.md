# Presto - An efficient library for REST API implementation

[![Github action](https://github.com/status-im/nim-presto/workflows/CI/badge.svg)](https://github.com/status-im/nim-presto/actions/workflows/ci.yml)
[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)

Presto is an asynchronous REST framework for [Nim](https://nim-lang.org/), built
on top of the [Chronos](https://github.com/status-im/nim-chronos) async I/O
library. It provides:

* a request **router** whose handlers receive path, query, and body parameters
  already unmarshalled into Nim types;
* an HTTP and HTTPS **server** to run the router, or the option to embed it into
  an existing chronos server as **middleware**;
* a strongly typed HTTP **client** generated at compile time from your own proc
  signatures;
* built-in support for CORS and Prometheus-style metrics.

## Installation
You can use Nim's official package manager Nimble to install Presto:

```
$ nimble install presto
```

To depend on Presto from your own package, add it to your `.nimble` file:

```nim
requires "presto"
```

## Documentation

Full documentation is available as a book at
[status-im.github.io/nim-presto](https://status-im.github.io/nim-presto/), with
generated API reference under [`/api`](https://status-im.github.io/nim-presto/api/theindex.html).

A minimal server looks like this:

```nim
import pkg/presto

proc decodeString*(t: typedesc[string], value: string): RestResult[string] =
  ok(value)

proc validate(pattern: string, value: string): int = 0

var router = RestRouter.init(validate)

router.api(MethodGet, "/") do () -> RestApiResponse:
  RestApiResponse.response("Hello World", Http200, "text/plain")

let server = RestServerRef.new(router, initTAddress("127.0.0.1:9000")).get()
server.start()
runForever()
```

## Contributing

When submitting pull requests, please add test cases for any new features or fixes and make sure `nimble test` is still able to execute the entire test suite successfully.

To build the documentation locally you need [mdBook](https://rust-lang.github.io/mdBook/)
with the `toc`, `open-on-gh`, `admonish`, and `shiftinclude` preprocessors:

```
$ nimble docs      # generates both the API docs and the book into ./docs
```

## License

Licensed and distributed under either of

* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

or

* Apache License, Version 2.0, ([LICENSE-APACHEv2](LICENSE-APACHEv2) or http://www.apache.org/licenses/LICENSE-2.0)

at your option. These files may not be copied, modified, or distributed except according to those terms.
