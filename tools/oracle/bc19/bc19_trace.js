#!/usr/bin/env node
// The bc19 parity oracle's trace driver.
//
// It `require`s the PINNED `coldbrew/game.js` and `coldbrew/action_record.js`
// UNMODIFIED BEYOND THE TWO COMMITTED PATCHES, reimplements `runtime.js`'s
// twenty-line `gameLoop`/`emptyQueue`, and prints the same six line kinds
// `tools/parity_trace_bc19.nim` prints from the Nim port.
//
// WHY THE LOOP IS REIMPLEMENTED AND NOTHING ELSE IS (docs/PARITY.md #bc19):
// `runtime.js` drives the game through `setInterval`, which cannot be run
// synchronously to completion, and `cli/run.js` additionally requires the
// rollup compiler, `vm2` (deprecated, known sandbox-escape CVEs) and a
// network update check on every invocation (`cli/run.js:13-16`). Everything
// else -- `Game`, `ActionRecord` and the starter library every bot inherits
// -- is the pinned checkout's own.
//
// THE ONLY npm DEPENDENCY IS `mersenne-twister@1.1.0`. The engine's own
// `package.json` pulls 404; the driver needs `game.js`, `action_record.js`,
// `specs.json` and the twister and nothing else.
//
// Usage:
//   node tools/oracle/bc19/bc19_trace.js --engine <checkout> --bot <name> \
//        --map <name> [--maps-dir data/maps/bc19] [--rounds 1000] \
//        [--out trace.txt] [--assert-clock] [--expect-freeze]
//
// Exit codes:
//   0  the game ran and the trace was written
//   1  a usage or load error
//   3  NOTHING HAPPENED -- no robot ever took an action, or no unit was ever
//      built. That is what catches a silently broken bot load, which is the
//      exact "green oracle proving nothing" trap.
//   6  Tier B' (a): a live robot's `robot.time` fell below `CHESS_INITIAL`
//      after a turn, so the engine's own freeze branch could have fired in a
//      game this job COMPARES. V1's divergence is only sound while that
//      never happens.
//   7  `--expect-freeze` was asked for and the engine did NOT freeze the bot.

'use strict';

const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return dflt;
  const v = process.argv[i + 1];
  return (v === undefined || v.startsWith('--')) ? true : v;
}

const engineDir = path.resolve(String(arg('engine', 'engine')));
const botName = String(arg('bot', 'bc19idle'));
const mapName = String(arg('map', 'seed-0043'));
const mapsDir = path.resolve(String(arg('maps-dir', 'data/maps/bc19')));
const maxRounds = parseInt(String(arg('rounds', '1000')), 10);
const outPath = arg('out', null);
const assertClock = arg('assert-clock', false) === true;
const expectFreeze = arg('expect-freeze', false) === true;
// `--allow-inert` waives the exit-3 "nothing happened" guard for ONE
// measured, documented pair. It is never a default and every use of it is
// named in `docs/PARITY.md` #bc19 with the reason.
const allowInert = arg('allow-inert', false) === true;
// `--allow-no-build` waives ONLY the "no unit was ever built" half of the
// guard, for a bot whose whole script is the BARTER and which therefore
// never builds anything. It still has to have taken a non-NOTHING action.
const allowNoBuild = arg('allow-no-build', false) === true;

const engineRequire = createRequire(path.join(engineDir, 'coldbrew', 'x.js'));
const SPECS = engineRequire(path.join(engineDir, 'coldbrew', 'specs.json'));
// `--rounds` OVERRIDES `SPECS.MAX_ROUNDS` rather than stopping the trace
// early, because `isOver` reads that constant (`game.js:591`) and the Nim
// side's `maxRounds` governs the same rung. Truncating one side and
// re-laddering the other would compare two different games. `game.js`
// `require`s the same object instance, so the assignment reaches it.
if (maxRounds !== SPECS.MAX_ROUNDS) SPECS.MAX_ROUNDS = maxRounds;
const Game = engineRequire(path.join(engineDir, 'coldbrew', 'game.js'));

