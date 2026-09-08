## bc23's wells: the rate, the adjacency that includes the carrier's own
## tile, the capacity, the 600 kg ELIXIR TRANSFORMATION, the 1400 kg RATE
## UPGRADE, and the fact that a positive transfer into a well removes the
## resource from the team total FOR GOOD.

import harness
import bc23_fixture

# --- the rate, and `-1` meaning "the rate" ---------------------------------
block:
  var w = bare(wells = @[(l: loc(11, 10), kind: 1)])
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  checkEq("a fresh well is rate 1", w.wellAtLoc(loc(11, 10)).rate(), 1)
  check("collect(-1) is legal", w.canCollectResource(c, loc(11, 10), -1))
  check("collect(1) is legal", w.canCollectResource(c, loc(11, 10), 1))
  check("collect(2) is NOT — above the rate",
    not w.canCollectResource(c, loc(11, 10), 2))
  check("a negative amount below -1 is refused",
    not w.canCollectResource(c, loc(11, 10), -2))
  discard w.doCollectResource(c, loc(11, 10), -1)
  checkEq("`-1` collected exactly the rate", c.adamantium, 1)

# --- adjacency INCLUDES the carrier's own tile ------------------------------
block:
  var w = bare(wells = @[(l: loc(10, 10), kind: 2)])
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  check("a carrier standing ON a well can collect from it",
    w.canCollectResource(c, loc(10, 10), -1))
  let d = w.place(teamA, rtCarrier, loc(11, 11))
  check("and so can one diagonally adjacent",
    w.canCollectResource(d, loc(10, 10), -1))
  let e = w.place(teamA, rtCarrier, loc(12, 12))
  check("but not one two tiles away, even though r2 = 8 <= 9",
    not w.canCollectResource(e, loc(10, 10), -1))
  checkEq("(the action radius really does reach it)",
    e.loc.distanceSquaredTo(loc(10, 10)), 8)

# --- capacity 40 -----------------------------------------------------------
block:
  var w = bare(wells = @[(l: loc(10, 10), kind: 1)])
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  w.addResourceAmount(c, resAdamantium, 40)
  check("a full carrier cannot collect", not c.canAdd(1))
  check("and the collect is refused",
    not w.canCollectResource(c, loc(10, 10), -1))
  checkEq("an anchor weighs the WHOLE capacity", AnchorWeight, CarrierCapacity)

# --- the 600 kg transformation ---------------------------------------------
block:
  var well = newWell(resMana)
  well.addResourceAmount(resAdamantium, 599)
  checkEq("599 kg of adamantium leaves a mana well alone", ord(well.kind),
    ord(resMana))
  well.addResourceAmount(resAdamantium, 1)
  checkEq("600 kg turns it into an ELIXIR well", ord(well.kind),
    ord(resElixir))
  checkEq("and it is not upgraded by that", int(well.upgraded), 0)
  ## An elixir well counts its 1400 against ELIXIR thereafter.
  well.addResourceAmount(resAdamantium, 1400)
  checkEq("more adamantium does NOT upgrade it", int(well.upgraded), 0)
  well.addResourceAmount(resElixir, 1400)
  checkEq("1400 kg of elixir does", int(well.upgraded), 1)
  checkEq("and the rate is 3", well.rate(), 3)

block:
  var well = newWell(resAdamantium)
  well.addResourceAmount(resMana, 600)
  checkEq("600 kg of MANA transforms an adamantium well", ord(well.kind),
    ord(resElixir))

block:
  var well = newWell(resAdamantium)
  well.addResourceAmount(resAdamantium, 1399)
  checkEq("1399 kg of its own type does not upgrade", int(well.upgraded), 0)
  well.addResourceAmount(resAdamantium, 1)
  checkEq("1400 does", int(well.upgraded), 1)
  checkEq("the rate is 3", well.rate(), 3)
  checkEq("and it is still an adamantium well", ord(well.kind),
    ord(resAdamantium))

