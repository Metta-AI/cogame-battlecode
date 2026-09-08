// The bc25 parity oracle's Java side: run the PUBLISHED engine headlessly and
// print one line per record from the live objects.
//
// CI-TIME ONLY. There is no JDK, no JRE and no Java in ANY runtime image
// stage; this file is compiled and run by the `parity-oracle-bc25` job of
// .github/workflows/ci.yml against the released `battlecode25-java-3.1.0.jar`
// (sha256 pinned in tools/oracle/bc25/jar.lock).
//
// It is `package battlecode.world;` so it needs NO reflection except for
// `ObjectInfo.dynamicBodyExecOrder`, which is private and is the only way to
// print in exec order -- and printing in exec order is what makes an ordering
// bug visible at all.
//
// FOUR THINGS THAT WOULD OTHERWISE COST A CI ROUND, WRITTEN DOWN:
//
//   * `--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED` IS MANDATORY on
//     every `java` invocation. Without it the instrumented `java.util.Random`
//     class fails its static initialiser with
//         IllegalAccessError: class instrumented.java.util.Random ... cannot
//         access class jdk.internal.misc.Unsafe
//     EVERY player class load throws, all four starting towers die by
//     exception on round 1, and the game ends at round 1 with
//     DESTROY_ALL_UNITS and a four-line trace. The job exits 0 and the diff is
//     empty. THAT IS THE "green oracle proving nothing" TRAP, and this driver
//     therefore FAILS LOUDLY (exit 3) IF NO ROBOT IS EVER BUILT.
//   * JDK 21, and `javac` with NO `--release`, NO `-source`, NO `-target`:
//     the engine's build.gradle sets VERSION_21 and hard-fails below it, and
//     the instrumenter uses ASM 9.7.1, which is happy with class-file
//     version 65. The bc21 lesson ("match javac flags to the JDK") is
//     discharged by using none at all.
//   * THE PLAYER URL MUST BE THE COMPILED CLASSES DIRECTORY. An empty URL
//     fails class loading and the world constructor NPEs.
//   * `new GameMaker(info, null, false)` is explicitly supported: the null
//     packet sink means no flatbuffers are written at all.
//
// Usage:
//   javac -nowarn -encoding UTF-8 -cp battlecode25-java-3.1.0.jar -d classes \
//         tools/oracle/bc25/Bc25Trace.java examplefuncsplayer/RobotPlayer.java
//   java -Xmx2g -XX:+UseSerialGC \
//        --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
//        -cp battlecode25-java-3.1.0.jar:classes \
//        battlecode.world.Bc25Trace <map> <rounds> <package> <classesDir>
//
// The trace, one line per record:
//
//   R <round> T <A|B> money=<n> painted=<n> towers=<n> bots=<n>
//             paintunits=<n> srp=<n>
//   R <round> M chk=<fnv1a64 of the colour array> mk=<fnv1a64 of both markers>
//   R <round> P <centerIdx> team=<A|B> life=<n>
//   R <round> U <id> team=<A|B> ty=<UnitType> x=<n> y=<n> hp=<n> pnt=<n>
//             acd=<n> mcd=<n> ra=<n> bc=<n>
//   R <round> W winner=<A|B|-> dom=<NAME|->
//
// Units are printed IN EXEC ORDER. The `bc=` column is the Java bytecode
// counter; the comparison strips it and uses it only for the Tier A headroom
// assertion.
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

public final class Bc25Trace {

    static String teamLetter(Team t) {
        return t == Team.A ? "A" : (t == Team.B ? "B" : "-");
    }

    @SuppressWarnings("unchecked")
    static List<InternalRobot> execOrder(GameWorld world) throws Exception {
        ObjectInfo info = world.getObjectInfo();
        Field f = ObjectInfo.class.getDeclaredField("dynamicBodyExecOrder");
        f.setAccessible(true);
        gnu.trove.list.array.TIntArrayList order =
                (gnu.trove.list.array.TIntArrayList) f.get(info);
        List<InternalRobot> out = new ArrayList<>();
        int[] ids = order.toArray();
        for (int id : ids) {
            InternalRobot r = info.getRobotByID(id);
            if (r != null) out.add(r);
        }
        return out;
    }

