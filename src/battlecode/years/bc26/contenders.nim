## Source-informed BC26 adaptations. Exact custody and limits: docs/PLAYERS-BC26.md.
type
  Contender26* = enum
    ctProofOfConcept
    ctSpaark2026
    ctGravy
    ctPowerpuffGirls
    ctComplexMerlin
    ctTspaark
    ctOldButGold

const
  ContenderNames26* = [ "proof-of-concept-2026", "spaark-2026", "gravy-2026", "powerpuff-girls-2026", "complex-merlin-2026", "tspaark-2026", "old-but-gold-2026" ]
  ContenderLabels26* = [ "ProofOfConcept (Nim)", "SPAARK (Nim)", "Gravy (Nim)", "Powerpuff Girls (Nim)", "The Complex Merlin (Nim)", "TSPAARK (Nim)", "Old But Gold (Nim)" ]
  ContenderReplies26*: array[Contender26, string] = [
    """{"sheet":{"backstab_policy":"retaliate_only","backstab_round":600,"cat_engagement":"avoid","cat_trap_budget":40,"rat_trap_budget":40,"spawn_curve":"lean","cheese_ferry_ratio":0.9,"king_count_target":1,"dirt_wall_policy":"none","throw_rats_to_feed_cats":false},"notes":"ProofOfConcept result_408 king-economy adaptation only; neural baby-rat policy is not reproduced.","motto":"ProofOfConcept economy."}""",
    """{"sheet":{"backstab_policy":"on_first_contact","backstab_round":600,"cat_engagement":"hunt","cat_trap_budget":40,"rat_trap_budget":40,"spawn_curve":"steady","cheese_ferry_ratio":0.5,"king_count_target":3,"dirt_wall_policy":"none","throw_rats_to_feed_cats":false},"notes":"SPAARK source-informed king economy; shared native navigation and combat. Not a full Java port.","motto":"SPAARK economy."}""",
    """{"sheet":{"backstab_policy":"retaliate_only","backstab_round":600,"cat_engagement":"opportunistic","cat_trap_budget":40,"rat_trap_budget":40,"spawn_curve":"steady","cheese_ferry_ratio":0.8,"king_count_target":2,"dirt_wall_policy":"king_shell","throw_rats_to_feed_cats":false},"notes":"Gravy source-informed king economy; shared native navigation and combat. Not a full Java port.","motto":"Gravy economy."}""",
    """{"sheet":{"backstab_policy":"on_first_contact","backstab_round":600,"cat_engagement":"hunt","cat_trap_budget":40,"rat_trap_budget":40,"spawn_curve":"swarm","cheese_ferry_ratio":0.55,"king_count_target":3,"dirt_wall_policy":"none","throw_rats_to_feed_cats":false},"notes":"Powerpuff Girls source-informed king economy; shared native navigation and combat. Not a full Java port.","motto":"Powerpuff Girls economy."}""",
    """{"sheet":{"backstab_policy":"on_first_contact","backstab_round":600,"cat_engagement":"hunt","cat_trap_budget":40,"rat_trap_budget":40,"spawn_curve":"steady","cheese_ferry_ratio":0.6,"king_count_target":4,"dirt_wall_policy":"choke","throw_rats_to_feed_cats":false},"notes":"The Complex Merlin source-informed king economy; shared native navigation and combat. Not a full Java port.","motto":"The Complex Merlin economy."}""",
    """{"sheet":{"backstab_policy":"on_first_contact","backstab_round":600,"cat_engagement":"opportunistic","cat_trap_budget":40,"rat_trap_budget":40,"spawn_curve":"lean","cheese_ferry_ratio":0.7,"king_count_target":2,"dirt_wall_policy":"king_shell","throw_rats_to_feed_cats":false},"notes":"TSPAARK source-informed king economy; shared native navigation and combat. Not a full Java port.","motto":"TSPAARK economy."}""",
    """{"sheet":{"backstab_policy":"retaliate_only","backstab_round":600,"cat_engagement":"opportunistic","cat_trap_budget":40,"rat_trap_budget":40,"spawn_curve":"steady","cheese_ferry_ratio":0.85,"king_count_target":3,"dirt_wall_policy":"king_shell","throw_rats_to_feed_cats":false},"notes":"Old But Gold source-informed king economy; shared native navigation and combat. Not a full Java port.","motto":"Old But Gold economy."}"""
  ]
