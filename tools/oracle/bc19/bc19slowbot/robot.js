// TIER B' (b), and it is NOT COMPARED AGAINST THE NIM SIDE AT ALL.
//
// The port has no wall clock, so the engine's freeze branch (V1,
// `coldbrew/game.js:806-808`) is the one behaviour this oracle cannot
// compare. This run exists so the port's READING of the rule is PROVED
// rather than asserted: `turn()` busy-loops for a calibrated interval, and
// `bc19_trace.js --expect-freeze` asserts that the engine DOES freeze it --
// `robot.time` goes negative and the robot's `A` line becomes `NOTHING` --
// at the turn the formula `time_{n+1} = time_n + CHESS_EXTRA - elapsed`
// predicts.
//
// The clock starts at `CHESS_INITIAL = 100` ms and gains `CHESS_EXTRA = 20`
// ms a turn, so a turn that burns ~40 ms loses 20 ms of clock a turn and the
// robot is frozen after about six turns. The busy loop is deliberately a
// WALL-CLOCK loop and not a fixed instruction count, because the rule it is
// proving is a wall-clock rule.
'use strict';

const BURN_MS = 40;

module.exports = function (BCAbstractRobot, SPECS) {
  class Bc19SlowBot extends BCAbstractRobot {
    turn() {
      const until = Date.now() + BURN_MS;
      // eslint-disable-next-line no-empty
      while (Date.now() < until) { }
      return null;
    }
  }
  return new Bc19SlowBot();
};
