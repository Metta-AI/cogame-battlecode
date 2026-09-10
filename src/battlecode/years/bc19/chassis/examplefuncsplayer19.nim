## `examplefuncsplayer19` — the deliberately weak floor and the parity
## oracle's other side.
##
## A port of `coldbrew/bots/example_js/robot.js` at
## `battlecode/battlecode19@80cf1cc535ec5a30559274aa1b49807ad4859925`
## (GPL-3.0, inside the engine repository, which is why the weak floor is
## LICENSED rather than invented), with the two committed hunks of
## `tools/oracle/bc19/examplefuncsplayer19/determinism.patch` applied.
##
## **IT MAY NOT GAIN BEHAVIOUR: IT IS ONE SIDE OF THE DIFFERENTIAL ORACLE.**
## `tests/test_bc19_examplefuncsplayer19.nim` asserts its RNG call sequence
## and its branch order against a recorded oracle trace, and Tier A" runs it
## against itself, bit-exact, on all nine parity pairs.
##
## Its whole behaviour, after the patch:
##
##   1. a per-robot `step` counter starting at -1, incremented at the top of
##      every turn;
##   2. a CASTLE: on every turn where `step % 10 == 0`, `buildUnit(CRUSADER,
##      1, 1)`; otherwise nothing;
##   3. a CRUSADER: `move(choice)` where `choice` is drawn from
##      `[[0,-1],[1,-1],[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1]]` — the
##      engine's own N, NE, E, SE, S, SW, W, NW order — by the patched RNG;
##   4. EVERY OTHER UNIT DOES NOTHING AT ALL — it never builds a pilgrim,
##      never mines, never builds a church, never signals, never trades and
##      never defends.
##
## THE TWO PATCH HUNKS, and why each exists:
##
##   1. `Math.floor(Math.random()*choices.length)` becomes
##      `Math.floor(rng()*choices.length)`, where `rng` is a
##      `java.util.Random` SEEDED FROM THE ROBOT'S OWN ID and created once
##      per robot. The stock line draws from the wall-clock-seeded global
##      RNG, so the stock bot is not reproducible even against itself and no
##      bit-exact parity is possible with it. A `java.util.Random` is chosen
##      rather than a second MT so the port can reuse
##      `src/battlecode/rng.nim` UNCHANGED — and Tier A" is then also a test
##      of that module against a SECOND, INDEPENDENT stream running
##      alongside the engine's own MT19937.
##   2. `if (this.me.team == 1) return this.buildUnit(...)` becomes
##      `return this.buildUnit(...)`. The stock bot's castle build is gated
##      on `team == 1`, so RED NEVER BUILDS ANYTHING AT ALL. A baseline that
##      is completely inert on one of the two sides cannot be scored, cannot
##      fill a league and makes the survival gate meaningless.
##
## Both are recorded in `docs/RULES-BC19.md` §Divergences and in
## `docs/PARITY.md` §bc19.

import ../../../rng
import ../constants, ../units, ../world
import ../actions

const Choices*: array[8, tuple[dx, dy: int]] = [
  (dx: 0, dy: -1), (dx: 1, dy: -1), (dx: 1, dy: 0), (dx: 1, dy: 1),
  (dx: 0, dy: 1), (dx: -1, dy: 1), (dx: -1, dy: 0), (dx: -1, dy: -1)]
  ## The engine's own N, NE, E, SE, S, SW, W, NW list, verbatim.

proc weakRandom(r: Robot): float64 =
  ## Patch hunk 1: one `java.util.Random(id)` per robot, created lazily on
  ## its first draw exactly as the patched JavaScript creates it on the
  ## bot's first turn, and `nextDouble()` standing in for `Math.random()`.
  var g: JavaRandom
  if not r.weakRngReady:
    g = initJavaRandom(r.id)
    r.weakRngReady = true
  else:
    g.seed = cast[int64](r.weakRng)
  result = g.nextDouble()
  r.weakRng = cast[uint64](g.seed)

proc runExamplefuncsplayer19*(w: World, r: Robot): Action =
  result = newAction()
  inc r.step
  case r.unit
  of ukCrusader:
    let choice = Choices[int(weakRandom(r) * float64(Choices.len))]
    result.hasAction = true
    result.kind = akMove
    result.dx = choice.dx
    result.dy = choice.dy
  of ukCastle:
    ## Patch hunk 2: no `team == 1` guard, so BOTH sides build.
    if r.step mod 10 == 0:
      result.hasAction = true
      result.kind = akBuild
      result.dx = 1
      result.dy = 1
      result.buildUnit = ukCrusader
  else:
    ## A PILGRIM, a PROPHET, a PREACHER and a CHURCH do nothing at all. That
    ## is what being the weak floor means, and it is why the substance
    ## assertions that need mining, depositing, church expansion, trading or
    ## a preacher blast are asserted ACROSS THE PAIR and never per seat.
    discard
