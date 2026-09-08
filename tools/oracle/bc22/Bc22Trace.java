// The bc22 parity oracle's Java side: run the PUBLISHED 2022 engine headlessly
// and print one line per record from the live objects.
//
// CI-TIME ONLY. There is no JDK, no JRE and no Java in ANY runtime image
// stage; this file is compiled and run by the `parity-oracle-bc22` job of
// .github/workflows/ci.yml against the released `battlecode22-2.2.1.jar`
// (sha256 AND size pinned in tools/oracle/bc22/jar.lock).
//
// It is `package battlecode.world;` so it needs NO reflection except for
// `ObjectInfo.dynamicBodyExecOrder` (private -- the only way to print in exec
// order) and `GameWorld.lead` / `gold` / `rubble` (private -- the only way to
// checksum the three map arrays). Printing in exec order is what makes an
// ordering bug visible at all; the three checksums are what make ONE WRONG
// SQUARE visible without printing 3 600 squares a round.
//
// FOUR THINGS THAT WERE MEASURED AND WOULD OTHERWISE EACH COST A CI ROUND:
//
//   * TEMURIN 8, AND IT IS NOT NEGOTIABLE. `engine/build.gradle` sets
//     `sourceCompatibility = 1.8` and declares `org.ow2.asm:asm:5.0.4`, which
//     cannot read modern class files. Under JDK 21 the instrumenter throws
//         java.lang.IllegalArgumentException
//         at org.objectweb.asm.ClassReader.<init>
//         from battlecode.instrumenter.TeamClassLoaderFactory.normalReader:233
//         via battlecode.instrumenter.bytecode.MethodCostUtil.getMethodData:96
//     on EVERY player class load; every robot dies as it spawns, NO ROBOT IS
//     EVER BUILT, the game ends at ROUND 1 with `winner=A dom=ANNIHILATION`
//     after six trace lines, and the job exits 0. That is the "green oracle
//     proving nothing" trap, and this driver therefore EXITS 3 IF NO ROBOT IS
//     EVER BUILT.
//   * `javac` WITH NO `--release`, NO `-source`, NO `-target`. `--release`
//     arrived in JDK 9 and dies with "invalid flag" on a JDK-8 javac in
//     seconds (the bc21 lesson). The compiler IS 8, so the target is 8.
//   * THE DRIVER MUST CALL `System.exit()`. The sandboxed player threads are
//     NON-DAEMON: a driver that returns or throws without it hangs for ever.
//     Every `java` invocation in the job is also wrapped in `timeout 600`.
//   * THE PLAYER URL MUST BE THE COMPILED CLASSES DIRECTORY. An empty URL
//     fails class loading and the world constructor NPEs.
//
// `GameMapIO.loadMapAsResource` takes THREE arguments in 2022, not bc23's
// four. `new GameMaker(info, null, false)` is explicitly supported: the null
// packet sink means no flatbuffers are written at all, so there is no `.bc22`
// file and no flatbuffers reader on either side of this port.
//
// Usage:
//   javac -nowarn -encoding UTF-8 -cp battlecode22-2.2.1.jar -d classes \
//         tools/oracle/bc22/Bc22Trace.java <bot>/RobotPlayer.java
//   java -Xmx2g -XX:+UseSerialGC \
//        -cp battlecode22-2.2.1.jar:classes \
//        battlecode.world.Bc22Trace <map> <rounds> <pkgA> <classesA> \
//                                   [<pkgB> <classesB>]
//
// The trace, one line per record:
//
//   R <round> T <A|B> pb=<n> au=<n> ar=<n> la=<n> wa=<n> mi=<n> bu=<n>
//             so=<n> sa=<n>
//   R <round> G leadchk=<fnv1a64> goldchk=<fnv1a64> rubblechk=<fnv1a64>
//             leadsum=<n> goldsum=<n>
//   R <round> U <id> team=<A|B> ty=<TYPE> md=<MODE> lv=<n> x=<n> y=<n>
//             hp=<n> acd=<n> mcd=<n> bc=<n>
//   R <round> S <A|B> arr=<fnv1a64 of the 64-slot shared array>
//   R <round> H hashord=<fnv1a64 of the ids in robotsArray() order>
//   R <round> A next=<idx> type=<ABYSS|CHARGE|FURY|VORTEX|-> round=<n>
//   R <round> Z winner=<A|B|-> dom=<NAME|->
//
// Robots are printed IN EXEC ORDER, not id order. The `H` line is what makes
// a TROVE-ORDER bug visible (docs/RULES-BC22.md Divergences item 4) and it is
// compared EVERY ROUND, not only on charge rounds: a trove bug then surfaces
// on round 1 as a checksum mismatch instead of on round 400 as a mystery.
// `rubblechk` is what proves a VORTEX permuted the right way. The `bc=`
// column is the Java bytecode counter; the comparison strips it from BOTH
// sides and uses it only for the Tier A headroom assertion.
package battlecode.world;

import battlecode.common.*;
import battlecode.server.GameInfo;
import battlecode.server.GameMaker;
import battlecode.server.GameState;
import battlecode.world.control.PlayerControlProvider;
import battlecode.world.control.TeamControlProvider;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.PrintStream;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;

