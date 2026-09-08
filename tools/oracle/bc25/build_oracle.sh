#!/usr/bin/env bash
# Build the bc25 parity oracle: verify the published jar, compile the trace
# driver, the upstream example bot and ALL THREE scenario packages.
#
# CI-TIME ONLY. Nothing here reaches any runtime image stage.
#
#   tools/oracle/bc25/build_oracle.sh <jar> <battlecode25-checkout> <outdir>
#
# JDK 21, AND `javac` WITH NO FLAGS AT ALL. The engine's build.gradle sets
# `sourceCompatibility = VERSION_21` and hard-fails below it, and the
# instrumenter uses ASM 9.7.1, which is happy with class-file version 65. So
# the bc21 lesson ("match javac flags to the JDK") is discharged by using
# none: no `--release`, no `-source`, no `-target`. `-source 8` here would be
# as wrong as `--release 8` was there.
set -euo pipefail

JAR="${1:?usage: build_oracle.sh <jar> <engine-checkout> <outdir>}"
ENGINE="${2:?}"
OUT="${3:?}"
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

rm -rf "$OUT"
mkdir -p "$OUT/src" "$OUT/classes"
cp -r "$HERE/bc25scenario" "$OUT/src/"

# The two variants are the same file with one constant flipped, exactly as
# bc24's teleport variant is: `bc25scenariopaint` paints flat out so
# PAINT_ENOUGH_AREA fires, `bc25scenariowipe` hunts enemy units so
# DESTROY_ALL_UNITS does.
for variant in paint wipe; do
  pkg="bc25scenario${variant}"
  flag="$(echo "$variant" | tr '[:lower:]' '[:upper:]')"
  mkdir -p "$OUT/src/$pkg"
  sed -e "s/^package bc25scenario;/package ${pkg};/" \
      -e "s/${flag} = false;/${flag} = true;/" \
      "$HERE/bc25scenario/RobotPlayer.java" > "$OUT/src/$pkg/RobotPlayer.java"
  grep -q "${flag} = true;" "$OUT/src/$pkg/RobotPlayer.java" || {
    echo "::error::the ${variant} substitution did not apply"; exit 1; }
done

cp -r "$ENGINE/example-bots/src/main/examplefuncsplayer" "$OUT/src/"

javac -nowarn -encoding UTF-8 -cp "$JAR" -d "$OUT/classes" \
  "$HERE/Bc25Trace.java" \
  "$OUT/src/examplefuncsplayer/RobotPlayer.java" \
  "$OUT/src/bc25scenario/RobotPlayer.java" \
  "$OUT/src/bc25scenariopaint/RobotPlayer.java" \
  "$OUT/src/bc25scenariowipe/RobotPlayer.java"

echo "oracle built into $OUT/classes"
