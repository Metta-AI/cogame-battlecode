#!/usr/bin/env python3
"""Convert Battlecode 2024 `.map24` flatbuffers to `data/maps/bc24/<name>.json`.

CI-TIME ONLY. There is no flatbuffer reader, no Python and no JVM in any
runtime image stage: the sim reads the committed JSON. `tests/test_bc24_maps.nim`
asserts the committed files against the design note's pinned table and the
`test` job re-runs this converter with `--check`, so a hand-edited map file
fails the build.

    tools/convert_maps_bc24.py --engine /path/to/battlecode24 --out data/maps/bc24
    tools/convert_maps_bc24.py --engine ... --out data/maps/bc24 --check
    tools/convert_maps_bc24.py --engine ... --parse-all   # every .map24 reads

battlecode24 ships no generated Python bindings (only `schema/{java,js,ts}`)
and `flatc` is not in the coworld toolchain, so the tables this converter needs
are read straight off the wire with the vtable walk below. The layout is fixed
by `schema/battlecode.fbs` at the pinned commit
(`166c79bbf4156c866caf434062cb1f403c01695f`):

    table GameMap {
        name, size: Vec, symmetry: int, bodies, randomSeed: int,
        walls: [bool], water: [bool], divider: [bool],
        spawnLocations: VecTable, resourcePiles: VecTable,
        resourcePileAmounts: [int]
    }

The two engine-side transforms `GameMapIO.Serial.deserialize` applies are
applied HERE, once, exactly as the engine does them:

  * `if (amt < 100) amt *= 10` on every resource pile (the back-compat rule for
    older maps), and
  * the six `spawnLocations` centres are painted out to `r^2 <= 2` discs into a
    per-tile spawn-zone array, team A for even indices and team B for odd ones.

`spawn_centers` is then RE-DERIVED off that painted array exactly as
`LiveMap.getSpawnZoneCenters` does — index-ascending, interleaving A into even
slots and B into odd ones, with the engine's own `i-width-1` / `i+width+1`
neighbour test including its row-wrap. That order decides flag ids and
therefore the flag-broadcast re-roll order, so it is recorded rather than
recomputed from the file's own table.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys

SYMMETRIES = ["rotation", "horizontal", "vertical"]
# schema/battlecode.fbs: "The map symmetry: 0 for rotation, 1 for horizontal,
# 2 for vertical." The engine never reads it for a rule; it is recorded so the
# map card and the doctrine brief can say something true.


class Buf:
    def __init__(self, data: bytes) -> None:
        self.d = data

    def u16(self, at: int) -> int:
        return struct.unpack_from("<H", self.d, at)[0]

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

    def vec_bool(self, field: int):
        start, n = self.vector(field)
        if n == 0:
            return []
        return [b != 0 for b in self.b.d[start:start + n]]


# GameMap field ids, in declaration order.
GM_NAME, GM_SIZE, GM_SYMMETRY, GM_BODIES, GM_SEED = 0, 1, 2, 3, 4
GM_WALLS, GM_WATER, GM_DIVIDER = 5, 6, 7
GM_SPAWNLOCS, GM_PILES, GM_PILE_AMOUNTS = 8, 9, 10
# VecTable field ids.
VT_XS, VT_YS = 0, 1


def locations_within_r2(width, height, cx, cy, r2):
    """`GameWorld.getAllLocationsWithinRadiusSquaredWithoutMap`, verbatim.

    x ascending outer, y ascending inner, over the clamped `ceil(sqrt(r2)) + 1`
    box, keeping `dx^2 + dy^2 <= r2`. THE ORDER IS LOAD-BEARING everywhere it is
    used in the sim; here it only decides which tiles a spawn zone covers, but
    the same helper is ported to Nim and shares this definition.
    """
    import math
    ceiled = int(math.ceil(math.sqrt(r2))) + 1
    out = []
    for x in range(max(cx - ceiled, 0), min(cx + ceiled, width - 1) + 1):
        for y in range(max(cy - ceiled, 0), min(cy + ceiled, height - 1) + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r2:
                out.append((x, y))
    return out


def spawn_zone_centers(spawn_zones, width, height):
    """`LiveMap.getSpawnZoneCenters`, verbatim, including its row wrap.

    A tile is a centre when the tiles at `i-width-1` and `i+width+1` belong to
    the same team's spawn zone AND are `onTheMap`. The engine computes
    `onTheMap` from `indexToLocation(i +- (width+1))`, which for an index near
    a row boundary names a tile on ANOTHER ROW; that wrap is part of the
    engine's behaviour and is reproduced rather than corrected.
    """
    size = width * height

    def on_the_map(idx):
        # `LiveMap.indexToLocation` is `(idx % width, idx / width)` with JAVA's
        # remainder and division, which truncate TOWARD ZERO for a negative
        # index; Python's `%` and `//` floor instead, so the two disagree and
        # the engine's answer is the one that matters.
        y = int(idx / width) if idx >= 0 else -((-idx) // width)
        x = idx - y * width
        return 0 <= x < width and 0 <= y < height

    centers = [[0] * 6, [0] * 6]
    cur_a, cur_b = 0, 1
    for i in range(size):
        for team, cur in ((1, "a"), (2, "b")):
            if spawn_zones[i] != team:
                continue
            lo, hi = i - width - 1, i + width + 1
            if not on_the_map(lo):
                continue
            if not (0 <= lo < size) or spawn_zones[lo] != team:
                continue
            if not on_the_map(hi):
                continue
            if not (0 <= hi < size) or spawn_zones[hi] != team:
                continue
            slot = cur_a if cur == "a" else cur_b
            if slot >= 6:
                raise SystemExit("::error::more than three spawn-zone centres "
                                 f"for team {cur}")
            centers[0][slot] = i % width
            centers[1][slot] = i // width
            if cur == "a":
                cur_a += 2
            else:
                cur_b += 2
    return centers


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
    water = gm.vec_bool(GM_WATER)
    dam = gm.vec_bool(GM_DIVIDER)
    for label, arr in (("walls", walls), ("water", water), ("dam", dam)):
        if len(arr) != size:
            raise SystemExit(f"::error::{path.name}: {label} is {len(arr)}, "
                             f"expected {size}")

    piles = gm.table(GM_PILES)
    pile_xs = piles.vec_i32(VT_XS) if piles is not None else []
    pile_ys = piles.vec_i32(VT_YS) if piles is not None else []
    pile_amounts = gm.vec_i32(GM_PILE_AMOUNTS)
    crumbs = []
    for i, x in enumerate(pile_xs):
        amt = int(pile_amounts[i])
        # GameMapIO.Serial.deserialize: "support older maps by multiplying
        # crumbs by 10 if value is low". Applied ONCE, at conversion time.
        if amt < 100:
            amt *= 10
        crumbs.append([int(x), int(pile_ys[i]), amt])

    spawn_table = gm.table(GM_SPAWNLOCS)
    sxs = spawn_table.vec_i32(VT_XS) if spawn_table is not None else []
    sys_ = spawn_table.vec_i32(VT_YS) if spawn_table is not None else []
    if len(sxs) != 6 or len(sys_) != 6:
        raise SystemExit(f"::error::{path.name}: spawnLocations has "
                         f"{len(sxs)} entries, expected 6")
    spawn_zones = [0] * size
    for i in range(6):
        team = 1 if i % 2 == 0 else 2
        for (x, y) in locations_within_r2(width, height, sxs[i], sys_[i], 2):
            spawn_zones[x + y * width] = team

    centers = spawn_zone_centers(spawn_zones, width, height)

    return {
        "name": gm.string(GM_NAME),
        "width": width,
        "height": height,
        "random_seed": gm.scalar_i32(GM_SEED),
        "symmetry": SYMMETRIES[gm.scalar_i32(GM_SYMMETRY)],
        "walls": "".join("1" if v else "0" for v in walls),
        "water": "".join("1" if v else "0" for v in water),
        "dam": "".join("1" if v else "0" for v in dam),
        "crumbs": crumbs,
        "spawn_locations": [[int(sxs[i]), int(sys_[i])] for i in range(6)],
        "spawn_centers": [[centers[0][i], centers[1][i]] for i in range(6)],
    }


def render(doc: dict) -> str:
    return json.dumps(doc, sort_keys=True, separators=(",", ":")) + "\n"


def pool_names():
    pools = json.loads(
        (pathlib.Path(__file__).with_name("map_pools_bc24.json")).read_text())
    return sorted({n for pool in pools.values() for n in pool})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path,
                    help="a checkout of github.com/battlecode/battlecode24")
    ap.add_argument("--out", type=pathlib.Path)
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--parse-all", action="store_true",
                    help="read every .map24 in the engine and print a table")
    args = ap.parse_args()

    map_dir = args.engine / "engine/src/main/battlecode/world/resources"

    if args.parse_all:
        rows = []
        for source in sorted(map_dir.glob("*.map24")):
            doc = convert(source)
            rows.append((doc["name"], doc["width"], doc["height"],
                         doc["random_seed"], doc["symmetry"],
                         doc["dam"].count("1"), doc["water"].count("1"),
                         doc["walls"].count("1"), len(doc["crumbs"]),
                         sum(c[2] for c in doc["crumbs"])))
        for r in rows:
            print("\t".join(str(v) for v in r))
        print(f"{len(rows)} .map24 files parsed", file=sys.stderr)
        return 0

    if args.out is None:
        ap.error("--out is required unless --parse-all")
    names = args.only or pool_names()
    args.out.mkdir(parents=True, exist_ok=True)
    drift = []
    for name in names:
        source = map_dir / f"{name}.map24"
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
            sys.stderr.write("converted bc24 maps differ from the engine: "
                             + ", ".join(drift) + "\n")
            return 1
        print(f"{len(names)} converted bc24 maps match the engine")
    else:
        print(f"wrote {len(names)} maps to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
