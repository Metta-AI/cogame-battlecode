#!/usr/bin/env bash
# Build the bc16 parity oracle: verify the published jar by sha256 AND size,
# assert it really is self-contained, then compile the trace driver, the Tier A
# idle bot and the Tier A" `greenhorn` twin.
#
# CI-TIME ONLY. Nothing here reaches any runtime image stage.
#
#   tools/oracle/bc16/build_oracle.sh <jar> <outdir>
#
# TEMURIN 8, AND `javac` WITH NO `--release`, NO `-source`, NO `-target`.
# `--release` arrived in JDK 9 and dies with "invalid flag" on a JDK-8 javac
# in seconds (the bc21 lesson); the compiler IS 8, so the target is 8. And the
# JDK has to BE 8: the jar bundles a 2016-era ASM and a 2016-era XStream and
# the whole instrumenter is built for Java 8 class files (docs/PARITY.md
# section bc16).
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

# THERE IS NO `SPEC_VERSION` IN 2016's GameConstants, so the jar's own
# `battlecode-version` ENTRY -- a file at the jar root, NOT a manifest
# attribute (measured: the manifest carries only Ant's own three lines) -- is
# the third pin on top of the sha256 and the size.
version="$(unzip -p "$JAR" battlecode-version | tr -d '\r\n' | head -c 64)"
wantversion="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$HERE/jar.lock")"
echo "jar battlecode-version: ${version}"
test "${version}" = "${wantversion}" || {
  echo "::error::jar battlecode-version is ${version}, want ${wantversion}"
  exit 1; }

# The jar really is self-contained: no Ant, no Ivy, no Gradle, no shim, no
# Maven list. The listing goes to a FILE first: `unzip -l | grep -q` takes
# SIGPIPE the moment grep is satisfied, and under `set -o pipefail` that fails
# the whole step on a jar that is perfectly fine.
listing="$(mktemp)"
unzip -l "$JAR" > "$listing"
entries="$(tail -1 "$listing" | awk '{print $2}')"
echo "jar entries: ${entries}"
for needed in 'org/objectweb/asm' 'com/thoughtworks/xstream' \
              'battlecode/instrumenter/bytecode/resources/MethodCosts.txt'; do
  if ! grep -q "$needed" "$listing"; then
    echo "::error::the jar does not bundle ${needed}; this job would need a"
    echo "::error::Maven download list, which the whole design avoids"
    exit 1
  fi
done
# And the two things bc22 needed and 2016 does NOT: recorded rather than
# assumed, because their absence is why bc16 needs no trove port at all.
for absent in 'gnu/trove' 'net/sf/jsi'; do
  if grep -q "$absent" "$listing"; then
    echo "::notice::the jar unexpectedly bundles ${absent}; 2016 uses"
    echo "::notice::LinkedHashMap and HashMap from the JDK and needs neither"
  fi
done
maps="$(grep -c 'battlecode/world/resources/.*\.xml' "$listing" || true)"
echo "jar .xml map resources: ${maps}"
test "${maps}" = "54" || {
  echo "::error::expected all 54 .xml map resources in the jar, got ${maps}"
  exit 1; }
rm -f "$listing"

rm -rf "$OUT"
mkdir -p "$OUT/classes"

# BOTH BOTS ARE OURS. There is no upstream `examplefuncsplayer` for 2016 --
# the 2016 scaffold is a separate, unarchived project -- so unlike every other
# year there is nothing here to diff against an upstream copy. `bc16idle` is
# `while (true) Clock.yield();` and `bc16greenhorn` is the Java twin of
# `src/battlecode/years/bc16/chassis/greenhorn.nim`, which
# `tests/test_bc16_greenhorn.nim` holds to its five load-bearing statements
# from the other side. IT MAY NOT GAIN BEHAVIOUR.
for absent in 'repair(' 'activate(' 'clearRubble(' 'broadcastSignal(' \
              'RobotType.GUARD' 'RobotType.SCOUT' 'RobotType.VIPER' \
              'RobotType.TURRET'; do
  if grep -qF "$absent" "$HERE/bc16greenhorn/RobotPlayer.java"; then
    echo "::error::bc16greenhorn carries \`${absent}\` -- it is one side of"
    echo "::error::the differential oracle and may not gain behaviour"
    exit 1
  fi
done

javac -nowarn -encoding UTF-8 -cp "$JAR" -d "$OUT/classes" \
  "$HERE/Bc16Trace.java" \
  "$HERE/bc16idle/RobotPlayer.java" \
  "$HERE/bc16greenhorn/RobotPlayer.java"

for pkg in bc16idle bc16greenhorn; do
  test -f "$OUT/classes/$pkg/RobotPlayer.class" || {
    echo "::error::$pkg did not compile into $OUT/classes"
    exit 1; }
done
test -f "$OUT/classes/battlecode/world/Bc16Trace.class" || {
  echo "::error::the trace driver did not compile"; exit 1; }

echo "oracle built into $OUT/classes"
