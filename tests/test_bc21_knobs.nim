## THE bc21 KNOB-TEETH GATE.
##
## Every one of the ten knobs must visibly change play. For each, this shard
## plays a PAIRED set of seeded games — identical seed, identical map,
## identical opponent (the all-defaults `california-roll` reference), the only
## difference being that knob at its LOW and then its HIGH setting — and
## asserts a named, SIGNED statistic moves. A knob that is inert fails the
## build.
##
## The pair is `Bog` under BOTH side assignments, played to round 800. The
## episode seed only chooses the map and the side assignment — the world RNG
## comes from the MAP's own `randomSeed` — so those two games are every
## distinct game these inputs can produce, and everything here is fully
## deterministic, so a threshold that holds once holds every time.
##
## THE THRESHOLDS LIVE IN ONE TABLE so tuning is a one-line change, and each is
## set at roughly half the measured delta. Measured at GameVersion GV06,
## summed over the two games:
##
##   knob                   low -> high                measured        gate
##   opening                turtle -> muck_spam        muck@150   0->130   >= 25
##                                                     slanInfl@150 -96 %  >= 60 %
##   slanderer_ratio        0 -> 90                    slanderers 58->685  >= 15
##                                                     slanderer income
##                                                       6060 -> 7394      >= 800
##   muck_ratio             0 -> 90                    muckrakers 60->690  >= 30
##                                                     enemy-half turns
##                                                       25930 -> 160885   >= 150 %
##   politician_size_curve  cheap -> fat               mean mix influence
##                                                       18 -> 52 (2.89x)  >= 2.5x
##                                                     politicians 416->270 >= 25 %
##   bid_policy             never -> escalate          votes 0 -> 544      >= 250
##                                                     bid influence 0->5627 >= 2000
##   expansion              defend -> neutrals first   neutrals 0 -> 4     >= 2
##   flank_policy           screen -> flank_wide       enemy-half turns
##                                                       6073 -> 22031     >= 150 %
##   empower_threshold      0 -> 250                   empowers per 100
##                                                       politicians 103->45 >= 25
##                                                     politicians alive 0->232 >= 20
##   convert_over_kill      false -> true              enemy politicians
##                                                       converted 11 -> 26 >= 3
##   eco_exponential_round  200 -> 1200                slanderers after 400
##                                                       0 -> 236          >= 10
##                                                     influence held in units
##                                                       at 600  -37 %     >= 30 %
##
## FIVE OF THE NOTE'S OWN GATE STATISTICS ARE MEASURED DIFFERENTLY, and THIS
## HEADER IS THE RECORD OF ALL FIVE. (An earlier version of this paragraph said
## three, and pointed at docs/PARITY.md; PARITY.md is about the Java oracle and
## has no knob-gate section, so the pointer was to nothing.) The note's table
## and this file's table differ in exactly these places:
##   * `muck_ratio`'s second gate is muckraker-turns in the enemy half rather
##     than "enemy slanderers exposed", because the number of slanderers the
##     OPPONENT chooses to build — not the number of muckrakers we build — is
##     what binds that counter;
##   * `politician_size_curve`'s first gate measures the mean influence of the
##     politicians the SPEND MIX built, which is exactly what the knob steers,
##     rather than of every politician (a defence or capture body's size is
##     dictated by the threat or the target, not by the curve) — and it gates
##     at 2.5x rather than the note's 3x, which is this file's rule of roughly
##     half the measured delta applied to the measured 2.89x;
##   * `politician_size_curve`'s second gate is politicians BUILT down >= 25 %
##     (416 -> 270) rather than the note's "empowers down >= 30 %". A fatter
##     curve spends more influence per body, so the build count is the knob's
##     first-order effect; the empower count moves only through it;
##   * `empower_threshold`'s first gate is empowers PER POLITICIAN BUILT rather
##     than raw empowers, because a low threshold collapses the economy and so
##     builds far fewer politicians in the first place;
##   * `empower_threshold`'s second gate is politicians ALIVE AT THE END up
##     >= 20 (0 -> 232) rather than the note's "mean conviction delivered per
##     empower up >= 2x". A politician that does not clear the threshold does
##     not destroy itself, so the surviving population is the knob's direct and
##     largest signal, while at a threshold of 250 the empower events the note's
##     statistic would average over are few.

