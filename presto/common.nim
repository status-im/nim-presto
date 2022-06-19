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
    headers*: HttpTable
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
  RestKeyValueTuple* = tuple[key: string, value: string]

proc error*(t: typedesc[RestApiResponse],
            status: HttpCode = Http200, msg: string = "",
            contentType: string = "text/html",
            headers: HttpTable): RestApiResponse =
  ## Create REST API error response with status ``status`` and content specified
  ## by type ``contentType`` and data ``data``. You can also specify
  ## additional HTTP response headers using ``headers`` argument.
  ##
  ## Please note that ``contentType`` argument's value has priority over
  ## ``Content-Type`` header's value in ``headers`` table.
  RestApiResponse(kind: RestApiResponseKind.Error, status: status,
                  headers: headers,
                  errobj: RestApiError(status: status, message: msg,
                                       contentType: contentType))

proc error*(t: typedesc[RestApiResponse],
            status: HttpCode = Http200, msg: string = "",
            contentType: string = "text/html",
            headers: openArray[RestKeyValueTuple]): RestApiResponse =
  error(t, status, msg, contentType, HttpTable.init(headers))

proc error*(t: typedesc[RestApiResponse],
            status: HttpCode = Http200, msg: string = "",
            contentType: string = "text/html"): RestApiResponse =
  error(t, status, msg, contentType, HttpTable.init())

proc response*(t: typedesc[RestApiResponse], data: ByteChar,
               status: HttpCode = Http200, contentType = "text/text",
               headers: HttpTable): RestApiResponse =
  ## Create REST API data response with status ``status`` and content specified
  ## by type ``contentType`` and data ``data``. You can also specify
  ## additional HTTP response headers using ``headers`` argument.
  ##
  ## Please note that ``contentType`` argument's value has priority over
  ## ``Content-Type`` header's value in ``headers`` table.
  let content =
    when data is seq[byte]:
      ContentBody(contentType: contentType, data: data)
    else:
      block:
        var default: seq[byte]
        ContentBody(contentType: contentType,
                    data: if len(data) > 0: toBytes(data) else: default)
  RestApiResponse(kind: RestApiResponseKind.Content, status: status,
                  headers: headers, content: content)

proc response*(t: typedesc[RestApiResponse], data: ByteChar,
               status: HttpCode = Http200, contentType = "text/text",
               headers: openArray[RestKeyValueTuple]): RestApiResponse =
  response(t, data, status, contentType, HttpTable.init(headers))

proc response*(t: typedesc[RestApiResponse], data: ByteChar,
               status: HttpCode = Http200,
               contentType = "text/text"): RestApiResponse =
  response(t, data, status, contentType, HttpTable.init())

proc redirect*(t: typedesc[RestApiResponse], status: HttpCode = Http307,
               location: string, preserveQuery = false,
               headers: HttpTable): RestApiResponse =
  ## Create REST API redirect response with status ``status`` and new location
  ## ``location``.
  ##
  ## You can preserve HTTP query string `uri.query` part using ``preserveQuery``
  ## argument. When ``preserveQuery`` is true new query string will be formed as
  ## concatenation of original HTTP request query string and ``location`` query
  ## string.
  ##
  ## You can also specify additional HTTP response headers using ``headers``
  ## argument.
  ##
  ## Please note that ``location`` argument's value has priority over
  ## ``Location`` header's value in ``headers`` table.
  RestApiResponse(kind: RestApiResponseKind.Redirect, status: status,
                  headers: headers, location: location,
                  preserveQuery: preserveQuery)

proc redirect*(t: typedesc[RestApiResponse], status: HttpCode = Http307,
               location: string, preserveQuery = false,
               headers: openArray[RestKeyValueTuple]): RestApiResponse =
  redirect(t, status, location, preserveQuery, HttpTable.init(headers))

proc redirect*(t: typedesc[RestApiResponse], status: HttpCode = Http307,
               location: string,
               preserveQuery = false): RestApiResponse =
  redirect(t, status, location, preserveQuery, HttpTable.init())
