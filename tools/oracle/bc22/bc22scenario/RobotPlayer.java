// The Tier A-prime SCENARIO BOT: deterministic, RNG-free, and scripted by
// round number to force every rare path early.
//
// CI-TIME ONLY. This file is compiled and run by the `parity-oracle-bc22` job
// against the released `battlecode22-2.2.1.jar`; there is no JDK, no JRE and
// no Java in any runtime image stage.
//
// IT IS WRITTEN LINE FOR LINE AGAINST
// `src/battlecode/years/bc22/chassis/scenario22.nim`. Read them side by side.
// Three properties, each of which the parity job asserts:
//
//   (a) NO RNG AT ALL. Every decision is a function of the round number, the
//       robot's id, its type and the engine's own scan order. There is no
//       draw to desynchronise.
//   (b) CHEAP. The job asserts it never exceeds 25 % of its bytecode limit,
//       so it can never be cut off mid-turn and the port's "no mid-turn
//       resumption" divergence (docs/RULES-BC22.md Divergences item 1) is
//       never exercised.
//   (c) SCRIPTED TO FORCE THE RARE PATHS that Tier A's example bot never
//       reaches. Over eight full 2000-round games the 2022 example bot never
//       built a builder, a sage, a laboratory or a watchtower, never mutated,
//       never transformed, never transmuted, never envisioned, never wrote
//       the shared array, never made a single gold, and ended EVERY game at
//       round 2000 on MORE_LEAD_NET_WORTH with gold 0-0.
//
// EVERY QUERY IS ROBOT-LOCAL, and that is the whole reason this file can
// exist. A sandboxed robot has a `RobotController`, not a `GameWorld`: it
// cannot ask for its team's building count, for the enemy's archon list, or
// for the anomaly cursor. So every scan goes through
// `getAllLocationsWithinRadiusSquared`, which clamps the radius to the type's
// vision radius and walks the engine's own x-outer/y-inner order over the
// `ceil(sqrt) + 1` box, and the anomaly lookahead goes through
// `rc.getAnomalySchedule()` scanned for the first entry at or after this
// round. `scenario22.nim`'s `visible` iterator and `nextScheduled` proc are
// those two methods, ported.
package bc22scenario;

import battlecode.common.*;

public class RobotPlayer {

    // `Direction.values()`'s first eight, in the enum's own order, written out
    // as literals so neither side depends on the other's iteration order by
    // accident. This is scenario22.nim's `ScenarioDirs`.
    static final Direction[] DIRS = {
        Direction.NORTH, Direction.NORTHEAST, Direction.EAST,
        Direction.SOUTHEAST, Direction.SOUTH, Direction.SOUTHWEST,
        Direction.WEST, Direction.NORTHWEST
    };

    // The variant switch. The Nim twin selects the same four scripts with
    // `-d:bc22Scenario` / `-d:bc22ScenarioAnnihilate` / `-d:bc22ScenarioTie` /
    // `-d:bc22ScenarioFury`; here `tools/oracle/bc22/build_oracle.sh` emits
    // FOUR PACKAGES from this one file with `sed`, rewriting the package line
    // and the literal below. It is a compile-time constant on purpose: a
    // `System.getProperty` call would be refused by the instrumenter, and a
    // `static final boolean` folds away so no robot pays a bytecode for it.
    static final String VARIANT = "base"; // VARIANT-LINE
    static final boolean ANNIHILATE = VARIANT.equals("annihilate");
    static final boolean TIE = VARIANT.equals("tie");
    static final boolean FURY = VARIANT.equals("fury");

    public static void run(RobotController rc) throws GameActionException {
        while (true) {
            try {
                switch (rc.getType()) {
                    case ARCHON: archon(rc); break;
                    case BUILDER: builder(rc); break;
                    case MINER: miner(rc); break;
                    case SOLDIER: soldier(rc); break;
                    case SAGE: sage(rc); break;
                    case WATCHTOWER: turret(rc); break;
                    case LABORATORY: lab(rc); break;
                    default: break;
                }
            } catch (GameActionException ignored) {
            } catch (Exception ignored) {
            } finally {
                Clock.yield();
            }
        }
    }

