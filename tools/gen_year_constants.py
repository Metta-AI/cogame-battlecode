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

`--year bc20` does the same job for Battlecode 2020 "Soup" against a checkout
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


def read_constants_from(path: pathlib.Path) -> list[tuple[str, str, str]]:
    src = path.read_text()
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
    add("## `tools/gen_year_constants.py --year bc20`. `tests/test_bc20_constants.nim`")
    add("## regenerates this file and byte-diffs it, so an edit here fails the build")
    add("## instead of quietly changing the rules under a `GameVersion` that no")
    add("## longer describes them.")
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--year", default="bc26", choices=["bc26", "bc20"])
    ap.add_argument("--engine", required=True, type=pathlib.Path)
    ap.add_argument("--out", type=pathlib.Path, default=None)
    ap.add_argument("--check", action="store_true",
                    help="diff against the committed file; exit 1 on drift")
    args = ap.parse_args()

    out = args.out or pathlib.Path(
        f"src/battlecode/years/{args.year}/constants.nim")
    label = TAG if args.year == "bc26" else BC20_COMMIT
    text = render(args.engine) if args.year == "bc26" else render_bc20(args.engine)
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
