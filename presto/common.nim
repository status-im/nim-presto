#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import chronos/apps
import stew/[results, byteutils]
export results, apps

{.push raises: [Defect].}

type
  ContentBody* = object
    contentType*: string
    data*: seq[byte]

  RestResult*[T] = Result[T, cstring]

  RestApiError* = object
    status*: HttpCode
    message*: string
    contentType*: string

  RestApiResponse* = Result[ContentBody, RestApiError]

  ByteChar* = string | seq[byte]

proc error*(t: typedesc[RestApiResponse], status: HttpCode = Http200,
            msg: string = "",
            contentType: string = "text/html"): RestApiResponse =
  err(RestApiError(status: status, message: msg, contentType: contentType))

proc response*(t: typedesc[RestApiResponse], data: ByteChar,
               contentType = "text/text"): RestApiResponse =
  when data is seq[byte]:
    ok(ContentBody(contentType: contentType, data: data))
  else:
    var default: seq[byte]
    if len(data) > 0:
      ok(ContentBody(contentType: contentType, data: toBytes(data)))
    else:
      ok(ContentBody(contentType: contentType, data: default))

proc isEmpty*(error: RestApiError): bool =
  error == RestApiError()
