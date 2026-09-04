#!/usr/bin/env python3
"""Convert Battlecode 2020 `.map20` flatbuffers to `data/maps/bc20/<name>.json`.

CI-TIME ONLY. There is no flatbuffer reader, no Python and no JVM in any
runtime image stage: the sim reads the committed JSON. `tests/test_bc20_maps.nim`
re-converts and diffs (through `tools/ci/check_bc20_maps.sh`), so a hand-edited
map file fails the build.

    tools/convert_maps_bc20.py --engine /path/to/battlecode20 --out data/maps/bc20
    tools/convert_maps_bc20.py --engine ... --out data/maps/bc20 --check

battlecode20 ships no generated Python bindings (only `schema/java`,
`schema/js` and `schema/ts`), and `flatc` is not available in the coworld
toolchain, so the four tables this converter needs are read directly off the
wire with the vtable walk below. The layout is fixed by `schema/battlecode.fbs`
at the pinned commit and is asserted field by field.

SYMMETRY IS NOT IN THE FILE. The 2020 `.map20` schema has no symmetry field, so
it is DETECTED exactly the way the engine does in
`world/control/CowControlProvider.getSymmetry`: candidates in the order
`vertical`, `horizontal`, `rotational`; each eliminated by the first tile where
soup, elevation ("dirt") or robot type disagrees under that transform; the first
survivor wins; `rotational` when none survives. Engine naming: `vertical` flips
x (`symmetricX = w-1-x`), `horizontal` flips y (`symmetricY = h-1-y`),
`rotational` flips both.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys

# schema/battlecode.fbs `enum BodyType : byte`, in declaration order.
BODY_TYPES = ["hq", "miner", "refinery", "vaporator", "design_school",
              "fulfillment_center", "landscaper", "delivery_drone",
              "net_gun", "cow"]
# world/TeamMapping.java: 1 -> A, 2 -> B; cows are NEUTRAL (team id 0).
TEAMS = {0: "neutral", 1: "A", 2: "B"}


# ---------------------------------------------------------------------------
#  A minimal flatbuffer reader (little-endian, as the format mandates)
# ---------------------------------------------------------------------------

class Buf:
    def __init__(self, data: bytes) -> None:
        self.d = data

    def u16(self, at: int) -> int:
        return struct.unpack_from("<H", self.d, at)[0]

    def i16(self, at: int) -> int:
        return struct.unpack_from("<h", self.d, at)[0]

    def i32(self, at: int) -> int:
        return struct.unpack_from("<i", self.d, at)[0]

    def u32(self, at: int) -> int:
        return struct.unpack_from("<I", self.d, at)[0]

    def i8(self, at: int) -> int:
        return struct.unpack_from("<b", self.d, at)[0]


class Table:
    """One flatbuffer table: an absolute position plus its vtable."""

    def __init__(self, buf: Buf, pos: int) -> None:
        self.b = buf
        self.pos = pos
        self.vtable = pos - buf.i32(pos)
        self.vlen = buf.u16(self.vtable)

    def offset(self, field: int) -> int:
        """Byte offset of field `field` from the table position, 0 if absent."""
        slot = 4 + field * 2
        if slot >= self.vlen:
            return 0
        return self.b.u16(self.vtable + slot)

    def indirect(self, field: int) -> int | None:
        o = self.offset(field)
        if o == 0:
            return None
        at = self.pos + o
        return at + self.b.i32(at)

    def table(self, field: int) -> "Table | None":
        at = self.indirect(field)
        return None if at is None else Table(self.b, at)

    def struct_pos(self, field: int) -> int | None:
        # An inline struct lives AT the field offset, not behind an indirection.
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
        return self.d_slice(at + 4, length).decode("utf-8")

    def d_slice(self, at: int, length: int) -> bytes:
        return self.b.d[at:at + length]

    def vector(self, field: int) -> tuple[int, int]:
        """(first element position, element count); (0, 0) when absent."""
        at = self.indirect(field)
        if at is None:
            return (0, 0)
        return (at + 4, self.b.u32(at))

    def vec_i32(self, field: int) -> list[int]:
        start, n = self.vector(field)
        if n == 0:
            return []
        return list(struct.unpack_from(f"<{n}i", self.b.d, start))

    def vec_i8(self, field: int) -> list[int]:
        start, n = self.vector(field)
        if n == 0:
            return []
        return list(struct.unpack_from(f"<{n}b", self.b.d, start))

    def vec_bool(self, field: int) -> list[bool]:
        start, n = self.vector(field)
        return [bool(self.b.d[start + i]) for i in range(n)]


# GameMap field ids, in `schema/battlecode.fbs` declaration order.
GM_NAME, GM_MIN, GM_MAX, GM_BODIES = 0, 1, 2, 3
GM_SEED, GM_DIRT, GM_WATER, GM_POLLUTION, GM_SOUP, GM_INITIAL_WATER = 4, 5, 6, 7, 8, 9
# SpawnedBodyTable field ids.
SB_IDS, SB_TEAMS, SB_TYPES, SB_LOCS = 0, 1, 2, 3
# VecTable field ids.
VT_XS, VT_YS = 0, 1


def detect_symmetry(width: int, height: int, soup: list[int],
                    dirt: list[int], body_type_at: dict[int, str]) -> str:
    """`CowControlProvider.getSymmetry`, ported literally.

    The candidate list is scanned x-major then y (the engine's own loop order)
    and a candidate is dropped at the first disagreeing tile. The engine breaks
    out of both loops the moment one candidate is left and returns
    `possible.get(0)`, so the answer is the FIRST SURVIVOR in the declaration
    order [vertical, horizontal, rotational], defaulting to rotational.
    """
    possible = ["vertical", "horizontal", "rotational"]

    def sym_x(x: int, s: str) -> int:
        return x if s == "horizontal" else width - 1 - x

    def sym_y(y: int, s: str) -> int:
        return y if s == "vertical" else height - 1 - y

    for x in range(width):
        for y in range(height):
            here = x + width * y
            for s in list(reversed(possible)):
                there = sym_x(x, s) + width * sym_y(y, s)
                if soup[here] != soup[there] or dirt[here] != dirt[there]:
                    possible.remove(s)
                    continue
                a = body_type_at.get(here)
                b = body_type_at.get(there)
                if (a is not None) or (b is not None):
                    if a is None or b is None or a != b:
                        possible.remove(s)
            if len(possible) <= 1:
                break
        if len(possible) <= 1:
            break
    return possible[0] if possible else "rotational"


def convert(path: pathlib.Path) -> dict:
    data = path.read_bytes()
    buf = Buf(data)
    root_pos = buf.u32(0)
    gm = Table(buf, root_pos)

    min_pos = gm.struct_pos(GM_MIN)
    max_pos = gm.struct_pos(GM_MAX)
    if min_pos is None or max_pos is None:
        raise SystemExit(f"::error::{path.name}: no minCorner/maxCorner")
    min_x, min_y = buf.i32(min_pos), buf.i32(min_pos + 4)
    max_x, max_y = buf.i32(max_pos), buf.i32(max_pos + 4)
    width, height = max_x - min_x, max_y - min_y
    size = width * height

    dirt = gm.vec_i32(GM_DIRT)
    water = gm.vec_bool(GM_WATER)
    pollution = gm.vec_i32(GM_POLLUTION)
    soup = gm.vec_i32(GM_SOUP)
    for label, arr in (("dirt", dirt), ("water", water),
                       ("pollution", pollution), ("soup", soup)):
        if len(arr) != size:
            raise SystemExit(f"::error::{path.name}: {label} array is "
                             f"{len(arr)}, expected {size}")

    bodies_table = gm.table(GM_BODIES)
    bodies: list[dict] = []
    body_type_at: dict[int, str] = {}
    if bodies_table is not None:
        ids = bodies_table.vec_i32(SB_IDS)
        teams = bodies_table.vec_i8(SB_TEAMS)
        types = bodies_table.vec_i8(SB_TYPES)
        locs = bodies_table.table(SB_LOCS)
        xs = locs.vec_i32(VT_XS) if locs is not None else []
        ys = locs.vec_i32(VT_YS) if locs is not None else []
        for i, rid in enumerate(ids):
            kind = BODY_TYPES[types[i]]
            x, y = xs[i] - min_x, ys[i] - min_y
            bodies.append({
                "id": int(rid),
                "team": TEAMS[int(teams[i])],
                "type": kind,
                "x": int(x),
                "y": int(y),
            })
            body_type_at[x + width * y] = kind
    bodies.sort(key=lambda b: b["id"])

    return {
        "name": gm.string(GM_NAME),
        "width": width,
        "height": height,
        "symmetry": detect_symmetry(width, height, soup, dirt, body_type_at),
        "random_seed": gm.scalar_i32(GM_SEED),
        "initial_water": gm.scalar_i32(GM_INITIAL_WATER),
        "elevation": dirt,
        "water": water,
        "pollution": pollution,
        "soup": soup,
        "initial_bodies": bodies,
    }


def render(doc: dict) -> str:
    # Compact and stable: the committed file is diffed byte for byte in CI, so
    # the serialisation has to be deterministic.
    return json.dumps(doc, sort_keys=True, separators=(",", ":")) + "\n"


def pool_names() -> list[str]:
    pools = json.loads(
        (pathlib.Path(__file__).with_name("map_pools_bc20.json")).read_text())
    return sorted({n for pool in pools.values() for n in pool})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path,
                    help="a checkout of github.com/battlecode/battlecode20")
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    map_dir = args.engine / "engine/src/main/battlecode/world/resources"
    names = args.only or pool_names()

    args.out.mkdir(parents=True, exist_ok=True)
    drift = []
    for name in names:
        source = map_dir / f"{name}.map20"
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
            sys.stderr.write("converted bc20 maps differ from the engine: "
                             + ", ".join(drift) + "\n")
            return 1
        print(f"{len(names)} converted bc20 maps match the engine")
    else:
        print(f"wrote {len(names)} maps to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
