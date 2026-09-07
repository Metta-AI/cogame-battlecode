## bc24 flags: setup carries own flags only, after setup enemy flags only, the
## same-round-drop refusal, `locIsStartRef` (Java's OBJECT-IDENTITY start-
## location test) including a flag dropped on its own start tile, the four-and
## twenty-five round return timers and WHICH team's upgrade changes them, the
## round-200 confirmation in both branches, stacked flags with independent
## timers and oldest-first pickup, capture by walking in and by picking up
## while already standing in a friendly spawn zone, and the third capture
## setting the winner mid-round.

import harness
import bc24_fixture
import battlecode/years/bc24/[flags, rules]

# --- who may pick up what, and when -----------------------------------------
block:
  var w = bare()
  w.currentRound = 50
  let a = w.placeDuck(teamA, loc(3, 4))
  check("during setup a duck may take its OWN flag",
    w.canPickupFlag(a, loc(3, 3)))
  let bFlag = w.ownFlags(teamB)[0]
  let b = w.placeDuck(teamA, bFlag.loc + dWest)
  check("but never the enemy's", not w.canPickupFlag(b, bFlag.loc))
  w.postSetup()
  check("after setup it may take the ENEMY's",
    w.canPickupFlag(b, bFlag.loc))
  check("and no longer its own", not w.canPickupFlag(a, loc(3, 3)))

block:
  var w = bare()
  w.currentRound = 50
  let a = w.placeDuck(teamA, loc(3, 4))
  a.actionCooldown = 10
  check("the action counter gates a pickup", not w.canPickupFlag(a, loc(3, 3)))
  a.actionCooldown = 0
  check("an empty tile has nothing to take",
    not w.canPickupFlag(a, loc(9, 9)))
  w.pickupFlag(a, loc(3, 3))
  check("the duck is carrying", a.hasFlag())
  checkEq("+10 action cooldown", a.actionCooldown, PickupDropCooldown)
  check("and a full-handed duck cannot take another",
    not w.canPickupFlag(a, loc(3, 3)))
  checkEq("a SETUP pickup is not counted", w.stats.flagsPickedUp[0], 0)

# --- locIsStartRef ----------------------------------------------------------
block:
  var w = bare()
  let f = w.ownFlags(teamA)[0]
  check("a fresh flag's loc IS its start location, by identity",
    f.locIsStartRef)
  w.currentRound = 50
  let a = w.placeDuck(teamA, loc(3, 4))
  w.pickupFlag(a, f.loc)
  check("a pickup clears it", not f.locIsStartRef)
  a.actionCooldown = 0
  w.dropFlag(a, loc(3, 3))
  check("dropping the flag back on its OWN START TILE does NOT restore it "
    , not f.locIsStartRef)
  checkEq("and the coordinates are the same tile", f.loc, f.startLoc)

block:
  ## The consequence: a flag dropped on its own start tile still runs a return
  ## timer, and it cannot be picked up in the round it was dropped.
  var w = bare()
  w.postSetup()
  let f = w.ownFlags(teamB)[0]
  let a = w.placeDuck(teamA, f.loc + dWest)
  w.pickupFlag(a, f.loc)
  a.actionCooldown = 0
  w.dropFlag(a, a.loc)
  checkEq("droppedRounds starts at zero", f.droppedRounds, 0)
  let b = w.placeDuck(teamA, a.loc + dWest)
  check("nobody may pick it up in the round it was dropped",
    not w.canPickupFlag(b, f.loc))
  w.resetDroppedFlags()
  checkEq("the timer ticks", f.droppedRounds, 1)
  check("and now it may be taken", w.canPickupFlag(b, f.loc))

# --- the return timer -------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let f = w.ownFlags(teamB)[0]
  let home = f.startLoc
  let a = w.placeDuck(teamA, f.loc + dWest)
  w.pickupFlag(a, f.loc)
  a.actionCooldown = 0
  w.dropFlag(a, a.loc)
  ## `droppedRounds` starts at zero and the test is `>= 4`, so the flag flies
  ## home on the FIFTH end-of-round -- four whole rounds after the round it
  ## was dropped in, which is what "four rounds" means.
  for i in 1 .. 4:
    w.resetDroppedFlags()
  check("four ticks is not enough", not (f.loc == home))
  w.resetDroppedFlags()
  check("the fifth end-of-round flies it home", f.loc == home)
  check("and its identity is restored", f.locIsStartRef)

block:
  ## CAPTURING held by the OPPONENT of the flag's owner stretches the delay
  ## from 4 to 25. Team A holds it; the flag belongs to team B.
  var w = bare()
  w.postSetup()
  w.stats.upgrades[ord(teamA)][1] = true
  let f = w.ownFlags(teamB)[0]
  let home = f.startLoc
  let a = w.placeDuck(teamA, f.loc + dWest)
  w.pickupFlag(a, f.loc)
  a.actionCooldown = 0
  w.dropFlag(a, a.loc)
  for i in 1 .. 25:
    w.resetDroppedFlags()
  check("twenty-five ticks is not enough", not (f.loc == home))
  w.resetDroppedFlags()
  check("the twenty-sixth is", f.loc == home)

block:
  ## The flag's OWN team holding CAPTURING changes nothing about its own
  ## flags' return delay.
  var w = bare()
  w.postSetup()
  w.stats.upgrades[ord(teamB)][1] = true
  let f = w.ownFlags(teamB)[0]
  let home = f.startLoc
  let a = w.placeDuck(teamA, f.loc + dWest)
  w.pickupFlag(a, f.loc)
  a.actionCooldown = 0
  w.dropFlag(a, a.loc)
  for i in 1 .. 5:
    w.resetDroppedFlags()
  check("still four rounds -- an upgrade only helps against the OTHER team's "
        , f.loc == home)

