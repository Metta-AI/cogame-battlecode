#!/usr/bin/env node
// Generate the committed bc19 boards by running the PINNED 2019 engine's own
// map generator under the PINNED Node, and record the MT19937 state the
// runtime has to resume from.
//
// WHY THIS EXISTS AT BUILD TIME AND NOT AT RUN TIME (design note V3):
//
//   (a) `coldbrew/game.js:153` calls `regions.sort(x => -1*x.length)` — a
//       ONE-ARGUMENT, sign-constant comparator, so the result is
//       implementation-defined. Measured under the pinned V8 it is a plain
//       reversal in 42 of 42 multi-region cases and the region kept passable
//       is NOT the largest in 40 of them. Porting that faithfully would mean
//       porting one V8 sort.
//   (b) 13 of the first 400 seeds produce UNPLAYABLE boards (0 castles, 2-4
//       passable squares), because that same reversal keeps a tiny pocket and
//       the castle placement then exhausts its 1000-try counter
//       (`game.js:177-188`). A pool that can draw such a board is not a pool.
//
// So the boards are generated once, curated for playability, and COMMITTED,
// together with `mt_state` — the 624-word MT19937 state and `mti` IMMEDIATELY
// AFTER `makeMap()` RETURNED — which is exactly the generator state
// `createItem` draws the castles' ids from (D1.2). Get that wrong by one draw
// and every subsequent robot id differs.
//
// IF A FUTURE NODE BUMP MAKES THE REGENERATION BYTE-DIFF FAIL, THE COMMITTED
// MAPS ARE THE RULES AND THE OLD NODE IS THE PIN. Regenerating instead is a
// RULES CHANGE and bumps `GameVersion` (docs/PARITY.md #bc19).
//
// Usage:
//   node tools/gen_maps_bc19.mjs --engine <checkout> --out data/maps/bc19 \
//        [--pools tools/map_pools_bc19.json] [--check] [--seeds 1,2,3]
//
//   --check   regenerate into memory and byte-diff against the committed
//             files instead of writing (what `parity-oracle-bc19` runs).

import { createRequire } from 'module';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { resolve, join } from 'path';

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return dflt;
  const v = process.argv[i + 1];
  return (v === undefined || v.startsWith('--')) ? true : v;
}

const engineDir = resolve(String(arg('engine', 'engine')));
const outDir = resolve(String(arg('out', 'data/maps/bc19')));
const poolsPath = resolve(String(arg('pools', 'tools/map_pools_bc19.json')));
const check = arg('check', false) === true;

const require = createRequire(join(engineDir, 'coldbrew', 'noop.js'));
const Game = require(join(engineDir, 'coldbrew', 'game.js'));

// ---------------------------------------------------------------------------
//  Curation: the rules a board must pass to be committed at all.
// ---------------------------------------------------------------------------

function measure(seed) {
  // `dont_create_map = true` builds the generator from the seed and stops. We
  // then call `makeMap()` ourselves so we can snapshot the MT state at the
  // exact instant it returns, BEFORE the castles' `createItem` draws.
  const g = new Game(seed, 100, 20, false, false, true);
  const toCreate = g.makeMap();
  const mtState = { mt: Array.from(g.generator.mt), mti: g.generator.mti };

  const height = g.map.length;
  const width = g.map[0].length;

  let passable = 0;
  for (let y = 0; y < height; y++)
    for (let x = 0; x < width; x++) if (g.map[y][x]) passable++;

  // Passable region count over the FULL board.
  const visited = [];
  for (let y = 0; y < height; y++) visited.push(new Array(width).fill(false));
  let regions = 0;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (!g.map[y][x] || visited[y][x]) continue;
      regions++;
      const stack = [[x, y]];
      while (stack.length) {
        const [cx, cy] = stack.pop();
        if (visited[cy][cx]) continue;
        visited[cy][cx] = true;
        if (cy > 0 && g.map[cy - 1][cx] && !visited[cy - 1][cx]) stack.push([cx, cy - 1]);
        if (cx > 0 && g.map[cy][cx - 1] && !visited[cy][cx - 1]) stack.push([cx - 1, cy]);
        if (cy < height - 1 && g.map[cy + 1][cx] && !visited[cy + 1][cx]) stack.push([cx, cy + 1]);
        if (cx < width - 1 && g.map[cy][cx + 1] && !visited[cy][cx + 1]) stack.push([cx + 1, cy]);
      }
    }
  }

  let karb = 0, fuel = 0;
  for (let y = 0; y < height; y++)
    for (let x = 0; x < width; x++) {
      if (g.karbonite_map[y][x]) karb++;
      if (g.fuel_map[y][x]) fuel++;
    }

  const castlesRed = toCreate.filter(r => r.team === 0);
  const castlesBlue = toCreate.filter(r => r.team === 1);

  // `transpose` is not exposed, so it is recovered from the geometry: the
  // engine mirrors rows unless it transposed, in which case it mirrors
  // columns. Both tests are exact on a generated board.
  let mirrorRows = true, mirrorCols = true;
  for (let y = 0; y < height && (mirrorRows || mirrorCols); y++)
    for (let x = 0; x < width; x++) {
      if (g.map[y][x] !== g.map[height - 1 - y][x]) mirrorRows = false;
      if (g.map[y][x] !== g.map[y][width - 1 - x]) mirrorCols = false;
    }
  // `transpose === true` mirrors across the VERTICAL midline (x -> w-1-x);
  // the note calls that symmetry "horizontal".
  const symmetry = mirrorCols && !mirrorRows ? 'horizontal'
                 : mirrorRows && !mirrorCols ? 'vertical'
                 : mirrorCols ? 'horizontal' : 'vertical';

  return { g, toCreate, mtState, width, height, passable, regions, karb, fuel,
           castlesRed, castlesBlue, symmetry };
}

