# Competitor fidelity audit

Coleman's objection is correct. This Coworld's named archive adaptations do
not execute the archived competitors. Their standings cannot support a claim
that Softmax policies match the original MIT Battlecode champions.

## What actually runs

`battlecode_player.nim` sends one registration, containing either a prompt or a
scripted selector. It never receives robot observations or chooses robot actions.
The game runs the entire match using its own controllers.

For 2025, `chassis/contenders25.nim` distinguishes tower production, targeting,
some soldier priorities, and refill behavior. Every contender's moppers call
the same `runMopper`; every splasher calls the same `runSplasher`. Movement,
exploration, ruin construction, resource patterns, and messaging use shared
native code. This is an architectural substitution, not a broken source loader.

For 2026, `chassis/contenders26.nim` adapts king production predicates. Every
baby rat calls the same `runRat`. The archived neural and tactical controllers
are not in that execution path.

## Concrete source discrepancies

| Entry | Original behavior omitted by the adaptation | Evidence |
| --- | --- | --- |
| Om Nom, 2025 | Tower demolition and rebuilding for paint; template-generated navigation, tactical attacks, symmetry inference, and communications | [`Tower.java.jinja2`](https://github.com/battlecode-archive/2025-Om-Nom/blob/bc2f945b13c78cfaf8331f59fabcd7e16d53c71f/templates/Tower.java.jinja2) checks farm patterns and nearby robots before `rc.disintegrate()`. [`RobotPlayer.java.jinja2`](https://github.com/battlecode-archive/2025-Om-Nom/blob/bc2f945b13c78cfaf8331f59fabcd7e16d53c71f/templates/RobotPlayer.java.jinja2) invokes the omitted subsystems every turn. |
| confused, 2025 | Soldier state transitions, tower flickering, per-unit navigation, and its own mopper/splasher micro | [`Soldier.java`](https://github.com/battlecode-archive/2025-confused/blob/bb21870cec74c9991c6a880cead3b24e5c0c7ac9/java/src/finals/Soldier.java) implements distinct DEFAULT, FLICKER, ATTACK, REFILL, and BUILD_TOWER behavior. |
| SPAARK, 2025 | Generated movement and combat, robot state machines, and points-of-interest communications | [`src/SPAARK`](https://github.com/battlecode-archive/2025-SPAARK/tree/63165da768ad1e087e3f8e4f6ee84e1a51d3a014/src/SPAARK) includes MotionCodeGen, Mopper, Splasher, Soldier, and POI implementations that the shared controller does not execute. |
| ProofOfConcept, 2026 | Learned movement and action networks, encoders, and rat decision-making | [`result_408/RobotPlayer.java`](https://github.com/battlecode-archive/2026-ProofOfConcept/blob/efcfcdc9b2394d120c2245c7234725fe7af86814/battlecode26/src/result_408/RobotPlayer.java) runs `runBabyRat`, neural encoders, `chooseAction`, and `chooseMove`. The adaptation runs none of those. |
| Other 2026 entries | Baby-rat tactics, navigation, carrying, combat, and team communications | Each source directory is pinned in [PLAYERS-BC26.md](PLAYERS-BC26.md). Their native adaptation dispatches baby rats to one shared implementation. |

No source-line coverage percentage is claimed. Generated source size does not
measure strategic importance. The missing execution paths establish the
comparison problem directly.

## What the existing tests prove

Engine parity tests compare rules or the example player against selected Java
scenarios. They do not compare the named champion controllers with their originals.
Contender tests establish distinct native trajectories and legal execution.
Neither test suite certifies equivalent tactics or playing strength.

Native shared team memory and `DecisionOps` also differ from Battlecode's
per-robot memory, explicit communications, and Java bytecode scheduling.
Changing production ratios cannot restore those semantics.

## Repairs

The existing Coworld remains a doctrine game. Its public description, player
labels, replay labels, and release rosters explicitly call the entries
**strategy adaptations** or **king economy adaptations**. Historical results
remain observations about those adaptations; they are not rescored as original
competitor matches.

Release relabeling checks the registered player IDs against the release account's
owned identities, renames those identities, and verifies readback before policy
resolution. It preserves leaderboard membership and history instead of creating
eleven replacement players. A missing owner, independent rename, disabled player,
or name collision stops the release before its first rename.

The release's explicit `submit_contenders` option promotes exact uploaded policy
versions under those registered identities. It checks ownership and current
champions first, records a submission ledger, avoids duplicate submissions,
and verifies unchanged league rosters and unrelated champions after placement.

The [official runner](../tools/official/README.md) compiles complete pinned archive
source directories and executes them using the published 2025/2026 engines.
Om Nom uses its own Jinja generator in production mode; ProofOfConcept includes
its generated neural code. No robot controller is translated or substituted.
The observer records telemetry and official replay bytes; upstream chooses
the winner and enforces the original bytecode execution model.

An archive is not necessarily the exact tournament submission. In particular,
Just Woke Up's selected version and ProofOfConcept's experiment have no independently
verified final artifact identity. Preserve that qualification even when their
complete source executes. Engine versions and map pools also affect comparisons.

The separate `battlecode-2025-archives` and `battlecode-2026-archives` Coworlds
use game-hosted JSON selectors for these complete implementations. They share
neither player artifacts nor rankings with the doctrine game. They support
these pinned archives, not arbitrary new
competitor submissions. Nine licensed archives are distributed; SPAARK 2026
and Old But Gold remain local audit targets because their pinned revisions lack
license files. The observer replay exposes units and economy; the local
runner also retains the full official-client replay.

## Live verification — 2026-09-28

The doctrine Coworld is certified and canonical at **0.11.10**. All eleven
adaptation policies are active at **v2**, under their original registered player
IDs. The BC25 and BC26 leagues retain 10 and 14 active champions, respectively;
unrelated champions and both player rosters are preserved.

Both complete-archive Coworlds are certified and canonical at **0.1.1**. Hosted
confused versus Om Nom completed 322 rounds; ProofOfConcept versus Gravy completed
236 rounds. All nine distributed archives also passed complete container
episodes from both seats. These are execution checks, not strength estimates.

The initial archive release passed matches but failed hosted replay loading.
The corrected release loads hosted HTTP/HTTPS artifacts and gates full
certification. Exact IDs, policy versions, submissions, source commits, hosted
match telemetry, and distribution limits are in
[the verification receipt](fidelity-release-verification.json).

## Recommended external correction

“Coleman is right: our displayed entries were partial strategy adaptations,
not the original Battlecode submissions. They omitted substantial navigation,
combat, communications, and learned behavior. Those standings do not establish
parity with past champions. We are labeling the adaptations explicitly and
adding execution of complete archived bots on the official engines.”
