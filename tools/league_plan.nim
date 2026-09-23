## Emit reviewable API payloads for independent year leagues. No network writes.
import std/[json, sets]
import battlecode/years/registry

proc buildLeaguePlan*(manifest: JsonNode): JsonNode =
  let variants = manifest["variants"]
  if manifest["game"]["name"].getStr() != "battlecode" or variants.len != Years.len:
    raise newException(ValueError, "expected the battlecode Coworld and every registered year")
  var seen = initHashSet[string]()
  result = newJArray()
  for variant in variants:
    let id = variant["id"].getStr()
    if not isRegisteredYear(id) or id in seen or yearSpec(id).id != id:
      raise newException(ValueError, "unknown or duplicate year variant: " & id)
    if variant["game_config"]["year"].getStr() != id:
      raise newException(ValueError, "variant and engine year disagree: " & id)
    seen.incl(id)
    result.add(%*{
      "seed_request": {
        "coworld_name": "battlecode",
        "league_key": id,
        "league_name": yearSpec(id).title,
        "default_variant_id": id,
        "template": "commissioner_driven",
        "overrides": {"commissioner_key": "platform"},
        "enabled": true
      },
      "settings_request": {
        "ladder": {
          "enabled": false,
          "scheduler": {"strategy": "round_robin", "variant_rotation": [id]},
          "divisions": []
        }
      }
    })

when isMainModule:
  echo pretty(buildLeaguePlan(parseJson(readFile("coworld_manifest_template.json"))))
