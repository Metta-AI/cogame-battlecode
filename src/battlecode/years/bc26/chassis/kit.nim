## Shared chassis scaffolding: per-robot memory, the clan's doctrine, and the
## DECISION BUDGET that replaces the engine's JVM bytecode limit.
##
## The engine meters a robot's turn in bytecodes through an instrumenting
## class loader. There is no JVM here, so every primitive step a bot takes —
## a sense, a BFS expansion, a candidate evaluation — is charged against
## `Robot.opsLeft` instead, and the robot ends its turn where it stands when
## the budget runs out. Bounded, machine-independent, deterministic, and a
## deliberate divergence (docs/RULES.md §Divergences).

import std/tables
import ../../../rng
import ../../../sheet
import ../constants, ../world

export sheet, constants, world, rng

type
  Brain* = ref object
    ## One robot's private memory. In Battlecode each robot gets its own
    ## class loader, so `static` fields are per robot — `rng` here is
    ## examplefuncsplayer's `new Random(6147)`, one per rat, not one per team.
    rng*: JavaRandom
    turnCount*: int
    ferry*: bool
    hasTarget*: bool
    target*: Loc
    knownMine*: Loc
    hasKnownMine*: bool

  Clan* = ref object
    team*: Team
    doctrine*: Doctrine
    brains*: Table[int, Brain]
    catsFed*: int
    hostilitiesOpened*: bool

proc newClan*(team: Team, doctrine: Doctrine): Clan =
  Clan(team: team, doctrine: doctrine, brains: initTable[int, Brain]())

proc brainFor*(clan: Clan, r: Robot): Brain =
  ## Lazily created, seeded 6147 exactly as `examplefuncsplayer` does, and
  ## keyed by robot id so a rat's memory follows it across its whole life.
  if r.id notin clan.brains:
    let b = Brain(rng: initJavaRandom(6147))
    ## The miner/skirmisher split is a pure function of the robot id and the
    ## `cheese_ferry_ratio` knob, so the same seed always produces the same
    ## roster (sheet knob site: `rat.nim` role assignment).
    let h = (uint32(r.id) * 2654435761'u32) mod 100'u32
    b.ferry = int(h) < int(clan.doctrine.cheeseFerryRatio * 100)
    clan.brains[r.id] = b
  clan.brains[r.id]

proc spend*(r: Robot, ops: int): bool {.discardable.} =
  ## Charge `ops` decision credits. False once the robot is out of budget;
  ## every loop in the chassis checks it and stops.
  if r.opsLeft <= 0: return false
  r.opsLeft -= ops
  r.opsLeft > 0

proc hostilitiesOpen*(clan: Clan, w: World): bool =
  ## Knob site for `backstab_policy`. With hostilities closed the enemy is
  ## simply not a candidate for bite / ratnap / throw / rat-trap, which is
  ## the whole of the cooperate-or-betray decision.
  if not w.isCooperation:
    ## Once the world has flipped there is nothing left to protect: every
    ## doctrine, `never` included, fights back. `never` only ever promised
    ## not to be the one who starts it.
    return true
  case clan.doctrine.backstabPolicy
  of bpNever, bpRetaliateOnly:
    false
  of bpOnFirstContact:
    true
  of bpAtRoundN:
    w.currentRound >= clan.doctrine.backstabRound
  of bpWhenAhead:
    let me = ord(clan.team)
    let them = 1 - me
    w.currentRound >= 200 and
      w.teamInfo.damageToCats[me] > w.teamInfo.damageToCats[them] and
      w.teamInfo.numRatKings[me] >= w.teamInfo.numRatKings[them]
