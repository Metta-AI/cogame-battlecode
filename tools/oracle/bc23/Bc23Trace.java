// The bc23 parity oracle's Java side: run the PUBLISHED 2023 engine headlessly
// and print one line per record from the live objects.
//
// CI-TIME ONLY. There is no JDK, no JRE and no Java in ANY runtime image
// stage; this file is compiled and run by the `parity-oracle-bc23` job of
// .github/workflows/ci.yml against the released `battlecode23-3.0.15.jar`
// (sha256 AND size pinned in tools/oracle/bc23/jar.lock).
//
// It is `package battlecode.world;` so it needs NO reflection except for
// `ObjectInfo.dynamicBodyExecOrder` and `GameWorld.islandIdToIsland`, which
// are private and are the only way to print in exec order and in island-id
// order -- and printing in those orders is what makes an ordering bug visible
// at all.
//
// FOUR THINGS THAT WERE MEASURED AND WOULD OTHERWISE EACH COST A CI ROUND:
//
//   * TEMURIN 8, AND IT IS NOT NEGOTIABLE. The jar bundles ASM 5.0.4, which
//     cannot read modern class files. Under JDK 21 the instrumenter throws
//         java.lang.IllegalArgumentException
//         at org.objectweb.asm.ClassReader.<init>
//         from TeamClassLoaderFactory.normalReader
//         via MethodCostUtil.getMethodData
//     on EVERY player class load; every robot dies as it spawns, NO ROBOT IS
//     EVER BUILT, the trace is a few hundred empty lines and the job exits 0.
//     That is the "green oracle proving nothing" trap, and this driver
//     therefore EXITS 3 IF NO ROBOT IS EVER BUILT.
//   * `javac` WITH NO `--release`, NO `-source`, NO `-target`. `--release`
//     arrived in JDK 9 and dies with "invalid flag" on a JDK-8 javac in
//     seconds (the bc21 lesson). The compiler IS 8, so the target is 8.
//   * THE DRIVER MUST CALL `System.exit()`. The sandboxed player threads are
//     NON-DAEMON: a driver that returns or throws without it hangs for ever.
//     Measured -- the first run of this driver hung until the harness timeout
//     after an unrelated exception. Every `java` invocation in the job is
//     also wrapped in `timeout 600`.
//   * THE PLAYER URL MUST BE THE COMPILED CLASSES DIRECTORY. An empty URL
//     fails class loading and the world constructor NPEs.
//
// `new GameMaker(info, null, false)` is explicitly supported: the null packet
// sink means no flatbuffers are written at all, so there is no `.bc23` file
// and no flatbuffers reader on either side of this port.
//
// Usage:
//   javac -nowarn -encoding UTF-8 -cp battlecode23-3.0.15.jar -d classes \
//         tools/oracle/bc23/Bc23Trace.java <bot>/RobotPlayer.java
//   java -Xmx2g -XX:+UseSerialGC \
//        -cp battlecode23-3.0.15.jar:classes \
//        battlecode.world.Bc23Trace <map> <rounds> <pkgA> <classesA> \
//                                   [<pkgB> <classesB>]
//
// The trace, one line per record:
//
//   R <round> T <A|B> ad=<n> mn=<n> ex=<n> isl=<n> anch=<n> anchheld=<n>
//   R <round> I <islandId> own=<0|1|2> hp=<n> anch=<STANDARD|ACCELERATING|->
//   R <round> W <wellIdx> ty=<AD|MN|EX> rate=<1|3> ad=<n> mn=<n> ex=<n>
//   R <round> M chk=<fnv1a64 of the per-tile per-team multiplier hundredths>
//   R <round> U <id> team=<A|B> ty=<TYPE> x=<n> y=<n> hp=<n> ad=<n> mn=<n>
//             ex=<n> anc=<n> acd=<n> mcd=<n> bc=<n>
//   R <round> S <A|B> arr=<fnv1a64 of the 64-slot shared array>
//   R <round> Z winner=<A|B|-> dom=<NAME|->
//
// Robots are printed IN EXEC ORDER, not id order; islands in ascending id.
// The `bc=` column is the Java bytecode counter; the comparison strips it and
// uses it only for the Tier A headroom assertion.
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
import java.util.HashMap;
import java.util.List;
import java.util.TreeSet;

public final class Bc23Trace {

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

    @SuppressWarnings("unchecked")
    static HashMap<Integer, Island> islands(GameWorld world) throws Exception {
        Field f = GameWorld.class.getDeclaredField("islandIdToIsland");
        f.setAccessible(true);
        return (HashMap<Integer, Island>) f.get(world);
    }

    static Well[] wells(GameWorld world) throws Exception {
        Field f = GameWorld.class.getDeclaredField("wells");
        f.setAccessible(true);
        return (Well[]) f.get(world);
    }

    static double[][] multipliers(GameWorld world) throws Exception {
        Field f = GameWorld.class.getDeclaredField("cooldownMultipliers");
        f.setAccessible(true);
        return (double[][]) f.get(world);
    }

    static long fnv(int[] values) {
        long h = 0xCBF29CE484222325L;
        for (int i = 0; i < values.length; i++) {
            h = (h ^ (values[i] & 0xFFFFFFFFL)) * 0x100000001B3L;
        }
        return h;
    }

