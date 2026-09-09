// Tier B: regenerate the WHOLE FINITE ARITHMETIC DOMAIN of bc16 from the
// released jar's OWN classes, so the committed `data/bc16/tables.json` can be
// byte-diffed against it.
//
// CI-TIME ONLY. Compiled and run by the `parity-oracle-bc16` job under the CI
// TEMURIN 8 against `battlecode-2016.0.2.2.jar`; there is no JDK in any
// runtime image stage.
//
// bc16 has exactly TWO non-algebraic functions on any gameplay path and BOTH
// have finite domains, so unlike a sampled tier this one is the ENTIRE
// domain:
//
//   * `pow(k/8000.0, 1.5)` for all 8 001 k — the argument of
//     `InternalRobot.decrementDelays` (`:326`), which this port PINS to its
//     1.0 branch (V1). The port does not read this table at run time; it
//     exists so the divergence is MEASURED rather than asserted, and
//     `tests/table_bc16_delay.nim` is what reads it. **Tabled from
//     `StrictMath.pow`, because the engine's `Math.pow` is not reproducible
//     between JDK builds — see the comment at the table itself;**
//   * `(int) Math.sqrt(r2)` for r2 0..10 000 — both radius scans
//     (`GameWorld.java:355`, `MapLocation.java:262`).
//
//   plus, over their own whole finite domains:
//   * the twelve-row `RobotType` table with all seventeen constructor fields
//     and the `turnsInto` graph, read by REFLECTION off the jar's own class;
//   * the eight derived predicates for all twelve types;
//   * the outbreak ladder for levels 0..12, i.e. `type.maxHealth(round)` and
//     `type.attackPower(round)` at every level a 3000-round game can reach
//     and two beyond it;
//   * the guard reduction `damage > 10 ? damage - 4 : damage` and the guard
//     multiplier over every reachable attack power;
//   * the `directionTo` lattice for dx, dy in -80..80 (25 921 pairs), which
//     is the 2.414 threshold form in `MapLocation.java:146-183`;
//   * the rubble clear map `max(0, 0.95r - 10)` over r in 0..1000 plus a
//     decade sample to 10^6;
//   * the parts income `max(0, 2 - 0.01n)` for n = 0..400.
//
//   javac -nowarn -encoding UTF-8 -cp <jar> -d classes tools/JavaBc16Tables.java
//   java -cp <jar>:classes JavaBc16Tables tables
//   java -cp <jar>:classes JavaBc16Tables constants   # every field, printed
//
// NO --release, NO -source, NO -target: `--release` arrived in JDK 9 and dies
// with "invalid flag" on a JDK-8 javac in seconds (the bc21 lesson). The
// compiler IS 8, so the target is 8.
//
// There is NO `SPEC_VERSION` in 2016's `GameConstants` — the field does not
// exist — so `spec_version` below is the jar's own `battlecode-version`
// manifest attribute, passed in by the job.
import battlecode.common.Direction;
import battlecode.common.GameConstants;
import battlecode.common.MapLocation;
import battlecode.common.RobotType;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.TreeSet;

public final class JavaBc16Tables {

    static String q(String s) { return "\"" + s + "\""; }

    /** A double printed so that Nim's own `$` of the same double matches. */
    static String d(double v) {
        if (v == Math.rint(v) && Math.abs(v) < 1e16)
            return Long.toString((long) v) + ".0";
        return Double.toString(v);
    }

