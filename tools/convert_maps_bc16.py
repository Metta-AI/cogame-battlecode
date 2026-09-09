#!/usr/bin/env python3
"""Convert Battlecode 2016 `.xml` maps to `data/maps/bc16/<name>.json`.

CI-TIME ONLY. There is no XML reader, no Python and no JVM in any runtime image
stage: the sim reads the committed JSON. `tests/test_bc16_maps.nim` asserts the
committed files against the design note's pinned table and the `test` job
re-runs this converter with `--check`, so a hand-edited map file fails the
build.

    tools/convert_maps_bc16.py --engine /path/to/battlecode-server-2016 \
        --out data/maps/bc16
    tools/convert_maps_bc16.py --engine ... --out data/maps/bc16 --check
    tools/convert_maps_bc16.py --engine ... --parse-all   # every .xml reads

2016's map format is XML, not flatbuffers (`world/GameMap.java:31-42`,
`world/GameMapIO.java`), so this is a plain stdlib walk with no `flatc`, no
schema and no dependency:

    <game-map width height origin seed rounds mapName armageddon?>
      <initialRubble><double-array>…</double-array> x height   # [y][x] rows
      <initialParts><double-array>…</double-array> x height    # [y][x] rows
      <zombieSpawnSchedule>
        <round number="N"><zombie-count type="T" count="C"/>…</round>…
      <initialRobots><initial-robot originOffsetX originOffsetY type team/>…

THREE THINGS THIS CONVERTER RESOLVES AT BUILD TIME so the runtime sim never
has to (design note D3, D4 and V3):

* **the map symmetry** (`GameMap.updateSymmetries`, `:529-636`): VERTICAL,
  HORIZONTAL, ROTATIONAL and — only when `width == height` —
  NEGATIVE_DIAGONAL and POSITIVE_DIAGONAL are each tested over the rubble and
  parts arrays AND over the robot roster, and **the FIRST one that holds in
  that order wins** (the engine warns and returns early on the second). Both
  the winner and the whole found set are written out, and CI byte-diffs them
  against the JVM's own `getSymmetry()`.
* **the per-den zombie spawn schedule** (`GameMap.buildZombieSpawnMap`,
  `:729-801`) — THE ONE HASH-ORDER DEPENDENCY IN THE WHOLE 2016 ENGINE. The
  den list is built by walking `byLoc.keySet()`, a `java.util.HashMap` keyed by
  `MapLocation` (`hashCode() = x*13 + y*23`) and filled by `Collectors.toMap`
  in initial-robot FILE order, and that order decides which den receives each
  leftover zombie when a round's count does not divide evenly. `JavaHashMap`
  below reproduces Java 8's implementation exactly — `h ^ (h >>> 16)`, bucket
  `hash & (n-1)`, capacity 16, load factor 0.75, resize splitting each bucket
  into its lo/hi lists in place, iteration walking buckets 0…n-1 and each chain
  in insertion order — so the split is computed once here and the sim reads it.
  `tools/JavaBc16HashOrder.java` cross-checks this emulation against a real
  `java.util.HashMap`.
* **the two memoised den constants** `spawn_dir` and `chirality`
  (`ZombieControlProvider.getSpawnDirection` `:313-342` /
  `getSpawnChirality` `:350-385`), which are pure functions of the map.

Coordinates are ORIGIN-RELATIVE (V3): the XML carries an `origin` attribute
(XStream sets the final field directly, so the constructor's random draw never
happens for a file-loaded map), the origin is added uniformly to every
coordinate, and every rule in the engine is translation invariant — so the
converter emits zero-origin coordinates and records the file's origin for
provenance only.

The converter REFUSES a map that is `armageddon="true"` (V4 — both armageddon
maps are 2 archons vs 0 over 12 000 rounds), that has unequal archon counts,
that is outside 30…80 in either dimension, or whose `getSpawnDirection` would
be -1.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

# `RobotType.values()` order. The ordinal is load-bearing: `ZombieCount`
# sorts by it and the den's spawn priority reads it.
ROBOT_TYPES = ["ZOMBIEDEN", "STANDARDZOMBIE", "RANGEDZOMBIE", "FASTZOMBIE",
               "BIGZOMBIE", "ARCHON", "SCOUT", "SOLDIER", "GUARD", "VIPER",
               "TURRET", "TTM"]
TYPE_ORDINAL = {name: i for i, name in enumerate(ROBOT_TYPES)}

# `Team.values()` order: A, B, NEUTRAL, ZOMBIE.
TEAMS = ["A", "B", "NEUTRAL", "ZOMBIE"]
TEAM_ORDINAL = {name: i for i, name in enumerate(TEAMS)}

ZOMBIE_TYPES = ["STANDARDZOMBIE", "RANGEDZOMBIE", "FASTZOMBIE", "BIGZOMBIE"]

# `ZombieControlProvider.DIRECTIONS`, in that order. `nextInt(8)` indexes it
# and `floorMod(start + i*chir, 8)` walks it.
DIRECTIONS = [("NORTH", 0, -1), ("NORTH_EAST", 1, -1), ("EAST", 1, 0),
              ("SOUTH_EAST", 1, 1), ("SOUTH", 0, 1), ("SOUTH_WEST", -1, 1),
              ("WEST", -1, 0), ("NORTH_WEST", -1, -1)]

# `GameMap.Symmetry.values()` order, which is also the FIRST-WINS test order
# of `updateSymmetries`.
SYMMETRIES = ["VERTICAL", "HORIZONTAL", "ROTATIONAL", "NEGATIVE_DIAGONAL",
              "POSITIVE_DIAGONAL", "NONE"]

MAP_MIN = 30
MAP_MAX = 80


class RefuseMap(Exception):
    """A map the converter will not convert, with the engine's own reason."""


