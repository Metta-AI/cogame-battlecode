/**
 * Battlecode 2017 tables, printed from the PINNED JAR'S OWN CLASSES.
 *
 * CI-ONLY, JDK 8 ONLY. Nothing here ships in any image: `.github/workflows/ci.yml`
 * compiles this file inside the `parity-oracle-bc17` job with
 * `javac -cp <jar>` (no `--release`, no `-source`, no `-target` -- the compiler
 * IS 8) and runs it against the sha256- and size-verified
 * `org.battlecode:battlecode:2017.1.6.2` artefact.
 *
 * Three modes, all of them gates rather than conveniences:
 *
 *   constants   every `GameConstants` field by REFLECTION (2017's
 *               `GameConstants` is an *interface*, so its fields are
 *               implicitly `public static final` and reflection sees all of
 *               them) plus the whole six-row `RobotType` table with its eleven
 *               columns, as JSON with every float printed as its raw IEEE-754
 *               bits. `tools/gen_year_constants.py --year bc17 --tables` turns
 *               that into `src/battlecode/years/bc17/constants.nim` and
 *               byte-diffs it, so the constant table is provably the engine's
 *               and provably not hand-typed.
 *
 *   fdlibm      the fdlibm/StrictMath pin of `docs/RULES-BC17.md` F4: every
 *               boundary vector value-for-value, and a sha256 digest per
 *               expression SHAPE over a two-million-point sample of the
 *               engine's own argument domains, drawn by a recipe BOTH SIDES
 *               RUN (`java.util.Random(20170101)`, which
 *               `src/battlecode/rng.nim` already reproduces). Compared against
 *               the committed `data/bc17/fdlibm_vectors.json`.
 *
 *   maps        every committed board's `LiveMap` fields -- width, height,
 *               origin, seed, rounds and every initial body's id, team, type,
 *               float coordinates, radius, health, contained bullets and
 *               contained robot IN `getInitialBodies()` ORDER -- as a
 *               canonical raw-bits dump, which is what proves
 *               `tools/convert_maps_bc17.py`'s pure-Python flatbuffer walk
 *               rather than trusting it. `convert_maps_bc17.py --dump-bits`
 *               prints the same dump from the committed JSON and CI diffs the
 *               two.
 *
 * EVERY FLOAT IS PRINTED AS ITS RAW BITS, never as a decimal: a float32 needs
 * nine significant digits to round-trip and a formatter mismatch between
 * `Float.toString` and Python's `repr` would masquerade as a divergence for a
 * week.
 */
import battlecode.common.Direction;
import battlecode.common.GameConstants;
import battlecode.common.MapLocation;
import battlecode.common.RobotType;
import battlecode.common.Team;
import battlecode.common.BodyInfo;
import battlecode.common.RobotInfo;
import battlecode.common.TreeInfo;
import battlecode.world.GameMapIO;
import battlecode.world.LiveMap;

import java.lang.reflect.Field;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Random;