    // ---- the local scans, each one a proc in scenario22.nim --------------

    static MapLocation[] visible(RobotController rc, int r2)
            throws GameActionException {
        return rc.getAllLocationsWithinRadiusSquared(rc.getLocation(), r2);
    }

    static AnomalyScheduleEntry nextScheduled(RobotController rc) {
        AnomalyScheduleEntry[] sched = rc.getAnomalySchedule();
        int now = rc.getRoundNum();
        for (int i = 0; i < sched.length; i++) {
            if (sched[i].roundNumber >= now) return sched[i];
        }
        return null;
    }

    static boolean buildFirst(RobotController rc, RobotType type)
            throws GameActionException {
        for (int i = 0; i < DIRS.length; i++) {
            if (rc.canBuildRobot(type, DIRS[i])) {
                rc.buildRobot(type, DIRS[i]);
                return true;
            }
        }
        return false;
    }

    static boolean moveFirst(RobotController rc) throws GameActionException {
        for (int i = 0; i < DIRS.length; i++) {
            if (rc.canMove(DIRS[i])) {
                rc.move(DIRS[i]);
                return true;
            }
        }
        return false;
    }

    static boolean seesFriendly(RobotController rc, RobotType type)
            throws GameActionException {
        for (MapLocation l : visible(rc, rc.getType().actionRadiusSquared)) {
            RobotInfo b = at(rc, l);
            if (b != null && b.team == rc.getTeam() && b.type == type) {
                return true;
            }
        }
        return false;
    }

    static boolean attackFirst(RobotController rc)
            throws GameActionException {
        for (MapLocation l : visible(rc, rc.getType().actionRadiusSquared)) {
            if (rc.canAttack(l)) {
                rc.attack(l);
                return true;
            }
        }
        return false;
    }

    // NO `canSenseRobotAtLocation` GUARD, on purpose: every location
    // `visible()` returns is on the map and inside the type's vision radius
    // (the engine clamps the radius itself), so the guard can only ever be
    // true and it costs a bytecode charge per square. The bot has a 25 %
    // budget and the parity job enforces it.
    static RobotInfo at(RobotController rc, MapLocation l)
            throws GameActionException {
        return rc.senseRobotAtLocation(l);
    }

    // ---- the seven scripts ------------------------------------------------

