## `bulwark`'s economy: `plan()`, `attackMix()`, `queue()` and the per-archon
## commitment ledger — the ONLY place parts are ever committed.
##
## It also holds the UNCONDITIONAL FLOOR of the anti-inert rule, which is
## independent of every knob: at least `AttackersPerArchonFloor = 3` attackers
## per archon, and a build order whenever the stockpile is above 200. Every
## knob moves HOW MUCH OF WHAT, WHEN — never WHETHER IT PLAYS.

import ../world
import kit

export kit

func attackerTarget*(w: World, s: Side): int =
  ## `plan()`: the attacker census the faction wants standing, by opening.
  ## `turtle` HALVES it, never zeroes it (the anti-inert rule).
  let archons = max(1, s.archons.len)
  let base = case s.doctrine.opening
    of opTurtle: 6 * archons
    of opSoldierViperAggro: 12 * archons
    of opScoutZombiePull: 8 * archons
  max(AttackersPerArchonFloor * archons, base)

func scoutTarget*(w: World, s: Side): int =
  ## `scout_zombie_pull` commissions 2 SCOUTs per archon by round 200; the
  ## other two openings keep one scout per faction as an eye, and
  ## `rubble_clear` wants one as the cheapest digger (movementDelay 1.4).
  let archons = max(1, s.archons.len)
  case s.doctrine.opening
  of opScoutZombiePull: 2 * archons
  else:
    if s.doctrine.rubbleClear == rcNever: 1 else: 2

func openingGuardBias*(opening: Opening16): int =
  ## THE OPENING'S OWN SHARE OF THE ATTACK MIX, and it is what gives `opening`
  ## teeth beyond a census target.
  ##
  ## MEASURED, and the reason this exists: with the attacker TARGET as the
  ## only difference (6 per archon for `turtle` against 12 for
  ## `soldier_viper_aggro`), a paired 800-round game on `river` and `checkers`
  ## produced 116 soldiers against 115 and 63 guards against 80 — i.e. the
  ## knob moved nothing, because the parts economy caps both openings at the
  ## same census long before either target is reached and `guard_ratio` alone
  ## decided the mix. The three openings ARE the three archetypes the 2016
  ## finals produced, and a turret turtle is not a soldier/viper push with a
  ## different unit ceiling, so the opening moves the MIX as well:
  ##
  ##   `turtle`                 0 -- the wall is guards, and the DEFAULT
  ##                                 `guard_ratio: 45` already buys it
  ##   `soldier_viper_aggro`  -20 -- the spearhead is soldiers (4 damage at
  ##                                 r2 <= 13) and the vipers behind them
  ##   `scout_zombie_pull`      0 -- the bait is scouts; the mix is the cog's
  ##
  ## **THE BIAS IS DELIBERATELY ONE-SIDED, and the reason is MEASURED.** A
  ## symmetric +-20 gives the knob the same 40-point spread and the same
  ## teeth, but it also moves the ALL-DEFAULTS game, which is what
  ## `tests/test_bc16_survival.nim` measures: at turtle +20 the mirror falls
  ## to 1 of 6 games ending other than `archons_destroyed`, with 5 dens killed
  ## and a median of 770 rounds, against 3 of 6, 20 dens and 2 147 rounds at
  ## turtle 0. A guard deals 1.5 doubled to 3.0 against a zombie while a den
  ## is 2 000 HP, so an extra 20 points of guard share is a slower den
  ## programme and a shorter game. Leaving `turtle` at the cog's own number
  ## keeps the default doctrine at its measured best AND keeps the whole
  ## 40-point spread that gives `opening` its teeth.
  ##
  ## The cog's own `guard_ratio` still dominates: the bias is applied to it and
  ## CLAMPED to 0..100, so `guard_ratio: 0` is all-soldier and
  ## `guard_ratio: 100` is all-guard in EVERY opening.
  case opening
  of opTurtle: 0
  of opSoldierViperAggro: -20
  of opScoutZombiePull: 0

func effectiveGuardRatio*(s: Side): int =
  max(0, min(100, s.doctrine.guardRatio +
                  openingGuardBias(s.doctrine.opening)))

func wantsGuardNext*(w: World, s: Side): bool =
  ## `attackMix()`: the percentage of the ATTACKER budget that goes to GUARDs
  ## rather than SOLDIERs. Deterministic and census-driven rather than random,
  ## so a doctrine's mix is reproducible: build a guard when the guard share
  ## of the standing attacker mix is below the effective ratio.
  if w.brokenChassis: return false        ## the negative control never guards
  let guards = s.counts[rtGuard]
  let soldiers = s.counts[rtSoldier]
  let total = guards + soldiers
  let ratio = effectiveGuardRatio(s)
  if s.doctrine.guardRatio >= 100: return true
  if s.doctrine.guardRatio <= 0: return false
  if ratio >= 100: return true
  if ratio <= 0: return false
  if total == 0: return ratio >= 50
  (guards * 100) < (ratio * total)