// ---------------------------------------------------------------------------
//  The starter library, taken from the pinned checkout rather than rewritten
// ---------------------------------------------------------------------------
//
// `coldbrew/starter/js_starter.js` exports the library as a STRING of ES
// module source -- that is how the real toolchain hands it to rollup. The
// driver evaluates that exact string with its two `export` keywords removed,
// so every bot below inherits THE UPSTREAM `BCAbstractRobot`, including all
// of its CLIENT-SIDE checks. Those checks matter: `this.move()` on an
// occupied square THROWS inside the library, `_do_turn` catches it into
// `_bc_error_action`, and the engine therefore sees an action with no
// `action` key at all -- a NOTHING, not a refused move.
const starterSource = engineRequire(
  path.join(engineDir, 'coldbrew', 'starter', 'js_starter.js'));
const starterFactory = new Function(
  starterSource.replace(/^export /gm, '') +
  '\nreturn { SPECS: SPECS, BCAbstractRobot: BCAbstractRobot };');
const starter = starterFactory();

// ---------------------------------------------------------------------------
//  Bots
// ---------------------------------------------------------------------------

function loadBotFactory(name) {
  if (name === 'examplefuncsplayer19') {
    // THE ONE BOT THAT IS UPSTREAM'S OWN. It is the pinned engine's
    // `coldbrew/bots/example_js/robot.js` with the two hunks of
    // `determinism.patch` applied to the CHECKOUT, so there is exactly one
    // copy of it and it is upstream's. The loader strips the `import` line
    // the real compiler would resolve and wraps the module body in a
    // factory, which is what gives each robot its own closure -- and
    // therefore its own `step` counter -- exactly as `vm2` did.
    const file = path.join(engineDir, 'coldbrew', 'bots', 'example_js',
      'robot.js');
    const src = fs.readFileSync(file, 'utf8')
      .replace(/^import[^\n]*\n/m, '')
      .replace(/^export /gm, '');
    const make = new Function('BCAbstractRobot', 'SPECS',
      src + '\nreturn robot;');
    return () => make(starter.BCAbstractRobot, starter.SPECS);
  }
  const file = path.join(__dirname, name, 'robot.js');
  if (!fs.existsSync(file)) {
    console.error(`::error::no oracle bot at ${file}`);
    process.exit(1);
  }
  const make = require(file);
  return () => make(starter.BCAbstractRobot, starter.SPECS);
}

const makeBot = loadBotFactory(botName);

// ---------------------------------------------------------------------------
//  The board: GENERATED, then asserted byte-identical to the committed file
// ---------------------------------------------------------------------------

const mapSeed = parseInt(mapName.slice(5), 10);
const game = new Game(mapSeed, SPECS.CHESS_INITIAL, SPECS.CHESS_EXTRA,
  false, false, true);
const toCreate = game.makeMap();
const mtState = { mti: game.generator.mti, mt: Array.from(game.generator.mt) };

const committedPath = path.join(mapsDir, mapName + '.json');
if (!fs.existsSync(committedPath)) {
  console.error(`::error::no committed board at ${committedPath}`);
  process.exit(1);
}
const committed = JSON.parse(fs.readFileSync(committedPath, 'utf8'));

function rows(grid) {
  return grid.map(row => row.map(v => (v ? '1' : '0')).join(''));
}
function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

let mapFailures = 0;
function want(label, got, expected) {
  if (!same(got, expected)) {
    console.error(`::error::${mapName}: ${label} differs between the ` +
      `generated board and the committed one`);
    mapFailures++;
  }
}
want('width', game.map[0].length, committed.width);
want('height', game.map.length, committed.height);
want('map', rows(game.map), committed.map);
want('karbonite_map', rows(game.karbonite_map), committed.karbonite_map);
want('fuel_map', rows(game.fuel_map), committed.fuel_map);
want('castles', toCreate.map(r => [r.x, r.y, r.team]), committed.castles);
// THE POST-`makeMap` MT19937 STATE. This is what proves the id stream is
// aligned (D1.2): get it wrong by one draw and every subsequent robot id
// differs, and ids are what `getItem` and the shadow are keyed by.
want('mt_state.mti', mtState.mti, committed.mt_state.mti);
want('mt_state.mt', mtState.mt, committed.mt_state.mt);
if (mapFailures) {
  console.error(`::error::${mapFailures} board mismatch(es) on ${mapName} ` +
    `under node ${process.version}. THE COMMITTED MAPS ARE THE RULES AND ` +
    `THE OLD NODE IS THE PIN (docs/PARITY.md #bc19).`);
  process.exit(1);
}

