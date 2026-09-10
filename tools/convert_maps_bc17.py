#!/usr/bin/env python3
"""Convert Battlecode 2017 `.map17` flatbuffers to `data/maps/bc17/<name>.json`.

CI-TIME AND BUILD-TIME ONLY, AND PURE PYTHON. There is no flatbuffer reader, no
Python, no Node and NO JVM in any runtime image stage, and there is no JVM in
this script either: the 2017 map resources live inside the pinned oracle jar
(`battlecode/world/resources/*.map17`, all seventy of them), so this converter
reads them straight out of the jar with `zipfile` and the vtable walk below.
The sim reads only the committed JSON.

    tools/convert_maps_bc17.py --jar battlecode-2017.1.6.2.jar --out data/maps/bc17
    tools/convert_maps_bc17.py --jar ... --out data/maps/bc17 --check
    tools/convert_maps_bc17.py --jar ... --parse-all   # every .map17 reads

`tests/test_bc17_maps.nim` asserts the committed files against the design
note's measured table, the `test` job re-runs this converter with `--check`, so
a hand-edited map file fails the build, and `parity-oracle-bc17`'s Tier B
byte-diffs every one of them against the JVM's own `LiveMap` fields.

The layout is fixed by `schema/battlecode.fbs` at the pinned engine commit
(`165d8a8ef24f03e13a101bb8bc9f5b32dcb33c6c`) and was re-read off the jar's own
`battlecode/schema/*.class` accessors with `javap`:

    table GameMap {
        name: string, minCorner: Vec, maxCorner: Vec,
        bodies: SpawnedBodyTable, trees: NeutralTreeTable, randomSeed: int
    }
    struct Vec { x: float; y: float; }             // FLOAT, not int: 2017 is
                                                  // the continuous-space year
    table SpawnedBodyTable {
        robotIDs: [int], teamIDs: [byte], types: [BodyType], locs: VecTable
    }
    table NeutralTreeTable {
        robotIDs: [int], locs: VecTable, radii: [float], healths: [float],
        maxHealths: [float], containedBullets: [int],
        containedBodies: [BodyType]
    }
    table VecTable { xs: [float], ys: [float] }

TWO CONVERSION RULES ARE TAKEN FROM THE ENGINE RATHER THAN FROM THE FILE, and
both are `GameMapIO.Serial.deserialize`'s own (docs/RULES-BC17.md, spec-vs-engine
disagreements 1 and the neutral-tree health rule):

  * `rounds` is ALWAYS `GameConstants.GAME_DEFAULT_ROUNDS` = 3000. The engine
    never reads a round count out of the map file (`GameMapIO.java:235`), and
    all seventy official maps therefore run 3000 rounds (2999 played).
  * a neutral tree's health and max health are RECOMPUTED as
    `radius * NEUTRAL_TREE_HEALTH_RATE` (= 200 x radius) and the file's own
    `healths`/`maxHealths` vectors are IGNORED — `GameMapIO.java:389-400`
    computes them and only warns on a mismatch.

`initial_bodies` is emitted SORTED ASCENDING BY ID because `LiveMap`'s
constructor sorts its bodies by id (`LiveMap.java:67`) and that order is the
initial `ObjectInfo.dynamicBodyExecOrder` — i.e. the order the archons take
their turns in. It is a rule, not a formatting choice.

Every float is emitted as the shortest decimal that round-trips its float64
widening, so `parseFloat` + `float32()` on the Nim side recovers the exact
float32 bit pattern the engine holds. Widths and heights are computed with a
float32 subtraction, exactly as the `strictfp` engine computes them.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys
import zipfile

BODY_TYPES = ["archon", "gardener", "lumberjack", "soldier", "tank", "scout",
              "tree_bullet", "tree_neutral", "bullet", "none"]
  # battlecode/schema/BodyType, in ordinal order.

TEAMS = ["neutral", "A", "B"]
  # battlecode/util/TeamMapping: 0 NEUTRAL, 1 A, 2 B.

STARTING_HEALTH = {
    # `RobotType.getStartingHealth()`: an ARCHON and a GARDENER are born at
    # full health, every fighter at `PLANTED_UNIT_STARTING_HEALTH_FRACTION`
    # (0.2f) x maxHealth. Only initial ARCHONS ever appear in a map file, so
    # only that row is ever read here; the rest are named so the dump stays
    # honest if a future map carries something else.
    "archon": 400.0, "gardener": 40.0, "lumberjack": 10.0,
    "soldier": 10.0, "tank": 40.0, "scout": 2.0,
}

MAP_RESOURCE_DIR = "battlecode/world/resources"
GAME_DEFAULT_ROUNDS = 3000
NEUTRAL_TREE_HEALTH_RATE = 200.0


def f32(value: float) -> float:
    """The float32 rounding of `value`, kept as a Python float."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


