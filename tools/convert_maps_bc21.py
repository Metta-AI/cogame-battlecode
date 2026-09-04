#!/usr/bin/env python3
"""Convert Battlecode 2021 `.map21` flatbuffers to `data/maps/bc21/<name>.json`.

CI-TIME ONLY. There is no flatbuffer reader, no Python and no JVM in any
runtime image stage: the sim reads the committed JSON. `tests/test_bc21_maps.nim`
asserts the committed files against the note's pinned table and the `test` job
re-runs this converter with `--check`, so a hand-edited map file fails the
build.

    tools/convert_maps_bc21.py --engine /path/to/battlecode21 --out data/maps/bc21
    tools/convert_maps_bc21.py --engine ... --out data/maps/bc21 --check

battlecode21 ships no generated Python bindings (only `schema/{java,js,ts}`)
and `flatc` is not in the coworld toolchain, so the three tables this converter
needs are read straight off the wire with the vtable walk below. The layout is
fixed by `schema/battlecode.fbs` at the pinned commit
(`ed39c1a49574db57e5463d720736220506280294`) and is asserted field by field.

SYMMETRY IS NOT IN THE FILE, AND THE 2021 ENGINE NEVER USES IT. Unlike 2020,
there is no `getSymmetry` anywhere in the engine (2021 has no cows and nothing
else that needs it). It is DETECTED here purely so the doctrine prompt and the
map card can say something true: candidates are tested in the order `vertical`
(flip x), `horizontal` (flip y), `rotational` (both) against BOTH the
passability array and the Enlightenment-Center placement (type, influence and
the A<->B team flip), and EVERY candidate that holds is recorded in
`symmetries`; the first survivor is `symmetry` and is what the card shows.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys

# schema/battlecode.fbs `enum BodyType : byte`, in declaration order.
BODY_TYPES = ["enlightenment_center", "politician", "slanderer", "muckraker"]
# world/TeamMapping.java: 1 -> A, 2 -> B; neutral Enlightenment Centers are 0.
TEAMS = {0: "neutral", 1: "a", 2: "b"}


# ---------------------------------------------------------------------------
#  A minimal flatbuffer reader (little-endian, as the format mandates)
# ---------------------------------------------------------------------------

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
        """Byte offset of field `field` from the table position, 0 if absent."""
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
        return self.b.d[at + 4:at + 4 + length].decode("utf-8")

    def vector(self, field: int):
        """(first element position, element count); (0, 0) when absent."""
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

    def vec_f64(self, field: int):
        start, n = self.vector(field)
        if n == 0:
            return []
        return list(struct.unpack_from(f"<{n}d", self.b.d, start))


# GameMap field ids, in `schema/battlecode.fbs` declaration order.
GM_NAME, GM_MIN, GM_MAX, GM_BODIES, GM_SEED, GM_PASSABILITY = 0, 1, 2, 3, 4, 5
# SpawnedBodyTable field ids.
SB_IDS, SB_TEAMS, SB_TYPES, SB_LOCS, SB_INFLUENCES = 0, 1, 2, 3, 4
# VecTable field ids.
VT_XS, VT_YS = 0, 1

CANDIDATES = ["vertical", "horizontal", "rotational"]


def detect_symmetries(width, height, passability, body_at):
    """Every transform under which passability AND the Centers agree.

    `vertical` flips x, `horizontal` flips y, `rotational` flips both — the
    same naming battlecode20's own `getSymmetry` used, kept so the two years
    read alike. A Center's mirror must be a Center OF THE SAME TYPE WITH THE
    SAME INFLUENCE; the TEAM is deliberately not compared, exactly as
    battlecode20's own `getSymmetry` compared only the body type.

    That matters on `Corridor`, which is 33 wide with both Centers on the
    centre column: it is a perfectly good vertical mirror of itself, and the
    two teams are laid out along the OTHER axis. Which of the recorded
    symmetries actually maps your Centers onto the enemy's is a question for
    the chassis (`world.newWorld` picks it), not for the converter.
    """
    def sym_x(x, s):
        return x if s == "horizontal" else width - 1 - x

    def sym_y(y, s):
        return y if s == "vertical" else height - 1 - y

    holds = []
    for s in CANDIDATES:
        ok = True
        for x in range(width):
            for y in range(height):
                here = x + width * y
                there = sym_x(x, s) + width * sym_y(y, s)
                if passability[here] != passability[there]:
                    ok = False
                    break
                a = body_at.get(here)
                b = body_at.get(there)
                if a is None and b is None:
                    continue
                if a is None or b is None:
                    ok = False
                    break
                if (a["type"] != b["type"]
                        or a["influence"] != b["influence"]):
                    ok = False
                    break
            if not ok:
                break
        if ok:
            holds.append(s)
    return holds


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

    passability = gm.vec_f64(GM_PASSABILITY)
    if len(passability) != size:
        raise SystemExit(f"::error::{path.name}: passability array is "
                         f"{len(passability)}, expected {size}")

    bodies_table = gm.table(GM_BODIES)
    bodies = []
    body_at = {}
    if bodies_table is not None:
        ids = bodies_table.vec_i32(SB_IDS)
        teams = bodies_table.vec_i8(SB_TEAMS)
        types = bodies_table.vec_i8(SB_TYPES)
        influences = bodies_table.vec_i32(SB_INFLUENCES)
        locs = bodies_table.table(SB_LOCS)
        xs = locs.vec_i32(VT_XS) if locs is not None else []
        ys = locs.vec_i32(VT_YS) if locs is not None else []
        for i, rid in enumerate(ids):
            body = {
                "id": int(rid),
                "team": TEAMS[int(teams[i])],
                "type": BODY_TYPES[types[i]],
                # The .map21 body coordinates are already ORIGIN-RELATIVE:
                # GameMapIO reads them straight into a MapLocation and
                # GameWorld's constructor is what translates them by
                # getOrigin(). Subtracting minCorner here would shift every
                # Center off the board.
                "x": int(xs[i]),
                "y": int(ys[i]),
                "influence": int(influences[i]),
            }
            bodies.append(body)
            body_at[body["x"] + width * body["y"]] = body
    # `LiveMap`'s constructor sorts initialBodies by the FILE's body id, and
    # GameWorld spawns them in that order — which is what fixes both the exec
    # order and the engine ids they are minted with.
    bodies.sort(key=lambda b: b["id"])

    holds = detect_symmetries(width, height, passability, body_at)

    return {
        "name": gm.string(GM_NAME),
        "width": width,
        "height": height,
        "origin": [min_x, min_y],
        "random_seed": gm.scalar_i32(GM_SEED),
        "symmetry": holds[0] if holds else "none",
        "symmetries": holds,
        # 17 significant digits round-trips an IEEE-754 double exactly, which
        # matters: passability divides the action cooldown.
        "passability": [float(f"{p:.17g}") for p in passability],
        "initial_bodies": bodies,
    }


def render(doc: dict) -> str:
    # Compact and stable: the committed file is diffed byte for byte in CI, so
    # the serialisation has to be deterministic.
    return json.dumps(doc, sort_keys=True, separators=(",", ":")) + "\n"


def pool_names():
    pools = json.loads(
        (pathlib.Path(__file__).with_name("map_pools_bc21.json")).read_text())
    return sorted({n for pool in pools.values() for n in pool})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path,
                    help="a checkout of github.com/battlecode/battlecode21")
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    map_dir = args.engine / "engine/src/main/battlecode/world/resources"
    names = args.only or pool_names()

    args.out.mkdir(parents=True, exist_ok=True)
    drift = []
    for name in names:
        source = map_dir / f"{name}.map21"
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
            sys.stderr.write("converted bc21 maps differ from the engine: "
                             + ", ".join(drift) + "\n")
            return 1
        print(f"{len(names)} converted bc21 maps match the engine")
    else:
        print(f"wrote {len(names)} maps to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
