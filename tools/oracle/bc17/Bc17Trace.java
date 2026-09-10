// The bc17 parity oracle's Java side: run the PUBLISHED 2017 engine headlessly
// and print one line per record FROM THE LIVE OBJECTS.
//
// CI-TIME ONLY. There is no JDK, no JRE and no Java in ANY runtime image
// stage; this file is compiled and run by the `parity-oracle-bc17` job of
// .github/workflows/ci.yml against the released `battlecode-2017.1.6.2.jar`
// (URL, sha256, byte size and SPEC_VERSION pinned in
// tools/oracle/bc17/jar.lock) plus the four engine sources the two committed
// engine patches touch.
//
// It is `package battlecode.world;` so it needs reflection only for
// `ObjectInfo`'s private `gameRobotsByID` / `gameTreesByID` /
// `gameBulletsByID` / `dynamicBodyExecOrder`, `GameWorld`'s private
// `currentBroadcasters`, `IDGenerator`'s private `reservedIDs` / `cursor` and
// `GameMaker.MatchMaker`'s private action log -- the only ways to print in
// trove order, in exec order, to read the two id streams and to recover what
// each robot DID on its turn.
//
// SIX THINGS THAT WERE MEASURED AND WOULD OTHERWISE EACH COST A CI ROUND:
//
//   * TEMURIN 8, AND IT IS NOT NEGOTIABLE. The jar bundles a 2017-era
//     ASM 5.0.4 and the whole instrumenter is built for Java 8 class files.
//     Under a modern JDK the instrumenter throws
//     `java.lang.IllegalArgumentException` inside
//     `org.objectweb.asm.ClassReader.<init>` on EVERY player class load, no
//     robot is ever built, the game ends in one round AND THE JOB EXITS 0.
//     This driver therefore EXITS 3 IF NOTHING EVER HAPPENED.
//   * `javac` WITH NO `--release`, NO `-source`, NO `-target`. `--release`
//     arrived in JDK 9 and dies with "invalid flag" on a JDK-8 javac in
//     seconds (the bc21 lesson). The compiler IS 8, so the target is 8.
//   * THE DRIVER MUST CALL `System.exit()`. The sandboxed player threads are
//     NON-DAEMON: a driver that returns or throws without it hangs for ever.
//     Every `java` invocation in the job is also wrapped in `timeout 900`.
//   * **NO `NullControlProvider` REGISTRATION IS NEEDED, UNLIKE 2016.** 2017
//     has no neutral ROBOTS -- only neutral trees -- so `Team.NEUTRAL` never
//     reaches `runRobot`. The driver ASSERTS that: a neutral robot spawning
//     is a hard failure rather than a silent surprise.
//   * `GameMapIO.loadMap(name, null)` is the RESOURCE FALLBACK path
//     (`GameMapIO.java:56-64`) -- the jar carries all 70 `.map17` resources
//     and every pool map is one of them, so this job needs NO `--map-dir`.
//   * `GameWorld` needs a real `GameMaker.MatchMaker`, so the driver builds a
//     real `GameInfo` and a real `GameMaker(gameInfo, null)` and calls
//     `makeGameHeader()`. NO FLATBUFFER FILE IS WRITTEN and no `.bc17` bytes
//     are produced on either side: `writeGame` is never called.
//
// THE ONE IMPORTANT DEPARTURE FROM EVERY SIBLING YEAR: **every float in this
// trace is printed as its RAW IEEE-754 BITS in hex, never as a decimal.** A
// float32 needs nine significant decimal digits to round-trip and a formatter
// mismatch between Java's `%.9g` and Nim's `formatFloat` would masquerade as
// a divergence for a week; bc16 solved that with a `%.6f` convention plus a
// per-field float allowlist in the comparator, and bc17 removes the problem
// instead of managing it. **The consequence is that `parity_tiers_bc17.py`
// needs NO float allowlist at all.**
//
//   R <round> T <A|B> bul=<hex8> vp=<n> ar=<n> ga=<n> lj=<n> so=<n> ta=<n>
//             sc=<n> tr=<n> trm=<n>
//   R <round> U <id> team=<A|B> ty=<TYPE> x=<hex8> y=<hex8> hp=<hex8> ra=<n>
//             ac=<n> mc=<n> wc=<n> shc=<n> cd=<n> bc=<n>
//   R <round> E <id> team=<A|B|N> x=<hex8> y=<hex8> r=<hex8> hp=<hex8>
//             mhp=<hex8> cb=<n> crob=<TYPE|-> ra=<n>
//   R <round> B <id> team=<A|B> x=<hex8> y=<hex8> dir=<hex8> sp=<hex8>
//             dmg=<hex8> ra=<n>
//   R <round> A <id> act=<NAME> tgt=<n> x=<hex8> y=<hex8> arg=<hex8>
//   R <round> G exec=<fnv1a64> execlen=<n> ubod=<fnv1a64> tbod=<fnv1a64>
//             bbod=<fnv1a64> nb=<n> rid=<n> bid=<n> broad=<fnv1a64>
//   R <round> W winner=<A|B|-> dom=<NAME|->
//
// **ROBOTS AND BULLETS ARE PRINTED IN EXEC ORDER AND TREES IN TROVE ORDER**,
// which is what makes an ordering bug visible on the round it happens; the
// **`G` line is bc17's own addition and it is the most valuable line in the
// trace** -- it carries the exec-order fold, the three body folds, the two id
// streams and the broadcaster array's fold, so a trove bug (D1) or an
// id-stream bug (D3) surfaces immediately instead of as a mystery 400 rounds
// later.
//
// **HOW THE `A` LINE IS RECOVERED, AND WHY IT IS A PRIORITY AND NOT A
// SEQUENCE.** The engine has no "last action" concept: it has
// `MatchMaker.addAction`, which records FIRE / FIRE_TRIAD / FIRE_PENTAD /
// CHOP / SHAKE_TREE / PLANT_TREE / WATER_TREE / SPAWN_UNIT /
// LUMBERJACK_STRIKE / DIE_* with a target id, and it records a MOVE, a
// BROADCAST and a DONATE NOWHERE AT ALL. Those three are recovered here from
// the robot's own `getMoveCount()`, from `GameWorld.currentBroadcasters` and
// from the team's victory-point delta across the turn, and a TANK's body
// attack from the health of the trees around it before and after the turn --
// but their ORDER relative to the logged actions is not recoverable from two
// separate lists. So BOTH sides reduce a turn to ONE action by the SAME FIXED
// PRIORITY (highest first):
//
//     DISINTEGRATE > FIRE_*/STRIKE/CHOP > BODY_ATTACK > PLANT/HIRE/BUILD
//                  > WATER > SHAKE > DONATE > MOVE > BROADCAST > NOTHING
//
// and `src/battlecode/years/bc17/actions.nim`'s `noteAction` keeps exactly
// the same maximum. Within a group the members are mutually exclusive in one
// turn (one attack, one build-class action, one water, one shake), so the
// rule is total. `tgt` is the engine's own target where the engine has one
// (SHAKE/WATER/PLANT the tree, SPAWN_UNIT the new robot) and the victory
// points gained for a DONATE; it is ZERO everywhere else, including for a
// BROADCAST's channel, because the engine does not record one and a field
// invented on one side only is exactly the bc23 mistake. `x` and `y` are the
// robot's location WHEN THE LINE IS PRINTED, which both emitters can produce
// without knowing when in the turn the action happened, and `arg` is
// reserved and printed as zero on both sides for the same reason.
package battlecode.world;

