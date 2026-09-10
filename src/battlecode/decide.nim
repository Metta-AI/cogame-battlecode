## The decision layer: ONE sealed, simultaneous doctrine turn per episode.
##
## Both seats are asked at the same moment and their two provider calls go out
## as ONE PARALLEL BATCH (`curly.makeRequests`, coworld-ctf's `decide.nim`
## shape) with the same deadline. Seats are never queried one after another.
##
## DEGRADE, NEVER HANG. Every wait is bounded: attempt 1 gets `attempt1Ms`,
## the single retry gets `retryMs`, and the whole phase is wrapped in a
## monotonic `doctrineBudgetMs` deadline. A provider throttle with no other
## candidate model skips the retry outright (it cannot land). On a second
## failure the seat plays its scripted doctrine and a `doctrine_fallback`
## event names the cause. No failure mode leaves a seat without a doctrine.

import std/[json, monotimes, strutils, times]
import curly
import sim_types, sheet, baselines, llm, match
import years/dispatch
from years/bc25/patterns as pat25 import
  patternRows, pkMoneyTower, pkPaintTower, pkDefenseTower, pkResource

type
  SeatPolicy* = object
    ## What one seat registered as. A seat that registers with neither field
    ## — or never registers at all — is `awu`.
    isLlm*: bool
    prompt*: string
    scripted*: string
      ## The raw `PLAYER_SCRIPTED` value. Resolved to a `Baseline` PER YEAR at
      ## episode time by `baselineForSeat`, because `bowl-of-chowder` means
      ## nothing to bc26 and `awu` means nothing to bc20. Storing a parsed
      ## `Baseline` on the seat would be resolving it before the year is known.
    label*: string
    registered*: bool

  DecisionResult* = object
    sheets*: array[2, Sheet]
    decisionMs*: array[2, int]
    fallback*: array[2, string]
    fallbackDetail*: array[2, string]
      ## The provider's own last words for this seat, one line, capped at
      ## `MaxFallbackDetailRunes`. Recorded in the replay beside the one-word
      ## cause so a fallback can be read after the fact.
    briefs*: array[2, string]
      ## The prompt payload composed for this seat, verbatim — the "observation"
      ## of a game whose decisions are taken server-side. Recorded in the replay.
    policyKind*: array[2, string]
    events*: seq[MatchEvent]

proc baselineForSeat*(year: string, seat: SeatPolicy): Baseline =
  if seat.scripted.len > 0: baselineFor(year, seat.scripted)
  else: defaultBaselineFor(year)

proc chassisForSeat*(year: string, seat: SeatPolicy): ScriptedChassis =
  ## D1: the chassis is fixed by the OPERATOR. A scripted seat drives the
  ## chassis its `PLAYER_SCRIPTED` names; an LLM seat drives the year's fixed
  ## champion chassis — `bowl-of-chowder` on bc20, `california-roll` on bc21,
  ## `gone-sharkin` on bc24.
  if seat.isLlm: strongChassisFor(year)
  else: baselineChassis(baselineForSeat(year, seat))

proc chassisNameFor*(year: string, seat: SeatPolicy, sheet: Sheet): string =
  case yearIdOf(year)
  of yBc20, yBc21, yBc22, yBc24, yBc25, yBc23, yBc16, yBc19:
    (if seat.isLlm: $strongChassisFor(year)
     else: baselineName(baselineForSeat(year, seat)))
  of yBc26: $sheet.doctrine.chassis

const SystemPreamble* = """
You command a clan of robot rats in Battlecode 2026, "Uneasy Alliances": a
two-clan grid war on a symmetric map, 2000 rounds a game, best of three.

You do not move a single rat. Before the war you write ONE DOCTRINE — a JSON
sheet of named knobs — and a deterministic simulation then plays the whole
match from it while you watch.

THE WORLD
- Each clan starts with one 3x3 RAT KING (600 hp). A king eats 2 cheese every
  round and loses 10 hp a round when the bank is empty. Losing every rat king
  loses the game outright.
- Baby rats (100 hp) forage cheese from mines, bite, dig and place dirt, lay
  rat traps and cat traps, ratnap and throw each other. Four rats in a ring
  can be crowned into a new king for 50 cheese; five kings maximum, dropping
  to two after round 1200.
- Cheese mines spawn 20 cheese on symmetric pairs of tiles. Income is roughly
  half a cheese per round per clan: an over-built roster starves its own
  crowns about sixty rounds later.
- Neutral NPC CATS (4000 hp) patrol waypoints, chase rats, pounce and scratch
  for 20. They are the shared enemy while the alliance holds.

THE MOTIVE
Both clans start in COOPERATION and the points formula is cat-damage
weighted. The moment either clan takes a hostile action against the other —
a bite, a ratnap, a throw, or the victim walking into your rat trap — the
world flips to BACKSTAB and the formula reweights toward king survival.
  cooperation: points = int(50 * cat-damage share + 30 * king share + 20 * cheese share)
  backstab:    points = int(30 * cat-damage share + 50 * king share + 20 * cheese share)
Winning a game is worth 100; points are worth at most 100 and the two clans'
points sum to about 100. So the game bonus dominates, and killing every enemy
king wins outright. Cat traps cannot be placed after a backstab unless you
were the victim, and then only for 100 rounds.

YOUR REPLY
Reply with ONE JSON object and NOTHING else. Your reply must begin with '{'.
{"sheet": {...knobs...}, "notes": "<=280 chars", "motto": "<=48 chars"}

THE KNOBS (unknown key, wrong type or out-of-range value = that field's
default; you cannot forfeit by answering badly, only by answering weakly):
  backstab_policy        "never" | "when_ahead" | "at_round_N"
                         | "on_first_contact" | "retaliate_only" default "retaliate_only"
  backstab_round         1..2000 (read only for at_round_N)      default 600
  cat_engagement         "avoid" | "opportunistic" | "hunt" | "feed"
                                                                  default "opportunistic"
  cat_trap_budget        0..200                                   default 40
  rat_trap_budget        0..200                                   default 60
  spawn_curve            "lean" | "steady" | "swarm"              default "steady"
  cheese_ferry_ratio     0.0..1.0 (miners vs skirmishers)         default 0.5
  king_count_target      1..5                                     default 3
  dirt_wall_policy       "none" | "king_shell" | "choke"          default "king_shell"
  throw_rats_to_feed_cats  true | false                           default false

Your clan is driven by the `awu` chassis. That is not yours to choose: there
is no `chassis` knob, and a reply that sends one has it ignored.
"""

const Bc20Preamble* = """
You command a clan in Battlecode 2020 "Soup": a two-clan grid war on a
symmetric map where THE WATER RISES EVERY ROUND, 1500 rounds a game, best of
three.

You do not move a single robot. Before the war you write ONE DOCTRINE — a JSON
sheet of ten named knobs — and a deterministic simulation then plays the whole
match from it while you watch.

THE CLOCK IS THE WATER
- The water level rises on a fixed curve and floods outward ONE RING PER ROUND
  from every already-flooded tile whose neighbour sits below the level.
  Anything that is not a delivery drone dies on a flooding tile.
- Your HQ starts at a low elevation and CANNOT BE RAISED: dirt dropped on a
  building buries it. The only thing that keeps an HQ dry is a ring of eight
  adjacent tiles the water can never cross. An HQ that is never walled drowns
  on a schedule.

THE WORLD
- MINERS (70 soup) mine SOUP (7 per action, carry 100) and deposit it at the HQ
  or a REFINERY (200), which refines up to 20 per round into the team pool.
- DESIGN SCHOOLS (150) build LANDSCAPERS (150), which dig and dump dirt: raise
  the ground into a lattice, wall the HQ in, or bury the enemy HQ under FIFTY
  dirt. A landscaper carries 25.
- FULFILLMENT CENTERS (150) build DELIVERY DRONES (150), which pick up any unit
  within r^2 <= 3 — including enemy landscapers — and drop them in the water.
- VAPORATORS (500) print 2 soup a round and scrub pollution. NET GUNS (250)
  shoot drones within r^2 <= 15; so does the HQ.
- Pollution slows every action and shrinks every sensor. Cows pollute heavily.
- The only global channel is a blockchain: seven ints a message, seven messages
  a round, paid for in soup, and BOTH TEAMS READ EVERY BLOCK.

HOW A GAME ENDS
Round 1499, or when an HQ is buried or drowned. The ladder, first hit wins:
HQ destroyed; more robots alive (buildings included); greater net worth; more
transactions minted; highest living robot id; coin flip.
  points = int(60 * HQ-survival share + 25 * unit share + 15 * net-worth share)
Winning a game is worth 100 and points are worth at most 100, so the game bonus
dominates: lose your HQ, lose the game.

YOUR REPLY
Reply with ONE JSON object and NOTHING else. Your reply must begin with '{'.
{"sheet": {...knobs...}, "notes": "<=280 chars", "motto": "<=48 chars"}

THE KNOBS (unknown key, wrong type or out-of-range value = that field's
default; you cannot forfeit by answering badly, only by answering weakly):
  opening                 "rush" | "lattice" | "passive_lattice" | "turtle"
                                                          default "passive_lattice"
  terraform_start_round   1..1500                          default 300
  lattice_radius          2..12                            default 6
  landscaper_count_curve  "lean" | "steady" | "swarm"      default "steady"
  miner_count_curve       "lean" | "steady" | "swarm"      default "steady"
  vaporator_budget        0..6                             default 2
  drone_role              "harass" | "wall" | "buster" | "carry_landscapers"
                                                          default "harass"
  net_gun_ring            0..6                             default 2
  rush_trigger            0..1500 (0 = never)              default 0
  wall_hq_round           0..1500 (0 = never)              default 250
"""

