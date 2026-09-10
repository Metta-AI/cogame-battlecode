// TIER A''. The bot itself is NOT here.
//
// `examplefuncsplayer19` is the PINNED ENGINE'S OWN
// `coldbrew/bots/example_js/robot.js` with the two hunks of
// `determinism.patch` applied TO THE CHECKOUT, so there is exactly one copy
// of it in this repository's CI and that copy is upstream's. No upstream
// JavaScript is vendored here.
//
// `bc19_trace.js` resolves the name `examplefuncsplayer19` straight to the
// patched checkout (see its `loadBotFactory`), which is why this file is a
// note rather than a bot. It exists because `docs/RULES-BC19.md` and
// `NOTICE` both name this path, and a licence file that credits derived
// behaviour to a path that does not exist is a defect.
//
// Its Nim twin is
// `src/battlecode/years/bc19/chassis/examplefuncsplayer19.nim`, ported
// statement for statement WITH THE PATCH APPLIED, and it MAY NOT GAIN
// BEHAVIOUR: it is one side of the differential oracle.
'use strict';

module.exports = function () {
  throw new Error(
    'examplefuncsplayer19 is the pinned engine\'s own patched bot; ' +
    'bc19_trace.js loads it from the checkout and never from here');
};
