// The bc16 parity oracle's Java side: run the PUBLISHED 2016 engine headlessly
// and print one line per record from the LIVE OBJECTS.
//
// CI-TIME ONLY. There is no JDK, no JRE and no Java in ANY runtime image
// stage; this file is compiled and run by the `parity-oracle-bc16` job of
// .github/workflows/ci.yml against the released `battlecode-2016.0.2.2.jar`
// (sha256 AND size pinned in tools/oracle/bc16/jar.lock).
//
// It is `package battlecode.world;` so it needs reflection only for
// `GameWorld.rubble` / `parts` / `gameObjectsByID` / `rand` (all private --
// the only way to checksum the two map arrays, print in exec order and read
// the RNG state) and `ZombieControlProvider.random`.
//
// FIVE THINGS THAT WERE MEASURED AND WOULD OTHERWISE EACH COST A CI ROUND:
//
//   * TEMURIN 8, AND IT IS NOT NEGOTIABLE. The jar bundles a 2016-era ASM and
//     a 2016-era XStream and the whole instrumenter is built for Java 8 class
//     files. The bc22 and bc23 runs both measured the failure mode on a
//     modern JDK -- `java.lang.IllegalArgumentException` inside
//     `org.objectweb.asm.ClassReader.<init>` on EVERY player class load, no
//     robot ever built, the game over in one round, AND THE JOB EXITING 0 --
//     and 2016's ASM is older still. This driver therefore EXITS 3 IF NOTHING
//     EVER HAPPENED.
//   * `javac` WITH NO `--release`, NO `-source`, NO `-target`. `--release`
//     arrived in JDK 9 and dies with "invalid flag" on a JDK-8 javac in
//     seconds (the bc21 lesson). The compiler IS 8, so the target is 8.
//   * THE DRIVER MUST CALL `System.exit()`. The sandboxed player threads are
//     NON-DAEMON: a driver that returns or throws without it hangs for ever.
//     Every `java` invocation in the job is also wrapped in `timeout 900`.
//   * **NEUTRALS MUST BE REGISTERED TO A `NullControlProvider`, NOT TO THE
//     ZOMBIE ONE.** `TeamControlProvider` asserts a provider for every team it
//     is asked about, and a NEUTRAL robot's `runRobot` reaches
//     `ZombieControlProvider`'s "somehow controlling a non-zombie robot -> kill
//     it" branch, which would delete every neutral on the board on round 0.
//     `world/control/NullControlProvider.java` exists for exactly this.
//   * `GameMapIO.loadMap(name, null)` is the RESOURCE FALLBACK path
//     (`GameMapIO.java:56-61`) -- the jar carries 54 `.xml` map resources and
//     every pool map is one of them, so this job needs NO `--map-dir`.
//
// The trace, one line per record. All coordinates are ORIGIN-RELATIVE on both
// sides (V3): the Java side subtracts `map.getOrigin()` here, so neither
// emitter can create or hide a divergence with a translation.
//
//   R <round> T <A|B> parts=<%.6f> ar=<n> sc=<n> so=<n> gu=<n> vi=<n> tu=<n> tt=<n>
//   R <round> Z zn=<n> zs=<n> zr=<n> zf=<n> zb=<n> dens=<n> neu=<n> outbreak=<n>
//   R <round> G rubblechk=<fnv1a64> partschk=<fnv1a64>
//             rubblesum=<float64 BITS in hex> partssum=<float64 BITS in hex>
//
// **THE TWO SUMS ARE PRINTED AS RAW IEEE-754 BIT PATTERNS AND NOT AS
// DECIMALS, AND THAT IS MEASURED RATHER THAN fastidious.** `%.6f` rounds
// HALF-UP in `java.lang.String.format` and HALF-TO-EVEN in C's `printf`,
// which is what Nim's `formatFloat` calls. A 900-term sum lands on an exact
// decimal tie often enough that it happened: on `checkers` at round 219 the
// two sides held BYTE-IDENTICAL rubble arrays and printed
// `88935.090413` against `88935.090412`. Bit patterns have no rounding mode.
//   R <round> U <id> team=<A|B|N|Z> ty=<TYPE> x=<n> y=<n> hp=<%.6f> cd=<%.6f>
//             wd=<%.6f> zi=<n> vi=<n> ra=<n> bd=<n> bc=<n>
//   R <round> D <id> x=<n> y=<n> hp=<%.6f> q=<s>:<r>:<f>:<b>
//   R <round> X world=<48-bit hex> zombie=<48-bit hex> idgen=<48-bit hex>
//   R <round> W winner=<A|B|-> dom=<NAME|->
//
// Robots are printed IN EXEC ORDER (the `LinkedHashMap`'s own iteration), not
// id order, which is what makes an ordering bug visible at all. **The `X` line
// is bc16's own addition and it is the most valuable line in the trace**: it
// carries ALL THREE `java.util.Random` states EVERY ROUND, so a single missed
// or extra `nextInt`/`nextBoolean` (D2b/D2c) surfaces on the round it happens
// instead of as a mystery four hundred rounds later. The `bc=` column is the
// Java bytecode counter; the comparator strips it from BOTH sides by one
// `normalize()` applied to each (LEARNINGS 2026-09-08: bc23's stripped it from
// the Java side only and every pair "diverged" at round 1) and uses it only
// for the Tier A headroom assertion.
package battlecode.world;