const Bc21Preamble* = """
You command a party in Battlecode 2021 "Campaign": a two-clan grid war on a
symmetric map where EVERY ROUND AUCTIONS ONE CITIZEN'S VOTE, 1500 rounds a
game, best of three.

You do not move a single robot. Before the war you write ONE DOCTRINE - a JSON
sheet of ten named knobs - and a deterministic simulation then plays the whole
match from it while you watch.

THE CLOCK IS THE ELECTION
- Every round each Enlightenment Center may bid influence. The single highest
  bidder IN THE GAME wins the vote for its team and pays its bid; the other
  team's top bidder pays ceil(bid/2) FOR NOTHING. Equal top bids: nobody wins,
  both pay half. At round 1500 the team with more votes wins.
- A team that loses EVERY robot loses immediately, at any round.

INFLUENCE IS THE ONLY RESOURCE, AND IT IS NOT A POOL
It sits inside each Enlightenment Center and does three incompatible jobs: it
buys units, it buys votes, and it is what an enemy politician steals when it
converts your Center. Each Center earns ceil(0.2*sqrt(round)) per round (about
8500 over a whole game) on top of its starting 150.

THE TRIANGLE
- SLANDERERS are the multiplier: one built for x influence pays its parent
  Center floor(x*(1/50 + 0.03*e^(-0.001x))) per round for its first 51 rounds
  - a ~2.35x return for x in 21..130 - and at 300 rounds old silently becomes
  a politician. It cannot act and dies to a single muckraker.
- MUCKRAKERS cost 1 influence, see furthest, and EXPOSE enemy slanderers: the
  slanderer dies and your team gets +0.001 x (that slanderer's influence) on
  every speech for 50 rounds.
- POLITICIANS are walking bombs. Empowering splits (conviction - 10) equally
  among EVERY other robot in the chosen radius (r^2 <= 9) - healing friends,
  feeding friendly Centers, converting or killing everything else - and then
  the politician dies. A Center with conviction c is captured by a politician
  of c + 11.

HOW A GAME ENDS
Round 1500, or the moment a team loses every robot. The ladder, first hit wins:
one team annihilated; more votes; more Enlightenment Centers; greater total
influence; coin flip (drawn from the map's own seed, not the wall clock).
  points = int(40*survival + 35*vote share + 15*centre share + 10*influence share)
Winning a game is worth 100 and points are worth at most 100, so the game bonus
dominates: lose the election, lose the match.

YOUR REPLY
Reply with ONE JSON object and NOTHING else. Your reply must begin with '{'.
{"sheet": {...knobs...}, "notes": "<=280 chars", "motto": "<=48 chars"}

THE KNOBS (unknown key, wrong type or out-of-range value = that field's
default; you cannot forfeit by answering badly, only by answering weakly):
  opening                "muck_spam" | "slanderer_turtle" | "balanced"
                                                          default "balanced"
  slanderer_ratio        0..100 (% of post-opening spend) default 45
  muck_ratio             0..100 (% of post-opening spend) default 25
  politician_size_curve  "cheap" | "ramp" | "fat"         default "ramp"
  bid_policy             "never" | "fixed" | "proportional"
                         | "escalate_when_ahead"          default "proportional"
  expansion              "neutral_centers_first" | "defend_home"
                                                default "neutral_centers_first"
  flank_policy           "screen_home" | "hunt_slanderers" | "flank_wide"
                                                   default "hunt_slanderers"
  empower_threshold      0..300 (percent)                 default 60
  convert_over_kill      true | false                     default true
  eco_exponential_round  1..1500                          default 700

Politicians take 100 - slanderer_ratio - muck_ratio. If the two sum above 100
they are renormalised. Your party is driven by the `california-roll` chassis.
That is not yours to choose: there is no `chassis` knob, and a reply that sends
one has it ignored.
"""

const Bc24Preamble* = """
You command a flock of FIFTY IDENTICAL DUCKS in Battlecode 2024 "Breadwars": a
two-clan grid war on a symmetric map, 2000 rounds a game, best of three.

You do not move a single duck. Before the war you write ONE DOCTRINE - a JSON
sheet of ten named knobs - and a deterministic simulation then plays the whole
match from it while you watch.

THE CLOCK IS THE DAM
- For the first 200 rounds an impassable dam splits the map and NOBODY CAN
  ATTACK. Ducks spawn, walk crumbs off the floor, dig water, fill water, lay
  invisible traps, and carry their own three flags to wherever they want them
  (minimum spacing 6 tiles - fail that at round 200 and all three teleport
  home).
- At round 200 the dam evaporates and the flag placements freeze.

WHAT ENDS A GAME EARLY: NOTHING BUT CAPTURING ALL THREE ENEMY FLAGS.
Otherwise round 2000 decides it on the ladder below.

EVERY DUCK IS THE SAME DUCK
1000 HP, vision r^2 20, attack and heal r^2 4, interact r^2 2. What makes them
different is what they DO: attacking, healing and building each earn experience
in that skill, six levels each, and AT LEVEL 4 A DUCK GAINS MASTERY - that
skill keeps climbing to 6 while the other two freeze at 3.
  damage by attack level  150 158 161 165 195 203 240   (+ATTACK upgrade: 210
                                                          220 225 231 273 284
                                                          336)
  heal by heal level       80  82  84  86  88  92 100   (+HEALING: 130 134 137
                                                          139 143 150 163)
A duck that dies goes to JAIL for 25 rounds, comes back at full health at a
spawn zone, and loses experience in its own best skill on the way in.

CRUMBS ARE THE ONLY RESOURCE AND THEY ARE GLOBAL PER TEAM
400 to start, 10 a round for free, whatever your ducks walk over, and 30 for
every kill made while standing on ENEMY ground. They buy digging (20), filling
(30), stun and water traps (100) and explosive traps (200) - and nothing else,
because ducks are free and infinite. Build level makes all of that cheaper.

THE THREE TRAPS ARE INVISIBLE TO THE ENEMY
  EXPLOSIVE 200 crumbs  750 damage to everything in r^2 <= 4 that walks onto
                        it; 200 in r^2 <= 2 if it is dug, filled or built on
  STUN      100 crumbs  sets enemy movement AND action cooldowns to 40 inside
                        r^2 <= 13
  WATER     100 crumbs  floods every free land tile inside r^2 <= 9

GLOBAL UPGRADES: one point a team at rounds 600, 1200 and 1800.
  attack   +60 base damage
  heal     +50 base heal
  capture  THEIR dropped flags take 25 rounds to fly home instead of 4, and
           YOUR flag-carry movement cooldown drops from 20 to 12

HOW A GAME ENDS
A team captures all three enemy flags, at any round - or round 2000 arrives and
the ladder decides it, first hit wins: more flags captured; higher total of all
skill levels over all fifty ducks (jailed included); more crumbs; coin flip
(drawn from the map's own seed, not the wall clock).
  points = int(60*flag share + 25*level share + 15*crumb share)
Winning a game is worth 100 and points are worth at most 100, so the game bonus
dominates: capture the flags or lose.

YOUR REPLY
Reply with ONE JSON object and NOTHING else. Your reply must begin with '{'.
{"sheet": {...knobs...}, "notes": "<=280 chars", "motto": "<=48 chars"}

THE KNOBS (unknown key, wrong type or out-of-range value = that field's
default; you cannot forfeit by answering badly, only by answering weakly):
  specialisation_split  "attack" | "heal" | "build" | "balanced"
                                                        default "balanced"
  flag_rush_round       201..1200                       default 450
  trap_budget           0..60 (% of crumb income)       default 30
  trap_placement        "choke" | "flag_ring" | "spawn_ring"
                                                        default "flag_ring"
  trap_mix              "stun" | "explosive" | "mixed"  default "mixed"
  heal_priority         "wounded_first" | "attackers_first" | "carrier_first"
                                                  default "wounded_first"
  water_dig_policy      "none" | "choke_dig" | "moat" | "fill_paths"
                                                      default "choke_dig"
  upgrade_order         3 distinct of "attack" | "heal" | "capture"
                                        default ["attack","heal","capture"]
  retreat_hp            100..900                        default 400
  flag_carry_escort     0..6                            default 2

No setting of any knob makes your flock idle: it always spawns, always takes
crumbs, always defends a flag it sees under threat, and always commits to an
enemy flag by flag_rush_round. Your flock is driven by the `gone-sharkin`
chassis. That is not yours to choose: there is no `chassis` knob, and a reply
that sends one has it ignored.
"""

