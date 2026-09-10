// TIER A'. `castles_destroyed`, and the proof that the game STOPS BEFORE THE
// NEXT ROBOT ACTS.
//
// Written line for line against `scenarioKill` in
// `src/battlecode/years/bc19/chassis/scenario19.nim`. Castles build a
// crusader into the first free adjacent square every turn; crusaders walk at
// THE MIRROR OF THEIR OWN SPAWN and attack it once it is inside r2 16.
//
// The mirror axis is recovered EXACTLY rather than guessed: the engine
// mirrors the FULL map, so `map[y][x] === map[y][W-1-x]` for every square
// means the mirror is the VERTICAL midline (which this repository calls
// "horizontal" symmetry). Both implementations run the same loop in the same
// order and cache the answer on the robot.
'use strict';

const ADJACENT_SCAN = [
  [-1, -1], [0, -1], [1, -1],
  [-1, 0], [1, 0],
  [-1, 1], [0, 1], [1, 1]];

module.exports = function (BCAbstractRobot, SPECS) {
  class Bc19ScenarioKill extends BCAbstractRobot {
    onBoard(x, y) {
      return x >= 0 && y >= 0 && y < this.map.length && x < this.map[0].length;
    }

    mirrorAxisHorizontal() {
      const h = this.map.length;
      const w = this.map[0].length;
      for (let y = 0; y < h; y++)
        for (let x = 0; x < w; x++)
          if (this.map[y][x] !== this.map[y][w - 1 - x]) return false;
      return true;
    }

    firstFreeAdjacent() {
      const shadow = this.getVisibleRobotMap();
      for (const off of ADJACENT_SCAN) {
        const x = this.me.x + off[0];
        const y = this.me.y + off[1];
        if (!this.onBoard(x, y)) continue;
        if (!this.map[y][x]) continue;
        if (shadow[y][x] !== 0) continue;
        return { dx: off[0], dy: off[1] };
      }
      return null;
    }

    towardTarget(tx, ty) {
      // The cheapest legal step that STRICTLY reduces the squared distance,
      // scanning dy then dx over the unit's whole offset range in a fixed
      // order. No RNG, no tie-break beyond first-wins.
      const speed = SPECS.UNITS[this.me.unit].SPEED;
      if (speed <= 0) return null;
      const shadow = this.getVisibleRobotMap();
      let best = Math.pow(this.me.x - tx, 2) + Math.pow(this.me.y - ty, 2);
      let out = null;
      for (let dy = -3; dy <= 3; dy++) {
        for (let dx = -3; dx <= 3; dx++) {
          const r2 = dx * dx + dy * dy;
          if (r2 === 0 || r2 > speed) continue;
          const nx = this.me.x + dx;
          const ny = this.me.y + dy;
          if (!this.onBoard(nx, ny)) continue;
          if (!this.map[ny][nx]) continue;
          if (shadow[ny][nx] !== 0) continue;
          if (this.fuel < r2 * SPECS.UNITS[this.me.unit].FUEL_PER_MOVE)
            continue;
          const d = Math.pow(nx - tx, 2) + Math.pow(ny - ty, 2);
          if (d < best) {
            best = d;
            out = { dx: dx, dy: dy };
          }
        }
      }
      return out;
    }

    turn() {
      if (this.me.unit === SPECS.CASTLE) {
        const sq = this.firstFreeAdjacent();
        if (!sq) return null;
        return { action: 'build', dx: sq.dx, dy: sq.dy,
                 build_unit: SPECS.CRUSADER };
      }
      if (this.me.unit !== SPECS.CRUSADER) return null;
      if (this.targetX === undefined) {
        this.homeX = this.homeX === undefined ? this.me.x : this.homeX;
        this.homeY = this.homeY === undefined ? this.me.y : this.homeY;
        if (this.mirrorAxisHorizontal()) {
          this.targetX = this.map[0].length - 1 - this.homeX;
          this.targetY = this.homeY;
        } else {
          this.targetX = this.homeX;
          this.targetY = this.map.length - 1 - this.homeY;
        }
      }
      // THE LOWEST-ID VISIBLE ENEMY INSIDE THE CRUSADER'S OWN r2 1..16.
      // `visible` is ordered by ASCENDING id on BOTH SIDES -- the port in
      // `years/bc19/vision.nim` and the engine under
      // `tools/oracle/bc19/visible_order.patch` (V2) -- so "the lowest-id
      // one" is the same robot in both, and this is the one scripted
      // decision in the whole tier that DEPENDS ON THAT PATCH WORKING.
      const seen = this.getVisibleRobots();
      for (let i = 0; i < seen.length; i++) {
        const other = seen[i];
        if (!this.isVisible(other)) continue;
        if (other.team === this.me.team) continue;
        const dd = Math.pow(other.x - this.me.x, 2) +
          Math.pow(other.y - this.me.y, 2);
        if (dd < 1 || dd > 16) continue;
        return { action: 'attack', dx: other.x - this.me.x,
                 dy: other.y - this.me.y };
      }
      const step = this.towardTarget(this.targetX, this.targetY);
      if (!step) return null;
      return { action: 'move', dx: step.dx, dy: step.dy };
    }
  }
  return new Bc19ScenarioKill();
};
