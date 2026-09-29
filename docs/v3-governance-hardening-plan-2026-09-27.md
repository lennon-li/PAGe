> **HISTORICAL GOVERNANCE PLAN.** This document describes the earlier release-v1 / launcher-v3 hardening cycle. Current canonical v3 uses weekF12, launcher v5, release `5472d089…da853b`, and API v3. See `docs/v3-current-canonical-stack-2026-09-28.md`.

# PAGe v3 governance hardening and release plan

Date: 2026-09-27
Status: pre-implementation plan for independent audit
Scope: governance/reproducibility/weekly issuance only; no model retuning or metric re-selection

## Objective

Close the eight governance/orchestration findings from the focused GPT-5.6 Sol / High audits without changing the accepted v3 statistical decisions:

- M1-A remains frozen M1-v2;
- M1-B remains B-only peak-location / continuous timing posterior, with 2018-19 no-event and 2019-20 pandemic-transition exclusion;
- M2-A remains exact A1 for +1/+2;
- M2-B remains exact B1 for +1 and posterior-C2-if-causal-timing-available-else-B1 for +2;
- all v3 outputs remain shadow-only / non-production.

The hardening target is a content-addressed, deterministic v3 shadow release that can detect source/policy/code drift before live data are read and that can issue v2 and v3 from one archived surveillance vintage.

## Findings to close

1. M1-B policy/provenance drift: v8 hashes an older B season-policy document state.
2. `modeling_eligibility_v3.csv` lacks a deterministic source/generator lineage.
3. M1-B v8 has no stable `artifact_id` even though runtime provenance tries to record one.
4. v3 executable/docs/tests are not represented by the recorded Git HEAD; `git_head=f982746` is therefore not a valid v3 release identity.
5. Standalone M2-B runner accepts gapped `weekF` panels although its growth features require contiguous weeks.
6. Runtime executable hash closure is incomplete: runners source the whole `PAGe/R/*.R` tree but release manifests do not pin the full code closure.
7. v2 and v3 runners may independently resolve/download different source vintages.
8. Master-plan and artifact lineage contain stale/superseded references that can confuse governance.

## Governing release identity

Do **not** treat Git HEAD as the v3 release identity for this hardening cycle. The user has not requested a commit, and private/generated artifacts are intentionally not committed under `docs/artifact-storage.md`.

Instead create a deterministic content-addressed release bundle:

`artifacts/v3-shadow-release-v1/<release_id>/`

with:

- `release_manifest.tsv` — every executable source, policy source, runtime helper, runner, frozen model artifact and canonical evidence object required for issuance;
- `code_manifest.csv` — complete sorted SHA-256 closure of every `PAGe/R/*.R` sourced at runtime plus v2/v3 runner/helper files;
- `release_metadata.csv` — release ID, component IDs/versions, routing, season policy, canonical evidence versions, and informative `git_head` / dirty state;
- `canonical_component_inventory.csv` — authoritative current components and superseded predecessors;
- `release_id.txt` — SHA-256/digest of the canonical sorted manifest payload.

`release_id` becomes the runtime/governance identity. `git_head` remains diagnostic only until an explicit source commit is requested.

### Canonical release-ID serialization

The release digest payload is a UTF-8 / LF-only line-oriented manifest, sorted by `(role,path)` with repo-relative POSIX paths only. Each line is exactly:

`role\tpath\tsha256\tsize_bytes`

Rules:

- roles and paths must be unique; duplicate roles or duplicate paths are fatal unless a role is explicitly declared multi-valued in the builder;
- symlinks are forbidden; only regular files may enter the payload;
- timestamps, Git diagnostics, generated `release_id.txt`, release metadata, completion markers, and derived manifest files are excluded from the digest payload;
- `release_metadata.csv` records the resulting `release_id` but is not itself part of the digest payload;
- the builder writes to a staging directory, computes the release ID, then atomically renames to `artifacts/v3-shadow-release-v1-<release_id_prefix>/`; an existing non-empty target is immutable and causes failure;
- `artifacts/v3-shadow-release-v1/` may be a small pointer/receipt only, never the authoritative identity.

The combined runner and transaction launcher must validate the release manifest before resolving live/replay data.

## Phase 1 — deterministic B season policy and eligibility

### 1.1 Machine-readable policy source

Create:

`governance/v3_b_season_policy_v1.csv`

