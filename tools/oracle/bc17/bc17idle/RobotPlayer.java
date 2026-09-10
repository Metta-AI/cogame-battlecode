// TIER A's bot: `while (true) Clock.yield();`, and nothing else.
//
// CI-TIME ONLY (the `parity-oracle-bc17` job). Its Nim twin is the
// `-d:bc17Idle` build of `tools/parity_trace_bc17.nim`, whose
// `runControllerFor` is a bare `discard`.
//
// **THIS TIER IS DELIBERATELY SMALL AND THAT IS WORTH SAYING**: in 2017
// nothing happens without a player action -- no NPCs, no passive spawning, no
// terrain change -- so what an idle pair proves is the round counter, the
// initial exec order off the map file, the neutral-tree pass (up to 1 228
// trees a round on `LineOfFire`, every one of them taking
// `processBeginningOfRound` and `roundsAlive++` and returning zero income),
// the trove machinery idle, THE INCOME CLIFF (`max(0, 2 - 0.01 * supply)` is
// exactly zero at any supply of 200 or more and both teams start at 300, so
// 2 999 rounds of nothing end at exactly 300.0), and the round-limit ladder
// falling through to rung 4.
//
// TIER B' (a): the headroom assertion every bot in this job carries. Under
// the instrumenter `java.lang.System` is rewritten to
// `battlecode/instrumenter/inject/System`, whose `exit(int)` throws
// `RobotDeathException` -- so this kills the robot rather than the JVM, the
// robot vanishes from the trace, and the pair diverges on that round. That is
// the point: the engine's own pause-and-resume must PROVABLY never fire in
// any game this job compares, because the port meters a fixed DecisionOps
// budget instead and has no mid-turn resumption (docs/RULES-BC17.md V1).
package bc17idle;

import battlecode.common.*;

public strictfp class RobotPlayer {
    public static void run(RobotController rc) throws GameActionException {
        while (true) {
            if (Clock.getBytecodesLeft() < 5000) {
                System.exit(4);
            }
            Clock.yield();
        }
    }
}