# ---------------------------------------------------------------------------
#  java.util.HashMap iteration order (Java 8), for D3
# ---------------------------------------------------------------------------


def _java_int(v: int) -> int:
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v


def _loc_hash(x: int, y: int) -> int:
    """`MapLocation.hashCode()` == `x * 13 + y * 23`, as a Java int."""
    return _java_int(x * 13 + y * 23)


class JavaHashMap:
    """Java 8's `HashMap` insertion + iteration order, for `MapLocation` keys.

    Only what `buildZombieSpawnMap` needs: `put` of distinct keys and a
    `keySet()` walk. Bins are chains (never trees): treeification needs eight
    keys in ONE bucket and the official rosters top out at 104 robots, so it
    cannot be reached — and `--parse-all` asserts it for all 98 maps.
    """

    def __init__(self) -> None:
        self.cap = 16
        self.threshold = 12          # 16 * 0.75
        self.size = 0
        self.table: list[list[tuple[int, tuple[int, int]]]] = [
            [] for _ in range(self.cap)]

    @staticmethod
    def spread(h: int) -> int:
        """`HashMap.hash(key)` == `h ^ (h >>> 16)`."""
        u = h & 0xFFFFFFFF
        return (u ^ (u >> 16)) & 0xFFFFFFFF

    def put(self, key: tuple[int, int]) -> None:
        h = self.spread(_loc_hash(key[0], key[1]) & 0xFFFFFFFF)
        i = h & (self.cap - 1)
        for entry in self.table[i]:
            if entry[1] == key:
                return
        if len(self.table[i]) >= 7:
            raise RefuseMap("a HashMap bucket would treeify; "
                            "the chain emulation is not valid here")
        self.table[i].append((h, key))
        self.size += 1
        if self.size > self.threshold:
            self._resize()

    def _resize(self) -> None:
        """`HashMap.resize()`: each bin splits IN PLACE into a lo and a hi
        list, preserving relative order, and the hi list lands at
        `j + oldCap`."""
        old_cap = self.cap
        new_cap = old_cap * 2
        new_table: list[list[tuple[int, tuple[int, int]]]] = [
            [] for _ in range(new_cap)]
        for j in range(old_cap):
            for entry in self.table[j]:
                if entry[0] & old_cap:
                    new_table[j + old_cap].append(entry)
                else:
                    new_table[j].append(entry)
        self.cap = new_cap
        self.threshold *= 2
        self.table = new_table

    def keys(self) -> list[tuple[int, int]]:
        """`keySet()` iteration: buckets 0…n-1, each chain in insertion
        order."""
        out = []
        for bucket in self.table:
            for entry in bucket:
                out.append(entry[1])
        return out