    static int[] colourArray(GameWorld world) throws Exception {
        Field f = GameWorld.class.getDeclaredField("colorLocations");
        f.setAccessible(true);
        return (int[]) f.get(world);
    }

    static int[] markerArray(GameWorld world, Team t) {
        return world.getmarkersArray(t);
    }

    static long fnv(int[] values) {
        long h = 0xCBF29CE484222325L;
        for (int v : values) {
            h = (h ^ (v & 0xFFFFFFFFL)) * 0x100000001B3L;
        }
        return h;
    }

    /** The SRP registry, in the engine's own list order. */
    @SuppressWarnings("unchecked")
    static List<MapLocation> srpCentres(GameWorld world) throws Exception {
        Field f = GameWorld.class.getDeclaredField("resourcePatternCenters");
        f.setAccessible(true);
        return (java.util.ArrayList<MapLocation>) f.get(world);
    }

    static Team[] srpTeams(GameWorld world) throws Exception {
        Field f = GameWorld.class.getDeclaredField("resourcePatternCentersByLoc");
        f.setAccessible(true);
        return (Team[]) f.get(world);
    }

    static int[] srpLifetimes(GameWorld world) throws Exception {
        Field f = GameWorld.class.getDeclaredField("resourcePatternLifetimes");
        f.setAccessible(true);
        return (int[]) f.get(world);
    }

    static int countType(GameWorld world, Team t, boolean towers) {
        int n = 0;
        for (UnitType type : UnitType.values()) {
            if (towers == type.isTowerType()) {
                n += world.getObjectInfo().getRobotTypeCount(t, type);
            }
        }
        return n;
    }

    static int paintInUnits(GameWorld world, Team t) throws Exception {
        int n = 0;
        for (InternalRobot r : execOrder(world)) {
            if (r.getTeam() == t) n += r.getPaint();
        }
        return n;
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.err.println("usage: Bc25Trace <map> <rounds> <package> <classesDir>");
            System.exit(2);
        }
        final String mapName = args[0];
        final int rounds = Integer.parseInt(args[1]);
        final String pkg = args[2];
        final String classes = new File(args[3]).getAbsolutePath();

        LiveMap map = GameMapIO.loadMapAsResource(
                Bc25Trace.class.getClassLoader(),
                "battlecode/world/resources", mapName, false);

        GameInfo info = new GameInfo("A", pkg, classes, "B", pkg, classes,
                new String[]{mapName}, null, false);
        GameMaker maker = new GameMaker(info, null, false);
        maker.makeGameHeader();

        ByteArrayOutputStream robotOut = new ByteArrayOutputStream();
        TeamControlProvider provider = new TeamControlProvider();
        provider.registerControlProvider(Team.A,
                new PlayerControlProvider(Team.A, pkg, classes, robotOut, false));
        provider.registerControlProvider(Team.B,
                new PlayerControlProvider(Team.B, pkg, classes, robotOut, false));

        // Player stdout would otherwise interleave with the trace.
        PrintStream realOut = System.out;
        System.setOut(new PrintStream(new ByteArrayOutputStream()));

        GameWorld world = new GameWorld(map, provider, maker.getMatchMaker());
        TeamInfo ti = world.getTeamInfo();

        StringBuilder sb = new StringBuilder(1 << 20);
        int builtEver = 0;
        int startingUnits = execOrder(world).size();
        int peakBytecodes = 0;
        int peakRound = -1;
        int peakId = -1;
        int peakLimit = GameConstants.ROBOT_BYTECODE_LIMIT;

