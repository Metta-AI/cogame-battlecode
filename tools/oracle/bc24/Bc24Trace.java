// The bc24 parity oracle's Java side: run the PUBLISHED engine headlessly and
// print one line per record from the live objects.
//
// CI-TIME ONLY. There is no JDK, no JRE and no Java in ANY runtime image
// stage; this file is compiled and run by the `parity-oracle-bc24` job of
// .github/workflows/ci.yml against the released `battlecode24-3.0.5.jar`
// (sha256 pinned in tools/oracle/bc24/jar.lock).
//
// It is `package battlecode.world;` so it needs NO reflection: it loads the
// map with `GameMapIO.loadMapAsResource`, builds a `TeamControlProvider` over
// two `PlayerControlProvider`s and calls `GameWorld.runRound()` in a loop.
//
// THREE THINGS THAT COST A RUN TO DISCOVER, WRITTEN DOWN:
//
//   * JDK 8 IS MANDATORY. The instrumenter rewrites `java.util` classes with
//     ASM 5.0.4, which refuses class-file versions above 52; under a newer JDK
//     every player class load throws and the match ends empty -- which is
//     exactly what a "green" oracle looks like when it is proving nothing.
//     This driver therefore FAILS LOUDLY if no duck ever spawns.
//   * THE PLAYER URL MUST BE THE COMPILED CLASSES DIRECTORY. An empty URL
//     fails class loading and the world constructor NPEs.
//   * `new GameMaker(info, null, false)` is explicitly supported: the null
//     packet sink means no flatbuffers are written at all.
//
// Usage:
//   javac -source 8 -target 8 -cp battlecode24-3.0.5.jar -d classes \
//         tools/oracle/bc24/Bc24Trace.java tools/oracle/bc24/Bc24Scenario.java \
//         examplefuncsplayer/RobotPlayer.java
//   java -cp battlecode24-3.0.5.jar:classes battlecode.world.Bc24Trace \
//        <map> <rounds> <package> <classesDir>
//
// Units are printed IN EXEC ORDER, not id order, which is what makes an
// ordering bug visible. The `bc=` column is the Java bytecode counter; the
// comparison strips it and uses it only for the Tier A headroom assertion.
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

public final class Bc24Trace {

    static String teamLetter(Team t) {
        return t == Team.A ? "A" : (t == Team.B ? "B" : "-");
    }

    @SuppressWarnings("unchecked")
    static List<InternalRobot> execOrder(GameWorld world) throws Exception {
        // `ObjectInfo.dynamicBodyExecOrder` is the engine's own turn order and
        // is private; reading it is the only way to print in that order, and
        // it is what makes an ordering bug visible at all.
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

    static String upgradeMask(TeamInfo ti, Team t) {
        boolean[] u = ti.getGlobalUpgrades(t);
        return "" + (u[0] ? 1 : 0) + (u[1] ? 1 : 0) + (u[2] ? 1 : 0);
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 4) {
            System.err.println("usage: Bc24Trace <map> <rounds> <package> <classesDir>");
            System.exit(2);
        }
        final String mapName = args[0];
        final int rounds = Integer.parseInt(args[1]);
        final String pkg = args[2];
        final String classes = new File(args[3]).getAbsolutePath();

        LiveMap map = GameMapIO.loadMapAsResource(
                Bc24Trace.class.getClassLoader(),
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
        int spawnedEver = 0;
        int peakBytecodes = 0;
        int peakRound = -1;
        int peakId = -1;

        for (int round = 1; round <= rounds; round++) {
            GameState state = world.runRound();
            int cur = world.getCurrentRound();
            for (Team t : new Team[]{Team.A, Team.B}) {
                sb.append("R ").append(cur).append(" T ").append(teamLetter(t))
                  .append(" crumbs=").append(ti.getBread(t))
                  .append(" caps=").append(ti.getFlagsCaptured(t))
                  .append(" picked=").append(ti.getFlagsPickedUp(t))
                  .append(" lvl=").append(ti.getLevelSum(t))
                  .append(" alive=").append(aliveCount(world, t))
                  .append(" up=").append(upgradeMask(ti, t))
                  .append(" upp=").append(ti.getGlobalUpgradePoints(t))
                  .append('\n');
            }
            for (InternalRobot r : execOrder(world)) {
                boolean sp = r.isSpawned();
                if (sp) spawnedEver++;
                MapLocation l = r.getLocation();
                int bc = r.getBytecodesUsed();
                if (bc > peakBytecodes) {
                    peakBytecodes = bc;
                    peakRound = cur;
                    peakId = r.getID();
                }
                sb.append("R ").append(cur).append(" U ").append(r.getID())
                  .append(" team=").append(teamLetter(r.getTeam()))
                  .append(" sp=").append(sp ? 1 : 0)
                  .append(" x=").append(sp ? l.x : -1)
                  .append(" y=").append(sp ? l.y : -1)
                  .append(" hp=").append(r.getHealth())
                  .append(" acd=").append(r.getActionCooldownTurns())
                  .append(" mcd=").append(r.getMovementCooldownTurns())
                  .append(" ax=").append(r.getExp(SkillType.ATTACK))
                  .append(" bx=").append(r.getExp(SkillType.BUILD))
                  .append(" hx=").append(r.getExp(SkillType.HEAL))
                  .append(" flag=").append(r.hasFlag() ? r.getFlag().getId() : -1)
                  .append(" ra=").append(r.getRoundsAlive())
                  .append(" bc=").append(bc)
                  .append('\n');
            }
            for (Flag f : world.getAllFlags()) {
                sb.append("R ").append(cur).append(" F ").append(f.getId())
                  .append(" team=").append(teamLetter(f.getTeam()))
                  .append(" x=").append(f.getLoc().x)
                  .append(" y=").append(f.getLoc().y)
                  .append(" start=").append(f.getLoc() == f.getStartLoc() ? 1 : 0)
                  .append(" carried=")
                  .append(f.isPickedUp() ? f.getCarryingRobot().getID() : -1)
                  .append(" dropped=").append(f.getDroppedRounds())
                  .append('\n');
            }
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
        System.err.println("bc24-oracle map=" + mapName
                + " rounds=" + world.getCurrentRound()
                + " peak_bytecodes=" + peakBytecodes
                + " peak_round=" + peakRound
                + " peak_id=" + peakId
                + " limit=" + GameConstants.BYTECODE_LIMIT);
        if (spawnedEver == 0) {
            System.err.println("::error::no duck was ever spawned: the "
                    + "instrumenter almost certainly refused the player "
                    + "classes (JDK 8 is mandatory)");
            System.exit(3);
        }
    }

    static int aliveCount(GameWorld world, Team t) throws Exception {
        int n = 0;
        for (InternalRobot r : execOrder(world)) {
            if (r.getTeam() == t && r.isSpawned()) n++;
        }
        return n;
    }
}
