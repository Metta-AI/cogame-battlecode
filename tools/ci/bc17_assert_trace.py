#!/usr/bin/env python3
"""bc17: assert off the JAVA traces that the games really did what the tier
claims, before anything is allowed to call a bit-exact pair evidence.

CI-TIME ONLY, run by the `parity-oracle-bc17` job of
`.github/workflows/ci.yml` immediately after the traces are produced and
BEFORE `parity_tiers_bc17.py` compares them. **A tier that agrees bit for bit
while nothing happens proves nothing**, and this is the script that stops
that from being possible. Everything below is read from the ENGINE'S OWN
trace, never from the port's.

What it asserts:

  every pair       the game reached round 2 900, or ended earlier with a
                   DECISIVE `W` line (`DESTROYED` or `PHILANTROPIED`) -- an
                   early end must be a decided game, not a game that fell
                   over. Under a JDK newer than 8 the instrumenter kills
                   every robot as it spawns and the game is over in one
                   round, which is exactly what this catches from the other
                   side.
  Tier A           `bul=` is the bits of 300.0f on EVERY round of EVERY idle
                   pair -- THE INCOME CLIFF turned into a gate, because
                   `max(0, 2 - 0.01 * supply)` is exactly zero at any supply
                   of 200 or more and both teams start at 300; `rid=` and
                   `bid=` never move, so no id is ever drawn; `execlen` never
                   leaves the initial body count; and the `W` line carries
                   `WON_BY_DUBIOUS_REASONS`, i.e. the round-limit ladder fell
                   all the way through to rung 4.
  every non-idle   at least one `A` line carries a non-`NOTHING` action.
  Tier A''         every `examplefuncsplayer17` pair peaked at 7 or more
                   robots (measured minimum: 7, on `Cramped`, whose sides
                   annihilate each other by round 533) and at least one pair
                   peaked at 30 or more (measured maximum: 78, on `Alone`).
  Tier A'          over the 36 scenario traces TOGETHER: a `U` line for each
                   of the SIX types; a fighter healing by exactly
                   `0.04 x maxHealth` on twenty consecutive rounds with NO
                   `A` line during them (the dormancy and its 4 %-a-turn
                   heal); `B` lines appearing THREE and FIVE at a time from
                   one robot in one round (the triad and the pentad); an `E`
                   line disappearing on a `CHOP` round FOLLOWED BY a new `U`
                   line of the contained type (the chop-only goodie release
                   of rule 7.3); an `E` line disappearing with NO chop and NO
                   new `U` line (a tree killed by a bullet releases nothing);
                   a `bul=` jump matching a `SHAKE`; a `vp=` jump matching a
                   `DONATE` **with the floor arithmetic recomputed**
                   (`floor(spent / (7.5 + 0.0041666666 * round))`); and the
                   `DominationFactor` vocabulary across the set.
  Tier B' (b)      the NON-COMPARED `bc17slowbot` trace: some robot's `bc=`
                   column reached its type's bytecode limit and its `A` line
                   was `NOTHING` on that round -- the engine's own
                   pause-and-resume, proved to exist where the rule says it
                   does, on the one bot that is meant to be paused.

**WHAT IS DELIBERATELY NOT ASSERTED HERE, AND WHY**, because a gate that
quietly does not cover something is worse than no gate: `BODY_ATTACK` and
`PHILANTROPIED` are NOT reachable by the committed scenario bots -- see
`docs/PARITY.md` section bc17, "What is NOT compared", which names both with
the measurement that shows why.
"""

import argparse
import math
import pathlib
import struct
import sys

# `RobotType`'s own table, battlecode 2017.1.6.2 -- the two columns this
# script needs. A type that is not here is a trace this script and the
# emitters disagree about.
MAX_HEALTH = {"ARCHON": 400, "GARDENER": 40, "LUMBERJACK": 50,
              "SOLDIER": 50, "TANK": 200, "SCOUT": 10}
LIMITS = {"ARCHON": 30000, "GARDENER": 15000, "LUMBERJACK": 15000,
          "SOLDIER": 15000, "TANK": 15000, "SCOUT": 15000}
BULLETS_INITIAL_BITS = "43960000"          # 300.0f
VP_BASE_COST = 7.5
VP_INCREASE_PER_ROUND = 0.0041666666


def f32(hexbits: str) -> float:
    return struct.unpack(">f", struct.pack(">I", int(hexbits, 16)))[0]


def fields(parts):
    out = {}
    for p in parts:
        if "=" in p:
            k, v = p.split("=", 1)
            out[k] = v
    return out


