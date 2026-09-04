#!/usr/bin/env python3
"""Generate src/battlecode/years/<year>/constants.nim from the pinned engine.

CI-TIME ONLY (Python and a Java *source* checkout; no JVM is involved, and
neither exists in any runtime image stage). The Battlecode 2026 rule set has
69 numeric constants plus two enum tables, and hand-transcribing them is the
kind of work that goes wrong once and stays wrong for a season -- so they are
read straight out of the engine sources at tag engine.1.2.5 and emitted
mechanically. `tests/test_constants.nim` re-runs this and byte-diffs, so a
hand-edited constant fails the build.

    tools/gen_year_constants.py --engine /path/to/battlecode26-engine.1.2.5 \
        --out src/battlecode/years/bc26/constants.nim
    tools/gen_year_constants.py --engine ... --check   # diff, exit 1 on drift

`--year bc20` and `--year bc21` do the same job for Battlecode 2020 "Soup" against a checkout
of github.com/battlecode/battlecode20 at the pinned commit, reading
`common/GameConstants.java` and `common/RobotType.java`:

    tools/gen_year_constants.py --year bc20 --engine /path/to/battlecode20 \
        --out src/battlecode/years/bc20/constants.nim

The engine checkout is fetched by CI:
    curl -fsSL https://github.com/battlecode/battlecode26/archive/refs/tags/engine.1.2.5.tar.gz
"""

from __future__ import annotations

import argparse
import pathlib
import re
import struct
import sys

TAG = "engine.1.2.5"

CONST_RE = re.compile(
    r"public\s+static\s+final\s+(int|long|float|double|String)\s+"
    r"([A-Z0-9_]+)\s*=\s*([^;]+);"
)
UNIT_RE = re.compile(
    r"^\s*(BABY_RAT|RAT_KING|CAT)\((.*?)\)\s*[,;]\s*$", re.M
)
TRAP_RE = re.compile(
    r"^\s*(RAT_TRAP|CAT_TRAP|NONE)\((.*?)\)\s*[,;]\s*$", re.M
)

def nim_literal(java_type: str, raw: str) -> tuple[str, str]:
    """(nim type, nim literal) for one Java constant initialiser.

    The WIDTHS are load-bearing, not cosmetic. `CHEESE_MINE_SPAWN_PROBABILITY`
    is a Java `float`, so `1 - it` is 0.00999999977..., not 0.01, and the
    cheese-mine spawn test lands differently for a mine that has been quiet
    for a few hundred rounds. `MAX_TEAM_EXECUTION_TIME` is a `long` that does
    not fit the 32-bit `int` a wasm32 build gets.
    """
    text = raw.strip()
    if java_type == "String":
        return "string", text
    # The 2020 rule set names one constant by a Java expression rather than a
    # literal: MIN_WATER_ELEVATION = Integer.MIN_VALUE/2. Evaluate the handful
    # of forms that actually occur rather than hand-typing the value.
    JAVA_EXPRESSIONS = {
        "Integer.MIN_VALUE/2": "-1073741824",
        "Integer.MAX_VALUE/2": "1073741823",
    }
    text = JAVA_EXPRESSIONS.get(text.replace(" ", ""), text)
    if re.fullmatch(r"[-+0-9._eE]+[LlFfDd]?", text):
        text = text.rstrip("LlFfDd")
    if java_type == "int":
        return "int", str(int(text, 0))
    if java_type == "long":
        return "int64", str(int(text, 0))
    if java_type == "float":
        return "float32", repr(float(text))
    return "float64", repr(float(text))


def read_constants_from(path: pathlib.Path,
                        strip_comments: bool = False) -> list[tuple[str, str, str]]:
    src = path.read_text()
    if strip_comments:
        # 2021 keeps MAX_ROBOT_ID as a COMMENTED-OUT declaration ("Cannot be
        # guaranteed in Battlecode 2021", because conversions mint new ids).
        # A regex over the raw text picks it up as a live constant, which is
        # exactly the sort of thing a generator is supposed to prevent.
        src = re.sub(r"//[^\n]*", "", src)
    out = []
    for java_type, name, raw in CONST_RE.findall(src):
        nim_type, literal = nim_literal(java_type, raw)
        out.append((name, nim_type, literal))
    return out


