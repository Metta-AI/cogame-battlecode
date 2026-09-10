#!/usr/bin/env bash
# Build the bc17 parity oracle: verify the published jar by sha256, byte size
# AND `GameConstants.SPEC_VERSION`, assert it really is self-contained, apply
# the THREE committed patches to the four files they touch, assert each one
# landed, assert the weak floor has not gained behaviour, and compile the
# trace driver, the four patched engine sources and the seven oracle bots.
#
# CI-TIME ONLY. Nothing here reaches any runtime image stage: there is no
# JDK, no JRE and no Java in ANY stage of the Dockerfile.
#
#   tools/oracle/bc17/build_oracle.sh <jar> <engine-src-root> <outdir>
#
# where <engine-src-root> is a checkout of
# github.com/battlecode/battlecode-server-2017 at the commit `jar.lock` pins
# (`engine_commit`), i.e. the directory containing `src/main/battlecode`.
#
# TEMURIN 8, AND `javac` WITH NO `--release`, NO `-source`, NO `-target`.
# `--release` arrived in JDK 9 and dies with "invalid flag" on a JDK-8 javac
# in seconds (the bc21 lesson); the compiler IS 8, so the target is 8. And
# the JDK has to BE 8: the jar bundles a 2017-era ASM 5.0.4 and the whole
# instrumenter is built for Java 8 class files, so under a modern JDK the
# instrumenter throws IllegalArgumentException inside ClassReader.<init> on
# every player class load, nothing is ever built, the game ends in one round
# and the job would exit 0 while proving nothing (docs/PARITY.md section
# bc17). The job's first step asserts that; `Bc17Trace.java` asserts it again
# from the other side.
set -euo pipefail

JAR="${1:?usage: build_oracle.sh <jar> <engine-src-root> <outdir>}"
SRC="${2:?usage: build_oracle.sh <jar> <engine-src-root> <outdir>}"
OUT="${3:?usage: build_oracle.sh <jar> <engine-src-root> <outdir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"

lock() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
    "$HERE/jar.lock" "$1"
}

# ---------------------------------------------------------------------------
# 1. THE JAR, PINNED THREE WAYS.
# ---------------------------------------------------------------------------
want="$(lock sha256)"
got="$(sha256sum "$JAR" | cut -d" " -f1)"
if [ "$want" != "$got" ]; then
  echo "::error::oracle jar sha256 mismatch: want $want got $got"
  exit 1
fi
wantbytes="$(lock bytes)"
gotbytes="$(stat -c%s "$JAR")"
if [ "$wantbytes" != "$gotbytes" ]; then
  echo "::error::oracle jar size mismatch: want $wantbytes got $gotbytes"
  exit 1
fi
echo "oracle jar verified: $got ($gotbytes bytes)"

# UNLIKE 2016 THERE *IS* A `GameConstants.SPEC_VERSION`, so it is a THIRD
# independent pin on top of the sha256 and the size -- read by reflection out
# of the jar's own classes rather than out of a manifest attribute.
rm -rf "$OUT"
mkdir -p "$OUT/classes" "$OUT/bots" "$OUT/engine/battlecode/common" \
         "$OUT/engine/battlecode/world" "$OUT/probe"
cat > "$OUT/probe/SpecVersion.java" <<'JAVA'
public final class SpecVersion {
    public static void main(String[] args) throws Exception {
        Class<?> c = Class.forName("battlecode.common.GameConstants");
        System.out.println(c.getField("SPEC_VERSION").get(null));
    }
}
JAVA
javac -nowarn -encoding UTF-8 -cp "$JAR" -d "$OUT/probe" \
  "$OUT/probe/SpecVersion.java"
spec="$(java -cp "$JAR:$OUT/probe" SpecVersion | tr -d '\r\n')"
wantspec="$(lock spec_version)"
echo "jar GameConstants.SPEC_VERSION: ${spec}"
test "${spec}" = "${wantspec}" || {
  echo "::error::the jar's SPEC_VERSION is ${spec}, want ${wantspec}. The"
  echo "::error::primary pin is the sha256 and the size in"
  echo "::error::tools/oracle/bc17/jar.lock, so this means the pin and the"
  echo "::error::file have come apart."
  exit 1; }

# ---------------------------------------------------------------------------
# 2. THE JAR REALLY IS SELF-CONTAINED.
# ---------------------------------------------------------------------------
# No Gradle, no Maven resolution, no deps.lock and no jsi shim. The listing
# goes to a FILE first: `unzip -l | grep -q` takes SIGPIPE the moment grep is
# satisfied, and under `set -o pipefail` that fails a perfectly good jar --
# the bc16 scar.
listing="$OUT/jar-listing.txt"
unzip -l "$JAR" > "$listing"
entries="$(tail -1 "$listing" | awk '{print $2}')"
echo "jar entries: ${entries}"
for needed in 'org/objectweb/asm' 'gnu/trove' 'net/sf/jsi' \
              'com/google/flatbuffers'; do
  if ! grep -q "$needed" "$listing"; then
    echo "::error::the jar does not bundle ${needed}; this job would need a"
    echo "::error::Maven download list, which the whole design avoids"
    exit 1
  fi