import battlecode.common.*;
import battlecode.server.GameState;
import battlecode.world.control.NullControlProvider;
import battlecode.world.control.PlayerControlProvider;
import battlecode.world.control.TeamControlProvider;
import battlecode.world.control.ZombieControlProvider;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.PrintStream;
import java.lang.reflect.Field;
import java.net.URL;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Random;

public final class Bc16Trace {

    static String teamLetter(Team t) {
        if (t == Team.A) return "A";
        if (t == Team.B) return "B";
        if (t == Team.NEUTRAL) return "N";
        if (t == Team.ZOMBIE) return "Z";
        return "-";
    }

    /** The insertion-ordered `LinkedHashMap` walk, which IS the exec order. */
    @SuppressWarnings("unchecked")
    static List<InternalRobot> execOrder(GameWorld world) throws Exception {
        Field f = GameWorld.class.getDeclaredField("gameObjectsByID");
        f.setAccessible(true);
        java.util.Map<Integer, InternalRobot> byId =
                (java.util.Map<Integer, InternalRobot>) f.get(world);
        List<InternalRobot> out = new ArrayList<InternalRobot>();
        for (InternalRobot r : byId.values()) {
            if (r != null) out.add(r);
        }
        return out;
    }

    static double[] squareArray(GameWorld world, String name) throws Exception {
        Field f = GameWorld.class.getDeclaredField(name);
        f.setAccessible(true);
        Object sa = f.get(world);
        Field inner = sa.getClass().getDeclaredField("store");
        inner.setAccessible(true);
        return (double[]) inner.get(sa);
    }

    /** `java.util.Random`'s 48-bit seed, the only way to compare a stream. */
    static long randomSeed(Random r) throws Exception {
        Field f = Random.class.getDeclaredField("seed");
        f.setAccessible(true);
        java.util.concurrent.atomic.AtomicLong a =
                (java.util.concurrent.atomic.AtomicLong) f.get(r);
        return a.get();
    }

    static long worldRandomSeed(GameWorld world) throws Exception {
        Field f = GameWorld.class.getDeclaredField("rand");
        f.setAccessible(true);
        return randomSeed((Random) f.get(world));
    }

    /**
     * THE ZOMBIE STREAM, HELD BY REFERENCE AND NOT RE-READ FROM THE FIELD.
     *
     * MEASURED, and it cost a debugging round: `ZombieControlProvider`'s
     * `matchEnded()` sets its own `random` field to **null**, so reading the
     * field once per round NPEs on the last round of a finished game — and
     * "helpfully" returning the previous round's cached value instead makes
     * the FINAL X line disagree with the Nim side by one round's worth of
     * draws, which reads exactly like a real RNG divergence. Holding the
     * `Random` OBJECT keeps its state readable after the provider drops it.
     */
    static Random zombieRandom = null;

