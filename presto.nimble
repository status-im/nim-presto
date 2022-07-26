mode = ScriptMode.Verbose

packageName   = "presto"
version       = "0.0.4"
author        = "Status Research & Development GmbH"
description   = "REST API implementation"
license       = "MIT"
skipDirs      = @["tests", "examples"]

requires "nim >= 1.2.0",
         "chronos >= 3.0.9",
         "chronicles",
         "stew"

proc runTest(filename: string) =
  let styleCheckStyle =
    if (NimMajor, NimMinor) < (1, 6):
      "hint"
    else:
      "error"
  var excstr: string =
    "nim c -r --hints:off --styleCheck:usages --styleCheck:" & styleCheckStyle &
    " --skipParentCfg " & getEnv("NIMFLAGS") & " "
  excstr.add("tests/" & filename)
  exec excstr
  rmFile "tests/" & filename.toExe

task test, "Runs rest tests":
  runTest("testall")
