#!/usr/bin/env bash
# Build the bc24 parity oracle: verify the published jar, compile the trace
# driver, the upstream example bot and BOTH scenario packages.
#
# CI-TIME ONLY. Nothing here reaches any runtime image stage.
#
#   tools/oracle/bc24/build_oracle.sh <jar> <battlecode24-checkout> <outdir>
#
# JDK 8 IS MANDATORY: the instrumenter rewrites `java.util` classes with ASM
# 5.0.4, which refuses class-file versions above 52, so under a newer JDK every
# player class load throws and the match ends empty. `javac` is invoked with
# plain `-source 8 -target 8`; `--release` ARRIVED IN JDK 9 and dies with
# "invalid flag" on a Temurin 8 compiler in seconds (the 2026-09-04 bc21
# learning, which cost that run a CI round).
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

rm -rf "$OUT"
mkdir -p "$OUT/src" "$OUT/classes"
cp -r "$HERE/bc24scenario" "$OUT/src/"
mkdir -p "$OUT/src/bc24scenariotel"
sed -e 's/^package bc24scenario;/package bc24scenariotel;/' \
    -e 's/TELEPORT = false;/TELEPORT = true;/' \
    "$HERE/bc24scenario/RobotPlayer.java" > "$OUT/src/bc24scenariotel/RobotPlayer.java"
grep -q 'TELEPORT = true;' "$OUT/src/bc24scenariotel/RobotPlayer.java" || {
  echo "::error::the teleport substitution did not apply"; exit 1; }
cp -r "$ENGINE/example-bots/src/main/examplefuncsplayer" "$OUT/src/"

javac -source 8 -target 8 -nowarn -encoding UTF-8 -cp "$JAR" -d "$OUT/classes" \
  "$HERE/Bc24Trace.java" \
  "$OUT/src/examplefuncsplayer/RobotPlayer.java" \
  "$OUT/src/bc24scenario/RobotPlayer.java" \
  "$OUT/src/bc24scenariotel/RobotPlayer.java"

echo "oracle built into $OUT/classes"
