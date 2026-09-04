// The bc20 PARITY ORACLE, JDK side. CI-ONLY: there is no JDK, no JRE and no
// upstream Java source in any image this repository builds.
//
// WHAT THIS IS, AND WHY IT IS NOT THE WHOLE ENGINE
// -----------------------------------------------
// The design note asks for the 2020 engine built from source and driven
// head-to-head against the Nim port. That build is BLOCKED BY A DEAD
// ARTIFACT: `engine/build.gradle` depends on `net.sf.jsi:jsi:1.1.0-SNAPSHOT`,
// which was published only to jcenter (shut down 2022) and to the Sonatype OSS
// SNAPSHOTS repository (expired). Both 404 today, and the engine's
// `world/ObjectInfo.java` imports `net.sf.jsi` directly, so nothing resolves
// and `:engine:jar` cannot be produced without patching the upstream build --
// which would make the "unmodified engine" oracle a modified one.
//
// What DOES still work is the part of the engine that has no dependencies at
// all. `common/GameConstants.java`, `common/RobotType.java`,
// `common/Transaction.java`, `common/Direction.java`, `common/Team.java` and
// `world/IDGenerator.java` compile with a bare `javac` against the pinned
// checkout, and between them they own every piece of arithmetic the Nim port
// could get subtly wrong and never notice:
//
//   * the water level, which is `Math.exp`/`Math.sin` and therefore a HotSpot
//     intrinsic;
//   * both pollution coefficients, which are `float` narrowings of `double`
//     expressions;
//   * `Transaction.compareTo`, which decides the minting order;
//   * `IDGenerator`, whose 48-bit LCG and Fisher-Yates block shuffle decide
//     every robot id, and therefore the `highest_id` tiebreak rung and the
//     cow RNG seeds;
//   * the constants and the `RobotType` table themselves.
//
// This program emits all of that as a text vector file. `tools/parity_trace_bc20.nim`
// emits the same file from the Nim port and the job diffs them, byte for byte.
//
//   javac -d /tmp/oracle/classes \
//     $BC20_DIR/engine/src/main/battlecode/common/{GameConstants,RobotType,Transaction,Direction,Team}.java \
//     $BC20_DIR/engine/src/main/battlecode/world/IDGenerator.java \
//     tools/oracle/Bc20Oracle.java
//   java -cp /tmp/oracle/classes Bc20Oracle > /tmp/oracle/java.vectors
//
// docs/PARITY.md section bc20 records what each tier proves and what the dead
// artifact costs.

import battlecode.common.Direction;
import battlecode.common.GameConstants;
import battlecode.common.RobotType;
import battlecode.common.Transaction;
import battlecode.world.IDGenerator;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;

public final class Bc20Oracle {

    static String f32(float v) {
        return String.format("%08x", Float.floatToRawIntBits(v));
    }