for (let i = 0; i < toCreate.length; i++) {
  game.createItem(toCreate[i].x, toCreate[i].y, toCreate[i].team,
    SPECS.CASTLE);
}

// ---------------------------------------------------------------------------
//  The trace
// ---------------------------------------------------------------------------

const TEAM = ['RED', 'BLUE'];
const UNIT = ['CASTLE', 'CHURCH', 'PILGRIM', 'CRUSADER', 'PROPHET',
              'PREACHER'];
const ACTION = ['NOTHING', 'MOVE', 'ATTACK', 'BUILD', 'MINE', 'TRADE',
                'GIVE', 'TIMEOUT'];

const FNV_OFFSET = 0xcbf29ce484222325n;
const FNV_PRIME = 0x100000001b3n;
const MASK64 = (1n << 64n) - 1n;

function fnv1a64(values) {
  let h = FNV_OFFSET;
  for (const v of values) {
    let u = BigInt(v >>> 0) & 0xffffffffn;
    for (let b = 0; b < 4; b++) {
      h = (h ^ (u & 0xffn)) & MASK64;
      h = (h * FNV_PRIME) & MASK64;
      u >>= 8n;
    }
  }
  return h;
}

function shadowChecksum() {
  const flat = [];
  for (let y = 0; y < game.shadow.length; y++)
    for (let x = 0; x < game.shadow[0].length; x++) flat.push(game.shadow[y][x]);
  return fnv1a64(flat);
}
function queueChecksum() {
  return fnv1a64(game.robots.map(r => r.id));
}
function mtChecksum() {
  return fnv1a64(Array.from(game.generator.mt));
}

const lines = [];
function emit(s) { lines.push(s); }

function emitRoundState(round) {
  emit(`R ${round} Q robin=${game.robin} live=${game.robots.length} ` +
    `ids=${game.ids.length}`);
  for (let t = 0; t < 2; t++) {
    let ca = 0, ch = 0, pi = 0, cr = 0, pr = 0, pe = 0, hp = 0;
    for (const r of game.robots) {
      if (r.team !== t) continue;
      hp += r.health;
      switch (r.unit) {
        case 0: ca++; break;
        case 1: ch++; break;
        case 2: pi++; break;
        case 3: cr++; break;
        case 4: pr++; break;
        case 5: pe++; break;
      }
    }
    emit(`R ${round} T ${TEAM[t]} karb=${game.karbonite[t]} ` +
      `fuel=${game.fuel[t]} ca=${ca} ch=${ch} pi=${pi} cr=${cr} pr=${pr} ` +
      `pe=${pe} hp=${hp} offer=${game.last_offer[t][0]}:${game.last_offer[t][1]}`);
  }
  // ROBOTS IN QUEUE ORDER, not id order -- which is what makes an ordering
  // bug visible on the round it happens.
  for (const r of game.robots) {
    emit(`R ${round} U ${r.id} team=${TEAM[r.team]} ty=${UNIT[r.unit]} ` +
      `x=${r.x} y=${r.y} hp=${r.health} k=${r.karbonite} f=${r.fuel} ` +
      `t=${r.turn} sig=${r.signal} sr=${r.signal_radius} ` +
      `ct=${r.castle_talk}`);
  }
  // THE `G` LINE IS THE MOST VALUABLE LINE IN THE TRACE. `mt` and `mti` are
  // bc19's own addition: a single missed or extra id draw (D1.2) surfaces on
  // the round it happens instead of as a mystery three hundred rounds later.
  emit(`R ${round} G shadowchk=${shadowChecksum()} ` +
    `queuechk=${queueChecksum()} mt=${mtChecksum()} mti=${game.generator.mti}`);
}

