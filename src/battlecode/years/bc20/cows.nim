## The NPC cows: `world/control/CowControlProvider.java`, ported exactly.
##
## A cow's RNG is `new Random(84307 * mapSeed + 20201 * (cowId / 2))`, created
## LAZILY on the cow's first turn. Each turn:
##
##  * if the cow is ready, draw up to FOUR directions as
##    `DIRECTIONS[floor(nextDouble() * 8)]`, reversing the direction when the
##    cow's id is odd, and move on the first draw that is legal AND whose
##    destination is not flooded — STOPPING THE DRAW LOOP the moment it moves;
##  * if the cow is not ready, burn exactly four `nextDouble()` calls and do
##    nothing.
##
## The reversal uses the map symmetry, which the engine recomputes on every
## NEUTRAL spawn. Cows only exist at map load, so the value is fixed for the
## match — but it is still read from the world, not from the map file, because
## that is where the engine reads it.

import ../../rng
import world

const CowDirections* = MoveDirs
  ## `CowControlProvider.DIRECTIONS`: N, NE, E, SE, S, SW, W, NW.

proc reverseDirection*(w: World, d: Dir): Dir =
  case w.symmetry
  of symHorizontal:
    case d
    of dNortheast: dSoutheast
    of dSoutheast: dNortheast
    of dNorth: dSouth
    of dSouth: dNorth
    of dNorthwest: dSouthwest
    of dSouthwest: dNorthwest
    else: d
  of symVertical:
    case d
    of dNortheast: dNorthwest
    of dSoutheast: dSouthwest
    of dNorthwest: dNortheast
    of dSouthwest: dSoutheast
    of dWest: dEast
    of dEast: dWest
    else: d
  of symRotational:
    d.opposite()

proc cowSeed*(mapSeed, cowId: int): int =
  ## `84307 * world.getMapSeed() + 20201 * (cow.getID() / 2)` is Java `int`
  ## arithmetic and it OVERFLOWS on most map seeds (`84307 * 43223` alone is
  ## 3 644 001 461). Java wraps; a checked Nim conversion would raise on
  ## exactly the seeds that matter, so the product is taken in `uint32` and
  ## reinterpreted, then sign-extended by `new Random(long)`.
  let a = cast[uint32](int32(mapSeed)) * 84307'u32
  let b = cast[uint32](int32(cowId div 2)) * 20201'u32
  int(cast[int32](a + b))

proc runCow*(w: World, cow: Robot) =
  if cow.id notin w.cowRand:
    w.cowRand[cow.id] = initJavaRandom(cowSeed(w.map.randomSeed, cow.id))
  var rng = w.cowRand[cow.id]
  var i = 4
  if isReady(cow):
    while i > 0:
      dec i
      var d = CowDirections[int(rng.nextDouble() * 8.0)]
      if cow.id mod 2 == 1:
        d = w.reverseDirection(d)
      if w.canMove(cow, d) and not w.isFlooded(cow.loc + d):
        w.move(cow, d)
        break
  else:
    while i > 0:
      dec i
      discard rng.nextDouble()
  w.cowRand[cow.id] = rng
