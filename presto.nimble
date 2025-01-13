mode = ScriptMode.Verbose

packageName   = "presto"
version       = "0.1.0"
author        = "Status Research & Development GmbH"
description   = "REST API implementation"
license       = "MIT"
skipDirs      = @["tests", "examples"]

requires "nim >= 2.0.0",
         "chronos ^= 4.0.3",
         "chronicles",
         "metrics",
         "results",
         "stew"

let nimc = getEnv("NIMC", "nim") # Which nim compiler to use
let lang = getEnv("NIMLANG", "c") # Which backend (c/cpp/js)
let flags = getEnv("NIMFLAGS", "") # Extra flags for the compiler
let verbose = getEnv("V", "") notin ["", "0"]

let cfg =
  " --styleCheck:usages --styleCheck:error" &
  (if verbose: "" else: " --verbosity:0 --hints:off") &
  " --skipParentCfg --skipUserCfg --outdir:build --nimcache:build/nimcache -f"

proc build(args, path: string) =
  exec nimc & " " & lang & " " & cfg & " " & flags & " " & args & " " & path

proc run(path: string) =
  build " --mm:refc -r", path
  build " --mm:orc -r", path

task test, "Runs rest tests":
  run "tests/testall"