const Bc25Preamble* = """
You command a clan of steampunk robot bunnies in Battlecode 2025 "Chromatic
Conflict": a two-clan paint war on a symmetric grid between 20x20 and 60x60,
2000 rounds a game, best of three.

You do not move a single robot. Before the war you write ONE DOCTRINE - a JSON
sheet of ten named knobs - and a deterministic simulation then plays the whole
match from it while you watch.

THE SCORE IS THE COLOUR OF THE MAP
Every tile is your colour, their colour, or bare. Paint 70% of
(width*height - walls) and you WIN ON THE SPOT. Destroy every enemy robot AND
tower and you win on the spot. Otherwise round 2000 decides it, and the FIRST
rung that is not tied wins: more squares painted, more towers alive, more
chips, more paint summed over all units, more robots alive, coin flip.

PAINT IS ALSO THE FUEL
Every robot carries a stash. Below 50% full every cooldown grows by
(100 - 2*percent) percent. At ZERO it cannot move, cannot act, and loses 20 HP
every single turn. Ending a turn costs 1 paint on bare ground and 2 on enemy
ground (DOUBLED for a mopper), plus 1 for every allied unit within radius^2 2 -
TOWERS COUNT - doubled again on enemy ground. Standing on your own colour is
free. So the whole economy is a loop: paint tiles, build towers on ruins,
towers mine paint, robots refill, paint more tiles.

THE THREE ROBOTS
  SOLDIER   250 HP, 200 paint cap, 250 chips + 200 tower-paint to build.
            Paints ONE tile within radius^2 9 for 5 paint, or hits an enemy
            TOWER for 50. Can never paint over enemy paint.
  SPLASHER  150 HP, 300 cap, 400 chips + 300 paint. Throws a 50-paint bomb up
            to radius^2 4 away: repaints everything within radius^2 4 of the
            centre and, inside radius^2 2, paints OVER ENEMY PAINT - the only
            way to take ground back at scale - and deals 100 to every enemy
            tower in the blast.
  MOPPER    50 HP, 100 cap, 300 chips + 100 paint. Erases one enemy tile and
            steals 10 paint from a robot standing on it; a mop swing takes 5
            paint from up to SIX enemies in a cardinal direction; and it is the
            ONLY unit that can hand paint to an ally.

TOWERS ARE THE MAP
You start with a money tower and a paint tower, both already LEVEL 2. Every
other tower must be PAINTED INTO EXISTENCE: a robot paints an exact 5x5
two-colour pattern around a ruin and completes it for 1000 chips, and the
pattern decides whether a MONEY, PAINT or DEFENSE tower rises. Towers spawn
robots, mine, and shoot ONE single-target shot AND one area shot every turn for
free. Upgrades cost 2500 then 5000. Nobody may hold more than 25.
  money   +20/30/40 chips a turn
  paint   +5/10/15 paint a turn INTO ITS OWN STASH (capped at 1000)
  defense +5/+7/+9 to the single-target damage of EVERY tower you own, and
          20/30/40 chips every time one of its shots connects

THE SPECIAL RESOURCE PATTERN
A different 5x5 shape, painted anywhere, paid for with 200 chips, that must
survive FIFTY ROUNDS UNDISTURBED and then gives +3 per turn to EVERY MINING
TOWER YOU OWN. One pattern with eight mining towers is +24 a turn forever; one
mopper walking through it at round 49 is 200 chips in the bin.

  points = int(55*area share + 20*tower share + 10*chip share
               + 10*paint share + 5*robot share)
Winning a game is worth 200 and points are worth at most 100, so the game bonus
dominates: own the colour or lose.

YOUR REPLY
Reply with ONE JSON object and NOTHING else. Your reply must begin with '{'.
{"sheet": {...knobs...}, "notes": "<=280 chars", "motto": "<=48 chars"}

THE KNOBS (unknown key, wrong type or out-of-range value = that field's
default; you cannot forfeit by answering badly, only by answering weakly):
  opening              "paint_eco" | "tower_rush" | "balanced"
                                                       default "balanced"
  unit_mix             {"soldier":0..100,"mopper":0..100,"splasher":0..100}
                       clamped to soldier>=30, mopper>=10, splasher>=10 and
                       normalised to 100      default {60,25,15}
  srp_priority         0..100 (% of chip income for resource patterns)
                                                       default 35
  tower_type_order     3 distinct of "money" | "paint" | "defense"
                                       default ["money","paint","defense"]
  ruin_claim_radius    4..20                            default 10
  defense_tower_chokes "never" | "late" | "early"       default "late"
  paint_reserve_floor  10..70 (% of capacity)           default 30
  mop_enemy_paint      0..100 (% of mopper turns)       default 40
  splash_targets       "towers" | "territory" | "mixed" default "mixed"
  upgrade_policy       "never" | "paint_first" | "money_first" | "defense_first"
                                                  default "money_first"

No setting of any knob makes your clan idle: it always builds robots whenever a
tower can pay for one, always paints the ground under a soldier that is not
already yours, always refills below paint_reserve_floor, always claims the
nearest ruin it can reach, and always keeps at least two moppers and one
splasher once the income allows it. Your clan is driven by the `spaark`
chassis. That is not yours to choose: there is no `chassis` knob, and a reply
that sends one has it ignored.
"""

const Bc23Preamble* = """
You command a faction in Battlecode 2023, "Tempest": a two-faction grid war on
a symmetric map between 20x20 and 60x60, 2000 rounds a game, best of three.

You do not move a single robot. Before the war you write ONE DOCTRINE — a JSON
sheet of twelve named knobs — and a deterministic simulation then plays the
whole match from it while you watch.

THE WORLD
- Each faction starts with 1 to 4 HEADQUARTERS. They are INDESTRUCTIBLE, they
  cannot move, each has its own stockpile, and each may take UP TO FIVE
  ACTIONS IN ONE TURN (action cooldown 2 against a limit of 10).
- Everything runs off two resources and a third you have to manufacture.
  Wells of ADAMANTIUM and MANA sit on the map; pour 600 kg of the OPPOSITE
  resource into a well and it becomes an ELIXIR well. Pour 1400 kg of a well's
  own type into it and its rate goes from 1 to 3.
- CARRIER (50 Ad, 150 hp, capacity 40): mines 1 kg per action from a well it
  stands on or beside, carries it home, and hands it to a headquarters. Its
  movement cooldown is floor(5 + 3*cargo/8), so a full carrier is half the
  speed of an empty one. It can THROW its whole cargo at an enemy within
  r2<=9 for floor(5*cargo/4) damage — up to 50 — and the cargo is destroyed
  whether it hits or not, off your team total.
- LAUNCHER (45 Mn, 200 hp): hits one square within r2<=16 for 20 damage, even
  a robot it cannot see. IT IS THE ONLY UNIT THAT DEALS REAL DAMAGE.
- AMPLIFIER (30 Ad + 15 Mn, 120 hp): lets friendly robots within r2<=20 WRITE
  the faction's 64-slot shared array.
- DESTABILIZER (200 Ex, 300 hp): marks a square; every tile within r2<=15 of
  it gives the ENEMY +10% cooldowns for five rounds and then deals 50 damage
  to whatever enemy stands there.
- BOOSTER (150 Ex, 400 hp): gives every ALLY within r2<=20 of where it stood
  -10% cooldowns for ten rounds, stacking three deep. The patch does not
  follow the booster.
- CLOUDS add 20% to every cooldown and collapse vision to r2<=4 — BOTH WAYS,
  so a robot in a cloud is also hidden. CURRENTS shove every robot standing on
  one, one square, at the end of every round.

HOW A GAME ENDS
- You win outright by holding 75% of the SKY ISLANDS. A headquarters builds an
  anchor (standard = 80 Ad + 80 Mn, 250 health; accelerating = 300 Ex, 750
  health), an EMPTY carrier takes it — an anchor weighs the carrier's whole
  capacity — walks onto an island tile and plants it.
- An anchor's health moves every round by (percent of the island's tiles YOUR
  robots occupy) minus (percent THEIRS occupy). At zero the island goes
  neutral. AN ANCHOR WITHOUT A GARRISON IS A LOAN, NOT A PURCHASE.
- If nobody conquers 75% by round 2000 the match is decided on a five-rung
  ladder, first difference wins: more islands held, then more anchors EVER
  placed, then more elixir, then more mana, then more adamantium, then a coin
  flip.
- THERE IS NO ELIMINATION. Headquarters cannot be destroyed and a faction with
  no robots at all plays on to round 2000.

YOUR DOCTRINE — twelve knobs, and nothing else
  opening                  "launcher_rush" | "carrier_eco" | "balanced"
                                                        default "balanced"
  launcher_ratio           20..80 (% of build decisions) default 45
  well_priority            "adamantium" | "mana" | "balanced"
                                                        default "balanced"
  elixir_tech              "never" | "mid" | "early"     default "mid"
  elixir_spend             "accelerating_anchors" | "boosters" | "destabilizers"
                                                        default "accelerating_anchors"
  anchor_round             1..1800                       default 400
  anchor_budget            0..100 (% of income)          default 35
  island_priority          "nearest" | "contested" | "safe"
                                                        default "nearest"
  amplifier_use            "never" | "one" | "escort"    default "one"
  destabilizer_use         "hold" | "defend" | "siege"   default "defend"
  retreat_on_launcher_loss "never" | "regroup" | "home"  default "regroup"
  carrier_throw            0..100                        default 25

No setting of any knob makes your faction idle: it always keeps at least three
carriers per headquarters mining and DEPOSITING, always builds a launcher when
mana allows and the census is short, always spends a headquarters' spare
actions, always answers an enemy launcher sensed near one of its own
headquarters, and always takes a lethal carrier throw inside r2<=9. Your
faction is driven by the `lemonade` chassis. That is not yours to choose:
there is no `chassis` knob, and a reply that sends one has it ignored.
"""

