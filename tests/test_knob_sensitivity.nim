## THE KNOB-TEETH GATE.
##
## `backstab_policy` is not allowed to be the only knob that changes the
## match. For each of the other ten knobs this shard plays a paired set of
## seeded games — identical seed, map and opponent, the two clans identical
## except that knob at its LOW and HIGH setting — and asserts a named, signed
## statistic moves. A knob that is inert fails the build.
##
## The thresholds live in ONE table so tuning is a one-line change. They are
## set at roughly half the measured delta at GameVersion GV01, so a real
## regression trips them and ordinary drift does not:
##
##   knob                     low -> high            measured        gate
##   spawn_curve              lean -> swarm          rats 40 -> 162  +25 %
##   king_count_target        1 -> 5                 kings 0 -> 8    +2
##   cheese_ferry_ratio       0.1 -> 0.9             chz 2590 -> 8470 +20 %
##   cat_trap_budget          0 -> 80                traps 0 -> 34   +12
##   rat_trap_budget          0 -> 120               traps 0 -> 106  +20
##   dirt_wall_policy         none -> king_shell     dirt 0 -> 58    +20
##   cat_engagement           avoid -> hunt          cat 0 -> 3740   +30 %
##   throw_rats_to_feed_cats  false -> true          fed 0 -> 40     >= 1
##   chassis                  scaffold -> awu        wins 2/4        >= 4 of 6

import std/strutils
import harness
import battlecode/sheet
import battlecode/years/bc26/[maps, rules]

const
  Maps = ["DefaultSmall", "closeup", "cheesefarm"]
  Seeds = [1, 2]
  Rounds = 800

type Totals = object
  rats, kings, cheese, traps, dirt, catDamage, catsFed, wins: array[2, int]

proc pairedGames(lowJson, highJson: string): Totals =
  ## The LOW setting takes seat 0 and the HIGH setting seat 1, on the same
  ## maps and the same seeds, so the only difference between the two clans is
  ## the knob under test.
  let sheets = [parseReply(lowJson), parseReply(highJson)]
  for mapName in Maps:
    for seed in Seeds:
      let (w, o) = playGame(loadMap(mapName), sheets, 0, 0, Rounds, 0)
      for slot in 0 .. 1:
        result.rats[slot] += o.ratsBuilt[slot]
        result.kings[slot] += o.kingsBuilt[slot]
        result.cheese[slot] += o.cheeseTransferred[slot]
        result.traps[slot] += o.trapsPlaced[slot]
        result.dirt[slot] += o.dirtPlaced[slot]
        result.catDamage[slot] += o.catDamage[slot]
        result.catsFed[slot] += o.catsFed[slot]
      if o.winnerSlot >= 0: result.wins[o.winnerSlot] += 1

proc pct(name: string, values: array[2, int], minPct: int) =
  ## A signed RELATIVE delta: the high setting must beat the low one by at
  ## least `minPct` percent.
  let low = values[0]
  let high = values[1]
  let ok = if low == 0: high > 0 else: high * 100 >= low * (100 + minPct)
  check(name & " (" & $low & " -> " & $high & ", needs +" & $minPct & "%)", ok)

proc abs(name: string, values: array[2, int], minDelta: int) =
  check(name & " (" & $values[0] & " -> " & $values[1] & ", needs +" &
    $minDelta & ")", values[1] - values[0] >= minDelta)

block:
  let t = pairedGames("""{"sheet":{"spawn_curve":"lean"}}""",
                      """{"sheet":{"spawn_curve":"swarm"}}""")
  pct("spawn_curve lean->swarm raises rats built", t.rats, 25)

block:
  let t = pairedGames("""{"sheet":{"king_count_target":1}}""",
                      """{"sheet":{"king_count_target":5}}""")
  abs("king_count_target 1->5 raises kings built", t.kings, 2)

block:
  let t = pairedGames("""{"sheet":{"cheese_ferry_ratio":0.1}}""",
                      """{"sheet":{"cheese_ferry_ratio":0.9}}""")
  pct("cheese_ferry_ratio 0.1->0.9 raises cheese delivered", t.cheese, 20)

block:
  ## Rat traps are zeroed on both sides so the delta is CAT traps only.
  let t = pairedGames(
    """{"sheet":{"cat_trap_budget":0,"rat_trap_budget":0}}""",
    """{"sheet":{"cat_trap_budget":80,"rat_trap_budget":0}}""")
  abs("cat_trap_budget 0->80 raises traps placed", t.traps, 12)

block:
  ## Cat traps are zeroed and hostilities are opened so rat traps are worth
  ## laying; the delta is RAT traps only.
  let t = pairedGames(
    """{"sheet":{"rat_trap_budget":0,"cat_trap_budget":0,"backstab_policy":"on_first_contact"}}""",
    """{"sheet":{"rat_trap_budget":120,"cat_trap_budget":0,"backstab_policy":"on_first_contact"}}""")
  abs("rat_trap_budget 0->120 raises traps placed", t.traps, 20)

block:
  let t = pairedGames("""{"sheet":{"dirt_wall_policy":"none"}}""",
                      """{"sheet":{"dirt_wall_policy":"king_shell"}}""")
  abs("dirt_wall_policy none->king_shell raises dirt placed", t.dirt, 20)
  checkEq("and `none` really places no dirt at all", t.dirt[0], 0)

block:
  let t = pairedGames("""{"sheet":{"cat_engagement":"avoid"}}""",
                      """{"sheet":{"cat_engagement":"hunt"}}""")
  pct("cat_engagement avoid->hunt raises cat damage", t.catDamage, 30)
  checkEq("and `avoid` really does no cat damage at all", t.catDamage[0], 0)

block:
  let t = pairedGames(
    """{"sheet":{"cat_engagement":"feed","throw_rats_to_feed_cats":false}}""",
    """{"sheet":{"cat_engagement":"feed","throw_rats_to_feed_cats":true}}""")
  check("throw_rats_to_feed_cats false->true feeds at least one cat (" &
    $t.catsFed[0] & " -> " & $t.catsFed[1] & ")", t.catsFed[1] >= 1)
  checkEq("and `false` never feeds one", t.catsFed[0], 0)

block:
  ## `chassis` is the only knob whose teeth are measured in WINS: the
  ## distilled awubot against the ported example bot.
  let t = pairedGames("""{"sheet":{"chassis":"scaffold"}}""",
                      """{"sheet":{"chassis":"awu"}}""")
  let games = Maps.len * Seeds.len
  check("chassis scaffold->awu: awu wins at least 4 of " & $games & " (" &
    $t.wins[0] & "/" & $t.wins[1] & ")", t.wins[1] >= 4)
  check("and dominates on cheese delivered (" & $t.cheese[0] & " -> " &
    $t.cheese[1] & ")", t.cheese[1] > t.cheese[0])
  check("on cat damage (" & $t.catDamage[0] & " -> " & $t.catDamage[1] & ")",
    t.catDamage[1] > t.catDamage[0])
  check("and on rats built (" & $t.rats[0] & " -> " & $t.rats[1] & ")",
    t.rats[1] > t.rats[0])

finish("test_knob_sensitivity")
