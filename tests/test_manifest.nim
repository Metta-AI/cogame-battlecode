## THE TRIPLE-SYNC TRIPWIRE.
##
## The results key set, the manifest's `results_schema.required` and the key
## set `tools/ci/docker_smoke.sh` asserts are ONE set. When any of the three
## drifts, a green docker-smoke stops meaning anything, so they are compared
## here rather than trusted.
##
## The shard also checks the manifest invariants that only bite two phases
## later: `num_agents` inside every `game_config` and never at variant top
## level (`CoworldVariant` is `additionalProperties: false`), bounded arrays
## everywhere, no runner-managed `tokens`, and `protocols`/`docs` as
## `{type, value}` objects.

import std/[algorithm, json, os, sequtils, strutils]
import harness
import battlecode/[results, sim_types]
import battlecode/years/registry

let compose = readFile("compose.yaml")
let manifest = parseJson(readFile("coworld_manifest_template.json"))
let game = manifest["game"]
## `variants` and `certification` are TOP LEVEL, not under `game`:
## `docker_smoke.sh` reads `manifest["certification"]["game_config"]` and the
## platform schema puts them there too.
let variants = manifest["variants"]
let cert = manifest["certification"]

# --- the closed results key set ---------------------------------------------
block:
  var required: seq[string]
  for v in game["results_schema"]["required"]:
    required.add(v.getStr())
  var expected = @ResultsKeys
  required.sort()
  expected.sort()
  checkEq("results_schema.required == the results document's key set",
    required, expected)

  var properties: seq[string]
  for key, _ in game["results_schema"]["properties"]:
    properties.add(key)
  properties.sort()
  checkEq("and every required key has a schema", properties, expected)

  var reasons: seq[string]
  for v in game["results_schema"]["properties"]["reason"]["enum"]:
    reasons.add(v.getStr())
  checkEq("the reason enum is the closed set", reasons, @EpisodeReasons)

  ## `games.items.required` is narrowed to the FIVE year-neutral keys, and
  ## each year's own statistics are optional siblings — the two sets do not
  ## collide. Deliberately not a nested `stats` object: nesting would change
  ## the bytes every shipped bc26 replay's `result` block carries.
  var gameKeys: seq[string]
  for v in game["results_schema"]["properties"]["games"]["items"]["required"]:
    gameKeys.add(v.getStr())
  var expectedGameKeys = @RequiredGameKeys
  gameKeys.sort()
  expectedGameKeys.sort()
  checkEq("the per-game required key set is year-neutral", gameKeys,
    expectedGameKeys)

  var gameProps: seq[string]
  for key, _ in game["results_schema"]["properties"]["games"]["items"]["properties"]:
    gameProps.add(key)
  for key in RequiredGameKeys:
    check("the schema declares the required game key " & key, key in gameProps)
  for key in Bc26GameKeys:
    check("the schema keeps bc26's optional game key " & key, key in gameProps)
  for key in Bc20GameKeys:
    check("the schema declares bc20's optional game key " & key,
      key in gameProps)
  for key in Bc20GameKeys:
    check("and bc20's key does not collide with bc26's",
      key notin Bc26GameKeys)
  for key in Bc21GameKeys:
    check("the schema declares bc21's optional game key " & key,
      key in gameProps)
  for key in Bc21GameKeys:
    ## bc21 REUSES `units_built` and `units_alive` deliberately — same meaning,
    ## same type — and everything else must be its own.
    if key in ["units_built", "units_alive"]:
      check("bc21 reuses " & key & " from bc20", key in Bc20GameKeys)
    else:
      check("bc21's key " & key & " collides with neither older year",
        key notin Bc26GameKeys and key notin Bc20GameKeys)
  for key in Bc24GameKeys:
    check("the schema declares bc24's optional game key " & key,
      key in gameProps)
  for key in Bc24GameKeys:
    ## bc24 shares NOTHING with the other three: one unit type, one resource
    ## and a flag game.
    check("bc24's key " & key & " collides with no older year",
      key notin Bc26GameKeys and key notin Bc20GameKeys and
      key notin Bc21GameKeys)

  var endReasons: seq[string]
  for v in game["results_schema"]["properties"]["games"]["items"]["properties"]["end_reason"]["enum"]:
    endReasons.add(v.getStr())
  var wantEndReasons = @EndReasons
  endReasons.sort()
  wantEndReasons.sort()
  checkEq("end_reason is the union of all four years plus abandoned",
    endReasons, wantEndReasons)
  check("and bc24's two DEAD RUNGS are absent: `checkEndOfMatch` never calls " &
    "MORE_FLAGS_PICKED and no action a doctrine can reach produces " &
    "RESIGNATION",
    "more_flags_picked" notin endReasons and "resignation" notin endReasons)

  var yearEnum: seq[string]
  for v in game["config_schema"]["properties"]["year"]["enum"]:
    yearEnum.add(v.getStr())
  checkEq("config_schema.year.enum names all four years", yearEnum,
    @["bc26", "bc20", "bc21", "bc24"])
  ## bc24 plays to 2000 rounds, which is EXACTLY the existing ceiling, so no
  ## schema change was needed -- and this is the assertion that says so.
  let rounds = game["config_schema"]["properties"]["maxRounds"]
  checkEq("maxRounds still tops out at 2000", rounds["maximum"].getInt(), 2000)
  checkEq("and still bottoms at 50", rounds["minimum"].getInt(), 50)