    public static void main(String[] args) {
        StringBuilder o = new StringBuilder();

        // -- constants -----------------------------------------------------
        o.append("constants\n");
        o.append("MIN_WATER_ELEVATION ").append(GameConstants.MIN_WATER_ELEVATION).append('\n');
        o.append("INITIAL_SOUP ").append(GameConstants.INITIAL_SOUP).append('\n');
        o.append("BASE_INCOME_PER_ROUND ").append(GameConstants.BASE_INCOME_PER_ROUND).append('\n');
        o.append("SOUP_MINING_RATE ").append(GameConstants.SOUP_MINING_RATE).append('\n');
        o.append("MAX_DIRT_DIFFERENCE ").append(GameConstants.MAX_DIRT_DIFFERENCE).append('\n');
        o.append("DELIVERY_DRONE_PICKUP_RADIUS_SQUARED ")
                .append(GameConstants.DELIVERY_DRONE_PICKUP_RADIUS_SQUARED).append('\n');
        o.append("NET_GUN_SHOOT_RADIUS_SQUARED ")
                .append(GameConstants.NET_GUN_SHOOT_RADIUS_SQUARED).append('\n');
        o.append("BLOCKCHAIN_TRANSACTION_LENGTH ")
                .append(GameConstants.BLOCKCHAIN_TRANSACTION_LENGTH).append('\n');
        o.append("NUMBER_OF_TRANSACTIONS_PER_BLOCK ")
                .append(GameConstants.NUMBER_OF_TRANSACTIONS_PER_BLOCK).append('\n');
        o.append("INITIAL_COOLDOWN_TURNS ")
                .append(GameConstants.INITIAL_COOLDOWN_TURNS).append('\n');

        // -- the RobotType table -------------------------------------------
        o.append("robottypes\n");
        for (RobotType t : RobotType.values()) {
            o.append(t.name()).append(' ')
                    .append(t.cost).append(' ')
                    .append(t.dirtLimit).append(' ')
                    .append(t.soupLimit).append(' ')
                    .append(f32(t.actionCooldown)).append(' ')
                    .append(t.sensorRadiusSquared).append(' ')
                    .append(t.pollutionRadiusSquared).append(' ')
                    .append(t.localPollutionAdditiveEffect).append(' ')
                    .append(f32(t.localPollutionMultiplicativeEffect)).append(' ')
                    .append(t.globalPollutionAmount).append(' ')
                    .append(t.maxSoupProduced).append(' ')
                    .append(t.isBuilding() ? 1 : 0).append(' ')
                    .append(t.canRefine() ? 1 : 0).append(' ')
                    .append(t.canAffectPollution() ? 1 : 0).append(' ')
                    .append(t.canMove() ? 1 : 0).append(' ')
                    .append(t.canFly() ? 1 : 0).append(' ')
                    .append(t.canBePickedUp() ? 1 : 0).append(' ')
                    .append(t.canShoot() ? 1 : 0).append(' ')
                    .append(t.canBeShot() ? 1 : 0).append('\n');
        }

        // -- Direction, whose ordinals the map files and the cow provider
        //    index into ---------------------------------------------------
        o.append("directions\n");
        for (Direction d : Direction.allDirections()) {
            o.append(d.name()).append(' ').append(d.dx).append(' ')
                    .append(d.dy).append(' ').append(d.opposite().name()).append('\n');
        }

        // -- the water level, every round in the cap -----------------------
        o.append("water\n");
        for (int r = 0; r <= 1500; r++) {
            o.append(r).append(' ').append(f32(GameConstants.getWaterLevel(r))).append('\n');
        }

        // -- both pollution coefficients, the WHOLE integer domain ---------
        o.append("pollution\n");
        for (int p = 0; p <= 65535; p++) {
            o.append(p).append(' ')
                    .append(f32(GameConstants.getCooldownPollutionCoefficient(p)))
                    .append(' ')
                    .append(f32(GameConstants.getSensorRadiusPollutionCoefficient(p)))
                    .append('\n');
        }

        // -- Math.round(float), which is how a sensed radius and a pollution
        //    reading are narrowed ------------------------------------------
        o.append("round\n");
        float[] probes = {0.0f, 0.5f, -0.5f, 1.4999999f, 2.5f, -2.5f,
                35.0f, 27.65f, 6.9999995f, 1e7f, -1e7f};
        for (float v : probes) {
            o.append(f32(v)).append(' ').append(Math.round(v)).append('\n');
        }

        // -- IDGenerator: the ids every map seed produces -------------------
        o.append("ids\n");
        int[] seeds = {30, 432, 219, 9999, 43223, 118811, 198248, 4444, 6370};
        for (int seed : seeds) {
            IDGenerator gen = new IDGenerator(seed);
            o.append(seed);
            for (int i = 0; i < 24; i++) {
                o.append(' ').append(gen.nextID());
            }
            o.append('\n');
        }

        // -- java.util.Random: the transaction-id stream and the cow stream -
        o.append("random\n");
        for (int seed : seeds) {
            Random r = new Random(seed);
            o.append(seed);
            for (int i = 0; i < 8; i++) {
                o.append(' ').append(r.nextInt());
            }
            o.append('\n');
        }
        o.append("cowseeds\n");
        for (int seed : seeds) {
            for (int id = 0; id < 6; id++) {
                // `84307 * mapSeed + 20201 * (cowId / 2)` is Java `int`
                // arithmetic and it OVERFLOWS. This vector is what proves the
                // Nim port wraps rather than raising.
                int cowSeed = 84307 * seed + 20201 * (id / 2);
                Random r = new Random(cowSeed);
                o.append(seed).append(' ').append(id).append(' ').append(cowSeed);
                for (int i = 0; i < 4; i++) {
                    o.append(' ').append(Double.doubleToRawLongBits(r.nextDouble()));
                }
                o.append('\n');
            }
        }

        // -- Transaction.compareTo, over a corpus with deliberate ties ------
        o.append("transactions\n");
        Random corpus = new Random(20200101L);
        List<Transaction> pool = new ArrayList<Transaction>();
        for (int i = 0; i < 200; i++) {
            int[] message = new int[GameConstants.BLOCKCHAIN_TRANSACTION_LENGTH];
            for (int j = 0; j < message.length; j++) {
                message[j] = corpus.nextInt(50);
            }
            // Costs and ids collide on purpose: the second and third rungs of
            // the comparator are only exercised by ties.
            int cost = 1 + corpus.nextInt(5);
            int id = corpus.nextInt(7);
            pool.add(new Transaction(cost, message, id));
            o.append("in ").append(cost).append(' ').append(id).append(' ')
                    .append(pool.get(pool.size() - 1).getSerializedMessage()).append('\n');
        }
        Collections.sort(pool);
        for (Transaction t : pool) {
            o.append("out ").append(t.getCost()).append(' ')
                    .append(t.getSerializedMessage()).append('\n');
        }

        System.out.print(o);
    }
}
