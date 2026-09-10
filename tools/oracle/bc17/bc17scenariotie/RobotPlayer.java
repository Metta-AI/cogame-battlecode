// TIER A' -- `bc17scenariotie`: the round-limit ladder, walked rung by rung.
//
// CI-TIME ONLY, no RNG at all. The Nim twin is the `-d:bc17ScenarioTie` arm
// of `src/battlecode/years/bc17/chassis/scenario17.nim`.
//
// Both sides do exactly the same thing -- hire one gardener on round 2 and
// plant one tree with it -- so nothing separates them for 2 999 rounds
// except the ONE asymmetry: TEAM A donates 8 bullets on round 40, which at
// that round's price buys exactly one victory point. That is rung 1
// (`teamInfo.getVictoryPoints(A) != getVictoryPoints(B)` -> PWNED) reached
// by a ONE-POINT margin, with rungs 2, 3 and 4 sitting underneath it
// untouched -- and on the maps where the mirrored plant does not survive,
// the ladder falls through to rung 2 (a one-tree difference), rung 3 (a
// one-bullet difference INCLUDING the archon's -1 `bulletCost`) or rung 4
// (the highest robot id). Which rung a given map reaches is itself part of
// the compared trace: the `W` line carries the `DominationFactor` by name.
//
// See `bc17scenario/RobotPlayer.java`'s header for `roundsAlive` and the
// headroom assertion.
package bc17scenariotie;

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
                        Direction north = new Direction(0f, 1f);
                        if (rc.getRoundNum() == 2
                                && rc.canHireGardener(north)) {
                            rc.hireGardener(north);
                        }
                        if (rc.getRoundNum() == 40 && rc.getTeam() == Team.A
                                && rc.getTeamBullets() >= 8f) {
                            rc.donate(8f);
                        }
                        break;
                    }
                    case GARDENER: {
                        Direction east = new Direction(1f, 0f);
                        if (rc.isBuildReady() && roundsAlive == 1
                                && rc.canPlantTree(east)) {
                            rc.plantTree(east);
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
