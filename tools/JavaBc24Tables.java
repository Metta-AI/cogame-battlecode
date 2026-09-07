// Regenerates the committed bc24 skill table from THE JAR'S OWN CLASSES, and
// cross-checks every gameplay constant in the released 3.0.5 jar against the
// values `tools/gen_year_constants.py --year bc24` read out of the pinned
// master sources.
//
// CI-TIME ONLY. There is no JDK, no JRE and no Java in ANY runtime image
// stage; this file is compiled and run by the `parity-oracle-bc24` job of
// .github/workflows/ci.yml, which then BYTE-DIFFS the output against
// data/bc24/skills.json. A hand-edited table fails the build.
//
// Unlike bc20's water table and bc21's embezzle curve, this table is the WHOLE
// FINITE DOMAIN of bc24's arithmetic, not a sample: 7 levels x {upgrade on,
// off} for damage and heal, and 7 build levels x {explosive, stun, water, dig,
// fill} for cooldowns and crumb costs. bc24 has no transcendental anywhere, so
// Tier B is a proof rather than an argument.
//
// THE TWO ROUNDING REGIMES ARE THE POINT. Read them off the engine, not the
// spec:
//
//   * damage  = Math.round(base * ((float) SkillType.ATTACK.getSkillEffect(l)
//                                  / 100 + 1))      -- a FLOAT32 product
//   * heal    = Math.round(base * ((float) SkillType.HEAL.getSkillEffect(l)
//                                  / 100 + 1))      -- a FLOAT32 product
//   * every cooldown and every crumb cost
//             = (int) Math.round(C * (1 + .01 * pct))  -- a FLOAT64 product
//
// `.01` is a double literal, so the second family widens; `(float) x / 100`
// keeps the first family in float32. `Math.round(float)` and
// `Math.round(double)` are different methods with different results.
//
//   javac -source 8 -target 8 -cp battlecode24-3.0.5.jar -d out \
//         tools/JavaBc24Tables.java
//   java -cp battlecode24-3.0.5.jar:out JavaBc24Tables skills > out.json
//   java -cp battlecode24-3.0.5.jar:out JavaBc24Tables constants
//   java -cp battlecode24-3.0.5.jar:out JavaBc24Tables specversion

import battlecode.common.GameConstants;
import battlecode.common.GlobalUpgrade;
import battlecode.common.SkillType;
import battlecode.common.TrapType;

public final class JavaBc24Tables {

    // --- the engine's own two regimes, called through the jar's classes ---

    static int damage(int level, boolean upgraded) {
        int base = SkillType.ATTACK.skillEffect;
        if (upgraded) base += GlobalUpgrade.ATTACK.baseAttackChange;
        return Math.round(base * ((float) SkillType.ATTACK.getSkillEffect(level) / 100 + 1));
    }

    static int heal(int level, boolean upgraded) {
        int base = SkillType.HEAL.skillEffect;
        if (upgraded) base += GlobalUpgrade.HEALING.baseHealChange;
        return Math.round(base * ((float) SkillType.HEAL.getSkillEffect(level) / 100 + 1));
    }

    static int attackCooldown(int level) {
        return (int) Math.round(GameConstants.ATTACK_COOLDOWN
                * (1 + .01 * SkillType.ATTACK.getCooldown(level)));
    }

    static int healCooldown(int level) {
        return (int) Math.round(GameConstants.HEAL_COOLDOWN
                * (1 + .01 * SkillType.HEAL.getCooldown(level)));
    }

    static int buildCooldown(int base, int level) {
        return (int) Math.round(base * (1 + .01 * SkillType.BUILD.getCooldown(level)));
    }

    static int buildCost(int base, int level) {
        return (int) Math.round(base * (1 + 0.01 * SkillType.BUILD.getSkillEffect(level)));
    }

    static void row(StringBuilder sb, String key, int[] values) {
        sb.append('"').append(key).append("\":[");
        for (int i = 0; i < values.length; i++) {
            if (i > 0) sb.append(',');
            sb.append(values[i]);
        }
        sb.append(']');
    }

    static int[] over7(java.util.function.IntUnaryOperator f) {
        int[] out = new int[7];
        for (int l = 0; l <= 6; l++) out[l] = f.applyAsInt(l);
        return out;
    }