block:
  ## The third leg: what docker_smoke.sh actually asserts.
  let smoke = readFile("tools/ci/docker_smoke.sh")
  for key in ResultsKeys:
    check("docker_smoke.sh checks results key " & key,
      "\"" & key & "\"" in smoke or "'" & key & "'" in smoke or
      key & "'" in smoke)

# --- num_agents -------------------------------------------------------------
block:
  ## ONE VARIANT PER BATTLECODE YEAR.
  checkEq("one variant per registered year", variants.len, 4)
  var variantIds: seq[string]
  for variant in variants: variantIds.add(variant["id"].getStr())
  checkEq("and they are the registered years", variantIds,
    @["bc26", "bc20", "bc21", "bc24"])
  for variant in variants:
    check("variant " & variant["id"].getStr() & " is a registered year",
      isRegisteredYear(variant["game_config"]["year"].getStr()))
    checkEq("variant " & variant["id"].getStr() & " names its own year",
      variant["game_config"]["year"].getStr(), variant["id"].getStr())
  check("variants are TOP LEVEL", not game.hasKey("variants"))
  check("and so is certification", not game.hasKey("certification"))
  for variant in variants:
    let id = variant["id"].getStr()
    check(id & " has no variant-level num_agents",
      not variant.hasKey("num_agents"))
    check(id & " has a game_config", variant.hasKey("game_config"))
    check(id & " has num_agents INSIDE its game_config",
      variant["game_config"].hasKey("num_agents"))
    checkEq(id & " is a two-seat variant",
      variant["game_config"]["num_agents"].getInt(), 2)
    checkEq(id & " names two players",
      variant["game_config"]["players"].len, 2)
    check(id & " is a registered year",
      isRegisteredYear(variant["game_config"]["year"].getStr()))
    checkEq("the variant id IS the year",
      id, variant["game_config"]["year"].getStr())

  check("the certification fixture carries num_agents",
    cert["game_config"].hasKey("num_agents"))
  checkEq("and it is 2", cert["game_config"]["num_agents"].getInt(), 2)
  checkEq("with both declared player entries seated",
    cert["players"].len, 2)
  checkEq("and two named players in the config",
    cert["game_config"]["players"].len, 2)
  var declared: seq[string]
  for p in manifest["player"]:
    declared.add(p["id"].getStr())
  var seated: seq[string]
  for p in cert["players"]:
    seated.add(p["player_id"].getStr())
    check("certification seats a DECLARED player: " & p["player_id"].getStr(),
      p["player_id"].getStr() in declared)
  ## The other direction, and the one that failed release 0.2.0: the
  ## certifier's `players-run` step fails `players_missing` for EVERY declared
  ## player that occupies no certification slot, so a manifest may not declare
  ## a player the fixture does not seat.
  for id in declared:
    check("every DECLARED player has a certification slot: " & id,
      id in seated)
  ## And the pair of checks that closes it: the certifier also requires
  ## `len(certification.players) == certification.game_config.num_agents`, so
  ## with two seats there are exactly TWO cert slots and `player[]` may
  ## therefore contain exactly those two ids and nothing else. bc24 adds no
  ## `player[]` entry at all; `PLAYER_SCRIPTED` resolves PER YEAR in
  ## `src/battlecode/baselines.nim`, so seating `awu` on a bc24 episode
  ## already plays Gone Sharkin'.
  checkEq("len(certification.players) == certification num_agents",
    cert["players"].len, cert["game_config"]["num_agents"].getInt())
  checkEq("player[] is exactly the two ids the fixture seats", declared,
    @["awu", "scaffold"])
  checkEq("and the certification fixture stays on bc26",
    cert["game_config"]["year"].getStr(), "bc26")
  for p in manifest["player"]:
    check(p["id"].getStr() & "'s description names its bc24 resolution",
      "bc24" in p["description"].getStr())