function reject(m) {
  if (m.width < 32 || m.width > 64) return 'dimension outside 32..64';
  if (m.height !== m.width) return 'not square';
  if (m.castlesRed.length < 1 || m.castlesBlue.length < 1)
    return 'fewer than 1 castle a side';
  if (m.castlesRed.length !== m.castlesBlue.length)
    return 'unequal castle counts';
  if (m.passable * 100 < m.width * m.height * 30)
    return 'fewer than 30 % passable squares';
  if (m.regions !== 1) return 'more than one passable region';
  return null;
}

function boolRows(grid) {
  // `[y][x]` order, as the engine stores it, and as one string of `0`/`1` a
  // byte-diff can read: 22 boards of 64x64 booleans as JSON arrays would be
  // 6 MB of commas.
  return grid.map(row => row.map(v => (v ? '1' : '0')).join(''));
}

function euclid(a, b) {
  return Math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2);
}

function build(seed) {
  const m = measure(seed);
  const why = reject(m);
  if (why) return { seed, refused: why };
  const name = 'seed-' + String(seed).padStart(4, '0');
  let sepMin = Infinity, sepMax = 0;
  for (const r of m.castlesRed)
    for (const b of m.castlesBlue) {
      const d = euclid([r.x, r.y], [b.x, b.y]);
      if (d < sepMin) sepMin = d;
      if (d > sepMax) sepMax = d;
    }
  const doc = {
    name,
    seed,
    width: m.width,
    height: m.height,
    symmetry: m.symmetry,
    passable_squares: m.passable,
    karbonite_depots: m.karb,
    fuel_depots: m.fuel,
    castles_per_side: m.castlesRed.length,
    castle_separation_min_milli: Math.round(sepMin * 1000),
    castle_separation_max_milli: Math.round(sepMax * 1000),
    // `[x, y, team]` rows, IN `to_create` ORDER — which is the opening queue
    // order and therefore the order the castles' ids are drawn in.
    castles: m.toCreate.map(r => [r.x, r.y, r.team]),
    map: boolRows(m.g.map),
    karbonite_map: boolRows(m.g.karbonite_map),
    fuel_map: boolRows(m.g.fuel_map),
    mt_state: { mti: m.mtState.mti, mt: m.mtState.mt }
  };
  return { seed, name, doc, m };
}

function serialize(doc) {
  return JSON.stringify(doc, null, 1) + '\n';
}

// ---------------------------------------------------------------------------
//  Main
// ---------------------------------------------------------------------------

let seeds;
const seedsArg = arg('seeds', null);
if (seedsArg && seedsArg !== true) {
  seeds = String(seedsArg).split(',').map(s => parseInt(s, 10));
} else {
  const pools = JSON.parse(readFileSync(poolsPath, 'utf8'));
  seeds = [];
  for (const pool of ['small', 'mixed', 'large'])
    for (const name of pools[pool]) seeds.push(parseInt(name.slice(5), 10));
}

if (!check && !existsSync(outDir)) mkdirSync(outDir, { recursive: true });

let failures = 0;
for (const seed of seeds) {
  const r = build(seed);
  if (r.refused) {
    console.error(`::error::seed ${seed} is not a playable board: ${r.refused}`);
    failures++;
    continue;
  }
  const text = serialize(r.doc);
  const path = join(outDir, r.name + '.json');
  if (check) {
    if (!existsSync(path)) {
      console.error(`::error::${path} is missing`);
      failures++;
    } else if (readFileSync(path, 'utf8') !== text) {
      console.error(`::error::${path} does not match a regeneration from the ` +
        `pinned engine under node ${process.version}`);
      failures++;
    } else {
      console.log(`ok ${r.name} ${r.doc.width}x${r.doc.height} ` +
        `pass=${r.doc.passable_squares} karb=${r.doc.karbonite_depots} ` +
        `fuel=${r.doc.fuel_depots} cast=${r.doc.castles_per_side} ` +
        `${r.doc.symmetry}`);
    }
  } else {
    writeFileSync(path, text);
    console.log(`wrote ${r.name} ${r.doc.width}x${r.doc.height} ` +
      `pass=${r.doc.passable_squares} karb=${r.doc.karbonite_depots} ` +
      `fuel=${r.doc.fuel_depots} cast=${r.doc.castles_per_side} ` +
      `${r.doc.symmetry} sep=${(r.doc.castle_separation_min_milli / 1000).toFixed(1)}`);
  }
}

// The thirteen degenerate seeds of the first 400, asserted BY SEED with the
// stated reason — which proves V3's curation rather than trusting it.
const Degenerate = [7, 20, 24, 83, 108, 127, 175, 211, 232, 267, 283, 348, 365];
if (arg('assert-degenerate', false) === true) {
  for (const seed of Degenerate) {
    const r = build(seed);
    if (!r.refused) {
      console.error(`::error::seed ${seed} was expected to be refused as ` +
        `unplayable and was not`);
      failures++;
    } else {
      console.log(`refused ${seed}: ${r.refused}`);
    }
  }
}

if (failures) {
  console.error(`::error::${failures} bc19 map failure(s)`);
  process.exit(1);
}
