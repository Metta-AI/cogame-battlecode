// The Tier A-prime SCENARIO BOT: deterministic, RNG-free, and scripted by
// round number to force every rare path early.
//
// CI-TIME ONLY. This file is compiled and run by the `parity-oracle-bc23` job
// against the released `battlecode23-3.0.15.jar`; there is no JDK, no JRE and
// no Java in any runtime image stage.
//
// IT IS WRITTEN LINE FOR LINE AGAINST
// `src/battlecode/years/bc23/chassis/scenario23.nim`. Read them side by side.
// Three properties, each of which the parity job asserts:
//
//   (a) NO RNG AT ALL. Every decision is a function of the round number, the
//       robot's type and the engine's own scan order. There is no draw to
//       desynchronise.
//   (b) CHEAP. The job asserts it never exceeds 50 % of its bytecode limit,
//       so it can never be cut off mid-turn and the port's "no mid-turn
//       resumption" divergence is never exercised.
//   (c) SCRIPTED TO FORCE THE RARE PATHS that Tier A's example bot never
//       reaches: building an anchor of BOTH kinds, taking one from a
//       headquarters, ferrying it, planting it, capturing and losing
//       islands, `CONQUEST` and the sky-island ladder rungs, transferring a
//       resource to a headquarters AND into a well (the elixir
//       transformation and the rate upgrade), amplifiers, destabilizers,
//       boosters, the tempo lattice, both comms write windows, the carrier
//       throw and disintegration.
//
// EVERY QUERY IS ROBOT-LOCAL, and that is the whole reason this file can
// exist. A sandboxed robot has a `RobotController`, not a `GameWorld`: it
// cannot ask for island 0's first tile, for its team's total anchor stock, or
// for the map's well list. So every scan goes through
// `getAllLocationsWithinRadiusSquared`, which clamps the radius to the type's
// vision radius, walks the engine's own x-outer/y-inner order and filters by
// `canSenseLocation` -- hence the cloud collapse. `scenario23.nim`'s
// `visible` iterator is that method, ported.
package bc23scenario;

import battlecode.common.*;

public class RobotPlayer {

    static final ResourceType[] REAL = {
        ResourceType.ADAMANTIUM, ResourceType.MANA, ResourceType.ELIXIR
    };

    public static void run(RobotController rc) throws GameActionException {
        while (true) {
            try {
                switch (rc.getType()) {
                    case HEADQUARTERS: headquarters(rc); break;
                    case CARRIER: carrier(rc); break;
                    case LAUNCHER: launcher(rc); break;
                    case DESTABILIZER: destabilizer(rc); break;
                    case BOOSTER: booster(rc); break;
                    default: amplifier(rc); break;
                }
            } catch (GameActionException ignored) {
            } catch (Exception ignored) {
            } finally {
                Clock.yield();
            }
        }
    }

    // ---- the local scans, each one a proc in scenario23.nim ---------------

    static MapLocation[] visible(RobotController rc, int r2)
            throws GameActionException {
        return rc.getAllLocationsWithinRadiusSquared(rc.getLocation(), r2);
    }

    static MapLocation firstBuildTile(RobotController rc)
            throws GameActionException {
        for (MapLocation l : visible(rc,
                GameConstants.DISTANCE_SQUARED_FROM_HEADQUARTER)) {
            if (!rc.isLocationOccupied(l) && rc.sensePassability(l)) return l;
        }
        return null;
    }

    static MapLocation firstIslandTile(RobotController rc)
            throws GameActionException {
        for (MapLocation l : visible(rc, rc.getType().visionRadiusSquared)) {
            if (rc.senseIsland(l) >= 0) return l;
        }
        return null;
    }

    static MapLocation firstFriendlyHeadquarters(RobotController rc,
            boolean withAnchor) throws GameActionException {
        for (MapLocation l : visible(rc, rc.getType().visionRadiusSquared)) {
            RobotInfo other = rc.senseRobotAtLocation(l);
            if (other == null || other.getTeam() != rc.getTeam()) continue;
            if (other.getType() != RobotType.HEADQUARTERS) continue;
            if (withAnchor && other.getTotalAnchors() == 0) continue;
            return l;
        }
        return null;
    }

