// TIER A' -- `bc17scenario`, the scripted bot that forces every rare path
// EARLY instead of hoping a real game reaches it.
//
// CI-TIME ONLY (the `parity-oracle-bc17` job). **NO RNG AT ALL**: every
// branch is a function of the round number and the robot's own age, so both
// sides can be compared BIT FOR BIT for a whole 2 999-round game. Its Nim
// twin is `src/battlecode/years/bc17/chassis/scenario17.nim`, selected by
// `-d:bc17Scenario`, and the two are written LINE FOR LINE against each
// other.
//
// What it forces: hire a GARDENER and prove the ten-turn cooldown (a second
// hire one round later is refused, a third at round 13 is not); plant and
// then try to build on the next round, proving the cooldown is SHARED
// between planting and building; water a tree at 45 HP and at 48 HP (the
// wasted 3 of the clamp); build one of each of SOLDIER, LUMBERJACK, TANK and
// SCOUT and prove the 20-turn dormancy and the 4 %-a-turn heal; move at
// exactly `strideRadius`, at half of it and at TWICE it (the atan2
// re-projection); walk a SCOUT onto a tree and a TANK into one (the body
// attack); fire a single, a triad and a pentad at a known angle and prove
// the centre-left-right spawn order and the bullet id sequence; strike;
// chop a neutral tree and shake one; broadcast on channel 0 and on channel
// 9 999; and donate a NON-MULTIPLE of the price so the destroyed remainder
// is on the trace.
//
// **`roundsAlive` IS NOT EXPOSED TO A PLAYER**, so it is counted here, and
// the count starts at 20 for a BUILDABLE type because such a robot is
// dormant -- `canExecuteCode()` is false and its bytecode limit is 0 -- for
// exactly its first twenty turns. The Nim twin reads the real counter, so
// the two agree only if this reconstruction is right, and the trace's `ra=`
// column is what proves it round by round.
//
// TIER B' (a): the headroom assertion. Under the instrumenter
// `java.lang.System` is rewritten to `battlecode/instrumenter/inject/System`
// whose `exit(int)` throws `RobotDeathException`, so this kills the robot,
// removes it from the trace and diverges the pair on that round. That is the
// point: the engine's own pause-and-resume must PROVABLY never fire in any
// game this job compares.
package bc17scenario;

import battlecode.common.*;

