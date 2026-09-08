## `examplefuncsplayer22`, statement for statement.
##
## §Tests item 15. IT MAY NOT GAIN BEHAVIOUR: it is one side of the
## differential oracle, and the Java side of that oracle is upstream's file
## byte for byte apart from its `package` line.

import harness
import bc22_fixture
import battlecode/rng
import battlecode/years/bc22/chassis/scaffold22

block:
  ## The RNG is `new Random(6147)` and static fields are PER ROBOT under the
  ## instrumenter, so every unit carries its own stream.
  var w = bare()
  let a = w.place(teamA, rtMiner, loc(5, 5))
  let b = w.place(teamA, rtMiner, loc(7, 5))
  checkEq("two robots start with the SAME stream", a.scaffoldRng.seed,
    b.scaffoldRng.seed)
  var reference = initJavaRandom(6147)
  checkEq("which is Random(6147)", a.scaffoldRng.seed, reference.seed)
  discard a.scaffoldRng.nextInt(8)
  check("and they advance INDEPENDENTLY",
    a.scaffoldRng.seed != b.scaffoldRng.seed)

block:
  ## The eight `directions`, in the order `rng.nextInt(8)` indexes.
  checkEq("directions[0] is NORTH", MoveDirs[0], dNorth)
  checkEq("directions[1] is NORTHEAST", MoveDirs[1], dNortheast)
  checkEq("directions[2] is EAST", MoveDirs[2], dEast)
  checkEq("directions[3] is SOUTHEAST", MoveDirs[3], dSoutheast)
  checkEq("directions[4] is SOUTH", MoveDirs[4], dSouth)
  checkEq("directions[5] is SOUTHWEST", MoveDirs[5], dSouthwest)
  checkEq("directions[6] is WEST", MoveDirs[6], dWest)
  checkEq("directions[7] is NORTHWEST", MoveDirs[7], dNorthwest)
  checkEq("and there are exactly eight", MoveDirs.len, 8)

block:
  ## THE ARCHON PICKS ITS DIRECTION *BEFORE* THE COIN FLIP. That order fixes
  ## the whole stream, so it is asserted against a reference `java.util.Random`
  ## rather than against the port's own behaviour.
  var w = bare(archons = @[(id: 2, x: 10, y: 10, team: 1),
                           (id: 3, x: 25, y: 10, team: 2)])
  let arch = w.robotsById[2]
  var reference = initJavaRandom(6147)
  let wantDir = MoveDirs[int(reference.nextInt(8))]
  let wantMiner = reference.nextBoolean()
  runScaffold22(w, arch)
  let built = w.getRobot(arch.loc + wantDir)
  check("something was built in the drawn direction", built != nil)
  if built != nil:
    checkEq("and it is what the coin flip said",
      built.kind, (if wantMiner: rtMiner else: rtSoldier))
  checkEq("the archon's stream advanced by exactly two draws",
    arch.scaffoldRng.seed, reference.seed)

block:
  ## The miner: `dx, dy in {-1, 0, 1}` in THAT order, and per square
  ## `while (canMineGold) ... while (canMineLead)`. Because a miner's action
  ## cooldown is 2, the inner loops really do fire up to five times a turn.
  var w = bare(lead = @[(l: loc(9, 9), amount: 20), (l: loc(10, 10), amount: 20)])
  w.setGold(loc(9, 9), 3)
  let m = w.place(teamA, rtMiner, loc(10, 10))
  runScaffold22(w, m)
  checkEq("gold at the FIRST square in dx/dy order is taken first",
    w.getGold(loc(9, 9)), 0)
  checkEq("three gold reached the reserve", w.teamGold(teamA), 3)
  checkEq("and the remaining two actions went to LEAD on that same square",
    w.getLead(loc(9, 9)), 18)
  checkEq("so the miner's own square is untouched this turn",
    w.getLead(loc(10, 10)), 20)
  checkEq("five actions in all", m.actionCooldown, 10)

block:
  ## The soldier attacks `senseNearbyRobots(actionRadiusSquared, opponent)[0]`
  ## — which is the FIRST enemy in the engine's scan order, i.e. the most
  ## WESTERN one, not the nearest.
  var w = bare()
  let s = w.place(teamA, rtSoldier, loc(10, 10))
  let west = w.place(teamB, rtMiner, loc(8, 10))
  let near = w.place(teamB, rtMiner, loc(11, 10))
  runScaffold22(w, s)
  checkEq("the WESTERN enemy is the one hit", west.health,
    maxHealthOf(rtMiner, 1) - 3)
  checkEq("and the nearer one is untouched", near.health,
    maxHealthOf(rtMiner, 1))

block:
  ## A BUILDER, a SAGE, a LABORATORY and a WATCHTOWER do NOTHING AT ALL. That
  ## is why this bot never makes a gold, never puts up a building and always
  ## ends at round 2000 on MORE_LEAD_NET_WORTH.
  var w = bare()
  w.addLead(teamA, 1000)
  w.addGold(teamA, 1000)
  for kind in [rtBuilder, rtSage, rtLaboratory, rtWatchtower]:
    var w2 = bare()
    w2.addLead(teamA, 1000)
    w2.addGold(teamA, 1000)
    let r = w2.placeLive(teamA, kind, loc(10, 10))
    let enemy = w2.place(teamB, rtMiner, loc(11, 10))
    let before = (r.loc, r.actionCooldown, r.movementCooldown, r.mode,
                  enemy.health, w2.robotsById.len)
    runScaffold22(w2, r)
    checkEq($kind & " does not move", r.loc, before[0])
    checkEq($kind & " spends no action", r.actionCooldown, before[1])
    checkEq($kind & " spends no movement", r.movementCooldown, before[2])
    checkEq($kind & " does not transform", r.mode, before[3])
    checkEq($kind & " attacks nothing", enemy.health, before[4])
    checkEq($kind & " builds nothing", w2.robotsById.len, before[5])
  discard w

block:
  ## And end to end: the bot ACTS — miners, soldiers, lead and attacks — but is
  ## not required to survive, to build a building, or to compete.
  var totalMiners = 0
  var totalSoldiers = 0
  var totalLead = 0
  var totalDamage = 0
  var totalLabs = 0
  var totalGold = 0
  for sideAslot in 0 .. 1:
    let (w, o) = playGame(loadMap("chalice"), defaultSheets(),
      [ckExamplefuncsplayer22, ckExamplefuncsplayer22], 0, sideAslot, 600, 0)
    for slot in 0 .. 1:
      totalMiners += o.minersBuilt[slot]
      totalSoldiers += o.soldiersBuilt[slot]
      totalLead += o.leadMined[slot]
      totalDamage += o.damageDealt[slot]
      totalLabs += o.labsBuilt[slot]
      totalGold += o.goldTransmuted[slot]
    checkEq("the scaffold emits no illegal order", w.refusedActions, 0)
  check("it builds miners", totalMiners >= 1)
  check("it builds soldiers", totalSoldiers >= 1)
  check("it mines lead", totalLead >= 1)
  check("it lands attacks", totalDamage >= 1)
  checkEq("and it NEVER builds a laboratory", totalLabs, 0)
  checkEq("so it never makes a single gold", totalGold, 0)

finish("test_bc22_scaffold")
