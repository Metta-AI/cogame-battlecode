package battlecode.world;

import battlecode.common.Team;
import battlecode.crossplay.CrossPlayLanguage;
import battlecode.server.GameInfo;
import battlecode.world.control.NullControlProvider;
import battlecode.world.control.PlayerControlProvider;
import battlecode.world.control.TeamControlProvider;
import java.io.OutputStream;

public final class OfficialMatch26 extends OfficialMatch {
    GameInfo gameInfo(String map, String a, String aClasses, String b, String bClasses) {
        return new GameInfo(a, CrossPlayLanguage.JAVA, a, aClasses, b, CrossPlayLanguage.JAVA,
                            b, bClasses, new String[]{map}, null, false);
    }

    TeamControlProvider players(String a, String aClasses, OutputStream aLog,
                                String b, String bClasses, OutputStream bLog) {
        TeamControlProvider players = new TeamControlProvider();
        players.registerControlProvider(Team.A, new PlayerControlProvider(Team.A, a, CrossPlayLanguage.JAVA,
                null, aClasses, aLog, false));
        players.registerControlProvider(Team.B, new PlayerControlProvider(Team.B, b, CrossPlayLanguage.JAVA,
                null, bClasses, bLog, false));
        players.registerControlProvider(Team.NEUTRAL, new NullControlProvider());
        return players;
    }

    String economy(GameWorld world) {
        TeamInfo t = world.getTeamInfo();
        return "[[" + t.getCheese(Team.A) + "," + t.getPoints(Team.A) + "," + t.getNumRatKings(Team.A)
                + "],[" + t.getCheese(Team.B) + "," + t.getPoints(Team.B) + "," + t.getNumRatKings(Team.B) + "]]";
    }

    public static void main(String[] args) throws Exception {
        new OfficialMatch26().run(args);
    }
}
