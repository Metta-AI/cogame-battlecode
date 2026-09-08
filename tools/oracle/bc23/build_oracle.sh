#!/usr/bin/env bash
# Build the bc23 parity oracle: verify the published jar by sha256 AND size,
# then compile the trace driver and the upstream example bot.
#
# CI-TIME ONLY. Nothing here reaches any runtime image stage.
#
#   tools/oracle/bc23/build_oracle.sh <jar> <outdir>
#
# TEMURIN 8, AND `javac` WITH NO `--release`, NO `-source`, NO `-target`.
# `--release` arrived in JDK 9 and dies with "invalid flag" on a JDK-8 javac
# in seconds (the bc21 lesson); the compiler IS 8, so the target is 8. And
# the JDK has to BE 8: the jar bundles ASM 5.0.4 and under JDK 21 the
# instrumenter throws inside ClassReader.<init> on every player class load
# (docs/PARITY.md section bc23).
#
# THE EXAMPLE BOT IS UPSTREAM'S FILE WITH EXACTLY ONE CHANGE: its `package`
# line, so the two sides can name the package `examplefuncsplayer23`. It
# needs NO determinism patch -- it seeds its own java.util.Random(6147) and
# never calls Math.random() -- and the committed copy is byte-for-byte
# upstream's apart from that line, which this script applies with `sed` so
# the committed file stays a pristine copy.
set -euo pipefail

JAR="${1:?usage: build_oracle.sh <jar> <outdir>}"
OUT="${2:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"

want="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha256"])' "$HERE/jar.lock")"
got="$(sha256sum "$JAR" | cut -d" " -f1)"
if [ "$want" != "$got" ]; then
  echo "::error::oracle jar sha256 mismatch: want $want got $got"
  exit 1
fi
wantbytes="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["bytes"])' "$HERE/jar.lock")"
gotbytes="$(stat -c%s "$JAR")"
if [ "$wantbytes" != "$gotbytes" ]; then
  echo "::error::oracle jar size mismatch: want $wantbytes got $gotbytes"
  exit 1
fi
echo "oracle jar verified: $got ($gotbytes bytes)"

# The jar really is self-contained: no Gradle, no shim, no Maven list.
# The listing goes to a FILE first: `unzip -l | grep -q` takes SIGPIPE the
# moment grep is satisfied, and under `set -o pipefail` that fails the whole
# step on a jar that is perfectly fine.
listing="$(mktemp)"
unzip -l "$JAR" > "$listing"
entries="$(tail -1 "$listing" | awk '{print $2}')"
echo "jar entries: ${entries}"
if ! grep -q 'gnu/trove' "$listing"; then
  echo "::error::the jar does not bundle gnu.trove; the driver's exec-order"
  echo "::error::reflection needs TIntArrayList"
  exit 1
fi
if ! grep -q 'net/sf/jsi' "$listing"; then
  echo "::error::the jar does not bundle net.sf.jsi -- the dead-artifact"
  echo "::error::problem that forced bc21's shim WOULD then arise here"
  exit 1
fi
maps="$(grep -c '\.map23' "$listing" || true)"
echo "jar .map23 resources: ${maps}"
test "${maps}" = "103" || {
  echo "::error::expected all 103 .map23 resources in the jar, got ${maps}"
  exit 1; }
rm -f "$listing"

rm -rf "$OUT"
mkdir -p "$OUT/src/examplefuncsplayer23" "$OUT/classes"
sed -e 's/^package examplefuncsplayer;/package examplefuncsplayer23;/' \
  "$HERE/examplefuncsplayer23/RobotPlayer.java" \
  > "$OUT/src/examplefuncsplayer23/RobotPlayer.java"
grep -q '^package examplefuncsplayer23;' \
  "$OUT/src/examplefuncsplayer23/RobotPlayer.java" || {
  echo "::error::the package substitution did not apply"; exit 1; }
# And nothing else changed.
if ! diff <(tail -n +2 "$HERE/examplefuncsplayer23/RobotPlayer.java") \
          <(tail -n +2 "$OUT/src/examplefuncsplayer23/RobotPlayer.java") \
          >/dev/null; then
  echo "::error::the committed example bot differs from upstream's by more"
  echo "::error::than its package line. It is one side of the differential"
  echo "::error::oracle and may not gain behaviour."
  exit 1
fi

javac -nowarn -encoding UTF-8 -cp "$JAR" -d "$OUT/classes" \
  "$HERE/Bc23Trace.java" \
  "$OUT/src/examplefuncsplayer23/RobotPlayer.java"

echo "oracle built into $OUT/classes"