done
# gnu/trove AND net/sf/jsi are both present and both are LOAD-BEARING here,
# unlike 2016: trove's TIntObjectHashMap iteration order is observable
# through GameWorld.updateTrees's float32 sum and through
# senseBroadcastingRobotLocations (D1), and the R-tree's candidate order is
# observable through senseNearbyRobots (D2, normalised by rtree_order.patch).
maps="$(grep -c 'battlecode/world/resources/.*\.map17' "$listing" || true)"
echo "jar .map17 map resources: ${maps}"
test "${maps}" = "70" || {
  echo "::error::expected all 70 .map17 map resources in the jar, got ${maps}"
  echo "::error::-- and this job passes no --map-dir, so every pool map has"
  echo "::error::to be one of them."
  exit 1; }

# ---------------------------------------------------------------------------
# 3. THE THREE PATCHES, AND THERE ARE EXACTLY THREE.
# ---------------------------------------------------------------------------
# These are the ONLY three places this oracle is not the published engine and
# the published scaffold, and docs/PARITY.md section bc17 names all three
# with their reasons.
patches="$(find "$HERE" -name '*.patch' | wc -l)"
test "${patches}" -eq 3 || {
  echo "::error::found ${patches} patches under tools/oracle/bc17, want"
  echo "::error::exactly three (strictmath, rtree_order, determinism). A"
  echo "::error::fourth place where the oracle is not the engine is a"
  echo "::error::defect, not a patch."
  exit 1; }

test -d "$SRC/src/main/battlecode" || {
  echo "::error::$SRC is not a battlecode-server-2017 checkout"; exit 1; }
cp "$SRC/src/main/battlecode/common/Direction.java" \
   "$SRC/src/main/battlecode/common/MapLocation.java" \
   "$OUT/engine/battlecode/common/"
cp "$SRC/src/main/battlecode/world/InternalBullet.java" \
   "$SRC/src/main/battlecode/world/ObjectInfo.java" \
   "$OUT/engine/battlecode/world/"
mkdir -p "$OUT/engine/examplefuncsplayer17"
cp "$HERE/examplefuncsplayer17/RobotPlayer.java" \
   "$OUT/engine/examplefuncsplayer17/RobotPlayer.java"

apply() {
  local patch="$1"
  local hunks
  hunks="$(grep -c '^@@' "$patch")"
  echo "applying $(basename "$patch") (${hunks} hunk(s))"
  ( cd "$OUT/engine" && git apply --check -p1 "$patch" ) || {
    echo "::error::$(basename "$patch") no longer applies to the pinned"
    echo "::error::sources. A patch that has drifted off its commit is a"
    echo "::error::patch nobody has read."
    exit 1; }
  ( cd "$OUT/engine" && git apply -p1 "$patch" )
}

apply "$HERE/strictmath.patch"
# F1/F2: exactly ELEVEN call sites in three files, and nothing else --
# `abs`, `min`, `max`, `floor`, `ceil`, `toDegrees`, `toRadians` and
# `Math.PI` are left exactly as they are. `\bMath\.` does not match inside
# `StrictMath.`, which is the whole point of the word boundary.
smsites="$({ grep -c 'StrictMath\.\(sin\|cos\|atan2\|sqrt\)' \
  "$OUT/engine/battlecode/common/Direction.java" \
  "$OUT/engine/battlecode/common/MapLocation.java" \
  "$OUT/engine/battlecode/world/InternalBullet.java" || true; } \
  | awk -F: '{s+=$2} END {print s+0}')"
echo "strictmath.patch: ${smsites} StrictMath call sites"
test "${smsites}" -eq 11 || {
  echo "::error::strictmath.patch left ${smsites} StrictMath sites, want 11"
  exit 1; }
left="$({ grep -c '\bMath\.\(sin\|cos\|atan2\|sqrt\)' \
  "$OUT/engine/battlecode/common/Direction.java" \
  "$OUT/engine/battlecode/common/MapLocation.java" \
  "$OUT/engine/battlecode/world/InternalBullet.java" || true; } \
  | awk -F: '{s+=$2} END {print s+0}')"
test "${left}" -eq 0 || {
  echo "::error::${left} bare Math.{sin,cos,atan2,sqrt} call sites survive"
  echo "::error::strictmath.patch; the normalisation has to be total or it"
  echo "::error::is not a normalisation."
  exit 1; }

apply "$HERE/rtree_order.patch"
# D2: every net.sf.jsi query is gone from ObjectInfo, replaced by the SAME
# `(distanceSquaredTo(query) ascending, id ascending)` enumeration
# src/battlecode/years/bc17/index.nim uses.
rtleft="$(grep -c 'nearestN' "$OUT/engine/battlecode/world/ObjectInfo.java" \
  || true)"