# --- no runner-managed tokens, and bounded arrays ---------------------------
proc walkArrays(node: JsonNode, path: string) =
  if node.kind == JObject:
    if node.hasKey("type") and node["type"].kind == JString and
        node["type"].getStr() == "array":
      check("array is bounded at " & path,
        node.hasKey("minItems") and node.hasKey("maxItems"))
    for key, value in node:
      walkArrays(value, path & "/" & key)
  elif node.kind == JArray:
    var i = 0
    for value in node.items:
      walkArrays(value, path & "/" & $i)
      inc i

walkArrays(game["config_schema"], "config_schema")
walkArrays(game["results_schema"], "results_schema")

block:
  check("config_schema forbids unknown keys",
    not game["config_schema"]["additionalProperties"].getBool())
  ## The runner INJECTS one connection token per seat into every episode's
  ## game_config, so the schema must DECLARE and REQUIRE them: `coworld
  ## certify` refuses a manifest whose config_schema does not
  ## ("game.config_schema must require tokens", 0.1.0, 2026-09-04).
  var required: seq[string]
  for v in game["config_schema"]["required"]:
    required.add(v.getStr())
  check("config_schema requires tokens", "tokens" in required)
  check("config_schema requires players", "players" in required)
  check("and declares a bounded tokens array",
    game["config_schema"]["properties"]["tokens"]["maxItems"].getInt() == 2)
  ## What must NOT carry tokens is the shipped VALUES: those are the runner's
  ## to supply at episode time, never the manifest's to pin.
  for variant in variants:
    check("no tokens in " & variant["id"].getStr() & "'s game_config",
      not variant["game_config"].hasKey("tokens"))
  check("no tokens in the certification game_config",
    not cert["game_config"].hasKey("tokens"))
  ## Every game_config key must be in the schema, or the platform rejects it.
  for variant in variants:
    for key, _ in variant["game_config"]:
      check("config_schema declares " & key,
        game["config_schema"]["properties"].hasKey(key))
  for key, _ in cert["game_config"]:
    check("config_schema declares the certification key " & key,
      game["config_schema"]["properties"].hasKey(key))

# --- protocols and docs are {type, value} objects ---------------------------
block:
  for key in ["player", "global"]:
    check("game.protocols has a " & key & " key",
      game["protocols"].hasKey(key))
    let node = game["protocols"][key]
    checkEq(key & " protocol is an object", node.kind, JObject)
    check(key & " protocol has type and value",
      node.hasKey("type") and node.hasKey("value"))
  let docs = game["docs"]
  checkEq("docs.readme is an object", docs["readme"].kind, JObject)
  check("docs.readme has type and value",
    docs["readme"].hasKey("type") and docs["readme"].hasKey("value"))
  checkEq("six doc pages ship — one rules page per year", docs["pages"].len, 6)
  var ids: seq[string]
  for page in docs["pages"]:
    ids.add(page["id"].getStr())
    check("page " & page["id"].getStr() & " has a title",
      page.hasKey("title"))
    checkEq("page content is an object", page["content"].kind, JObject)
    check("page content has type and value",
      page["content"].hasKey("type") and page["content"].hasKey("value"))
    ## Every referenced doc must actually exist in the tree.
    let target = "docs/" & page["id"].getStr().replace(".md", "").
      toUpperAscii() & ".md"
    check("the page's file exists: " & target, fileExists(target))
  checkEq("the pages are the ones the design note names", ids,
    @["rules.md", "rules-bc20.md", "rules-bc21.md", "rules-bc24.md",
      "replay.md", "parity.md"])

