// The Tier A-prime SCENARIO BOT, Java side -- the line-for-line twin of
// `src/battlecode/years/bc24/chassis/scenario24.nim`.
//
// CI-TIME ONLY, compiled against the released battlecode24-3.0.5.jar by the
// `parity-oracle-bc24` job. It exists because Tier A's own measurement showed
// what Tier A cannot cover: `examplefuncsplayer24` leaves all three global
// upgrade points unspent on every map, never builds a stun or water trap, and
// on most maps never picks a flag up at all. Those are exactly the "rare code
// paths that fire mid-game" the Fleet card 1218171523823317 postmortem warns
// about.
//
// The bot is (a) DETERMINISTIC with no RNG at all, (b) CHEAP -- the job
// asserts it never exceeds 25 % of the bytecode limit, so it can never be cut
// off mid-turn -- and (c) SCRIPTED BY ROUND NUMBER to force every rare path
// early.
//
// It knows only what the RobotController tells it. In particular it can only
// see flags through `senseNearbyFlags` (r^2 <= 20) and
// `senseBroadcastFlagLocations`, which is exactly the information the Nim twin
// restricts itself to.
//
// THE TELEPORT VARIANT IS A SECOND PACKAGE, NOT A SYSTEM PROPERTY.
// `System.getProperty` returns null inside the instrumented sandbox -- the
// instrumenter stubs it -- so a `-D` flag silently leaves TELEPORT false and
// the Java side quietly plays a different script from the Nim side. That cost
// this run one local iteration and is why `tools/oracle/bc24/build_oracle.sh`
// generates `bc24scenariotel/RobotPlayer.java` from this file with two `sed`
// substitutions instead. The Nim twin uses `-d:bc24ScenarioTeleport`.
package bc24scenario;

import battlecode.common.*;