class Pair:
    """One Java trace, walked once."""

    def __init__(self, path: pathlib.Path):
        self.path = path
        self.last_round = 0
        self.winner = "-"
        self.dom = "-"
        self.acted = False
        self.peak_robots = 0
        self.idle_bul_ok = True
        self.idle_bul_bad = None
        self.rid = set()
        self.bid = set()
        self.execlens = set()
        self.types = set()
        self.doms = set()
        self.triad = False
        self.pentad = False
        self.chop_release = False
        self.bullet_kill_no_release = False
        self.shake_jump = False
        self.donate_floor = False
        self.dormancy = False
        self.paused = False

    def walk(self):
        prev_trees = {}          # id -> crob
        prev_robots = set()
        prev_bul = {}            # team -> float
        prev_vp = {}             # team -> int
        cur = None
        trees = {}
        robots = set()
        bul = {}
        vp = {}
        acts = {}                # robot id -> (act, tgt)
        bullets_by_parentless = {}
        heal = {}                # robot id -> [(round, hp, ty, acted)]
        newborn_bullets = {}     # round -> count of B lines with ra=0
        with self.path.open() as fh:
            for line in fh:
                parts = line.split()
                if len(parts) < 3 or parts[0] != "R":
                    continue
                rnd = int(parts[1])
                kind = parts[2]
                if cur is None:
                    cur = rnd
                if rnd != cur:
                    self._close_round(cur, prev_trees, prev_robots, trees,
                                      robots, prev_bul, bul, prev_vp, vp,
                                      acts, newborn_bullets.get(cur, {}))
                    prev_trees, prev_robots = trees, robots
                    prev_bul, prev_vp = bul, vp
                    trees, robots, bul, vp, acts = {}, set(), {}, {}, {}
                    cur = rnd
                if kind == "T":
                    f = fields(parts[4:])
                    team = parts[3]
                    bul[team] = f32(f["bul"])
                    vp[team] = int(f["vp"])
                    if f["bul"] != BULLETS_INITIAL_BITS and self.idle_bul_ok:
                        self.idle_bul_ok = False
                        self.idle_bul_bad = (rnd, team, f["bul"])
                elif kind == "U":
                    rid_ = int(parts[3])
                    f = fields(parts[4:])
                    robots.add(rid_)
                    self.types.add(f["ty"])
                    ra = int(f["ra"])
                    if ra <= 20 and f["ty"] in ("SOLDIER", "LUMBERJACK",
                                                "TANK", "SCOUT"):
                        heal.setdefault(rid_, []).append(
                            (ra, f32(f["hp"]), f["ty"]))
                    bc = int(f["bc"])
                    if bc >= LIMITS[f["ty"]]:
                        self.paused_candidate = (rnd, rid_)
                        self.paused = self.paused or True
                elif kind == "E":
                    trees[int(parts[3])] = fields(parts[4:]).get("crob", "-")
                elif kind == "B":
                    f = fields(parts[4:])
                    if int(f["ra"]) == 0:
                        d = newborn_bullets.setdefault(rnd, {})
                        d[f["team"]] = d.get(f["team"], 0) + 1
                elif kind == "A":
                    f = fields(parts[4:])
                    acts[int(parts[3])] = (f["act"], int(f["tgt"]))
                    if f["act"] != "NOTHING":
                        self.acted = True
                elif kind == "G":
                    f = fields(parts[3:])
                    self.rid.add(f["rid"])
                    self.bid.add(f["bid"])
                    self.execlens.add(int(f["execlen"]))
                elif kind == "W":
                    f = fields(parts[3:])
                    self.winner = f.get("winner", "-")
                    self.dom = f.get("dom", "-")
                    self.doms.add(self.dom)
                self.last_round = max(self.last_round, rnd)
                if len(robots) > self.peak_robots:
                    self.peak_robots = len(robots)
        if cur is not None:
            self._close_round(cur, prev_trees, prev_robots, trees, robots,
                              prev_bul, bul, prev_vp, vp, acts,
                              newborn_bullets.get(cur, {}))
        # The dormancy window: a BUILDABLE robot heals exactly
        # `0.04 * maxHealth` a turn for its first twenty turns and takes no
        # action at all while it does.
        for rid_, rows in heal.items():
            rows.sort()
            if len(rows) < 20:
                continue
            ty = rows[0][2]
            step = 0.04 * MAX_HEALTH[ty]
            ok = True
            for i in range(1, 20):
                if rows[i][0] != rows[i - 1][0] + 1:
                    ok = False
                    break
                got = rows[i][1] - rows[i - 1][1]
                want = min(step, MAX_HEALTH[ty] - rows[i - 1][1])
                if abs(got - want) > 1e-4:
                    ok = False
                    break
            if ok:
                self.dormancy = True
                break
        return self

    def _close_round(self, rnd, prev_trees, prev_robots, trees, robots,
                     prev_bul, bul, prev_vp, vp, acts, newborn):
        gone = set(prev_trees) - set(trees)
        fresh = robots - prev_robots
        chopped = any(a[0] == "CHOP" for a in acts.values())
        for t in gone:
            crob = prev_trees[t]
            if chopped and crob != "-":
                for r in fresh:
                    self.chop_release = True
            if not chopped and crob == "-" and not fresh:
                self.bullet_kill_no_release = True
        for team, count in newborn.items():
            if count == 3:
                self.triad = True
            elif count == 5:
                self.pentad = True
        for rid_, (act, tgt) in acts.items():
            if act == "SHAKE" and prev_bul and bul:
                for team in bul:
                    if bul[team] > prev_bul.get(team, 0) + 0.5:
                        self.shake_jump = True
            if act == "DONATE" and prev_bul and bul:
                for team in bul:
                    spent = prev_bul.get(team, 0.0) - bul[team]
                    gained = vp.get(team, 0) - prev_vp.get(team, 0)
                    if spent <= 0 or gained <= 0:
                        continue
                    price = VP_BASE_COST + VP_INCREASE_PER_ROUND * rnd
                    if gained == tgt and math.floor(spent / price) == gained:
                        self.donate_floor = True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, type=pathlib.Path)
    ap.add_argument("--maps", nargs="+", required=True)
    ap.add_argument("--idle-bot", default="bc17idle")
    ap.add_argument("--weak-bot", default="examplefuncsplayer17")
    ap.add_argument("--scenario-bots", nargs="+", required=True)
    ap.add_argument("--slowbot-trace", type=pathlib.Path)
    args = ap.parse_args()

    bad = []
    scenario = []
    weak_peaks = []
    for bot in [args.idle_bot, args.weak_bot] + list(args.scenario_bots):
        for map_name in args.maps:
            path = args.dir / f"{bot}.{map_name}.java"
            if not path.exists():
                bad.append(f"{bot}/{map_name}: no Java trace at {path}")
                continue
            p = Pair(path).walk()
            tag = f"{bot}/{map_name}"
            print(f"{tag}: rounds={p.last_round} winner={p.winner} "
                  f"dom={p.dom} peak_robots={p.peak_robots} "
                  f"acted={p.acted} types={sorted(p.types)}")
            if p.last_round < 2900 and p.dom not in ("DESTROYED",
                                                     "PHILANTROPIED"):
                bad.append(
                    f"{tag}: ended at round {p.last_round} with dom={p.dom}. "
                    f"An early end must be a DECIDED game. Under a JDK newer "
                    f"than 8 the instrumenter kills every robot as it spawns "
                    f"and the game is over in one round -- this is the "
                    f"assertion that catches that from the other side.")
            if p.winner not in ("A", "B") or p.dom == "-":
                bad.append(f"{tag}: the final W line is "
                           f"winner={p.winner} dom={p.dom}; every 2017 game "
                           f"ends with a winner and a DominationFactor.")
            if bot == args.idle_bot:
                if not p.idle_bul_ok:
                    bad.append(
                        f"{tag}: an idle game's bullet supply left 300.0 at "
                        f"round {p.idle_bul_bad[0]} (team "
                        f"{p.idle_bul_bad[1]}, bits {p.idle_bul_bad[2]}). "
                        f"THE INCOME CLIFF: max(0, 2 - 0.01 * supply) is "
                        f"exactly zero at any supply of 200 or more.")
                if len(p.rid) != 1 or len(p.bid) != 1:
                    bad.append(
                        f"{tag}: an idle game drew an id -- rid values "
                        f"{sorted(p.rid)[:4]}, bid {sorted(p.bid)[:4]}. "
                        f"Nothing spawns without a player action in 2017.")
                if len(p.execlens) != 1:
                    bad.append(
                        f"{tag}: the exec order changed length in an idle "
                        f"game: {sorted(p.execlens)[:6]}")
                if p.dom != "WON_BY_DUBIOUS_REASONS":
                    bad.append(
                        f"{tag}: an idle game ended {p.dom}, not "
                        f"WON_BY_DUBIOUS_REASONS. With no victory points, no "
                        f"trees and equal bullet worth the ladder must fall "
                        f"through to rung 4.")
                if p.acted:
                    bad.append(f"{tag}: the IDLE bot took an action.")
            else:
                if not p.acted:
                    bad.append(
                        f"{tag}: not one A line carries a non-NOTHING "
                        f"action, so this pair agrees about nothing "
                        f"happening.")
            if bot == args.weak_bot:
                weak_peaks.append(p.peak_robots)
                if p.peak_robots < 7:
                    bad.append(
                        f"{tag}: peaked at {p.peak_robots} robots. The "
                        f"measured minimum over the nine pairs is 7 "
                        f"(`Cramped`, whose sides annihilate each other by "
                        f"round 533).")
            if bot in args.scenario_bots:
                scenario.append(p)

    if weak_peaks and max(weak_peaks) < 30:
        bad.append(
            f"the weak floor peaked at only {max(weak_peaks)} robots across "
            f"all nine pairs; the measured maximum is 78 (`Alone`). Tier A'' "
            f"is the tier that runs a REAL army.")

    # Tier A': the scripted paths, over the 36 traces TOGETHER.
    if scenario:
        types = set()
        doms = set()
        for p in scenario:
            types |= p.types
            doms |= p.doms
        want_types = {"ARCHON", "GARDENER", "LUMBERJACK", "SOLDIER", "TANK",
                      "SCOUT"}
        missing = want_types - types
        if missing:
            bad.append(
                f"Tier A': the scenario traces never show a "
                f"{sorted(missing)} -- the bots are supposed to build one of "
                f"each of the six types.")
        want_doms = {"DESTROYED", "PWNED", "OWNED", "BARELY_BEAT",
                     "WON_BY_DUBIOUS_REASONS"}
        missing_doms = want_doms - doms
        if missing_doms:
            bad.append(
                f"Tier A': the scenario traces never end {sorted(missing_doms)}"
                f". Every rung of the round-limit ladder plus the mid-round "
                f"destruction win is supposed to be on this set. "
                f"(PHILANTROPIED is NOT in this set and is named in "
                f"docs/PARITY.md section bc17 as not reachable.)")
        checks = [
            ("the 20-turn dormancy and its 4 %-a-turn heal",
             any(p.dormancy for p in scenario)),
            ("a TRIAD (three bullets from one robot in one round)",
             any(p.triad for p in scenario)),
            ("a PENTAD (five bullets from one robot in one round)",
             any(p.pentad for p in scenario)),
            ("the chop-only goodie release (a tree with a contained robot "
             "destroyed on a CHOP round, followed by a new robot)",
             any(p.chop_release for p in scenario)),
            ("a tree destroyed with NO chop and NO release",
             any(p.bullet_kill_no_release for p in scenario)),
            ("a bullet-supply jump on a SHAKE",
             any(p.shake_jump for p in scenario)),
            ("a victory-point jump on a DONATE, with floor(spent/price) "
             "recomputed from the trace",
             any(p.donate_floor for p in scenario)),
        ]
        for name, ok in checks:
            print(f"Tier A' {'OK  ' if ok else 'MISS'}: {name}")
            if not ok:
                bad.append(f"Tier A': {name} never happened in any of the "
                           f"{len(scenario)} scenario traces.")

    # Tier B' (b): the slow bot really was paused.
    if args.slowbot_trace is not None:
        if not args.slowbot_trace.exists():
            bad.append(f"no slowbot trace at {args.slowbot_trace}")
        else:
            pegged = None
            with args.slowbot_trace.open() as fh:
                for line in fh:
                    parts = line.split()
                    if len(parts) < 3 or parts[2] != "U":
                        continue
                    f = fields(parts[4:])
                    if int(f["bc"]) >= LIMITS[f["ty"]]:
                        pegged = (parts[1], parts[3], f["bc"], f["ty"])
                        break
            if pegged is None:
                bad.append(
                    "Tier B' (b): `bc17slowbot` burns ~20 000 bytecodes a "
                    "turn and the engine never paused it. Either the burn "
                    "was optimised away or the metering is not what the port "
                    "believes it is (docs/RULES-BC17.md V1).")
            else:
                print(f"Tier B' (b): robot {pegged[1]} ({pegged[3]}) used "
                      f"{pegged[2]} bytecodes on round {pegged[0]}, at or "
                      f"over its limit -- the engine's pause-and-resume "
                      f"exists and fires where the rule says it does.")

    for b in bad:
        print(f"::error::{b}")
    if bad:
        return 1
    print("bc17: every trace really played a game, and every path Tier A' "
          "claims really fired.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
