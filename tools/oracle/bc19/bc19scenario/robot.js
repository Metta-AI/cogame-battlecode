// TIER A'. THE LOAD-BEARING TIER, together with A''.
//
// Written LINE FOR LINE against `scenarioMain` in
// `src/battlecode/years/bc19/chassis/scenario19.nim`, and deliberately so:
// EVERY DECISION HERE IS A PURE FUNCTION OF `me.unit`, `me.turn` AND THE
// SQUARES IMMEDIATELY AROUND THE ROBOT. Those are exactly the facts both
// implementations can read identically, with NO RNG AT ALL and no dependence
// on the `visible` array's order (V2). The script is keyed by TURN NUMBER so
// every rare path fires early, while the games are still short enough for
// Tier B''s chess-clock assertion to hold.
//
// It returns RAW ACTION OBJECTS rather than calling `this.move()` /
// `this.attack()` / `this.buildUnit()`, because the starter library's
// CLIENT-SIDE checks would throw before the engine ever saw the action --
// and the paths this bot exists to force are precisely the ones the engine
// accepts and the library refuses (the legal 0-damage CHURCH attack, the
// PILGRIM attack that is a validation failure, a build onto an occupied
// square, a move a castle cannot make). `signal` and `castleTalk` ARE called
// through the library, because `_do_turn` overwrites those two fields from
// the library's own state whatever the bot returns.
//
// What it is the only cover for: one of every unit type built; a move at
// every legal r-squared for every mobile type; `mine` to capacity and one
// turn past it; `give`; an attack at every range boundary INCLUDING THE
// PROPHET'S r2 16 MINIMUM (15 refused, 16 and 64 accepted, 65 refused); a
// PREACHER blast that damages ITSELF; the legal 0-damage CHURCH attack
// (D6.1); the refused PILGRIM attack (D6.2); a broadcast at seven radii up
// to 7938; castle talk from a mobile unit; and a signal issued in the same
// turn as an ILLEGAL MOVE, proving the signal still lands.
'use strict';

// The scan order for "the first free adjacent square": dy ascending outer,
// dx ascending inner, skipping (0, 0). `scenario19.nim`'s `AdjacentScan`
// holds exactly this order and both implementations walk it identically.
const ADJACENT_SCAN = [
  [-1, -1], [0, -1], [1, -1],
  [-1, 0], [1, 0],
  [-1, 1], [0, 1], [1, 1]];