# ---------------------------------------------------------------------------
#  Reading the XML
# ---------------------------------------------------------------------------


def _rows(node: ET.Element) -> list[list[float]]:
    rows = []
    for arr in node.findall("double-array"):
        text = (arr.text or "").strip()
        rows.append([float(v) for v in text.split(",")] if text else [])
    return rows


def _fmt(v: float) -> float:
    """The exact decimal value, as an int when it is one.

    Every rubble and parts value in the 98 official maps is an integral
    `double`; keeping them as ints makes the committed JSON small and the Nim
    parse exact. A genuinely fractional value is kept as a float.
    """
    return int(v) if v == int(v) else v


def read_map(path: pathlib.Path) -> dict:
    root = ET.parse(path).getroot()
    gm = root.find("game-map")
    if gm is None:
        raise RefuseMap("no <game-map> element")
    width = int(gm.attrib["width"])
    height = int(gm.attrib["height"])
    name = gm.attrib["mapName"]
    seed = int(gm.attrib["seed"])
    rounds = int(gm.attrib.get("rounds", 3000))
    armageddon = gm.attrib.get("armageddon", "false") == "true"
    origin = gm.attrib.get("origin", "0,0")

    rubble_rows = _rows(gm.find("initialRubble"))
    parts_rows = _rows(gm.find("initialParts"))
    if len(rubble_rows) != height or any(len(r) != width for r in rubble_rows):
        raise RefuseMap("initialRubble is not height x width")
    if len(parts_rows) != height or any(len(r) != width for r in parts_rows):
        raise RefuseMap("initialParts is not height x width")

    schedule: list[tuple[int, dict[str, int]]] = []
    for rnd in gm.find("zombieSpawnSchedule").findall("round"):
        number = int(rnd.attrib["number"])
        counts: dict[str, int] = {}
        for zc in rnd.findall("zombie-count"):
            kind = zc.attrib["type"]
            counts[kind] = counts.get(kind, 0) + int(zc.attrib["count"])
        schedule.append((number, counts))
    # `ZombieSpawnSchedule.getRounds()` sorts, and `getScheduleForRound` sorts
    # its counts by (type ordinal, count) — so the whole-map schedule is
    # order-free and the converter canonicalises it here.
    schedule.sort(key=lambda item: item[0])

    robots = []
    for r in gm.find("initialRobots").findall("initial-robot"):
        robots.append((int(r.attrib["originOffsetX"]),
                       int(r.attrib["originOffsetY"]),
                       r.attrib["type"], r.attrib["team"]))

    return {
        "name": name, "width": width, "height": height, "seed": seed,
        "rounds": rounds, "armageddon": armageddon, "origin": origin,
        "rubble": rubble_rows, "parts": parts_rows,
        "schedule": schedule, "robots": robots,
    }


# ---------------------------------------------------------------------------
#  Symmetry (D4) and the per-den split (D3)
# ---------------------------------------------------------------------------


def opposite(sym: str, x: int, y: int, width: int, height: int):
    if sym == "VERTICAL":
        return (x, height - y - 1)
    if sym == "HORIZONTAL":
        return (width - x - 1, y)
    if sym == "ROTATIONAL":
        return (width - x - 1, height - y - 1)
    if sym == "NEGATIVE_DIAGONAL":
        return (height - y - 1, width - x - 1)
    if sym == "POSITIVE_DIAGONAL":
        return (y, x)
    return None


def opposite_robots(r1, r2) -> bool:
    """`GameMap.oppositeRobots`, verbatim."""
    if r1 is None or r2 is None:
        return False
    if r1[2] != r2[2]:
        return False
    if r1[3] in ("ZOMBIE", "NEUTRAL"):
        return r1[3] == r2[3]
    return r2[3] not in ("ZOMBIE", "NEUTRAL") and r2[3] != r1[3]