const Bc22Preamble* = """
You command a faction of robots in Battlecode 2022, "Mutation": a two-faction
grid war on a symmetric map between 20x20 and 60x60, 2000 rounds a game, best
of three.

You do not move a single robot. Before the war you write ONE DOCTRINE — a JSON
sheet of eleven named knobs — and a deterministic simulation then plays the
whole match from it while you watch.

THE WORLD
- Each faction starts with 1 to 4 ARCHONS (600 hp) and 200 lead. LOSE YOUR
  LAST ARCHON AND YOU LOSE THE GAME IMMEDIATELY.
- An archon builds MINERS (50 Pb), BUILDERS (40 Pb), SOLDIERS (75 Pb, 50 hp,
  3 damage at r2<=13) and SAGES (20 Au, 100 hp, 45 damage at r2<=25, one shot
  every twenty turns) in an adjacent square, and repairs a friendly droid for
  2/4/6 a turn within r2<=20.
- A BUILDER puts up LABORATORIES (180 Pb) and WATCHTOWERS (150 Pb) as
  PROTOTYPES at 80% health that can do nothing until the builder has repaired
  them to full — ten repairs for a laboratory, fifteen for a watchtower.
- Every square carries RUBBLE 0..100, and every cooldown a robot pays is
  floor((1 + rubble/10) * base) at the square it is standing on when the
  action resolves. Rubble 60 is seven times the cost of bare ground.
- Lead is on the map and finite: THE MAP ADDS 5 LEAD EVERY 20 ROUNDS TO EVERY
  SQUARE THAT STILL HOLDS AT LEAST 1, so a miner that takes a square to zero
  has destroyed that deposit for the rest of the game. A miner's action
  cooldown is 2 against a limit of 10, so it mines up to FIVE times a turn on
  flat ground.
- GOLD exists only because a LABORATORY makes it, or because something died
  and dropped 20% of its build cost. A laboratory's price is
  floor(20 - 18*exp(-k*n)) lead per gold in the number n of friendly robots it
  can see inside r2<=53, with k = 0.02/0.01/0.005 by its level: TWO LEAD A
  GOLD STANDING ALONE, ELEVEN WITH FORTY FRIENDS NEARBY.
- Buildings can be MUTATED to level 2 with lead (archon 300, watchtower 150,
  laboratory 150) and level 3 with gold (80 / 60 / 25), and can TRANSFORM
  between TURRET mode (acts, cannot move) and PORTABLE mode (moves, cannot
  act) for 100 cooldown — so an archon can get up and walk.
- Each map ships a fixed, PUBLIC ANOMALY SCHEDULE of roughly one event per 200
  rounds. ABYSS takes 10% of the metal on every square and in both reserves,
  ROUNDED DOWN — so a square holding 9 or fewer loses nothing. CHARGE destroys
  the top 5% of ALL DROIDS ON THE BOARD ranked by how many friends each can
  see — the ranking is over BOTH teams, so the side that clumps donates the
  victims, and under twenty droids IT KILLS NOBODY. FURY takes 5% of the max
  health of every building IN TURRET MODE — a building in PORTABLE mode and a
  PROTOTYPE take NOTHING. VORTEX reflects or rotates the rubble map.
- At round 2000 the SINGULARITY takes the weaker side: more archons alive,
  then greater gold net worth, then greater lead net worth, then a coin flip.

SCORING
  points = int(64 * archon share + 24 * gold-net-worth share
               + 12 * lead-net-worth share)
Winning a game is worth 200 and points are worth at most 100, so the game
bonus dominates: killing the last enemy archon wins outright.

YOUR REPLY
Reply with ONE JSON object and NOTHING else. Your reply must begin with '{'.
{"sheet": {...knobs...}, "notes": "<=280 chars", "motto": "<=48 chars"}

THE KNOBS (unknown key, wrong type or out-of-range value = that field's
default; the five integers CLAMP; you cannot forfeit by answering badly, only
by answering weakly):
  opening              "soldier_rush" | "miner_eco" | "sage_spam"  default "miner_eco"
  miner_count_curve    "lean" | "steady" | "heavy"                 default "steady"
  mine_floor           0..5   how much lead a miner LEAVES         default 1
  soldier_sage_ratio   0..100 percent of the attack budget, in
                       lead-equivalent, that goes to soldiers      default 65
  lab_round            1..1800 when the first laboratory is
                       commissioned                                default 300
  lab_solitude         0..40  the most friendly robots a lab
                       tolerates before it stops transmuting       default 12
  gold_use             "sages" | "mutations"                       default "sages"
  watchtower_policy    "never" | "home" | "forward"                default "home"
  anomaly_play         "ignore" | "time_pushes"                    default "time_pushes"
  archon_relocate      "never" | "safety" | "lead"                 default "safety"
  retreat_hp           0..100 percent of max health at which a
                       droid disengages toward an archon           default 40

No setting of any knob makes your faction idle: it always keeps at least three
miners per archon digging, always builds a soldier when lead allows and the
census is short, always spends an archon's action rather than banking it,
always answers an enemy attacker sensed near one of its own archons, always
repairs a damaged droid in an archon's reach, and NEVER lets its last archon
stand up while an enemy attacker is within eight squares. Your faction is
driven by the `wololo` chassis. That is not yours to choose: there is no
`chassis` knob, and a reply that sends one has it ignored.

HOW A GAME ENDS
A game ends the instant a faction's last archon dies (`annihilated`), or at
round 2000 on the Singularity ladder. There is NO elimination for losing
droids: a faction with one archon and nothing else plays on to round 2000
earning 2 lead a round.
"""

const Bc16Preamble* = """
You command a faction of robots in Battlecode 2016, "Zombie Invasion": a
two-faction grid war on a symmetric map, 3000 rounds a game (numbered 0 to
2999), best of three.

You do not move a single robot. Before the war you write ONE DOCTRINE — a
JSON sheet of eleven named knobs — and a deterministic simulation then plays
the whole match from it while you watch.

THE WORLD
- Each faction starts with 1 to 4 ARCHONS (1000 hp) and 300 PARTS. AN ARCHON
  CANNOT BE BUILT AND IS THE ONLY THING THAT DECIDES THE GAME: lose your last
  one and you lose immediately.
- An archon builds SOLDIERS (30 parts, 60 hp, 4 damage at range-squared 13),
  GUARDS (30, 145 hp, 1.5 melee but DOUBLE against zombies and 4 damage
  BLOCKED off any hit above 10), SCOUTS (25, 80 hp, NO attack, IGNORES
  RUBBLE, sight range-squared 53), VIPERS (120, 120 hp, 2 damage at
  range-squared 20 that INFECTS FOR 20 TURNS) and TURRETS (130, 100 hp, 13
  damage between range-squared 6 and 40, immobile — it must PACK into a TTM
  to move and UNPACK to shoot). Building freezes the archon for that unit's
  build turns: 20 for a scout, 12 a soldier, 10 a guard, 30 a viper, 25 a
  turret.
- An archon also REPAIRS one friendly non-archon for 1 hp a turn, for free,
  within range-squared 24 — the only healing in the game — and PICKS UP EVERY
  PART on any square it stands on or walks onto, all of it, and nothing else
  in the game collects parts.
- Income is `max(0, 2 - 0.01 * your live robot count)` parts per round: ZERO
  AT 200 ROBOTS and half at 100. That is the whole economy alongside the
  map's parts and 200 per zombie den killed.

THE HORDE
- Each map ships a fixed PUBLIC zombie spawn schedule — round to counts of
  STANDARDZOMBIE / RANGEDZOMBIE / FASTZOMBIE / BIGZOMBIE — divided evenly
  among the map's 2 to 12 ZOMBIE DENS (2000 hp each, worth 200 parts to
  whoever kills one). You can read the whole schedule from round 0.
- Zombies belong to a third team, SEE THE WHOLE MAP ALWAYS, and every zombie
  every turn walks at the NEAREST PLAYER-CONTROLLED ROBOT ON THE MAP, OF
  EITHER FACTION, and hits it.
- Every 300 rounds the OUTBREAK LEVEL rises and every zombie spawned after it
  is stronger: x1.0, x1.1, x1.2, x1.3, x1.5, x1.7, x2.0, x2.3, x2.6, x3.0 —
  so a round-2700 BIGZOMBIE has 5000 health and 250 damage.
- A den that still has zombies queued damages EVERY adjacent non-zombie robot
  for 10 a round.

INFECTION, RUBBLE, NEUTRALS
- A zombie hit infects for 10 turns (no damage); a VIPER hit for 20 turns at
  2 damage a turn. ANYTHING THAT DIES WHILE INFECTED LEAVES NO RUBBLE AND
  STANDS BACK UP AS A ZOMBIE of its own type on the horde's team, where it
  fell: archon to BIGZOMBIE, scout to FASTZOMBIE, soldier or guard to
  STANDARDZOMBIE, viper/turret/TTM to RANGEDZOMBIE. It then hunts whoever is
  nearest — which can be them.
- Anything that dies UNINFECTED raises the rubble on its square by its own
  max health (1000 an archon, 500 a bigzombie, 145 a guard; a third of that
  if a TURRET landed the killing blow). RUBBLE OF 100 OR MORE IS IMPASSABLE
  to everything except a SCOUT, a FASTZOMBIE and a BIGZOMBIE; 50 or more
  DOUBLES every movement and cooldown charge. One clear action turns r into
  max(0, 0.95r - 10), so 100 takes fourteen actions and 1000 takes about 55.
  A TURRET and a TTM cannot clear.
- NEUTRAL robots stand on most maps. An ARCHON ACTIVATES one within
  range-squared 2 for ZERO PARTS and 2 core delay: the neutral is replaced by
  an identical robot on your team, immediately active. Some maps place
  neutral ARCHONS, and an extra archon is the first tiebreak at round 2999.

FRIENDLY FIRE IS LEGAL and there is no reading under which shooting your own
soldiers is a strategy; the chassis never does it.

YOUR REPLY
Reply with ONE JSON object and NOTHING else. Your reply must begin with '{'.
{"sheet": {...knobs...}, "notes": "<=280 chars", "motto": "<=48 chars"}

THE KNOBS (unknown key, wrong type or out-of-range value = that field's
default; the four integers CLAMP to their range; you cannot forfeit by
answering badly, only by answering weakly):
  opening             "turtle" | "soldier_viper_aggro" | "scout_zombie_pull"
                                                          default "turtle"
  turret_count        0..12                                default 3
  guard_ratio         0..100  (percent of the ATTACKER budget)  default 45
  zombie_kiting       "never" | "ranged_only" | "always"   default "ranged_only"
  den_clear_round     1..2800                              default 900
  parts_priority      "units" | "turrets" | "vipers"       default "units"
  archon_spread       "huddle" | "spread" | "split"        default "spread"
  neutral_activation  "never" | "opportunistic" | "hunt"   default "opportunistic"
  retreat_hp          0..100  (percent of max health)      default 35
  rubble_clear        "never" | "paths" | "aggressive"     default "paths"
  infection_policy    "ignore" | "quarantine" | "suicide_squad"
                                                          default "quarantine"

THE CHASSIS IS NOT YOURS TO CHOOSE. There is no `chassis` knob, and a reply
that sends one has it recorded as an unknown field and ignored. Your faction
is driven by the `bulwark` chassis, which independently of every knob keeps at
least one archon collecting parts, builds an attacker whenever parts allow and
the attacker census is short (never fewer than three attackers per archon),
answers any hostile sensed within range-squared 24 of one of its own archons,
spends every archon's free repair every turn, never walks its last archon
into a den's damage ring, and never fires on its own units.

HOW A GAME ENDS
A game ends the instant a faction's last ARCHON dies (`archons_destroyed`),
or at the end of round 2999 on this ladder, first non-zero difference wins:
more archons alive (`more_archons`), then greater total live-archon health
(`more_archon_health`), then greater parts stockpile plus the parts cost of
every live robot (`more_parts_net_worth`), then higher maximum live archon id
(`highest_id`, and Clan Basil on a 0-0). THERE IS NO ELIMINATION FOR LOSING
YOUR ARMY: a faction with one archon and nothing else plays on to round 2999
earning 2 parts a round.
"""

