## Tiny assertion harness shared by the shards. Each test file runs
## standalone (`nim r --path:src tests/test_x.nim`), prints one line per
## check group and exits non-zero on the first failure count > 0 — which is
## what ci.yml's per-file loop reads.



var failures* = 0
var checks* = 0

proc check*(name: string, ok: bool) =
  inc checks
  if not ok:
    echo "FAIL ", name
    inc failures

proc checkEq*[T](name: string, got, want: T) =
  inc checks
  if got != want:
    echo "FAIL ", name, ": got ", got, " want ", want
    inc failures

proc finish*(suite: string) =
  if failures > 0:
    quit(suite & ": " & $failures & " of " & $checks & " checks failed", 1)
  echo suite, ": ok (", checks, " checks)"

when isMainModule:
  ## Not a shard: `ci.yml` runs every `tests/*.nim`, so this says what it is
  ## rather than exiting silently and looking like an empty test.
  echo "harness: the shared assertion helpers; not a test shard"