def find_symmetries(m: dict) -> list[str]:
    """`GameMap.updateSymmetries`, in the engine's own order.

    Returns every symmetry that holds, in `Symmetry.values()` order; the
    engine takes the first (`symmetry` below) and warns about the rest.
    """
    width, height = m["width"], m["height"]
    rubble, parts = m["rubble"], m["parts"]
    square = width == height

    def same_tile(x1, y1, x2, y2) -> bool:
        return (rubble[y1][x1] == rubble[y2][x2]
                and parts[y1][x1] == parts[y2][x2])

    flags = {"VERTICAL": True, "HORIZONTAL": True, "ROTATIONAL": True,
             "NEGATIVE_DIAGONAL": square, "POSITIVE_DIAGONAL": square}
    for y in range(height):
        for x in range(width):
            if flags["VERTICAL"]:
                flags["VERTICAL"] = same_tile(x, y, x, height - y - 1)
            if flags["HORIZONTAL"]:
                flags["HORIZONTAL"] = same_tile(x, y, width - x - 1, y)
            if flags["ROTATIONAL"]:
                flags["ROTATIONAL"] = same_tile(
                    x, y, width - x - 1, height - y - 1)
            if square:
                if flags["NEGATIVE_DIAGONAL"]:
                    flags["NEGATIVE_DIAGONAL"] = same_tile(
                        x, y, height - y - 1, width - x - 1)
                if flags["POSITIVE_DIAGONAL"]:
                    flags["POSITIVE_DIAGONAL"] = same_tile(x, y, y, x)

    # The robot roster. `byLoc` here is a plain dict: `updateSymmetries` only
    # LOOKS UP in it (it walks `keySet()` but the conjunction it builds is
    # order-free), unlike `buildZombieSpawnMap`, which is order-DEPENDENT.
    by_loc = {(r[0], r[1]): r for r in m["robots"]}
    for (x, y), r1 in by_loc.items():
        for sym in list(flags):
            if not flags[sym]:
                continue
            opp = opposite(sym, x, y, width, height)
            flags[sym] = opposite_robots(r1, by_loc.get(opp))
    return [s for s in SYMMETRIES if s != "NONE" and flags.get(s)]


def den_locations(m: dict, symmetry: str) -> list[tuple[int, int]]:
    """`buildZombieSpawnMap`'s `denLocs`, in the engine's own PAIR order.

    The `byLoc.keySet()` walk is a real `java.util.HashMap` iteration and is
    what this function exists to reproduce (D3).
    """
    hm = JavaHashMap()
    for r in m["robots"]:
        hm.put((r[0], r[1]))
    by_loc = {(r[0], r[1]): r for r in m["robots"]}

    dens: list[tuple[int, int]] = []
    for loc in hm.keys():
        r1 = by_loc[loc]
        if r1[2] != "ZOMBIEDEN" or loc in dens:
            continue
        dens.append(loc)
        opp = opposite(symmetry, loc[0], loc[1], m["width"], m["height"])
        if (opp is not None and opposite_robots(r1, by_loc.get(opp))
                and opp not in dens):
            dens.append(opp)
    return dens


def split_schedule(m: dict, dens: list[tuple[int, int]]) -> list[dict]:
    """`buildZombieSpawnMap`'s division: even shares plus a PERSISTENT cursor
    handing out the leftovers, surviving across types AND across rounds."""
    per_den: list[dict[int, dict[str, int]]] = [{} for _ in dens]
    if not dens:
        return per_den
    cursor = 0
    n = len(dens)
    for rnd, counts in m["schedule"]:
        # `getScheduleForRound` sorts by (type ordinal, count).
        for kind in sorted(counts, key=lambda k: (TYPE_ORDINAL[k],
                                                  counts[k])):
            count = counts[kind]
            even, left = divmod(count, n)
            for i in range(n):
                if even:
                    slot = per_den[i].setdefault(rnd, {})
                    slot[kind] = slot.get(kind, 0) + even
            for _ in range(left):
                slot = per_den[cursor].setdefault(rnd, {})
                slot[kind] = slot.get(kind, 0) + 1
                cursor = (cursor + 1) % n
    return per_den


