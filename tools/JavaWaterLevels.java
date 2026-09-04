// Regenerates `data/bc20/water_levels.json` — CI-ONLY, never in an image.
//
// `GameConstants.getWaterLevel` is
//
//     (float)(Math.exp(0.0028*x - 1.38*Math.sin(0.00157*x - 1.73)
//                      + 1.38*Math.sin(-1.73)) - 1)
//
// and `Math.exp` / `Math.sin` are HotSpot INTRINSICS that are not bit-identical
// to any libm this port would link natively or under emscripten. The function
// depends only on the round number, so the whole domain is emitted here, once,
// under the JDK, as float32 BIT PATTERNS, and the sim (native and wasm) reads
// the committed table. Bit-exact against Java by construction, on every
// platform, with no libm in the loop.
//
//     javac -d /tmp/wl tools/JavaWaterLevels.java
//     java -cp /tmp/wl JavaWaterLevels > data/bc20/water_levels.json
//
// The `parity-oracle` CI job regenerates and byte-diffs this file as a BLOCKING
// step. The emitted table is also checked against `StrictMath` here, so a JDK
// whose intrinsics disagree with the reference implementation is reported
// rather than silently baked in.
public final class JavaWaterLevels {

    static final int MAX_ROUND = 1500;

    static float waterLevel(int roundNumber) {
        double x = roundNumber;
        return (float) (Math.exp(0.0028 * x - 1.38 * Math.sin(0.00157 * x - 1.73)
                + 1.38 * Math.sin(-1.73)) - 1);
    }

    static float strictWaterLevel(int roundNumber) {
        double x = roundNumber;
        return (float) (StrictMath.exp(0.0028 * x - 1.38 * StrictMath.sin(0.00157 * x - 1.73)
                + 1.38 * StrictMath.sin(-1.73)) - 1);
    }

    public static void main(String[] args) {
        int strictMismatches = 0;
        StringBuilder out = new StringBuilder();
        out.append("{\"source\":\"battlecode20 GameConstants.getWaterLevel\",");
        out.append("\"encoding\":\"float32 bit pattern, 8 hex digits, big-endian\",");
        out.append("\"max_round\":").append(MAX_ROUND).append(',');
        out.append("\"levels\":[");
        for (int r = 0; r <= MAX_ROUND; r++) {
            float v = waterLevel(r);
            if (Float.floatToRawIntBits(v) != Float.floatToRawIntBits(strictWaterLevel(r))) {
                strictMismatches++;
            }
            if (r > 0) {
                out.append(',');
            }
            out.append('"');
            out.append(String.format("%08x", Float.floatToRawIntBits(v)));
            out.append('"');
        }
        out.append("]}\n");
        System.out.print(out);
        if (strictMismatches > 0) {
            System.err.println("WARNING: Math and StrictMath disagree on "
                    + strictMismatches + " of " + (MAX_ROUND + 1) + " rounds");
        }
    }
}
