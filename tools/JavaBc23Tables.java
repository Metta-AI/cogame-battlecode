// Tier B: regenerate the WHOLE FINITE ARITHMETIC DOMAIN of bc23 from the
// released jar's OWN classes, so the committed `data/bc23/tables.json` can be
// byte-diffed against it.
//
// CI-TIME ONLY. Compiled and run by the `parity-oracle-bc23` job under the CI
// TEMURIN 8 against `battlecode23-3.0.15.jar`; there is no JDK in any runtime
// image stage.
//
// bc23 HAS NO TRANSCENDENTAL ANYWHERE -- the only non-integer arithmetic is
// the cooldown multiplier (a float64 product of an exact hundredth), the
// carrier's `floor(0.375f * w) + 5` and `floor(1.25f * w)` (both exact in
// float32 for w <= 40), and the float32 conquest division -- so unlike bc21
// this tier is not a sample. It is the entire domain:
//
//   * the whole `RobotType` table, 10 fields x 6 types;
//   * the whole `Anchor` table, 8 fields x 2;
//   * `floor(CARRIER_MOVEMENT_SLOPE * w) + CARRIER_MOVEMENT_INTERCEPT` for
//     EVERY reachable cargo weight 0..40;
//   * `floor(CARRIER_DAMAGE_FACTOR * w)` for every weight 0..40;
//   * THE ENTIRE COOLDOWN-MULTIPLIER LATTICE: every reachable multiplier
//     (1.00 + cloud 0.20 - 0.10 per boost stack 0..3 + 0.10 per destabilise
//     stack 0..2 - 0.15 for the accelerating anchor, each step re-quantised
//     by `Math.round(x*100.0)/100.0` exactly as GameWorld does) x every base
//     cooldown in {2, 10, 15, 20, 25, 70, 140} AND every carrier base 5..20,
//     as `(int) Math.round(base * multiplier)` computed by the JVM itself;
//   * the conquest threshold `((float) held) / total >= 0.75f` for every
//     island count 4..35 and every held count;
//   * the island occupancy `(100 * (a - b)) / area` for every (a, b) pair up
//     to area 20.
//
//   javac -nowarn -encoding UTF-8 -cp <jar> -d classes tools/JavaBc23Tables.java
//   java -cp <jar>:classes JavaBc23Tables tables
//   java -cp <jar>:classes JavaBc23Tables constants   # every field, printed
//
// NO --release, NO -source, NO -target: `--release` arrived in JDK 9 and dies
// with "invalid flag" on a JDK-8 javac in seconds (the bc21 lesson). The
// compiler IS 8, so the target is 8.
import battlecode.common.Anchor;
import battlecode.common.GameConstants;
import battlecode.common.RobotType;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.TreeSet;

public final class JavaBc23Tables {

    static String q(String s) { return "\"" + s + "\""; }

    /** The engine's own accumulation, step for step. */
    static double quantise(double x) { return Math.round(x * 100.0) / 100.0; }

    static TreeSet<Integer> reachableHundredths() {
        TreeSet<Integer> out = new TreeSet<Integer>();
        for (int cloud = 0; cloud <= 1; cloud++) {
            for (int boosts = 0; boosts <= GameConstants.MAX_BOOST_STACKS; boosts++) {
                for (int destab = 0; destab <= GameConstants.MAX_DESTABILIZE_STACKS; destab++) {
                    for (int anchor = 0; anchor <= GameConstants.MAX_ANCHOR_STACKS; anchor++) {
                        double m = 1.0;
                        if (cloud == 1) { m += GameConstants.CLOUD_MULTIPLIER; m = quantise(m); }
                        for (int i = 0; i < boosts; i++) { m += GameConstants.BOOSTER_MULTIPLIER; m = quantise(m); }
                        for (int i = 0; i < destab; i++) { m += GameConstants.DESTABILIZER_MULTIPLIER; m = quantise(m); }
                        for (int i = 0; i < anchor; i++) { m += GameConstants.ANCHOR_MULTIPLIER; m = quantise(m); }
                        out.add(Integer.valueOf((int) Math.round(m * 100.0)));
                    }
                }
            }
        }
        return out;
    }

