// THE TIER A BOT: `while (true) Clock.yield();` and nothing else.
//
// CI-TIME ONLY.
//
// **Tier A is a REAL AND LARGE TIER for bc16, and that is the single most
// important thing to understand about this year's parity.** The zombie half
// of this game is ENGINE-SIDE, so an idle player still exercises the den
// schedules and their per-den split, the spawn ring's direction and
// chirality, `spawnAllPossible` and its proximity-damage fallback, the whole
// eight-step zombie movement ladder, ALL THREE RNG STREAMS, infection and the
// die-and-turn conversion, the corpse-rubble deposit, `clearRubble` by digging
// zombies, the parts income curve, both factions' archons being eaten, the
// mid-turn `DESTROYED` check, AND the round-2999 ladder on the games where an
// archon survives.
//
// It also spends essentially no bytecodes, so the engine's own
// `amountToDecrement` is exactly 1.0 for the whole game and V1 is not
// exercised at all.
package bc16idle;

import battlecode.common.Clock;
import battlecode.common.RobotController;

public strictfp class RobotPlayer {
    public static void run(RobotController rc) {
        while (true) {
            Clock.yield();
        }
    }
}