def read_constants(engine: pathlib.Path) -> list[tuple[str, str, str]]:
    return read_constants_from(
        engine / "engine/src/main/battlecode/common/GameConstants.java")


def read_units(engine: pathlib.Path) -> list[tuple[str, list[str]]]:
    src = (engine / "engine/src/main/battlecode/common/UnitType.java").read_text()
    return [(name, [v.strip() for v in args.split(",")])
            for name, args in UNIT_RE.findall(src)]


def read_traps(engine: pathlib.Path) -> list[tuple[str, list[str]]]:
    src = (engine / "engine/src/main/battlecode/common/TrapType.java").read_text()
    return [(name, [v.strip() for v in args.split(",")])
            for name, args in TRAP_RE.findall(src)]


def camel(name: str) -> str:
    parts = name.split("_")
    return parts[0].capitalize() + "".join(p.capitalize() for p in parts[1:])


def render(engine: pathlib.Path) -> str:
    consts = read_constants(engine)
    units = read_units(engine)
    traps = read_traps(engine)

    lines: list[str] = []
    add = lines.append
    add("## Battlecode 2026 gameplay constants -- GENERATED, do not edit.")
    add("##")
    add(f"## Source: github.com/battlecode/battlecode26 at tag `{TAG}`,")
    add("## files `common/GameConstants.java`, `common/UnitType.java` and")
    add("## `common/TrapType.java`, read by `tools/gen_year_constants.py`.")
    add("## `tests/test_constants.nim` regenerates this file and byte-diffs it,")
    add("## so an edit here fails the build instead of quietly changing the")
    add("## rules under a `GameVersion` that no longer describes them.")
    add("")
    add(f"const EngineTag* = \"{TAG}\"")
    add("")
    add("type")
    add("  UnitType* = enum")
    for name, _ in units:
        add(f"    ut{camel(name)} = \"{name}\"")
    add("")
    add("  TrapType* = enum")
    for name, _ in traps:
        add(f"    tt{camel(name)} = \"{name}\"")
    add("")
    add("  UnitSpec* = object")
    add("    ## `common/UnitType.java`'s constructor arguments, verbatim.")
    add("    health*, size*, visionConeRadiusSquared*, visionConeAngle*: int")
    add("    actionCooldown*, movementCooldown*, bytecodeLimit*: int")
    add("")
    add("  TrapSpec* = object")
    add("    ## `common/TrapType.java`'s constructor arguments, verbatim.")
    add("    buildCost*, damage*, stunTime*: int")
    add("    actionCooldown*, maxCount*, triggerRadiusSquared*: int")
    add("")
    add("const")
    for name, nim_type, literal in consts:
        add(f"  {camel(name)}*: {nim_type} = {literal}")
    add("")
    add("  UnitSpecs*: array[UnitType, UnitSpec] = [")
    for name, args in units:
        add(f"    ut{camel(name)}: UnitSpec(health: {args[0]}, size: {args[1]}, "
            f"visionConeRadiusSquared: {args[2]},")
        add(f"      visionConeAngle: {args[3]}, actionCooldown: {args[4]}, "
            f"movementCooldown: {args[5]},")
        add(f"      bytecodeLimit: {args[6]}),")
    add("  ]")
    add("")
    add("  TrapSpecs*: array[TrapType, TrapSpec] = [")
    for name, args in traps:
        add(f"    tt{camel(name)}: TrapSpec(buildCost: {args[0]}, damage: {args[1]}, "
            f"stunTime: {args[2]},")
        add(f"      actionCooldown: {args[3]}, maxCount: {args[4]}, "
            f"triggerRadiusSquared: {args[5]}),")
    add("  ]")
    add("")
    add("  # The per-robot DECISION BUDGET that replaces the engine's JVM")
    add("  # bytecode limit. Hand-authored, not generated: it is this port's")
    add("  # own rule, listed in docs/RULES.md §Divergences.")
    add("  DecisionOpsBabyRat* = 1500")
    add("  DecisionOpsRatKing* = 2500")
    add("  DecisionOpsCat* = 800")
    add("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
#  bc20 — Battlecode 2020 "Soup"
# ---------------------------------------------------------------------------

BC20_COMMIT = "7618f6be7d12da39f2e6e25801e578f1fecfbd86"

# `common/RobotType.java`'s enum entries, one per line, with the constructor
# arguments in declaration order:
#   spawnSource, cost, dirtLimit, soupLimit, actionCooldown,
#   sensorRadiusSquared, pollutionRadiusSquared, localPollutionAdditiveEffect,
#   localPollutionMultiplicativeEffect, globalPollutionAmount,
#   maxSoupProduced, bytecodeLimit
BC20_ROBOT_RE = re.compile(
    r"^\s{4}([A-Z_]+)\s*\(([^)]*)\),\s*$", re.M
)

# The per-robot DECISION BUDGET that replaces the JVM bytecode limit, at one
# tenth of the Java limit. Hand-authored, not generated: it is this port's own
# rule (docs/RULES-BC20.md §Divergences).
BC20_DECISION_OPS = {
    "HQ": 2000,
    "MINER": 1000,
    "LANDSCAPER": 1000,
    "DELIVERY_DRONE": 1000,
    "NET_GUN": 700,
    "REFINERY": 500,
    "VAPORATOR": 500,
    "DESIGN_SCHOOL": 500,
    "FULFILLMENT_CENTER": 500,
    "COW": 0,
}


def read_bc20_robots(engine: pathlib.Path) -> list[tuple[str, list[str]]]:
    src = (engine / "engine/src/main/battlecode/common/RobotType.java").read_text()
    # Cut at the constructor so the field declarations below the enum body are
    # not mistaken for entries.
    body = src.split("RobotType(RobotType spawnSource", 1)[0]
    out = []
    for name, args in BC20_ROBOT_RE.findall(body):
        parts = [v.strip() for v in args.split(",")]
        if len(parts) != 12:
            continue
        out.append((name, parts))
    return out


def bc20_num(text: str) -> str:
    return text.rstrip("LlFfDd")


def render_bc20(engine: pathlib.Path) -> str:
    consts = read_constants_from(
        engine / "engine/src/main/battlecode/common/GameConstants.java")
    robots = read_bc20_robots(engine)
    if len(robots) != 10:
        raise SystemExit(f"::error::expected 10 RobotType entries, saw {len(robots)}")

    lines: list[str] = []
    add = lines.append
    add('## Battlecode 2020 "Soup" gameplay constants -- GENERATED, do not edit.')
    add("##")
    add(f"## Source: github.com/battlecode/battlecode20 at commit `{BC20_COMMIT}`,")
    add("## files `common/GameConstants.java` and `common/RobotType.java`, read by")
    add("## `tools/gen_year_constants.py --year bc20`. The `test` job of")
    add("## `.github/workflows/ci.yml` re-runs that generator with `--check`,")
    add("## which byte-diffs this file, so an edit here fails the build instead")
    add("## of quietly changing the rules under a `GameVersion` that no longer")
    add("## describes them.")
    add("##")
    add("## The two derived functions `getWaterLevel`, `getSensorRadiusPollutionCoefficient`")
    add("## and `getCooldownPollutionCoefficient` are NOT constants and live in")
    add("## `flood.nim` and `pollution.nim`.")
    add("")
    add(f'const EngineCommit* = "{BC20_COMMIT}"')
    add("")
    add("type")
    add("  RobotKind* = enum")
    for name, _ in robots:
        add(f'    rt{camel(name)} = "{name}"')
    add("")
    add("  RobotSpec* = object")
    add("    ## `common/RobotType.java`'s constructor arguments, verbatim.")
    add("    cost*, dirtLimit*, soupLimit*: int")
    add("    actionCooldown*: float32")
    add("    sensorRadiusSquared*, pollutionRadiusSquared*: int")
    add("    localPollutionAdditiveEffect*: int")
    add("    localPollutionMultiplicativeEffect*: float32")
    add("    globalPollutionAmount*, maxSoupProduced*, bytecodeLimit*: int")
    add("    decisionOps*: int")
    add("")
    add("const")
    for name, nim_type, literal in consts:
        add(f"  {camel(name)}*: {nim_type} = {literal}")
    add("")
    add("  RobotSpecs*: array[RobotKind, RobotSpec] = [")
    for name, a in robots:
        add(f"    rt{camel(name)}: RobotSpec(cost: {bc20_num(a[1])}, "
            f"dirtLimit: {bc20_num(a[2])}, soupLimit: {bc20_num(a[3])},")
        add(f"      actionCooldown: {bc20_num(a[4])}'f32, "
            f"sensorRadiusSquared: {bc20_num(a[5])},")
        add(f"      pollutionRadiusSquared: {bc20_num(a[6])}, "
            f"localPollutionAdditiveEffect: {bc20_num(a[7])},")
        add(f"      localPollutionMultiplicativeEffect: {bc20_num(a[8])}'f32,")
        add(f"      globalPollutionAmount: {bc20_num(a[9])}, "
            f"maxSoupProduced: {bc20_num(a[10])},")
        add(f"      bytecodeLimit: {bc20_num(a[11])}, "
            f"decisionOps: {BC20_DECISION_OPS[name]}),")
    add("  ]")
    add("")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
#  bc21 — Battlecode 2021 "Campaign"
# ---------------------------------------------------------------------------

BC21_COMMIT = "ed39c1a49574db57e5463d720736220506280294"

# `common/RobotType.java`'s enum entries. Unlike 2020 the 2021 entries carry a
# javadoc block each, so they are matched by name and argument list rather than
# by indentation, and the arguments are:
#   spawnSource, convictionRatio, actionCooldown, initialCooldown,
#   actionRadiusSquared, sensorRadiusSquared, detectionRadiusSquared,
#   bytecodeLimit
BC21_ROBOT_RE = re.compile(
    r"^\s{4}(ENLIGHTENMENT_CENTER|POLITICIAN|SLANDERER|MUCKRAKER)"
    r"\s*\(([^)]*)\)\s*,\s*$", re.M
)

# The per-robot DECISION BUDGET that replaces the JVM bytecode limit, at one
# tenth of the Java limit. Hand-authored, not generated: it is this port's own
# rule (docs/RULES-BC21.md §Divergences item 1).
BC21_DECISION_OPS = {
    "ENLIGHTENMENT_CENTER": 2000,
    "POLITICIAN": 1500,
    "SLANDERER": 750,
    "MUCKRAKER": 1500,
}


def f32_literal(text: str) -> str:
    """The EXACT value a Java `float` literal holds, as a Nim float literal.

    Nim keeps a `const` of type `float32` at its COMPILE-TIME double value, so
    `float64(SomeFloat32Const)` yields the double nearest the decimal source
    rather than the float32 the Java constant actually is. `0.2f` is
    0.20000000298023224, and `ceil(0.2f * sqrt(25))` is 2 in Java and 1 under
    the naive transcription — a real, silent, once-every-25-rounds divergence
    that the `ec_passive` table caught. Emitting the widened float32 value
    makes the two identical whichever way Nim folds it.
    """
    value = struct.unpack("<f", struct.pack("<f", float(text)))[0]
    return repr(value)


def read_bc21_robots(engine: pathlib.Path):
    src = (engine / "engine/src/main/battlecode/common/RobotType.java").read_text()
    body = src.split("RobotType(RobotType spawnSource", 1)[0]
    out = []
    for name, args in BC21_ROBOT_RE.findall(body):
        parts = [v.strip() for v in args.split(",")]
        if len(parts) != 8:
            continue
        out.append((name, parts))
    return out


def render_bc21(engine: pathlib.Path) -> str:
    consts = read_constants_from(
        engine / "engine/src/main/battlecode/common/GameConstants.java",
        strip_comments=True)
    robots = read_bc21_robots(engine)
    if len(robots) != 4:
        raise SystemExit(
            f"::error::expected 4 RobotType entries, saw {len(robots)}")

    lines: list[str] = []
    add = lines.append
    add('## Battlecode 2021 "Campaign" gameplay constants -- GENERATED, do not edit.')
    add("##")
    add(f"## Source: github.com/battlecode/battlecode21 at commit `{BC21_COMMIT}`")
    add("## (release 2021.3.0.5), files `common/GameConstants.java` and")
    add("## `common/RobotType.java`, read by")
    add("## `tools/gen_year_constants.py --year bc21`. The `test` job of")
    add("## `.github/workflows/ci.yml` re-runs that generator with `--check`,")
    add("## which byte-diffs this file, so an edit here fails the build instead")
    add("## of quietly changing the rules under a `GameVersion` that no longer")
    add("## describes them.")
    add("##")
    add("## `RobotType.getPassiveInfluence` is NOT a constant: the Enlightenment")
    add("## Center curve and the slanderer embezzle formula live in")
    add("## `economy.nim`, backed by the committed JDK-generated tables in")
    add("## `data/bc21/`.")
    add("")
    add(f'const EngineCommit* = "{BC21_COMMIT}"')
    add('const EngineRelease* = "2021.3.0.5"')
    add("")
    add("type")
    add("  RobotKind* = enum")
    for name, _ in robots:
        add(f'    rt{camel(name)} = "{name}"')
    add("")
    add("  RobotSpec* = object")
    add("    ## `common/RobotType.java`'s constructor arguments, verbatim.")
    add("    ## `convictionRatio`, `actionCooldown` and `initialCooldown` are")
    add("    ## Java `float`s; widening them changes which round a robot is")
    add("    ## ready, so they stay float32 here.")
    add("    convictionRatio*, actionCooldown*, initialCooldown*: float32")
    add("    actionRadiusSquared*, sensorRadiusSquared*: int")
    add("    detectionRadiusSquared*, bytecodeLimit*: int")
    add("    decisionOps*: int")
    add("")
    add("const")
    for name, nim_type, literal in consts:
        if nim_type == "float32":
            literal = f32_literal(literal)
        add(f"  {camel(name)}*: {nim_type} = {literal}")
    add("")
    add("  RobotSpecs*: array[RobotKind, RobotSpec] = [")
    for name, a in robots:
        add(f"    rt{camel(name)}: RobotSpec("
            f"convictionRatio: {f32_literal(bc20_num(a[1]))}'f32,")
        add(f"      actionCooldown: {f32_literal(bc20_num(a[2]))}'f32, "
            f"initialCooldown: {f32_literal(bc20_num(a[3]))}'f32,")
        add(f"      actionRadiusSquared: {bc20_num(a[4])}, "
            f"sensorRadiusSquared: {bc20_num(a[5])},")
        add(f"      detectionRadiusSquared: {bc20_num(a[6])}, "
            f"bytecodeLimit: {bc20_num(a[7])},")
        add(f"      decisionOps: {BC21_DECISION_OPS[name]}),")
    add("  ]")
    add("")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--year", default="bc26", choices=["bc26", "bc20", "bc21"])
    ap.add_argument("--engine", required=True, type=pathlib.Path)
    ap.add_argument("--out", type=pathlib.Path, default=None)
    ap.add_argument("--check", action="store_true",
                    help="diff against the committed file; exit 1 on drift")
    args = ap.parse_args()

    out = args.out or pathlib.Path(
        f"src/battlecode/years/{args.year}/constants.nim")
    label = {"bc26": TAG, "bc20": BC20_COMMIT, "bc21": BC21_COMMIT}[args.year]
    text = {"bc26": render, "bc20": render_bc20,
            "bc21": render_bc21}[args.year](args.engine)
    if args.check:
        current = out.read_text() if out.exists() else ""
        if current != text:
            sys.stderr.write(
                f"{out} differs from a fresh generation against {label}.\n"
                "Re-run tools/gen_year_constants.py and commit the result.\n")
            return 1
        print(f"{out} matches {label}")
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
