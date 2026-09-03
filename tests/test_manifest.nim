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

let manifest = parseJson(readFile("coworld_manifest_template.json"))
let game = manifest["game"]

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

  var gameKeys: seq[string]
  for v in game["results_schema"]["properties"]["games"]["items"]["required"]:
    gameKeys.add(v.getStr())
  var expectedGameKeys = @GameKeys
  gameKeys.sort()
  expectedGameKeys.sort()
  checkEq("the per-game key set matches too", gameKeys, expectedGameKeys)

block:
  ## The third leg: what docker_smoke.sh actually asserts.
  let smoke = readFile("tools/ci/docker_smoke.sh")
  for key in ResultsKeys:
    check("docker_smoke.sh checks results key " & key,
      "\"" & key & "\"" in smoke or "'" & key & "'" in smoke or
      key & "'" in smoke)

# --- num_agents -------------------------------------------------------------
block:
  checkEq("exactly one variant ships in v1", game["variants"].len, 1)
  for variant in game["variants"]:
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

  let cert = game["certification"]
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
  for p in cert["players"]:
    check("certification seats a DECLARED player: " & p["player_id"].getStr(),
      p["player_id"].getStr() in declared)

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
  check("config_schema has no tokens property",
    not game["config_schema"]["properties"].hasKey("tokens"))
  for variant in game["variants"]:
    check("no tokens in " & variant["id"].getStr() & "'s game_config",
      not variant["game_config"].hasKey("tokens"))
  check("no tokens in the certification game_config",
    not game["certification"]["game_config"].hasKey("tokens"))
  ## Every game_config key must be in the schema, or the platform rejects it.
  for variant in game["variants"]:
    for key, _ in variant["game_config"]:
      check("config_schema declares " & key,
        game["config_schema"]["properties"].hasKey(key))
  for key, _ in game["certification"]["game_config"]:
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
  checkEq("three doc pages ship", docs["pages"].len, 3)
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
    @["rules.md", "replay.md", "parity.md"])

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
  checkEq("the server-side LLM secret",
    game["runnable"]["env"]["ANTHROPIC_API_KEY_URI"].getStr(),
    "secret://coworld/battlecode/anthropic_api_key")
  checkEq("the replay viewer is the STATIC bundle",
    game["replay_viewer"]["bundle"].getStr(), "static-replay-viewer")
  checkEq("both players are declared", manifest["player"].len, 2)
  for p in manifest["player"]:
    checkEq(p["id"].getStr() & " runs the player entrypoint",
      p["runnable"]["run"][0].getStr(), "/bin/battlecode-player")
    checkEq(p["id"].getStr() & " gets one cpu",
      p["runnable"]["resources"]["limits"]["cpu"].getStr(), "1")
    checkEq(p["id"].getStr() & " uses the player image",
      p["image"].getStr(), "{{PLAYER_IMAGE}}")
  checkEq("the game uses the game image", game["image"].getStr(),
    "{{GAME_IMAGE}}")

# --- the policy set ---------------------------------------------------------
block:
  let policies = parseJson(readFile("tools/ci/policies.json"))
  checkEq("four policies ship", policies.len, 4)
  var prompts = 0
  var scripted = 0
  var owned = 0
  for p in policies:
    check("every policy runs the player entrypoint",
      p["run"].getStr() == "/bin/battlecode-player")
    check("and is named for this game",
      p["name"].getStr().startsWith("battlecode-"))
    if p["env"].hasKey("PLAYER_PROMPT"):
      inc prompts
      check("a champion's prompt is substantial",
        p["env"]["PLAYER_PROMPT"].getStr().len > 200)
    if p["env"].hasKey("PLAYER_SCRIPTED"): inc scripted
    if p.hasKey("player"): inc owned
  checkEq("two LLM champions", prompts, 2)
  checkEq("two scripted baselines", scripted, 2)
  checkEq("champion #2 carries its owning player", owned, 1)
  checkEq("and it is the second prompt policy",
    policies[1]["player"].getStr(),
    "ply_bac48eb1-662e-44f8-973d-f3e016dccf5d")
  check("the two champion prompts differ",
    policies[0]["env"]["PLAYER_PROMPT"].getStr() !=
    policies[1]["env"]["PLAYER_PROMPT"].getStr())

# --- compose.yaml service names are load-bearing ----------------------------
block:
  let compose = readFile("compose.yaml")
  check("compose declares a `game` service", "\n  game:" in compose)
  check("compose declares a `player` service", "\n  player:" in compose)
  check("the game image matches the release image name",
    "cogame-battlecode-game:latest" in compose)
  check("both are linux/amd64", compose.count("platform: linux/amd64") == 2)

# --- no JVM anywhere in the image -------------------------------------------
block:
  let dockerfile = readFile("Dockerfile")
  for banned in ["openjdk", "java", "jdk", "jre", "nodejs", "npm"]:
    check("the Dockerfile installs no " & banned,
      banned notin dockerfile.toLowerAscii().replace("java engine exists", "") or
      "no jdk" in dockerfile.toLowerAscii())
  check("the runtime stage is debian slim", "FROM debian:bookworm-slim AS runtime" in dockerfile)
  check("and the player stage reuses it", "FROM runtime AS player" in dockerfile)

finish("test_manifest")
