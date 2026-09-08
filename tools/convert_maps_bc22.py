#!/usr/bin/env python3
"""Convert Battlecode 2022 `.map22` flatbuffers to `data/maps/bc22/<name>.json`.

CI-TIME ONLY. There is no flatbuffer reader, no Python and no JVM in any
runtime image stage: the sim reads the committed JSON. `tests/test_bc22_maps.nim`
asserts the committed files against the design note's pinned table and the
`test` job re-runs this converter with `--check`, so a hand-edited map file
fails the build.

    tools/convert_maps_bc22.py --engine /path/to/battlecode22 --out data/maps/bc22
    tools/convert_maps_bc22.py --engine ... --out data/maps/bc22 --check
    tools/convert_maps_bc22.py --engine ... --parse-all   # every .map22 reads

battlecode22 ships no generated Python bindings and `flatc` is not in the
coworld toolchain, so the tables this converter needs are read straight off the
wire with the vtable walk below. The layout is fixed by `schema/battlecode.fbs`
at the pinned commit (`6ed05b679c0822e9bbe332812ff5655812dd023e`):

    table GameMap {
        name: string, minCorner: Vec, maxCorner: Vec, symmetry: int,
        bodies: SpawnedBodyTable, randomSeed: int,
        rubble: [int], lead: [int], anomalies: [int], anomalyRounds: [int]
    }
    table SpawnedBodyTable {
        robotIDs: [int], teamIDs: [byte], types: [BodyType], locs: VecTable
    }

`symmetry` is `MapSymmetry.values()`'s index order (0 rotation, 1 horizontal,
2 vertical) and in THIS year it is read at run time, by the VORTEX anomaly —
unlike every other year, where the field is inert. `anomalies` is an
`AnomalyType` ordinal (0 abyss, 1 charge, 2 fury, 3 vortex) paired positionally
with `anomalyRounds`. `teamIDs` is `util/TeamMapping` (1 = A, 2 = B) and
`BodyType` is `{MINER, BUILDER, SOLDIER, SAGE, ARCHON, LABORATORY,
WATCHTOWER}` — note that the schema's ordinals are NOT `RobotType`'s.

`rounds` is not in the file at all: `GameMapIO` hard-codes
`GameConstants.GAME_MAX_NUMBER_OF_ROUNDS`, so the converter emits 2000.

`initial_bodies` is emitted SORTED ASCENDING BY ID because `LiveMap`'s
constructor sorts its bodies by id, and that order is the initial
`ObjectInfo.dynamicBodyExecOrder` — i.e. the order the archons take their
turns in. It is a rule, not a formatting choice: the official maps carry
archon ids BELOW the 10 000 `IDGenerator` floor (`maze`: 2, 3, 6, 7, 8, 9), so
A and B alternate in the opening order.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys

SYMMETRIES = ["rotation", "horizontal", "vertical"]

# schema BodyType ordinals -> this repo's own type names.
BODY_TYPES = ["miner", "builder", "soldier", "sage",
              "archon", "laboratory", "watchtower"]

ANOMALIES = ["abyss", "charge", "fury", "vortex"]


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


# GameMap field ids, in declaration order.
GM_NAME, GM_MINCORNER, GM_MAXCORNER, GM_SYMMETRY = 0, 1, 2, 3
GM_BODIES, GM_SEED, GM_RUBBLE = 4, 5, 6
GM_LEAD, GM_ANOMALIES, GM_ANOMALY_ROUNDS = 7, 8, 9
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
    ox, oy = buf.i32(mn), buf.i32(mn + 4)
    width = buf.i32(mx) - ox
    height = buf.i32(mx + 4) - oy
    size = width * height

    rubble = gm.vec_i32(GM_RUBBLE)
    lead = gm.vec_i32(GM_LEAD)
    for label, arr in (("rubble", rubble), ("lead", lead)):
        if len(arr) < size:
            raise SystemExit(f"::error::{path.name}: {label} is {len(arr)}, "
                             f"expected at least {size}")
    rubble = rubble[:size]
    lead = lead[:size]

    kinds = gm.vec_i32(GM_ANOMALIES)
    rounds = gm.vec_i32(GM_ANOMALY_ROUNDS)
    if len(kinds) != len(rounds):
        raise SystemExit(f"::error::{path.name}: ragged anomaly schedule")

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
            spawns.append([int(ids[i]), int(xs[i]) - ox, int(ys[i]) - oy,
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
        "rubble": rubble,
        "lead": [[i % width, i // width, int(v)]
                 for i, v in enumerate(lead) if v != 0],
        "anomalies": [[int(rounds[i]), int(kinds[i])]
                      for i in range(len(kinds))],
        "initial_bodies": spawns,
    }


def render(doc: dict) -> str:
    out = {k: v for k, v in doc.items() if not k.startswith("_")}
    return json.dumps(out, sort_keys=True, separators=(",", ":")) + "\n"


def pool_names():
    pools = json.loads(
        (pathlib.Path(__file__).with_name("map_pools_bc22.json")).read_text())
    return sorted({n for pool in pools.values() for n in pool})


def summarise(doc: dict) -> tuple:
    rub = doc["rubble"]
    leads = [row[2] for row in doc["lead"]]
    counts = {}
    for body in doc["initial_bodies"]:
        counts[body[3]] = counts.get(body[3], 0) + 1
    sched = doc["anomalies"]
    return (
        doc["name"], doc["width"], doc["height"], doc["random_seed"],
        doc["symmetry"], counts.get(1, 0), counts.get(2, 0),
        round(sum(rub) / len(rub), 1), max(rub), min(rub),
        len(leads), sum(leads), (max(leads) if leads else 0),
        sum(1 for a in sched if a[1] == 0), sum(1 for a in sched if a[1] == 1),
        sum(1 for a in sched if a[1] == 2), sum(1 for a in sched if a[1] == 3),
        len(sched), (sched[0][0] if sched else -1),
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path,
                    help="a checkout of github.com/battlecode/battlecode22")
    ap.add_argument("--out", type=pathlib.Path)
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--parse-all", action="store_true",
                    help="read every .map22 in the engine and print a table")
    args = ap.parse_args()

    map_dir = args.engine / "engine/src/main/battlecode/world/resources"

    if args.parse_all:
        rows = []
        for source in sorted(map_dir.glob("*.map22")):
            rows.append(summarise(convert(source)))
        for r in rows:
            print("\t".join(str(v) for v in r))
        print(f"{len(rows)} .map22 files parsed", file=sys.stderr)
        return 0

    if args.out is None:
        ap.error("--out is required unless --parse-all")
    names = args.only or pool_names()
    args.out.mkdir(parents=True, exist_ok=True)
    drift = []
    for name in names:
        source = map_dir / f"{name}.map22"
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
            sys.stderr.write("converted bc22 maps differ from the engine: "
                             + ", ".join(drift) + "\n")
            return 1
        print(f"{len(names)} converted bc22 maps match the engine")
    else:
        print(f"wrote {len(names)} maps to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