// ---------------------------------------------------------------------------
//  `runtime.js`'s loop -- and NOTHING else is reimplemented
// ---------------------------------------------------------------------------

function emptyQueue() {
  while (game.init_queue > 0) {
    const robot = game.initializeRobot();
    const bot = makeBot();
    game.registerHook(function (dump) {
      // The engine hands the hook a STRING, `robot._do_turn({...});`, which
      // `vm2` would evaluate in the bot's own context. The driver parses the
      // payload out of it and calls the bot's own `_do_turn`, which is the
      // same call the string makes.
      const open = dump.indexOf('(');
      const close = dump.lastIndexOf(')');
      return bot._do_turn(JSON.parse(dump.slice(open + 1, close)));
    }, robot.id);
  }
}

let actionsSeen = 0;
let nonNothing = 0;
let unitsBuilt = 0;
let peakAlive = 0;
let clockViolations = 0;
let froze = false;
let freezeTurn = -1;
let lastRoundEmitted = 0;
let turnsInRound = {};

// `enactTurn` is wrapped so the `A` line is emitted for the robot that acted
// and the round-state block is emitted once per round, after its last turn.
const realEnactTurn = game.enactTurn.bind(game);

function step() {
  const roundBefore = game.round;
  const robot = game.robots[game.robin >= game.robots.length ? 0 : game.robin];
  const idBefore = robot ? robot.id : 0;
  const idsBefore = game.ids.length;
  // The record the engine builds is not returned, so it is recovered from
  // the robot's own post-turn state plus the queue delta. `ActionRecord` is
  // patched in only to capture the record itself.
  capturedRecord = null;
  realEnactTurn();
  const rec = capturedRecord;
  const round = game.round;
  turnsInRound[round] = (turnsInRound[round] || 0) + 1;
  if (rec) {
    actionsSeen++;
    if (rec.action !== 0) nonNothing++;
    if (rec.action === 3) unitsBuilt++;
    emit(`R ${round} A ${idBefore} act=${ACTION[rec.action]} ` +
      `dx=${rec.dx === null ? 0 : rec.dx} dy=${rec.dy === null ? 0 : rec.dy} ` +
      `u=${rec.build_unit === null ? -1 : rec.build_unit} ` +
      `gk=${rec.give_karbonite === null ? 0 : rec.give_karbonite} ` +
      `gf=${rec.give_fuel === null ? 0 : rec.give_fuel} ` +
      `tk=${rec.trade_karbonite === null ? 0 : rec.trade_karbonite} ` +
      `tf=${rec.trade_fuel === null ? 0 : rec.trade_fuel}`);
  }
  if (game.robots.length > peakAlive) peakAlive = game.robots.length;
  // TIER B' (a): after every turn of every compared game, every live robot's
  // chess clock must still be at or above `CHESS_INITIAL`. If it is not, the
  // engine's freeze branch COULD have fired and V1's divergence is no longer
  // provably unexercised.
  for (const r of game.robots) {
    if (r.time < 0) {
      if (!froze) freezeTurn = r.turn;
      froze = true;
    }
    if (assertClock && r.initialized && r.time < SPECS.CHESS_INITIAL) {
      clockViolations++;
    }
  }
  return roundBefore;
}

// `ActionRecord.enact` is the last thing `enactTurn` calls on the record, so
// wrapping it is how the driver gets hold of the record the engine built --
// without touching `game.js` at all.
let capturedRecord = null;
const ActionRecord = engineRequire(
  path.join(engineDir, 'coldbrew', 'action_record.js'));
const realEnact = ActionRecord.prototype.enact;
ActionRecord.prototype.enact = function (g, r) {
  capturedRecord = this;
  return realEnact.call(this, g, r);
};

