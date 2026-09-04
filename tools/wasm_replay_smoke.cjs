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
const vm = require('vm');

const bundle = path.resolve(process.argv[2] || '');
const replayPath = path.resolve(process.argv[3] || '');
if (!process.argv[2] || !process.argv[3]) {
  console.error('usage: node tools/wasm_replay_smoke.cjs <bundle> <replay.json>');
  process.exit(2);
}

// The emitted glue's data-package loader resolves `bc_replay.data` against
// the PROCESS working directory under node, not through Module.locateFile,
// so the smoke runs from inside the bundle. Both paths above are absolute
// for exactly that reason.
process.chdir(bundle);

// The emitted glue is a plain script that populates a GLOBAL `Module` and
// calls Module.onRuntimeInitialized — the SAME bootstrap the worker uses. It
// is not a MODULARIZE factory, and this file must not pretend otherwise.
global.Module = {
  locateFile: (file) => path.join(bundle, file)
};
global.Module.print = (text) => console.log('  [wasm] ' + text);
global.Module.printErr = (text) => console.error('  [wasm] ' + text);

global.Module.onRuntimeInitialized = () => {
  const Module = global.Module;
  console.log('runtime initialized; loading ' + path.basename(replayPath));
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

// LOAD IT IN GLOBAL SCOPE, NOT WITH require().
//
// The glue opens with `var Module = typeof Module != "undefined" ? Module : {}`.
// Inside a CommonJS module that `var` is hoisted into the module scope and
// shadows `global.Module`, so `typeof Module` is "undefined" at that line and
// the glue silently builds its OWN empty Module: `locateFile` is not ours,
// `onRuntimeInitialized` above is never called, node runs out of work and
// exits 0 having tested NOTHING. That is what this file did from the day it
// was written — 0.1 s, no output, green.
//
// Run the same bytes with `vm.runInThisContext` and the declaration sees the
// global object, which already has `Module`, so the glue adopts it. The three
// bindings below are the ones a CommonJS wrapper would have supplied and the
// glue uses under ENVIRONMENT_IS_NODE.
global.__dirname = bundle;
global.__filename = path.join(bundle, 'bc_replay.js');
global.require = require;
vm.runInThisContext(fs.readFileSync(global.__filename, 'utf8'),
  { filename: global.__filename });

// And if it still never boots, say so instead of exiting 0.
setTimeout(() => {
  console.error('the wasm runtime never initialized: ' +
    'Module.onRuntimeInitialized was not called within 60 s');
  process.exit(1);
}, 60000);