const Bc19Preamble* = """
You command a religious order in Battlecode 2019, "Crusade": a two-order grid
war on a SQUARE, MIRROR-SYMMETRIC map between 32x32 and 64x64, 1000 rounds a
game, best of three.

You do not move a single robot. Before the war you write ONE DOCTRINE -- a
JSON sheet of eleven named knobs -- and a deterministic simulation then plays
the whole match from it while you watch.

THE BOARD IS A MIRROR AND THE MIRROR IS THE MAP. Every robot is handed the
WHOLE terrain map, the WHOLE karbonite map and the WHOLE fuel map on its
FIRST turn, so their castles are exactly the mirror image of yours and you
know where they are from round 1. There is no scouting problem and no fog
over terrain -- only over units.

CASTLES ARE THE ONLY THING THAT DECIDES THE GAME. Lose your last one and you
lose on the spot. At round 1000 the side with more castles wins, then the
side with greater TOTAL HEALTH OF ALL ITS LIVE UNITS, then a coin flip.

KARBONITE BUILDS UNITS AND FUEL RUNS THEM. The ONLY free income in the game
is a FLAT 25 fuel per team per round -- it does not scale with castles or
churches -- and karbonite has NO passive income at all. A PILGRIM standing
on a depot mines +2 karbonite (cap 20) or +10 fuel (cap 100) a turn for 1
fuel, and the load is UNREFINED and UNSPENDABLE until a robot GIVEs it to an
adjacent CASTLE or CHURCH. Every move costs r-squared times the unit's fuel
rate, every attack costs 10 to 25, and every broadcast costs ceil(sqrt(r2)).

FOUR THINGS MAKE THIS YEAR ITS OWN GAME:
  1. THE PREACHER HITS YOU TOO. Its attack puts 20 damage on EVERY OCCUPIED
     SQUARE within range-squared 3 of the target -- nine squares -- WITH NO
     TEAM CHECK, and its minimum range is 1, so firing at anything adjacent
     damages ITSELF and every friendly beside it.
  2. A KILL PAYS. When you kill a non-structure you collect
     floor((its carried karbonite + its build karbonite / 2) / r2) karbonite
     and floor(its carried fuel / r2) fuel, capped at your own capacity. A
     loaded pilgrim is the most valuable target on the board.
  3. A CHURCH is a second SPAWN point AND a second DEPOSIT point, costs 50
     karbonite and 200 fuel, and can only be built by a PILGRIM.
  4. THE TWO ORDERS CAN TRADE WITH EACH OTHER. A CASTLE may propose a
     karbonite-for-fuel swap; when both standing offers match element-wise
     the swap executes and both offers clear.

A PROPHET CANNOT HIT WHAT IS NEXT TO IT: its range is 16 to 64 SQUARED and it
is blind inside 16. A CRUSADER moves range-squared 9 a turn, twice as far as
anything else in the game.
"""

proc preambleFor*(year: string): string =
  case yearIdOf(year)
  of yBc20: Bc20Preamble
  of yBc21: Bc21Preamble
  of yBc24: Bc24Preamble
  of yBc25: Bc25Preamble
  of yBc23: Bc23Preamble
  of yBc22: Bc22Preamble
  of yBc16: Bc16Preamble
  of yBc19: Bc19Preamble
  of yBc26: SystemPreamble

