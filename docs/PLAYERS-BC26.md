# 2026 archive adaptations

Seven separately named scripted players are intended for **Battlecode 2026 —
Uneasy Alliances** (`bc26`) only. They use individual player identities and
immutable policy versions. Account identity is global; their league submissions
are restricted to the 2026 league. They do not replace the existing `awu` or
`scaffold` controllers.

These are **king-economy adaptations, not full functional duplicates** of the
archived bots. Each has a distinct production policy, a separately recorded
controller ID and an explicit native doctrine. Navigation, baby-rat combat,
mining, carrying, formation, traps, dirt and communications reuse the native
chassis. The doctrine settings are adaptation choices, not upstream constants.
No tournament ranking or equivalent playing strength is claimed.

ProofOfConcept needs particular care: its archive contains generated neural
policies and experiments without a clearly identified final submission. This
entry adapts only `result_408`'s hand-written king production rule. **Its neural
baby-rat policy is not implemented**, and the experiment's round-1200 resignation
is not reproduced. Its display name and policy notes identify this limitation.

## Source custody

| Team | Revision and source directory | Selected production behavior |
| --- | --- | --- |
| ProofOfConcept | [`efcfcdc`](https://github.com/battlecode-archive/2026-ProofOfConcept/tree/efcfcdc9b2394d120c2245c7234725fe7af86814/battlecode26/src/result_408) | Four-turn cheese-rate sample and 2,000-cheese-per-king breeding reserve; no neural inference |
| SPAARK | [`a164312`](https://github.com/battlecode-archive/2026-SPAARK/tree/a16431207623fa18c30e29b1ddf01e43276f31a1/src/SPAARK) | Rolling cost history, dynamic cheese reserve, early cost ceiling, nearby-threat bonus |
| Gravy | [`f9c268a`](https://github.com/battlecode-archive/2026-Gravy/tree/f9c268abc53d235b09a767c407300ecdad66bfbf/src/testplayer) | Cost-dependent reserves, phase ceilings at 150/400, 400-cheese late reserve from round 1900 |
| Powerpuff Girls | [`91fdddb`](https://github.com/battlecode-archive/2026-Powerpuff-Girls/tree/91fdddbb1c015a2e8cd7ebcb8eebc8319b7ce06d/src/Finals) | Opening population cap, six cheese bands, rolling income gate scaled by king count |
| The Complex Merlin | [`76fe387`](https://github.com/battlecode-archive/2026-The-Complex-Merlin/tree/76fe3873ccf6bad4510ca151f6415ffb6629de18/java/src/TheComplexMerlin) | Opening exception, cheap-rat reserve ladder, time/mine-gated expansion and 100-cost ceiling |
| TSPAARK | [`64c3257`](https://github.com/battlecode-archive/2026-TSPAARK/tree/64c3257a929f52c9824e60a330a7acf5a3670ef1/src/Delta) | Bank-dependent population targets plus bonuses for kings and discovered mines |
| Old But Gold | [`70b3f40`](https://github.com/battlecode-archive/2026-Old-But-Gold/tree/70b3f40cebefcca9dc858771715d78088e7ae520/basic51) | Five-times-rat-cost reserve and a 2,100-cheese reserve that decreases with round number |

TSPAARK's README explicitly identifies Delta as its final submitted bot. Merlin's
README names its implementation. The other directories are selected archived
implementations; final tournament artifact identity is not independently proven.

Production predicates are adapted separately in `chassis/contenders26.nim`.
The rolling histories are private to each king and reset for each game. Mine
counts use that king's observed mines; upstream messaging and map-symmetry
inference are not reproduced. King fleeing and collecting use native pathing.
Spawn locations, exact target tie-breaking, emergency state machines, Java
bytecode interruption, neural networks and learned parameters are not ported.

## Registration and validation

`tools/ci/bc26-contender-policies.json` is the explicit seven-player roster.
Names end in `-2026`, including `spaark-2026` to distinguish it from the 2025
SPAARK entry. Unknown or wrong-year names keep the existing fallback behavior;
these containers are intended to be submitted only to `bc26`.

Release with this roster and `elevated_players=true` for first-time provisioning.
The helper reuses exact owned names and raises only the release account's league
player allowance enough to preserve every existing identity. Build, certify and
upload game and player images together, confirm the game version is canonical,
then submit each exact version as its matching player to the live `bc26` league.
Read back each player's submissions and memberships across all leagues to prove
that none entered `bc25` or another year.

The contender tests cover source-derived production boundaries, distinct
registration, legal complete games from both seats, deterministic memory and
seven distinct trajectories. Replay tests serialize and rederive each controller
with matching per-round hashes. Container smoke checks exercise every selector
through actual player registration and require complete games without fallback.
These tests establish native operation; they do not establish Java equivalence.
