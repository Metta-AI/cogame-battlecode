// TIER A. A bot whose `turn()` returns nothing at all.
//
// THIS TIER IS DELIBERATELY SMALL, and that is the single most important
// difference between bc19 parity and bc16 parity. In bc16 the zombies are
// ENGINE-SIDE, so an idle player still exercises half the game. IN BC19
// NOTHING AT ALL HAPPENS WITHOUT A PLAYER ACTION -- no NPCs, no terrain
// change, no passive spawning.
//
// What it does prove, and it is worth having and cheap: the turn queue and
// `robin`, the round counter, the FLAT 25-fuel-per-team-per-round trickle,
// the initial castles' id draws off the committed MT19937 state, the points
// at which `isOver` is evaluated, and the round-limit ladder -- both sides
// keep every castle and end level on castles and on health, so the coin flip
// with the engine's `win_condition = 1` overwrite fires on every pair.
//
// Its Nim twin is `-d:bc19Idle` in `src/battlecode/years/bc19/rules.nim`.
'use strict';

module.exports = function (BCAbstractRobot, SPECS) {
  class Bc19Idle extends BCAbstractRobot {
    turn() {
      return null;
    }
  }
  return new Bc19Idle();
};