import battlecode.common.*;
import battlecode.schema.Action;
import battlecode.server.GameInfo;
import battlecode.server.GameMaker;
import battlecode.server.GameState;
import battlecode.world.control.PlayerControlProvider;
import battlecode.world.control.RobotControlProvider;
import battlecode.world.control.TeamControlProvider;

import gnu.trove.list.array.TByteArrayList;
import gnu.trove.list.array.TIntArrayList;
import gnu.trove.map.hash.TIntObjectHashMap;
import gnu.trove.procedure.TObjectProcedure;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.OutputStream;
import java.io.PrintStream;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final strictfp class Bc17Trace {

    // ---- the action vocabulary, ordinals shared with the Nim side --------
    static final int ACT_NOTHING = 0;
    static final int ACT_MOVE = 1;
    static final int ACT_FIRE_SINGLE = 2;
    static final int ACT_FIRE_TRIAD = 3;
    static final int ACT_FIRE_PENTAD = 4;
    static final int ACT_STRIKE = 5;
    static final int ACT_CHOP = 6;
    static final int ACT_SHAKE = 7;
    static final int ACT_WATER = 8;
    static final int ACT_PLANT = 9;
    static final int ACT_HIRE = 10;
    static final int ACT_BUILD = 11;
    static final int ACT_BROADCAST = 12;
    static final int ACT_DONATE = 13;
    static final int ACT_DISINTEGRATE = 14;
    static final int ACT_BODY_ATTACK = 15;

    static final String[] ACT_NAMES = {
        "NOTHING", "MOVE", "FIRE_SINGLE", "FIRE_TRIAD", "FIRE_PENTAD",
        "STRIKE", "CHOP", "SHAKE", "WATER", "PLANT", "HIRE", "BUILD",
        "BROADCAST", "DONATE", "DISINTEGRATE", "BODY_ATTACK"
    };

    /** The priority of the header's table, by action ordinal. */
    static int rank(int act) {
        switch (act) {
            case ACT_DISINTEGRATE: return 100;
            case ACT_FIRE_SINGLE:
            case ACT_FIRE_TRIAD:
            case ACT_FIRE_PENTAD:
            case ACT_STRIKE:
            case ACT_CHOP: return 90;
            case ACT_BODY_ATTACK: return 80;
            case ACT_PLANT:
            case ACT_HIRE:
            case ACT_BUILD: return 70;
            case ACT_WATER: return 60;
            case ACT_SHAKE: return 50;
            case ACT_DONATE: return 40;
            case ACT_MOVE: return 30;
            case ACT_BROADCAST: return 20;
            default: return 0;
        }
    }

    // ---- formatting ------------------------------------------------------

    /** `java.lang.Long.toHexString` of a float32's RAW bits. */
    static String bits(float v) {
        return Long.toHexString(Float.floatToRawIntBits(v) & 0xFFFFFFFFL);
    }

    static long fnvStep(long h, long v) {
        return (h ^ (v & 0xFFFFFFFFL)) * 0x100000001B3L;
    }

    static String teamLetter(Team t) {
        if (t == Team.A) return "A";
        if (t == Team.B) return "B";
        if (t == Team.NEUTRAL) return "N";
        return "-";
    }

    // ---- reflection ------------------------------------------------------

    static Object peek(Object target, Class<?> owner, String name) {
        try {
            Field f = owner.getDeclaredField(name);
            f.setAccessible(true);
            return f.get(target);
        } catch (Exception e) {
            throw new RuntimeException("cannot read " + owner.getSimpleName()
                    + "." + name, e);
        }
    }

    @SuppressWarnings("unchecked")
    static TIntObjectHashMap<InternalTree> trees(ObjectInfo oi) {
        return (TIntObjectHashMap<InternalTree>)
                peek(oi, ObjectInfo.class, "gameTreesByID");
    }

    static TIntArrayList execOrder(ObjectInfo oi) {
        return (TIntArrayList)
                peek(oi, ObjectInfo.class, "dynamicBodyExecOrder");
    }

    @SuppressWarnings("unchecked")
    static TIntObjectHashMap<RobotInfo> currentBroadcasters(GameWorld w) {
        return (TIntObjectHashMap<RobotInfo>)
                peek(w, GameWorld.class, "currentBroadcasters");
    }

    /** The id `nextID()` would hand out next, WITHOUT consuming it. */
    static int peekId(IDGenerator gen) {
        int[] reserved = (int[]) peek(gen, IDGenerator.class, "reservedIDs");
        int cursor = ((Integer) peek(gen, IDGenerator.class, "cursor"))
                .intValue();
        return reserved[cursor];
    }

    // ---- the per-turn watcher -------------------------------------------

    /**
     * A pass-through `RobotControlProvider` that brackets every robot's turn
     * so the `A` line can be recovered. It changes NOTHING the engine does:
     * every call is delegated, in order, to the real `TeamControlProvider`.
     */
    static final class Watcher implements RobotControlProvider {
        final TeamControlProvider inner;
        GameWorld world;
        TIntArrayList actionIDs;
        TByteArrayList actionKinds;
        TIntArrayList actionTargets;
        /** robot id -> (act, tgt) for the round being played. */
        final Map<Integer, int[]> turnAction = new HashMap<Integer, int[]>();
        boolean neutralRobotSeen = false;
        long actionsEver = 0;

        Watcher(TeamControlProvider inner) {
            this.inner = inner;
        }

        void bindMatchMaker(GameMaker.MatchMaker mm) {
            actionIDs = (TIntArrayList)
                    peek(mm, GameMaker.MatchMaker.class, "actionIDs");
            actionKinds = (TByteArrayList)
                    peek(mm, GameMaker.MatchMaker.class, "actions");
            actionTargets = (TIntArrayList)
                    peek(mm, GameMaker.MatchMaker.class, "actionTargets");
        }

        public void matchStarted(GameWorld w) {
            this.world = w;
            inner.matchStarted(w);
        }

        public void matchEnded() { inner.matchEnded(); }

        public void roundStarted() {
            turnAction.clear();
            inner.roundStarted();
        }

        public void roundEnded() { inner.roundEnded(); }

        public void robotSpawned(InternalRobot robot) {
            if (robot.getTeam() == Team.NEUTRAL) neutralRobotSeen = true;
            inner.robotSpawned(robot);
        }

        public void robotKilled(InternalRobot robot) {
            inner.robotKilled(robot);
        }

        public int getBytecodesUsed(InternalRobot robot) {
            return inner.getBytecodesUsed(robot);
        }

        public boolean getTerminated(InternalRobot robot) {
            return inner.getTerminated(robot);
        }

        public void runRobot(InternalRobot robot) {
            final int id = robot.getID();
            final Team team = robot.getTeam();
            final int logBefore = actionIDs.size();
            final int vpBefore = world.getTeamInfo().getVictoryPoints(team);
            final boolean broadcastBefore =
                    currentBroadcasters(world).containsKey(id);
            // A TANK's body attack is invisible to the engine's action log,
            // so the trees it could possibly reach are snapshotted. The set
            // is a handful of trees and only tanks pay for it.
            Map<Integer, Float> treesBefore = null;
            if (robot.getType() == RobotType.TANK) {
                treesBefore = new HashMap<Integer, Float>();
                float reach = RobotType.TANK.bodyRadius
                        + RobotType.TANK.strideRadius
                        + GameConstants.NEUTRAL_TREE_MAX_RADIUS;
                for (InternalTree t : world.getObjectInfo()
                        .getAllTreesWithinRadius(robot.getLocation(), reach)) {
                    treesBefore.put(Integer.valueOf(t.getID()),
                            Float.valueOf(t.getHealth()));
                }
            }

            inner.runRobot(robot);

            int best = ACT_NOTHING;
            int bestTgt = 0;
            for (int i = logBefore; i < actionIDs.size(); i++) {
                if (actionIDs.get(i) != id) continue;
                final byte kind = actionKinds.get(i);
                final int target = actionTargets.get(i);
                int act = ACT_NOTHING;
                int tgt = 0;
                switch (kind) {
                    case Action.FIRE: act = ACT_FIRE_SINGLE; break;
                    case Action.FIRE_TRIAD: act = ACT_FIRE_TRIAD; break;
                    case Action.FIRE_PENTAD: act = ACT_FIRE_PENTAD; break;
                    case Action.LUMBERJACK_STRIKE: act = ACT_STRIKE; break;
                    case Action.CHOP: act = ACT_CHOP; break;
                    case Action.SHAKE_TREE:
                        act = ACT_SHAKE; tgt = target; break;
                    case Action.WATER_TREE:
                        act = ACT_WATER; tgt = target; break;
                    case Action.PLANT_TREE:
                        act = ACT_PLANT; tgt = target; break;
                    case Action.SPAWN_UNIT: {
                        InternalRobot built = world.getObjectInfo()
                                .getRobotByID(target);
                        act = (built != null
                                && built.getType() == RobotType.GARDENER)
                                ? ACT_HIRE : ACT_BUILD;
                        tgt = target;
                        break;
                    }
                    case Action.DIE_SUICIDE:
                    case Action.DIE_EXCEPTION:
                        act = ACT_DISINTEGRATE; break;
                    default: continue;
                }
                actionsEver++;
                if (rank(act) >= rank(best)) {
                    best = act;
                    bestTgt = tgt;
                }
            }

            if (treesBefore != null && rank(ACT_BODY_ATTACK) > rank(best)) {
                for (Map.Entry<Integer, Float> e : treesBefore.entrySet()) {
                    InternalTree now = world.getObjectInfo()
                            .getTreeByID(e.getKey().intValue());
                    if (now == null
                            || now.getHealth() < e.getValue().floatValue()) {
                        best = ACT_BODY_ATTACK;
                        bestTgt = 0;
                        actionsEver++;
                        break;
                    }
                }
            }

            final int vpAfter = world.getTeamInfo().getVictoryPoints(team);
            if (vpAfter != vpBefore && rank(ACT_DONATE) > rank(best)) {
                best = ACT_DONATE;
                bestTgt = vpAfter - vpBefore;
                actionsEver++;
            }
            if (robot.getMoveCount() > 0 && rank(ACT_MOVE) > rank(best)) {
                best = ACT_MOVE;
                bestTgt = 0;
                actionsEver++;
            }
            if (!broadcastBefore
                    && currentBroadcasters(world).containsKey(id)
                    && rank(ACT_BROADCAST) > rank(best)) {
                best = ACT_BROADCAST;
                bestTgt = 0;
                actionsEver++;
            }
            turnAction.put(Integer.valueOf(id), new int[] {best, bestTgt});
        }
    }

    // ---- the driver ------------------------------------------------------

    public static void main(String[] args) throws Exception {
        int exit = 0;
        try {
            exit = run(args);
        } catch (Throwable t) {
            t.printStackTrace();
            exit = 4;
        }
        // MANDATORY: the sandboxed player threads are non-daemon.
        System.exit(exit);
    }

    static int run(String[] args) throws Exception {
        if (args.length < 4) {
            System.err.println("usage: Bc17Trace <map> <rounds> <pkgA> "
                    + "<classesA> [<pkgB> <classesB>]");
            return 2;
        }
        final String mapName = args[0];
        final int rounds = Integer.parseInt(args[1]);
        final String pkgA = args[2];
        final File dirA = new File(args[3]).getAbsoluteFile();
        final String pkgB = args.length >= 6 ? args[4] : pkgA;
        final File dirB = args.length >= 6
                ? new File(args[5]).getAbsoluteFile() : dirA;

        // The RESOURCE FALLBACK path: the jar carries all 70 .map17 maps and
        // every pool map is one of them, so no --map-dir is needed.
        final LiveMap map = GameMapIO.loadMap(mapName, null);

        final GameInfo gameInfo = new GameInfo(
                "A", pkgA, dirA.toURI().toURL().toString(),
                "B", pkgB, dirB.toURI().toURL().toString(),
                new String[] {mapName}, null, false);
        // A real GameMaker with a null packet sink: it builds the flatbuffers
        // in memory and NOTHING IS EVER WRITTEN -- `writeGame` is not called.
        final GameMaker gameMaker = new GameMaker(gameInfo, null);
        gameMaker.makeGameHeader();

        // Player stdout would otherwise interleave with the trace.
        final PrintStream realOut = System.out;
        final OutputStream sink = new OutputStream() {
            public void write(int b) { }
            public void write(byte[] b, int off, int len) { }
        };
        System.setOut(new PrintStream(sink));

        final TeamControlProvider teams = new TeamControlProvider();
        teams.registerControlProvider(Team.A,
                new PlayerControlProvider(pkgA,
                        dirA.toURI().toURL().toString(), sink));
        teams.registerControlProvider(Team.B,
                new PlayerControlProvider(pkgB,
                        dirB.toURI().toURL().toString(), sink));
        // NO `Team.NEUTRAL` REGISTRATION, unlike 2016: 2017 has no neutral
        // ROBOTS at all, only neutral trees, so `runRobot` is never reached
        // for one. The watcher asserts that rather than assuming it.
        final Watcher watcher = new Watcher(teams);
        watcher.bindMatchMaker(gameMaker.getMatchMaker());

        final GameWorld world = new GameWorld(map, watcher,
                new long[2][GameConstants.TEAM_MEMORY_LENGTH],
                gameMaker.getMatchMaker());

        final ObjectInfo oi = world.getObjectInfo();
        final TeamInfo ti = world.getTeamInfo();
        final StringBuilder sb = new StringBuilder(1 << 20);

        int lastRound = -1;
        int peakRobots = oi.getRobotCount(Team.A) + oi.getRobotCount(Team.B);
        int peakBullets = 0;
        int peakBytecodes = 0;
        int peakLimit = 1;
        int peakRound = -1;
        int peakId = -1;
        long bulletsEver = 0;
        long treesEver = 0;

        for (int i = 0; i < rounds; i++) {
            final GameState state = world.runRound();
            final int cur = world.getCurrentRound();
            lastRound = cur;

            // One walk for both teams: a tree is MATURE once its
            // `roundsAlive` passes 80, which is exactly the round
            // `InternalTree.updateTree` stops growing it and starts paying.
            final int[] mature = new int[3];
            trees(oi).forEachValue(new TObjectProcedure<InternalTree>() {
                public boolean execute(InternalTree tree) {
                    if (tree.getRoundsAlive() > 80) {
                        mature[tree.getTeam().ordinal()]++;
                    }
                    return true;
                }
            });
            for (int t2 = 0; t2 <= 1; t2++) {
                final Team t = t2 == 0 ? Team.A : Team.B;
                sb.append("R ").append(cur).append(" T ").append(teamLetter(t))
                  .append(" bul=").append(bits(ti.getBulletSupply(t)))
                  .append(" vp=").append(ti.getVictoryPoints(t))
                  .append(" ar=").append(oi.getRobotTypeCount(t, RobotType.ARCHON))
                  .append(" ga=").append(oi.getRobotTypeCount(t, RobotType.GARDENER))
                  .append(" lj=").append(oi.getRobotTypeCount(t, RobotType.LUMBERJACK))
                  .append(" so=").append(oi.getRobotTypeCount(t, RobotType.SOLDIER))
                  .append(" ta=").append(oi.getRobotTypeCount(t, RobotType.TANK))
                  .append(" sc=").append(oi.getRobotTypeCount(t, RobotType.SCOUT))
                  .append(" tr=").append(oi.getTreeCount(t))
                  .append(" trm=").append(mature[t.ordinal()])
                  .append('\n');
            }

            // ROBOTS AND BULLETS IN EXEC ORDER; the folds are built in the
            // same walk so an ordering bug cannot hide in one and not the
            // other.
            final int[] order = execOrder(oi).toArray();
            long execFold = 0xCBF29CE484222325L;
            long uFold = 0xCBF29CE484222325L;
            long bFold = 0xCBF29CE484222325L;
            int liveRobots = 0;
            int liveBullets = 0;
            final StringBuilder bulletLines = new StringBuilder();
            final StringBuilder actionLines = new StringBuilder();
            for (int k = 0; k < order.length; k++) {
                final int id = order[k];
                execFold = fnvStep(execFold, id);
                final InternalRobot r = oi.getRobotByID(id);
                if (r != null) {
                    liveRobots++;
                    final MapLocation l = r.getLocation();
                    final int bc = r.getBytecodesUsed();
                    final int limit = r.getType().bytecodeLimit;
                    if (limit > 0 && (long) bc * peakLimit
                            > (long) peakBytecodes * limit) {
                        peakBytecodes = bc;
                        peakLimit = limit;
                        peakRound = cur;
                        peakId = id;
                    }
                    uFold = fnvStep(uFold, id);
                    uFold = fnvStep(uFold, Float.floatToRawIntBits(l.x));
                    uFold = fnvStep(uFold, Float.floatToRawIntBits(l.y));
                    uFold = fnvStep(uFold,
                            Float.floatToRawIntBits(r.getHealth()));
                    sb.append("R ").append(cur).append(" U ").append(id)
                      .append(" team=").append(teamLetter(r.getTeam()))
                      .append(" ty=").append(r.getType().name())
                      .append(" x=").append(bits(l.x))
                      .append(" y=").append(bits(l.y))
                      .append(" hp=").append(bits(r.getHealth()))
                      .append(" ra=").append(r.getRoundsAlive())
                      .append(" ac=").append(r.getAttackCount())
                      .append(" mc=").append(r.getMoveCount())
                      .append(" wc=").append(r.getWaterCount())
                      .append(" shc=").append(r.getShakeCount())
                      .append(" cd=").append(r.getBuildCooldownTurns())
                      .append(" bc=").append(bc)
                      .append('\n');
                    final int[] act = watcher.turnAction.get(
                            Integer.valueOf(id));
                    final int a = act == null ? ACT_NOTHING : act[0];
                    final int tgt = act == null ? 0 : act[1];
                    actionLines.append("R ").append(cur).append(" A ")
                      .append(id).append(" act=").append(ACT_NAMES[a])
                      .append(" tgt=").append(tgt)
                      .append(" x=").append(bits(l.x))
                      .append(" y=").append(bits(l.y))
                      .append(" arg=").append(bits(0f))
                      .append('\n');
                    continue;
                }
                final InternalBullet b = oi.getBulletByID(id);
                if (b == null) continue;
                liveBullets++;
                final MapLocation bl = b.getLocation();
                bFold = fnvStep(bFold, id);
                bFold = fnvStep(bFold, Float.floatToRawIntBits(bl.x));
                bFold = fnvStep(bFold, Float.floatToRawIntBits(bl.y));
                bFold = fnvStep(bFold,
                        Float.floatToRawIntBits(b.getDirection().radians));
                bulletLines.append("R ").append(cur).append(" B ").append(id)
                  .append(" team=").append(teamLetter(b.getTeam()))
                  .append(" x=").append(bits(bl.x))
                  .append(" y=").append(bits(bl.y))
                  .append(" dir=").append(bits(b.getDirection().radians))
                  .append(" sp=").append(bits(b.getSpeed()))
                  .append(" dmg=").append(bits(b.getDamage()))
                  .append(" ra=").append(b.getRoundsAlive())
                  .append('\n');
            }
            if (liveRobots > peakRobots) peakRobots = liveRobots;
            if (liveBullets > peakBullets) peakBullets = liveBullets;
            bulletsEver += liveBullets;

            // TREES IN TROVE ORDER -- `gameTreesByID.forEachValue` IS the
            // order the float32 income sum is accumulated in (D1).
            final long[] tFold = new long[] {0xCBF29CE484222325L};
            final int[] treeSeen = new int[1];
            final int curRound = cur;
            final StringBuilder treeLines = new StringBuilder();
            trees(oi).forEachValue(new TObjectProcedure<InternalTree>() {
                public boolean execute(InternalTree tree) {
                    treeSeen[0]++;
                    MapLocation l = tree.getLocation();
                    tFold[0] = fnvStep(tFold[0], tree.getID());
                    tFold[0] = fnvStep(tFold[0], Float.floatToRawIntBits(l.x));
                    tFold[0] = fnvStep(tFold[0], Float.floatToRawIntBits(l.y));
                    tFold[0] = fnvStep(tFold[0],
                            Float.floatToRawIntBits(tree.getHealth()));
                    RobotType inside = tree.getContainedRobot();
                    treeLines.append("R ").append(curRound).append(" E ")
                      .append(tree.getID())
                      .append(" team=").append(teamLetter(tree.getTeam()))
                      .append(" x=").append(bits(l.x))
                      .append(" y=").append(bits(l.y))
                      .append(" r=").append(bits(tree.getRadius()))
                      .append(" hp=").append(bits(tree.getHealth()))
                      .append(" mhp=").append(bits(tree.getMaxHealth()))
                      .append(" cb=").append((int) tree.getContainedBullets())
                      .append(" crob=")
                      .append(inside == null ? "-" : inside.name())
                      .append(" ra=").append(tree.getRoundsAlive())
                      .append('\n');
                    return true;
                }
            });
            treesEver += treeSeen[0];
            sb.append(treeLines);
            sb.append(bulletLines);
            sb.append(actionLines);

            long broadFold = 0xCBF29CE484222325L;
            for (RobotInfo ri : world.getPreviousBroadcasters()) {
                broadFold = fnvStep(broadFold, ri.ID);
                broadFold = fnvStep(broadFold,
                        Float.floatToRawIntBits(ri.location.x));
                broadFold = fnvStep(broadFold,
                        Float.floatToRawIntBits(ri.location.y));
            }

            sb.append("R ").append(cur).append(" G exec=")
              .append(Long.toHexString(execFold))
              .append(" execlen=").append(order.length)
              .append(" ubod=").append(Long.toHexString(uFold))
              .append(" tbod=").append(Long.toHexString(tFold[0]))
              .append(" bbod=").append(Long.toHexString(bFold))
              .append(" nb=").append(liveBullets)
              .append(" rid=").append(peekId(world.idGenerator))
              .append(" bid=").append(peekId(world.bulletIdGenerator))
              .append(" broad=").append(Long.toHexString(broadFold))
              .append('\n');

            if (sb.length() > (1 << 22)) {
                realOut.print(sb);
                sb.setLength(0);
            }
            if (state == GameState.DONE || !world.isRunning()) break;
        }

        final Team winner = world.getWinner();
        sb.append("R ").append(lastRound).append(" W winner=")
          .append(winner == null ? "-" : teamLetter(winner))
          .append(" dom=")
          .append(world.getGameStats().getDominationFactor() == null ? "-"
                  : world.getGameStats().getDominationFactor().name())
          .append('\n');
        realOut.print(sb);
        realOut.flush();

        System.setOut(realOut);
        System.err.println("bc17-oracle map=" + mapName
                + " rounds=" + lastRound
                + " peak_bytecodes=" + peakBytecodes
                + " peak_limit=" + peakLimit
                + " peak_pct=" + (peakLimit == 0 ? 0
                        : (100 * peakBytecodes / peakLimit))
                + " peak_round=" + peakRound
                + " peak_id=" + peakId
                + " peak_robots=" + peakRobots
                + " peak_bullets=" + peakBullets
                + " bullet_rounds=" + bulletsEver
                + " tree_rounds=" + treesEver
                + " actions=" + watcher.actionsEver
                + " neutral_robot=" + watcher.neutralRobotSeen);

        if (watcher.neutralRobotSeen) {
            System.err.println("::error::a NEUTRAL robot was spawned. 2017 "
                    + "has no neutral robots -- only neutral trees -- and "
                    + "this driver deliberately registers no control "
                    + "provider for Team.NEUTRAL.");
            return 5;
        }
        // THE GREEN-ORACLE-PROVING-NOTHING TRAP. Under a JDK newer than 8 the
        // instrumenter throws inside ClassReader.<init> on every player class
        // load, no robot ever acts, and this job would be green while proving
        // nothing.
        // The condition is "nothing happened AND the game did not run its
        // course", not merely "nothing happened": Tier A's `bc17idle` is a
        // bot whose whole body is `while (true) Clock.yield();`, so on that
        // tier NO ROBOT EVER ACTS BY DESIGN and it still plays all 2 999
        // rounds. A broken instrumenter looks nothing like that -- every
        // robot is `suicide()`d as it spawns, the game is over in one round
        // with DESTROYED, and this is the branch that catches it.
        if (watcher.actionsEver == 0 && peakBullets == 0
                && lastRound < rounds - 1) {
            System.err.println("::error::no robot ever took an action and no "
                    + "bullet was ever spawned. THIS ORACLE MUST RUN ON "
                    + "TEMURIN 8 -- the jar bundles a 2017-era ASM 5.0.4 and "
                    + "under a modern JDK every player class load throws "
                    + "inside ClassReader.<init>, and this oracle would be "
                    + "green while proving nothing (docs/PARITY.md "
                    + "section bc17).");
            return 3;
        }
        return 0;
    }
}