    static MapLocation firstWell(RobotController rc)
            throws GameActionException {
        for (MapLocation l : visible(rc, rc.getType().visionRadiusSquared)) {
            if (rc.senseWell(l) != null) return l;
        }
        return null;
    }

    /**
     * Where a full carrier walks: the first visible well whose CURRENT kind
     * is not one we are carrying -- the only kind of well a transfer can
     * transform -- and otherwise the first friendly headquarters we can see.
     *
     * ONE SCAN FOR BOTH. They are independent "first in scan order" queries,
     * so folding them together changes no answer; it changes the bytecode
     * bill, and the carrier is the type this bot peaks on (44 % of its
     * 12 500 with two scans against the job's 50 % headroom bound).
     */
    static MapLocation walkTarget(RobotController rc, boolean wantWell)
            throws GameActionException {
        MapLocation well = null;
        MapLocation hq = null;
        for (MapLocation l : visible(rc, rc.getType().visionRadiusSquared)) {
            if (wantWell && well == null) {
                WellInfo info = rc.senseWell(l);
                if (info != null) {
                    ResourceType kindHere = info.getResourceType();
                    for (ResourceType t : REAL) {
                        if (t != kindHere && rc.getResourceAmount(t) > 0) {
                            well = l;
                            break;
                        }
                    }
                }
            }
            if (hq == null) {
                RobotInfo other = rc.senseRobotAtLocation(l);
                if (other != null && other.getTeam() == rc.getTeam()
                        && other.getType() == RobotType.HEADQUARTERS) {
                    hq = l;
                }
            }
            if (hq != null && (well != null || !wantWell)) break;
        }
        return well != null ? well : hq;
    }

    static MapLocation firstEnemyTarget(RobotController rc)
            throws GameActionException {
        for (MapLocation l : visible(rc, rc.getType().actionRadiusSquared)) {
            RobotInfo other = rc.senseRobotAtLocation(l);
            if (other != null && other.getTeam() != rc.getTeam()
                    && other.getType() != RobotType.HEADQUARTERS
                    && rc.canAttack(l)) {
                return l;
            }
        }
        return null;
    }

    /** `directionTo`, then the eight rotations in a fixed order. */
    static void stepToward(RobotController rc, MapLocation target)
            throws GameActionException {
        if (!rc.isMovementReady()) return;
        if (target == null) return;
        Direction d = rc.getLocation().directionTo(target);
        for (int k = 0; k < 8; k++) {
            if (rc.canMove(d)) {
                rc.move(d);
                return;
            }
            d = d.rotateRight();
        }
    }

    static int totalAnchors(RobotController rc) {
        return rc.getNumAnchors(Anchor.STANDARD)
             + rc.getNumAnchors(Anchor.ACCELERATING);
    }

    /** `InternalRobot.getTypeAnchor`: STANDARD first, then ACCELERATING. */
    static Anchor typeAnchor(RobotInfo hq) {
        if (hq.getNumAnchors(Anchor.STANDARD) > 0) return Anchor.STANDARD;
        if (hq.getNumAnchors(Anchor.ACCELERATING) > 0) {
            return Anchor.ACCELERATING;
        }
        return null;
    }

    static int weight(RobotController rc) {
        return totalAnchors(rc) * GameConstants.ANCHOR_WEIGHT
             + rc.getResourceAmount(ResourceType.ADAMANTIUM)
             + rc.getResourceAmount(ResourceType.MANA)
             + rc.getResourceAmount(ResourceType.ELIXIR);
    }

    // ---- the five controllers --------------------------------------------

