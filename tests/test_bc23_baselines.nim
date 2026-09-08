## bc23's two baselines: both `PLAYER_SCRIPTED` resolutions producing a sheet
## that passes the SAME `validate` the LLM path uses; EVERY ACTION EITHER
## CHASSIS EMITS BEING LEGAL for the acting robot at the moment it is emitted
## (the `refusedActions` audit) and no robot exceeding its `DecisionOps`
## budget; `examplefuncsplayer23` ACTING but not required to survive; and
## `lemonade` beating it 6/6.

import std/json
import harness
import bc23_fixture
import battlecode/baselines
import battlecode/years/dispatch

# --- (a) both resolutions pass the same validate ------------------------
block:
  checkEq("the bc23 default baseline is `lemonade`",
    $defaultBaselineFor("bc23"), "lemonade")
  for name in ["awu", "lemonade", "", "nonsense", "spaark"]:
    checkEq("`" & name & "` resolves to lemonade on bc23",
      $baselineFor("bc23", name), "lemonade")
  for name in ["scaffold", "examplefuncsplayer", "examplefuncsplayer23",
               "example"]:
    checkEq("`" & name & "` resolves to examplefuncsplayer23 on bc23",
      $baselineFor("bc23", name), "examplefuncsplayer23")
  for kind in [blLemonade, blExamplefuncsplayer23]:
    let s = baselineSheet("bc23", kind)
    checkEq($kind & "'s reply passes validate with no repairs",
      s.defaultsApplied.len, 0)
    checkEq("and no unknown fields", s.unknownFields.len, 0)
    checkEq("and it is the ALL-DEFAULTS sheet — which is also the fallback " &
      "sheet the note prints verbatim", $(s.toJson()),
      $(defaultSheet("bc23").toJson()))
    check("the notes survive", s.notes.len > 0)
  checkEq("`lemonade` maps to the year-neutral chassis value",
    $baselineChassis(blLemonade), "lemonade")
  checkEq("and so does the weak floor",
    $baselineChassis(blExamplefuncsplayer23), "examplefuncsplayer23")
  checkEq("an LLM seat on bc23 drives `lemonade`",
    $strongChassisFor("bc23"), "lemonade")
  ## A chassis name belonging to ANOTHER year falls back to bc23's strong one.
  checkEq("`spaark` on a bc23 game plays lemonade",
    chassisKindFor(scSpaark), ckLemonade)
  checkEq("and `examplefuncsplayer25` too",
    chassisKindFor(scExamplefuncsplayer25), ckLemonade)
  checkEq("while bc23's own weak name is honoured",
    chassisKindFor(scExamplefuncsplayer23), ckExamplefuncsplayer23)

# --- (b) every action is legal, and no robot overspends its budget -------
block:
  for mapName in ["Quiet", "Barcode"]:
    for pair in [[ckLemonade, ckLemonade],
                 [ckLemonade, ckExamplefuncsplayer23],
                 [ckExamplefuncsplayer23, ckExamplefuncsplayer23]]:
      let (w, o) = mirror(600, mapName, defaultSheet("bc23"), pair)
      checkEq(mapName & " " & $pair[0] & "/" & $pair[1] &
        ": NO ILLEGAL ORDER — every `do*` re-checked its own `can*`",
        w.refusedActions, 0)
      check(mapName & ": no robot exceeded its DecisionOps budget",
        w.opsUsedPeak <= DecisionOpsHeadquarters)
      check(mapName & ": and the peak is a real number", w.opsUsedPeak > 0)
      check(mapName & ": the game actually played", o.roundsPlayed > 0)
      ## No headquarters ever moved.
      for id in w.headquarters[0] & w.headquarters[1]:
        if not w.existsRobot(id): continue
        let hq = w.robotsById[id]
        var atStart = false
        for b in w.map.initialBodies:
          if b.id == id and loc(b.x, b.y) == hq.loc: atStart = true
        check(mapName & ": a headquarters never moved", atStart)

# --- (c) `examplefuncsplayer23` ACTS ------------------------------------
block:
  ## It is not required to survive or to compete — only to play.
  let (w, o) = mirror(1200, "Quiet", defaultSheet("bc23"),
    [ckExamplefuncsplayer23, ckExamplefuncsplayer23])
  for seat in 0 .. 1:
    check("seat " & $seat & " built at least one carrier",
      o.carriersBuilt[seat] >= 1)
    check("seat " & $seat & " built at least one launcher",
      o.launchersBuilt[seat] >= 1)
    check("seat " & $seat & " built at least one anchor",
      o.anchorsBuilt[seat] >= 1)
    check("seat " & $seat & " collected at least once",
      o.adamantiumMined[seat] + o.manaMined[seat] >= 1)
  check("and at least one throw landed across the pair",
    o.throwDamage[0] + o.throwDamage[1] >= 1)
  checkEq("but it NEVER deposits — which is what makes it the weak floor",
    o.resourcesBanked[0] + o.resourcesBanked[1], 0)
  discard w

# --- (d) `lemonade` beats `examplefuncsplayer23` 6/6 -------------------
block:
  var wins = 0
  var games = 0
  for mapName in ["Quiet", "Barcode"]:
    for seed in [7, 263, 519]:
      let sideAslot = sideAslotFor(seed, 0)
      ## Seat 0 is always `lemonade`; the side it plays alternates with the
      ## seed, so the result is not an artefact of the exec order.
      let (w, o) = mirror(2000, mapName, defaultSheet("bc23"),
        [ckLemonade, ckExamplefuncsplayer23], sideAslot)
      games += 1
      if o.winnerSlot == 0: wins += 1
      checkEq(mapName & "/" & $seed & ": no illegal order", w.refusedActions, 0)
  checkEq("`lemonade` beats `examplefuncsplayer23` on 3 seeds x 2 small maps",
    wins, games)
  checkEq("which is six games", games, 6)

finish("test_bc23_baselines")
