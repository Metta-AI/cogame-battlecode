// Tier B: regenerate the WHOLE FINITE ARITHMETIC DOMAIN of bc25 from the
// released jar's OWN classes, so the committed `data/bc25/tables.json` can be
// byte-diffed against it.
//
// CI-TIME ONLY. Compiled and run by the `parity-oracle-bc25` job under the CI
// JDK 21 against `battlecode25-java-3.1.0.jar`; there is no JDK in any runtime
// image stage.
//
// bc25 HAS NO TRANSCENDENTAL ANYWHERE AND NO FLOAT32 ANYWHERE -- the only
// floating point in the whole round loop is `Math.round(double)` in four
// places -- so unlike bc21 this tier is not a sample. It is the entire domain:
//
//   * the whole `UnitType` table, 13 fields x 12 types;
//   * `round(paint * 100.0 / capacity)` for EVERY (paint, capacity) pair over
//     the three robot capacities and 1000 for towers;
//   * the cooldown surcharge for every paint percentage 0..100 x every base
//     cooldown the rule set uses {10, 20, 30, 50};
//   * `round(painted * 1000.0 / areaWithoutWalls)` over every
//     `areaWithoutWalls` a 20..60 map can have, at the 70 % boundary and its
//     two neighbours;
//   * the four pattern bit tables.
//
//   javac -nowarn -encoding UTF-8 -cp <jar> -d classes tools/JavaBc25Tables.java
//   java --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
//        -cp <jar>:classes JavaBc25Tables tables
//   java ... JavaBc25Tables constants     # every GameConstants field, printed
//   java ... JavaBc25Tables specversion   # the useless literal "1"
import battlecode.common.GameConstants;
import battlecode.common.UnitType;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class JavaBc25Tables {

    static String q(String s) { return "\"" + s + "\""; }

    /** `InternalRobot.addActionCooldownTurns`, from the jar's own constants. */
    static int surcharge(int add, int paintPercentage) {
        if (paintPercentage >= GameConstants.INCREASED_COOLDOWN_THRESHOLD) {
            return add;
        }
        return add + (int) Math.round(add
                * (GameConstants.INCREASED_COOLDOWN_INTERCEPT
                   + GameConstants.INCREASED_COOLDOWN_SLOPE * paintPercentage)
                / 100.0);
    }

    static void tables() {
        StringBuilder sb = new StringBuilder();
        sb.append("{\n");

        sb.append("  \"unit_types\": {\n");
        UnitType[] types = UnitType.values();
        for (int i = 0; i < types.length; i++) {
            UnitType t = types[i];
            sb.append("    ").append(q(t.name())).append(": [")
              .append(t.paintCost).append(',').append(t.moneyCost).append(',')
              .append(t.attackCost).append(',').append(t.health).append(',')
              .append(t.level).append(',').append(t.paintCapacity).append(',')
              .append(t.actionCooldown).append(',')
              .append(t.actionRadiusSquared).append(',')
              .append(t.attackStrength).append(',')
              .append(t.aoeAttackStrength).append(',')
              .append(t.paintPerTurn).append(',').append(t.moneyPerTurn)
              .append(',').append(t.attackMoneyBonus).append(']')
              .append(i + 1 < types.length ? ",\n" : "\n");
        }
        sb.append("  },\n");

        // The paint percentage, over EVERY (paint, capacity) pair.
        sb.append("  \"paint_percentage\": {\n");
        int[] caps = {UnitType.SOLDIER.paintCapacity,
                      UnitType.SPLASHER.paintCapacity,
                      UnitType.MOPPER.paintCapacity,
                      UnitType.LEVEL_ONE_PAINT_TOWER.paintCapacity};
        for (int c = 0; c < caps.length; c++) {
            sb.append("    ").append(q(String.valueOf(caps[c]))).append(": [");
            for (int paint = 0; paint <= caps[c]; paint++) {
                if (paint > 0) sb.append(',');
                sb.append((int) Math.round(paint * 100.0 / caps[c]));
            }
            sb.append(']').append(c + 1 < caps.length ? ",\n" : "\n");
        }
        sb.append("  },\n");

        // The cooldown surcharge, over every base and every percentage.
        sb.append("  \"cooldown_surcharge\": {\n");
        int[] bases = {GameConstants.MOVEMENT_COOLDOWN,
                       GameConstants.ATTACK_MOPPER_SWING_COOLDOWN,
                       UnitType.MOPPER.actionCooldown,
                       UnitType.SPLASHER.actionCooldown};
        for (int b = 0; b < bases.length; b++) {
            sb.append("    ").append(q(String.valueOf(bases[b]))).append(": [");
            for (int p = 0; p <= 100; p++) {
                if (p > 0) sb.append(',');
                sb.append(surcharge(bases[b], p));
            }
            sb.append(']').append(b + 1 < bases.length ? ",\n" : "\n");
        }
        sb.append("  },\n");

        // The coverage per mille at the 70 % boundary and its neighbours, for
        // every areaWithoutWalls a 20..60 map can have.
        sb.append("  \"coverage_permille\": {\n");
        List<String> rows = new ArrayList<>();
        int minArea = GameConstants.MAP_MIN_WIDTH * GameConstants.MAP_MIN_HEIGHT;
        int maxArea = GameConstants.MAP_MAX_WIDTH * GameConstants.MAP_MAX_HEIGHT;
        for (int area = minArea; area <= maxArea; area += 1) {
            int win = (area * GameConstants.PAINT_PERCENT_TO_WIN + 99) / 100;
            StringBuilder r = new StringBuilder();
            r.append("    ").append(q(String.valueOf(area))).append(": [");
            for (int d = -1; d <= 1; d++) {
                if (d > -1) r.append(',');
                r.append((int) Math.round((win + d) * 1000.0 / area));
            }
            r.append(",").append(win).append(']');
            rows.add(r.toString());
        }
        sb.append(String.join(",\n", rows)).append("\n  },\n");

        // The four pattern bit tables, decoded from the four ints.
        sb.append("  \"patterns\": {\n");
        String[] names = {"RESOURCE", "DEFENSE_TOWER", "MONEY_TOWER",
                          "PAINT_TOWER"};
        int[] ints = {GameConstants.RESOURCE_PATTERN,
                      GameConstants.DEFENSE_TOWER_PATTERN,
                      GameConstants.MONEY_TOWER_PATTERN,
                      GameConstants.PAINT_TOWER_PATTERN};
        for (int k = 0; k < names.length; k++) {
            sb.append("    ").append(q(names[k])).append(": [");
            for (int dx = -2; dx <= 2; dx++) {
                for (int dy = -2; dy <= 2; dy++) {
                    if (dx > -2 || dy > -2) sb.append(',');
                    int bitNum = GameConstants.PATTERN_SIZE * (dx + 2) + dy + 2;
                    sb.append((ints[k] >> bitNum) & 1);
                }
            }
            sb.append(']').append(k + 1 < names.length ? ",\n" : "\n");
        }
        sb.append("  }\n}\n");
        System.out.print(sb);
    }

    static void constants() throws Exception {
        List<String> names = new ArrayList<>();
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
        if (what.equals("specversion")) {
            System.out.println(GameConstants.SPEC_VERSION);
        } else if (what.equals("constants")) {
            constants();
        } else {
            tables();
        }
    }
}
