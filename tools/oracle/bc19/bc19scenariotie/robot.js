// TIER A'. The round-limit ladder's `more_unit_health` rung, forced -- AND
// the CHURCH, which is the one unit `bc19scenario` cannot afford.
//
// Written line for line against `scenarioTie` in
// `src/battlecode/years/bc19/chassis/scenario19.nim`. RED builds and BLUE
// builds NOTHING, so at the round limit the CASTLE COUNTS ARE LEVEL and the
// TOTAL UNIT HEALTH IS NOT: the ladder takes `more_unit_health` and the
// engine records its own `win_condition = 1`.
//
// RED's chain is PILGRIM -> CHURCH -> CHURCH ATTACK. An order starts with
// 100 karbonite and NO PASSIVE INCOME, a church costs 50 of it, and by the
// time `bc19scenario`'s pilgrim exists its castles have spent the opening
// hundred on the four buildable mobile types -- so the church, and with it
// the LEGAL 0-DAMAGE CHURCH ATTACK (D6.1), can only be reached by a bot
// that buys nothing else. This is that bot.
//
// Reading its own team is the one asymmetry any bot is allowed -- `me.team`
// is in the observation -- and it is what makes this the only scripted way
// to reach a rung that a mirror match never does.
'use strict';

const ADJACENT_SCAN = [
  [-1, -1], [0, -1], [1, -1],
  [-1, 0], [1, 0],
  [-1, 1], [0, 1], [1, 1]];

module.exports = function (BCAbstractRobot, SPECS) {
  class Bc19ScenarioTie extends BCAbstractRobot {
    firstFreeAdjacent() {
      const shadow = this.getVisibleRobotMap();
      for (const off of ADJACENT_SCAN) {
        const x = this.me.x + off[0];
        const y = this.me.y + off[1];
        if (x < 0 || y < 0 || y >= this.map.length ||
            x >= this.map[0].length) continue;
        if (!this.map[y][x]) continue;
        if (shadow[y][x] !== 0) continue;
        return { dx: off[0], dy: off[1] };
      }
      return null;
    }

    turn() {
      if (this.me.team !== SPECS.RED) return null;
      if (this.me.unit === SPECS.CASTLE) {
        if (this.me.turn !== 1) return null;
        const sq = this.firstFreeAdjacent();
        if (!sq) return null;
        return { action: 'build', dx: sq.dx, dy: sq.dy,
                 build_unit: SPECS.PILGRIM };
      }
      if (this.me.unit === SPECS.PILGRIM) {
        if (this.me.turn !== 2) return null;
        const sq = this.firstFreeAdjacent();
        if (!sq) return null;
        return { action: 'build', dx: sq.dx, dy: sq.dy,
                 build_unit: SPECS.CHURCH };
      }
      if (this.me.unit === SPECS.CHURCH) {
        if (this.me.turn !== 1) return null;
        // D6.1: the CHURCH's `ATTACK_RADIUS` is the SCALAR 0, so both range
        // comparisons are against `undefined` and both are false -- a
        // CHURCH may legally "attack" ANY on-board square for 0 fuel and 0
        // damage, consuming its turn. Measured on the real engine:
        // `record.action == 2`.
        // Five squares TOWARD THE BOARD'S CENTRE, so the target is on the
        // board for every church on every board in the pair set -- a fixed
        // (5, 5) falls off the edge in the bottom-right quarter and the
        // dx/dy gate then refuses the action before the quirk is reached.
        return { action: 'attack',
                 dx: this.me.x * 2 < this.map[0].length ? 5 : -5,
                 dy: this.me.y * 2 < this.map.length ? 5 : -5 };
      }
      return null;
    }
  }
  return new Bc19ScenarioTie();
};