    static void captureZombieRandom(ZombieControlProvider z) throws Exception {
        Field f = ZombieControlProvider.class.getDeclaredField("random");
        f.setAccessible(true);
        zombieRandom = (Random) f.get(z);
    }

    static long zombieRandomSeed(ZombieControlProvider z) throws Exception {
        if (zombieRandom == null) captureZombieRandom(z);
        return zombieRandom == null ? 0L : randomSeed(zombieRandom);
    }

    static long idGeneratorSeed(GameWorld world) throws Exception {
        Field f = GameWorld.class.getDeclaredField("idGenerator");
        f.setAccessible(true);
        Object gen = f.get(world);
        Field rf = gen.getClass().getDeclaredField("random");
        rf.setAccessible(true);
        return randomSeed((Random) rf.get(gen));
    }

    /** The den's own queue, if the provider exposes one for this location. */
    static int[] denQueue(ZombieControlProvider z, InternalRobot den)
            throws Exception {
        Field f = ZombieControlProvider.class.getDeclaredField("denQueues");
        f.setAccessible(true);
        Object q = f.get(z);
        int[] out = new int[4];
        if (!(q instanceof java.util.Map)) return out;
        // KEYED BY ROBOT ID, not by location: `denQueues` is a
        // `Map<Integer, Map<RobotType, Integer>>` (`:57`) filled in
        // `robotSpawned` with `denQueues.put(robot.getID(), spawnQueue)`.
        // Looking it up by `MapLocation` silently returned null and printed
        // `q=0:0:0:0` for every den on every round -- which agreed with the
        // Nim side except on the rounds where a den really was holding a
        // queue, i.e. exactly the rounds the column exists for.
        java.util.Map<?, ?> byId = (java.util.Map<?, ?>) q;
        Object counts = byId.get(Integer.valueOf(den.getID()));
        if (counts instanceof java.util.Map) {
            java.util.Map<?, ?> byType = (java.util.Map<?, ?>) counts;
            RobotType[] types = new RobotType[] {
                RobotType.STANDARDZOMBIE, RobotType.RANGEDZOMBIE,
                RobotType.FASTZOMBIE, RobotType.BIGZOMBIE };
            for (int i = 0; i < 4; i++) {
                Object v = byType.get(types[i]);
                if (v instanceof Integer) out[i] = ((Integer) v).intValue();
            }
        }
        return out;
    }

    static long fnv(double[] values) {
        long h = 0xCBF29CE484222325L;
        for (int i = 0; i < values.length; i++) {
            long tenths = (long) (values[i] * 10.0);
            h = (h ^ (tenths & 0xFFFFFFFFL)) * 0x100000001B3L;
        }
        return h;
    }

