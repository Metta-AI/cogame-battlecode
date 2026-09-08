## `gold.nim` — `sink()`: what gold buys once it flows.
##
## Behaviour ported from `BSreenivas0713/Battlecode2022` `src/MPTempName/`
## (AGPL-3.0): the mutation ladder's marginal-value ordering. BEHAVIOUR, NOT
## CODE. `NOTICE` names the file.
##
## `gold_use: sages` — 20 Au each, 45 damage, one shot every twenty turns, and
## the only unit that can envision an anomaly. Handled in `econ.nim`'s build
## order, because a sage is built by an ARCHON.
##
## `gold_use: mutations` — the LEVEL-3 mutations, which cost gold: 25 Au for a
## laboratory (k = 0.005, i.e. two lead a gold out to n = 8), 60 Au for a
## watchtower (12 damage), 80 Au for an archon (1944 HP and +6 repair). The
## marginal-value order is exactly that: **a lab first at 25, then a watchtower
## at 60, then an archon at 80** — the cheapest rung that compounds, then the
## one that shoots, then the one that survives.
##
## Level-2 mutations cost LEAD and are governed by `watchtower_policy` and the
## archon programme, not by this knob.
##
## Under `soldier_sage_ratio: 100` this knob has nothing to spend — that is the
## DOCTRINE'S OWN choice, not a dropped field: the value is still recorded and
## `plainWords22` says "no gold programme, so its sink never opens".

import kit, econ

export kit

func mutationValue*(k: RobotType, level: int): int =
  ## Lower is a better buy. The three level-3 gold costs, in the marginal-value
  ## order the 7th-place bot used.
  if level != 3: return high(int)
  case k
  of rtLaboratory: 0
  of rtWatchtower: 1
  of rtArchon: 2
  else: high(int)

proc bestMutationTarget*(w: World, side: Side, r: Robot): Robot =
  ## The best friendly building inside the builder's r2 <= 5 to mutate, or nil.
  ##
  ## Level 2 is a LEAD buy and is always worth taking on a laboratory (k halves,
  ## so the price curve flattens) and on a watchtower under `watchtower_policy`.
  ## Level 3 is a GOLD buy and is only taken when `gold_use: mutations`.
  result = nil
  var best = high(int)
  for l in w.locationsWithinRadiusSquared(
      r.loc, RobotSpecs[rtBuilder].actionRadiusSquared):
    let b = w.getRobot(l)
    if b == nil or b.team != side.team: continue
    if not b.kind.isBuilding(): continue
    if not b.canMutateSelf(): continue
    let nextLevel = b.level + 1
    if nextLevel == 3 and side.doctrine.goldUse != guMutations: continue
    if nextLevel == 2:
      ## A level-2 watchtower is only bought when the doctrine wants towers at
      ## all, and only once a second laboratory exists — the note's own rule.
      if b.kind == rtWatchtower and
         (side.doctrine.watchtowerPolicy == wpNever or side.labsLive < 2):
        continue
    if not w.canMutate(r, l): continue
    let score =
      if nextLevel == 3: mutationValue(b.kind, 3)
      else: 10 + ord(b.kind)
    if score < best:
      best = score
      result = b

proc goldSinkOpen*(side: Side): bool =
  ## Whether the gold programme has anywhere to spend. Read by
  ## `#bc22-doctrines`' plain-words panel as well as by the chassis.
  side.doctrine.soldierSageRatio < 100