    static String resourceLetters(ResourceType t) {
        if (t == ResourceType.ADAMANTIUM) return "AD";
        if (t == ResourceType.MANA) return "MN";
        if (t == ResourceType.ELIXIR) return "EX";
        return "-";
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
            System.err.println("usage: Bc23Trace <map> <rounds> <pkgA> "
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

        LiveMap map = GameMapIO.loadMapAsResource(
                Bc23Trace.class.getClassLoader(),
                "battlecode/world/resources", mapName, false);

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

        // Player stdout would otherwise interleave with the trace.
        PrintStream realOut = System.out;
        System.setOut(new PrintStream(new ByteArrayOutputStream()));

        GameWorld world = new GameWorld(map, provider, maker.getMatchMaker());
        TeamInfo ti = world.getTeamInfo();

        StringBuilder sb = new StringBuilder(1 << 20);
        int builtEver = 0;
        int alive = execOrder(world).size();
        int peakBytecodes = 0;
        int peakLimit = 1;
        int peakRound = -1;
        int peakId = -1;

        for (int round = 1; round <= rounds; round++) {
            GameState state = world.runRound();
            int cur = world.getCurrentRound();

            HashMap<Integer, Island> isl = islands(world);
            TreeSet<Integer> islandIds = new TreeSet<Integer>(isl.keySet());

            for (int ti2 = 0; ti2 <= 1; ti2++) {
                Team t = ti2 == 0 ? Team.A : Team.B;
                int held = 0;
                for (Integer id : islandIds) {
                    Island island = isl.get(id);
                    if (island != null && island.getTeam() == t) held++;
                }
                sb.append("R ").append(cur).append(" T ").append(teamLetter(t))
                  .append(" ad=").append(ti.getAdamantium(t))
                  .append(" mn=").append(ti.getMana(t))
                  .append(" ex=").append(ti.getElixir(t))
                  .append(" isl=").append(held)
                  .append(" anch=").append(ti.getAnchorsPlaced(t))
                  .append(" anchheld=").append(held)
                  .append('\n');
            }

            for (Integer id : islandIds) {
                Island island = isl.get(id);
                if (island == null) continue;
                Anchor a = island.getAnchor();
                sb.append("R ").append(cur).append(" I ").append(id.intValue())
                  .append(" own=").append(island.getTeamInt())
                  .append(" hp=").append(island.getHealth())
                  .append(" anch=").append(a == null ? "-" : a.name())
                  .append('\n');
            }

            Well[] ws = wells(world);
            for (int i = 0; i < ws.length; i++) {
                if (ws[i] == null) continue;
                sb.append("R ").append(cur).append(" W ").append(i)
                  .append(" ty=").append(resourceLetters(ws[i].getResourceType()))
                  .append(" rate=").append(ws[i].getRate())
                  .append(" ad=").append(ws[i].getResource(ResourceType.ADAMANTIUM))
                  .append(" mn=").append(ws[i].getResource(ResourceType.MANA))
                  .append(" ex=").append(ws[i].getResource(ResourceType.ELIXIR))
                  .append('\n');
            }

            // The multiplier checksum is what makes ONE wrong tempo tile
            // visible without printing 3600 tiles a round. It is folded in
            // INTEGER HUNDREDTHS, y ascending outer and x ascending inner,
            // exactly as `tempo.checksum` folds it on the Nim side.
            double[][] mult = multipliers(world);
            int width = map.getWidth();
            int height = map.getHeight();
            int[] flat = new int[width * height * 2];
            int k = 0;
            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                    int idx = x + y * width;
                    flat[k++] = ((int) Math.round(mult[idx][0] * 100.0)) & 0xFFFF;
                    flat[k++] = ((int) Math.round(mult[idx][1] * 100.0)) & 0xFFFF;
                }
            }
            sb.append("R ").append(cur).append(" M chk=")
              .append(Long.toHexString(fnv(flat)))
              .append('\n');

            for (InternalRobot r : execOrder(world)) {
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
                  .append(" x=").append(l == null ? -1 : l.x)
                  .append(" y=").append(l == null ? -1 : l.y)
                  .append(" hp=").append(r.getHealth())
                  .append(" ad=").append(r.getResource(ResourceType.ADAMANTIUM))
                  .append(" mn=").append(r.getResource(ResourceType.MANA))
                  .append(" ex=").append(r.getResource(ResourceType.ELIXIR))
                  .append(" anc=").append(r.getNumAnchors(Anchor.STANDARD)
                          + r.getNumAnchors(Anchor.ACCELERATING))
                  .append(" acd=").append(r.getActionCooldownTurns())
                  .append(" mcd=").append(r.getMovementCooldownTurns())
                  .append(" bc=").append(bc)
                  .append('\n');
            }

            for (int ti2 = 0; ti2 <= 1; ti2++) {
                Team t = ti2 == 0 ? Team.A : Team.B;
                int[] arr = new int[GameConstants.SHARED_ARRAY_LENGTH];
                for (int i = 0; i < arr.length; i++) {
                    arr[i] = ti.readSharedArray(t, i);
                }
                sb.append("R ").append(cur).append(" S ").append(teamLetter(t))
                  .append(" arr=").append(Long.toHexString(fnv(arr)))
                  .append('\n');
            }

            int now = execOrder(world).size();
            if (now > alive) builtEver += (now - alive);
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
        System.err.println("bc23-oracle map=" + mapName
                + " rounds=" + world.getCurrentRound()
                + " peak_bytecodes=" + peakBytecodes
                + " peak_limit=" + peakLimit
                + " peak_pct=" + (peakLimit == 0 ? 0
                        : (100 * peakBytecodes / peakLimit))
                + " peak_round=" + peakRound
                + " peak_id=" + peakId
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
