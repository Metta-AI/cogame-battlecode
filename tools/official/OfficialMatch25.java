package battlecode.world;

import battlecode.common.Team;
import battlecode.server.GameInfo;
import battlecode.world.control.PlayerControlProvider;
import battlecode.world.control.TeamControlProvider;
import java.io.OutputStream;

public final class OfficialMatch25 extends OfficialMatch {
    GameInfo gameInfo(String map, String a, String aClasses, String b, String bClasses) {
        return new GameInfo(a, a, aClasses, b, b, bClasses, new String[]{map}, null, false);
    }

    TeamControlProvider players(String a, String aClasses, OutputStream aLog,
                                String b, String bClasses, OutputStream bLog) {
        TeamControlProvider players = new TeamControlProvider();
        players.registerControlProvider(Team.A, new PlayerControlProvider(Team.A, a, aClasses, aLog, false));
        players.registerControlProvider(Team.B, new PlayerControlProvider(Team.B, b, bClasses, bLog, false));
        return players;
    }

    String economy(GameWorld world) {
        TeamInfo t = world.getTeamInfo();
        return "[[" + t.getMoney(Team.A) + "," + t.getNumberOfPaintedSquares(Team.A)
                + "],[" + t.getMoney(Team.B) + "," + t.getNumberOfPaintedSquares(Team.B) + "]]";
    }

    public static void main(String[] args) throws Exception {
        new OfficialMatch25().run(args);
    }
}
