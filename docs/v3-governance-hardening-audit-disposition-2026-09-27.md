> **HISTORICAL AUDIT DISPOSITION.** This audit closed the earlier release-v1 / launcher-v3 cycle. Current canonical v3 is the weekF12 release `5472d089…da853b` with launcher v5 and API v3. See `docs/v3-current-canonical-stack-2026-09-28.md`.

# V3 governance hardening pre-implementation audit disposition

Date: 2026-09-27
Auditor: Jax / GPT-5.6 Sol / High reasoning
Verdict: APPROVE WITH FIXES

The plan in `docs/v3-governance-hardening-plan-2026-09-27.md` is approved for implementation only after the following requirements are incorporated. These requirements are binding for the implementation and final audit.

## Required fixes incorporated

1. **Non-circular release identity**
   - Canonical payload is UTF-8/LF text with one line per bound file: `role<TAB>repo_relative_path<TAB>sha256<TAB>size_bytes`.
   - Rows sort lexicographically by `(role, path)`.
   - Duplicate `(role,path)` rows and duplicate normative roles that are declared singular are rejected.
   - Symlinks are rejected for bound release inputs.
   - `release_id = SHA256(canonical_payload_bytes)`.
   - `release_metadata.csv`, timestamps, Git diagnostics, release output files, and `release_id.txt` are excluded from the release-ID payload.
   - Build in a temporary directory and publish atomically to `artifacts/v3-shadow-release-v1/<release_id>/` only after validation.

2. **Complete source/runtime closure**
   - Bind all normative policy sources, builders, runners, runtime helpers, release validator/launcher, canonical inventory, runtime contracts, focused acceptance tests, and every current `PAGe/R/*.R` dynamically sourced by the runners.
   - Runtime preflight checks exact set equality between the bound `PAGe/R/*.R` paths and the current source directory; unexpected as well as missing/changed files fail preflight.
   - Record R version plus versions of directly used runtime packages (`digest`, `mgcv`, and package dependencies actually loaded by the runners).

3. **Eligibility lineage**
   - Timing-contract v3 source manifest binds its generator, all inputs, and all generated outputs (with the manifest itself excluded from its own circular hash set).
   - Eligibility schema includes explicit M1-B and M2-B training/scoring/timing eligibility fields.
   - Coverage must be unique and exhaustive over canonical seasons; booleans must be strict TRUE/FALSE; exclusions and finite timing truth must satisfy component-specific invariants.

4. **Behavior equivalence, not hash-only equivalence**
   - M1-B v9 must preserve the accepted v8 fitted library hash and compare peak and passage posterior outputs on fixed historical origins to numerical tolerance.
   - M2-B shadow-v3 must preserve accepted shadow-v2 state coefficients, shape grid, constants, routes, lower-bound diagnostics and fixture predictions. Re-fitting is allowed only if the resulting payload is proven numerically equivalent; copying the accepted payload is preferred.
   - Equivalence fixtures cover pre-window, active posterior-C2, no-timing fallback, lower-bound-saturated, +1 and +2 paths.
   - Artifact IDs include every behavior-affecting field and are recomputed by validators.

5. **Pure typed-panel validation**
   - Typed-panel validation never repairs/recomputes supplied fields silently.
   - Reject `p_A != y_A/N_A` or `p_B != y_B/N_B` outside tolerance.
   - Reject duplicate, non-integer, or gapped `weekF` and invalid/misaligned dates.
   - Add a golden test proving v2 default ingestion and v2 typed-panel replay produce identical effective panels and predictions.

6. **Separate source and panel identities**
   - Provenance records archived raw-source SHA, supplied typed-panel byte SHA, canonical effective-panel SHA, season/origin, and validated release ID separately.
   - Official v2 and v3 comparison children must record the same effective-panel SHA and release ID.

7. **Authoritative atomic launcher**
   - `2026/run_weekly_shadow_release_v3.R` is the only path allowed to emit official `v2_v3_comparison.csv`.
   - Resolve raw source once, build typed panel once, stage both child runs under a pending transaction, and publish the transaction only after both succeed and agree on season/origin/effective-panel SHA/release ID.
   - Failed transactions may leave a failure receipt outside the publishable final directory but must not leave an official comparison artifact.

8. **Build release last**
   - Release bundle is built only after policy, timing contract, M1-B v9, M2-B v3, runners, launcher, tests, inventory and master-plan cleanup are final because all are bound into the release.

## Audit interpretation

The audit agreed that a Git-independent content-addressed release ID can replace the stale Git HEAD as the authoritative v3 runtime identity **if and only if** the manifest definition above is exact and runtime preflight validates the full closure. Git HEAD and dirty state remain diagnostic metadata only until a commit is explicitly requested.

No model selection, tuning, thresholds, or routing decisions are reopened by this hardening cycle.