Required fields:

- `season`
- `M1_B_peak_eligible`
- `M1_B_training_eligible`
- `M2_B_state_eligible`
- `M2_B_timing_eligible`
- `M2_B_scoring_eligible`
- `exclusion_reason`
- `review_status`

Policy rows must encode explicitly:

- 2018-19: no meaningful B timing event; M1-B timing false; M2-B state true; M2-B timing false.
- 2019-20: pandemic-transition exclusion; all B modeling/scoring false where the v3 policy currently excludes it.
- all other canonical seasons: eligible subject to the existing component definitions.

The existing human-readable `docs/v3-m1-b-season-policy-2026-09-26.md` remains explanatory documentation, but machine behavior derives from the CSV.

### 1.2 Timing contract v3

Create `scripts/v3_build_timing_contract_v3.R` and write only to:

`artifacts/v3-joint-timing-contract-v3/`

It must deterministically regenerate:

- `timing_contract_v3.csv`
- `modeling_eligibility_v3.csv`
- `timing_geometry_v3.csv`
- `season_observation_regimes.csv`
- `source_manifest.csv`
- `contract_metadata.csv`

Inputs must include the machine-readable policy source in the manifest. The output eligibility registry must be derived from canonical season coverage + policy source, never hand-edited. The builder must enforce unique/exhaustive canonical-season coverage, strict TRUE/FALSE parsing, allowed status values, exclusion-reason invariants, and finite timing truth wherever timing eligibility is TRUE.

The timing-contract source manifest must bind the generator script SHA, every input source SHA, and every generated output SHA. Output hashes are written after generation and then the manifest itself is hashed separately in metadata to avoid self-reference.

The v3 timing truth values must be numerically identical to the accepted v2 timing contract except for added governance/status fields. Explicit invariants include:

- 2017-18 B activity marker remains detector value `23.9642295842807`;
- 2018-19 finite B peak is absent;
- 2019-20 may remain archived timing data but is marked ineligible by the policy registry;
- all source hashes are current.

## Phase 2 — M1-B v9 provenance closure

Create:

- `scripts/build_m1_b_v3_peak_artifact_v9.R`
- `scripts/v3_m1_b_runtime_helpers_v8.R`
- `artifacts/m1-b-v3-peak-v9/`

M1-B v9 must preserve the **same fitted library behavior** and the same 9 training seasons as v8.

Required changes:

1. Consume timing-contract v3 and deterministic eligibility v3.
2. Hash and validate the machine-readable B season-policy source.
3. Add a deterministic `artifact_id` computed from a canonical core payload containing at least:
   - version/status;
   - library hash;
   - ordered training seasons;
   - amplitude grid;
   - B activity parameters/window;
   - timing-contract ID/hash;
   - eligibility hash;
   - policy-source hash;
   - runtime constants;
   - disabled calibration/A-conditioning/hard-passage flags.
4. Runtime validator recomputes and verifies `artifact_id`.
5. Runtime validator verifies current policy/eligibility/timing/helper hashes rather than only hashes embedded at build time.
6. Keep `git_head` diagnostic only; add release binding later via the release manifest.
7. Assert the v9 fitted-library hash equals the accepted v8 library hash exactly. Any model-behavior change is a hard failure.
8. Define `artifact_id` from a canonical UTF-8/LF, sorted, line-oriented core payload with explicit field names and stable numeric formatting; exclude timestamps, file paths, Git diagnostics, and the artifact ID field itself. Runtime recomputation must use the same serializer.
9. Add fixed-origin behavioral equivalence tests versus v8 for both peak-location and passage posteriors, including pre-activation/inactive, active posterior, and late/post-peak cases.

## Phase 3 — M2-B shadow v3 rebinding

Because M2-B shadow-v2 is cryptographically bound to M1-B v8, build a new package rather than modifying v2:

- `scripts/build_m2_b_v3_shadow_artifact_v3.R`
- `scripts/v3_m2_b_runtime_helpers_v3.R`
- `artifacts/m2-b-v3-shadow-v3/`

Requirements:

- bind to M1-B v9 SHA/artifact ID;
- use timing-contract v3;
- preserve exactly the accepted state-model coefficients, shape grid, routing constants, C2 weights, eta, season sets and historical evidence decision;
- do not refit accepted state/shape payloads during packaging; copy the accepted shadow-v2 behavioral payload after validating exact coefficient/grid/constants hashes;
- assert artifact behavior equivalence with shadow-v2 for deterministic replay fixtures covering +1, +2, no-timing fallback, active posterior-C2, and lower-bound saturation diagnostics;
- keep +1 exact B1;
- keep +2 posterior-C2 if causal timing is available, otherwise exact B1;
- keep hard passage and production routes forbidden;
- retain lower-bound saturation as monitoring-only.

The new M2-B package gets a new `artifact_id`; model-equivalence checks must show any change is governance/provenance only.

## Phase 4 — runtime code closure and panel validation

### 4.1 Shared panel validator

Add a shared pure operations validator helper used by both weekly runners. It must validate without mutating, recomputing, sorting, or normalizing the supplied panel. It must require:

- exactly one requested season;
- integer unique `weekF`;
- contiguous `weekF` coverage;
- valid A/B counts and `p=y/N`;
- paired date columns if dates are present;
- exact `origin-2:origin` support when forecasts are issued.

Update `2026/run_weekly_m2_b_shadow_v3.R` so the standalone runner rejects the same gapped panel that the combined runner already rejects.

Add an explicit regression test that removes an interior week and proves both standalone and combined v3 runners fail before issuance. Add a golden equivalence test proving v2 default ingestion and v2 `--typed-panel` replay yield the same effective panel hash and identical predictions for a fixed fixture.

### 4.2 Full executable hash closure

Generate the release `code_manifest.csv` from:

- all sorted `PAGe/R/*.R` files sourced by `.shadow_v2_source_package()`;
- v2 runner;
- combined v3 runner;
- standalone M2-B runner;
- M1-B and M2-B runtime helpers;
- release/transaction launcher;
- release validator.

The runtime release preflight hashes every entry before data resolution.

No hard-coded partial code list is accepted as release closure. Preflight must enforce exact set equality between the dynamically sourced `PAGe/R/*.R` set and the manifest set: missing, changed, or unexpected runtime files are all fatal. Include the shared operations validator helper itself. Record R version plus package versions for runtime dependencies used by the runners/builders.

## Phase 5 — one-source transaction for v2/v3 comparison

### 5.1 Add typed-panel mode to v2 operations runner

Extend `2026/run_weekly_shadow_v2.R` with an operations-only `--typed-panel=PATH` mode.

This must not change frozen v2 modeling code or defaults. It only bypasses independent raw-source resolution and consumes an already archived typed A/B panel after the same strict validation.

### 5.2 Release transaction launcher

Create:

`2026/run_weekly_shadow_release_v3.R`

Responsibilities:

1. Validate release manifest/code closure/artifact identities **before** source resolution.
2. Resolve/download the surveillance source exactly once.
3. Archive the raw source once under a transaction directory.
4. Build and strictly validate one typed A/B panel once.
5. Hash the typed panel.
6. Invoke v2 and combined v3 using that exact archived typed-panel path.
7. Verify both child run provenance files record the identical typed-panel SHA and origin week.
8. Emit transaction-level:
   - `source_transaction.tsv`
   - `v2_v3_comparison.csv`
   - `release_id.txt`
   - child run paths
   - source/panel SHA-256
   - release manifest SHA-256
9. Fail the whole transaction if either child runner fails or records a different panel hash/origin.

This launcher is the **only authoritative path** allowed to emit `v2_v3_comparison.csv`. Standalone v2/v3 runners remain diagnostic/replay tools and must never emit an official comparison artifact.

Transaction publication is atomic: run both children under a pending transaction directory, write raw-source SHA, supplied typed-panel byte SHA, canonical effective-panel SHA, origin/season, and validated release ID into child provenance, verify equality, then atomically publish a final transaction directory with a completion marker. If either child fails, no publishable comparison directory or completion marker may exist; an optional failed-transaction receipt may be written outside the publishable tree.

## Phase 6 — canonical/superseded inventory and plan cleanup

Create:

`docs/v3-canonical-component-inventory-2026-09-27.md`

It must list exactly one canonical item for each role:

- timing contract;
- B policy/eligibility source;
- M1-A;
- M1-B;
- M2-A;
- M2-B;
- combined runner;
- release launcher;
- historical evidence package for M1-B/M2-A/M2-B;
- release manifest.