class Buf:
    def __init__(self, data: bytes) -> None:
        self.d = data

    def u16(self, at: int) -> int:
        return struct.unpack_from("<H", self.d, at)[0]

    def i8(self, at: int) -> int:
        return struct.unpack_from("<b", self.d, at)[0]

    def i32(self, at: int) -> int:
        return struct.unpack_from("<i", self.d, at)[0]

    def u32(self, at: int) -> int:
        return struct.unpack_from("<I", self.d, at)[0]

    def f32(self, at: int) -> float:
        return struct.unpack_from("<f", self.d, at)[0]


class Table:
    """One flatbuffer table: an absolute position plus its vtable."""

    def __init__(self, buf: Buf, pos: int) -> None:
        self.b = buf
        self.pos = pos
        self.vtable = pos - buf.i32(pos)
        self.vlen = buf.u16(self.vtable)

    def offset(self, field: int) -> int:
        slot = 4 + field * 2
        if slot >= self.vlen:
            return 0
        return self.b.u16(self.vtable + slot)

    def indirect(self, field: int):
        o = self.offset(field)
        if o == 0:
            return None
        at = self.pos + o
        return at + self.b.i32(at)

    def table(self, field: int):
        at = self.indirect(field)
        return None if at is None else Table(self.b, at)

    def struct_pos(self, field: int):
        o = self.offset(field)
        return None if o == 0 else self.pos + o

    def scalar_i32(self, field: int, default: int = 0) -> int:
        o = self.offset(field)
        return default if o == 0 else self.b.i32(self.pos + o)

    def string(self, field: int) -> str:
        at = self.indirect(field)
        if at is None:
            return ""
        length = self.b.u32(at)
        return self.b.d[at + 4:at + 4 + length].decode("utf-8")

    def vector(self, field: int):
        at = self.indirect(field)
        if at is None:
            return (0, 0)
        return (at + 4, self.b.u32(at))

    def vec_i32(self, field: int):
        start, n = self.vector(field)
        if n == 0:
            return []
        return list(struct.unpack_from(f"<{n}i", self.b.d, start))

    def vec_i8(self, field: int):
        start, n = self.vector(field)
        if n == 0:
            return []
        return list(struct.unpack_from(f"<{n}b", self.b.d, start))

    def vec_f32(self, field: int):
        start, n = self.vector(field)
        if n == 0:
            return []
        return list(struct.unpack_from(f"<{n}f", self.b.d, start))


# GameMap field ids, in declaration order.
GM_NAME, GM_MINCORNER, GM_MAXCORNER = 0, 1, 2
GM_BODIES, GM_TREES, GM_SEED = 3, 4, 5
# SpawnedBodyTable field ids.
SB_IDS, SB_TEAMS, SB_TYPES, SB_LOCS = 0, 1, 2, 3
# NeutralTreeTable field ids.
NT_IDS, NT_LOCS, NT_RADII, NT_HEALTHS = 0, 1, 2, 3
NT_MAXHEALTHS, NT_BULLETS, NT_BODIES = 4, 5, 6
# VecTable field ids.
VT_XS, VT_YS = 0, 1