    static String join(List<String> parts, String sep) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < parts.size(); i++) {
            if (i > 0) b.append(sep);
            b.append(parts.get(i));
        }
        return b.toString();
    }

    /** The seventeen constructor fields, by reflection off the jar's class. */
    static String robotRow(RobotType t) throws Exception {
        StringBuilder b = new StringBuilder("[");
        b.append(t.isBuilding).append(", ");
        b.append(t.isZombie).append(", ");
        b.append(t.infectTurns).append(", ");
        b.append(q(t.spawnSource == null ? "-" : t.spawnSource.name()))
         .append(", ");
        b.append(t.partCost).append(", ");
        b.append(t.buildTurns).append(", ");
        b.append(d(t.maxHealth)).append(", ");
        b.append(d(t.attackPower)).append(", ");
        b.append(t.attackRadiusSquared).append(", ");
        b.append(d(t.movementDelay)).append(", ");
        b.append(d(t.attackDelay)).append(", ");
        b.append(d(t.cooldownDelay)).append(", ");
        b.append(t.sensorRadiusSquared).append(", ");
        b.append(t.bytecodeLimit).append(", ");
        b.append(q(t.turnsInto == null ? "-" : t.turnsInto.name())).append(", ");
        b.append(t.ignoresRubble).append(", ");
        b.append(t.strengthWeight);
        return b.append("]").toString();
    }

    static String predicateRow(RobotType t) {
        StringBuilder b = new StringBuilder("[");
        b.append(t.canAttack()).append(", ");
        b.append(t.canInfect()).append(", ");
        b.append(t.isInfectable()).append(", ");
        b.append(t.canMove()).append(", ");
        b.append(t.canBuild()).append(", ");
        b.append(t.canMessageSignal()).append(", ");
        b.append(t.isBuildable()).append(", ");
        b.append(t.canClearRubble());
        return b.append("]").toString();
    }

    static void tables(String specVersion) throws Exception {
        StringBuilder b = new StringBuilder();
        b.append("{\n");
        b.append("  ").append(q("spec_version")).append(": ")
         .append(q(specVersion)).append(",\n");

        // --- the twelve-row RobotType table, in values() order ------------
        // The order IS load-bearing: `ZombieCount.compareTo` sorts by ordinal
        // and the den's spawn priority reads it.
        b.append("  ").append(q("robot_type_fields")).append(": [")
         .append(q("isBuilding")).append(", ").append(q("isZombie"))
         .append(", ").append(q("infectTurns")).append(", ")
         .append(q("spawnSource")).append(", ").append(q("partCost"))
         .append(", ").append(q("buildTurns")).append(", ")
         .append(q("maxHealth")).append(", ").append(q("attackPower"))
         .append(", ").append(q("attackRadiusSquared")).append(", ")
         .append(q("movementDelay")).append(", ").append(q("attackDelay"))
         .append(", ").append(q("cooldownDelay")).append(", ")
         .append(q("sensorRadiusSquared")).append(", ")
         .append(q("bytecodeLimit")).append(", ").append(q("turnsInto"))
         .append(", ").append(q("ignoresRubble")).append(", ")
         .append(q("strengthWeight")).append("],\n");

        b.append("  ").append(q("robot_types")).append(": {\n");
        List<String> rows = new ArrayList<String>();
        for (RobotType t : RobotType.values())
            rows.add("    " + q(t.name()) + ": " + robotRow(t));
        b.append(join(rows, ",\n")).append("\n  },\n");

        b.append("  ").append(q("predicate_fields")).append(": [")
         .append(q("canAttack")).append(", ").append(q("canInfect"))
         .append(", ").append(q("isInfectable")).append(", ")
         .append(q("canMove")).append(", ").append(q("canBuild"))
         .append(", ").append(q("canMessageSignal")).append(", ")
         .append(q("isBuildable")).append(", ").append(q("canClearRubble"))
         .append("],\n");
        b.append("  ").append(q("predicates")).append(": {\n");
        rows = new ArrayList<String>();
        for (RobotType t : RobotType.values())
            rows.add("    " + q(t.name()) + ": " + predicateRow(t));
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- the outbreak ladder, levels 0..12 ---------------------------
        // `RobotType.maxHealth(round)` / `attackPower(round)` scale a ZOMBIE
        // at the moment it spawns and never afterwards; a player unit never
        // scales. A 3000-round game reaches level 9 (round 2999 / 300);
        // 10..12 are unreachable and are tabled anyway.
        b.append("  ").append(q("outbreak_multiplier")).append(": [");
        rows = new ArrayList<String>();
        for (int level = 0; level <= 12; level++)
            rows.add(d(RobotType.STANDARDZOMBIE.maxHealth(level * 300)
                       / RobotType.STANDARDZOMBIE.maxHealth));
        b.append(join(rows, ", ")).append("],\n");

        b.append("  ").append(q("outbreak_health")).append(": {\n");
        rows = new ArrayList<String>();
        for (RobotType t : RobotType.values()) {
            List<String> cells = new ArrayList<String>();
            for (int level = 0; level <= 12; level++)
                cells.add(d(t.maxHealth(level * 300)));
            rows.add("    " + q(t.name()) + ": [" + join(cells, ", ") + "]");
        }
        b.append(join(rows, ",\n")).append("\n  },\n");

        b.append("  ").append(q("outbreak_attack")).append(": {\n");
        rows = new ArrayList<String>();
        for (RobotType t : RobotType.values()) {
            List<String> cells = new ArrayList<String>();
            for (int level = 0; level <= 12; level++)
                cells.add(d(t.attackPower(level * 300)));
            rows.add("    " + q(t.name()) + ": [" + join(cells, ", ") + "]");
        }
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- the guard multiplier and reduction ---------------------------
        // `GUARD_ZOMBIE_MULTIPLIER = 2.0` applies when a GUARD attacks a
        // zombie; `GUARD_DAMAGE_REDUCTION = 4.0` comes off any hit ABOVE
        // `GUARD_DEFENSE_THRESHOLD = 10.0` landing ON a guard.
        TreeSet<Double> powers = new TreeSet<Double>();
        for (RobotType t : RobotType.values())
            for (int level = 0; level <= 12; level++) {
                powers.add(Double.valueOf(t.attackPower(level * 300)));
                powers.add(Double.valueOf(t.attackPower(level * 300)
                    * GameConstants.GUARD_ZOMBIE_MULTIPLIER));
            }
        b.append("  ").append(q("guard_reduction")).append(": {\n");
        rows = new ArrayList<String>();
        for (Double p : powers) {
            double raw = p.doubleValue();
            double after = raw > GameConstants.GUARD_DEFENSE_THRESHOLD
                ? raw - GameConstants.GUARD_DAMAGE_REDUCTION : raw;
            rows.add("    " + q(d(raw)) + ": " + d(after));
        }
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- THE `pow(k/8000, 1.5)` TABLE, all 8 001 k (V1, Tier B') ------
        //
        // **`StrictMath.pow`, NOT `Math.pow`, AND THAT IS MEASURED RATHER
        // THAN fastidious.** The engine calls `Math.pow`, whose result the
        // JLS permits to differ from the exact result by up to 1 ulp AND
        // WHICH IS THEREFORE NOT REPRODUCIBLE BETWEEN JDK BUILDS. Measured on
        // Temurin 8u422: `Math.pow` and `StrictMath.pow` disagree on **780 of
        // these 8 001 values**, each by exactly one ulp, first at k = 6 --
        // and the CI runner's Temurin 8u452 disagrees with 8u422 in turn, so
        // a byte-diff of a `Math.pow` table fails for a reason that has
        // nothing to do with this port. `StrictMath.pow` must reproduce
        // fdlibm bit for bit on every conforming JVM, so the committed table
        // is stable, and `ci.yml` separately asserts that the RUNNING JDK's
        // `Math.pow` -- the call the engine actually makes -- is within one
        // ulp of every value here. Both facts are recorded in
        // `docs/PARITY.md` section bc16 and `docs/RULES-BC16.md` V1.
        b.append("  ").append(q("pow_1_5_source"))
         .append(": ").append(q("StrictMath.pow")).append(",\n");
        b.append("  ").append(q("pow_1_5")).append(": [");
        rows = new ArrayList<String>();
        for (int k = 0; k <= 8000; k++)
            rows.add(d(StrictMath.pow(k / 8000.0, 1.5)));
        b.append(join(rows, ", ")).append("],\n");

        // --- (int) Math.sqrt(r2) for r2 0..10 000 -------------------------
        b.append("  ").append(q("int_sqrt")).append(": [");
        rows = new ArrayList<String>();
        for (int r2 = 0; r2 <= 10000; r2++)
            rows.add(Integer.toString((int) Math.sqrt(r2)));
        b.append(join(rows, ", ")).append("],\n");

        // --- THE directionTo LATTICE, dx, dy in -80..80 -------------------
        // 25 921 pairs, flattened row-major with dy outer. Each cell is the
        // `Direction`'s own `ordinal()`, so `NONE` is 8 and `OMNI` 9.
        b.append("  ").append(q("direction_to")).append(": [");
        rows = new ArrayList<String>();
        MapLocation origin = new MapLocation(0, 0);
        for (int dy = -80; dy <= 80; dy++)
            for (int dx = -80; dx <= 80; dx++)
                rows.add(Integer.toString(
                    origin.directionTo(new MapLocation(dx, dy)).ordinal()));
        b.append(join(rows, ", ")).append("],\n");

        // --- the rubble clear map, r 0..1000 plus a decade sample ---------
        b.append("  ").append(q("rubble_clear")).append(": [");
        rows = new ArrayList<String>();
        for (int r = 0; r <= 1000; r++)
            rows.add(d(Math.max(0.0,
                r * (1 - GameConstants.RUBBLE_CLEAR_PERCENTAGE)
                  - GameConstants.RUBBLE_CLEAR_FLAT_AMOUNT)));
        b.append(join(rows, ", ")).append("],\n");

        b.append("  ").append(q("rubble_clear_decades")).append(": {\n");
        rows = new ArrayList<String>();
        for (int e = 1; e <= 6; e++) {
            double r = Math.pow(10, e);
            rows.add("    " + q(d(r)) + ": " + d(Math.max(0.0,
                r * (1 - GameConstants.RUBBLE_CLEAR_PERCENTAGE)
                  - GameConstants.RUBBLE_CLEAR_FLAT_AMOUNT)));
        }
        b.append(join(rows, ",\n")).append("\n  },\n");

        // --- the parts income curve, n = 0..400 ---------------------------
        // `max(0, ARCHON_PART_INCOME - PART_INCOME_UNIT_PENALTY * n)`, which
        // reaches EXACTLY ZERO at 200 robots.
        b.append("  ").append(q("parts_income")).append(": [");
        rows = new ArrayList<String>();
        for (int n = 0; n <= 400; n++)
            rows.add(d(Math.max(0.0, GameConstants.ARCHON_PART_INCOME
                - GameConstants.PART_INCOME_UNIT_PENALTY * n)));
        b.append(join(rows, ", ")).append("],\n");

        // --- the whole GameConstants interface, by reflection -------------
        // 2016's `GameConstants` is an INTERFACE, so its fields carry no
        // `public static final` in the source at all and are implicitly
        // static final in the class file. Reflection therefore sees them all.
        b.append("  ").append(q("constants")).append(": {\n");
        rows = new ArrayList<String>();
        List<String> names = new ArrayList<String>();
        for (Field f : GameConstants.class.getDeclaredFields()) {
            if (!Modifier.isStatic(f.getModifiers())) continue;
            names.add(f.getName());
        }
        Collections.sort(names);
        for (String name : names) {
            Field f = GameConstants.class.getDeclaredField(name);
            f.setAccessible(true);
            Object v = f.get(null);
            String rendered = (v instanceof Double)
                ? d(((Double) v).doubleValue())
                : (v instanceof String ? q((String) v) : String.valueOf(v));
            rows.add("    " + q(name) + ": " + rendered);
        }
        b.append(join(rows, ",\n")).append("\n  }\n");

        b.append("}\n");
        System.out.print(b.toString());
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
        String spec = args.length > 1 ? args[1] : "2016.0.2.2";
        if ("constants".equals(what)) constants();
        else tables(spec);
        // The sandboxed player threads in this engine are NON-DAEMON, so
        // every bc16 Java entry point exits explicitly rather than returning.
        System.exit(0);
    }
}
