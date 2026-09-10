// TIER A' -- `bc17scenariotree`: THE TREE LIFE CYCLE IN ISOLATION.
//
// CI-TIME ONLY, no RNG at all. The Nim twin is the `-d:bc17ScenarioTree`
// arm of `src/battlecode/years/bc17/chassis/scenario17.nim`.
//
// One archon hires one gardener, the gardener plants ONE tree and then
// stands still, and a TANK is built long after the tree has matured and
// walked west INTO it. What that puts on the trace, round by round and in
// raw float32 bits: the 81-round growth with its exact health sequence
// (`healTree(BULLET_TREE_MAX_HEALTH * 0.01f)` while `roundsAlive <= 80`) and
// ZERO income throughout; the FIRST income round (`health * (1f/50f)`, with
// the constant computed at class-init and not written as `0.02f`); the decay
// that starts with it; and a tree killed by a TANK BODY ATTACK -- 4 damage,
// the move spent (`incrementMoveCount` fires BEFORE the tank branch), and
// the tank refusing to move while still blocked.
//
// See `bc17scenario/RobotPlayer.java`'s header for why `roundsAlive` is
// counted here and why the headroom assertion is a `System.exit`.
package bc17scenariotree;

import battlecode.common.*;

public strictfp class RobotPlayer {
    static RobotController rc;
    static int roundsAlive;
    static int step = -1;

    public static void run(RobotController rc) throws GameActionException {
        RobotPlayer.rc = rc;
        roundsAlive = rc.getType().isBuildable() ? 20 : 0;
        while (true) {
            try {
                switch (rc.getType()) {
                    case ARCHON:
                        if (rc.getRoundNum() == 2) {
                            Direction north = new Direction(0f, 1f);
                            if (rc.canHireGardener(north)) {
                                rc.hireGardener(north);
                            }
                        }
                        break;
                    case GARDENER:
                        if (rc.isBuildReady()) {
                            Direction east = new Direction(1f, 0f);
                            if (roundsAlive == 1) {
                                if (rc.canPlantTree(east)) rc.plantTree(east);
                            } else if (roundsAlive >= 120 && step < 0) {
                                // Once the tree is long past its 81-round
                                // growth: a TANK costs 300 bullets, so this
                                // RETRIES until the side can afford one
                                // rather than firing once at a round number
                                // and silently never happening.
                                if (rc.canBuildRobot(RobotType.TANK, east)) {
                                    rc.buildRobot(RobotType.TANK, east);
                                    step = 1;
                                }
                            }
                        }
                        break;
                    case TANK: {
                        Direction west = new Direction(-1f, 0f);
                        if (!rc.hasMoved()
                                && rc.canMove(west, rc.getType().strideRadius)) {
                            rc.move(west, rc.getType().strideRadius);
                        }
                        break;
                    }
                    default:
                        break;
                }
            } catch (Exception e) {
                // The twin counts a refusal and moves on; the engine throws.
            }
            if (Clock.getBytecodesLeft() < 5000) {
                System.exit(4);
            }
            Clock.yield();
            roundsAlive++;
        }
    }
}