    static void skills() {
        StringBuilder sb = new StringBuilder();
        sb.append('{');
        sb.append("\"engine\":\"battlecode24\",\"levels\":7,");
        row(sb, "attack_xp", over7(l -> SkillType.ATTACK.getExperience(l)));
        sb.append(',');
        row(sb, "build_xp", over7(l -> SkillType.BUILD.getExperience(l)));
        sb.append(',');
        row(sb, "heal_xp", over7(l -> SkillType.HEAL.getExperience(l)));
        sb.append(',');
        row(sb, "damage", over7(l -> damage(l, false)));
        sb.append(',');
        row(sb, "damage_upgraded", over7(l -> damage(l, true)));
        sb.append(',');
        row(sb, "heal", over7(l -> heal(l, false)));
        sb.append(',');
        row(sb, "heal_upgraded", over7(l -> heal(l, true)));
        sb.append(',');
        row(sb, "attack_cooldown", over7(JavaBc24Tables::attackCooldown));
        sb.append(',');
        row(sb, "heal_cooldown", over7(JavaBc24Tables::healCooldown));
        sb.append(',');
        row(sb, "dig_cost", over7(l -> buildCost(GameConstants.DIG_COST, l)));
        sb.append(',');
        row(sb, "fill_cost", over7(l -> buildCost(GameConstants.FILL_COST, l)));
        sb.append(',');
        row(sb, "dig_cooldown", over7(l -> buildCooldown(GameConstants.DIG_COOLDOWN, l)));
        sb.append(',');
        row(sb, "fill_cooldown", over7(l -> buildCooldown(GameConstants.FILL_COOLDOWN, l)));
        sb.append(',');
        row(sb, "explosive_cost", over7(l -> buildCost(TrapType.EXPLOSIVE.buildCost, l)));
        sb.append(',');
        row(sb, "stun_cost", over7(l -> buildCost(TrapType.STUN.buildCost, l)));
        sb.append(',');
        row(sb, "water_cost", over7(l -> buildCost(TrapType.WATER.buildCost, l)));
        sb.append(',');
        row(sb, "trap_cooldown",
            over7(l -> buildCooldown(TrapType.EXPLOSIVE.actionCooldownIncrease, l)));
        sb.append(',');
        row(sb, "jail_penalty_attack", over7(l -> SkillType.ATTACK.getPenalty(l)));
        sb.append(',');
        row(sb, "jail_penalty_build", over7(l -> SkillType.BUILD.getPenalty(l)));
        sb.append(',');
        row(sb, "jail_penalty_heal", over7(l -> SkillType.HEAL.getPenalty(l)));
        sb.append('}');
        System.out.println(sb.toString());
    }

