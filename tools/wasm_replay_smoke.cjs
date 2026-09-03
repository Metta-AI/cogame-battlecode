// Load the EMITTED wasm module under node and drive it directly.
//
// The browser harness (tools/ci/viewer_smoke.mjs) proves the whole page
// renders; this proves the module itself answers, which is where wasm32-only
// failures live — 32-bit int overflow traps and address-space exhaustion are
// both invisible to the native Nim tests, which run 64-bit.
//
//   node tools/wasm_replay_smoke.cjs <bundle dir> <replay.json>

'use strict';

const fs = require('fs');
const path = require('path');

const bundle = process.argv[2];
const replayPath = process.argv[3];
if (!bundle || !replayPath) {
  console.error('usage: node tools/wasm_replay_smoke.cjs <bundle> <replay.json>');
  process.exit(2);
}

// The emitted glue is a plain script that populates a GLOBAL `Module` and
// calls Module.onRuntimeInitialized — the SAME bootstrap the worker uses. It
// is not a MODULARIZE factory, and this file must not pretend otherwise.
global.Module = {
  locateFile: (file) => path.join(bundle, file)
};

global.Module.onRuntimeInitialized = () => {
  const Module = global.Module;
  const bytes = fs.readFileSync(replayPath);
  const pointer = Module._malloc(bytes.length);
  Module.HEAPU8.set(bytes, pointer);
  const loaded = Module._bc_load_replay(pointer, bytes.length);
  Module._free(pointer);

  const readString = (ptrFn, lenFn) => {
    const length = ptrFn && lenFn ? lenFn() : 0;
    if (!length) return '';
    return Buffer.from(
      Module.HEAPU8.subarray(ptrFn(), ptrFn() + length)).toString('utf8');
  };

  if (!loaded) {
    console.error('bc_load_replay failed: ' +
      readString(Module._bc_error_ptr, Module._bc_error_len) +
      ' (stage: ' + readString(Module._bc_stage_ptr, Module._bc_stage_len) + ')');
    process.exit(1);
  }

  const version = readString(
    Module._bc_game_version_ptr, Module._bc_game_version_len);
  const stamp = readString(
    Module._bc_sim_sources_stamp_ptr, Module._bc_sim_sources_stamp_len);
  if (!version) {
    console.error('the module reports no GameVersion');
    process.exit(1);
  }

  const first = Module._bc_packet_len();
  if (first <= 0) {
    console.error('the first frame produced an empty sprite packet');
    process.exit(1);
  }

  // Step it. 200 frames is well past the point where a stale-globals bug
  // (the ctf emscripten_exit_with_live_runtime scar) would show up.
  let frames = 0;
  for (let i = 0; i < 200; i++) {
    const step = Module._bc_frame();
    if (step < 0) {
      console.error('bc_frame failed: ' +
        readString(Module._bc_error_ptr, Module._bc_error_len));
      process.exit(1);
    }
    if (step !== 1) break;
    if (Module._bc_packet_len() <= 0) {
      console.error('frame ' + i + ' produced an empty sprite packet');
      process.exit(1);
    }
    frames++;
  }
  if (frames < 50) {
    console.error('the module only advanced ' + frames + ' frames');
    process.exit(1);
  }

  const mismatch = Module._bc_mismatch_round();
  if (mismatch >= 0) {
    console.error('the re-derivation diverged from the recording at round ' +
      mismatch);
    process.exit(1);
  }

  console.log(JSON.stringify({
    loaded: true,
    game_version: version,
    sim_sources_stamp: stamp,
    first_packet_bytes: first,
    frames: frames,
    mismatch_round: mismatch
  }));
  process.exit(0);
};

require(path.resolve(bundle, 'bc_replay.js'));
