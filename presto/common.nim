#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import chronos/apps, chronos/apps/http/httpclient
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

  RestApiResponseKind* {.pure.} = enum
    Empty, Error, Redirect, Content

  RestApiResponse* = object
    status*: HttpCode
    case kind*: RestApiResponseKind
    of RestApiResponseKind.Empty:
      discard
    of RestApiResponseKind.Content:
      content*: ContentBody
    of RestApiResponseKind.Error:
      errobj*: RestApiError
    of RestApiResponseKind.Redirect:
      location*: string
      preserveQuery*: bool

  ByteChar* = string | seq[byte]

  RestDefect* = object of Defect
  RestError* = object of CatchableError
  RestBadRequestError* = object of RestError
  RestEncodingError* = object of RestError
    field*: cstring
  RestDecodingError* = object of RestError
  RestCommunicationError* = object of RestError
    exc*: ref CatchableError
  RestRedirectionError* = object of RestError
  RestResponseError* = object of RestError
    status*: int
    contentType*: string
    message*: string

proc error*(t: typedesc[RestApiResponse],
            status: HttpCode = Http200, msg: string = "",
            contentType: string = "text/html"): RestApiResponse =
  RestApiResponse(kind: RestApiResponseKind.Error, status: status,
                  errobj: RestApiError(status: status, message: msg,
                                       contentType: contentType))

proc response*(t: typedesc[RestApiResponse], data: ByteChar,
               status: HttpCode = Http200,
               contentType = "text/text"): RestApiResponse =
  let content =
    when data is seq[byte]:
      ContentBody(contentType: contentType, data: data)
    else:
      block:
        var default: seq[byte]
        ContentBody(contentType: contentType,
                    data: if len(data) > 0: toBytes(data) else: default)

  RestApiResponse(kind: RestApiResponseKind.Content,
                  status: status,
                  content: content)

proc redirect*(t: typedesc[RestApiResponse], status: HttpCode = Http307,
               location: string, preserveQuery = false): RestApiResponse =
  RestApiResponse(kind: RestApiResponseKind.Redirect, status: status,
                  location: location, preserveQuery: preserveQuery)
