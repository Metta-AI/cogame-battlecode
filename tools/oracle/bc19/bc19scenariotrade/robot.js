// TIER A'. THE BARTER, and it is the only cover for all four of its paths.
//
// Written line for line against `scenarioTrade` in
// `src/battlecode/years/bc19/chassis/scenario19.nim`.
//
// The castles act in `to_create` order -- RED, BLUE, RED, BLUE -- so on each
// scripted turn RED sets the standing offer and BLUE matches it:
//
//   turn 1  the initial `last_offer` is [[0,0],[0,0]], so THE FIRST CASTLE
//           TO OFFER (0,0) ALREADY MATCHES and executes a zero trade;
//   turn 2  a matched, PAYABLE offer -- both stores move in opposite
//           directions;
//   turn 3  a matched, UNPAYABLE offer -- BOTH OFFERS CLEAR AND THEN IT
//           THROWS, so the offers are gone and nothing moved;
//   turn 4  a second matched payable offer, proving the ledger recovered.
//
// The sign convention is the ENGINE's: POSITIVE MEANS THE RESOURCE MOVES
// RED TO BLUE.
'use strict';

module.exports = function (BCAbstractRobot, SPECS) {
  class Bc19ScenarioTrade extends BCAbstractRobot {
    turn() {
      if (this.me.unit !== SPECS.CASTLE) return null;
      switch (this.me.turn) {
        case 1:
          return { action: 'trade', trade_karbonite: 0, trade_fuel: 0 };
        case 2:
          return { action: 'trade', trade_karbonite: 10, trade_fuel: -50 };
        case 3:
          return { action: 'trade', trade_karbonite: 1000, trade_fuel: 1000 };
        case 4:
          return { action: 'trade', trade_karbonite: 5, trade_fuel: 5 };
        default:
          return null;
      }
    }
  }
  return new Bc19ScenarioTrade();
};