def convert(data: bytes, name_hint: str) -> dict:
    buf = Buf(data)
    gm = Table(buf, buf.u32(0))

    mn = gm.struct_pos(GM_MINCORNER)
    mx = gm.struct_pos(GM_MAXCORNER)
    if mn is None or mx is None:
        raise SystemExit(f"::error::{name_hint}: no corners")
    min_x, min_y = buf.f32(mn), buf.f32(mn + 4)
    max_x, max_y = buf.f32(mx), buf.f32(mx + 4)
    width = f32(max_x - min_x)
    height = f32(max_y - min_y)

    bodies = []
    bt = gm.table(GM_BODIES)
    if bt is not None:
        ids = bt.vec_i32(SB_IDS)
        teams = bt.vec_i8(SB_TEAMS)
        types = bt.vec_i8(SB_TYPES)
        locs = bt.table(SB_LOCS)
        xs = locs.vec_f32(VT_XS) if locs is not None else []
        ys = locs.vec_f32(VT_YS) if locs is not None else []
        if not (len(ids) == len(teams) == len(types) == len(xs) == len(ys)):
            raise SystemExit(f"::error::{name_hint}: ragged body table")
        for i in range(len(ids)):
            kind = BODY_TYPES[types[i]]
            if kind in ("tree_bullet", "tree_neutral", "bullet", "none"):
                raise SystemExit(
                    f"::error::{name_hint}: body {ids[i]} is a {kind}; the "
                    "2017 body table carries only robots")
            bodies.append({
                "kind": "robot",
                "id": int(ids[i]),
                "team": TEAMS[teams[i]],
                "type": kind,
                "x": xs[i],
                "y": ys[i],
            })

    tt = gm.table(GM_TREES)
    if tt is not None:
        ids = tt.vec_i32(NT_IDS)
        radii = tt.vec_f32(NT_RADII)
        cb = tt.vec_i32(NT_BULLETS)
        cbody = tt.vec_i8(NT_BODIES)
        locs = tt.table(NT_LOCS)
        xs = locs.vec_f32(VT_XS) if locs is not None else []
        ys = locs.vec_f32(VT_YS) if locs is not None else []
        if not (len(ids) == len(radii) == len(cb) == len(cbody) ==
                len(xs) == len(ys)):
            raise SystemExit(f"::error::{name_hint}: ragged tree table")
        for i in range(len(ids)):
            contained = BODY_TYPES[cbody[i]]
            if contained in ("tree_bullet", "tree_neutral", "bullet"):
                raise SystemExit(
                    f"::error::{name_hint}: tree {ids[i]} contains a "
                    f"{contained}")
            bodies.append({
                "kind": "tree",
                "id": int(ids[i]),
                "team": "neutral",
                "radius": radii[i],
                "x": xs[i],
                "y": ys[i],
                "contained_bullets": int(cb[i]),
                # `GameMapIO` RECOMPUTES the health from the radius and only
                # warns when the file disagrees, so the file's own `healths`
                # and `maxHealths` vectors are deliberately not read.
                "health": f32(radii[i] * NEUTRAL_TREE_HEALTH_RATE),
                "contained_robot": ("-" if contained == "none" else contained),
            })

    # LiveMap sorts its initial bodies ascending by id, and that order IS the
    # initial exec order. Emit it sorted so the loader never has to.
    bodies.sort(key=lambda row: row["id"])

    return {
        "name": gm.string(GM_NAME),
        "width": width,
        "height": height,
        "origin": [min_x, min_y],
        "seed": gm.scalar_i32(GM_SEED),
        "rounds": GAME_DEFAULT_ROUNDS,
        "initial_bodies": bodies,
    }


def render(doc: dict) -> str:
    return json.dumps(doc, sort_keys=True, separators=(",", ":")) + "\n"


def bits(value: float) -> str:
    return "0x%08x" % struct.unpack("<I", struct.pack("<f", value))[0]


def dump_bits(doc: dict) -> str:
    """The canonical raw-bits dump `tools/JavaBc17Tables.java maps` prints.

    Tier B of `parity-oracle-bc17` diffs the two, which is what proves this
    pure-Python flatbuffer walk against the JVM's own `LiveMap` rather than
    trusting it. Every float is raw IEEE-754 bits, never a decimal.
    """
    out = []
    out.append("MAP %s w=%s h=%s ox=%s oy=%s seed=%d rounds=%d bodies=%d" % (
        doc["name"], bits(doc["width"]), bits(doc["height"]),
        bits(doc["origin"][0]), bits(doc["origin"][1]),
        doc["seed"], doc["rounds"], len(doc["initial_bodies"])))
    for b in doc["initial_bodies"]:
        if b["kind"] == "robot":
            out.append("R %d team=%s ty=%s x=%s y=%s hp=%s" % (
                b["id"], b["team"], b["type"].upper(),
                bits(b["x"]), bits(b["y"]),
                bits(STARTING_HEALTH[b["type"]])))
        else:
            out.append("E %d team=NEUTRAL x=%s y=%s r=%s hp=%s cb=%d crob=%s" %
                       (b["id"], bits(b["x"]), bits(b["y"]),
                        bits(b["radius"]), bits(b["health"]),
                        b["contained_bullets"],
                        ("-" if b["contained_robot"] == "-"
                         else b["contained_robot"].upper())))
    return "\n".join(out) + "\n"