    static String f6(double v) { return String.format("%.6f", v); }

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
            System.err.println("usage: Bc16Trace <map> <rounds> <pkgA> "
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

        // The RESOURCE FALLBACK path: the jar carries 54 .xml maps and every
        // pool map is one of them, so no --map-dir is needed.
        GameMap map = GameMapIO.loadMap(mapName, null);
        final MapLocation origin = map.getOrigin();

        ZombieControlProvider zombies = new ZombieControlProvider();
        TeamControlProvider provider = new TeamControlProvider();
        provider.registerControlProvider(Team.A,
                new PlayerControlProvider(pkgA, dirA.toURI().toURL()));
        provider.registerControlProvider(Team.B,
                new PlayerControlProvider(pkgB, dirB.toURI().toURL()));
        provider.registerControlProvider(Team.ZOMBIE, zombies);
        // NEUTRALS GET A NullControlProvider, NOT THE ZOMBIE ONE -- see the
        // header. The zombie provider's "somehow controlling a non-zombie
        // robot" branch would kill every neutral on the board.
        provider.registerControlProvider(Team.NEUTRAL,
                new NullControlProvider());

        // Player stdout would otherwise interleave with the trace.
        PrintStream realOut = System.out;
        System.setOut(new PrintStream(new ByteArrayOutputStream()));

        GameWorld world = new GameWorld(map, provider, "A", "B",
                new long[2][GameConstants.TEAM_MEMORY_LENGTH]);
        // `matchStarted` has run by now, so the stream exists: hold it.
        captureZombieRandom(zombies);

        StringBuilder sb = new StringBuilder(1 << 20);
        int zombiesEverSpawned = 0;
        int actionsEver = 0;
        int peakRobots = execOrder(world).size();
        int peakBytecodes = 0;
        int peakLimit = 1;
        int peakRound = -1;
        int peakId = -1;
        int lastRound = -1;
        boolean sawTurn = false;
        boolean sawInfection = false;

        for (int i = 0; i < rounds; i++) {
            GameState state = world.runRound();
            int cur = world.getCurrentRound();
            lastRound = cur;

            for (int t2 = 0; t2 <= 1; t2++) {
                Team t = t2 == 0 ? Team.A : Team.B;
                sb.append("R ").append(cur).append(" T ").append(teamLetter(t))
                  .append(" parts=").append(f6(world.resources(t)))
                  .append(" ar=").append(world.getRobotTypeCount(t, RobotType.ARCHON))
                  .append(" sc=").append(world.getRobotTypeCount(t, RobotType.SCOUT))
                  .append(" so=").append(world.getRobotTypeCount(t, RobotType.SOLDIER))
                  .append(" gu=").append(world.getRobotTypeCount(t, RobotType.GUARD))
                  .append(" vi=").append(world.getRobotTypeCount(t, RobotType.VIPER))
                  .append(" tu=").append(world.getRobotTypeCount(t, RobotType.TURRET))
                  .append(" tt=").append(world.getRobotTypeCount(t, RobotType.TTM))
                  .append('\n');
            }

            int zs = world.getRobotTypeCount(Team.ZOMBIE, RobotType.STANDARDZOMBIE);
            int zr = world.getRobotTypeCount(Team.ZOMBIE, RobotType.RANGEDZOMBIE);
            int zf = world.getRobotTypeCount(Team.ZOMBIE, RobotType.FASTZOMBIE);
            int zb = world.getRobotTypeCount(Team.ZOMBIE, RobotType.BIGZOMBIE);
            int dens = world.getRobotTypeCount(Team.ZOMBIE, RobotType.ZOMBIEDEN);
            if (zs + zr + zf + zb > zombiesEverSpawned) {
                zombiesEverSpawned = zs + zr + zf + zb;
            }
            sb.append("R ").append(cur).append(" Z zn=")
              .append(world.getRobotCount(Team.ZOMBIE) - dens)
              .append(" zs=").append(zs).append(" zr=").append(zr)
              .append(" zf=").append(zf).append(" zb=").append(zb)
              .append(" dens=").append(dens)
              .append(" neu=").append(world.getRobotCount(Team.NEUTRAL))
              .append(" outbreak=").append(cur / GameConstants.OUTBREAK_TIMER)
              .append('\n');

            double[] rubble = squareArray(world, "rubble");
            double[] parts = squareArray(world, "parts");
            double rubbleSum = 0.0;
            double partsSum = 0.0;
            for (int k = 0; k < rubble.length; k++) rubbleSum += rubble[k];
            for (int k = 0; k < parts.length; k++) partsSum += parts[k];
            sb.append("R ").append(cur).append(" G rubblechk=")
              .append(Long.toHexString(fnv(rubble)))
              .append(" partschk=").append(Long.toHexString(fnv(parts)))
              .append(" rubblesum=")
              .append(Long.toHexString(Double.doubleToRawLongBits(rubbleSum)))
              .append(" partssum=")
              .append(Long.toHexString(Double.doubleToRawLongBits(partsSum)))
              .append('\n');

            List<InternalRobot> order = execOrder(world);
            if (order.size() > peakRobots) peakRobots = order.size();
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
                if (bc > 0) actionsEver++;
                if (r.getZombieInfectedTurns() > 0
                        || r.getViperInfectedTurns() > 0) sawInfection = true;
                if (r.getType() == RobotType.ZOMBIEDEN) {
                    int[] q = denQueue(zombies, r);
                    sb.append("R ").append(cur).append(" D ").append(r.getID())
                      .append(" x=").append(l == null ? -1 : l.x - origin.x)
                      .append(" y=").append(l == null ? -1 : l.y - origin.y)
                      .append(" hp=").append(f6(r.getHealthLevel()))
                      .append(" q=").append(q[0]).append(':').append(q[1])
                      .append(':').append(q[2]).append(':').append(q[3])
                      .append('\n');
                    continue;
                }
                sb.append("R ").append(cur).append(" U ").append(r.getID())
                  .append(" team=").append(teamLetter(r.getTeam()))
                  .append(" ty=").append(r.getType().name())
                  .append(" x=").append(l == null ? -1 : l.x - origin.x)
                  .append(" y=").append(l == null ? -1 : l.y - origin.y)
                  .append(" hp=").append(f6(r.getHealthLevel()))
                  .append(" cd=").append(f6(r.getCoreDelay()))
                  .append(" wd=").append(f6(r.getWeaponDelay()))
                  .append(" zi=").append(r.getZombieInfectedTurns())
                  .append(" vi=").append(r.getViperInfectedTurns())
                  .append(" ra=").append(r.getRoundsAlive())
                  .append(" bd=").append(r.isActive() ? 0 : 1)
                  .append(" bc=").append(bc)
                  .append('\n');
                if (r.getTeam() == Team.ZOMBIE
                        && r.getType() != RobotType.ZOMBIEDEN) sawTurn = true;
            }

            // THE `X` LINE: all three RNG states, EVERY round.
            sb.append("R ").append(cur).append(" X world=")
              .append(Long.toHexString(worldRandomSeed(world)))
              .append(" zombie=")
              .append(Long.toHexString(zombieRandomSeed(zombies)))
              .append(" idgen=")
              .append(Long.toHexString(idGeneratorSeed(world)))
              .append('\n');

            if (sb.length() > (1 << 22)) {
                realOut.print(sb);
                sb.setLength(0);
            }
            if (state == GameState.DONE || !world.isRunning()) break;
        }