    static void headquarters(RobotController rc) throws GameActionException {
        int round = rc.getRoundNum();
        MapLocation l;
        if (round == 2 || round % 40 == 0) {
            l = firstBuildTile(rc);
            if (l != null && rc.canBuildRobot(RobotType.CARRIER, l)) {
                rc.buildRobot(RobotType.CARRIER, l);
            }
        }
        if (round == 3 || round % 41 == 0) {
            l = firstBuildTile(rc);
            if (l != null && rc.canBuildRobot(RobotType.LAUNCHER, l)) {
                rc.buildRobot(RobotType.LAUNCHER, l);
            }
        }
        if (round == 4) {
            l = firstBuildTile(rc);
            if (l != null && rc.canBuildRobot(RobotType.AMPLIFIER, l)) {
                rc.buildRobot(RobotType.AMPLIFIER, l);
            }
        }
        // SIX BUILDS ATTEMPTED IN ONE TURN, forced once: a headquarters has
        // no action cooldown, so what stops this is the resource check and
        // the free-tile scan, not the clock.
        if (round == 30) {
            for (int k = 0; k < 6; k++) {
                l = firstBuildTile(rc);
                if (l == null) break;
                if (!rc.canBuildRobot(RobotType.CARRIER, l)) break;
                rc.buildRobot(RobotType.CARRIER, l);
            }
        }
        // THIS headquarters' own stock, not the team's.
        if (round >= 6 && totalAnchors(rc) == 0
                && rc.canBuildAnchor(Anchor.STANDARD)) {
            rc.buildAnchor(Anchor.STANDARD);
        }
        if (rc.canBuildAnchor(Anchor.ACCELERATING)) {
            rc.buildAnchor(Anchor.ACCELERATING);
        }
        if (rc.getResourceAmount(ResourceType.ELIXIR)
                >= RobotType.DESTABILIZER.buildCostElixir && round % 50 == 0) {
            l = firstBuildTile(rc);
            if (l != null && rc.canBuildRobot(RobotType.DESTABILIZER, l)) {
                rc.buildRobot(RobotType.DESTABILIZER, l);
            }
        }
        if (rc.getResourceAmount(ResourceType.ELIXIR)
                >= RobotType.BOOSTER.buildCostElixir && round % 51 == 0) {
            l = firstBuildTile(rc);
            if (l != null && rc.canBuildRobot(RobotType.BOOSTER, l)) {
                rc.buildRobot(RobotType.BOOSTER, l);
            }
        }
        // A headquarters may always write.
        if (rc.canWriteSharedArray(round % 64, round % 65536)) {
            rc.writeSharedArray(round % 64, round % 65536);
        }
    }