        for (int round = 1; round <= rounds; round++) {
            GameState state = world.runRound();
            int cur = world.getCurrentRound();

            for (Team t : new Team[]{Team.A, Team.B}) {
                sb.append("R ").append(cur).append(" T ").append(teamLetter(t))
                  .append(" money=").append(ti.getMoney(t))
                  .append(" painted=").append(ti.getNumberOfPaintedSquares(t))
                  .append(" towers=").append(countType(world, t, true))
                  .append(" bots=").append(countType(world, t, false))
                  .append(" paintunits=").append(paintInUnits(world, t))
                  .append(" srp=").append(world.getNumResourcePatterns(t))
                  .append('\n');
            }

            // The paint checksum is what makes ONE mispainted tile visible
            // without printing 3600 tiles a round.
            int[] markersA = markerArray(world, Team.A);
            int[] markersB = markerArray(world, Team.B);
            int[] both = new int[markersA.length + markersB.length];
            System.arraycopy(markersA, 0, both, 0, markersA.length);
            System.arraycopy(markersB, 0, both, markersA.length, markersB.length);
            sb.append("R ").append(cur).append(" M chk=")
              .append(Long.toUnsignedString(fnv(colourArray(world)), 16))
              .append(" mk=")
              .append(Long.toUnsignedString(fnv(both), 16))
              .append('\n');

            List<MapLocation> centres = srpCentres(world);
            Team[] centreTeams = srpTeams(world);
            int[] lifetimes = srpLifetimes(world);
            for (MapLocation c : centres) {
                int idx = world.locationToIndex(c);
                sb.append("R ").append(cur).append(" P ").append(idx)
                  .append(" team=").append(teamLetter(centreTeams[idx]))
                  .append(" life=").append(lifetimes[idx])
                  .append('\n');
            }

            for (InternalRobot r : execOrder(world)) {
                MapLocation l = r.getLocation();
                int bc = r.getBytecodesUsed();
                int limit = r.getType().isRobotType()
                        ? GameConstants.ROBOT_BYTECODE_LIMIT
                        : GameConstants.TOWER_BYTECODE_LIMIT;
                if (bc * peakLimit > peakBytecodes * limit) {
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
                  .append(" pnt=").append(r.getPaint())
                  .append(" acd=").append(r.getActionCooldownTurns())
                  .append(" mcd=").append(r.getMovementCooldownTurns())
                  .append(" ra=").append(r.getRoundsAlive())
                  .append(" bc=").append(bc)
                  .append('\n');
            }

            int now = execOrder(world).size();
            if (now > startingUnits) builtEver += (now - startingUnits);
            startingUnits = now;

            if (sb.length() > (1 << 22)) {
                realOut.print(sb);
                sb.setLength(0);
            }
            if (state == GameState.DONE || !world.isRunning()) break;
        }

        Team winner = world.getWinner();
        sb.append("R ").append(world.getCurrentRound()).append(" W winner=")
          .append(winner == null ? "-" : teamLetter(winner))
          .append(" dom=")
          .append(world.getGameStats().getDominationFactor() == null ? "-"
                  : world.getGameStats().getDominationFactor().name())
          .append('\n');
        realOut.print(sb);
        realOut.flush();

        System.setOut(realOut);
        System.err.println("bc25-oracle map=" + mapName
                + " rounds=" + world.getCurrentRound()
                + " peak_bytecodes=" + peakBytecodes
                + " peak_limit=" + peakLimit
                + " peak_pct=" + (peakLimit == 0 ? 0 : (100 * peakBytecodes / peakLimit))
                + " peak_round=" + peakRound
                + " peak_id=" + peakId
                + " built=" + builtEver);
        if (builtEver == 0) {
            System.err.println("::error::no robot was ever built: the "
                    + "instrumenter almost certainly refused the player "
                    + "classes. --add-opens=java.base/jdk.internal.misc="
                    + "ALL-UNNAMED is MANDATORY on every java invocation; "
                    + "without it every player class load throws, the four "
                    + "starting towers die on round 1, and this oracle would "
                    + "be green while proving nothing.");
            System.exit(3);
        }
    }
}