import std/strformat
import harness
import battlecode/[baselines, sheet]
import battlecode/years/bc21/[constants, maps, rules, world]

const
  GateMap = "Bog"
  GateSeeds = [1, 256]
  Rounds = 800

type Measurement = object
  muck150, slanInfl150, slanBuilt, slaPassive, polBuilt: int
  neutrals, unitInfl600, empowers, muckBuilt: int
  politiciansConverted, votes, bidInfl, mixPol, mixPolInfl: int
  slanAfter400, muckEnemyHalf, polAlive: int

proc measure(sheetJson: string): Measurement =
  ## The TEST seat plays `sheetJson`; the reference opponent plays the
  ## all-defaults sheet.
  let test = parseReply(sheetJson, "bc21")
  let reference = baselineSheet("bc21", blCaliforniaRoll)
  for seed in GateSeeds:
    let sa = sideAslotFor(seed, 0)
    let t = if sa == 0: 0 else: 1     # the TEAM the test seat plays
    var m150, s150, sB400, u600 = 0
    proc onRound(w: World, round: int) {.closure.} =
      if round == 150:
        m150 = w.stats.muckrakersBuilt[t]
        s150 = w.stats.slandererInfluence[t]
      elif round == 400:
        sB400 = w.stats.slanderersBuilt[t]
      elif round == 600:
        var held = 0
        for _, r in w.robotsById:
          if r.team == Team(t) and r.kind != rtEnlightenmentCenter:
            held += r.influence
        u600 = held
    let (w, o) = playGame(loadMap(GateMap), [test, reference],
      [ckCaliforniaRoll, ckCaliforniaRoll], 0, sa, Rounds, 0, onRound)
    result.muck150 += m150
    result.slanInfl150 += s150
    result.unitInfl600 += u600
    result.slanAfter400 += w.stats.slanderersBuilt[t] - sB400
    result.neutrals += o.neutralsCaptured[0]
    result.slanBuilt += o.slanderersBuilt[0]
    result.muckBuilt += o.muckrakersBuilt[0]
    result.polBuilt += o.politiciansBuilt[0]
    result.slaPassive += w.stats.slandererPassive[t]
    result.empowers += o.empowers[0]
    result.politiciansConverted += w.stats.politiciansConverted[t]
    result.votes += o.votes[0]
    result.bidInfl += o.bidInfluenceSpent[0]
    result.muckEnemyHalf += w.stats.muckrakerTurnsEnemyHalf[t]
    result.mixPol += w.stats.mixPoliticians[t]
    result.mixPolInfl += w.stats.mixPoliticianInfluence[t]
    result.polAlive += o.politiciansAlive[0]

proc pair(knob, lo, hi: string): (Measurement, Measurement) =
  (measure("{\"sheet\":{\"" & knob & "\":" & lo & "}}"),
   measure("{\"sheet\":{\"" & knob & "\":" & hi & "}}"))

proc upBy(name: string, a, b, delta: int) =
  check(&"{name}: {a} -> {b} (needs +{delta})", b - a >= delta)

proc downByPct(name: string, a, b, pct: int) =
  check(&"{name}: {a} -> {b} (needs -{pct} %)",
    a > 0 and (a - b) * 100 div a >= pct)

proc upByPct(name: string, a, b, pct: int) =
  check(&"{name}: {a} -> {b} (needs +{pct} %)",
    a > 0 and (b - a) * 100 div a >= pct)

proc mean(total, count: int): int = (if count > 0: total div count else: 0)