# --- the rest of the shape --------------------------------------------------
block:
  checkEq("game.name is the slug and the secret namespace",
    game["name"].getStr(), GameName)
  check("game.description is present", game["description"].getStr().len > 40)
  check("there is no game.tags", not game.hasKey("tags"))
  check("tags are top level", manifest.hasKey("tags"))
  check("with at least three", manifest["tags"].len >= 3)
  check("$schema is declared", manifest.hasKey("$schema"))
  checkEq("episode_timeout_minutes", manifest["episode_timeout_minutes"].getInt(), 20)
  checkEq("the game runnable type", game["runnable"]["type"].getStr(), "game")
  checkEq("the game entrypoint", game["runnable"]["run"][0].getStr(),
    "/bin/battlecode")
  checkEq("the game image lives on the runnable",
    game["runnable"]["image"].getStr(), "{{GAME_IMAGE}}")
  checkEq("the server-side LLM secret",
    game["runnable"]["env"]["ANTHROPIC_API_KEY_URI"].getStr(),
    "secret://coworld/battlecode/anthropic_api_key")
  checkEq("the replay viewer is the STATIC bundle",
    game["replay_viewer"]["bundle"].getStr(), "static-replay-viewer")
  ## Two declared baselines, both seated by the certification fixture, and
  ## `PLAYER_SCRIPTED` resolves each PER YEAR: on bc20 `awu` plays
  ## bowl-of-chowder and `scaffold` plays examplefuncsplayer
  ## (src/battlecode/baselines.nim). Declaring the bc20 names as extra player
  ## entries is what failed release 0.2.0 (`players_missing`).
  checkEq("both baselines are declared", manifest["player"].len, 2)
  var playerIds: seq[string]
  for p in manifest["player"]: playerIds.add(p["id"].getStr())
  checkEq("and they are the two the fixture seats", playerIds,
    @["awu", "scaffold"])
  for p in manifest["player"]:
    checkEq(p["id"].getStr() & " runs the player entrypoint",
      p["run"][0].getStr(), "/bin/battlecode-player")
    checkEq(p["id"].getStr() & " gets one cpu",
      p["resources"]["limits"]["cpu"].getStr(), "1")
    checkEq(p["id"].getStr() & " uses the player image",
      p["image"].getStr(), "{{PLAYER_IMAGE}}")
    checkEq(p["id"].getStr() & " is typed as a player",
      p["type"].getStr(), "player")