public strictfp class RobotPlayer {

    static final boolean TELEPORT = false;

    static final Direction[] DIRS = {
        Direction.NORTH, Direction.NORTHEAST, Direction.EAST,
        Direction.SOUTHEAST, Direction.SOUTH, Direction.SOUTHWEST,
        Direction.WEST, Direction.NORTHWEST,
    };

    static final int CLAIM_SLOT = 63;
    static final int CARRY_ROUND = 300;

    // Static fields are PER ROBOT under the instrumenter.
    static int myIndex = -1;
    static boolean claimed = false;
    static int trapStage = 0;
    static int digStage = 0;
    static boolean dropped = false;

    static void stepToward(RobotController rc, MapLocation target)
            throws GameActionException {
        Direction dir = rc.getLocation().directionTo(target);
        if (dir != Direction.CENTER && rc.canMove(dir)) {
            rc.move(dir);
            return;
        }
        for (Direction d : DIRS) {
            if (rc.canMove(d)) {
                rc.move(d);
                return;
            }
        }
    }

    static FlagInfo senseFlag(RobotController rc, boolean own)
            throws GameActionException {
        return senseFlag(rc, own, false);
    }

    static FlagInfo senseFlag(RobotController rc, boolean own,
                              boolean skipCarried) throws GameActionException {
        Team want = own ? rc.getTeam() : rc.getTeam().opponent();
        FlagInfo[] flags = rc.senseNearbyFlags(-1, want);
        for (FlagInfo f : flags) {
            if (skipCarried && f.isPickedUp()) continue;
            return f;
        }
        return null;
    }

    static void walkAtEnemyFlag(RobotController rc) throws GameActionException {
        FlagInfo seen = senseFlag(rc, false);
        if (seen != null) {
            stepToward(rc, seen.getLocation());
            return;
        }
        MapLocation[] bc = rc.senseBroadcastFlagLocations();
        if (bc.length > 0) stepToward(rc, bc[0]);
    }

    static RobotInfo lowestIdEnemyInRange(RobotController rc)
            throws GameActionException {
        RobotInfo[] bots = rc.senseNearbyRobots(
                GameConstants.ATTACK_RADIUS_SQUARED, rc.getTeam().opponent());
        RobotInfo best = null;
        for (RobotInfo b : bots) if (best == null || b.getID() < best.getID()) best = b;
        return best;
    }

    static RobotInfo lowestIdWoundedAlly(RobotController rc)
            throws GameActionException {
        RobotInfo[] bots = rc.senseNearbyRobots(
                GameConstants.HEAL_RADIUS_SQUARED, rc.getTeam());
        RobotInfo best = null;
        for (RobotInfo b : bots) {
            if (b.getID() == rc.getID()) continue;
            if (b.getHealth() >= GameConstants.DEFAULT_HEALTH) continue;
            if (best == null || b.getID() < best.getID()) best = b;
        }
        return best;
    }

    static MapLocation ownCentre(RobotController rc) throws GameActionException {
        return rc.getAllySpawnLocations()[0];
    }

    public static void run(RobotController rc) throws GameActionException {
        while (true) {
            try {
                turn(rc);
            } catch (Exception e) {
                // A scenario bot that throws is a scenario bot that proves
                // nothing; the trace comparison would show it immediately.
            } finally {
                Clock.yield();
            }
        }
    }

    static void turn(RobotController rc) throws GameActionException {
        if (!claimed) {
            claimed = true;
            myIndex = rc.readSharedArray(CLAIM_SLOT);
            if (rc.canWriteSharedArray(CLAIM_SLOT, myIndex + 1))
                rc.writeSharedArray(CLAIM_SLOT, myIndex + 1);
        }

        if (!rc.isSpawned()) {
            for (MapLocation l : rc.getAllySpawnLocations()) {
                if (rc.canSpawn(l)) {
                    rc.spawn(l);
                    return;
                }
            }
            return;
        }

        final int me = myIndex;

        // The first SPAWNED duck of the team to act buys the next upgrade in
        // a fixed order, the round the point lands.
        if (rc.canBuyGlobal(GlobalUpgrade.ATTACK)) rc.buyGlobal(GlobalUpgrade.ATTACK);
        else if (rc.canBuyGlobal(GlobalUpgrade.HEALING)) rc.buyGlobal(GlobalUpgrade.HEALING);
        else if (rc.canBuyGlobal(GlobalUpgrade.CAPTURING)) rc.buyGlobal(GlobalUpgrade.CAPTURING);

        switch (me) {
        case 0: {
            if (dropped) return;
            if (!rc.hasFlag()) {
                FlagInfo own = senseFlag(rc, true);
                if (own == null) {
                    stepToward(rc, ownCentre(rc));
                    return;
                }
                if (rc.canPickupFlag(own.getLocation())) {
                    rc.pickupFlag(own.getLocation());
                    return;
                }
                stepToward(rc, own.getLocation());
                return;
            }
            if (TELEPORT) {
                FlagInfo other = senseFlag(rc, true, true);
                if ((other != null
                        && rc.getLocation().distanceSquaredTo(other.getLocation()) <= 16)
                        || rc.getRoundNum() >= 180) {
                    if (rc.canDropFlag(rc.getLocation())) {
                        rc.dropFlag(rc.getLocation());
                        dropped = true;
                    }
                    return;
                }
                MapLocation[] far = rc.getAllySpawnLocations();
                if (far.length > 0) stepToward(rc, far[far.length - 1]);
            } else {
                if (rc.getRoundNum() >= 40) {
                    if (rc.canDropFlag(rc.getLocation())) {
                        rc.dropFlag(rc.getLocation());
                        dropped = true;
                    }
                    return;
                }
                stepToward(rc, ownCentre(rc));
            }
            return;
        }
        case 1: {
            TrapType[] stages = {TrapType.STUN, TrapType.WATER, TrapType.EXPLOSIVE};
            if (trapStage <= 2) {
                TrapType kind = stages[trapStage];
                for (Direction d : DIRS) {
                    MapLocation l = rc.getLocation().add(d);
                    if (!rc.onTheMap(l)) continue;
                    if (rc.canBuild(kind, l)) {
                        rc.build(kind, l);
                        trapStage += 1;
                        return;
                    }
                }
                if (rc.canBuild(kind, rc.getLocation())) {
                    rc.build(kind, rc.getLocation());
                    trapStage += 1;
                    return;
                }
            }
            return;
        }
        case 2: {
            if (digStage % 2 == 0) {
                for (Direction d : DIRS) {
                    MapLocation l = rc.getLocation().add(d);
                    if (!rc.onTheMap(l)) continue;
                    if (rc.canDig(l)) {
                        rc.dig(l);
                        digStage += 1;
                        return;
                    }
                }
            } else {
                for (Direction d : DIRS) {
                    MapLocation l = rc.getLocation().add(d);
                    if (!rc.onTheMap(l)) continue;
                    if (rc.canFill(l)) {
                        rc.fill(l);
                        digStage += 1;
                        return;
                    }
                }
            }
            return;
        }
        case 3: {
            RobotInfo victim = lowestIdEnemyInRange(rc);
            if (victim != null && rc.canAttack(victim.getLocation())) {
                rc.attack(victim.getLocation());
                return;
            }
            walkAtEnemyFlag(rc);
            return;
        }
        case 4: case 7: case 8: case 9: case 10: case 11: {
            RobotInfo patient = lowestIdWoundedAlly(rc);
            if (patient != null && rc.canHeal(patient.getLocation())) {
                rc.heal(patient.getLocation());
                return;
            }
            RobotInfo victim = lowestIdEnemyInRange(rc);
            if (victim != null && rc.canAttack(victim.getLocation())) {
                rc.attack(victim.getLocation());
                return;
            }
            walkAtEnemyFlag(rc);
            return;
        }
        case 5: case 12: case 13: case 14: case 15: case 16: {
            RobotInfo victim = lowestIdEnemyInRange(rc);
            if (victim != null && rc.canAttack(victim.getLocation())) {
                rc.attack(victim.getLocation());
                return;
            }
            walkAtEnemyFlag(rc);
            return;
        }
        case 6: {
            if (rc.getRoundNum() < CARRY_ROUND) return;
            if (rc.hasFlag()) {
                MapLocation home = rc.getLocation();
                int bestD = Integer.MAX_VALUE;
                for (MapLocation l : rc.getAllySpawnLocations()) {
                    int d = rc.getLocation().distanceSquaredTo(l);
                    if (d < bestD) {
                        bestD = d;
                        home = l;
                    }
                }
                stepToward(rc, home);
                return;
            }
            if (rc.canPickupFlag(rc.getLocation())) {
                rc.pickupFlag(rc.getLocation());
                return;
            }
            for (Direction d : DIRS) {
                MapLocation l = rc.getLocation().add(d);
                if (rc.onTheMap(l) && rc.canPickupFlag(l)) {
                    rc.pickupFlag(l);
                    return;
                }
            }
            walkAtEnemyFlag(rc);
            return;
        }
        default:
            // Hold station: the game reaches round 2000 and the tiebreak
            // ladder decides it, which is the point.
            return;
        }
    }
}
