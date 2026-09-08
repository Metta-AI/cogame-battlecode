// Tier B: regenerate the WHOLE FINITE ARITHMETIC DOMAIN of bc22 from the
// released jar's OWN classes, so the committed `data/bc22/tables.json` can be
// byte-diffed against it.
//
// CI-TIME ONLY. Compiled and run by the `parity-oracle-bc22` job under the CI
// TEMURIN 8 against `battlecode22-2.2.1.jar`; there is no JDK in any runtime
// image stage.
//
// bc22 has exactly ONE transcendental -- the laboratory's transmutation rate,
// `(int)(20.0 - 18.0 * Math.exp(-k*n))` -- and its domain is finite
// (3 levels x n in 0..176), so unlike bc21 this tier is not a sample. It is
// the entire domain:
//
//   * the whole `RobotType` table, 9 constructor fields x 7 types, plus every
//     per-level getMaxHealth / getDamage / getHealing / getLeadMutateCost /
//     getGoldMutateCost / getLeadWorth / getGoldWorth / getLeadDropped /
//     getGoldDropped value;
//   * the whole `AnomalyType` table, 4 fields x 4;
//   * THE ENTIRE RUBBLE COOLDOWN LATTICE: `(int)((1 + r/10.0) * c)` for
//     rubble 0..100 x base in {2, 10, 16, 20, 24, 25, 100, 200}, computed by
//     the JVM itself -- 808 entries, of which the ones that DIFFER from the
//     integer form `((10+r)*c)/10` are listed separately so a reviewer can
//     see them (measured: 22 of them, always one lower);
//   * the prototype health `(int)(0.8f * hp)` for all nine building health
//     values;
//   * the reclaim `(int)(worth * 0.2f)` for every reachable worth;
//   * the four anomaly truncations over their whole reachable domains:
//     ABYSS `(int)(0.1f*m)` and `(int)(0.99f*m)` for m 0..1000 plus a decade
//     sample above it, CHARGE `(int)(0.05f*n)` for n 0..500, CHARGE-sage
//     `(int)(0.22f*hp)` and FURY `(int)(hp*0.05f)` / `* 0.1f` for all nine
//     health values;
//   * the LABORATORY RATE `(int)(20.0 - 18.0*Math.exp(-k*n))` for all
//     3 x 177 (level, n) pairs.
//
//   javac -nowarn -encoding UTF-8 -cp <jar> -d classes tools/JavaBc22Tables.java
//   java -cp <jar>:classes JavaBc22Tables tables
//   java -cp <jar>:classes JavaBc22Tables constants   # every field, printed
//
// NO --release, NO -source, NO -target: `--release` arrived in JDK 9 and dies
// with "invalid flag" on a JDK-8 javac in seconds (the bc21 lesson). The
// compiler IS 8, so the target is 8.
import battlecode.common.AnomalyType;
import battlecode.common.GameConstants;
import battlecode.common.RobotType;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.TreeSet;

public final class JavaBc22Tables {

    static String q(String s) { return "\"" + s + "\""; }

    static final int[] COOLDOWN_BASES = new int[] {2, 10, 16, 20, 24, 25, 100, 200};

    /** Every health value a building can reach, ascending. */
    static TreeSet<Integer> buildingHealths() {
        TreeSet<Integer> out = new TreeSet<Integer>();
        for (RobotType t : RobotType.values()) {
            if (!t.isBuilding()) continue;
            for (int level = 1; level <= GameConstants.MAX_LEVEL; level++)
                out.add(Integer.valueOf(t.getMaxHealth(level)));
        }
        return out;
    }

    /** Every net worth a live robot can carry, ascending. */
    static TreeSet<Integer> reachableWorths() {
        TreeSet<Integer> out = new TreeSet<Integer>();
        for (RobotType t : RobotType.values()) {
            for (int level = 1; level <= GameConstants.MAX_LEVEL; level++) {
                out.add(Integer.valueOf(t.getLeadWorth(level)));
                out.add(Integer.valueOf(t.getGoldWorth(level)));
            }
        }
        return out;
    }