block:
  checkEq("the opposite of adamantium is mana", ord(opposite(resAdamantium)),
    ord(resMana))
  checkEq("and the opposite of mana is adamantium", ord(opposite(resMana)),
    ord(resAdamantium))
  checkEq("elixir has no opposite", ord(opposite(resElixir)), ord(resNone))

# --- collecting at rate 3 after the upgrade --------------------------------
block:
  var w = bare(wells = @[(l: loc(10, 10), kind: 1)])
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  w.wellAt[w.idx(loc(10, 10))].addResourceAmount(resAdamantium, 1400)
  checkEq("the well is upgraded", w.wellAtLoc(loc(10, 10)).rate(), 3)
  check("collect(3) is legal", w.canCollectResource(c, loc(10, 10), 3))
  check("collect(4) is not", not w.canCollectResource(c, loc(10, 10), 4))
  discard w.doCollectResource(c, loc(10, 10), -1)
  checkEq("`-1` collected THREE", c.adamantium, 3)

# --- a transfer INTO a well leaves the team total for good ------------------
block:
  var w = bare(wells = @[(l: loc(11, 10), kind: 2)])
  let c = w.place(teamA, rtCarrier, loc(10, 10))
  w.addResourceAmount(c, resAdamantium, 30)
  checkEq("the team holds 30", w.teamResource(teamA, resAdamantium), 30)
  check("the transfer is legal",
    w.canTransferResource(c, loc(11, 10), resAdamantium, 30))
  check("and it happens", w.doTransferResource(c, loc(11, 10),
    resAdamantium, 30))
  checkEq("THE WELL SWALLOWED IT", w.teamResource(teamA, resAdamantium), 0)
  checkEq("the carrier is empty", c.adamantium, 0)
  checkEq("and the well remembers it", w.wellAtLoc(loc(11, 10)).adamantium, 30)

# --- a transfer to a friendly headquarters -------------------------------
block:
  var w = bare()
  let c = w.place(teamA, rtCarrier, loc(4, 15))
  w.addResourceAmount(c, resMana, 12)
  check("a positive transfer to a friendly headquarters is legal",
    w.canTransferResource(c, loc(3, 15), resMana, 12))
  check("and it happens", w.doTransferResource(c, loc(3, 15), resMana, 12))
  checkEq("the headquarters holds it", w.robotsById[2].mana, 12)
  checkEq("and the TEAM total is unchanged — it never left",
    w.teamResource(teamA, resMana), 12)
  checkEq("resources_banked records the deposit",
    w.stats.resourcesBanked[0], 12)
  check("a zero transfer is refused",
    not w.canTransferResource(c, loc(3, 15), resMana, 0))

# --- a NEGATIVE transfer: only from a friendly headquarters that holds it ---
block:
  var w = bare(wells = @[(l: loc(5, 15), kind: 1)])
  let c = w.place(teamA, rtCarrier, loc(4, 15))
  let hq = w.robotsById[2]
  w.addResourceAmount(hq, resAdamantium, 20)
  check("withdrawing 20 is legal",
    w.canTransferResource(c, loc(3, 15), resAdamantium, -20))
  check("withdrawing 21 is not — the headquarters has 20",
    not w.canTransferResource(c, loc(3, 15), resAdamantium, -21))
  check("withdrawing from a WELL is not legal at all",
    not w.canTransferResource(c, loc(5, 15), resAdamantium, -1))
  check("and it happens", w.doTransferResource(c, loc(3, 15),
    resAdamantium, -20))
  checkEq("the carrier holds it", c.adamantium, 20)
  checkEq("the headquarters does not", hq.adamantium, 0)

block:
  ## And the capacity bounds a withdrawal.
  var w = bare()
  let c = w.place(teamA, rtCarrier, loc(4, 15))
  let hq = w.robotsById[2]
  w.addResourceAmount(hq, resAdamantium, 100)
  check("withdrawing 41 exceeds the carrier's capacity",
    not w.canTransferResource(c, loc(3, 15), resAdamantium, -41))
  check("withdrawing 40 does not",
    w.canTransferResource(c, loc(3, 15), resAdamantium, -40))

finish("test_bc23_wells")
