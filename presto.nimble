mode = ScriptMode.Verbose

packageName   = "presto"
version       = "0.0.3"
author        = "Status Research & Development GmbH"
description   = "REST API implementation"
license       = "MIT"
skipDirs      = @["tests", "examples"]

requires "nim >= 1.2.0",
         "chronos >= 3.0.3",
         "chronicles",
         "stew"

proc runTest(filename: string) =
  var excstr: string = "nim c -r "
  excstr.add("tests/" & filename)
  exec excstr
  rmFile "tests/" & filename.toExe

task test, "Runs rest tests":
  runTest("testall")
