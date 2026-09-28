// Observation-only wrapper around the published engine. Player execution,
// scheduling, bytecode instrumentation, rules, and winner selection are upstream.
package battlecode.world;

import battlecode.common.Team;
import battlecode.server.GameInfo;
import battlecode.server.GameMaker;
import battlecode.server.GameState;
import battlecode.world.control.TeamControlProvider;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Path;

public abstract class OfficialMatch {
    abstract GameInfo gameInfo(String map, String a, String aClasses, String b, String bClasses);
    abstract TeamControlProvider players(String a, String aClasses, OutputStream aLog,
                                         String b, String bClasses, OutputStream bLog);
    abstract String economy(GameWorld world);

    final void run(String[] args) throws Exception {
        String mapName = args[0];
        Path output = Path.of(args[5]);
        Files.createDirectories(output);
        LiveMap map = GameMapIO.loadMapAsResource(getClass().getClassLoader(),
                "battlecode/world/resources", mapName, false);
        GameMaker maker = new GameMaker(gameInfo(mapName, args[1], args[2], args[3], args[4]), null, false);
        maker.makeGameHeader();
        // Private bot logs go to their own files, never to public protocol stdout.
        System.setOut(new PrintStream(OutputStream.nullOutputStream()));
        try (OutputStream aLog = Files.newOutputStream(output.resolve("seat-0.log"));
             OutputStream bLog = Files.newOutputStream(output.resolve("seat-1.log"));
             PrintStream trace = new PrintStream(Files.newOutputStream(output.resolve("frames.jsonl")))) {
            GameWorld world = new GameWorld(map, players(args[1], args[2], aLog, args[3], args[4], bLog),
                                            maker.getMatchMaker());
            long[] bytecodes = new long[2];
            while (world.runRound() != GameState.DONE) {
                StringBuilder robots = new StringBuilder();
                world.getObjectInfo().eachRobot(r -> {
                    if (robots.length() > 0) robots.append(',');
                    robots.append('[').append(r.getID()).append(",\"").append(r.getTeam())
                          .append("\",\"").append(r.getType()).append("\",")
                          .append(r.getLocation().x).append(',').append(r.getLocation().y)
                          .append(',').append(r.getHealth()).append(']');
                    if (r.getTeam().isPlayer()) bytecodes[r.getTeam().ordinal()] += r.getBytecodesUsed();
                    return true;
                });
                trace.println("{\"round\":" + world.getCurrentRound() + ",\"robots\":[" + robots
                        + "],\"economy\":" + economy(world) + "}");
            }
            if (world.getCurrentRound() <= 1 || bytecodes[0] == 0 || bytecodes[1] == 0) {
                throw new IllegalStateException("No meaningful player execution; inspect seat logs and JDK instrumentation");
            }
            Team winner = world.getWinner();
            if (!winner.isPlayer()) throw new IllegalStateException("Engine did not select a player winner");
            maker.makeGameFooter(winner);
            maker.writeGame(output.resolve("official.bc" + args[6]).toFile());
            Files.writeString(output.resolve("result.json"),
                    "{\"winner\":\"" + winner + "\",\"rounds\":" + world.getCurrentRound()
                    + ",\"reason\":\"" + world.getGameStats().getDominationFactor()
                    + "\",\"width\":" + map.getWidth() + ",\"height\":" + map.getHeight()
                    + ",\"bytecodes\":[" + bytecodes[0] + "," + bytecodes[1] + "]}\n");
        }
    }
}