    static void tables() {
        StringBuilder b = new StringBuilder();
        b.append("{\n");
        b.append("  ").append(q("spec_version")).append(": ")
         .append(q(GameConstants.SPEC_VERSION)).append(",\n");

        // --- the RobotType constructor table, nine fields x seven types ---
        b.append("  ").append(q("robot_types")).append(": {\n");
        List<String> rows = new ArrayList<String>();
        for (RobotType t : RobotType.values()) {
            rows.add("    " + q(t.name()) + ": ["
                + t.buildCostLead + ", " + t.buildCostGold + ", "
                + t.actionCooldown + ", " + t.movementCooldown + ", "
                + t.health + ", " + t.damage + ", "
                + t.actionRadiusSquared + ", " + t.visionRadiusSquared + ", "
                + t.bytecodeLimit + "]");
        }
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- every per-level derived value, all seven types --------------
        String[] fns = new String[] {
            "max_health", "damage", "healing", "lead_mutate_cost",
            "gold_mutate_cost", "lead_worth", "gold_worth",
            "lead_dropped", "gold_dropped"
        };
        for (int f = 0; f < fns.length; f++) {
            b.append("  ").append(q(fns[f])).append(": {\n");
            rows = new ArrayList<String>();
            for (RobotType t : RobotType.values()) {
                List<String> cells = new ArrayList<String>();
                for (int level = 1; level <= GameConstants.MAX_LEVEL; level++) {
                    int v;
                    switch (f) {
                        case 0: v = t.getMaxHealth(level); break;
                        case 1: v = t.getDamage(level); break;
                        case 2: v = t.getHealing(level); break;
                        case 3: v = t.getLeadMutateCost(level); break;
                        case 4: v = t.getGoldMutateCost(level); break;
                        case 5: v = t.getLeadWorth(level); break;
                        case 6: v = t.getGoldWorth(level); break;
                        case 7: v = t.getLeadDropped(level); break;
                        default: v = t.getGoldDropped(level); break;
                    }
                    cells.add(Integer.toString(v));
                }
                rows.add("    " + q(t.name()) + ": [" + join(cells, ", ") + "]");
            }
            b.append(join(rows, ",\n")).append("\n  },\n");
        }

        // --- the AnomalyType table, four fields x four -------------------
        b.append("  ").append(q("anomalies")).append(": {\n");
        rows = new ArrayList<String>();
        for (AnomalyType a : AnomalyType.values()) {
            rows.add("    " + q(a.name()) + ": ["
                + (a.isGlobalAnomaly ? 1 : 0) + ", "
                + (a.isSageAnomaly ? 1 : 0) + ", "
                + a.globalPercentage + ", " + a.sagePercentage + "]");
        }
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- THE ENTIRE RUBBLE COOLDOWN LATTICE --------------------------
        // `(int) ((1 + rubble / 10.0) * cooldown)` -- a float64 divide, a
        // float64 multiply and a TRUNCATION, computed by the JVM itself.
        b.append("  ").append(q("rubble_cooldown")).append(": {\n");
        rows = new ArrayList<String>();
        List<String> differing = new ArrayList<String>();
        for (int i = 0; i < COOLDOWN_BASES.length; i++) {
            int base = COOLDOWN_BASES[i];
            List<String> cells = new ArrayList<String>();
            for (int r = GameConstants.MIN_RUBBLE; r <= GameConstants.MAX_RUBBLE; r++) {
                int f64 = (int) ((1 + r / 10.0) * base);
                cells.add(Integer.toString(f64));
                int integerForm = ((10 + r) * base) / 10;
                if (f64 != integerForm)
                    differing.add("[" + base + ", " + r + ", " + f64 + ", "
                                  + integerForm + "]");
            }
            rows.add("    " + q(Integer.toString(base)) + ": ["
                     + join(cells, ", ") + "]");
        }
        b.append(join(rows, ",\n")).append("\n  },\n");
        b.append("  ").append(q("rubble_cooldown_float_differs")).append(": [")
         .append(join(differing, ", ")).append("],\n");

        // --- the prototype health, all nine building health values -------
        b.append("  ").append(q("prototype_health")).append(": {\n");
        rows = new ArrayList<String>();
        for (Integer hp : buildingHealths())
            rows.add("    " + q(hp.toString()) + ": "
                + (int) (GameConstants.PROTOTYPE_HP_PERCENTAGE * hp.intValue()));
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- the reclaim drop, every reachable worth ---------------------
        b.append("  ").append(q("reclaim")).append(": {\n");
        rows = new ArrayList<String>();
        for (Integer w : reachableWorths())
            rows.add("    " + q(w.toString()) + ": "
                + (int) (w.intValue() * GameConstants.RECLAIM_COST_MULTIPLIER));
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- ABYSS: (int)(0.1f * m) and (int)(0.99f * m) -----------------
        b.append("  ").append(q("abyss_global")).append(": [");
        rows = new ArrayList<String>();
        for (int m = 0; m <= 1000; m++)
            rows.add(Integer.toString(
                (int) (AnomalyType.ABYSS.globalPercentage * m)));
        b.append(join(rows, ", ")).append("],\n");
        b.append("  ").append(q("abyss_sage")).append(": [");
        rows = new ArrayList<String>();
        for (int m = 0; m <= 1000; m++)
            rows.add(Integer.toString(
                (int) (AnomalyType.ABYSS.sagePercentage * m)));
        b.append(join(rows, ", ")).append("],\n");
        b.append("  ").append(q("abyss_global_decades")).append(": {\n");
        rows = new ArrayList<String>();
        for (int m = 2000; m <= 20000; m += 1000)
            rows.add("    " + q(Integer.toString(m)) + ": ["
                + (int) (AnomalyType.ABYSS.globalPercentage * m) + ", "
                + (int) (AnomalyType.ABYSS.sagePercentage * m) + "]");
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- CHARGE: (int)(0.05f * n) for n 0..500 -----------------------
        b.append("  ").append(q("charge_cut")).append(": [");
        rows = new ArrayList<String>();
        for (int n = 0; n <= 500; n++)
            rows.add(Integer.toString(
                (int) (AnomalyType.CHARGE.globalPercentage * n)));
        b.append(join(rows, ", ")).append("],\n");

        // --- CHARGE-sage and FURY, over all nine health values -----------
        b.append("  ").append(q("charge_sage_damage")).append(": {\n");
        rows = new ArrayList<String>();
        TreeSet<Integer> allHealths = new TreeSet<Integer>(buildingHealths());
        for (RobotType t : RobotType.values())
            for (int level = 1; level <= GameConstants.MAX_LEVEL; level++)
                allHealths.add(Integer.valueOf(t.getMaxHealth(level)));
        for (Integer hp : allHealths)
            rows.add("    " + q(hp.toString()) + ": "
                + (int) (-1 * AnomalyType.CHARGE.sagePercentage * hp.intValue()));
        b.append(join(rows, ",\n")).append("\n  },\n");

        b.append("  ").append(q("fury_damage")).append(": {\n");
        rows = new ArrayList<String>();
        for (Integer hp : buildingHealths())
            rows.add("    " + q(hp.toString()) + ": ["
                + (int) (-1 * hp.intValue() * AnomalyType.FURY.globalPercentage)
                + ", "
                + (int) (-1 * hp.intValue() * AnomalyType.FURY.sagePercentage)
                + "]");
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- THE LABORATORY RATE, all 3 x 177 pairs ----------------------
        // n is the friendly robots a lab can see inside r2 <= 53, i.e. the
        // 177 squares of that disc minus itself: 0..176.
        b.append("  ").append(q("transmute_rate")).append(": {\n");
        rows = new ArrayList<String>();
        double[] ks = new double[] {
            GameConstants.ALCHEMIST_LONELINESS_K_L1,
            GameConstants.ALCHEMIST_LONELINESS_K_L2,
            GameConstants.ALCHEMIST_LONELINESS_K_L3
        };
        for (int level = 1; level <= 3; level++) {
            List<String> cells = new ArrayList<String>();
            for (int n = 0; n <= 176; n++)
                cells.add(Integer.toString((int) (
                    GameConstants.ALCHEMIST_LONELINESS_A
                    - GameConstants.ALCHEMIST_LONELINESS_B
                      * Math.exp(-ks[level - 1] * n))));
            rows.add("    " + q(Integer.toString(level)) + ": ["
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
        // bc22 Java entry point.
        System.exit(0);
    }
}
