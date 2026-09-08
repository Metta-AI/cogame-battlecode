#!/usr/bin/env bash
# Build the bc22 parity oracle: verify the published jar by sha256 AND size,
# then compile the trace driver, the upstream example bot (Tier A) and the four
# variants of our own scenario bot (Tier A').
#
# CI-TIME ONLY. Nothing here reaches any runtime image stage.
#
#   tools/oracle/bc22/build_oracle.sh <jar> <outdir>
#
# TEMURIN 8, AND `javac` WITH NO `--release`, NO `-source`, NO `-target`.
# `--release` arrived in JDK 9 and dies with "invalid flag" on a JDK-8 javac
# in seconds (the bc21 lesson); the compiler IS 8, so the target is 8. And
# the JDK has to BE 8: the jar bundles ASM 5.0.4 and under JDK 21 the
# instrumenter throws inside ClassReader.<init> on every player class load
# (docs/PARITY.md section bc22).
#
# THE EXAMPLE BOT IS UPSTREAM'S FILE WITH EXACTLY ONE CHANGE: its `package`
# line, so the two sides can name the package `examplefuncsplayer22`. It
# needs NO determinism patch -- it seeds its own java.util.Random(6147), and
# static fields are PER ROBOT under the instrumenter, so every unit gets its
# own stream -- and the committed copy is byte-for-byte upstream's apart from
# that line, which this script applies with `sed` so the committed file stays
# a pristine copy.
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
  echo "::error::reflection needs TIntArrayList, and the port's trove.nim is"
  echo "::error::a port of the very classes this asserts are present"
  exit 1
fi
if ! grep -q 'net/sf/jsi' "$listing"; then
  echo "::error::the jar does not bundle net.sf.jsi -- the dead-artifact"
  echo "::error::problem that forced bc21's shim WOULD then arise here"
  exit 1
fi
maps="$(grep -c '\.map22' "$listing" || true)"
echo "jar .map22 resources: ${maps}"
test "${maps}" = "75" || {
  echo "::error::expected all 75 .map22 resources in the jar, got ${maps}"
  exit 1; }
rm -f "$listing"

rm -rf "$OUT"
mkdir -p "$OUT/src/examplefuncsplayer22" "$OUT/classes"
sed -e 's/^package examplefuncsplayer;/package examplefuncsplayer22;/' \
  "$HERE/examplefuncsplayer22/RobotPlayer.java" \
  > "$OUT/src/examplefuncsplayer22/RobotPlayer.java"
grep -q '^package examplefuncsplayer22;' \
  "$OUT/src/examplefuncsplayer22/RobotPlayer.java" || {
  echo "::error::the package substitution did not apply"; exit 1; }
# And nothing else changed.
if ! diff <(tail -n +2 "$HERE/examplefuncsplayer22/RobotPlayer.java") \
          <(tail -n +2 "$OUT/src/examplefuncsplayer22/RobotPlayer.java") \
          >/dev/null; then
  echo "::error::the committed example bot differs from upstream's by more"
  echo "::error::than its package line. It is one side of the differential"
  echo "::error::oracle and may not gain behaviour."
  exit 1
fi

# THE TIER A' SCENARIO BOT, IN FOUR VARIANTS. Unlike the example bot it is
# OURS: it is the Java twin of
# src/battlecode/years/bc22/chassis/scenario22.nim and the two are meant to be
# read side by side. The variant is a COMPILE-TIME CONSTANT rewritten here
# rather than a system property, because the instrumenter refuses
# System.getProperty and because a `static final boolean` folds away to
# nothing -- the job asserts this bot never exceeds 25 % of its bytecode
# limit.
SRC="$HERE/bc22scenario/RobotPlayer.java"
grep -q '^    static final String VARIANT = "base"; // VARIANT-LINE$' "$SRC" || {
  echo "::error::the scenario bot has no VARIANT-LINE to rewrite"; exit 1; }
for v in base annihilate tie fury; do
  case "$v" in
    base) pkg=bc22scenario ;;
    annihilate) pkg=bc22scenarioannihilate ;;
    tie) pkg=bc22scenariotie ;;
    fury) pkg=bc22scenariofury ;;
  esac
  mkdir -p "$OUT/src/$pkg"
  sed -e "s/^package bc22scenario;/package ${pkg};/" \
      -e "s/^    static final String VARIANT = \"base\"; \/\/ VARIANT-LINE\$/    static final String VARIANT = \"${v}\"; \/\/ VARIANT-LINE/" \
      "$SRC" > "$OUT/src/$pkg/RobotPlayer.java"
  grep -q "^package ${pkg};" "$OUT/src/$pkg/RobotPlayer.java" || {
    echo "::error::the ${pkg} package substitution did not apply"; exit 1; }
  grep -q "VARIANT = \"${v}\";" "$OUT/src/$pkg/RobotPlayer.java" || {
    echo "::error::the ${pkg} variant substitution did not apply"; exit 1; }
  # And NOTHING ELSE differs between the four: they are one bot.
  if ! diff <(sed -e '/^package /d' -e '/VARIANT-LINE/d' "$SRC") \
            <(sed -e '/^package /d' -e '/VARIANT-LINE/d' "$OUT/src/$pkg/RobotPlayer.java") \
            >/dev/null; then
    echo "::error::${pkg} differs from the committed scenario bot by more"
    echo "::error::than its package line and its variant literal"
    exit 1
  fi
done

javac -nowarn -encoding UTF-8 -cp "$JAR" -d "$OUT/classes" \
  "$HERE/Bc22Trace.java" \
  "$OUT/src/examplefuncsplayer22/RobotPlayer.java" \
  "$OUT/src/bc22scenario/RobotPlayer.java" \
  "$OUT/src/bc22scenarioannihilate/RobotPlayer.java" \
  "$OUT/src/bc22scenariotie/RobotPlayer.java" \
  "$OUT/src/bc22scenariofury/RobotPlayer.java"

for pkg in examplefuncsplayer22 bc22scenario bc22scenarioannihilate \
           bc22scenariotie bc22scenariofury; do
  test -f "$OUT/classes/$pkg/RobotPlayer.class" || {
    echo "::error::$pkg did not compile into $OUT/classes"
    exit 1; }
done

echo "oracle built into $OUT/classes"
