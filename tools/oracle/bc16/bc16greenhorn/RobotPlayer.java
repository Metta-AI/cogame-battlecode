// `greenhorn`'s Java twin, STATEMENT FOR STATEMENT against
// `src/battlecode/years/bc16/chassis/greenhorn.nim`.
//
// CI-TIME ONLY. Compiled by `tools/oracle/bc16/build_oracle.sh` against the
// published `battlecode-2016.0.2.2.jar` and run by the `parity-oracle-bc16`
// job's Tier A". There is no JDK in any runtime image stage.
//
// **IT MAY NOT GAIN BEHAVIOUR: it is one side of the differential oracle.**
// There is no upstream `examplefuncsplayer` for 2016 — the 2016 scaffold is a
// separate, unarchived project — so this bot is DEFINED by the Nim file above
// and written here from that specification, which is why it is kept to a
// shape small enough to verify by reading.
//
// `new java.util.Random(2016)` is seeded PER ROBOT: static fields are per
// robot under the instrumenter, so every unit carries its own stream and this
// bot needs no determinism patch (unlike bc20's, which did).
//
// Tier A" is what proves the two equal. `tests/test_bc16_greenhorn.nim`
// asserts, from the other side, that this file carries each of the five
// load-bearing statements and NONE of the behaviours the bot may not have.
package bc16greenhorn;

import battlecode.common.Direction;
import battlecode.common.RobotController;
import battlecode.common.RobotInfo;
import battlecode.common.RobotType;

import java.util.Random;

public strictfp class RobotPlayer {

    /** N, NE, E, SE, S, SW, W, NW — the order `nextInt(8)` indexes. */
    static final Direction[] DIRECTIONS = new Direction[] {
        Direction.NORTH, Direction.NORTH_EAST, Direction.EAST,
        Direction.SOUTH_EAST, Direction.SOUTH, Direction.SOUTH_WEST,
        Direction.WEST, Direction.NORTH_WEST
    };

    public static void run(RobotController rc) {
        Random rng = new Random(2016);
        RobotType type = rc.getType();
        while (true) {
            try {
                if (type == RobotType.ARCHON) {
                    archon(rc, rng);
                } else if (type == RobotType.SOLDIER) {
                    soldier(rc, rng);
                }
                // SCOUT, GUARD, VIPER, TURRET and TTM: nothing at all.
            } catch (Exception e) {
                // A greenhorn never throws on purpose; swallowing keeps the
                // trace comparable when the engine refuses an action.
            }
            battlecode.common.Clock.yield();
        }
    }

    static void archon(RobotController rc, Random rng) throws Exception {
        if (rc.getTeamParts() >= RobotType.SOLDIER.partCost
                && rc.isCoreReady()) {
            Direction d = DIRECTIONS[rng.nextInt(8)];
            if (rc.canBuild(d, RobotType.SOLDIER)) {
                rc.build(d, RobotType.SOLDIER);
            }
        } else if (rc.isCoreReady()) {
            Direction d = DIRECTIONS[rng.nextInt(8)];
            if (rc.canMove(d)) {
                rc.move(d);
            }
        }
    }

    static void soldier(RobotController rc, Random rng) throws Exception {
        RobotInfo[] hostiles = rc.senseHostileRobots(rc.getLocation(),
            rc.getType().attackRadiusSquared);
        if (hostiles.length > 0 && rc.isWeaponReady()) {
            rc.attackLocation(hostiles[0].location);
        } else if (rc.isCoreReady()) {
            Direction d = DIRECTIONS[rng.nextInt(8)];
            if (rc.canMove(d)) {
                rc.move(d);
            }
        }
    }
}