public final class Bc22Trace {

    static String teamLetter(Team t) {
        return t == Team.A ? "A" : (t == Team.B ? "B" : "-");
    }

    static List<InternalRobot> execOrder(GameWorld world) throws Exception {
        ObjectInfo info = world.getObjectInfo();
        Field f = ObjectInfo.class.getDeclaredField("dynamicBodyExecOrder");
        f.setAccessible(true);
        gnu.trove.list.array.TIntArrayList order =
                (gnu.trove.list.array.TIntArrayList) f.get(info);
        List<InternalRobot> out = new ArrayList<InternalRobot>();
        int[] ids = order.toArray();
        for (int i = 0; i < ids.length; i++) {
            InternalRobot r = info.getRobotByID(ids[i]);
            if (r != null) out.add(r);
        }
        return out;
    }

    static int[] intArray(GameWorld world, String name) throws Exception {
        Field f = GameWorld.class.getDeclaredField(name);
        f.setAccessible(true);
        return (int[]) f.get(world);
    }

    static int nextAnomalyIndex(LiveMap map) throws Exception {
        Field f = LiveMap.class.getDeclaredField("nextAnomalyIndex");
        f.setAccessible(true);
        return f.getInt(map);
    }

    static long fnv(int[] values) {
        long h = 0xCBF29CE484222325L;
        for (int i = 0; i < values.length; i++) {
            h = (h ^ (values[i] & 0xFFFFFFFFL)) * 0x100000001B3L;
        }
        return h;
    }

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
            System.err.println("usage: Bc22Trace <map> <rounds> <pkgA> "
                    + "<classesA> [<pkgB> <classesB>]");
            return 2;
        }
        final String mapName = args[0];
        final int rounds = Integer.parseInt(args[1]);
        final String pkgA = args[2];
        final String classesA = new File(args[3]).getAbsolutePath();
        final String pkgB = args.length >= 6 ? args[4] : pkgA;
        final String classesB = args.length >= 6
                ? new File(args[5]).getAbsolutePath() : classesA;

        // THREE arguments in 2022, not bc23's four.
        LiveMap map = GameMapIO.loadMapAsResource(
                Bc22Trace.class.getClassLoader(),
                "battlecode/world/resources", mapName);

        GameInfo info = new GameInfo("A", pkgA, classesA, "B", pkgB, classesB,
                new String[]{mapName}, null, false);
        GameMaker maker = new GameMaker(info, null, false);
        maker.makeGameHeader();

        ByteArrayOutputStream robotOut = new ByteArrayOutputStream();
        TeamControlProvider provider = new TeamControlProvider();
        provider.registerControlProvider(Team.A,
                new PlayerControlProvider(Team.A, pkgA, classesA, robotOut,
                        false));
        provider.registerControlProvider(Team.B,
                new PlayerControlProvider(Team.B, pkgB, classesB, robotOut,
                        false));

        // Player stdout would otherwise interleave with the trace: the
        // example bot prints its age and location EVERY TURN.
        PrintStream realOut = System.out;
        System.setOut(new PrintStream(new ByteArrayOutputStream()));

        GameWorld world = new GameWorld(map, provider, maker.getMatchMaker());
        TeamInfo ti = world.getTeamInfo();
        ObjectInfo oi = world.getObjectInfo();

        StringBuilder sb = new StringBuilder(1 << 20);
        int builtEver = 0;
        int alive = execOrder(world).size();
        int peakRobots = alive;
        int peakBytecodes = 0;
        int peakLimit = 1;
        int peakRound = -1;
        int peakId = -1;

        for (int round = 1; round <= rounds; round++) {
            GameState state = world.runRound();
            int cur = world.getCurrentRound();

            for (int t2 = 0; t2 <= 1; t2++) {
                Team t = t2 == 0 ? Team.A : Team.B;
                sb.append("R ").append(cur).append(" T ").append(teamLetter(t))
                  .append(" pb=").append(ti.getLead(t))
                  .append(" au=").append(ti.getGold(t))
                  .append(" ar=").append(oi.getRobotTypeCount(t, RobotType.ARCHON))
                  .append(" la=").append(oi.getRobotTypeCount(t, RobotType.LABORATORY))
                  .append(" wa=").append(oi.getRobotTypeCount(t, RobotType.WATCHTOWER))
                  .append(" mi=").append(oi.getRobotTypeCount(t, RobotType.MINER))
                  .append(" bu=").append(oi.getRobotTypeCount(t, RobotType.BUILDER))
                  .append(" so=").append(oi.getRobotTypeCount(t, RobotType.SOLDIER))
                  .append(" sa=").append(oi.getRobotTypeCount(t, RobotType.SAGE))
                  .append('\n');
            }

            // The three map arrays, folded. `rubblechk` is what proves a
            // VORTEX permuted the right way: measured on `charge` it changes
            // exactly once, at round 1000, and never again.
            int[] lead = intArray(world, "lead");
            int[] gold = intArray(world, "gold");
            int[] rubble = intArray(world, "rubble");
            long leadSum = 0;
            long goldSum = 0;
            for (int i = 0; i < lead.length; i++) leadSum += lead[i];
            for (int i = 0; i < gold.length; i++) goldSum += gold[i];
            sb.append("R ").append(cur).append(" G leadchk=")
              .append(Long.toHexString(fnv(lead)))
              .append(" goldchk=").append(Long.toHexString(fnv(gold)))
              .append(" rubblechk=").append(Long.toHexString(fnv(rubble)))
              .append(" leadsum=").append(leadSum)
              .append(" goldsum=").append(goldSum)
              .append('\n');

            List<InternalRobot> order = execOrder(world);
            for (InternalRobot r : order) {
                MapLocation l = r.getLocation();
                int bc = r.getBytecodesUsed();
                int limit = r.getType().bytecodeLimit;
                if (limit > 0 && (long) bc * peakLimit
                        > (long) peakBytecodes * limit) {
                    peakBytecodes = bc;
                    peakLimit = limit;
                    peakRound = cur;
                    peakId = r.getID();
                }
                sb.append("R ").append(cur).append(" U ").append(r.getID())
                  .append(" team=").append(teamLetter(r.getTeam()))
                  .append(" ty=").append(r.getType().name())
                  .append(" md=").append(r.getMode().name())
                  .append(" lv=").append(r.getLevel())
                  .append(" x=").append(l == null ? -1 : l.x)
                  .append(" y=").append(l == null ? -1 : l.y)
                  .append(" hp=").append(r.getHealth())
                  .append(" acd=").append(r.getActionCooldownTurns())
                  .append(" mcd=").append(r.getMovementCooldownTurns())
                  .append(" bc=").append(bc)
                  .append('\n');
            }

            for (int t2 = 0; t2 <= 1; t2++) {
                Team t = t2 == 0 ? Team.A : Team.B;
                int[] arr = new int[GameConstants.SHARED_ARRAY_LENGTH];
                for (int i = 0; i < arr.length; i++) {
                    arr[i] = ti.readSharedArray(t, i);
                }
                sb.append("R ").append(cur).append(" S ").append(teamLetter(t))
                  .append(" arr=").append(Long.toHexString(fnv(arr)))
                  .append('\n');
            }

            // THE `H` LINE: the ids in `robotsArray()` order, i.e. trove's
            // `values(V[])` high-index-to-low walk. This is the single most
            // important line in the trace, because it is the ONE order the
            // 2022 rule set actually reads (`causeChargeGlobal`) and it is a
            // function of the hash table's capacity, its insertion order and
            // its tombstone history. Compared EVERY round.
            InternalRobot[] hashOrder = oi.robotsArray();
            int[] ids = new int[hashOrder.length];
            for (int i = 0; i < hashOrder.length; i++) {
                ids[i] = hashOrder[i] == null ? 0 : hashOrder[i].getID();
            }
            sb.append("R ").append(cur).append(" H hashord=")
              .append(Long.toHexString(fnv(ids)))
              .append('\n');

            AnomalyScheduleEntry next = map.viewNextAnomaly();
            sb.append("R ").append(cur).append(" A next=")
              .append(nextAnomalyIndex(map))
              .append(" type=")
              .append(next == null ? "-" : next.anomalyType.name())
              .append(" round=").append(next == null ? -1 : next.roundNumber)
              .append('\n');

            int now = order.size();
            if (now > alive) builtEver += (now - alive);
            if (now > peakRobots) peakRobots = now;
            alive = now;

            if (sb.length() > (1 << 22)) {
                realOut.print(sb);
                sb.setLength(0);
            }
            if (state == GameState.DONE || !world.isRunning()) break;
        }

        Team winner = world.getWinner();
        sb.append("R ").append(world.getCurrentRound()).append(" Z winner=")
          .append(winner == null ? "-" : teamLetter(winner))
          .append(" dom=")
          .append(world.getGameStats().getDominationFactor() == null ? "-"
                  : world.getGameStats().getDominationFactor().name())
          .append('\n');
        realOut.print(sb);
        realOut.flush();

        System.setOut(realOut);
        System.err.println("bc22-oracle map=" + mapName
                + " rounds=" + world.getCurrentRound()
                + " peak_bytecodes=" + peakBytecodes
                + " peak_limit=" + peakLimit
                + " peak_pct=" + (peakLimit == 0 ? 0
                        : (100 * peakBytecodes / peakLimit))
                + " peak_round=" + peakRound
                + " peak_id=" + peakId
                + " peak_robots=" + peakRobots
                + " built=" + builtEver);
        if (builtEver == 0) {
            System.err.println("::error::no robot was ever built: the "
                    + "instrumenter almost certainly refused the player "
                    + "classes. THIS ORACLE MUST RUN ON TEMURIN 8 -- the jar "
                    + "bundles ASM 5.0.4 and under JDK 21 every player class "
                    + "load throws inside ClassReader.<init>, every robot "
                    + "dies as it spawns, and this oracle would be green "
                    + "while proving nothing.");
            return 3;
        }
        return 0;
    }
}
