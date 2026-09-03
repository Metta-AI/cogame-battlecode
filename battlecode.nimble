version     = "0.1.0"
author      = "Softmax"
description = "Battlecode 2026 \"Uneasy Alliances\", played by doctrine: a deterministic Nim port of the official rule set with a sealed one-shot LLM doctrine per clan."
license     = "AGPL-3.0-only"

srcDir = "src"
bin    = @["battlecode", "battlecode_player"]

requires "nim >= 2.2.4"
requires "bitworld >= 0.1.0"
requires "pixie"
requires "mummy >= 0.4.7"
requires "curly >= 1.1.1"
requires "whisky >= 0.1.3"
requires "crunchy >= 0.1.11"
requires "supersnappy >= 2.1.3"
requires "jsony"
requires "flatty >= 0.3.4"