test "${rtleft}" -eq 0 || {
  echo "::error::${rtleft} R-tree nearest-N queries survive"
  echo "::error::rtree_order.patch in ObjectInfo.java"
  exit 1; }
grep -q 'distanceSquaredTo(center)' \
  "$OUT/engine/battlecode/world/ObjectInfo.java" || {
  echo "::error::rtree_order.patch applied but the normative"
  echo "::error::(distanceSquaredTo, id) enumeration is not in ObjectInfo"
  exit 1; }

apply "$HERE/examplefuncsplayer17/determinism.patch"
mvleft="$(grep -c 'Math\.random' \
  "$OUT/engine/examplefuncsplayer17/RobotPlayer.java" || true)"
test "${mvleft}" -eq 0 || {
  echo "::error::${mvleft} global-RNG draws survive determinism.patch; the"
  echo "::error::stock bot is then not reproducible even against itself and"
  echo "::error::Tier A\" cannot mean anything."
  exit 1; }
grep -q 'new java.util.Random(rc.getID())' \
  "$OUT/engine/examplefuncsplayer17/RobotPlayer.java" || {
  echo "::error::determinism.patch applied but the per-robot"
  echo "::error::java.util.Random(rc.getID()) is not in the bot"
  exit 1; }

# ---------------------------------------------------------------------------
# 4. THE WEAK FLOOR HAS NOT GAINED BEHAVIOUR.
# ---------------------------------------------------------------------------
# `examplefuncsplayer17` is one side of the differential oracle AND the
# league's deliberately weak filler. It never plants a tree, never waters
# one, never shakes, never chops and never donates, so it can never win by
# victory points and its only income is the sub-200 trickle. THAT IS WHAT
# BEING THE WEAK FLOOR MEANS.
for absent in 'plantTree(' 'water(' 'donate(' 'shake(' 'chop(' \
              'RobotType.TANK' 'RobotType.SCOUT'; do
  if grep -qF "$absent" \
      "$OUT/engine/examplefuncsplayer17/RobotPlayer.java"; then
    echo "::error::examplefuncsplayer17 carries \`${absent}\` -- it is one"
    echo "::error::side of the differential oracle and the league's weak"
    echo "::error::floor, and it may not gain behaviour."
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 5. COMPILE. NO `--release`, NO `-source`, NO `-target`.
# ---------------------------------------------------------------------------
# The four patched engine sources go FIRST on the classpath at run time, so
# they shadow the jar's own copies; everything else comes from the jar.
javac -nowarn -encoding UTF-8 -cp "$JAR" -d "$OUT/classes" \
  "$OUT/engine/battlecode/common/Direction.java" \
  "$OUT/engine/battlecode/common/MapLocation.java" \
  "$OUT/engine/battlecode/world/InternalBullet.java" \
  "$OUT/engine/battlecode/world/ObjectInfo.java"
javac -nowarn -encoding UTF-8 -cp "$OUT/classes:$JAR" -d "$OUT/classes" \
  "$HERE/Bc17Trace.java"

# THE BOTS GO IN THEIR OWN DIRECTORY, and that is not tidiness: the player
# class loader treats every class it can find under the bot URL as a TEAM
# class, so a bot directory that also holds `battlecode/**` makes every
# `battlecode.common` load throw "you can't use the package 'battlecode.'"
# and every robot die on its first turn. MEASURED, and it cost a round.
javac -nowarn -encoding UTF-8 -cp "$OUT/classes:$JAR" -d "$OUT/bots" \
  "$OUT/engine/examplefuncsplayer17/RobotPlayer.java" \
  "$HERE/bc17idle/RobotPlayer.java" \
  "$HERE/bc17scenario/RobotPlayer.java" \
  "$HERE/bc17scenariotree/RobotPlayer.java" \
  "$HERE/bc17scenariokill/RobotPlayer.java" \
  "$HERE/bc17scenariotie/RobotPlayer.java" \
  "$HERE/bc17slowbot/RobotPlayer.java"

for pkg in examplefuncsplayer17 bc17idle bc17scenario bc17scenariotree \
           bc17scenariokill bc17scenariotie bc17slowbot; do
  test -f "$OUT/bots/$pkg/RobotPlayer.class" || {
    echo "::error::$pkg did not compile into $OUT/bots"
    exit 1; }
done
test -f "$OUT/classes/battlecode/world/Bc17Trace.class" || {
  echo "::error::the trace driver did not compile"; exit 1; }
test -f "$OUT/classes/battlecode/world/ObjectInfo.class" || {
  echo "::error::the patched ObjectInfo did not compile"; exit 1; }

echo "oracle built: engine overrides + driver in $OUT/classes, seven bots in $OUT/bots"