    /** The values `constants.nim` claims, cross-checked against the JAR. */
    static int constants() {
        int bad = 0;
        bad += eq("GAME_MAX_NUMBER_OF_ROUNDS", GameConstants.GAME_MAX_NUMBER_OF_ROUNDS, 2000);
        bad += eq("SETUP_ROUNDS", GameConstants.SETUP_ROUNDS, 200);
        bad += eq("ROBOT_CAPACITY", GameConstants.ROBOT_CAPACITY, 50);
        bad += eq("NUMBER_FLAGS", GameConstants.NUMBER_FLAGS, 3);
        bad += eq("DEFAULT_HEALTH", GameConstants.DEFAULT_HEALTH, 1000);
        bad += eq("JAILED_ROUNDS", GameConstants.JAILED_ROUNDS, 25);
        bad += eq("INITIAL_CRUMBS_AMOUNT", GameConstants.INITIAL_CRUMBS_AMOUNT, 400);
        bad += eq("PASSIVE_CRUMBS_INCREASE", GameConstants.PASSIVE_CRUMBS_INCREASE, 10);
        bad += eq("KILL_CRUMB_REWARD", GameConstants.KILL_CRUMB_REWARD, 30);
        bad += eq("GLOBAL_UPGRADE_ROUNDS", GameConstants.GLOBAL_UPGRADE_ROUNDS, 600);
        bad += eq("VISION_RADIUS_SQUARED", GameConstants.VISION_RADIUS_SQUARED, 20);
        bad += eq("ATTACK_RADIUS_SQUARED", GameConstants.ATTACK_RADIUS_SQUARED, 4);
        bad += eq("HEAL_RADIUS_SQUARED", GameConstants.HEAL_RADIUS_SQUARED, 4);
        bad += eq("INTERACT_RADIUS_SQUARED", GameConstants.INTERACT_RADIUS_SQUARED, 2);
        bad += eq("COOLDOWN_LIMIT", GameConstants.COOLDOWN_LIMIT, 10);
        bad += eq("COOLDOWNS_PER_TURN", GameConstants.COOLDOWNS_PER_TURN, 10);
        bad += eq("MOVEMENT_COOLDOWN", GameConstants.MOVEMENT_COOLDOWN, 10);
        bad += eq("FLAG_MOVEMENT_COOLDOWN", GameConstants.FLAG_MOVEMENT_COOLDOWN, 20);
        bad += eq("ATTACK_COOLDOWN", GameConstants.ATTACK_COOLDOWN, 20);
        bad += eq("HEAL_COOLDOWN", GameConstants.HEAL_COOLDOWN, 30);
        bad += eq("DIG_COST", GameConstants.DIG_COST, 20);
        bad += eq("DIG_COOLDOWN", GameConstants.DIG_COOLDOWN, 20);
        bad += eq("FILL_COST", GameConstants.FILL_COST, 30);
        bad += eq("FILL_COOLDOWN", GameConstants.FILL_COOLDOWN, 30);
        bad += eq("PICKUP_DROP_COOLDOWN", GameConstants.PICKUP_DROP_COOLDOWN, 10);
        bad += eq("FLAG_DROPPED_RESET_ROUNDS", GameConstants.FLAG_DROPPED_RESET_ROUNDS, 4);
        bad += eq("FLAG_BROADCAST_UPDATE_INTERVAL",
                  GameConstants.FLAG_BROADCAST_UPDATE_INTERVAL, 100);
        bad += eq("FLAG_BROADCAST_NOISE_RADIUS",
                  GameConstants.FLAG_BROADCAST_NOISE_RADIUS, 100);
        bad += eq("MIN_FLAG_SPACING_SQUARED", GameConstants.MIN_FLAG_SPACING_SQUARED, 36);
        bad += eq("SHARED_ARRAY_LENGTH", GameConstants.SHARED_ARRAY_LENGTH, 64);
        bad += eq("MAX_SHARED_ARRAY_VALUE", GameConstants.MAX_SHARED_ARRAY_VALUE, 65535);
        bad += eq("MAP_MIN_WIDTH", GameConstants.MAP_MIN_WIDTH, 20);
        bad += eq("MAP_MAX_WIDTH", GameConstants.MAP_MAX_WIDTH, 60);
        bad += eq("MAP_MIN_HEIGHT", GameConstants.MAP_MIN_HEIGHT, 20);
        bad += eq("MAP_MAX_HEIGHT", GameConstants.MAP_MAX_HEIGHT, 60);
        bad += eq("BYTECODE_LIMIT", GameConstants.BYTECODE_LIMIT, 25000);
        bad += eq("EXPLOSIVE.buildCost", TrapType.EXPLOSIVE.buildCost, 200);
        bad += eq("EXPLOSIVE.triggerRadius", TrapType.EXPLOSIVE.triggerRadius, 0);
        bad += eq("EXPLOSIVE.enterRadius", TrapType.EXPLOSIVE.enterRadius, 4);
        bad += eq("EXPLOSIVE.interactRadius", TrapType.EXPLOSIVE.interactRadius, 2);
        bad += eq("EXPLOSIVE.enterDamage", TrapType.EXPLOSIVE.enterDamage, 750);
        bad += eq("EXPLOSIVE.interactDamage", TrapType.EXPLOSIVE.interactDamage, 200);
        bad += eq("STUN.buildCost", TrapType.STUN.buildCost, 100);
        bad += eq("STUN.triggerRadius", TrapType.STUN.triggerRadius, 2);
        bad += eq("STUN.enterRadius", TrapType.STUN.enterRadius, 13);
        bad += eq("STUN.opponentCooldown", TrapType.STUN.opponentCooldown, 40);
        bad += eq("WATER.buildCost", TrapType.WATER.buildCost, 100);
        bad += eq("WATER.triggerRadius", TrapType.WATER.triggerRadius, 2);
        bad += eq("WATER.enterRadius", TrapType.WATER.enterRadius, 9);
        bad += eq("ATTACK upgrade", GlobalUpgrade.ATTACK.baseAttackChange, 60);
        bad += eq("HEALING upgrade", GlobalUpgrade.HEALING.baseHealChange, 50);
        bad += eq("CAPTURING delay", GlobalUpgrade.CAPTURING.flagReturnDelayChange, 21);
        bad += eq("CAPTURING movement", GlobalUpgrade.CAPTURING.movementDelayChange, -8);
        System.out.println("constants: " + bad + " disagreement(s) between the "
                + "3.0.5 jar and the pinned master sources");
        return bad;
    }

    static int eq(String name, int actual, int expected) {
        if (actual == expected) return 0;
        System.out.println("DISAGREE " + name + " jar=" + actual
                + " sources=" + expected);
        return 1;
    }

    public static void main(String[] args) {
        String what = args.length > 0 ? args[0] : "skills";
        if (what.equals("skills")) {
            skills();
        } else if (what.equals("constants")) {
            System.exit(constants() == 0 ? 0 : 1);
        } else if (what.equals("specversion")) {
            System.out.println(GameConstants.SPEC_VERSION);
        } else {
            System.err.println("unknown mode: " + what);
            System.exit(2);
        }
    }
}
