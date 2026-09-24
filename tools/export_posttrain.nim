## Export full native Battlecode matches as Metta post-training examples.
## nim c -d:release --path:src -o:/tmp/battlecode-posttrain tools/export_posttrain.nim

import std/[json, os, osproc, strutils]
import battlecode/[server, decide, match, sheet, baselines, llm]

when isMainModule:
  let args = commandLineParams()
  if args.len != 3:
    quit("usage: battlecode-posttrain OUTPUT EPISODES VARIANT", 1)
  let output = args[0]
  let episodes = parseInt(args[1])
  let variant = args[2]
  if episodes < 10:
    quit("at least ten games are required", 1)
  if dirExists(output) or fileExists(output):
    quit("output already exists: " & output, 1)
  let manifest = parseFile("coworld_manifest_template.json")
  var variantConfig = newJNull()
  for entry in manifest["variants"]:
    if entry["id"].getStr() == variant:
      variantConfig = copy(entry["game_config"])
  doAssert variantConfig.kind == JObject
  createDir(output)
  let revision = execProcess("git rev-parse HEAD").strip()
  var
    trainRows: seq[string]
    validationRows: seq[string]
    runs = newJArray()
  for seed in 1 .. episodes:
    variantConfig["seed"] = %seed
    let config = parseConfig($variantConfig)
    let teacher = defaultBaselineFor(config.year)
    let reply = baselineReply(teacher)
    let accepted = parseReply(reply, config.year)
    var plan = buildPlan(config, [defaultSheet(config.year),
                                  defaultSheet(config.year)], seed)
    plan.sheets = [accepted, accepted]
    var rows: seq[string]
    for slot in 0 .. 1:
      let brief = briefFor(config, plan, slot)
      rows.add($(%*{
        "episode_id": "battlecode-" & variant & "-" & $seed,
        "seed": "battlecode-" & variant & "-" & $seed,
        "decision_id": slot,
        "prompt": [
          {"role": "system", "content": preambleFor(config.year)},
          {"role": "user", "content": userMessage("", brief)}
        ],
        "completion": [{"role": "assistant", "content": reply}],
        "game": "battlecode",
        "action_schema_revision": "battlecode-doctrine-" & config.year
      }))
    var events: seq[MatchEvent]
    let (games, reason) = playMatch(config, plan, events)
    doAssert reason == epComplete and games.len > 0
    let scores = scoresFor(games, config.year)
    if seed mod 5 == 0:
      validationRows.add(rows)
    else:
      trainRows.add(rows)
    runs.add(%*{"seed": seed, "games": games.len,
      "scores": [scores[0], scores[1]]})
  writeFile(output / "train.jsonl", trainRows.join("\n") & "\n")
  writeFile(output / "validation.jsonl", validationRows.join("\n") & "\n")
  writeFile(output / "manifest.json", pretty(%*{
    "schema_version": 1,
    "game": "battlecode",
    "variant": variant,
    "source_revision": revision,
    "teacher": baselineName(defaultBaselineFor(variant)),
    "train_examples": trainRows.len,
    "validation_examples": validationRows.len,
    "runs": runs
  }) & "\n")
  echo "train=", trainRows.len, " validation=", validationRows.len
