// The bc21 PARITY ORACLE's Java side: a headless driver that runs the engine's
// own round loop and prints a trace FROM THE LIVE OBJECTS.
//
// CI-TIME ONLY. There is no JDK, no JRE and no Java in any image stage; this
// file is compiled and run by the `parity-oracle-bc21` job of
// .github/workflows/ci.yml and nowhere else. The engine's own sources are
// byte-for-byte UNMODIFIED; this is one extra file on the classpath.
//
// WHY NOT READ THE .bc21? Because the flatbuffer carries what a REPLAY needs,
// not what a parity trace needs: cooldowns, flags, bids, buff counts and
// bytecodes-used exist only on the live `InternalRobot`. Driving `GameWorld`
// directly also means no flatbuffers reader, no `flatc` and no `pip install`
// on either side of the diff.
//
// `package battlecode.world;` so it can see the package-private state without
// reflection.
//
//   java -cp <jars>:classes battlecode.world.Bc21Trace <map> <rounds> [<pkg>]
//
// The trace, one line per record:
//
//   R <round> T <team> votes=<n> buffs=<n> ecs=<n> infl=<n> pol=<n> sla=<n>
//              muc=<n> topbid=<n> bidder=<id>
//   R <round> U <id> t=<TYPE> team=<A|B|N> x=<n> y=<n> inf=<n> conv=<n>
//              cd=<%.9f> flag=<n> bid=<n> ra=<n> bc=<n>
//   R <round> W winner=<A|B|-> dom=<NAME|->
//
// Units are printed in EXEC ORDER, not id order, which is what makes an
// ordering bug visible.
package battlecode.world;

import battlecode.common.GameConstants;
import battlecode.common.RobotType;
import battlecode.common.Team;
import battlecode.server.GameInfo;
import battlecode.server.GameMaker;
import battlecode.server.GameState;
import battlecode.world.control.NullControlProvider;
import battlecode.world.control.PlayerControlProvider;
import battlecode.world.control.TeamControlProvider;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.util.ArrayList;
import java.util.List;