func canAfford*(w: World, s: Side, kind: RobotType): bool =
  w.teamParts(s.team) - s.partsCommitted >= float64(kind.partCost())

proc commit*(s: Side, kind: RobotType) =
  s.partsCommitted += float64(kind.partCost())

func buildQueue*(w: World, s: Side): seq[RobotType] =
  ## `queue()`: what the stockpile buys first when it cannot buy everything.
  ## The list is in priority order and the archon takes the first entry it
  ## can afford, so a faction is never idle with parts in the bank.
  let d = s.doctrine
  var wantTurret = s.counts[rtTurret] + s.counts[rtTtm] < d.turretCount
  var wantScout = s.counts[rtScout] < scoutTarget(w, s)
  let wantAttacker = s.attackers < attackerTarget(w, s)
  let attackerFloor =
    s.attackers < AttackersPerArchonFloor * max(1, s.archons.len)
  ## THE FLOOR FIRST, at every knob setting: an attacker before anything else
  ## while the faction is under three per archon.
  ##
  ## ONE EXCEPTION, and it is measured rather than assumed: when the
  ## stockpile can afford a TURRET **and still buy an attacker afterwards**
  ## (130 + 30 = 160 parts), the turret deficit goes first. Without it a
  ## faction in a real war never spends `turret_count` at all — measured on
  ## `river` with `turret_count: 3`, ZERO turrets in 900 rounds, because
  ## attackers die faster than a receding target fills — and a knob that
  ## cannot be spent is a knob without teeth.
  if attackerFloor:
    if wantTurret and
        w.teamParts(s.team) - s.partsCommitted >=
          float64(rtTurret.partCost() + rtSoldier.partCost()):
      result.add(rtTurret)
    if wantsGuardNext(w, s): result.add(rtGuard)
    result.add(rtSoldier)
    result.add(rtGuard)
    return
  case d.partsPriority
  of ppTurrets:
    if wantTurret: result.add(rtTurret)
    if wantScout: result.add(rtScout)
    if wantAttacker:
      if wantsGuardNext(w, s): result.add(rtGuard) else: result.add(rtSoldier)
  of ppVipers:
    if s.counts[rtViper] * 3 <= s.attackers: result.add(rtViper)
    if wantScout: result.add(rtScout)
    if wantAttacker:
      if wantsGuardNext(w, s): result.add(rtGuard) else: result.add(rtSoldier)
    if wantTurret: result.add(rtTurret)
  of ppUnits:
    if wantScout and s.counts[rtScout] == 0: result.add(rtScout)
    ## A VIPER PER SIX SOLDIERS FOR THE AGGRO OPENING, AND IT GOES FIRST WHEN
    ## THE STOCKPILE CAN AFFORD IT PLUS AN ATTACKER. Measured: as a TAIL entry
    ## the viper was never reached at all -- `buildSomething` takes the first
    ## AFFORDABLE entry and a 30-part soldier is always affordable, so a
    ## `soldier_viper_aggro` faction built ZERO vipers in 800 rounds and the
    ## opening's headline unit did not exist. 120 + 30 = 150 parts is the same
    ## "and still buy an attacker afterwards" gate the turret deficit uses.
    if d.opening == opSoldierViperAggro and
        s.counts[rtViper] * 6 <= s.counts[rtSoldier] and
        w.teamParts(s.team) - s.partsCommitted >=
          float64(rtViper.partCost() + rtSoldier.partCost()):
      result.add(rtViper)
    ## A TURRET DEFICIT OUTRANKS A FURTHER ATTACKER once the unconditional
    ## floor is met: 130 parts and 25 frozen archon turns is a real
    ## commitment, and a faction that never gets there because its attacker
    ## target keeps receding never spends the knob at all (measured on
    ## `river`: without this line a `turret_count: 3` doctrine built ZERO
    ## turrets in 900 rounds, because attackers die faster than the target
    ## fills).
    if wantTurret: result.add(rtTurret)
    if wantAttacker:
      if wantsGuardNext(w, s): result.add(rtGuard) else: result.add(rtSoldier)
    if wantScout: result.add(rtScout)
  ## A viper per six soldiers once parts allow, for the aggro opening — and a
  ## soldier as the always-affordable tail, so a stockpile above 200 always
  ## has somewhere to go.
  if w.teamParts(s.team) - s.partsCommitted > 200.0:
    if wantsGuardNext(w, s): result.add(rtGuard)
    result.add(rtSoldier)
  result.add(rtSoldier)