def pool_names():
    pools = json.loads(
        (pathlib.Path(__file__).with_name("map_pools_bc17.json")).read_text())
    return sorted({n for key, pool in pools.items()
                   if not key.startswith("_") for n in pool})


def read_maps(jar: pathlib.Path):
    with zipfile.ZipFile(jar) as zf:
        out = {}
        for entry in zf.namelist():
            if entry.startswith(MAP_RESOURCE_DIR) and entry.endswith(".map17"):
                stem = entry.rsplit("/", 1)[-1][: -len(".map17")]
                out[stem] = zf.read(entry)
        return out


def archon_stats(doc: dict):
    per = {"A": [], "B": []}
    for b in doc["initial_bodies"]:
        if b["kind"] == "robot" and b["type"] == "archon":
            per[b["team"]].append((b["x"], b["y"]))
    sep_min, sep_max = -1.0, -1.0
    for a in per["A"]:
        for b in per["B"]:
            d = ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5
            if sep_min < 0 or d < sep_min:
                sep_min = d
            if d > sep_max:
                sep_max = d
    return per, sep_min, sep_max


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jar", required=True, type=pathlib.Path,
                    help="the pinned org.battlecode:battlecode:2017.1.6.2 jar")
    ap.add_argument("--out", type=pathlib.Path)
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--parse-all", action="store_true",
                    help="read every .map17 in the jar and print a table")
    ap.add_argument("--dump-bits", action="store_true",
                    help="print the canonical raw-bits LiveMap dump that "
                         "tools/JavaBc17Tables.java maps prints, from the "
                         "COMMITTED json (Tier B diffs the two)")
    args = ap.parse_args()

    maps = read_maps(args.jar)

    if args.parse_all:
        rows = []
        for stem in sorted(maps):
            doc = convert(maps[stem], stem)
            trees = [b for b in doc["initial_bodies"] if b["kind"] == "tree"]
            per, sep_min, sep_max = archon_stats(doc)
            rows.append((
                doc["name"], round(doc["width"], 3), round(doc["height"], 3),
                doc["seed"], len(per["A"]), len(per["B"]), len(trees),
                round(sum(t["radius"] for t in trees), 2),
                (min((t["radius"] for t in trees), default=0.0)),
                (max((t["radius"] for t in trees), default=0.0)),
                sum(1 for t in trees if t["contained_bullets"] > 0),
                sum(1 for t in trees if t["contained_robot"] != "-"),
                round(sep_min, 2), round(sep_max, 2),
                round(doc["origin"][0], 3), round(doc["origin"][1], 3),
                doc["rounds"]))
        for r in rows:
            print("\t".join(str(v) for v in r))
        print(f"{len(rows)} .map17 files parsed", file=sys.stderr)
        return 0

    if args.dump_bits:
        names = args.only or pool_names()
        for name in names:
            if args.out is not None:
                doc = json.loads((args.out / f"{name}.json").read_text())
            else:
                doc = convert(maps[name], name)
            sys.stdout.write(dump_bits(doc))
        return 0

    if args.out is None:
        ap.error("--out is required unless --parse-all")
    names = args.only or pool_names()
    args.out.mkdir(parents=True, exist_ok=True)
    drift = []
    for name in names:
        if name not in maps:
            sys.stderr.write(f"missing map in {args.jar}: {name}\n")
            return 1
        text = render(convert(maps[name], name))
        target = args.out / f"{name}.json"
        if args.check:
            if not target.exists() or target.read_text() != text:
                drift.append(name)
        else:
            target.write_text(text)
    if args.check:
        if drift:
            sys.stderr.write("converted bc17 maps differ from the jar: "
                             + ", ".join(drift) + "\n")
            return 1
        print(f"{len(names)} converted bc17 maps match the jar")
    else:
        print(f"wrote {len(names)} maps to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
