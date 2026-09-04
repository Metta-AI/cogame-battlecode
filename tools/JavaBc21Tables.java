// Regenerates the two committed bc21 economy tables under a JDK, and
// cross-checks Math.exp against StrictMath.exp over the range the sim reads.
//
// CI-TIME ONLY. There is no JDK, no JRE and no Java in ANY runtime image
// stage; this file is compiled and run by the `parity-oracle-bc21` job of
// .github/workflows/ci.yml, which then BYTE-DIFFS the output against
// data/bc21/ec_passive.json and data/bc21/embezzle.json. A hand-edited table
// fails the build.
//
// The two functions are `RobotType.getPassiveInfluence`'s two live arms, at
// battlecode21 commit ed39c1a49574db57e5463d720736220506280294:
//
//   ENLIGHTENMENT_CENTER: (int) Math.ceil(0.2f * Math.sqrt(roundNum))
//   SLANDERER (roundsAlive <= 50):
//     (int) (influence * (1.0/50 + 0.03f * Math.exp(-0.001f * influence)))
//
// The WIDTHS are load-bearing and are reproduced exactly: `-0.001f * influence`
// is a FLOAT multiplication (both the constant and the product are `float`)
// widened to `double` only when it enters Math.exp, and `0.03f * <double>`
// widens the float constant. Getting that wrong moves the slanderer
// breakpoints by one influence point each and the whole economy with them.
//
//   javac -d out tools/JavaBc21Tables.java
//   java -cp out JavaBc21Tables ec_passive   > data/bc21/ec_passive.json
//   java -cp out JavaBc21Tables embezzle     > data/bc21/embezzle.json
//   java -cp out JavaBc21Tables strictcheck  # prints disagreements, if any
//   java -cp out JavaBc21Tables tail         # the (4096, 1e8] sample
public final class JavaBc21Tables {

    static final int MAX_ROUNDS = 1500;
    static final int MAX_INFLUENCE = 4096;
    static final int EMBEZZLE_NUM_ROUNDS = 50;
    static final float EMBEZZLE_SCALE_FACTOR = 0.03f;
    static final float EMBEZZLE_DECAY_FACTOR = 0.001f;
    static final float PASSIVE_RATIO_EC = 0.2f;

    static int ecPassive(int roundNum) {
        return (int) Math.ceil(PASSIVE_RATIO_EC * Math.sqrt(roundNum));
    }

    static int embezzle(int influence) {
        return (int) (influence * (1.0 / EMBEZZLE_NUM_ROUNDS
                + EMBEZZLE_SCALE_FACTOR
                  * Math.exp(-EMBEZZLE_DECAY_FACTOR * influence)));
    }

    static int embezzleStrict(int influence) {
        return (int) (influence * (1.0 / EMBEZZLE_NUM_ROUNDS
                + EMBEZZLE_SCALE_FACTOR
                  * StrictMath.exp(-EMBEZZLE_DECAY_FACTOR * influence)));
    }

    static void ecPassiveTable() {
        StringBuilder sb = new StringBuilder();
        long total = 0;
        sb.append("{\"max_round\":").append(MAX_ROUNDS).append(",\"income\":[");
        for (int t = 1; t <= MAX_ROUNDS; t++) {
            if (t > 1) sb.append(',');
            int v = ecPassive(t);
            total += v;
            sb.append(v);
        }
        sb.append("],\"total\":").append(total).append('}');
        System.out.println(sb.toString());
    }

    static void embezzleTable() {
        StringBuilder sb = new StringBuilder();
        sb.append("{\"max_influence\":").append(MAX_INFLUENCE)
          .append(",\"income\":[");
        int[] income = new int[MAX_INFLUENCE + 1];
        for (int x = 1; x <= MAX_INFLUENCE; x++) {
            income[x] = embezzle(x);
            if (x > 1) sb.append(',');
            sb.append(income[x]);
        }
        sb.append("],\"breakpoints\":[");
        boolean first = true;
        int last = 0;
        for (int x = 1; x <= MAX_INFLUENCE; x++) {
            if (income[x] > last) {
                if (!first) sb.append(',');
                sb.append(x);
                first = false;
                last = income[x];
            }
        }
        sb.append("]}");
        System.out.println(sb.toString());
    }

    static int strictCheck() {
        int bad = 0;
        for (int x = 1; x <= MAX_INFLUENCE; x++) {
            if (embezzle(x) != embezzleStrict(x)) {
                System.out.println("DISAGREE x=" + x
                        + " math=" + embezzle(x)
                        + " strict=" + embezzleStrict(x));
                bad++;
            }
        }
        System.out.println("strictcheck: " + bad + " disagreement(s) over [1, "
                + MAX_INFLUENCE + "]");
        return bad;
    }

    // 4096 log-spaced samples in (4096, 1e8]; the Nim side prints the same
    // lines through its fdlibm port and the job diffs them.
    static void tail() {
        final long lo = MAX_INFLUENCE + 1;
        final long hi = 100000000L;
        final int n = 4096;
        long previous = -1;
        for (int i = 0; i < n; i++) {
            double f = (double) i / (double) (n - 1);
            long x = Math.round(Math.exp(Math.log(lo)
                    + f * (Math.log(hi) - Math.log(lo))));
            if (x <= previous) x = previous + 1;
            if (x > hi) break;
            previous = x;
            System.out.println("E " + x + " " + embezzle((int) x));
        }
    }

    public static void main(String[] args) {
        String what = args.length > 0 ? args[0] : "ec_passive";
        if (what.equals("ec_passive")) {
            ecPassiveTable();
        } else if (what.equals("embezzle")) {
            embezzleTable();
        } else if (what.equals("strictcheck")) {
            System.exit(strictCheck() == 0 ? 0 : 1);
        } else if (what.equals("tail")) {
            tail();
        } else {
            System.err.println("unknown mode: " + what);
            System.exit(2);
        }
    }
}
