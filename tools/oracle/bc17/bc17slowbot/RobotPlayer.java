// TIER B' (b) -- `bc17slowbot`: THE BOT THAT IS MEANT TO BE PAUSED.
//
// CI-TIME ONLY, and IT IS NEVER COMPARED AGAINST THE NIM SIDE. It exists so
// that the port's READING of the metering rule is proved rather than
// asserted: this bot burns a calibrated ~20 000 bytecodes in its turn, well
// past every type's limit, and `ci.yml` asserts that the engine DOES pause
// it -- its `bc=` column pegs at the limit and its `A` line stays NOTHING on
// the turns the arithmetic predicts.
//
// The port has no bytecode counter at all: it meters a fixed per-robot
// DecisionOps budget (3 000 archon / 1 500 other / 0 dormant) with NO
// mid-turn resumption, which is divergence V1 in docs/RULES-BC17.md and the
// one behaviour this oracle cannot compare. Tier B' (a) -- the
// `Clock.getBytecodesLeft() < 5000` assertion every COMPARED bot carries --
// proves the engine's pause-and-resume never fired in any game this job
// compares; this bot proves the pause exists and fires where the rule says
// it does. **It carries no headroom assertion, because being over the limit
// is its whole job.**
//
// The burn is a `long` accumulator over a fixed number of iterations so it
// is not optimised away and costs a predictable, JIT-independent number of
// INSTRUMENTED bytecodes (the instrumenter counts bytecodes, not
// wall-clock).
package bc17slowbot;

import battlecode.common.*;

public strictfp class RobotPlayer {
    static long burn = 0;

    public static void run(RobotController rc) throws GameActionException {
        while (true) {
            // ~4 bytecodes an iteration (load, add, store, jump) plus the
            // loop's own compare and increment: 3 000 iterations is about
            // 20 000 instrumented bytecodes, which is over the 10 000-,
            // 15 000- and 20 000-bytecode limits of every non-archon type
            // and two thirds of an archon's 30 000.
            for (int i = 0; i < 3000; i++) {
                burn += i;
            }
            Clock.yield();
        }
    }
}
