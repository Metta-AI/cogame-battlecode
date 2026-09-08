## `lemonade`'s elixir programme: `program()` and `sink()`.
##
## Behaviour ported from `vrangr1/BattleCode2023`
## `src/AFinalsBot/ElixirProducer.java` + `BotBooster.java` +
## `BotDestabilizer.java` (AGPL-3.0, head `244af40e`, 4th place) — the only
## published bot of the three that actually ran the elixir tree, which is why
## this year's headline doctrine axis has a real behaviour source.
##
## ONE GATE IS DELIBERATELY DROPPED. `ElixirProducer.shouldProduceElixir`
## additionally requires `MAP_SIZE > 1000`; the `small` pool's maps are 400
## tiles, and keeping that gate would make `elixir_tech` and `elixir_spend`
## dead knobs on a third of the map set, which the anti-inert rule forbids
## (§Decisions, and docs/RULES-BC23.md §Divergences item 13).
##
## THE TARGET is the mana well closest to one of our own headquarters and
## furthest from theirs; deposits go in 40 kg carrier loads of ADAMANTIUM,
## because 600 kg of the OPPOSITE resource is what transforms a well.

import ../world, kit

export kit

func elixirOpensAt*(side: Side): int =
  case side.doctrine.elixirTech
  of etNever: high(int)
  of etMid: 500
  of etEarly: 200

func elixirRunning*(w: World, side: Side): bool =
  ## `shouldProduceElixir`, minus the map-size gate: past the opening round,
  ## with a real army on the board and at least two wells being worked.
  if side.doctrine.elixirTech == etNever: return false
  if w.currentRound < elixirOpensAt(side): return false
  if side.doctrine.elixirTech == etMid:
    if side.carriers + side.launchers < 20: return false
    if side.knownWells.len < 2: return false
  true

proc chooseTarget*(w: World, side: Side) =
  ## `program()`. Picks once and keeps it: a half-converted well that the
  ## faction abandons is 600 kg thrown into a hole.
  if side.hasElixirTarget:
    if w.wellAtLoc(side.elixirTarget).kind == resElixir:
      ## Done — the programme has flipped its well. Look for the next one
      ## only if the doctrine is `early`, which can afford a second.
      if side.doctrine.elixirTech != etEarly:
        return
      side.hasElixirTarget = false
    else:
      return
  var best = high(int)
  for l in side.knownWells:
    if w.wellAtLoc(l).kind != resMana: continue
    var toHome = high(int)
    for h in side.homeHqs: toHome = min(toHome, chebyshev(h, l))
    var toEnemy = high(int)
    for h in side.enemyHqs: toEnemy = min(toEnemy, chebyshev(h, l))
    if toHome == high(int): toHome = 0
    if toEnemy == high(int): toEnemy = 0
    let score = toHome * 3 - toEnemy
    if score < best:
      best = score
      side.elixirTarget = l
      side.hasElixirTarget = true

func elixirProgress*(w: World, side: Side): int =
  if not side.hasElixirTarget: 0
  else: w.wellAtLoc(side.elixirTarget).elixirProgress()

func sinkUnit*(side: Side): RobotType =
  ## `sink()` — what the elixir buys once it flows. `accelerating_anchors` is
  ## spent by `anchors.nim`, so this reports the headquarters-built unit only.
  case side.doctrine.elixirSpend
  of esBoosters: rtBooster
  of esDestabilizers: rtDestabilizer
  of esAcceleratingAnchors: rtHeadquarters