public final class Bc21Trace {

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("usage: Bc21Trace <map> <rounds> [<player package>] [<player url>]");
            System.exit(2);
        }
        final String mapName = args[0];
        final int rounds = Integer.parseInt(args[1]);
        final String pkg = args.length > 2 ? args[2] : "examplefuncsplayer21";
        final String url = args.length > 3 ? args[3] : "";

        LiveMap map = GameMapIO.loadMapAsResource(
                Bc21Trace.class.getClassLoader(),
                "battlecode/world/resources", mapName);

        TeamControlProvider provider = new TeamControlProvider();
        ByteArrayOutputStream sink = new ByteArrayOutputStream();
        provider.registerControlProvider(Team.A,
                new PlayerControlProvider(Team.A, pkg, url, sink, false));
        provider.registerControlProvider(Team.B,
                new PlayerControlProvider(Team.B, pkg, url, sink, false));
        // `Server.setupWorld` registers this too, and every map with a NEUTRAL
        // Enlightenment Center needs it: `TeamControlProvider.robotSpawned`
        // dereferences the map entry, so without it the world's constructor
        // NPEs the moment it places the first neutral Centre.
        provider.registerControlProvider(Team.NEUTRAL, new NullControlProvider());

        GameInfo info = new GameInfo("A", pkg, url, "B", pkg, url,
                new String[] { mapName }, (File) null, false);
        // `null` is an explicitly supported packet sink: GameMaker.createEvent
        // guards on it, so no NetServer and no websocket are involved.
        GameMaker maker = new GameMaker(info, null, false);
        maker.makeGameHeader();

        GameWorld world = new GameWorld(map, provider, maker.getMatchMaker());

        StringBuilder out = new StringBuilder(1 << 20);
        int maxBytecodePct = 0;
        int robotsAt50 = -1;
        int firstCutoffRound = -1;
        String firstCutoffWho = "-";
        for (int round = 1; round <= rounds; round++) {
            GameState state = world.runRound();
            emitRound(world, out);
            if (round == 50) {
                robotsAt50 = world.getObjectInfo().getRobotCount(Team.A)
                        + world.getObjectInfo().getRobotCount(Team.B);
            }
            for (InternalRobot robot : world.getObjectInfo().robotsArray()) {
                int limit = robot.getType().bytecodeLimit;
                int used = robot.getBytecodesUsed();
                int pct = limit > 0 ? (used * 100) / limit : 0;
                if (pct > maxBytecodePct) maxBytecodePct = pct;
                if (used > limit && firstCutoffRound < 0) {
                    firstCutoffRound = round;
                    firstCutoffWho = robot.getType() + "#" + robot.getID()
                            + " used " + used + " of " + limit;
                }
            }
            if (state == GameState.DONE) break;
        }
        System.out.print(out);

        // (1) THE ASSERTION THAT STOPS A "GREEN" ORACLE PROVING NOTHING.
        //     Under the wrong JDK the match is EMPTY: the instrumenter rewrites
        //     java.util classes with ASM 5.0.4, which refuses class-file
        //     versions above 52, so under JDK 21 every player class load throws
        //     IllegalArgumentException from ClassReader and the match silently
        //     ends in a coin flip on round 1500 with two robots on the board.
        //     That is exactly what a green oracle looks like when it is proving
        //     nothing.
        //
        // (2) THE TIER-A BOUNDARY, reported rather than asserted.
        //     `examplefuncsplayer21`'s Enlightenment Center eventually spends
        //     its last influence, lets `rc.bid(1)` throw, and pays more than
        //     its whole 20 000-bytecode budget for the uncaught exception's
        //     stack trace. The JVM's instrumenter PAUSES it mid-turn and
        //     resumes it on the next round, so it consumes one fewer
        //     `RNG.nextDouble()` than a port that has no bytecode counter BY
        //     DESIGN (docs/RULES-BC21.md section Divergences item 1) and completes
        //     the turn. From that round on the two RNG streams are one draw
        //     apart and a bit-exact comparison is no longer DEFINED, never
        //     mind achievable. The job reads `BC21_FIRST_CUTOFF` and makes it
        //     the Tier A window; Tier C's ledger records what happens after.
        System.err.println("bc21 oracle " + mapName + ": robots at round 50 = "
                + robotsAt50 + ", peak bytecode use = " + maxBytecodePct + "%");
        System.err.println("BC21_FIRST_CUTOFF " + firstCutoffRound + " "
                + firstCutoffWho);
        if (robotsAt50 >= 0 && robotsAt50 <= 2) {
            System.err.println("::error::bc21 oracle " + mapName + ": only "
                    + robotsAt50 + " robots at round 50 - the players never ran "
                    + "(wrong JDK? the instrumenter needs class-file version <= 52)");
            System.exit(3);
        }
        // EXPLICIT, and not a nicety: every sandboxed robot runs on its own
        // NON-DAEMON thread, parked in `RobotMonitor.pause()`. Returning from
        // main leaves the JVM waiting on hundreds of them for ever, which on a
        // CI runner reads as "the oracle hung" rather than "the oracle
        // finished".
        System.out.flush();
        System.exit(0);
    }

    private static char teamChar(Team team) {
        if (team == Team.A) return 'A';
        if (team == Team.B) return 'B';
        return 'N';
    }

    private static void emitRound(GameWorld world, StringBuilder out) {
        final int round = world.getCurrentRound();
        final ObjectInfo objects = world.getObjectInfo();
        final TeamInfo teams = world.getTeamInfo();

        for (int t = 0; t < 2; t++) {
            final Team team = Team.values()[t];
            int ecs = 0, infl = 0, pol = 0, sla = 0, muc = 0;
            int topBid = 0, bidder = -1;
            InternalRobot best = null;
            for (InternalRobot robot : objects.robotsArray()) {
                if (robot.getTeam() != team) continue;
                infl += robot.getInfluence();
                switch (robot.getType()) {
                    case ENLIGHTENMENT_CENTER: ecs++; break;
                    case POLITICIAN: pol++; break;
                    case SLANDERER: sla++; break;
                    case MUCKRAKER: muc++; break;
                    default: break;
                }
                if (robot.getType() == RobotType.ENLIGHTENMENT_CENTER) {
                    int bid = robot.getBid();
                    if (best == null || bid > topBid
                            || (bid == topBid && robot.compareTo(best) < 0)) {
                        topBid = bid;
                        best = robot;
                    }
                }
            }
            if (best != null) bidder = best.getID();
            out.append("R ").append(round).append(" T ").append(teamChar(team))
               .append(" votes=").append(teams.getVotes(team))
               .append(" buffs=").append(teams.getNumBuffs(team, round))
               .append(" ecs=").append(ecs)
               .append(" infl=").append(infl)
               .append(" pol=").append(pol)
               .append(" sla=").append(sla)
               .append(" muc=").append(muc)
               .append(" topbid=").append(topBid)
               .append(" bidder=").append(bidder)
               .append('\n');
        }

        // EXEC ORDER, not id order.
        final List<InternalRobot> ordered = new ArrayList<>();
        objects.eachDynamicBodyByExecOrder((robot) -> {
            ordered.add(robot);
            return true;
        });
        for (InternalRobot robot : ordered) {
            out.append("R ").append(round).append(" U ").append(robot.getID())
               .append(" t=").append(robot.getType())
               .append(" team=").append(teamChar(robot.getTeam()))
               .append(" x=").append(robot.getLocation().x)
               .append(" y=").append(robot.getLocation().y)
               .append(" inf=").append(robot.getInfluence())
               .append(" conv=").append(robot.getConviction())
               .append(" cd=").append(String.format("%.9f", robot.getCooldownTurns()))
               .append(" flag=").append(robot.getFlag())
               .append(" bid=").append(robot.getBid())
               .append(" ra=").append(robot.getRoundsAlive())
               .append(" bc=").append(robot.getBytecodesUsed())
               .append('\n');
        }

        final Team winner = world.getWinner();
        out.append("R ").append(round).append(" W winner=")
           .append(winner == null ? "-" : String.valueOf(teamChar(winner)))
           .append(" dom=")
           .append(world.getGameStats().getDominationFactor() == null
                   ? "-" : world.getGameStats().getDominationFactor().name())
           .append('\n');
        if (round >= GameConstants.GAME_MAX_NUMBER_OF_ROUNDS) {
            // Nothing: the loop's own bound stops it.
        }
    }
}