    static void carrier(RobotController rc) throws GameActionException {
        int round = rc.getRoundNum();
        // Holding an anchor: plant it where we stand, or ferry it to the
        // first island tile we can see.
        if (totalAnchors(rc) > 0) {
            boolean placed = false;
            if (rc.senseIsland(rc.getLocation()) >= 0 && rc.canPlaceAnchor()) {
                rc.placeAnchor();
                placed = true;
            }
            if (!placed) stepToward(rc, firstIslandTile(rc));
            return;
        }
        // Empty, and a headquarters we can see holds an anchor: take it.
        if (weight(rc) == 0) {
            MapLocation hq = firstFriendlyHeadquarters(rc, true);
            if (hq != null) {
                if (rc.getLocation().isAdjacentTo(hq)) {
                    Anchor kind = typeAnchor(rc.senseRobotAtLocation(hq));
                    if (kind != null && rc.canTakeAnchor(hq, kind)) {
                        rc.takeAnchor(hq, kind);
                    }
                } else {
                    stepToward(rc, hq);
                }
                return;
            }
        }
        // Full. THE WELL CLAUSES ARE THE ELIXIR PROGRAMME AND THE ONLY WAY
        // TO REACH IT. `Well.addAdamantium` flips a MANA well to ELIXIR at
        // 600 adamantium and `Well.addMana` flips an ADAMANTIUM well at 600
        // mana, while 1400 of a well's OWN kind trips its rate upgrade
        // instead -- so the two paths need opposite transfers and the script
        // forces both:
        //
        //   * carrying elixir -> straight home, because a headquarters
        //     cannot buy a destabilizer or a booster out of a well;
        //   * beside a well of the other kind -> pour (the transformation);
        //   * beside a well of our own kind, every third round -> pour (the
        //     rate upgrade);
        //   * beside a friendly headquarters -> deposit;
        //   * otherwise walk to the nearest well of the other kind, then
        //     home.
        int weight = weight(rc);
        if (weight >= GameConstants.CARRIER_CAPACITY
                || (weight > 0 && round % 7 == 0)) {
            boolean carryingElixir =
                rc.getResourceAmount(ResourceType.ELIXIR) > 0;
            // THE 3x3, not `visible(actionRadiusSquared)` filtered by
            // `isAdjacentTo`: `getAllLocationsWithinRadiusSquared` is x
            // ascending outer, y ascending inner, so restricting it to
            // |dx| <= 1 and |dy| <= 1 IS this loop, in this order, and the
            // twenty-nine-tile scan cost the carrier a fifth of its bytecode
            // limit for eight useful tiles. Adjacent tiles are always
            // sensible: r^2 <= 2 is inside the cloud collapse's radius of 4.
            for (int ddx = -1; ddx <= 1; ddx++) {
              for (int ddy = -1; ddy <= 1; ddy++) {
                MapLocation l = rc.getLocation().translate(ddx, ddy);
                if (!rc.onTheMap(l)) continue;
                if (round >= 200 && !carryingElixir) {
                    WellInfo well = rc.senseWell(l);
                    if (well != null) {
                        ResourceType kindHere = well.getResourceType();
                        for (ResourceType t : REAL) {
                            int held = rc.getResourceAmount(t);
                            if (held == 0) continue;
                            if (t != kindHere || round % 3 == 0) {
                                if (rc.canTransferResource(l, t, held)) {
                                    rc.transferResource(l, t, held);
                                    return;
                                }
                            }
                        }
                    }
                }
                RobotInfo other = rc.senseRobotAtLocation(l);
                if (other != null
                        && other.getType() == RobotType.HEADQUARTERS
                        && other.getTeam() == rc.getTeam()) {
                    for (ResourceType t : REAL) {
                        int held = rc.getResourceAmount(t);
                        if (held > 0 && rc.canTransferResource(l, t, held)) {
                            rc.transferResource(l, t, held);
                            return;
                        }
                    }
                }
              }
            }
            // Nobody beside us: throw at the first enemy in range on a fixed
            // cadence.
            if (round % 13 == 0) {
                MapLocation target = firstEnemyTarget(rc);
                if (target != null) {
                    rc.attack(target);
                    return;
                }
            }
            // Then a well of the other kind if one is in sight, else home.
            stepToward(rc, walkTarget(rc, round >= 200 && !carryingElixir));
            return;
        }
        // Otherwise mine the first collectable well tile in the 3x3.
        for (int ddx = -1; ddx <= 1; ddx++) {
            for (int ddy = -1; ddy <= 1; ddy++) {
                MapLocation l = rc.getLocation().translate(ddx, ddy);
                if (rc.onTheMap(l) && rc.canCollectResource(l, -1)) {
                    rc.collectResource(l, -1);
                    return;
                }
            }
        }
        // Nothing to mine: walk to the first well we can see.
        stepToward(rc, firstWell(rc));
    }

    static void launcher(RobotController rc) throws GameActionException {
        MapLocation target = firstEnemyTarget(rc);
        if (target != null) rc.attack(target);
        stepToward(rc, firstIslandTile(rc));
    }

    static void destabilizer(RobotController rc) throws GameActionException {
        if (rc.canDestabilize(rc.getLocation())) {
            rc.destabilize(rc.getLocation());
        } else {
            stepToward(rc, firstIslandTile(rc));
        }
    }

    static void booster(RobotController rc) throws GameActionException {
        if (rc.canBoost()) {
            rc.boost();
        } else {
            stepToward(rc, firstIslandTile(rc));
        }
    }

    static void amplifier(RobotController rc) throws GameActionException {
        // The write-window probe: an amplifier may always write, and every
        // robot near it may too.
        if (rc.canWriteSharedArray(63, rc.getRoundNum() % 65536)) {
            rc.writeSharedArray(63, rc.getRoundNum() % 65536);
        }
        if (rc.getRoundNum() == 500) {
            // Exercise the disintegrate path exactly once.
            rc.disintegrate();
            return;
        }
        stepToward(rc, firstIslandTile(rc));
    }
}
