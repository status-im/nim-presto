import os

mode = ScriptMode.Verbose

packageName   = "presto"
version       = "0.2.0"
author        = "Status Research & Development GmbH"
description   = "REST API implementation"
license       = "MIT"
skipDirs      = @["tests", "examples"]

requires "nim >= 2.2.8",
         "chronos >= 4.0.3 & <5.0.0",
         "chronicles >= 0.12.4",
         "metrics >= 0.1.0",
         "results >= 0.5.0",
         "stew >= 0.5.2"

let nimc = getEnv("NIMC", "nim") # Which nim compiler to use
let lang = getEnv("NIMLANG", "c") # Which backend (c/cpp/js)
let flags = getEnv("NIMFLAGS", "") # Extra flags for the compiler
let verbose = getEnv("V", "") notin ["", "0"]
let platform = getEnv("PLATFORM", "")

let cfg =
  " --styleCheck:usages --styleCheck:error" &
  (if verbose: "" else: " --verbosity:0") &
  " --skipParentCfg --skipUserCfg --outdir:build " &
  quoteShell("--nimcache:build/nimcache/$projectName")

proc build(args, path: string) =
  exec nimc & " " & lang & " " & cfg & " " & flags & " " & args & " " & path

proc run(args, path: string) =
  build args & " --mm:refc -r", path
  if (NimMajor, NimMinor) > (1, 6):
    build args & " --mm:orc -r", path

task test, "Runs rest tests":
  run("", "tests/testall")

task test_asan, "Run all tests with ASAN":
  if platform != "x86":
    # https://clang.llvm.org/docs/AddressSanitizer.html
    putEnv("ASAN_OPTIONS", "detect_leaks=0:detect_stack_use_after_return=1")
    # https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html
    putEnv("UBSAN_OPTIONS", "print_stacktrace=1")
    let asanArgs =
      " --mm:orc -d:useMalloc --cc:clang --debugger:native" &
      " --passC:-fsanitize=address,undefined" &
      " --passL:-fsanitize=address,undefined" &
      " --passC:-fno-sanitize-recover=undefined" &
      " --passC:-fno-sanitize-merge" &
      " --passC:-fno-omit-frame-pointer"
    build asanArgs & " -r", "tests/testall"

task examples, "Compile all examples":
  echo "\r\n\x1B[0;94m[Suite]\x1B[0;37m Examples"
  for path in listFiles(thisDir() / "examples"):
    if path.splitFile().ext != ".nim":
      continue
    let filename = path.splitFile().name
    echo "  Compiling: ", filename
    try:
      build("", path)
      echo "  \x1B[0;92m[OK]\x1B[0;37m ", filename
    except:
      echo "  \x1B[0;31m[FAILED]\x1B[0;37m ", filename
      exec "exit 1"

task apidocs, "Generate the API docs":
  exec nimc & " doc " &
    "--git.url:https://github.com/status-im/nim-presto --git.commit:master --outdir:docs/api --project presto"
  exec nimc & " doc " &
    "--git.url:https://github.com/status-im/nim-presto --git.commit:master --outdir:docs/api --project presto/client"
  exec nimc & " doc " &
    "--git.url:https://github.com/status-im/nim-presto --git.commit:master --outdir:docs/api --project presto/secureserver"
  exec nimc & " doc " &
    "--git.url:https://github.com/status-im/nim-presto --git.commit:master --outdir:docs/api --project presto/middleware"

task book, "Generate the book":
  exec "mdbook build book/ -d ../docs/"

task docs, "Generate the documentation":
  rmDir "docs"
  exec "nimble book"
  exec "nimble apidocs"
