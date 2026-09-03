## `/bin/battlecode` — the game container entrypoint.
##
## Exit codes follow coworld-ctf: 0 whenever results + replay were attempted
## (including `deadline` and `fault`), 2 on an invalid config.

import std/os
import bitworld/runtime
import battlecode/[server, sim_types]

when isMainModule:
  let runtimeConfig = readRuntimeConfig()
  var config: GameConfig
  try:
    config = parseConfig(runtimeConfig.config)
  except ConfigError as error:
    echo "::error::battlecode: invalid game_config: ", error.msg
    quit(2)
  echo "battlecode config: year=", config.year, " pool=", config.pool,
    " seed=", config.seed, " games=", config.gamesPerMatch,
    " maxRounds=", config.maxRounds, " num_agents=", config.numAgents,
    " matchBudget=", config.matchBudgetSeconds, "s"
  runServer(runtimeConfig, config)
  quit(0)
