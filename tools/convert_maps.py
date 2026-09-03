#!/usr/bin/env python3
"""Convert Battlecode `.map26` flatbuffers to `data/maps/bc26/<name>.json`.

CI-TIME ONLY. There is no flatbuffer reader, no Python and no JVM in any
runtime image stage: the sim reads the committed JSON. `tests/test_maps.nim`
re-converts and diffs, so a hand-edited map file fails the build.

    tools/convert_maps.py --engine /path/to/battlecode26-engine.1.2.5 \
        --out data/maps/bc26
    tools/convert_maps.py --engine ... --out data/maps/bc26 --check

Field-for-field with `world/GameMapIO.java`'s `Serial.deserialize`:
symmetry is the raw enum ordinal, cheese-mine tiles come out of the
`cheeseMines` VecTable as `x + width*y`, cat waypoints likewise, and each
initial body keeps the id, direction ordinal and chirality the file carries
(the sim's `IDGenerator` continues from `MIN_ID`, so map ids and spawned ids
never collide).
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

# ROTATIONAL, HORIZONTAL, VERTICAL -- battlecode/world/MapSymmetry.java.
SYMMETRY = ["rotational", "horizontal", "vertical"]
# FlatHelpers.getDirectionFromOrdinal -- the WIRE order, which is
# Direction.DIRECTION_ORDER and NOT Direction.values(). Reading it as
# values() puts every initial body's facing 90 degrees out and desynchronises
# the very first round against the Java engine.
DIRECTIONS = ["center", "west", "southwest", "south", "southeast",
              "east", "northeast", "north", "northwest"]
# FlatHelpers.getUnitTypeFromRobotType: schema RobotType 0=NONE.
UNITS = {1: "baby_rat", 2: "rat_king", 3: "cat"}
# TeamMapping.team: 1 -> A, 2 -> B; cats are forced NEUTRAL.
TEAMS = {0: "neutral", 1: "A", 2: "B"}


def convert(path: pathlib.Path, schema_dir: pathlib.Path) -> dict:
    sys.path.insert(0, str(schema_dir))
    from battlecode.schema.GameMap import GameMap  # noqa: E402

    raw = GameMap.GetRootAs(bytearray(path.read_bytes()), 0)
    width = raw.Size().X()
    height = raw.Size().Y()
    size = width * height

    walls = [bool(raw.Walls(i)) for i in range(size)]
    dirt = [bool(raw.Dirt(i)) for i in range(size)]
    cheese = [int(raw.Cheese(i)) for i in range(size)]

    mines = []
    table = raw.CheeseMines()
    for i in range(table.XsLength()):
        mines.append(int(table.Xs(i)) + width * int(table.Ys(i)))

    cat_ids, cat_vecs = [], []
    for i in range(raw.CatWaypointVecsLength()):
        cat_ids.append(int(raw.CatWaypointIds(i)))
        wp = raw.CatWaypointVecs(i)
        cat_vecs.append([int(wp.Xs(j)) + width * int(wp.Ys(j))
                         for j in range(wp.XsLength())])

    bodies = []
    body_table = raw.InitialBodies()
    for i in range(body_table.SpawnActionsLength()):
        action = body_table.SpawnActions(i)
        unit = UNITS[int(action.RobotType())]
        team = "neutral" if unit == "cat" else TEAMS[int(action.Team())]
        bodies.append({
            "id": int(action.Id()),
            "team": team,
            "unit": unit,
            "x": int(action.X()),
            "y": int(action.Y()),
            "dir": DIRECTIONS[int(action.Dir())],
            "chirality": int(action.Chirality()),
        })
    bodies.sort(key=lambda b: b["id"])

    return {
        "name": raw.Name().decode("utf-8"),
        "width": width,
        "height": height,
        "symmetry": SYMMETRY[int(raw.Symmetry())],
        "random_seed": int(raw.RandomSeed()),
        "walls": walls,
        "dirt": dirt,
        "cheese": cheese,
        "cheese_mines": sorted(mines),
        "cat_waypoint_ids": cat_ids,
        "cat_waypoint_vecs": cat_vecs,
        "initial_bodies": bodies,
    }


def render(doc: dict) -> str:
    # Compact and stable: the committed file is diffed byte for byte by
    # tests/test_maps.nim, so the serialisation has to be deterministic.
    return json.dumps(doc, sort_keys=True, separators=(",", ":")) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--only", nargs="*", default=None,
                    help="map names to convert (default: the pool list)")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    schema_dir = args.engine / "schema/python"
    map_dir = args.engine / "maps"
    names = args.only
    if not names:
        pool_file = pathlib.Path(__file__).with_name("map_pools.json")
        pools = json.loads(pool_file.read_text())
        names = sorted({n for pool in pools.values() for n in pool})

    args.out.mkdir(parents=True, exist_ok=True)
    drift = []
    for name in names:
        source = map_dir / f"{name}.map26"
        if not source.exists():
            sys.stderr.write(f"missing map at {args.engine}: {name}\n")
            return 1
        text = render(convert(source, schema_dir))
        target = args.out / f"{name}.json"
        if args.check:
            if not target.exists() or target.read_text() != text:
                drift.append(name)
        else:
            target.write_text(text)
    if args.check:
        if drift:
            sys.stderr.write("converted maps differ from the engine: "
                             + ", ".join(drift) + "\n")
            return 1
        print(f"{len(names)} converted maps match the engine")
    else:
        print(f"wrote {len(names)} maps to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
