## `lemonade`'s amplifier placement and the write-window test every other
## module calls before it tries to speak.
##
## Behaviour ported from `awesomelemonade/Battlecode2023` `src/finalBot/`
## (AGPL-3.0), parameterised by `amplifier_use`. An amplifier costs
## 30 Ad + 15 Mn, has no action at all, sees r² ≤ 34 and is the ONLY way a
## robot away from a headquarters (r² ≤ 9) or one of our islands (r² ≤ 4) can
## WRITE the faction's shared array.

import ../world, ../comms as simcomms, kit

export kit

func amplifierPost*(w: World, side: Side, r: Robot): Loc =
  ## Where this amplifier wants to stand.
  ##
  ## * `one`: the midpoint between its nearest headquarters and the frontier,
  ##   so the widest band of our own half can speak;
  ## * `escort`: with the strike group, so a group four squares deep in their
  ##   half still shares targets;
  ## * `never`: unreachable — no amplifier is ever built.
  case side.doctrine.amplifierUse
  of auEscort:
    if side.strikeRound >= 0 and side.strikeCentre.x >= 0: side.strikeCentre
    else: side.nearestEnemyHome(r.loc)
  else:
    let home = side.nearestHome(r.loc)
    let front = side.nearestEnemyHome(home)
    loc((home.x * 2 + front.x) div 3, (home.y * 2 + front.y) div 3)

func canSpeak*(w: World, r: Robot): bool =
  simcomms.canWriteSharedArray(w, r, 0, 0)
