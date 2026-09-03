#!/usr/bin/env python3
"""Generate src/battlecode/years/bc26/constants.nim from the pinned engine.

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
    if re.fullmatch(r"[-+0-9._eE]+[LlFfDd]?", text):
        text = text.rstrip("LlFfDd")
    if java_type == "int":
        return "int", str(int(text, 0))
    if java_type == "long":
        return "int64", str(int(text, 0))
    if java_type == "float":
        return "float32", repr(float(text))
    return "float64", repr(float(text))


def read_constants(engine: pathlib.Path) -> list[tuple[str, str, str]]:
    src = (engine / "engine/src/main/battlecode/common/GameConstants.java").read_text()
    out = []
    for java_type, name, raw in CONST_RE.findall(src):
        nim_type, literal = nim_literal(java_type, raw)
        out.append((name, nim_type, literal))
    return out


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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path)
    ap.add_argument("--out", type=pathlib.Path,
                    default=pathlib.Path("src/battlecode/years/bc26/constants.nim"))
    ap.add_argument("--check", action="store_true",
                    help="diff against the committed file; exit 1 on drift")
    args = ap.parse_args()

    text = render(args.engine)
    if args.check:
        current = args.out.read_text() if args.out.exists() else ""
        if current != text:
            sys.stderr.write(
                f"{args.out} differs from a fresh generation against {TAG}.\n"
                "Re-run tools/gen_year_constants.py and commit the result.\n")
            return 1
        print(f"{args.out} matches {TAG}")
        return 0
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text)
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
