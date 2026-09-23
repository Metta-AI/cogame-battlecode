## Named 2025 strategy adaptations. Provenance and fidelity limits are in
## docs/PLAYERS-BC25.md; these are not executions of the Java submissions.
type
  Contender25* = enum
    ctConfused, ctJustWokeUp, ctOmNom, ctSpaark

const
  ContenderNames25* = ["confused", "just-woke-up", "om-nom", "spaark-2025"]
  ContenderLabels25* = ["confused (Nim)", "Just Woke Up (Nim)",
                        "Om Nom (Nim)", "SPAARK (Nim)"]
  ContenderReplies25*: array[Contender25, string] = [
    """{"sheet":{"opening":"tower_rush","srp_priority":35,
      "paint_reserve_floor":25,"ruin_claim_radius":20,
      "splash_targets":"towers","upgrade_policy":"defense_first"},
      "notes":"confused strategy adaptation; native Nim controller",
      "motto":"Expand, defend, then splash."}""",
    """{"sheet":{"opening":"tower_rush","srp_priority":55,
      "paint_reserve_floor":25,"ruin_claim_radius":20,
      "splash_targets":"mixed","upgrade_policy":"paint_first"},
      "notes":"Just Woke Up strategy adaptation; native Nim controller",
      "motto":"Build, refill, return."}""",
    """{"sheet":{"opening":"balanced","srp_priority":70,
      "paint_reserve_floor":25,"ruin_claim_radius":16,
      "splash_targets":"territory","upgrade_policy":"paint_first",
      "defense_tower_chokes":"never"},
      "notes":"Om Nom strategy adaptation; native Nim controller",
      "motto":"Grow the paint economy."}""",
    """{"sheet":{"opening":"balanced","srp_priority":60,
      "paint_reserve_floor":30,"ruin_claim_radius":20,
      "splash_targets":"mixed","upgrade_policy":"money_first"},
      "notes":"SPAARK 2025 strategy adaptation; native Nim controller",
      "motto":"Balance production, expand patterns."}"""
  ]