proc briefFor*(
  config: GameConfig, plan: MatchPlan, slot: int
): string =
  ## Everything this seat may legitimately know: its own alias and side, all
  ## the map cards, the seed, the scoring weights, the deadlines. NOT in here,
  ## ever: the opponent's doctrine, sheet, notes, motto, real player name or
  ## fallback status. Sealed and simultaneous.
  var games = newJArray()
  for g in 0 ..< plan.maps.len:
    games.add(mapCardFor(plan.year, plan.maps[g], slot, plan.sideAslots[g],
      plan.maxRounds))
  var payload = %*{
    "protocol": ProtocolId,
    "game_version": GameVersion,
    "year": plan.year,
    "slot": slot,
    "alias": aliasFor(slot),
    "opponent_alias": aliasFor(1 - slot),
    "team": (if plan.sideAslots[0] == slot: "A" else: "B"),
    "seed": plan.seed,
    "games": games,
    "budget": {
      "attempt1_ms": config.attempt1Ms,
      "retry_ms": config.retryMs,
      "one_shot": true
    }
  }
  case yearIdOf(plan.year)
  of yBc20:
    payload["flood_table"] = floodTableJson()
    payload["scoring"] = %*{
      "weights": {"hq_survival": 60, "unit_share": 25, "net_worth_share": 15},
      "win_bonus_per_game": 100,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer"
    }
  of yBc21:
    var breakpoints = newJArray()
    for value in bc21Breakpoints():
      if breakpoints.len >= 30: break
      breakpoints.add(%value)
    payload["economy"] = %*{
      "center_passive":
        "ceil(0.2*sqrt(round)) per center per round; 8507 total over 1500 rounds",
      "center_start_influence": 150,
      "slanderer_breakpoints": breakpoints,
      "slanderer_payments": 51,
      "camouflage_round": 300,
      "expose_buff": "+0.001 x slanderer influence, for 50 rounds",
      "empower_tax": 10,
      "votes_on_offer": plan.maxRounds,
      "losing_bid_cost": "ceil(bid/2)"
    }
    payload["sheet_schema"] = bc21SheetSchema()
    payload["scoring"] = %*{
      "weights": {"survival": 40, "vote_share": 35, "center_share": 15,
                  "influence_share": 10},
      "win_bonus_per_game": 100,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer"
    }
  of yBc24:
    payload["economy"] = %*{
      "start_crumbs": 400, "passive_per_round": 10,
      "kill_reward_in_enemy_territory": 30,
      "dig_cost": 20, "fill_cost": 30,
      "trap_costs": {"explosive": 200, "stun": 100, "water": 100},
      "trap_effects": {
        "explosive": "750 dmg r2<=4 on entry, 200 dmg r2<=2 on dig/fill/build",
        "stun": "enemy cooldowns set to 40, r2<=13",
        "water": "floods every free land tile r2<=9"},
      "flag_return_rounds": 4,
      "flag_return_rounds_with_enemy_capture_upgrade": 25
    }
    payload["units"] = %*{
      "per_team": 50, "hp": 1000, "vision_r2": 20, "attack_r2": 4,
      "heal_r2": 4, "interact_r2": 2, "jail_rounds": 25,
      "damage_by_attack_level": [150, 158, 161, 165, 195, 203, 240],
      "heal_by_heal_level": [80, 82, 84, 86, 88, 92, 100],
      "xp_to_level": {"attack": [15, 30, 45, 75, 110, 150],
                      "build": [5, 10, 15, 20, 25, 30],
                      "heal": [20, 40, 70, 100, 140, 180]},
      "mastery": "at level 4 in one skill the other two freeze at level 3"
    }
    payload["upgrades"] = %*{
      "rounds": [600, 1200, 1800],
      "attack": "+60 base damage",
      "heal": "+50 base heal",
      "capture": "their dropped flags take 25 rounds to fly home instead of " &
                 "4; your flag-carry movement cooldown 20 -> 12"
    }
    payload["sheet_schema"] = bc24SheetSchema()
    payload["scoring"] = %*{
      "weights": {"flag_share": 60, "level_share": 25, "crumb_share": 15},
      "win_bonus_per_game": 100,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer"
    }
  of yBc25:
    payload["economy"] = %*{
      "start_chips": 2500, "tower_costs": [1000, 2500, 5000],
      "money_tower_per_turn": [20, 30, 40],
      "paint_tower_per_turn": [5, 10, 15],
      "defense_tower_chips_per_hit": [20, 30, 40],
      "srp": {"chip_cost": 200, "paint_cost_to_mark": 25, "tiles": 25,
              "rounds_undisturbed_to_activate": 50,
              "bonus": "+3 per turn to EVERY mining tower you own"},
      "max_towers": 25
    }
    payload["units"] = %*{
      "soldier": {"hp": 250, "paint_cap": 200, "paint_cost": 200,
                  "chip_cost": 250, "attack_paint": 5, "attack_r2": 9,
                  "cooldown": 10,
                  "does": "paints one tile, or 50 damage to an enemy tower"},
      "splasher": {"hp": 150, "paint_cap": 300, "paint_cost": 300,
                   "chip_cost": 400, "attack_paint": 50, "attack_r2": 4,
                   "cooldown": 50,
                   "does": "paints everything within r2<=4 of the centre, " &
                           "over ENEMY paint within r2<=2, and 100 damage " &
                           "to every enemy tower in the blast"},
      "mopper": {"hp": 50, "paint_cap": 100, "paint_cost": 100,
                 "chip_cost": 300, "attack_paint": 0, "attack_r2": 2,
                 "cooldown": 30,
                 "does": "erases one enemy tile and steals 10 paint from a " &
                         "robot on it; mop swing (cooldown 20) takes 5 " &
                         "paint from up to SIX enemies in a cardinal " &
                         "direction; the only unit that can give paint to " &
                         "an ally"}
    }
    payload["paint_rules"] = %*{
      "vision_r2": 20,
      "end_turn_cost": "1 paint on bare ground, 2 on enemy ground, 0 on " &
                       "your own; DOUBLED for moppers; plus 1 per adjacent " &
                       "allied unit (towers count), doubled on enemy ground",
      "low_paint": "below 50% of capacity every cooldown grows by " &
                   "(100 - 2*percent)%",
      "zero_paint": "cannot move, cannot act, loses 20 HP every turn"
    }
    payload["towers"] = %*{
      "how_built": "paint an exact 5x5 two-colour pattern around a ruin, " &
                   "then complete it for 1000 chips",
      "patterns": {
        "money": pat25.patternRows(pat25.pkMoneyTower),
        "paint": pat25.patternRows(pat25.pkPaintTower),
        "defense": pat25.patternRows(pat25.pkDefenseTower),
        "srp": pat25.patternRows(pat25.pkResource),
        "legend": "P = your primary colour, S = your secondary; both count " &
                  "as yours for territory"},
      "hp": {"money": [1000, 1500, 2000], "paint": [1000, 1500, 2000],
             "defense": [2000, 2500, 3000]},
      "attacks": "one single-target shot AND one area shot per turn, no " &
                 "cooldown; defense towers add +5/+7/+9 to every allied " &
                 "tower's single shot"
    }
    payload["win"] = %*{
      "instant": "paint 70% of (width*height - walls), or destroy every " &
                 "enemy robot AND tower",
      "at_round_2000": ["more squares painted", "more towers alive",
                        "more chips", "more paint in units",
                        "more robots alive", "coin flip"]
    }
    payload["sheet_schema"] = bc25SheetSchema()
    payload["scoring"] = %*{
      "weights": {"area_share": 55, "tower_share": 20, "chip_share": 10,
                  "paint_share": 10, "robot_share": 5},
      "win_bonus_per_game": 200,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer"
    }
  of yBc23:
    payload["economy"] = %*{
      "start_per_headquarters": {"adamantium": 200, "mana": 200},
      "passive_per_headquarters_every_5_rounds":
        {"adamantium": 6, "mana": 6},
      "well_rate": 1, "upgraded_well_rate": 3,
      "well_upgrade_cost_same_resource": 1400,
      "well_to_elixir_cost_opposite_resource": 600,
      "carrier_capacity": 40, "anchor_weight": 40,
      "note": "a resource thrown into a well leaves your team total for good"
    }
    payload["units"] = %*{
      "headquarters": {"hp": "indestructible", "action_cd": 2, "action_r2": 9,
        "vision_r2": 34,
        "does": "builds robots and anchors (UP TO FIVE ACTIONS A TURN), " &
                "stores resources, deals 4 damage to every enemy within " &
                "r2<=9 at the end of every round"},
      "carrier": {"ad": 50, "hp": 150, "capacity": 40, "action_cd": 10,
        "action_r2": 9, "vision_r2": 20,
        "move_cd": "floor(5 + 3*cargo/8) - a full carrier is half the speed " &
                   "of an empty one",
        "does": "mines 1 (or 3 from an upgraded well) per action from a well " &
                "it stands on or beside, carries resources and anchors, " &
                "plants anchors, and can THROW its whole cargo for " &
                "floor(5*cargo/4) damage - up to 50 - losing the cargo " &
                "whether it hits or not"},
      "launcher": {"mn": 45, "hp": 200, "damage": 20, "action_cd": 10,
        "action_r2": 16, "vision_r2": 20, "move_cd": 20,
        "does": "the only real attacker; hits any square within r2<=16, " &
                "even a robot it cannot see"},
      "amplifier": {"ad": 30, "mn": 15, "hp": 120, "action_cd": "none",
        "vision_r2": 34, "move_cd": 15,
        "does": "lets friendly robots within r2<=20 WRITE the shared array"},
      "destabilizer": {"ex": 200, "hp": 300, "damage": 50, "action_cd": 70,
        "action_r2": 13, "move_cd": 25,
        "does": "marks a square: every tile within r2<=15 of it gives the " &
                "ENEMY +10% cooldowns for 5 rounds, then deals 50 damage to " &
                "whatever enemy stands there"},
      "booster": {"ex": 150, "hp": 400, "action_cd": 140, "move_cd": 25,
        "does": "gives every ALLY within r2<=20 of where it stood -10% " &
                "cooldowns for 10 rounds; stacks 3 deep; the patch does not " &
                "follow the booster"}
    }
    payload["anchors"] = %*{
      "standard": {"ad": 80, "mn": 80, "health": 250,
                   "heals_allies_within_r2_4": 4},
      "accelerating": {"ex": 300, "health": 750,
                       "heals_allies_within_r2_4": 6,
                       "cooldowns": "-15% for allies within r2<=4 of the island"},
      "how": "a headquarters builds it; an EMPTY carrier takes it (it weighs " &
             "the carrier's whole capacity), walks onto an island tile and " &
             "plants it",
      "holding": "every round an anchor's health moves by (percent of the " &
                 "island's tiles you occupy) - (percent they occupy), capped " &
                 "at its max; at 0 the island goes neutral and either side " &
                 "can plant",
      "override": "you may replace your OWN anchor (it returns to full " &
                  "health) but that does NOT count as a new anchor placed " &
                  "for the tiebreak"
    }
    payload["tempo"] = %*{
      "cloud": "+20% cooldowns and vision collapses to r2<=4 - both ways, " &
               "so a robot in a cloud is also hidden",
      "stacking": "ADDITIVE on a per-tile, per-team multiplier: 1.00 +0.20 " &
                  "cloud -0.10 per boost (max 3) +0.10 per destabilise " &
                  "(max 2) -0.15 accelerating anchor",
      "applied": "round(base_cooldown * multiplier), read at the tile you " &
                 "end up on"
    }
    payload["comms"] = %*{
      "shared_array": 64, "max_value": 65535,
      "write_rule": "a headquarters or an amplifier may always write; any " &
                    "other robot needs a friendly amplifier within r2<=20, a " &
                    "friendly headquarters within r2<=9, or one of YOUR " &
                    "islands within r2<=4",
      "read_rule": "always", "cost": "none"
    }
    payload["win"] = %*{
      "instant": "hold 75% of the sky islands (see islands_to_win per map)",
      "at_round_2000": ["more islands held", "more anchors ever placed",
                        "more elixir", "more mana", "more adamantium",
                        "coin flip"],
      "note": "there is NO elimination: headquarters cannot be destroyed and " &
              "a side with no robots plays on to round 2000"
    }
    payload["sheet_schema"] = bc23SheetSchema()
    payload["scoring"] = %*{
      "weights": {"islands_share": 60, "anchors_share": 22,
                  "elixir_share": 10, "mana_share": 5, "adamantium_share": 3},
      "win_bonus_per_game": 200,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer; the " &
              "league ranks by scores, which the win bonus dominates"
    }
  of yBc22:
    payload["economy"] = %*{
      "start_per_team": {"lead": 200, "gold": 0},
      "passive_per_team_per_round": {"lead": 2},
      "map_regeneration": {"every_rounds": 20, "amount": 5,
        "rule": "added ONLY to a square that still holds at least 1 lead " &
                "— a square mined to zero is dead for the rest of the game"},
      "mine_rate": "one unit per action; a miner's action cooldown is 2 " &
                   "against a limit of 10, so up to FIVE mines a turn on " &
                   "rubble-free ground",
      "reclaim": "a destroyed robot drops 20% of its build cost (including " &
                 "mutations) on the square it last occupied; an archon " &
                 "drops 20 gold, 36 at level 3",
      "laboratory": {
        "lead_per_gold": "floor(20 - 18*exp(-k*n)) where n is the friendly " &
                         "robots the lab can see (vision r2<=53) and k is " &
                         "0.02 / 0.01 / 0.005 by level",
        "measured_level1": {"0": 2, "3": 3, "6": 4, "10": 5, "13": 6,
                            "21": 8, "30": 10, "40": 11}}
    }
    payload["units"] = %*{
      "archon": {"au": "cannot be built (nominal 100)",
        "hp": "600/1080/1944 by level", "act_cd": 10, "move_cd": 24,
        "act_r2": 20, "vis_r2": 34,
        "does": "builds MINER, BUILDER, SOLDIER and SAGE in an adjacent " &
                "square; repairs a friendly non-building for 2/4/6 a turn " &
                "within r2<=20; LOSE YOUR LAST ARCHON AND YOU LOSE THE GAME " &
                "IMMEDIATELY"},
      "laboratory": {"pb": 180, "hp": "100/180/324", "act_cd": 10,
        "move_cd": 24, "vis_r2": 53,
        "does": "turns lead into exactly 1 gold per action at the " &
                "loneliness price above; the ONLY source of gold; built by " &
                "a BUILDER as an 80-HP prototype that needs 10 builder " &
                "repairs to come alive"},
      "watchtower": {"pb": 150, "hp": "150/270/486", "dmg": "4/8/12",
        "act_cd": 10, "act_r2": 20, "vis_r2": 34,
        "does": "a building that shoots; built by a BUILDER as a 120-HP " &
                "prototype that needs 15 builder repairs to come alive"},
      "miner": {"pb": 50, "hp": 40, "act_cd": 2, "move_cd": 20, "act_r2": 2,
        "vis_r2": 20,
        "does": "mines one lead or one gold per action from its own square " &
                "or any of the eight around it"},
      "builder": {"pb": 40, "hp": 30, "act_cd": 10, "move_cd": 20,
        "act_r2": 5, "vis_r2": 20,
        "does": "builds LABORATORY and WATCHTOWER, repairs a friendly " &
                "building 2 a turn, and MUTATES a friendly building a level"},
      "soldier": {"pb": 75, "hp": 50, "dmg": 3, "act_cd": 10, "move_cd": 16,
        "act_r2": 13, "vis_r2": 20,
        "does": "the general-purpose attacker, and the whole 2022 " &
                "metagame; 3 damage a hit, so an archon takes 200 hits"},
      "sage": {"au": 20, "hp": 100, "dmg": 45, "act_cd": 200, "move_cd": 25,
        "act_r2": 25, "vis_r2": 34,
        "does": "45 damage — fifteen soldiers' worth — once every twenty " &
                "turns; and the ONLY unit that can ENVISION an anomaly"}
    }
    payload["buildings"] = %*{
      "modes": "a building is built as a PROTOTYPE at 80% health that can " &
               "neither act nor move; a BUILDER repairing it to full turns " &
               "it into a TURRET (acts, cannot move); TRANSFORM flips " &
               "TURRET<->PORTABLE (moves, cannot act) and costs 100 " &
               "cooldown on the mode-appropriate counter, i.e. ten of its " &
               "own turns",
      "mutations": "level 2 costs LEAD (archon 300, watchtower 150, " &
                   "laboratory 150); level 3 costs GOLD (archon 80, " &
                   "watchtower 60, laboratory 25); applied by a BUILDER " &
                   "within r2<=5 and freezes the building for 100 on BOTH " &
                   "counters",
      "archons_walk": "an archon is a building: it can transform to " &
                      "PORTABLE and relocate"
    }
    payload["rubble"] = %*{
      "range": "0..100 per square, fixed except by a VORTEX",
      "effect": "every cooldown a robot pays is floor((1 + rubble/10) * " &
                "base), evaluated at the square the robot is standing on " &
                "when the action resolves — and for a MOVE that is the " &
                "DESTINATION square"
    }
    payload["anomalies"] = %*{
      "schedule": "public to every robot at all times, per map, roughly one " &
                  "per 200 rounds",
      "abyss": "10% of the lead and gold on EVERY square and in BOTH team " &
               "reserves, rounded DOWN — so a square holding 9 or fewer " &
               "loses nothing",
      "charge": "the top 5% of ALL droids on the board, ranked by how many " &
                "friendly robots each can see, are destroyed; the ranking " &
                "is over BOTH teams together, so the side that clumps " &
                "donates the victims; and floor(0.05*n) is ZERO for any " &
                "droid count of 19 or fewer",
      "fury": "every building IN TURRET MODE loses 5% of its max health, " &
              "rounded down (a level-1 watchtower loses 7); a building in " &
              "PORTABLE mode and a PROTOTYPE take NOTHING",
      "vortex": "the rubble map is reflected or rotated according to the " &
                "map's declared symmetry; lead, gold and robots do not move",
      "sage_versions": {
        "abyss": "99% of the metal on every square within r2<=25",
        "charge": "every enemy droid within r2<=25 loses 22% of its max HP",
        "fury": "every turret-mode building within r2<=25 loses 10% of its " &
                "max HP",
        "vortex": "NOT available to a sage"}
    }
    payload["comms"] = %*{
      "shared_array": 64, "max_value": 65535,
      "write_rule": "any robot, any time, no cooldown, no range test, no cost",
      "read_rule": "always"
    }
    payload["win"] = %*{
      "instant": "destroy the enemy's LAST ARCHON",
      "at_round_2000": ["more archons alive",
                        "greater gold net worth (reserve + live robots' " &
                        "gold worth)", "greater lead net worth", "coin flip"],
      "note": "there is no elimination for losing droids: a faction with " &
              "one archon and nothing else plays on to round 2000 earning " &
              "2 lead a round"
    }
    payload["sheet_schema"] = bc22SheetSchema()
    payload["scoring"] = %*{
      "weights": {"archons_share": 64, "gold_net_worth_share": 24,
                  "lead_net_worth_share": 12},
      "win_bonus_per_game": 200,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer; the " &
              "league ranks by ELO on match wins and results.scores is " &
              "dominated by the win bonus"
    }
  of yBc16:
    payload["economy"] = %*{
      "start_per_team": {"parts": 300},
      "income_per_team_per_round":
        "max(0, 2 - 0.01 * your live robot count) parts -- so income is " &
        "ZERO at 200 robots and half at 100",
      "den_bounty": 200,
      "map_parts": "archon-collected only, whole-square, never regenerating"
    }
    payload["units"] = %*{
      "archon": {"parts": "cannot be built", "hp": 1000, "attack": 0,
        "repair_r2": 24, "sight_r2": 35, "move_delay": 2,
        "cooldown_delay": 1, "turns_into": "bigzombie",
        "does": "builds SCOUT/SOLDIER/GUARD/VIPER/TURRET in an adjacent " &
                "square (and is FROZEN for that unit's build turns); " &
                "repairs one friendly non-archon for 1 hp within r2<=24 FOR " &
                "FREE, once a turn; activates NEUTRALs within r2<=2; " &
                "collects parts by standing on them. LOSE YOUR LAST ARCHON " &
                "AND YOU LOSE IMMEDIATELY"},
      "scout": {"parts": 25, "build_turns": 20, "hp": 80, "attack": 0,
        "sight_r2": 53, "move_delay": 1.4, "ignores_rubble": true,
        "turns_into": "fastzombie",
        "does": "sees further than anything else, walks through ANY rubble, " &
                "cannot attack, and is the cheapest thing you can put " &
                "between a den and yourself"},
      "soldier": {"parts": 30, "build_turns": 12, "hp": 60, "attack": 4,
        "attack_r2": 13, "sight_r2": 24, "move_delay": 2, "attack_delay": 2,
        "turns_into": "standardzombie"},
      "guard": {"parts": 30, "build_turns": 10, "hp": 145, "attack": 1.5,
        "attack_r2": 2, "sight_r2": 24, "move_delay": 2, "attack_delay": 1,
        "turns_into": "standardzombie",
        "does": "DOUBLE damage against zombies, and 4 damage BLOCKED off " &
                "any hit above 10"},
      "viper": {"parts": 120, "build_turns": 30, "hp": 120, "attack": 2,
        "attack_r2": 20, "infect_turns": 20, "move_delay": 2,
        "attack_delay": 3, "turns_into": "rangedzombie",
        "does": "infects for 20 turns at 2 damage a turn; an infected robot " &
                "that dies becomes a ZOMBIE instead of leaving rubble"},
      "turret": {"parts": 130, "build_turns": 25, "hp": 100, "attack": 13,
        "attack_r2": 40, "attack_r2_minimum": 6, "immobile": true,
        "attack_delay": 3, "cooldown_delay": 3, "turns_into": "rangedzombie",
        "does": "the longest reach in the game, but cannot shoot inside r2 " &
                "6 and cannot move or clear rubble; PACK it into a TTM (10 " &
                "delay on both counters) to relocate, UNPACK to shoot"},
      "ttm": {"parts": "not buildable -- only reachable by PACKING a turret",
        "hp": 100, "attack": 0, "move_delay": 2, "cooldown_delay": 2,
        "turns_into": "rangedzombie"}
    }
    payload["zombies"] = %*{
      "team": "a third team called THE HORDE; it never wins and never scores",
      "targeting": "EVERY zombie, EVERY turn, walks at the NEAREST " &
                   "player-controlled robot on the map, of EITHER team; " &
                   "zombies see the whole map always",
      "standardzombie": {"hp": 60, "attack": 2.5, "attack_r2": 2,
                         "move_delay": 3},
      "rangedzombie": {"hp": 60, "attack": 3, "attack_r2": 13,
                       "move_delay": 3},
      "fastzombie": {"hp": 80, "attack": 3, "attack_r2": 2,
                     "move_delay": 1.4, "ignores_rubble": true},
      "bigzombie": {"hp": 500, "attack": 25, "attack_r2": 2,
                    "move_delay": 4, "ignores_rubble": true},
      "outbreak": "every 300 rounds every NEWLY SPAWNED zombie's health and " &
                  "damage are multiplied: x1.0, x1.1, x1.2, x1.3, x1.5, " &
                  "x1.7, x2.0, x2.3, x2.6, x3.0",
      "den": {"hp": 2000, "bounty": 200,
              "does": "spawns its share of the public schedule into up to 8 " &
                      "adjacent squares a turn, in a ring starting toward " &
                      "the nearest initial archon; if it still has a queue " &
                      "it damages every adjacent non-zombie for 10 and " &
                      "tries again"}
    }
    payload["infection"] = %*{
      "zombie_bite": "10 turns, no damage",
      "viper_bite": "20 turns, 2 damage a turn",
      "on_death": "an INFECTED robot leaves NO rubble and stands back up as " &
                  "a zombie of its own type's turns_into, on the ZOMBIE " &
                  "team, at the current outbreak multiplier, on the square " &
                  "where it fell -- and it then hunts whoever is nearest",
      "on_activation": "a NEUTRAL killed by activation leaves no rubble and " &
                       "never turns"
    }
    payload["rubble"] = %*{
      "impassable_at": 100,
      "doubles_cost_at": 50,
      "from_a_corpse": "an UNINFECTED robot's death adds its own MAX HEALTH " &
                       "to its square (1000 for an archon, 500 for a " &
                       "bigzombie, 145 for a guard) -- a third of that if a " &
                       "TURRET landed the killing blow",
      "clearing": "one action turns r into max(0, 0.95*r - 10); a TURRET and " &
                  "a TTM cannot clear; clearing a square at exactly 0 costs " &
                  "nothing and does nothing"
    }
    payload["signals"] = %*{
      "basic_per_turn": 5, "message_per_turn": 20,
      "message_senders": "ARCHON and SCOUT only",
      "cost": "0.05 delay on BOTH counters inside twice your own sight " &
              "radius, plus 0.03 per unit beyond it",
      "queue": 1000,
      "note": "there is no shared array in 2016, and EVERY signal is heard " &
              "by the enemy too"
    }
    payload["win"] = %*{
      "instant": "destroy the enemy's LAST ARCHON",
      "at_round_2999": ["more archons alive",
                        "greater total live-archon health",
                        "greater parts stockpile plus the parts cost of " &
                        "every live robot",
                        "higher maximum live archon id (and Clan Basil on a " &
                        "0-0)"],
      "note": "there is no elimination for losing your army: a faction with " &
              "one archon and nothing else plays on to round 2999 earning 2 " &
              "parts a round"
    }
    payload["sheet_schema"] = bc16SheetSchema()
    payload["scoring"] = %*{
      "weights": {"archons_share": 64, "archon_health_share": 24,
                  "parts_net_worth_share": 12},
      "win_bonus_per_game": 200,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer; the " &
              "league ranks by ELO on match wins and results.scores is " &
              "dominated by the win bonus"
    }
  of yBc19:
    payload["economy"] = %*{
      "start_per_team": {"karbonite": 100, "fuel": 500},
      "passive_income_per_team_per_round": {
        "fuel": 25, "karbonite": 0,
        "note": "the ONLY free income in the game, and FLAT -- it does NOT " &
                "scale with castles or churches"},
      "mining": {"karbonite_per_turn": 2, "fuel_per_turn": 10,
                 "fuel_cost_per_mine": 1, "pilgrim_karbonite_capacity": 20,
                 "pilgrim_fuel_capacity": 100,
                 "note": "mining at capacity STILL COSTS THE FUEL and " &
                         "yields nothing"},
      "reclaim": "when you kill a non-structure you gain floor((its " &
        "carried karbonite + its build karbonite / 2) / r2_between_you_and_" &
        "it) karbonite and floor(its carried fuel / r2) fuel, capped at " &
        "your own capacity. STRUCTURES GAIN NOTHING.",
      "trade": "a CASTLE may propose a karbonite-for-fuel swap to the " &
        "ENEMY's castles; when both sides' standing offers match " &
        "element-wise the swap executes and both offers clear. Positive " &
        "means the resource moves from RED to BLUE. |offer| < 1024."
    }
    payload["units"] = %*{
      "castle": {"build": "cannot be built", "hp": 200, "vision_r2": 100,
        "damage": 10, "attack_r2": [1, 64], "attack_fuel": 10, "speed_r2": 0,
        "does": "builds PILGRIM/CRUSADER/PROPHET/PREACHER in an adjacent " &
                "square; reads the free 8-bit castle-talk channel of every " &
                "friendly unit at ANY range; barters with the enemy's " &
                "castles; cannot move. LOSE YOUR LAST CASTLE AND YOU LOSE " &
                "ON THE SPOT"},
      "church": {"build": {"karbonite": 50, "fuel": 200},
        "built_by": "a PILGRIM only", "hp": 100, "vision_r2": 100,
        "damage": 0, "speed_r2": 0,
        "does": "a second spawn point AND a second deposit point; cannot " &
                "move, cannot read castle talk, has no attack"},
      "pilgrim": {"build": {"karbonite": 10, "fuel": 50}, "hp": 10,
        "vision_r2": 100, "speed_r2": 4, "fuel_per_r2": 1,
        "karbonite_capacity": 20, "fuel_capacity": 100,
        "does": "the ONLY unit that can mine and the ONLY unit that can " &
                "build a CHURCH; cannot attack at all"},
      "crusader": {"build": {"karbonite": 15, "fuel": 50}, "hp": 40,
        "vision_r2": 49, "speed_r2": 9, "fuel_per_r2": 1, "damage": 10,
        "attack_r2": [1, 16], "attack_fuel": 10,
        "does": "the only FAST unit -- range-squared 9 a turn, twice as " &
                "far as anything else"},
      "prophet": {"build": {"karbonite": 25, "fuel": 50}, "hp": 20,
        "vision_r2": 64, "speed_r2": 4, "fuel_per_r2": 2, "damage": 10,
        "attack_r2": [16, 64], "attack_fuel": 25,
        "does": "the longest reach in the game, and BLIND INSIDE " &
                "range-squared 16 -- it cannot hit anything closer"},
      "preacher": {"build": {"karbonite": 30, "fuel": 50}, "hp": 60,
        "vision_r2": 16, "speed_r2": 4, "fuel_per_r2": 3, "damage": 20,
        "attack_r2": [1, 16], "attack_fuel": 15, "damage_spread_r2": 3,
        "does": "20 damage to EVERY OCCUPIED SQUARE within range-squared 3 " &
                "of the target -- nine squares -- WITH NO TEAM CHECK. Its " &
                "minimum range is 1, so firing at an adjacent enemy " &
                "damages ITSELF and every friendly beside it"}
    }
    payload["combat"] = %*{
      "no_vision_needed": "an attack needs no line of sight and no vision " &
        "-- only the range check",
      "no_team_check": "an attack may legally land on your own units; the " &
        "chassis never does it",
      "no_path_check": "a move goes to any square within its speed even if " &
        "the route is blocked; one unit per square, and a move onto an " &
        "occupied or impassable square is refused"
    }
    payload["comms"] = %*{
      "radio": {"bits": 16, "max_r2": 7938,
        "fuel_cost": "ceil(sqrt(r2)), charged ONCE per turn",
        "note": "every unit of BOTH teams inside the radius reads the " &
                "value, the sender's id and position, but NOT its team. " &
                "Audible from the end of your turn until the end of your " &
                "next."},
      "castle_talk": {"bits": 8, "fuel_cost": 0, "range": "unlimited",
        "note": "readable ONLY by CASTLES of your own team, one value per " &
                "unit per turn"}
    }
    payload["win"] = %*{
      "instant": "destroy the enemy's LAST CASTLE -- the game stops " &
        "immediately, before the next robot acts",
      "at_round_1000": ["more castles alive",
                        "greater TOTAL HEALTH of all your live units (not " &
                        "just castles)",
                        "a coin flip"],
      "both_castleless": "a coin flip",
      "note": "round 1000 consists of exactly ONE robot turn: the " &
              "game-over check runs before every turn, and the round " &
              "counter reaches 1000 on the first turn of that round"
    }
    payload["sheet_schema"] = bc19SheetSchema()
    payload["scoring"] = %*{
      "weights": {"castles_share": 64, "unit_health_share": 24,
                  "net_worth_share": 12},
      "win_bonus_per_game": 200,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer; net " &
              "worth is karbonite + fuel/5 + the build cost of every live " &
              "unit; the league ranks by ELO on match wins and " &
              "results.scores is dominated by the win bonus"
    }
  of yBc26:
    payload["scoring"] = %*{
      "cooperation": {"cat_damage": 0.5, "kings": 0.3, "cheese": 0.2},
      "backstab": {"cat_damage": 0.3, "kings": 0.5, "cheese": 0.2},
      "win_bonus_per_game": 100,
      "games": plan.maps.len,
      "note": "shares are float32; points truncate to an integer"
    }
  $payload