# --- the round-200 confirmation, both branches ------------------------------
block:
  var w = bare()
  w.currentRound = SetupRounds
  let f = w.ownFlags(teamA)[0]
  let carrier = w.placeDuck(teamA, loc(6, 6))
  w.removeFlagAt(f.loc, f)
  carrier.flag = f
  f.carriedBy = carrier.id
  f.loc = carrier.loc
  f.locIsStartRef = false
  w.processEndOfSetupPhase()
  check("the carrier lost the flag at the confirmation",
    not carrier.hasFlag())
  checkEq("the placement STUCK: start becomes the new tile", f.startLoc,
    loc(6, 6))
  check("and identity is restored", f.locIsStartRef)
  checkEq("no team failed the spacing rule", w.stats.setupFlagTeleports, 0)

block:
  var w = bare()
  w.currentRound = SetupRounds
  let flagsA = w.ownFlags(teamA)
  let homes = [flagsA[0].startLoc, flagsA[1].startLoc, flagsA[2].startLoc]
  ## Put flag 0 right next to flag 1: dist^2 = 1 < 36.
  w.removeFlagAt(flagsA[0].loc, flagsA[0])
  w.addFlagAt(flagsA[1].loc + dEast, flagsA[0])
  w.processEndOfSetupPhase()
  checkEq("all three of that team's flags teleported home",
    [flagsA[0].loc, flagsA[1].loc, flagsA[2].loc], homes)
  checkEq("and it was recorded", w.stats.setupFlagTeleports, 1)
  let flagsB = w.ownFlags(teamB)
  check("team B is judged INDEPENDENTLY and kept its own",
    flagsB[0].locIsStartRef)

# --- stacked flags ----------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let flagsB = w.ownFlags(teamB)
  let tile = loc(10, 10)
  w.removeFlagAt(flagsB[0].loc, flagsB[0])
  w.addFlagAt(tile, flagsB[0])
  flagsB[0].droppedRounds = 3
  w.removeFlagAt(flagsB[1].loc, flagsB[1])
  w.addFlagAt(tile, flagsB[1])
  flagsB[1].droppedRounds = 1
  checkEq("two flags on one tile", w.flagsAt(tile).len, 2)
  w.resetDroppedFlags()
  checkEq("with INDEPENDENT timers", flagsB[0].droppedRounds, 4)
  checkEq("and they really are independent", flagsB[1].droppedRounds, 2)
  let a = w.placeDuck(teamA, tile + dWest)
  w.pickupFlag(a, tile)
  check("a pickup takes the FIRST in list order", a.flag == flagsB[0])
  checkEq("leaving one behind", w.flagsAt(tile).len, 1)

# --- capture ----------------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let f = w.ownFlags(teamB)[0]
  let a = w.placeDuck(teamA, loc(4, 3))
  w.removeFlagAt(f.loc, f)
  a.flag = f
  f.carriedBy = a.id
  f.loc = a.loc
  w.doMove(a, dWest)
  checkEq("walking into a friendly spawn zone captures",
    w.stats.flagsCaptured[0], 1)
  check("the carrier is empty-handed", not a.hasFlag())
  checkEq("and the flag left the game", w.allFlags.len, 5)

block:
  var w = bare()
  w.postSetup()
  let f = w.ownFlags(teamB)[0]
  ## Put the enemy flag ON our spawn zone and pick it up from inside.
  w.moveFlagSetStartLoc(f, loc(3, 4))
  let a = w.placeDuck(teamA, loc(3, 3))
  w.pickupFlag(a, loc(3, 4))
  checkEq("picking up while already standing in a friendly spawn zone "
    , w.stats.flagsCaptured[0], 1)
  check("captures on the spot", not a.hasFlag())

block:
  ## The third capture sets the winner THE INSTANT it lands, but `running` is
  ## only cleared at the end of the round -- so the rest of the exec order
  ## still takes its turn.
  var w = bare()
  w.postSetup()
  w.stats.flagsCaptured[0] = 2
  let f = w.ownFlags(teamB)[0]
  let a = w.placeDuck(teamA, loc(4, 3))
  w.removeFlagAt(f.loc, f)
  a.flag = f
  f.carriedBy = a.id
  f.loc = a.loc
  w.doMove(a, dWest)
  checkEq("three captures", w.stats.flagsCaptured[0], 3)
  check("the winner is set at once", w.hasWinner)
  checkEq("with the CAPTURE domination", w.domination, dfCapture)
  check("but the round is still running", w.running)
  w.checkEndOfMatch()
  check("and only the end-of-round check stops it", not w.running)

# --- drops -----------------------------------------------------------------
block:
  var w = bare()
  w.postSetup()
  let f = w.ownFlags(teamB)[0]
  let a = w.placeDuck(teamA, f.loc + dWest)
  w.pickupFlag(a, f.loc)
  a.actionCooldown = 0
  w.water[w.idx(a.loc + dWest)] = true
  check("a flag cannot be dropped onto water",
    not w.canDropFlag(a, a.loc + dWest))
  check("but its own tile is fine", w.canDropFlag(a, a.loc))

block:
  var w = bare()
  w.postSetup()
  let f = w.ownFlags(teamB)[0]
  let a = w.placeDuck(teamA, f.loc + dWest)
  w.pickupFlag(a, f.loc)
  let at = a.loc
  w.addHealth(a, -DefaultHealth)
  check("a jailed carrier drops its flag ON ITS OWN TILE", f.loc == at)
  check("and is no longer carrying", f.carriedBy < 0)
  check("the tile holds it", w.hasFlagAt(at))

finish("bc24 flags")