        Team winner = world.getWinner();
        sb.append("R ").append(lastRound).append(" W winner=")
          .append(winner == null ? "-" : teamLetter(winner))
          .append(" dom=")
          .append(world.getGameStats().getDominationFactor() == null ? "-"
                  : world.getGameStats().getDominationFactor().name())
          .append('\n');
        realOut.print(sb);
        realOut.flush();

        System.setOut(realOut);
        System.err.println("bc16-oracle map=" + mapName
                + " rounds=" + lastRound
                + " peak_bytecodes=" + peakBytecodes
                + " peak_limit=" + peakLimit
                + " peak_pct=" + (peakLimit == 0 ? 0
                        : (100 * peakBytecodes / peakLimit))
                + " peak_round=" + peakRound
                + " peak_id=" + peakId
                + " peak_robots=" + peakRobots
                + " zombies_peak=" + zombiesEverSpawned
                + " actions=" + actionsEver
                + " saw_zombie_turn=" + sawTurn
                + " saw_infection=" + sawInfection);
        // THE GREEN-ORACLE-PROVING-NOTHING TRAP. bc16's Tier A runs an IDLE
        // bot, so "no robot was ever built" is not the right condition -- the
        // right one is that the ENGINE'S OWN HALF of the game never happened.
        if (zombiesEverSpawned == 0 && actionsEver == 0) {
            System.err.println("::error::no zombie was ever spawned and no "
                    + "robot ever took an action. THIS ORACLE MUST RUN ON "
                    + "TEMURIN 8 -- the jar bundles a 2016-era ASM and under "
                    + "a modern JDK every player class load throws inside "
                    + "ClassReader.<init>, and this oracle would be green "
                    + "while proving nothing.");
            return 3;
        }
        return 0;
    }
}
