// Emits tests/fixtures/java_random_vectors.json — the ground truth
// tests/test_rng.nim checks src/battlecode/rng.nim against.
//
// CI-TIME ONLY. There is no JDK in any runtime image stage (docs/RULES.md
// §Divergences); this file exists so the java.util.Random port is checked
// against the real thing rather than against a second reading of the spec.
//
//   javac -d /tmp/jrv tools/JavaRandomVectors.java
//   java -cp /tmp/jrv JavaRandomVectors > tests/fixtures/java_random_vectors.json
//
// IDGenerator is reproduced here rather than imported: the engine jar is not
// on the CI classpath for this step, and the algorithm is eight lines. It is
// a VERBATIM copy of battlecode/world/IDGenerator.java at tag engine.1.2.5;
// if that file ever changes, this one is wrong and test_rng.nim will say so
// against a freshly generated fixture.
import java.util.Random;

public class JavaRandomVectors {

    static final int ID_BLOCK_SIZE = 4096;
    static final int MIN_ID = 10000;

    static final class IdGen {
        private final int[] reservedIDs = new int[ID_BLOCK_SIZE];
        private final Random random;
        private int cursor;
        private int nextIDBlock;

        IdGen(int seed) {
            this.random = new Random(seed);
            this.nextIDBlock = MIN_ID;
            allocateNextBlock();
        }

        int nextID() {
            int id = reservedIDs[cursor];
            cursor++;
            if (cursor == ID_BLOCK_SIZE) allocateNextBlock();
            return id;
        }

        private void allocateNextBlock() {
            cursor = 0;
            for (int i = 0; i < ID_BLOCK_SIZE; i++) reservedIDs[i] = nextIDBlock + i + 1;
            for (int i = ID_BLOCK_SIZE - 1; i > 0; i--) {
                int index = random.nextInt(i + 1);
                int a = reservedIDs[index];
                reservedIDs[index] = reservedIDs[i];
                reservedIDs[i] = a;
            }
            nextIDBlock += ID_BLOCK_SIZE;
        }
    }

    static void ints(StringBuilder out, String key, int[] values) {
        out.append("\"").append(key).append("\":[");
        for (int i = 0; i < values.length; i++) {
            if (i > 0) out.append(',');
            out.append(values[i]);
        }
        out.append("]");
    }

    public static void main(String[] args) {
        // Five seeds, 10 000 draws each, plus the whole cheese-mine offset
        // call shape (nextInt(-4, 4)) and 5 000 ids out of the generator.
        final int[] seeds = {0, 1, 6370, 871345, -2147483648};
        final int n = 10000;
        StringBuilder out = new StringBuilder();
        out.append("{\"draws\":10000,\"seeds\":[");
        for (int s = 0; s < seeds.length; s++) {
            if (s > 0) out.append(',');
            int seed = seeds[s];
            out.append("{\"seed\":").append(seed).append(',');

            Random r = new Random(seed);
            int[] a = new int[n];
            for (int i = 0; i < n; i++) a[i] = r.nextInt();
            ints(out, "next_int", a);
            out.append(',');

            // Powers of two AND non-powers, so both branches of nextInt(bound)
            // are exercised, including the rejection loop.
            r = new Random(seed);
            for (int i = 0; i < n; i++) a[i] = r.nextInt(1 + (i % 97));
            ints(out, "next_int_bound", a);
            out.append(',');

            r = new Random(seed);
            for (int i = 0; i < n; i++) a[i] = r.nextInt(-4, 4);
            ints(out, "next_int_range", a);
            out.append(',');

            r = new Random(seed);
            out.append("\"next_float\":[");
            for (int i = 0; i < n; i++) {
                if (i > 0) out.append(',');
                out.append(Float.floatToIntBits(r.nextFloat()));
            }
            out.append("],");

            r = new Random(seed);
            out.append("\"next_double\":[");
            for (int i = 0; i < n; i++) {
                if (i > 0) out.append(',');
                out.append(Double.doubleToLongBits(r.nextDouble()));
            }
            out.append("],");

            r = new Random(seed);
            out.append("\"next_boolean\":[");
            for (int i = 0; i < n; i++) {
                if (i > 0) out.append(',');
                out.append(r.nextBoolean() ? 1 : 0);
            }
            out.append("],");

            IdGen gen = new IdGen(seed);
            int[] ids = new int[5000];
            for (int i = 0; i < ids.length; i++) ids[i] = gen.nextID();
            ints(out, "ids", ids);
            out.append('}');
        }
        out.append("]}");
        System.out.println(out);
    }
}
