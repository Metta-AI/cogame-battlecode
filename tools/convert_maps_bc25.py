#!/usr/bin/env python3
"""Convert Battlecode 2025 `.map25` flatbuffers to `data/maps/bc25/<name>.json`.

CI-TIME ONLY. There is no flatbuffer reader, no Python and no JVM in any
runtime image stage: the sim reads the committed JSON. `tests/test_bc25_maps.nim`
asserts the committed files against the design note's pinned table and the
`test` job re-runs this converter with `--check`, so a hand-edited map file
fails the build.

    tools/convert_maps_bc25.py --engine /path/to/battlecode25 --out data/maps/bc25
    tools/convert_maps_bc25.py --engine ... --out data/maps/bc25 --check
    tools/convert_maps_bc25.py --engine ... --parse-all   # every .map25 reads

battlecode25 ships no generated Python bindings and `flatc` is not in the
coworld toolchain, so the tables this converter needs are read straight off the
wire with the vtable walk below. The layout is fixed by `schema/battlecode.fbs`
at the pinned commit (`28975a487c1a30ed2b5bed644fe6ecd2c3dd1482`):

    table GameMap {
        name: string, size: Vec, symmetry: int,
        initialBodies: InitialBodyTable, randomSeed: int,
        walls: [bool], paint: [byte], ruins: VecTable,
        paintPatterns: [int]
    }
    struct SpawnAction { id: ushort, x: ushort, y: ushort,
                         team: byte, robotType: RobotType }

`paintPatterns` IS READ AND THEN IGNORED, exactly as `GameWorld` does
("//ignore patterns passed in with map and use hardcoded values") — it is
recorded in the `--parse-all` table only so the reader is provably complete.

`ruins` is the file's own list and does NOT contain the four starting-tower
tiles; `GameWorld`'s constructor adds those to `allRuins` itself, and
`years/bc25/world.nim` reproduces that.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys

SYMMETRIES = ["rotation", "horizontal", "vertical"]

ROBOT_TYPES = ["none", "paint_tower", "money_tower", "defense_tower",
               "soldier", "splasher", "mopper"]


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

    def vec_struct(self, field: int, size: int):
        """A vector of inline STRUCTS: absolute positions, in file order."""
        start, n = self.vector(field)
        return [start + i * size for i in range(n)]


# GameMap field ids, in declaration order.
GM_NAME, GM_SIZE, GM_SYMMETRY, GM_BODIES, GM_SEED = 0, 1, 2, 3, 4
GM_WALLS, GM_PAINT, GM_RUINS, GM_PATTERNS = 5, 6, 7, 8
# InitialBodyTable field ids.
IB_SPAWNS = 0
# VecTable field ids.
VT_XS, VT_YS = 0, 1

# `struct SpawnAction { id: ushort, x: ushort, y: ushort, team: byte,
#  robotType: RobotType(byte) }` — alignment 2, so 8 bytes with one pad byte.
SPAWN_SIZE = 8


def convert(path: pathlib.Path) -> dict:
    data = path.read_bytes()
    buf = Buf(data)
    gm = Table(buf, buf.u32(0))

    size_pos = gm.struct_pos(GM_SIZE)
    if size_pos is None:
        raise SystemExit(f"::error::{path.name}: no size")
    width, height = buf.i32(size_pos), buf.i32(size_pos + 4)
    size = width * height

    walls = gm.vec_bool(GM_WALLS)
    if len(walls) != size:
        raise SystemExit(f"::error::{path.name}: walls is {len(walls)}, "
                         f"expected {size}")
    paint = gm.vec_i8(GM_PAINT)
    if len(paint) != size:
        raise SystemExit(f"::error::{path.name}: paint is {len(paint)}, "
                         f"expected {size}")

    ruins_table = gm.table(GM_RUINS)
    rxs = ruins_table.vec_i32(VT_XS) if ruins_table is not None else []
    rys = ruins_table.vec_i32(VT_YS) if ruins_table is not None else []
    if len(rxs) != len(rys):
        raise SystemExit(f"::error::{path.name}: ragged ruin table")

    bodies = gm.table(GM_BODIES)
    spawns = []
    if bodies is not None:
        for at in bodies.vec_struct(IB_SPAWNS, SPAWN_SIZE):
            spawns.append([
                buf.u16(at),          # id
                buf.u16(at + 2),      # x
                buf.u16(at + 4),      # y
                buf.i8(at + 6),       # team
                buf.i8(at + 7),       # robotType
            ])

    # `paintPatterns` is read so the reader is provably complete, and then
    # DISCARDED: `GameWorld` ignores the map's copy and uses four hard-coded
    # ints (docs/RULES-BC25.md §Divergences item 7).
    patterns = gm.vec_i32(GM_PATTERNS)

    doc = {
        "name": gm.string(GM_NAME),
        "width": width,
        "height": height,
        "random_seed": gm.scalar_i32(GM_SEED),
        "symmetry": SYMMETRIES[gm.scalar_i32(GM_SYMMETRY)],
        "walls": "".join("1" if v else "0" for v in walls),
        "ruins": [[int(rxs[i]), int(rys[i])] for i in range(len(rxs))],
        "paint": [[i % width, i // width, int(v)]
                  for i, v in enumerate(paint) if v != 0],
        "initial_bodies": spawns,
    }
    doc["_patterns"] = patterns
    return doc


def render(doc: dict) -> str:
    out = {k: v for k, v in doc.items() if not k.startswith("_")}
    return json.dumps(out, sort_keys=True, separators=(",", ":")) + "\n"


def pool_names():
    pools = json.loads(
        (pathlib.Path(__file__).with_name("map_pools_bc25.json")).read_text())
    return sorted({n for pool in pools.values() for n in pool})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path,
                    help="a checkout of github.com/battlecode/battlecode25")
    ap.add_argument("--out", type=pathlib.Path)
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--parse-all", action="store_true",
                    help="read every .map25 in the engine and print a table")
    args = ap.parse_args()

    map_dir = args.engine / "engine/src/main/battlecode/world/resources"

    if args.parse_all:
        rows = []
        for source in sorted(map_dir.glob("*.map25")):
            doc = convert(source)
            rows.append((doc["name"], doc["width"], doc["height"],
                         doc["random_seed"], doc["symmetry"],
                         doc["walls"].count("1"), len(doc["ruins"]),
                         len(doc["paint"]), len(doc["initial_bodies"]),
                         len(doc["_patterns"])))
        for r in rows:
            print("\t".join(str(v) for v in r))
        print(f"{len(rows)} .map25 files parsed", file=sys.stderr)
        return 0

    if args.out is None:
        ap.error("--out is required unless --parse-all")
    names = args.only or pool_names()
    args.out.mkdir(parents=True, exist_ok=True)
    drift = []
    for name in names:
        source = map_dir / f"{name}.map25"
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
            sys.stderr.write("converted bc25 maps differ from the engine: "
                             + ", ".join(drift) + "\n")
            return 1
        print(f"{len(names)} converted bc25 maps match the engine")
    else:
        print(f"wrote {len(names)} maps to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