    static void archon(RobotController rc) throws GameActionException {
        int round = rc.getRoundNum();
        // Rounds 1-3: one miner each way, so there is an economy at all.
        if (round <= 3) { buildFirst(rc, RobotType.MINER); return; }
        if (ANNIHILATE) {
            // Every soldier the lead allows, for the annihilation run.
            buildFirst(rc, RobotType.SOLDIER);
            return;
        }
        // Rounds 4-12: THE BUILDER, which is what unlocks every building
        // path -- retried until one exists, not attempted once. Measured: on
        // `maze`, `turtle` and `vortex` the archon's square carries enough
        // rubble that its action cooldown lands on round 4, a single attempt
        // missed, and those three maps then ran 2000 rounds with no builder,
        // no laboratory, no watchtower, no gold and no sage -- i.e. Tier A'
        // proving nothing on three of eight maps.
        if (round <= 12) {
            if (!seesFriendly(rc, RobotType.BUILDER)) {
                if (buildFirst(rc, RobotType.BUILDER)) return;
            }
            buildFirst(rc, RobotType.SOLDIER);
            return;
        }
        // Rounds 13-40: soldiers, so the board is not empty.
        if (round <= 40) { buildFirst(rc, RobotType.SOLDIER); return; }
        // ONE PASS over the action radius, answering both questions this
        // script asks of it: is there already a sage, and what is the first
        // damaged friendly droid. TWO scans of a radius-20 box cost the
        // ARCHON 28-36 % of its 20 000 bytecodes -- measured -- and the whole
        // point of this bot is a 25 % ceiling.
        boolean sageSeen = false;
        MapLocation damaged = null;
        Team me = rc.getTeam();
        for (MapLocation l : visible(rc,
                RobotType.ARCHON.actionRadiusSquared)) {
            RobotInfo b = at(rc, l);
            if (b == null || b.team != me) continue;
            if (b.type == RobotType.SAGE) sageSeen = true;
            if (damaged == null && !b.type.isBuilding()
                    && b.health < b.type.getMaxHealth(b.level)) {
                damaged = l;
            }
        }
        // ONE sage, and only one -- the only unit that can envision. The
        // uncapped form was measured to spend every gold the laboratory ever
        // made: 1 722 sage-rounds on `chalice`, a team gold that never rose
        // above 20 for long, and therefore NO level-3 (gold) mutation
        // anywhere in 32 whole games. A sage costs 20 Au and a level-3
        // mutation costs gold too, and the scenario has to fund both.
        if (!sageSeen && rc.getTeamGoldAmount(me)
                    >= RobotType.SAGE.buildCostGold) {
            if (buildFirst(rc, RobotType.SAGE)) return;
        }
        // Round 300: transform out to PORTABLE; rounds 301-319 move; round
        // 320 onwards transform back -- proving exactly ONE counter is
        // charged each time. THE RETURN WINDOW IS OPEN-ENDED ON PURPOSE. A
        // three-round window (300 out, 301-302 move, 303 back) was measured
        // to leave the archon PORTABLE FOR EVER on all eight maps: the
        // transform cooldown is the type's movement cooldown scaled by
        // rubble, so `canTransform()` was still false on round 303, the
        // archon never came back, never built again, and no sage -- and
        // therefore no envision -- existed in the whole run.
        if (!FURY) {
            if (round == 300 && rc.getMode() == RobotMode.TURRET
                    && rc.canTransform()) {
                rc.transform();
                return;
            }
            if (round >= 301 && round <= 319
                    && rc.getMode() == RobotMode.PORTABLE) {
                moveFirst(rc);
                return;
            }
            if (round >= 320 && rc.getMode() == RobotMode.PORTABLE) {
                if (rc.canTransform()) rc.transform();
                return;
            }
        }
        // Otherwise: write the round number to the shared array (free in this
        // year, and legal with nothing nearby -- which is illegal in 2023),
        // then repair the first damaged friendly droid in range.
        rc.writeSharedArray(0,
                round % (GameConstants.MAX_SHARED_ARRAY_VALUE + 1));
        if (damaged != null && rc.canRepair(damaged)) {
            rc.repair(damaged);
            return;
        }
        buildFirst(rc, RobotType.SOLDIER);
    }

    static void builder(RobotController rc) throws GameActionException {
        // ONE PASS over the action radius, collecting the first square of
        // each category and the building census at the same time. The
        // three-scan form this replaces peaked at 58 % of the BUILDER's 7 500
        // bytecodes -- measured -- and the whole point of this bot is that it
        // can never be cut off mid-turn.
        MapLocation proto = null;
        MapLocation mutable = null;
        MapLocation damaged = null;
        int labs = 0;
        int towers = 0;
        Team me = rc.getTeam();
        for (MapLocation l : visible(rc,
                RobotType.BUILDER.actionRadiusSquared)) {
            RobotInfo b = at(rc, l);
            if (b == null || b.team != me) continue;
            if (b.type == RobotType.LABORATORY) labs++;
            else if (b.type == RobotType.WATCHTOWER) towers++;
            if (proto == null && b.mode == RobotMode.PROTOTYPE) proto = l;
            if (!b.type.isBuilding()) continue;
            if (mutable == null && rc.canMutate(l)) mutable = l;
            if (damaged == null && b.health < b.type.getMaxHealth(b.level)) {
                damaged = l;
            }
        }
        // Finish anything unfinished FIRST -- ten repairs for a laboratory,
        // fifteen for a watchtower -- then mutate, then place the next one,
        // then top up a finished building.
        if (proto != null && rc.canRepair(proto)) { rc.repair(proto); return; }
        if (mutable != null) { rc.mutate(mutable); return; }
        if (labs == 0) {
            if (buildFirst(rc, RobotType.LABORATORY)) return;
        } else if (towers < 2) {
            if (buildFirst(rc, RobotType.WATCHTOWER)) return;
        }
        if (damaged != null && rc.canRepair(damaged)) rc.repair(damaged);
    }