List v1-v8 / shadow-v1-v2 / older timing contracts as `superseded` with reason, never merely omit them.

Clean `docs/v3-joint-ab-modeling-plan-2026-09-25.md` so it references only current canonical versions in the status section and links to the canonical inventory for history.

## Phase 7 — release manifest and runtime validator

Create:

- `scripts/build_v3_shadow_release_v1.R`
- `scripts/v3_shadow_release_helpers_v1.R`
- `artifacts/v3-shadow-release-v1/<release_id>/`

The builder must refuse to overwrite a non-empty release directory.

The release manifest must bind at minimum:

- machine-readable season policy;
- timing contract v3 manifest + key outputs;
- M0-A artifact;
- M1-A artifact;
- M2-A artifact;
- M1-B v9 artifact + manifest/helper;
- M2-B shadow-v3 artifact + manifest/helper;
- canonical M1-B/M2-A/M2-B evidence verdict/integrity files;
- combined runner;
- v2 runner;
- transaction launcher;
- full `PAGe/R/*.R` code closure;
- relevant contract tests;
- canonical inventory and master plan.

`release_id` is computed from the canonical line-oriented payload defined above and stored both in metadata and in `release_id.txt`. The final release builder runs **last**, after launcher, validator, tests, inventory, and master-plan cleanup exist, so all normative executable/governance sources are bound.

Runtime release validator must recompute the release ID and every manifest hash.

## Phase 8 — test plan

Add/extend tests for:

1. deterministic eligibility regeneration from the policy source;
2. timing-contract v3 reproduces accepted timing values;
3. changing the policy source invalidates M1-B v9 preflight;
4. M1-B v9 artifact ID recomputes exactly;
5. M1-B v9 library hash equals v8 library hash;
6. M2-B shadow-v3 replay is numerically equivalent to shadow-v2 on fixed fixtures;
7. standalone M2-B rejects gapped weeks;
8. combined v3 rejects gapped weeks;
9. v2 typed-panel mode uses exact supplied panel hash;
10. release manifest detects source/helper/artifact tampering;
11. full `PAGe/R/*.R` code closure is represented in the release manifest;
12. one-source transaction gives v2 and v3 identical panel SHA/origin;
13. no child runner can issue production-eligible output;
14. release build is deterministic from the same inputs;
15. canonical inventory contains no duplicate canonical role.

Run relevant focused tests plus all existing v3 shadow contract/runner suites.

## Phase 9 — Git/worktree disclosure

Because no commit was requested, do not commit or push.

Release metadata must record:

- `git_head` as informative only;
- `git_status --porcelain` hash / dirty flag;
- authoritative `release_id`;
- explicit statement that generated private artifacts are governed by content hashes and artifact-storage policy, not Git tracking.

The final independent audit must judge reproducibility against the release ID/manifest, not against the stale Git HEAD alone. If a clean Git commit is later desired, it should contain the executable/docs/tests/policy source only; generated private artifacts remain outside Git.

## Acceptance criteria

The governance hardening release is acceptable only if all are true:

- all eight audit findings are explicitly closed or, for Git commit state, replaced by a documented content-addressed release identity that the final auditor accepts;
- no accepted model metric/routing decision changes;
- M1-B v9 library hash equals v8;
- M2-B shadow-v3 fixture predictions equal shadow-v2 to numerical tolerance across both horizons, inactive fallback, active correction, and lower-bound diagnostic cases;
- M1-B v9 peak and passage posterior outputs equal v8 on fixed origins, not only library hash;
- current policy/timing/eligibility/helper drift causes preflight failure;
- gapped panels fail in both standalone and combined runners;
- one-source transaction proves v2/v3 use the same panel SHA and origin;
- full release hash closure passes;
- all targeted tests pass with zero failures/warnings/skips unless a skip is explicitly unavoidable and documented;
- final independent audit returns `APPROVE` or `APPROVE WITH CAVEATS` with no critical blocker.

## Implementation order after plan audit

1. policy source + timing-contract v3;
2. M1-B v9 + tests;
3. M2-B shadow-v3 + equivalence tests;
4. shared panel validation + standalone gap fix;
5. v2 typed-panel operations mode;
6. release manifest/helper;
7. one-source transaction launcher;
8. canonical inventory/master-plan cleanup;
9. full focused test suite;
10. independent post-implementation audit.