proc decide*(
  config: GameConfig, plan: MatchPlan, seats: array[2, SeatPolicy]
): DecisionResult =
  ## The one decision turn. Returns a legal sheet for both seats no matter
  ## what the provider does.
  let client = newLlmClient(config)
  let started = getMonoTime()
  let budget = initDuration(milliseconds = max(1, config.doctrineBudgetMs))

  var open: seq[int]
  for slot in 0 .. 1:
    result.sheets[slot] = baselineSheet(config.year,
      baselineForSeat(config.year, seats[slot]))
    result.policyKind[slot] = if seats[slot].isLlm: "llm" else: "scripted"
    if seats[slot].isLlm and not client.disabled:
      open.add(slot)
      result.events.add(ev("doctrine_requested", ms = 0, fields = %*{
        "slot": slot, "attempt": 1, "deadline_ms": config.attempt1Ms}))
    elif seats[slot].isLlm:
      ## An LLM seat that CANNOT call the provider is a FALLBACK, not a
      ## scripted policy. Recording it is what makes the two countable.
      result.fallback[slot] = "no_credentials"
      result.events.add(ev("doctrine_fallback", ms = 0, fields = %*{
        "slot": slot, "cause": "no_credentials"}))
      echo "battlecode llm: seat ", slot,
        " falling back to the scripted doctrine (no_credentials)"

  var attempt = 0
  while open.len > 0 and attempt < 2:
    if client.disabled: break
    if getMonoTime() - started >= budget:
      ## The phase budget is spent. These seats fall back with the cause that
      ## actually stopped them, and `open` is CLEARED: the tail loop below
      ## records one `doctrine_fallback` per still-open seat, so leaving them
      ## open recorded a second event for the same seat and overwrote the
      ## surviving cause with "parse" — a budget timeout that reads as a
      ## malformed reply in both the replay and the log.
      for slot in open:
        result.fallback[slot] = "timeout"
        result.events.add(ev("doctrine_fallback", ms = 0, fields = %*{
          "slot": slot, "cause": "timeout"}))
        ## "falling back" is the phrase phase 60 greps the GAME log for.
        echo "battlecode llm: seat ", slot,
          " falling back to the scripted doctrine (timeout)"
      open.setLen(0)
      break
    let deadlineMs =
      if attempt == 0: config.attempt1Ms else: config.retryMs
    var batch: RequestBatch
    for slot in open:
      var user = briefFor(config, plan, slot)
      ## The observation, as sent. `SystemPreamble` (the rules digest and the
      ## sheet schema the note's payload lists) is the same for both seats and
      ## is recorded once, at the document level.
      if result.briefs[slot].len == 0: result.briefs[slot] = user
      if attempt > 0:
        user.add("\n\nYour previous reply was not usable. Reply with ONLY " &
          "the JSON object described above, starting with '{'.")
      let request = client.requestFor(
        preambleFor(config.year), userMessage(seats[slot].prompt, user))
      batch.post(request.url, request.headers, request.body, $slot)
    let batchStart = getMonoTime()
    ## ONE parallel batch. curly hands the deadline to CURLOPT_TIMEOUT, whose
    ## granularity is WHOLE SECONDS, so this conversion floors — which is why
    ## the config values are all whole seconds.
    let responses = client.curl.makeRequests(batch, max(1, deadlineMs div 1000))
    let latency = (getMonoTime() - batchStart).inMilliseconds.int
    var stillOpen: seq[int]
    for position, slot in open:
      var cause = "parse"
      try:
        let text = client.textOf(responses[position].response,
          responses[position].error, batch[position].url)
        result.sheets[slot] = parseReply(text, config.year)
        result.decisionMs[slot] = latency
        result.fallback[slot] = ""
        ## `chassis` is not a knob (sheet.KnownKeys). A reply that still sends
        ## one is already recorded in `unknownFields` and ignored — the clan
        ## runs the chassis the OPERATOR fixed — but a silent ignore is how
        ## round 1's champion came to idle three games, so the seat that tried
        ## is named in the log, along with the chassis it actually drives.
        if "chassis" in result.sheets[slot].unknownFields:
          echo "battlecode llm: seat ", slot,
            " sent `chassis`, which is not a doctrine knob: ignored, the clan",
            " runs the ",
            chassisNameFor(config.year, seats[slot], result.sheets[slot]),
            " chassis"
        result.events.add(ev("doctrine_received", ms = latency, fields = %*{
          "slot": slot, "attempt": attempt + 1, "latency_ms": latency,
          "defaults_applied": result.sheets[slot].defaultsApplied.len,
          "unknown_fields": result.sheets[slot].unknownFields.len}))
      except CatchableError as error:
        if responses[position].error.len > 0:
          cause = if "timeout" in responses[position].error.toLowerAscii():
                    "timeout" else: "transport"
        elif error.msg.startsWith("llm throttled"):
          cause = "throttled"
        result.fallbackDetail[slot] =
          sanitizeLine(error.msg, MaxFallbackDetailRunes)
        result.events.add(ev("doctrine_retry", ms = latency, fields = %*{
          "slot": slot, "cause": cause}))
        echo "battlecode llm: seat ", slot, " attempt ", attempt + 1,
          " failed, will retry: ", error.msg.truncateRunes(MaxFallbackDetailRunes)
        stillOpen.add(slot)
    open = stillOpen
    inc attempt
    if client.throttled and open.len > 0:
      ## FAIL FAST: the only model left answered 429, so the retry batch
      ## would be refused the same way.
      echo "battlecode llm: provider throttled with no other candidate; ",
        open.len, " seat(s) fall back"
      break

  for slot in open:
    result.sheets[slot] = baselineSheet(config.year,
      baselineForSeat(config.year, seats[slot]))
    let cause =
      if client.disabled or client.transport == ltNone: "no_credentials"
      elif client.throttled: "throttled"
      else: "parse"
    result.fallback[slot] = cause
    result.events.add(ev("doctrine_fallback", ms = 0, fields = %*{
      "slot": slot, "cause": cause}))
    ## "falling back" is the phrase phase 60 greps the GAME log for.
    echo "battlecode llm: seat ", slot,
      " falling back to the scripted doctrine (", cause, ")"
