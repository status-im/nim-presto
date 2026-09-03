import std/options
import pkg/presto

proc decodeString*(t: typedesc[string], value: string): RestResult[string] =
  ok(value)

proc validate(pattern: string, value: string): int = 0

# ANCHOR: cors
var router = RestRouter.init(
  validate, allowedOrigin = some("https://app.example.com"))
# ANCHOR_END: cors
discard router
