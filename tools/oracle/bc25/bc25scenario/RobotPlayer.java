// The Tier A-prime SCENARIO BOT: deterministic, RNG-free, and scripted by
// round number to force every rare path early.
//
// CI-TIME ONLY. This file is compiled and run by the `parity-oracle-bc25` job
// against the released jar; there is no JDK in any runtime image stage.
//
// IT IS WRITTEN LINE FOR LINE AGAINST
// `src/battlecode/years/bc25/chassis/scenario25.nim`. Read them side by side.
// Three properties, each of which the parity job asserts:
//
//   (a) NO RNG AT ALL. Every decision is a function of the round number, the
//       unit's type and its id. There is no draw to desynchronise.
//   (b) CHEAP. The job asserts it never exceeds 25 % of its bytecode limit,
//       so it can never be cut off mid-turn and the port's "no mid-turn
//       resumption" divergence is never exercised.
//   (c) SCRIPTED TO FORCE THE RARE PATHS: all three tower families and both
//       upgrade steps, all three robot types, the SRP lifecycle, splashes
//       over enemy paint and over towers, mop swings in all four cardinals, a
//       robot driven to exactly 0 paint, tower-to-tower broadcast across an
//       unpainted gap, and disintegration.
//
// The two variants `bc25scenariopaint` and `bc25scenariowipe` are produced by
// `build_oracle.sh` with a two-line `sed` on the constants below, exactly as
// bc24's teleport variant is.
package bc25scenario;

import battlecode.common.*;

public class RobotPlayer {

    static final boolean PAINT = false;
    static final boolean WIPE = false;

    static final Direction[] CARDINALS = {
        Direction.NORTH, Direction.SOUTH, Direction.EAST, Direction.WEST
    };
    static final Direction[] ALL = {
        Direction.NORTH, Direction.NORTHEAST, Direction.EAST,
        Direction.SOUTHEAST, Direction.SOUTH, Direction.SOUTHWEST,
        Direction.WEST, Direction.NORTHWEST
    };

    /** Rotate the three families so all three are built. */
    static UnitType towerKind(int index) {
        switch (index % 3) {
            case 0: return UnitType.LEVEL_ONE_MONEY_TOWER;
            case 1: return UnitType.LEVEL_ONE_PAINT_TOWER;
            default: return UnitType.LEVEL_ONE_DEFENSE_TOWER;
        }
    }

    static MapLocation firstEnemy(RobotController rc, int r2)
            throws GameActionException {
        for (MapLocation l : rc.getAllLocationsWithinRadiusSquared(
                rc.getLocation(), r2)) {
            if (!rc.canSenseLocation(l)) continue;
            RobotInfo bot = rc.senseRobotAtLocation(l);
            if (bot != null && bot.getTeam() != rc.getTeam()) return l;
        }
        return null;
    }

    public static void run(RobotController rc) throws GameActionException {
        while (true) {
            try {
                if (rc.getType().isTowerType()) tower(rc);
                else if (rc.getType() == UnitType.SOLDIER) soldier(rc);
                else if (rc.getType() == UnitType.MOPPER) mopper(rc);
                else splasher(rc);
            } catch (GameActionException ignored) {
            } catch (Exception ignored) {
            } finally {
                Clock.yield();
            }
        }
    }