public strictfp class JavaBc17Tables {

    // ---------------------------------------------------------------- helpers

    static String fbits(float v) {
        return String.format("0x%08x", Float.floatToRawIntBits(v));
    }

    static String dbits(double v) {
        return String.format("0x%016x", Double.doubleToRawLongBits(v));
    }

    static String jsonString(String s) {
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }

    // ------------------------------------------------------------- constants

    static void constants() throws Exception {
        StringBuilder out = new StringBuilder();
        out.append("{\n  \"spec_version\": ")
           .append(jsonString(GameConstants.SPEC_VERSION)).append(",\n");
        out.append("  \"constants\": [\n");
        Field[] fields = GameConstants.class.getFields();
        // Reflection order is unspecified; sort by name so the artefact is
        // canonical.
        Arrays.sort(fields, (a, b) -> a.getName().compareTo(b.getName()));
        boolean first = true;
        for (Field f : fields) {
            Class<?> t = f.getType();
            String kind;
            String value;
            if (t == int.class) {
                kind = "int";
                value = Integer.toString(f.getInt(null));
            } else if (t == float.class) {
                kind = "float";
                value = jsonString(fbits(f.getFloat(null)));
            } else if (t == String.class) {
                kind = "string";
                value = jsonString((String) f.get(null));
            } else {
                continue;
            }
            if (!first) out.append(",\n");
            first = false;
            out.append("    {\"name\": ").append(jsonString(f.getName()))
               .append(", \"kind\": ").append(jsonString(kind))
               .append(", \"value\": ").append(value).append("}");
        }
        out.append("\n  ],\n  \"robots\": [\n");
        first = true;
        for (RobotType rt : RobotType.values()) {
            if (!first) out.append(",\n");
            first = false;
            out.append("    {\"name\": ").append(jsonString(rt.name()))
               .append(", \"ordinal\": ").append(rt.ordinal())
               .append(", \"spawn_source\": ")
               .append(jsonString(rt.spawnSource == null
                                  ? "-" : rt.spawnSource.name()))
               .append(", \"build_cooldown_turns\": ")
               .append(rt.buildCooldownTurns)
               .append(", \"max_health\": ").append(rt.maxHealth)
               .append(", \"bullet_cost\": ").append(rt.bulletCost)
               .append(", \"body_radius\": ")
               .append(jsonString(fbits(rt.bodyRadius)))
               .append(", \"bullet_speed\": ")
               .append(jsonString(fbits(rt.bulletSpeed)))
               .append(", \"attack_power\": ")
               .append(jsonString(fbits(rt.attackPower)))
               .append(", \"sensor_radius\": ")
               .append(jsonString(fbits(rt.sensorRadius)))
               .append(", \"bullet_sight_radius\": ")
               .append(jsonString(fbits(rt.bulletSightRadius)))
               .append(", \"stride_radius\": ")
               .append(jsonString(fbits(rt.strideRadius)))
               .append(", \"bytecode_limit\": ").append(rt.bytecodeLimit)
               .append(", \"starting_health\": ")
               .append(jsonString(fbits(rt.getStartingHealth())))
               .append(", \"can_attack\": ").append(rt.canAttack())
               .append(", \"can_hire\": ").append(rt.canHire())
               .append(", \"can_build\": ").append(rt.canBuild())
               .append(", \"is_hireable\": ").append(rt.isHireable())
               .append(", \"is_buildable\": ").append(rt.isBuildable())
               .append("}");
        }
        out.append("\n  ]\n}\n");
        System.out.print(out);
    }

    // ---------------------------------------------------------------- fdlibm
    //
    // The eleven EXPRESSION SHAPES of docs/RULES-BC17.md F3 that involve a
    // transcendental or a width the port could get wrong. Each is a pure
    // function of one sample's (dx, dy) pair, so both sides can stream the
    // identical byte sequence into sha256 without exchanging anything but the
    // recipe.

    static final String[] SHAPES = {
        "direction_from_deltas",   // reduce((float) atan2((double)dy,(double)dx))
        "reduce_wrap",             // reduce(radians + 3*(float)PI)
        "radians_between",         // reduce((float)(rb - ra))
        "delta_x",                 // (float)(dist * cos(radians))
        "delta_y",                 // (float)(dist * sin(radians))
        "add_dir_x",               // dx + (float)cos(radians)
        "add_dir_dist_x",          // dx + (float)(dist * cos(radians))
        "distance_to",             // (float)sqrt((double)(dx*dx + dy*dy))
        "distance_squared_to",     // dx*dx + dy*dy
        "perp_dist",               // (float)|dist * sin(between)|
        "hit_dist",                // dist * (float)cos(between)
    };

    /** reduce(), copied from Direction.java:663-672 -- it is private there. */
    static float reduce(float rads) {
        if (rads <= -(float) Math.PI) {
            int circles = (int) Math.ceil(-(rads + Math.PI) / (2 * Math.PI));
            return rads + (float) (Math.PI * 2 * circles);
        } else if (rads > (float) Math.PI) {
            int circles = (int) Math.ceil((rads - Math.PI) / (2 * Math.PI));
            return rads - (float) (Math.PI * 2 * circles);
        }
        return rads;
    }

    static float shape(int which, float dx, float dy) {
        // The derived quantities every shape is built from, each one exactly
        // the engine's own expression.
        float radians = reduce((float) StrictMath.atan2(dy, dx));
        float distSq = dx * dx + dy * dy;
        float dist = (float) StrictMath.sqrt(distSq);
        // A second direction, from the SWAPPED deltas (the reflection about
        // the 45-degree line, i.e. pi/2 - theta), so `radians_between` and the
        // two `calcHitDist` shapes have a real pair to work on. The mirrored
        // pair `atan2(dx, -dy)` would have been exactly perpendicular and
        // would have made `perp_dist` degenerate to `dist`.
        float radiansB = reduce((float) StrictMath.atan2(dx, dy));
        float between = reduce(radiansB - radians);
        switch (which) {
            case 0: return radians;
            case 1: return reduce(radians + 3 * (float) Math.PI);
            case 2: return between;
            case 3: return (float) (dist * StrictMath.cos(radians));
            case 4: return (float) (dist * StrictMath.sin(radians));
            case 5: return dx + (float) StrictMath.cos(radians);
            case 6: return dx + (float) (dist * StrictMath.cos(radians));
            case 7: return dist;
            case 8: return distSq;
            case 9: return (float) Math.abs(dist * StrictMath.sin(between));
            default: return dist * (float) StrictMath.cos(between);
        }
    }

    static final int SAMPLE_SEED = 20170101;

    /** The canonical byte stream: big-endian raw bits, three floats a row. */
    static void appendBits(byte[] buf, int at, float v) {
        int bits = Float.floatToRawIntBits(v);
        buf[at] = (byte) (bits >>> 24);
        buf[at + 1] = (byte) (bits >>> 16);
        buf[at + 2] = (byte) (bits >>> 8);
        buf[at + 3] = (byte) bits;
    }

    /**
     * BLOCK SIZE, IN SAMPLES, of the two-level digest -- and it is a wire
     * format, so both sides carry the same number.
     *
     * The digest of one shape is
     *   sha256( concat over blocks of sha256(block bytes) )
     * where a block is at most BLOCK_SAMPLES rows of
     * `(bits(dx), bits(dy), bits(result))`. Two levels rather than one
     * because the Nim side's sha256 (crunchy) is ONE-SHOT: a single stream
     * over two million rows would need a 24 MB buffer per shape, and the same
     * test runs inside the wasm bundle. Blocking keeps the peak at 768 kB a
     * shape and leaves the artefact a few hundred bytes.
     */
    static final int BLOCK_SAMPLES = 65536;

    static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format("%02x", x));
        return sb.toString();
    }

    static void fdlibm(int samples) throws Exception {
        StringBuilder out = new StringBuilder();
        out.append("{\n");
        out.append("  \"note\": \"GENERATED by tools/JavaBc17Tables.java "
                   + "fdlibm under the pinned JDK 8. Every float is raw "
                   + "IEEE-754 bits. See docs/RULES-BC17.md F4.\",\n");
        out.append("  \"jdk\": ")
           .append(jsonString(System.getProperty("java.version")))
           .append(",\n");
        out.append("  \"sample\": {\"seed\": ").append(SAMPLE_SEED)
           .append(", \"count\": ").append(samples)
           .append(", \"block\": ").append(BLOCK_SAMPLES)
           .append(", \"recipe\": \"dx = (nextFloat() - 0.5f) * 200f, dy "
                   + "likewise, from java.util.Random(20170101); the digest "
                   + "of a shape is sha256 over the concatenated sha256 of "
                   + "each block of at most `block` rows of "
                   + "(bits(dx), bits(dy), bits(result)), big-endian\"},\n");

        // ---- the boundary vectors, value for value
        //
        // FORTY curated (dx, dy) pairs times the eleven shapes = 440 rows:
        // the eight cardinals and (0,0) the engine's own `Direction`
        // factories produce, `+-(float)pi` and one ulp either side of it, the
        // quarter angles, the smallest normal and subnormal float32, a spread
        // of powers of two and four real-looking board deltas.
        List<float[]> pairs = new ArrayList<float[]>();
        float pi = (float) Math.PI;
        float[][] cards = {{0, 0}, {1, 0}, {0, 1}, {-1, 0}, {0, -1},
                           {1, 1}, {1, -1}, {-1, 1}, {-1, -1}};
        for (float[] c : cards) pairs.add(c);
        float[] angles = {pi, -pi, Math.nextUp(pi), Math.nextDown(pi),
                          pi / 2, pi / 4, 3 * pi / 4};
        for (float a : angles) pairs.add(new float[]{a, 0.0f});
        pairs.add(new float[]{Float.MIN_NORMAL, 0.0f});
        pairs.add(new float[]{0.0f, Float.MIN_VALUE});
        pairs.add(new float[]{Float.MIN_VALUE, Float.MIN_VALUE});
        pairs.add(new float[]{-Float.MIN_NORMAL, 1.0f});
        int[] ks = {-30, -20, -10, -1, 0, 1, 3, 7};
        for (int k : ks) {
            float q = (float) Math.pow(2, k);
            pairs.add(new float[]{q, q});
            pairs.add(new float[]{q, -q});
        }
        pairs.add(new float[]{100f, 100f});
        pairs.add(new float[]{-100f, 0.5f});
        pairs.add(new float[]{0.05f, -99.5f});
        pairs.add(new float[]{3.5f, -0.25f});
        if (pairs.size() != 40) {
            System.err.println("expected 40 boundary pairs, built "
                               + pairs.size());
            System.exit(5);
        }

        out.append("  \"boundary\": [\n");
        boolean first = true;
        for (float[] p : pairs) {
            for (int s = 0; s < SHAPES.length; s++) {
                if (!first) out.append(",\n");
                first = false;
                out.append("    [").append(jsonString(SHAPES[s])).append(", ")
                   .append(jsonString(fbits(p[0]))).append(", ")
                   .append(jsonString(fbits(p[1]))).append(", ")
                   .append(jsonString(fbits(shape(s, p[0], p[1]))))
                   .append("]");
            }
        }
        // The rotations a triad and a pentad really produce, as radians: the
        // one place `Math.toRadians` is load-bearing.
        for (int i = 1; i <= 2; i++) {
            for (float deg : new float[]{20f, 15f}) {
                Direction east = new Direction(1, 0);
                Direction left = east.rotateLeftDegrees(i * deg);
                Direction right = east.rotateRightDegrees(i * deg);
                out.append(",\n    [\"rotate_left_degrees\", ")
                   .append(jsonString(fbits(i * deg))).append(", ")
                   .append(jsonString(fbits(east.radians))).append(", ")
                   .append(jsonString(fbits(left.radians))).append("]");
                out.append(",\n    [\"rotate_right_degrees\", ")
                   .append(jsonString(fbits(i * deg))).append(", ")
                   .append(jsonString(fbits(east.radians))).append(", ")
                   .append(jsonString(fbits(right.radians))).append("]");
            }
        }
        out.append("\n  ],\n");

        out.append("  \"digests\": {\n");
        MessageDigest sha = MessageDigest.getInstance("SHA-256");
        int shapes = SHAPES.length;
        byte[][] block = new byte[shapes][BLOCK_SAMPLES * 12];
        MessageDigest[] outer = new MessageDigest[shapes];
        for (int s = 0; s < shapes; s++) {
            outer[s] = MessageDigest.getInstance("SHA-256");
        }
        Random rng = new Random(SAMPLE_SEED);
        int inBlock = 0;
        for (int i = 0; i < samples; i++) {
            float dx = (rng.nextFloat() - 0.5f) * 200f;
            float dy = (rng.nextFloat() - 0.5f) * 200f;
            int at = inBlock * 12;
            for (int s = 0; s < shapes; s++) {
                appendBits(block[s], at, dx);
                appendBits(block[s], at + 4, dy);
                appendBits(block[s], at + 8, shape(s, dx, dy));
            }
            inBlock++;
            if (inBlock == BLOCK_SAMPLES) {
                for (int s = 0; s < shapes; s++) {
                    sha.reset();
                    outer[s].update(sha.digest(
                        Arrays.copyOf(block[s], BLOCK_SAMPLES * 12)));
                }
                inBlock = 0;
            }
        }
        if (inBlock > 0) {
            for (int s = 0; s < shapes; s++) {
                sha.reset();
                outer[s].update(sha.digest(
                    Arrays.copyOf(block[s], inBlock * 12)));
            }
        }
        for (int s = 0; s < shapes; s++) {
            out.append("    ").append(jsonString(SHAPES[s])).append(": ")
               .append(jsonString(hex(outer[s].digest())));
            out.append(s + 1 == shapes ? "\n" : ",\n");
        }
        out.append("  }\n}\n");
        System.out.print(out);
    }

    // ------------------------------------------------------------------ maps

    static void maps(String[] names) throws Exception {
        StringBuilder out = new StringBuilder();
        for (String name : names) {
            LiveMap m = GameMapIO.loadMapAsResource(
                JavaBc17Tables.class.getClassLoader(),
                "battlecode/world/resources/", name);
            out.append("MAP ").append(m.getMapName())
               .append(" w=").append(fbits(m.getWidth()))
               .append(" h=").append(fbits(m.getHeight()))
               .append(" ox=").append(fbits(m.getOrigin().x))
               .append(" oy=").append(fbits(m.getOrigin().y))
               .append(" seed=").append(m.getSeed())
               .append(" rounds=").append(m.getRounds())
               .append(" bodies=").append(m.getInitialBodies().length)
               .append("\n");
            for (BodyInfo b : m.getInitialBodies()) {
                if (b.isRobot()) {
                    RobotInfo r = (RobotInfo) b;
                    out.append("R ").append(r.ID)
                       .append(" team=").append(r.team.name())
                       .append(" ty=").append(r.type.name())
                       .append(" x=").append(fbits(r.location.x))
                       .append(" y=").append(fbits(r.location.y))
                       .append(" hp=").append(fbits(r.health))
                       .append("\n");
                } else {
                    TreeInfo t = (TreeInfo) b;
                    out.append("E ").append(t.ID)
                       .append(" team=").append(t.team.name())
                       .append(" x=").append(fbits(t.location.x))
                       .append(" y=").append(fbits(t.location.y))
                       .append(" r=").append(fbits(t.radius))
                       .append(" hp=").append(fbits(t.health))
                       .append(" cb=").append((int) t.containedBullets)
                       .append(" crob=").append(t.containedRobot == null
                                                ? "-"
                                                : t.containedRobot.name())
                       .append("\n");
                }
            }
        }
        System.out.print(out);
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 0) {
            System.err.println(
                "usage: JavaBc17Tables constants | fdlibm [samples] | "
                + "maps <Name>...");
            System.exit(2);
        }
        if ("constants".equals(args[0])) {
            constants();
        } else if ("fdlibm".equals(args[0])) {
            fdlibm(args.length > 1 ? Integer.parseInt(args[1]) : 2000000);
        } else if ("maps".equals(args[0])) {
            maps(Arrays.copyOfRange(args, 1, args.length));
        } else {
            System.err.println("unknown mode " + args[0]);
            System.exit(2);
        }
        System.exit(0);
    }
}