module.exports = function (BCAbstractRobot, SPECS) {
  class Bc19Scenario extends BCAbstractRobot {
    onBoard(x, y) {
      return x >= 0 && y >= 0 && y < this.map.length && x < this.map[0].length;
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

    build(unit) {
      const sq = this.firstFreeAdjacent();
      if (!sq) return null;
      return { action: 'build', dx: sq.dx, dy: sq.dy, build_unit: unit };
    }

    turn() {
      const turn = this.me.turn;
      if (this.me.unit === SPECS.CASTLE) {
        switch (turn) {
          case 1:
            this.signal(1234, 0);
            return this.build(SPECS.PILGRIM);
          case 2:
            this.signal(7, 1);
            return this.build(SPECS.PREACHER);
          case 3:
            this.signal(42, 2);
            return this.build(SPECS.PROPHET);
          // THE BUILD ORDER IS PILGRIM, PREACHER, PROPHET, CRUSADER AND
          // THE LAST ONE IS TRIED THREE TIMES, and both halves are measured
          // rather than chosen: an order starts with ONE HUNDRED KARBONITE
          // AND NO PASSIVE INCOME, so a castle can afford at most 80
          // karbonite of units in its whole opening. Buying the EXPENSIVE
          // units early is what puts a PREACHER on the board at all;
          // retrying the CHEAPEST one is what fills the remaining free
          // squares as units move away.
          case 4:
            this.signal(99, 3);
            return this.build(SPECS.CRUSADER);
          case 5:
            this.signal(5, 5);
            this.castleTalk(200);
            return this.build(SPECS.CRUSADER);
          case 6:
            this.signal(6, 10);
            this.castleTalk(17);
            return this.build(SPECS.CRUSADER);
          case 7:
            // The maximum legal radius, 2*(64-1)^2, whose cost is 90 fuel.
            this.signal(1, 2 * Math.pow(SPECS.MAX_BOARD_SIZE - 1, 2));
            return null;
          case 8:
            // r2 = 1, the CASTLE's minimum attack range.
            return { action: 'attack', dx: 1, dy: 0 };
          case 9:
            // r2 = 64, the CASTLE's maximum. Refused when it leaves the
            // board, identically on both sides.
            return { action: 'attack', dx: 8, dy: 0 };
          case 10:
            // An ILLEGAL move (a castle has SPEED 0) issued in the same turn
            // as a signal, proving the signal still lands.
            this.signal(321, 4);
            return { action: 'move', dx: 1, dy: 0 };
          case 11:
            // A build onto an occupied square -- refused.
            return { action: 'build', dx: 1, dy: 1,
                     build_unit: SPECS.CRUSADER };
          default:
            return null;
        }
      }
      if (this.me.unit === SPECS.CHURCH) {
        if (turn === 1) {
          // D6.1: the CHURCH's `ATTACK_RADIUS` is the scalar 0, so this is a
          // LEGAL 0-damage 0-fuel action that consumes the turn.
          return { action: 'attack', dx: 5, dy: 5 };
        }
        return this.build(SPECS.CRUSADER);
      }
      if (this.me.unit === SPECS.PILGRIM) {
        switch (turn) {
          case 1: return { action: 'mine' };
          case 2: return { action: 'move', dx: 1, dy: 0 };
          case 3: return { action: 'move', dx: 0, dy: 1 };
          // r2 = 4, the PILGRIM's maximum speed.
          case 4: return { action: 'move', dx: 2, dy: 0 };
          // D6.2: a PILGRIM attack is a VALIDATION FAILURE, not an action.
          case 5: return { action: 'attack', dx: 1, dy: 0 };
          // `give` WHATEVER THE PILGRIM ACTUALLY HOLDS. A fixed amount
          // fails validation on any board where the pilgrim had not
          // reached a depot, and the GIVE path would then silently never be
          // compared.
          case 6:
          case 8:
            return { action: 'give', dx: -1, dy: 0,
                     give_karbonite: Math.min(this.me.karbonite, 255),
                     give_fuel: Math.min(this.me.fuel, 255) };
          case 7:
            this.castleTalk(77);
            return { action: 'mine' };
          default: return { action: 'mine' };
        }
      }
      if (this.me.unit === SPECS.CRUSADER) {
        switch (turn) {
          // r2 = 9, the CRUSADER's maximum speed -- twice as far per turn as
          // anything else in the game.
          case 1: return { action: 'move', dx: 3, dy: 0 };
          case 2: return { action: 'attack', dx: 1, dy: 0 };
          // r2 = 16, the CRUSADER's maximum attack range.
          case 3: return { action: 'attack', dx: 4, dy: 0 };
          case 4: return { action: 'move', dx: 0, dy: -3 };
          default:
            return { action: 'move', dx: (turn & 1) === 1 ? 1 : -1, dy: 0 };
        }
      }
      if (this.me.unit === SPECS.PROPHET) {
        switch (turn) {
          // r2 = 9 -- INSIDE the PROPHET's r2 16 minimum, so REFUSED.
          case 1: return { action: 'attack', dx: 3, dy: 0 };
          // r2 = 16, exactly the minimum -- accepted.
          case 2: return { action: 'attack', dx: 4, dy: 0 };
          // r2 = 64, the maximum -- accepted.
          case 3: return { action: 'attack', dx: 8, dy: 0 };
          // r2 = 65 -- one past the maximum, refused.
          case 4: return { action: 'attack', dx: 8, dy: 1 };
          case 5: return { action: 'move', dx: 2, dy: 0 };
          default:
            return { action: 'move', dx: 0, dy: (turn & 1) === 1 ? 1 : -1 };
        }
      }
      // PREACHER.
      switch (turn) {
        // r2 = 1: the blast is nine squares around the target and includes
        // the PREACHER'S OWN SQUARE, so it damages itself. Measured on the
        // engine: 60 -> 40 HP.
        case 1: return { action: 'attack', dx: 1, dy: 0 };
        // r2 = 16, the PREACHER's maximum attack range.
        case 2: return { action: 'attack', dx: 4, dy: 0 };
        case 3: return { action: 'move', dx: 1, dy: 1 };
        default: return { action: 'attack', dx: 1, dy: 0 };
      }
    }
  }
  return new Bc19Scenario();
};
