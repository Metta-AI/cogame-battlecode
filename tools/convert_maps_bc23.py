#!/usr/bin/env python3
"""Convert Battlecode 2023 `.map23` flatbuffers to `data/maps/bc23/<name>.json`.

CI-TIME ONLY. There is no flatbuffer reader, no Python and no JVM in any
runtime image stage: the sim reads the committed JSON. `tests/test_bc23_maps.nim`
asserts the committed files against the design note's pinned table and the
`test` job re-runs this converter with `--check`, so a hand-edited map file
fails the build.

    tools/convert_maps_bc23.py --engine /path/to/battlecode23 --out data/maps/bc23
    tools/convert_maps_bc23.py --engine ... --out data/maps/bc23 --check
    tools/convert_maps_bc23.py --engine ... --parse-all   # every .map23 reads

battlecode23 ships no generated Python bindings and `flatc` is not in the
coworld toolchain, so the tables this converter needs are read straight off the
wire with the vtable walk below. The layout is fixed by `schema/battlecode.fbs`
at the pinned commit (`af42086ecd09709dc603b2aaa9e9b98312c9ef79`):

    table GameMap {
        name: string, minCorner: Vec, maxCorner: Vec, symmetry: int,
        bodies: SpawnedBodyTable, randomSeed: int,
        walls: [bool], clouds: [bool], currents: [int],
        islands: [int], resources: [int]
    }
    table SpawnedBodyTable {
        robotIDs: [int], teamIDs: [byte], types: [BodyType], locs: VecTable
    }

`currents` is an index into `Direction.DIRECTION_ORDER`
(`{CENTER, WEST, NORTHWEST, NORTH, NORTHEAST, EAST, SOUTHEAST, SOUTH,
SOUTHWEST}`), exactly as `GameWorld`'s constructor reads it; `resources` is a
`ResourceType` id (0 none, 1 adamantium, 2 mana, 3 elixir); `islands` is an
island id per tile with 0 meaning "no island".

`initial_bodies` is emitted SORTED ASCENDING BY ID because `LiveMap`'s
constructor sorts its bodies by id, and that order is the initial
`ObjectInfo.dynamicBodyExecOrder` — i.e. the order the headquarters take their
turns in. It is a rule, not a formatting choice.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys

SYMMETRIES = ["rotation", "horizontal", "vertical"]

BODY_TYPES = ["headquarters", "carrier", "launcher", "amplifier",
              "destabilizer", "booster"]

# Direction.DIRECTION_ORDER, the index space `currents` lives in.
DIRECTION_ORDER = ["center", "west", "northwest", "north", "northeast",
                   "east", "southeast", "south", "southwest"]


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

    def vec_bool(self, field: int):
        start, n = self.vector(field)
        if n == 0:
            return []
        return [b != 0 for b in self.b.d[start:start + n]]


# GameMap field ids, in declaration order.
GM_NAME, GM_MINCORNER, GM_MAXCORNER, GM_SYMMETRY = 0, 1, 2, 3
GM_BODIES, GM_SEED, GM_WALLS = 4, 5, 6
GM_CLOUDS, GM_CURRENTS, GM_ISLANDS, GM_RESOURCES = 7, 8, 9, 10
# SpawnedBodyTable field ids.
SB_IDS, SB_TEAMS, SB_TYPES, SB_LOCS = 0, 1, 2, 3
# VecTable field ids.
VT_XS, VT_YS = 0, 1


def convert(path: pathlib.Path) -> dict:
    data = path.read_bytes()
    buf = Buf(data)
    gm = Table(buf, buf.u32(0))

    mn = gm.struct_pos(GM_MINCORNER)
    mx = gm.struct_pos(GM_MAXCORNER)
    if mn is None or mx is None:
        raise SystemExit(f"::error::{path.name}: no corners")
    width = buf.i32(mx) - buf.i32(mn)
    height = buf.i32(mx + 4) - buf.i32(mn + 4)
    size = width * height

    walls = gm.vec_bool(GM_WALLS)
    clouds = gm.vec_bool(GM_CLOUDS)
    currents = gm.vec_i32(GM_CURRENTS)
    islands = gm.vec_i32(GM_ISLANDS)
    resources = gm.vec_i32(GM_RESOURCES)
    # `GameMapIO.deserialize` reads exactly `width * height` entries out of
    # each of the five per-tile vectors and ignores whatever follows, and
    # three of the 103 official maps (`Frog`, `Orbit`, `Rewind`) really do
    # carry an over-long vector. Reproduce the engine: a SHORT vector is a
    # broken file, a long one is truncated exactly as the engine truncates it.
    for label, arr in (("walls", walls), ("clouds", clouds),
                       ("currents", currents), ("islands", islands),
                       ("resources", resources)):
        if len(arr) < size:
            raise SystemExit(f"::error::{path.name}: {label} is {len(arr)}, "
                             f"expected at least {size}")
    walls = walls[:size]
    clouds = clouds[:size]
    currents = currents[:size]
    islands = islands[:size]
    resources = resources[:size]

    bodies = gm.table(GM_BODIES)
    spawns = []
    if bodies is not None:
        ids = bodies.vec_i32(SB_IDS)
        teams = bodies.vec_i8(SB_TEAMS)
        types = bodies.vec_i8(SB_TYPES)
        locs = bodies.table(SB_LOCS)
        xs = locs.vec_i32(VT_XS) if locs is not None else []
        ys = locs.vec_i32(VT_YS) if locs is not None else []
        if not (len(ids) == len(teams) == len(types) == len(xs) == len(ys)):
            raise SystemExit(f"::error::{path.name}: ragged body table")
        for i in range(len(ids)):
            spawns.append([int(ids[i]), int(xs[i]) - buf.i32(mn),
                           int(ys[i]) - buf.i32(mn + 4),
                           int(teams[i]), int(types[i])])
    # LiveMap sorts its initial bodies ascending by id, and that order IS the
    # initial exec order. Emit it sorted so the loader never has to.
    spawns.sort(key=lambda row: row[0])

    return {
        "name": gm.string(GM_NAME),
        "width": width,
        "height": height,
        "random_seed": gm.scalar_i32(GM_SEED),
        "symmetry": SYMMETRIES[gm.scalar_i32(GM_SYMMETRY)],
        "rounds": 2000,
        "walls": "".join("1" if v else "0" for v in walls),
        "clouds": "".join("1" if v else "0" for v in clouds),
        "currents": [[i % width, i // width, int(v)]
                     for i, v in enumerate(currents) if v != 0],
        "islands": [[i % width, i // width, int(v)]
                    for i, v in enumerate(islands) if v != 0],
        "resources": [[i % width, i // width, int(v)]
                      for i, v in enumerate(resources) if v != 0],
        "initial_bodies": spawns,
    }


def render(doc: dict) -> str:
    out = {k: v for k, v in doc.items() if not k.startswith("_")}
    return json.dumps(out, sort_keys=True, separators=(",", ":")) + "\n"


def pool_names():
    pools = json.loads(
        (pathlib.Path(__file__).with_name("map_pools_bc23.json")).read_text())
    return sorted({n for pool in pools.values() for n in pool})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path,
                    help="a checkout of github.com/battlecode/battlecode23")
    ap.add_argument("--out", type=pathlib.Path)
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--parse-all", action="store_true",
                    help="read every .map23 in the engine and print a table")
    args = ap.parse_args()

    map_dir = args.engine / "engine/src/main/battlecode/world/resources"

    if args.parse_all:
        rows = []
        for source in sorted(map_dir.glob("*.map23")):
            doc = convert(source)
            hq = sum(1 for b in doc["initial_bodies"] if b[4] == 0 and b[3] == 0)
            island_ids = {c[2] for c in doc["islands"]}
            rows.append((doc["name"], doc["width"], doc["height"],
                         doc["random_seed"], doc["symmetry"],
                         doc["walls"].count("1"), doc["clouds"].count("1"),
                         len(doc["currents"]), len(island_ids),
                         len(doc["islands"]),
                         sum(1 for r in doc["resources"] if r[2] == 1),
                         sum(1 for r in doc["resources"] if r[2] == 2),
                         sum(1 for r in doc["resources"] if r[2] == 3),
                         hq))
        for r in rows:
            print("\t".join(str(v) for v in r))
        print(f"{len(rows)} .map23 files parsed", file=sys.stderr)
        return 0

    if args.out is None:
        ap.error("--out is required unless --parse-all")
    names = args.only or pool_names()
    args.out.mkdir(parents=True, exist_ok=True)
    drift = []
    for name in names:
        source = map_dir / f"{name}.map23"
        if not source.exists():
            sys.stderr.write(f"missing map at {args.engine}: {name}\n")
            return 1
        text = render(convert(source))
        target = args.out / f"{name}.json"
        if args.check:
            if not target.exists() or target.read_text() != text:
                drift.append(name)
        else:
            target.write_text(text)
    if args.check:
        if drift:
            sys.stderr.write("converted bc23 maps differ from the engine: "
                             + ", ".join(drift) + "\n")
            return 1
        print(f"{len(names)} converted bc23 maps match the engine")
    else:
        print(f"wrote {len(names)} maps to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
