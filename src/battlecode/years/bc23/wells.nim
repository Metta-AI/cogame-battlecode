## The bc23 wells: type, swallowed inventory, and the two transformations.
##
## A behaviour port of `world/Well.java` at commit
## `af42086ecd09709dc603b2aaa9e9b98312c9ef79`. A well is a permanent map
## feature — it is never created, moved or destroyed during a game — and it
## holds an INVENTORY of everything ever poured into it. Two thresholds move
## it:
##
## * **600 kg of the OPPOSITE resource turns it into an elixir well** and it
##   stops producing its old resource for good;
## * **1400 kg of ITS OWN CURRENT type upgrades its rate from 1 to 3**, and
##   after a transformation "its own type" means elixir.
##
## `addResourceAmount` reproduces `Well.addAdamantium` / `addMana` /
## `addElixir` literally, including the order of the two tests inside each,
## because that order is what makes a mana well that has swallowed 600 kg of
## adamantium become elixir BEFORE the 1400 kg upgrade test can ever see it.

import units

export units

type
  Well* = object
    present*: bool
    kind*: Resource          ## the well's CURRENT type
    adamantium*: int
    mana*: int
    elixir*: int
    upgraded*: bool

func newWell*(kind: Resource): Well =
  Well(present: true, kind: kind)

func rate*(w: Well): int =
  if w.upgraded: WellAcceleratedRate else: WellStandardRate

func held*(w: Well, r: Resource): int =
  case r
  of resAdamantium: w.adamantium
  of resMana: w.mana
  of resElixir: w.elixir
  of resNone: 0

proc addResourceAmount*(w: var Well, r: Resource, amount: int) =
  ## `Well.addResourceAmount`, statement for statement.
  case r
  of resAdamantium:
    w.adamantium += amount
    if w.kind == resMana and w.adamantium >= UpgradeToElixir:
      w.kind = resElixir
    if w.kind == resAdamantium and w.adamantium >= UpgradeWellAmount and
        not w.upgraded:
      w.upgraded = true
  of resMana:
    w.mana += amount
    if w.kind == resAdamantium and w.mana >= UpgradeToElixir:
      w.kind = resElixir
    if w.kind == resMana and w.mana >= UpgradeWellAmount and not w.upgraded:
      w.upgraded = true
  of resElixir:
    w.elixir += amount
    if w.kind == resElixir and w.elixir >= UpgradeWellAmount and
        not w.upgraded:
      w.upgraded = true
  of resNone:
    discard

func opposite*(r: Resource): Resource =
  ## The resource a doctrine has to pour in to transform a well of type `r`.
  case r
  of resAdamantium: resMana
  of resMana: resAdamantium
  else: resNone

func elixirProgress*(w: Well): int =
  ## How much of the 600 kg opposite-resource transformation is already in the
  ## well. Zero for a well that is already elixir. Never read by a rule; the
  ## viewer draws it as the `600 -> 412` badge.
  case w.kind
  of resAdamantium: min(w.mana, UpgradeToElixir)
  of resMana: min(w.adamantium, UpgradeToElixir)
  else: 0