    static void tower(RobotController rc) throws GameActionException {
        MapLocation single = firstEnemy(rc, rc.getType().actionRadiusSquared);
        if (single != null && rc.canAttack(single)) rc.attack(single);
        if (single != null && rc.canAttack(null)) rc.attack(null);

        // The build schedule forces all three robot types early and then
        // keeps a trickle of soldiers going, because SOLDIERS ARE WHAT PAINT
        // PATTERNS and a scenario bot that spent its towers' paint on moppers
        // would never raise a tower and would prove nothing.
        int round = rc.getRoundNum();
        UnitType want = UnitType.SOLDIER;
        if (round == 4) want = UnitType.MOPPER;
        else if (round == 8) want = UnitType.SPLASHER;
        else if (round % 41 == 0) want = UnitType.MOPPER;
        else if (round % 53 == 0) want = UnitType.SPLASHER;

        // THE TOWER RESERVE: never spend the chips a `completeTowerPattern`
        // needs. Without it the towers buy robots with the 1000 and the tower
        // path never fires.
        if (rc.getMoney() - want.moneyCost
                >= UnitType.LEVEL_ONE_MONEY_TOWER.moneyCost) {
            for (MapLocation l : rc.getAllLocationsWithinRadiusSquared(
                    rc.getLocation(), GameConstants.BUILD_ROBOT_RADIUS_SQUARED)) {
                if (rc.canBuildRobot(want, l)) {
                    rc.buildRobot(want, l);
                    break;
                }
            }
        }

        // Tower->tower broadcast across an unpainted gap: no connectivity
        // needed, and it fires from round 5 so the comms path is compared
        // early.
        if (round >= 5 && round % 11 == 0 && rc.canBroadcastMessage()) {
            rc.broadcastMessage(round);
        }
    }

    static void soldier(RobotController rc) throws GameActionException {
        MapLocation ruin = null;
        int ruinIndex = 0;
        for (MapLocation l : rc.getAllLocationsWithinRadiusSquared(
                rc.getLocation(), GameConstants.VISION_RADIUS_SQUARED)) {
            if (!rc.canSenseLocation(l)) continue;
            MapInfo tile = rc.senseMapInfo(l);
            if (!tile.hasRuin()) continue;
            if (rc.canSenseRobotAtLocation(l)
                    && rc.senseRobotAtLocation(l) != null) continue;
            if (ruin == null) {
                ruin = l;
                ruinIndex = index(rc, l);
            }
        }

        // Upgrading is free of cooldown and paint, so it never competes with
        // the turn's action -- which is what makes the LEVEL_TWO and
        // LEVEL_THREE paths reachable this early.
        for (MapLocation l : rc.getAllLocationsWithinRadiusSquared(
                rc.getLocation(), GameConstants.BUILD_TOWER_RADIUS_SQUARED)) {
            if (rc.canUpgradeTower(l)) {
                rc.upgradeTower(l);
                break;
            }
        }

        if (ruin != null) {
            UnitType kind = towerKind(ruinIndex);
            if (rc.getLocation().distanceSquaredTo(ruin)
                    > GameConstants.BUILD_TOWER_RADIUS_SQUARED) {
                Direction dir = rc.getLocation().directionTo(ruin);
                if (rc.canMove(dir)) rc.move(dir);
            }
            if (rc.canMarkTowerPattern(kind, ruin)
                    && marker(rc, ruin.translate(1, 0)) == PaintType.EMPTY) {
                rc.markTowerPattern(kind, ruin);
            }
            for (MapLocation l : rc.getAllLocationsWithinRadiusSquared(
                    ruin, GameConstants.BUILD_TOWER_RADIUS_SQUARED * 4)) {
                PaintType mark = marker(rc, l);
                if (mark == PaintType.EMPTY) continue;
                boolean secondary = mark == PaintType.ALLY_SECONDARY;
                if (rc.senseMapInfo(l).getPaint() == mark) continue;
                if (rc.canAttack(l)) {
                    rc.attack(l, secondary);
                    break;
                }
            }
            if (rc.canCompleteTowerPattern(kind, ruin)) {
                rc.completeTowerPattern(kind, ruin);
            }
        }

        // The SRP lifecycle: mark, fill and complete a resource pattern
        // centred on the soldier's own tile whenever it is a valid centre.
        MapLocation here = rc.getLocation();
        if (rc.canCompleteResourcePattern(here)) {
            rc.completeResourcePattern(here);
        } else if (rc.canMarkResourcePattern(here)
                && marker(rc, here) == PaintType.EMPTY) {
            rc.markResourcePattern(here);
        } else {
            for (int dx = -2; dx <= 2; dx++) {
                for (int dy = -2; dy <= 2; dy++) {
                    MapLocation l = here.translate(dx, dy);
                    if (!rc.onTheMap(l) || !rc.canSenseLocation(l)) continue;
                    PaintType mark = marker(rc, l);
                    if (mark == PaintType.EMPTY) continue;
                    if (rc.senseMapInfo(l).getPaint() == mark) continue;
                    if (rc.canAttack(l)) {
                        rc.attack(l, mark == PaintType.ALLY_SECONDARY);
                        return;
                    }
                }
            }
        }

        if (WIPE) {
            MapLocation enemy = firstEnemy(rc, UnitType.SOLDIER.actionRadiusSquared);
            if (enemy != null && rc.canAttack(enemy)) {
                rc.attack(enemy);
                return;
            }
        }

        // One robot in ten never paints and therefore starves at exactly 0
        // paint, losing 20 HP a turn until it dies -- the `pnt=0` / falling
        // `hp` record the parity job looks for.
        if (rc.getID() % 10 == 3) return;

        if (!rc.senseMapInfo(here).getPaint().isAlly() && rc.canAttack(here)) {
            rc.attack(here);
            return;
        }

        if (PAINT) {
            for (MapLocation l : rc.getAllLocationsWithinRadiusSquared(
                    rc.getLocation(), UnitType.SOLDIER.actionRadiusSquared)) {
                if (!rc.canSenseLocation(l)) continue;
                MapInfo tile = rc.senseMapInfo(l);
                if (!tile.isPassable()) continue;
                if (tile.getPaint().isAlly()) continue;
                if (tile.getPaint().isEnemy()) continue;
                if (rc.canAttack(l)) {
                    rc.attack(l);
                    return;
                }
            }
        }

        // A SOLDIER WITH A RUIN TO WORK DOES NOT WANDER. It has to stay
        // beside the pattern for the twenty-five turns it takes to paint it.
        if (ruin == null) {
            Direction dir = ALL[rc.getRoundNum() % 8];
            if (rc.canMove(dir)) rc.move(dir);
        }
    }