public strictfp class RobotPlayer {
    static RobotController rc;
    static int roundsAlive;

    public static void run(RobotController rc) throws GameActionException {
        RobotPlayer.rc = rc;
        roundsAlive = rc.getType().isBuildable() ? 20 : 0;
        while (true) {
            try {
                switch (rc.getType()) {
                    case ARCHON: archon(); break;
                    case GARDENER: gardener(); break;
                    default: fighter(); break;
                }
            } catch (Exception e) {
                // The Nim twin COUNTS a refusal and moves on; the engine
                // throws. Swallowing here is what makes the two the same bot.
            }
            if (Clock.getBytecodesLeft() < 5000) {
                System.exit(4);
            }
            Clock.yield();
            roundsAlive++;
        }
    }

    static Direction east() { return new Direction(1f, 0f); }

    static Direction north() { return new Direction(0f, 1f); }

    static void archon() throws GameActionException {
        final int round = rc.getRoundNum();
        if (round == 2 || round == 3 || round == 13) {
            if (rc.canHireGardener(north())) rc.hireGardener(north());
        }
        if (round == 5) {
            rc.broadcast(0, 1234);
            rc.broadcast(GameConstants.BROADCAST_MAX_CHANNELS - 1, 4321);
        }
        if (round == 20) {
            // A NON-MULTIPLE of the price: 100 bullets at 7.5833 buys 13
            // points and the remainder is destroyed.
            if (rc.getTeamBullets() >= 100f) rc.donate(100f);
        }
        if (round == 30) {
            move(east(), rc.getType().strideRadius);
        } else if (round == 31) {
            move(east(), rc.getType().strideRadius / 2f);
        } else if (round == 32) {
            // TWICE a stride: the engine RE-PROJECTS rather than scaling, so
            // the destination is not on the segment.
            MapLocation target = rc.getLocation().add(east(),
                    rc.getType().strideRadius * 2f);
            if (!rc.hasMoved() && rc.canMove(target)) rc.move(target);
        }
    }

    /**
     * One of each BUILDABLE type, in cost order. `step` advances ONLY ON A
     * SUCCESSFUL BUILD, which is what makes the schedule reach a TANK at
     * all: a tank costs 300 bullets and a fixed round number would simply be
     * refused for want of funds, leaving the 20-turn dormancy, the tank's
     * body attack and the four-type `U` line coverage untested while the
     * pair still agreed bit for bit. The retry is DETERMINISTIC -- the
     * cursor is a function of the game's own history, not of a clock -- and
     * the Nim twin's `r.step` is the same cursor.
     */
    static final RobotType[] BUILD_ORDER = {
        RobotType.SOLDIER, RobotType.LUMBERJACK, RobotType.TANK,
        RobotType.SCOUT
    };
    static int step = -1;

    static void gardener() throws GameActionException {
        if (rc.isBuildReady()) {
            if (roundsAlive == 1) {
                if (rc.canPlantTree(east())) rc.plantTree(east());
            } else if (roundsAlive == 2) {
                // REFUSED, and that is the point: planting and building
                // share the ten-turn cooldown slot.
                build(RobotType.SOLDIER);
            } else if (roundsAlive >= 12) {
                if (step < 0) step = 0;
                if (step < BUILD_ORDER.length
                        && rc.canBuildRobot(BUILD_ORDER[step], north())) {
                    rc.buildRobot(BUILD_ORDER[step], north());
                    step++;
                }
            }
        }
        // Water once the tree has decayed to 45 and again at 48, so the
        // clamp's wasted 3 is on the trace. The twin's `waterCount == 0`
        // guard is unconditionally true where it stands -- the counter is
        // reset at the start of every turn and nothing above waters -- and
        // `getWaterCount()` is not on the 2017 `RobotController` at all.
        {
            TreeInfo[] mine = rc.senseNearbyTrees(
                    rc.getType().bodyRadius + GameConstants.BULLET_TREE_RADIUS
                            + GameConstants.INTERACTION_DIST_FROM_EDGE,
                    rc.getTeam());
            for (int i = 0; i < mine.length; i++) {
                if (mine[i].health >= 45f && mine[i].health <= 48f) {
                    if (rc.canWater(mine[i].ID)) rc.water(mine[i].ID);
                    break;
                }
            }
        }
    }

    static void build(RobotType type) throws GameActionException {
        if (rc.canBuildRobot(type, north())) rc.buildRobot(type, north());
    }

    static void fighter() throws GameActionException {
        switch (rc.getType()) {
            case SOLDIER: {
                int phase = roundsAlive % 12;
                if (phase == 1) {
                    if (rc.canFireSingleShot()) rc.fireSingleShot(east());
                } else if (phase == 4) {
                    if (rc.canFireTriadShot()) rc.fireTriadShot(east());
                } else if (phase == 7) {
                    if (rc.canFirePentadShot()) rc.firePentadShot(east());
                } else {
                    move(east(), rc.getType().strideRadius);
                }
                break;
            }
            case TANK:
            case SCOUT:
                move(east(), rc.getType().strideRadius);
                break;
            case LUMBERJACK: {
                if (roundsAlive % 6 == 1) {
                    if (rc.canStrike()) rc.strike();
                } else {
                    boolean chopped = false;
                    TreeInfo[] near = rc.senseNearbyTrees(
                            rc.getType().bodyRadius
                                    + GameConstants.NEUTRAL_TREE_MAX_RADIUS
                                    + GameConstants.INTERACTION_DIST_FROM_EDGE);
                    for (int i = 0; i < near.length; i++) {
                        if (near[i].team == rc.getTeam()) continue;
                        if (rc.canChop(near[i].ID)) {
                            rc.chop(near[i].ID);
                            chopped = true;
                            break;
                        }
                    }
                    if (!chopped) move(east(), rc.getType().strideRadius);
                }
                break;
            }
            default:
                break;
        }
        // Shake anything in reach, so the bullet jump is on the trace. The
        // twin's `shakeCount == 0` guard is unconditionally true here for
        // the same reason the water one is.
        {
            TreeInfo[] wild = rc.senseNearbyTrees(
                    rc.getType().bodyRadius
                            + GameConstants.NEUTRAL_TREE_MAX_RADIUS
                            + GameConstants.INTERACTION_DIST_FROM_EDGE,
                    Team.NEUTRAL);
            for (int i = 0; i < wild.length; i++) {
                if (rc.canShake(wild[i].ID)) {
                    rc.shake(wild[i].ID);
                    break;
                }
            }
        }
    }

    static void move(Direction dir, float dist) throws GameActionException {
        if (!rc.hasMoved() && rc.canMove(dir, dist)) rc.move(dir, dist);
    }
}