def direction_to(fx: int, fy: int, tx: int, ty: int) -> str:
    """`MapLocation.directionTo`, with the engine's own 2.414 fan."""
    dx = float(tx - fx)
    dy = float(ty - fy)
    if abs(dx) >= 2.414 * abs(dy):
        if dx > 0:
            return "EAST"
        if dx < 0:
            return "WEST"
        return "OMNI"
    if abs(dy) >= 2.414 * abs(dx):
        return "SOUTH" if dy > 0 else "NORTH"
    if dy > 0:
        return "SOUTH_EAST" if dx > 0 else "SOUTH_WEST"
    return "NORTH_EAST" if dx > 0 else "NORTH_WEST"


def spawn_direction(m: dict, den: tuple[int, int]) -> int:
    """`getSpawnDirection`: the direction to the closest INITIAL ARCHON of
    either team, first minimum in FILE order (`Stream.min` keeps the earlier
    element on a tie), as an index into `DIRECTIONS`."""
    best = None
    best_d = None
    for r in m["robots"]:
        if r[2] != "ARCHON":
            continue
        d = (r[0] - den[0]) ** 2 + (r[1] - den[1]) ** 2
        if best_d is None or d < best_d:
            best_d = d
            best = (r[0], r[1])
    if best is None:
        best = (m["width"] // 2, m["height"] // 2)
    name = direction_to(den[0], den[1], best[0], best[1])
    for i, (dir_name, _, _) in enumerate(DIRECTIONS):
        if dir_name == name:
            return i
    raise RefuseMap(f"getSpawnDirection would be -1 for den {den} ({name})")


def spawn_chirality(m: dict, den: tuple[int, int], symmetry: str) -> int:
    """`getSpawnChirality`: 1 for ROTATIONAL and NONE, otherwise
    `signum(loc.compareTo(opposite))` and 1 when that is 0 (a den on the line
    of symmetry). `compareTo` is x-then-y and translation invariant, so the
    origin does not matter (V3)."""
    if symmetry in ("ROTATIONAL", "NONE"):
        return 1
    opp = opposite(symmetry, den[0], den[1], m["width"], m["height"])
    if opp is None:
        return 1
    cmp = (den[0] - opp[0]) if den[0] != opp[0] else (den[1] - opp[1])
    if cmp > 0:
        return 1
    if cmp < 0:
        return -1
    return 1


# ---------------------------------------------------------------------------
#  Conversion
# ---------------------------------------------------------------------------


def convert(path: pathlib.Path) -> dict:
    m = read_map(path)
    if m["armageddon"]:
        raise RefuseMap("armageddon map (V4): a 2-vs-0 survival mode, "
                        "not a two-seat match")
    if not (MAP_MIN <= m["width"] <= MAP_MAX
            and MAP_MIN <= m["height"] <= MAP_MAX):
        raise RefuseMap(f"{m['width']}x{m['height']} is outside "
                        f"{MAP_MIN}..{MAP_MAX}")
    archons = {"A": 0, "B": 0}
    for r in m["robots"]:
        if r[2] == "ARCHON" and r[3] in archons:
            archons[r[3]] += 1
    if archons["A"] != archons["B"]:
        raise RefuseMap(f"unequal archon counts A={archons['A']} "
                        f"B={archons['B']}")
    if archons["A"] == 0:
        raise RefuseMap("no player archons")

    found = find_symmetries(m)
    symmetry = found[0] if found else "NONE"
    dens = den_locations(m, symmetry)
    splits = split_schedule(m, dens)

    den_rows = []
    for den, split in zip(dens, splits):
        den_rows.append({
            "x": den[0], "y": den[1],
            "spawn_dir": spawn_direction(m, den),
            "chirality": spawn_chirality(m, den, symmetry),
            "schedule": {str(rnd): {k: v for k, v in
                                    sorted(split[rnd].items(),
                                           key=lambda kv:
                                           TYPE_ORDINAL[kv[0]])
                                    if v}
                         for rnd in sorted(split)},
        })

    return {
        "name": m["name"],
        "width": m["width"],
        "height": m["height"],
        "random_seed": m["seed"],
        "rounds": m["rounds"],
        "symmetry": symmetry.lower(),
        "symmetries_found": [s.lower() for s in found],
        "file_origin": m["origin"],
        "rubble": [[_fmt(v) for v in row] for row in m["rubble"]],
        "parts": [[_fmt(v) for v in row] for row in m["parts"]],
        "initial_robots": [[r[0], r[1], TYPE_ORDINAL[r[2]],
                            TEAM_ORDINAL[r[3]]] for r in m["robots"]],
        "schedule": [{"round": rnd,
                      "counts": {k: counts[k] for k in ZOMBIE_TYPES
                                 if counts.get(k)}}
                     for rnd, counts in m["schedule"]],
        "dens": den_rows,
    }


def render(doc: dict) -> str:
    return json.dumps(doc, sort_keys=True, separators=(",", ":")) + "\n"


def pool_names() -> list[str]:
    pools = json.loads(
        (pathlib.Path(__file__).with_name("map_pools_bc16.json")).read_text())
    return sorted({n for pool in pools.values() for n in pool})


def summarise(doc: dict) -> tuple:
    rubble = [v for row in doc["rubble"] for v in row]
    parts = [v for row in doc["parts"] for v in row if v]
    archons = sum(1 for r in doc["initial_robots"]
                  if r[2] == TYPE_ORDINAL["ARCHON"] and r[3] == 0)
    neutrals = sum(1 for r in doc["initial_robots"] if r[3] == 2)
    total_z = sum(sum(row["counts"].values()) for row in doc["schedule"])
    per_den = 0
    if doc["dens"]:
        per_den = sum(sum(c.values())
                      for c in doc["dens"][0]["schedule"].values())
    return (
        doc["name"], f"{doc['width']}x{doc['height']}",
        doc["width"] * doc["height"], doc["random_seed"], doc["symmetry"],
        "+".join(doc["symmetries_found"]), archons, len(doc["dens"]),
        neutrals, round(sum(rubble) / len(rubble), 1), int(max(rubble)),
        sum(1 for v in rubble if v >= 100), int(sum(parts)), len(parts),
        int(max(parts)) if parts else 0, len(doc["schedule"]),
        doc["schedule"][0]["round"] if doc["schedule"] else -1,
        per_den, total_z,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, type=pathlib.Path,
                    help="a checkout of battlecode/battlecode-server-2016")
    ap.add_argument("--out", type=pathlib.Path)
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--parse-all", action="store_true",
                    help="read every .xml in the engine and print a table")
    args = ap.parse_args()

    map_dir = args.engine / "src/main/battlecode/world/resources"
    if not map_dir.is_dir():
        sys.stderr.write(f"no map resources under {map_dir}\n")
        return 1

    if args.parse_all:
        rows = []
        refused = []
        for source in sorted(map_dir.glob("*.xml")):
            try:
                rows.append(summarise(convert(source)))
            except RefuseMap as exc:
                refused.append((source.stem, str(exc)))
        for r in rows:
            print("\t".join(str(v) for v in r))
        for name, why in refused:
            print(f"REFUSED\t{name}\t{why}")
        print(f"{len(rows) + len(refused)} official .xml files parsed, "
              f"{len(refused)} refused", file=sys.stderr)
        return 0

    if args.out is None:
        ap.error("--out is required unless --parse-all")
    names = args.only or pool_names()
    args.out.mkdir(parents=True, exist_ok=True)
    drift = []
    for name in names:
        source = map_dir / f"{name}.xml"
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
            sys.stderr.write("converted bc16 maps differ from the engine: "
                             + ", ".join(drift) + "\n")
            return 1
        print(f"{len(names)} converted bc16 maps match the engine")
    else:
        print(f"wrote {len(names)} maps to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