# --- the policy set ---------------------------------------------------------
block:
  let policies = parseJson(readFile("tools/ci/policies.json"))
  ## Four per year: two `PLAYER_PROMPT` champions and two scripted fillers.
  checkEq("sixteen policies ship — four per year", policies.len, 16)
  var prompts = 0
  var scripted = 0
  var owned = 0
  ## A policy is CUT FROM a docker image, and `upload-policy` can only cut
  ## from a tag `coworld build` actually produced — i.e. one compose.yaml
  ## declares. `cogame-battlecode:latest` is built by nothing and failed all
  ## four uploads (0.1.4, 2026-09-04).
  for p in policies:
    check("every policy runs the player entrypoint",
      p["run"].getStr() == "/bin/battlecode-player")
    check("and is cut from an image compose builds: " & p["image"].getStr(),
      p["image"].getStr() in compose)
    checkEq("which is the PLAYER image, since policies are players",
      p["image"].getStr(), "cogame-battlecode-player:latest")
    check("and is named for this game",
      p["name"].getStr().startsWith("battlecode-"))
    if p["env"].hasKey("PLAYER_PROMPT"):
      inc prompts
      check("a champion's prompt is substantial",
        p["env"]["PLAYER_PROMPT"].getStr().len > 200)
    if p["env"].hasKey("PLAYER_SCRIPTED"): inc scripted
    if p.hasKey("player"): inc owned
  checkEq("two LLM champions per year", prompts, 8)
  checkEq("two scripted baselines per year", scripted, 8)
  checkEq("each year's champion #2 carries its owning player", owned, 4)
  checkEq("bc26 champion #2 is the second prompt policy",
    policies[1]["player"].getStr(),
    "ply_bac48eb1-662e-44f8-973d-f3e016dccf5d")
  checkEq("bc20 champion #2 is the sixth policy",
    policies[5]["player"].getStr(),
    "ply_bac48eb1-662e-44f8-973d-f3e016dccf5d")
  check("the two bc26 champion prompts differ",
    policies[0]["env"]["PLAYER_PROMPT"].getStr() !=
    policies[1]["env"]["PLAYER_PROMPT"].getStr())
  check("the two bc20 champion prompts differ",
    policies[4]["env"]["PLAYER_PROMPT"].getStr() !=
    policies[5]["env"]["PLAYER_PROMPT"].getStr())
  checkEq("and the bc20 policies are named for the year",
    policies[4]["name"].getStr(), "battlecode-bc20-latticer")
  checkEq("bc20 champion #2 is the rusher",
    policies[5]["name"].getStr(), "battlecode-bc20-rusher")
  checkEq("the bc20 fillers name the two published chassis",
    policies[6]["env"]["PLAYER_SCRIPTED"].getStr() & "," &
    policies[7]["env"]["PLAYER_SCRIPTED"].getStr(),
    "bowl-of-chowder,examplefuncsplayer")
  checkEq("bc21 champion #1 is the turtle",
    policies[8]["name"].getStr(), "battlecode-bc21-turtle")
  checkEq("bc21 champion #2 is the muckraker rush",
    policies[9]["name"].getStr(), "battlecode-bc21-muckrush")
  checkEq("and bc21 champion #2 carries its owning player",
    policies[9]["player"].getStr(),
    "ply_bac48eb1-662e-44f8-973d-f3e016dccf5d")
  checkEq("bc24 champion #1 is the fortress",
    policies[12]["name"].getStr(), "battlecode-bc24-fortress")
  checkEq("bc24 champion #2 is the flag rush",
    policies[13]["name"].getStr(), "battlecode-bc24-flagrush")
  checkEq("and bc24 champion #2 carries its owning player",
    policies[13]["player"].getStr(),
    "ply_bac48eb1-662e-44f8-973d-f3e016dccf5d")
  check("the two bc24 champion prompts differ",
    policies[12]["env"]["PLAYER_PROMPT"].getStr() !=
    policies[13]["env"]["PLAYER_PROMPT"].getStr())
  checkEq("the bc24 fillers name the two published chassis",
    policies[14]["env"]["PLAYER_SCRIPTED"].getStr() & "," &
    policies[15]["env"]["PLAYER_SCRIPTED"].getStr(),
    "gone-sharkin,examplefuncsplayer24")
  check("and neither bc24 filler is a champion",
    not policies[14].hasKey("player") and not policies[15].hasKey("player"))
  check("the two bc21 champion prompts differ",
    policies[8]["env"]["PLAYER_PROMPT"].getStr() !=
    policies[9]["env"]["PLAYER_PROMPT"].getStr())
  check("bc21 champion #1 is the slanderer-turtle/eco pole",
    "slanderer_turtle" in policies[8]["env"]["PLAYER_PROMPT"].getStr())
  check("and champion #2 is the muckraker rush",
    "muck_spam" in policies[9]["env"]["PLAYER_PROMPT"].getStr())
  checkEq("the bc21 fillers name the two published chassis",
    policies[10]["env"]["PLAYER_SCRIPTED"].getStr() & "," &
    policies[11]["env"]["PLAYER_SCRIPTED"].getStr(),
    "california-roll,examplefuncsplayer21")