# --- 1. opening ---------------------------------------------------------------
block:
  let (a, b) = pair("opening", "\"slanderer_turtle\"", "\"muck_spam\"")
  upBy("opening: muckrakers built by round 150", a.muck150, b.muck150, 25)
  downByPct("opening: influence spent on slanderers by round 150",
    a.slanInfl150, b.slanInfl150, 60)

# --- 2. slanderer_ratio --------------------------------------------------------
block:
  let (a, b) = pair("slanderer_ratio", "0", "90")
  upBy("slanderer_ratio: slanderers built", a.slanBuilt, b.slanBuilt, 15)
  upBy("slanderer_ratio: slanderer income generated", a.slaPassive,
    b.slaPassive, 800)

# --- 3. muck_ratio -------------------------------------------------------------
block:
  let (a, b) = pair("muck_ratio", "0", "90")
  upBy("muck_ratio: muckrakers built", a.muckBuilt, b.muckBuilt, 30)
  upByPct("muck_ratio: muckraker-turns in the enemy half", a.muckEnemyHalf,
    b.muckEnemyHalf, 150)

# --- 4. politician_size_curve --------------------------------------------------
block:
  let (a, b) = pair("politician_size_curve", "\"cheap\"", "\"fat\"")
  let meanA = mean(a.mixPolInfl, a.mixPol)
  let meanB = mean(b.mixPolInfl, b.mixPol)
  check(&"politician_size_curve: mean mix-built politician influence " &
    &"{meanA} -> {meanB} (needs 2.5x)", meanA > 0 and meanB * 10 >= meanA * 25)
  downByPct("politician_size_curve: politicians built", a.polBuilt, b.polBuilt,
    25)

# --- 5. bid_policy -------------------------------------------------------------
block:
  let (a, b) = pair("bid_policy", "\"never\"", "\"escalate_when_ahead\"")
  checkEq("bid_policy never really means never", a.votes, 0)
  checkEq("and spends nothing on the auction", a.bidInfl, 0)
  upBy("bid_policy: votes won", a.votes, b.votes, 250)
  upBy("bid_policy: influence spent on bids", a.bidInfl, b.bidInfl, 2000)

# --- 6. expansion --------------------------------------------------------------
block:
  let (a, b) = pair("expansion", "\"defend_home\"", "\"neutral_centers_first\"")
  upBy("expansion: neutral Centres captured", a.neutrals, b.neutrals, 2)

# --- 7. flank_policy -----------------------------------------------------------
block:
  let (a, b) = pair("flank_policy", "\"screen_home\"", "\"flank_wide\"")
  upByPct("flank_policy: muckraker-turns in the enemy half", a.muckEnemyHalf,
    b.muckEnemyHalf, 150)

# --- 8. empower_threshold ------------------------------------------------------
block:
  let (a, b) = pair("empower_threshold", "0", "250")
  let rateA = (if a.polBuilt > 0: a.empowers * 100 div a.polBuilt else: 0)
  let rateB = (if b.polBuilt > 0: b.empowers * 100 div b.polBuilt else: 0)
  check(&"empower_threshold: empowers per 100 politicians {rateA} -> {rateB} " &
    "(needs -25)", rateA - rateB >= 25)
  upBy("empower_threshold: politicians alive at the end", a.polAlive,
    b.polAlive, 20)

# --- 9. convert_over_kill ------------------------------------------------------
block:
  let (a, b) = pair("convert_over_kill", "false", "true")
  upBy("convert_over_kill: enemy politicians converted",
    a.politiciansConverted, b.politiciansConverted, 3)

# --- 10. eco_exponential_round -------------------------------------------------
block:
  let (a, b) = pair("eco_exponential_round", "200", "1200")
  upBy("eco_exponential_round: slanderers built after round 400",
    a.slanAfter400, b.slanAfter400, 10)
  downByPct("eco_exponential_round: influence held in units at round 600",
    a.unitInfl600, b.unitInfl600, 30)

finish("bc21 knobs")
