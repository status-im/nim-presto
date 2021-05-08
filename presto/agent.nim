#
#         REST API framework implementation
#             (c) Copyright 2021-Present
#         Status Research & Development GmbH
#
#              Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#              MIT license (LICENSE-MIT)
import strutils

const
  PrestoName* = "nim-presto"
    ## Project name string
  PrestoMajor* {.intdefine.}: int = 0
    ## Major number of nim-presto's version.
  PrestoMinor* {.intdefine.}: int = 0
    ## Minor number of nim-presto's version.
  PrestoPatch* {.intdefine.}: int = 3
    ## Patch number of nim-presto's version.
  PrestoVersion* = $PrestoMajor & "." & $PrestoMinor & "." & $PrestoPatch
    ## Version of nim-presto as a string.
  PrestoIdent* = "$1/$2 ($3/$4)" % [PrestoName, PrestoVersion, hostCPU,
                                    hostOS]
    ## Project ident name for networking services
