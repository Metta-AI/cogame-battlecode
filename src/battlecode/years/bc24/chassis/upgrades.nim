## bc24 global upgrades: one point per team at rounds 600, 1200 and 1800, spent
## by the FIRST duck of the team to act that round in the order the doctrine's
## `upgrade_order` names.
##
## Buying costs no crumbs, no cooldown and has no range, so there is never a
## reason to hold a point. `ACTION` is a backwards-compatibility alias of
## `ATTACK` and is not offered (docs/RULES-BC24.md §Divergences item 5).

import kit

export kit

func upgradeKindOf*(choice: UpgradeChoice): UpgradeKind =
  case choice
  of ucAttack: ugAttack
  of ucHeal: ugHealing
  of ucCapture: ugCapturing

proc spendUpgradePoint*(w: World, side: Side, r: Robot): bool
    {.discardable.} =
  if w.stats.upgradePoints[ord(side.team)] <= 0: return false
  for choice in side.doctrine.upgradeOrder:
    let kind = choice.upgradeKindOf()
    if w.canBuyGlobal(r, kind):
      w.doBuyGlobal(r, kind)
      return true
  false
