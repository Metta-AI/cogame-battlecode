// TIER A' -- `bc17scenariokill`: DESTROYED, proved end to end.
//
// CI-TIME ONLY, no RNG at all. The Nim twin is the `-d:bc17ScenarioKill`
// arm of `src/battlecode/years/bc17/chassis/scenario17.nim`.
//
// Archons hire on rounds 2, 13 and 24 (the ten-turn cooldown, three times),
// every gardener builds a SOLDIER every eleventh turn it is ready, and every
// soldier fires a single shot at the nearest enemy and then WALKS ONTO IT.
// On a map whose sides start close -- `HouseDivided`'s archon separation is
// 6.5 -- one side loses its last robot, which is what proves that the winner
// is set MID-ROUND by `setWinnerIfDestruction`, that the round STILL
// FINISHES (income, decay and every remaining body's turn), and that the
// NEXT `runRound` returns DONE.
//
// `senseNearbyRobots(-1, enemy)` returns the candidates in ASCENDING
// DISTANCE, which is the normalisation `rtree_order.patch` puts on the
// engine and `index.nim` puts on the port (D2) -- so `enemies[0]` is the
// nearest enemy on both sides, and this bot is one of the two places that
// order is load-bearing.
//
// See `bc17scenario/RobotPlayer.java`'s header for `roundsAlive` and the
// headroom assertion.
package bc17scenariokill;

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
                    case ARCHON: {
                        int round = rc.getRoundNum();
                        if (round == 2 || round == 13 || round == 24) {
                            Direction north = new Direction(0f, 1f);
                            if (rc.canHireGardener(north)) {
                                rc.hireGardener(north);
                            }
                        }
                        break;
                    }
                    case GARDENER: {
                        Direction east = new Direction(1f, 0f);
                        if (rc.isBuildReady() && roundsAlive % 11 == 1
                                && rc.canBuildRobot(RobotType.SOLDIER, east)) {
                            rc.buildRobot(RobotType.SOLDIER, east);
                        }
                        break;
                    }
                    case SOLDIER: {
                        RobotInfo[] enemies = rc.senseNearbyRobots(-1,
                                rc.getTeam().opponent());
                        if (enemies.length > 0) {
                            MapLocation target = enemies[0].location;
                            if (rc.canFireSingleShot()) {
                                rc.fireSingleShot(
                                        rc.getLocation().directionTo(target));
                            }
                            if (!rc.hasMoved() && rc.canMove(target)) {
                                rc.move(target);
                            }
                        } else {
                            Direction east = new Direction(1f, 0f);
                            if (!rc.hasMoved()
                                    && rc.canMove(east,
                                            rc.getType().strideRadius)) {
                                rc.move(east, rc.getType().strideRadius);
                            }
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