let winnerLine = 'R 0 W winner=- wc=-';
let rounds = 0;
while (true) {
  emptyQueue();
  if (game.isOver()) {
    winnerLine = `R ${game.round} W ` +
      `winner=${game.winner === undefined ? '-' : TEAM[game.winner]} ` +
      `wc=${game.win_condition === undefined ? '-' : game.win_condition}`;
    break;
  }
  const roundBefore = step();
  if (game.robin >= game.robots.length) {
    emitRoundState(game.round);
    lastRoundEmitted = game.round;
    rounds = game.round;
  }
  if (game.robots.length === 0) break;
}
if (lastRoundEmitted !== game.round) {
  emitRoundState(game.round);
  rounds = game.round;
}
emit(winnerLine);

const text = lines.join('\n') + '\n';
if (outPath && outPath !== true) fs.writeFileSync(String(outPath), text);
else process.stdout.write(text);

const summary = {
  bot: botName, map: mapName, rounds, lines: lines.length,
  actions: actionsSeen, non_nothing: nonNothing, builds: unitsBuilt,
  peak_alive: peakAlive, ids_spent: game.ids.length,
  winner: game.winner === undefined ? null : TEAM[game.winner],
  win_condition: game.win_condition === undefined ? null : game.win_condition,
  round_1000_turns: turnsInRound[maxRounds] || 0,
  froze, freeze_turn: freezeTurn
};
console.error('bc19_trace ' + JSON.stringify(summary));

// THE DRIVER MUST FAIL LOUDLY WHEN NOTHING HAPPENS. A green oracle that
// proved nothing is the exact trap this exit code exists for.
if (!allowInert && botName !== 'bc19idle' &&
    (nonNothing === 0 || (unitsBuilt === 0 && !allowNoBuild))) {
  console.error(`::error::${botName} on ${mapName}: no robot ever took an ` +
    `action (${nonNothing}) or no unit was ever built (${unitsBuilt}). The ` +
    `bot did not load, or it loaded and did nothing -- either way this ` +
    `trace proves nothing.`);
  process.exit(3);
}
if (assertClock && clockViolations > 0) {
  console.error(`::error::TIER B' (a): ${clockViolations} turn(s) left a ` +
    `live robot below CHESS_INITIAL on ${botName}/${mapName}. The engine's ` +
    `own freeze branch could have fired in a game this job COMPARES, so ` +
    `V1's divergence is not provably unexercised here.`);
  process.exit(6);
}
if (expectFreeze) {
  if (!froze) {
    console.error(`::error::TIER B' (b): the engine did NOT freeze ` +
      `${botName}. That run exists to prove the port's READING of the ` +
      `freeze rule, so a run in which nothing froze proves nothing.`);
    process.exit(7);
  }
  // THE FORMULA, CHECKED. `robot.time` starts at CHESS_INITIAL and moves by
  // `+ CHESS_EXTRA - elapsed` every turn, so a turn that burns `b` ms
  // crosses zero at turn `CHESS_INITIAL / (b - CHESS_EXTRA)` -- turn 5 for
  // the calibrated 40 ms burn. A generous +-3 turns absorbs runner jitter;
  // anything outside it means the rule is not what the port thinks it is.
  const predicted = Math.ceil(SPECS.CHESS_INITIAL / (40 - SPECS.CHESS_EXTRA));
  if (Math.abs(freezeTurn - predicted) > 3) {
    console.error(`::error::TIER B' (b): ${botName} froze on turn ` +
      `${freezeTurn}, but time_{n+1} = time_n + ${SPECS.CHESS_EXTRA} - ` +
      `elapsed predicts turn ${predicted} for a 40 ms burn. The port's ` +
      `reading of the freeze rule does not match the engine's behaviour.`);
    process.exit(7);
  }
  console.error(`bc19_trace TIER B' (b): the engine froze ${botName} on ` +
    `turn ${freezeTurn}, against a predicted ${predicted}. V1's freeze ` +
    `branch is real, and the port's DecisionOps clock provably never ` +
    `reaches it (TurnChargeOps == ChessExtraOps).`);
}