    static void miner(RobotController rc) throws GameActionException {
        // Exactly one miner disintegrates, at round 500, so the death path
        // and its reclaim drop are exercised without an attack.
        if (rc.getRoundNum() == 500 && rc.getID() % 7 == 0) {
            rc.disintegrate();
            return;
        }
        // One square is mined to ZERO and another to EXACTLY ONE, so the next
        // multiple of twenty proves that only the second regenerates.
        boolean first = true;
        for (MapLocation l : visible(rc,
                RobotType.MINER.actionRadiusSquared)) {
            while (rc.canMineGold(l)) rc.mineGold(l);
            int floorAt = first ? 0 : 1;
            first = false;
            while (rc.senseLead(l) > floorAt && rc.canMineLead(l)) {
                rc.mineLead(l);
            }
        }
        if (rc.isMovementReady()) moveFirst(rc);
    }

    static void soldier(RobotController rc) throws GameActionException {
        if (TIE) {
            // The tie run never attacks: the ladder has to walk all the way
            // down.
            if (rc.isMovementReady()) moveFirst(rc);
            return;
        }
        if (attackFirst(rc)) return;
        if (ANNIHILATE && rc.isMovementReady()) {
            // Home on the ROTATIONAL MIRROR of this square. A robot does not
            // know the map's symmetry or its own spawn, but it does know
            // getMapWidth() and getMapHeight(), and (W-1-x, H-1-y) is always
            // in the other half -- so soldiers cross the board, meet the
            // enemy archon and kill it.
            MapLocation me = rc.getLocation();
            MapLocation mirror = new MapLocation(
                    rc.getMapWidth() - 1 - me.x, rc.getMapHeight() - 1 - me.y);
            Direction d = me.directionTo(mirror);
            if (rc.canMove(d)) {
                rc.move(d);
                return;
            }
        }
        if (rc.isMovementReady()) moveFirst(rc);
    }

    static void sage(RobotController rc) throws GameActionException {
        // Envision each of ABYSS, CHARGE and FURY in turn, proving the three
        // radii and the three truncations. VORTEX.isSageAnomaly is false, so a
        // sage cannot envision one and the engine refuses it.
        int m = rc.getID() % 3;
        AnomalyType choice = m == 0 ? AnomalyType.ABYSS
                : (m == 1 ? AnomalyType.CHARGE : AnomalyType.FURY);
        if (rc.canEnvision(choice)) {
            rc.envision(choice);
            return;
        }
        if (!TIE) {
            if (attackFirst(rc)) return;
        }
        if (rc.isMovementReady()) moveFirst(rc);
    }

    static void turret(RobotController rc) throws GameActionException {
        // A watchtower: one stands in TURRET mode through a scheduled FURY and
        // one stands up to PORTABLE before it, so the pair proves 7 and 0.
        if (rc.getMode() == RobotMode.PROTOTYPE) return;
        if (!FURY) {
            AnomalyScheduleEntry nxt = nextScheduled(rc);
            // A FURY WITHIN ELEVEN ROUNDS, not exactly eleven rounds away.
            // The exact form was measured never to fire: a watchtower has to
            // be alive, finished, even-id and off cooldown on one specific
            // round, and over 32 whole games that never once coincided.
            boolean furySoon = nxt != null
                    && nxt.anomalyType == AnomalyType.FURY
                    && nxt.roundNumber - rc.getRoundNum() <= 11;
            if (furySoon && rc.getID() % 2 == 0
                    && rc.getMode() == RobotMode.TURRET
                    && rc.canTransform()) {
                rc.transform();
                return;
            }
            if (rc.getMode() == RobotMode.PORTABLE && !furySoon) {
                if (rc.canTransform()) rc.transform();
                return;
            }
        }
        if (rc.getMode() != RobotMode.TURRET) return;
        if (!TIE) attackFirst(rc);
    }

    static void lab(RobotController rc) throws GameActionException {
        if (rc.getMode() != RobotMode.TURRET) return;
        if (rc.canTransmute()) rc.transmute();
    }
}