# --- compose.yaml service names are load-bearing ----------------------------
block:
  check("compose declares a `game` service", "\n  game:" in compose)
  check("compose declares a `player` service", "\n  player:" in compose)
  check("the game image matches the release image name",
    "cogame-battlecode-game:latest" in compose)
  ## The release workflow's default policy image must also be a tag compose
  ## builds, for a dispatch that overrides `policies` without naming one.
  let release = readFile(".github/workflows/coworld-release.yml")
  check("the release workflow defaults policies to the player image",
    "IMAGE: cogame-battlecode-player" in release)
  check("both are linux/amd64", compose.count("platform: linux/amd64") == 2)

# --- the CLI that publishes this manifest validates it in CI ----------------
block:
  ## The note's shard 12 asks for the installed coworld CLI's own
  ## `_load_template_manifest`/`validate_upload_manifest` over this template.
  ## A Nim shard cannot import a Python package, so the call lives in the
  ## `test` job and this asserts it is still wired — the two defects it found
  ## when it was first run (a missing `game.owner`, and `resources.limits.
  ## memory`, which CoworldResourceLimits forbids) are the exact class of
  ## failure that otherwise surfaces in `coworld certify`, one phase later.
  let workflow = readFile(".github/workflows/ci.yml")
  check("ci.yml runs the coworld CLI over the template",
    "The coworld CLI accepts the manifest template" in workflow)
  check("through _load_template_manifest itself",
    "from coworld.bundle import _load_template_manifest" in workflow)
  check("and the CLI pin is a real version",
    "coworld==0.1.4" in workflow)
  ## The two things it rejected, asserted here as well so a Nim-only run
  ## still catches them.
  check("game.owner is present", manifest["game"]{"owner"}.getStr().len > 0)
  for runnable in @[manifest["game"]["runnable"]] & toSeq(manifest["player"].items):
    let limits = runnable{"resources"}{"limits"}
    check("no runnable declares resources.limits.memory (cpu only)",
      limits == nil or limits{"memory"} == nil)

# --- the licence trail is complete ------------------------------------------
block:
  ## AGPL-3.0 means the credits are load-bearing, and README.md links to
  ## NOTICE — a link that pointed at nothing until r1-N11.
  check("NOTICE exists", fileExists("NOTICE"))
  let notice = readFile("NOTICE")
  for named in ["battlecode/battlecode26", "engine.1.2.5",
                "991c91af9c35db497f3508393cb6a6f5610725c0",
                "awu7/battlecode-2026", "final",
                "a70328eacaab18622cdac838f5e4e981c2a1f0cd",
                "AGPL-3.0"]:
    check("NOTICE names " & named, named in notice)
  check("and says no upstream Java runs in the image",
    "No upstream Java source runs in any image" in notice)
  check("README's NOTICE link has a target", "[`NOTICE`](NOTICE)" in
    readFile("README.md") and fileExists("NOTICE"))

# --- no JVM anywhere in the image -------------------------------------------
block:
  ## The banned words are looked for in the INSTRUCTIONS, with the comments
  ## stripped. The old form was `banned notin dockerfile or "no jdk" in
  ## dockerfile`, and Dockerfile:7 says "NO JDK, NO JRE, NO JAVA, NO NODE" —
  ## so the right-hand disjunct was true for every word and the check passed
  ## vacuously no matter what the image installed (r1-N13c).
  let dockerfile = readFile("Dockerfile")
  var instructions = ""
  for line in dockerfile.splitLines():
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#"): continue
    instructions.add(stripped.toLowerAscii() & "\n")
  check("the Dockerfile has instructions to check", instructions.len > 200)
  for banned in ["openjdk", "java", "jdk", "jre", "nodejs", "npm"]:
    check("the Dockerfile installs no " & banned, banned notin instructions)
  check("the runtime stage is debian slim", "FROM debian:bookworm-slim AS runtime" in dockerfile)
  check("and the player stage reuses it", "FROM runtime AS player" in dockerfile)

finish("test_manifest")