    static void tables() {
        StringBuilder b = new StringBuilder();
        b.append("{\n");

        // --- the RobotType table, all ten fields x six types ------------
        b.append("  ").append(q("robot_types")).append(": {\n");
        List<String> rows = new ArrayList<String>();
        for (RobotType t : RobotType.values()) {
            rows.add("    " + q(t.name()) + ": ["
                + t.buildCostAdamantium + ", " + t.buildCostMana + ", "
                + t.buildCostElixir + ", " + t.actionCooldown + ", "
                + t.movementCooldown + ", " + t.health + ", " + t.damage + ", "
                + t.actionRadiusSquared + ", " + t.visionRadiusSquared + ", "
                + t.bytecodeLimit + "]");
        }
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- the Anchor table, all eight fields x two -------------------
        b.append("  ").append(q("anchors")).append(": {\n");
        rows = new ArrayList<String>();
        for (Anchor a : Anchor.values()) {
            rows.add("    " + q(a.name()) + ": ["
                + a.totalHealth + ", " + a.unitsAffected + ", "
                + a.accelerationFactor + ", " + a.healingFrequency + ", "
                + a.healingAmount + ", " + a.manaCost + ", "
                + a.adamantiumCost + ", " + a.elixirCost + "]");
        }
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- the carrier's base movement cooldown, every weight 0..40 ---
        b.append("  ").append(q("carrier_move_cooldown")).append(": [");
        rows = new ArrayList<String>();
        for (int w = 0; w <= GameConstants.CARRIER_CAPACITY; w++) {
            rows.add(Integer.toString(
                (int) Math.floor(GameConstants.CARRIER_MOVEMENT_SLOPE * w)
                + GameConstants.CARRIER_MOVEMENT_INTERCEPT));
        }
        b.append(join(rows, ", ")).append("],\n");

        // --- the carrier's throw damage, every weight 0..40 -------------
        b.append("  ").append(q("carrier_throw_damage")).append(": [");
        rows = new ArrayList<String>();
        for (int w = 0; w <= GameConstants.CARRIER_CAPACITY; w++) {
            rows.add(Integer.toString(
                (int) Math.floor(GameConstants.CARRIER_DAMAGE_FACTOR * w)));
        }
        b.append(join(rows, ", ")).append("],\n");

        // --- the reachable multipliers, in integer hundredths -----------
        TreeSet<Integer> hs = reachableHundredths();
        b.append("  ").append(q("reachable_multipliers")).append(": [");
        rows = new ArrayList<String>();
        for (Integer h : hs) rows.add(h.toString());
        b.append(join(rows, ", ")).append("],\n");

        // --- THE ENTIRE COOLDOWN LATTICE --------------------------------
        b.append("  ").append(q("cooldown_lattice")).append(": {\n");
        rows = new ArrayList<String>();
        int[] bases = new int[] {2, 10, 15, 20, 25, 70, 140,
                                 5, 6, 7, 8, 9, 11, 12, 13, 14,
                                 16, 17, 18, 19};
        TreeSet<Integer> allBases = new TreeSet<Integer>();
        for (int base : bases) allBases.add(Integer.valueOf(base));
        for (int base = 5; base <= 20; base++) allBases.add(Integer.valueOf(base));
        for (Integer base : allBases) {
            List<String> cells = new ArrayList<String>();
            for (Integer h : hs) {
                double mult = h.intValue() / 100.0;
                cells.add(Integer.toString(
                    (int) Math.round(base.intValue() * mult)));
            }
            rows.add("    " + q(base.toString()) + ": ["
                + join(cells, ", ") + "]");
        }
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- the float32 conquest threshold, every island count 4..35 ---
        b.append("  ").append(q("islands_to_win")).append(": {\n");
        rows = new ArrayList<String>();
        for (int total = GameConstants.MIN_NUMBER_ISLANDS;
             total <= GameConstants.MAX_NUMBER_ISLANDS; total++) {
            int need = total;
            for (int held = 0; held <= total; held++) {
                if (((float) held) / total
                        >= GameConstants.WIN_PERCENTAGE_OF_ISLANDS_OCCUPIED) {
                    need = held;
                    break;
                }
            }
            rows.add("    " + q(Integer.toString(total)) + ": " + need);
        }
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- the island occupancy formula, every (a, b) up to area 20 ---
        b.append("  ").append(q("occupancy_diff")).append(": {\n");
        rows = new ArrayList<String>();
        for (int area = 1; area <= GameConstants.MAX_ISLAND_AREA; area++) {
            List<String> cells = new ArrayList<String>();
            for (int own = 0; own <= area; own++) {
                for (int enemy = 0; enemy <= area - own; enemy++) {
                    cells.add(Integer.toString((100 * (own - enemy)) / area));
                }
            }
            rows.add("    " + q(Integer.toString(area)) + ": ["
                + join(cells, ", ") + "]");
        }
        b.append(join(rows, ",\n")).append("\n  }\n");

        b.append("}\n");
        System.out.print(b.toString());
    }

    static String join(List<String> parts, String sep) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < parts.size(); i++) {
            if (i > 0) b.append(sep);
            b.append(parts.get(i));
        }
        return b.toString();
    }

    static void constants() throws Exception {
        List<String> names = new ArrayList<String>();
        for (Field f : GameConstants.class.getDeclaredFields()) {
            if (!Modifier.isStatic(f.getModifiers())) continue;
            names.add(f.getName());
        }
        Collections.sort(names);
        for (String name : names) {
            Field f = GameConstants.class.getDeclaredField(name);
            f.setAccessible(true);
            System.out.println(name + "=" + f.get(null));
        }
    }

    public static void main(String[] args) throws Exception {
        String what = args.length > 0 ? args[0] : "tables";
        if ("constants".equals(what)) constants();
        else tables();
        // The sandboxed player threads are non-daemon in this engine; nothing
        // here starts one, but exiting explicitly is the house rule for every
        // bc23 Java entry point.
        System.exit(0);
    }
}
