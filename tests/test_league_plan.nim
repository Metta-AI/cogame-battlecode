## Year leagues must never default or rotate into another year's engine.
import std/[json, sets]
import harness
import ../tools/league_plan
import battlecode/years/registry

let manifest = parseJson(readFile("coworld_manifest_template.json"))
let plan = buildLeaguePlan(manifest)
checkEq("one independent league per registered year", plan.len, Years.len)
var keys = initHashSet[string]()
for entry in plan:
  let seed = entry["seed_request"]
  let id = seed["default_variant_id"].getStr()
  keys.incl(seed["league_key"].getStr())
  checkEq("same Coworld", seed["coworld_name"].getStr(), "battlecode")
  checkEq("league key pins its year", seed["league_key"].getStr(), id)
  checkEq("year-specific name", seed["league_name"].getStr(), yearSpec(id).title)
  checkEq("platform scheduler", seed["overrides"]["commissioner_key"].getStr(), "platform")
  let ladder = entry["settings_request"]["ladder"]
  check("scheduling remains paused for setup", not ladder["enabled"].getBool())
  checkEq("no cross-year rotation", ladder["scheduler"]["variant_rotation"], %*[id])
checkEq("independent league keys", keys.len, Years.len)
for year in Years:
  check("registered year has a league", year.id in keys)

block:
  let changed = parseJson($manifest)
  changed["variants"][0]["game_config"]["year"] = %"bc25"
  doAssertRaises(ValueError):
    discard buildLeaguePlan(changed)
block:
  let changed = parseJson($manifest)
  changed["variants"].elems[1] = changed["variants"][0]
  doAssertRaises(ValueError):
    discard buildLeaguePlan(changed)
block:
  let changed = parseJson($manifest)
  changed["variants"].elems.setLen(Years.len - 1)
  doAssertRaises(ValueError):
    discard buildLeaguePlan(changed)
finish("test_league_plan")