    static void mopper(RobotController rc) throws GameActionException {
        if (rc.getRoundNum() == 40 && rc.getID() % 10 == 7) {
            rc.disintegrate();
            return;
        }
        Direction dir = CARDINALS[rc.getRoundNum() % 4];
        if (rc.canMopSwing(dir)) {
            rc.mopSwing(dir);
        } else {
            MapLocation ahead = rc.getLocation().add(dir);
            if (rc.onTheMap(ahead) && rc.canAttack(ahead)) rc.attack(ahead);
        }
        if (rc.canMove(dir)) rc.move(dir);
    }

    static void splasher(RobotController rc) throws GameActionException {
        for (MapLocation l : rc.getAllLocationsWithinRadiusSquared(
                rc.getLocation(), UnitType.SPLASHER.actionRadiusSquared)) {
            if (!rc.canSenseLocation(l)) continue;
            RobotInfo bot = rc.senseRobotAtLocation(l);
            MapInfo tile = rc.senseMapInfo(l);
            boolean interesting =
                (bot != null && bot.getType().isTowerType()
                    && bot.getTeam() != rc.getTeam())
                || tile.getPaint().isEnemy();
            if (!interesting) continue;
            if (rc.canAttack(l)) {
                rc.attack(l);
                return;
            }
        }
        Direction dir = ALL[rc.getRoundNum() % 8];
        if (rc.canMove(dir)) rc.move(dir);
    }

    static PaintType marker(RobotController rc, MapLocation l)
            throws GameActionException {
        if (!rc.onTheMap(l) || !rc.canSenseLocation(l)) return PaintType.EMPTY;
        return rc.senseMapInfo(l).getMark();
    }

    static int index(RobotController rc, MapLocation l) {
        return l.x + l.y * rc.getMapWidth();
    }
}
