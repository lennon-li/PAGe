# PAGe v3 end-to-end API audit

Date: 2026-09-28  
Status: **APPROVE WITH CAVEATS for shadow deployment testing**

## Canonical chain

The current canonical v3 shadow chain is:

`training/evaluation evidence -> M0-A -> M1-A / M1-B -> M2-A / M2-B -> content-addressed release -> authoritative one-source v2/v3 transaction -> API v3 -> walk-forward deployment`

Canonical forecast release:

`5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b`

Release path:

`artifacts/v3-shadow-release-v3/5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b/`

Authoritative launcher:

`2026/run_weekly_shadow_release_v5.R`

Deployment API contract:

`page-weekly-api-v3`

Canonical minimum forecast origin: **weekF12**.

All v3 outputs remain `shadow_only`; `production_eligible=FALSE`.

## Statistical lineage

### M0-A

Canonical artifact:

`artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds`

The frozen policy uses `w_min=12`, three-observation raw persistence, and a 1-SE sampling-noise tolerance for weekly drops. The current 2026-27 weekF10 -> weekF11 decline therefore remains raw-step stable (`raw_drop_z` about -0.446 versus threshold -1). WeekF11 did not ignite because it is before `w_min=12`; a diagnostic that appends the current M2 weekF12 A projection (~1.677%) returns M0 ignition at weekF12.

### M1-A

Canonical artifact:

`artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/m1_v2_stage.rds`

M1-A is frozen from v2 and was not retuned for v3.

### B season/timing policy

The machine-readable B policy retains:

- 2018-19: no-event timing season;
- 2019-20: excluded from B timing model training/scoring as the pandemic-transition season.

The versioned B activity detector is:

`artifacts/v3-b-activity-window12-40-v1/B_window12_40_detection.rds`

Historical 8-40 versus 12-40 detector outputs have the same failure/NA pattern and finite activity dates to tolerance <=1e-12. The earliest historical finite B activity date remains about weekF23.964, so the lower-bound migration is behavior-preserving on the historical archive.

Timing contract v4:

`artifacts/v3-joint-timing-contract-v4/`

preserves reviewed timing truth and eligibility while rebinding B activity provenance to 12-40.

### M1-B

Canonical artifact:

`artifacts/m1-b-v3-peak-v10/m1_b_v3_peak_artifact.rds`

M1-B v10 preserves the fitted v9 library/training seasons and representative posterior behavior while rebinding to timing v4 / B activity 12-40. It is not a statistical refit.

### M2-A

Canonical artifact:

`artifacts/m2-v2-c2-governed-v1/m2_v2_c2_governed_fit.rds`

A +1 and +2 remain exact A1 state forecasts. The historical timing-informed A challenger did not clear the frozen promotion threshold, so v3 does not change A routing.

### M2-B

Canonical artifact:

`artifacts/m2-b-v3-shadow-v5/m2_b_v3_shadow_artifact.rds`

M2-B v5 is a versioned rebind, not a refit. It requires both:

- `origin_weekF >= 12`; and
- exact observations at `origin-2:origin`.

Routing remains:

- B +1: exact B1 state;
- B +2: posterior-C2 only when causal timing is available, otherwise exact B1 fallback.

At weekF12 historical replay has zero B timing activations, so B +2 is exact B1 fallback.

## Release and transaction integrity

The canonical content-addressed release binds the exact model artifacts, runtime helpers, runners, launcher, package source closure, runtime environment manifest, and acceptance tests.

The launcher resolves one source vintage, creates one typed panel, and runs v2 and v3 from that same panel. Parent publication verifies matching season, origin, release ID, raw-source SHA, supplied typed-panel SHA, and effective-panel SHA before emitting `v2_v3_comparison.csv` and the atomic `COMPLETED` marker.

## API v3

Historical API v1 and v2 are not canonical:

- v1 is pinned to release `17eec173...0ef57e` and the superseded weekF13 launcher path;
- v2 is pinned to release `65f29aeb...8d64`, the rejected experimental early-origin / three-observation-only policy.

API v3 is a versioned rebind to release `5472d089...a853b` and launcher v5:

- `scripts/v3_weekly_api_helpers_v3.R`
- `scripts/v3_weekly_api_deployment_helpers_v3.R`
- `scripts/build_v3_weekly_api_deployment_v3.R`
- `2026/run_page_weekly_api_v3.R`
- `2026/run_page_weekly_api_worker_v3.R`
- `2026/run_page_weekly_api_preflight_v3.R`
- `governance/v3_weekly_api_policy_v3.tsv`
- `deploy/systemd/page-weekly-api-v3.service`

After normalizing only the versioned filenames, contract ID, release ID, and launcher name, v2 and v3 API core/deployment/worker/preflight/service logic are behaviorally identical. The hardened state machine, idempotency, locking, storage checks, environment sanitization, worker isolation, and transaction validation were not redesigned.

A compatibility defect was found and fixed in the shared `/v1/release` projection: the router previously understood only the older release inventory schema (`role/path/status`), while release v3 uses (`component/canonical_path/status`). The router now normalizes either governed schema before returning M1-B/M2-B version metadata.

## Tests

Canonical model/release targeted suites:

- M1-B v10: 11/11
- M2-B v5: 13/13
- weekF12 combined runner: 9/9
- release manifest/closure: 17/17
- authoritative launcher: 10/10

Total model/release targeted assertions: **60/60**.

API v3 suites:

- core/state/idempotency/transaction validation: 94/94
- HTTP/auth/routes/disclosure behavior: 43/43
- canonical release/preflight/worker weekF11/weekF12 binding: 22/22

Total API v3 targeted assertions: **159/159**.

No failures, warnings, or skips were present in the final v3-targeted suites.

## Retained end-to-end execution evidence

Final evidence bundle:

`artifacts/v3-end-to-end-audit-2026-09-28-v2/`

The bundle contains a recursive 72-file SHA-256/size manifest.

### Real 2026-27 weekF11

Source: archived real OLIS weekF11 source.

API v3 deployment ID:

`2b7d3d64833f4addce28d0ffa033c721b2d174b1bf225ceb876e5edbf68bd412`

Result:

- API deployment/preflight succeeds;
- authoritative forecast transaction fails closed because origin weekF11 is below the canonical weekF12 minimum;
- no success projection is published.

This is expected behavior.

### Synthetic weekF12

API v3 deployment ID:

`b5f53351173e572f394783be76f6cc83c91432b7bec5d3d69c44ab0828e4a9bf`

Result:

- deployment/preflight succeeds;
- worker succeeds;
- origin is weekF12;
- four finite v3 forecasts are projected;
- release ID is exactly `5472d089...a853b`;
- source, supplied-panel, effective-panel, child-run, and transaction identities are retained in provenance.

The synthetic fixture validates execution and governance plumbing; it is not forecast-accuracy evidence.

## Current prospective walk-forward evidence

Report:

- `docs/v3_week8_11_walkforward_2026_27.qmd`
- `docs/v3_week8_11_walkforward_2026_27.html`

Supporting data:

`artifacts/v3-week8-11-walkforward-report-v1/`

The report covers weekF8-11 and clearly labels all pre-weekF12 M2 values as diagnostics, not issued forecasts.

Current score-to-date on realized diagnostic targets:

- A +1 MAE: ~0.4122 pp
- A +2 MAE: ~0.5535 pp
- B +1 MAE: ~0.0285 pp
- B +2 MAE: ~0.0481 pp

These values must not be pooled into canonical issued-forecast performance.

## Legacy / v2 / v3 comparisons

### M1 legacy versus v2

Matched common ledger:

`artifacts/m1-v2-lowrank-posterior-v10-release-consistent/common_ledger_vs_legacy_v16_strict_future_release.csv`

Across 81 common origin/truth rows in 10 seasons:

- v2 mean absolute peak error: ~1.093 weeks;
- legacy mean absolute peak error: ~1.375 weeks;
- matched difference: ~0.283 weeks lower MAE for v2.

This is a stage-specific M1 timing comparison only.

### M2 legacy versus v2, A-only

Matched-target-ledger benchmark:

- `docs/m2-v2-legacy-matched-a-benchmark-2026-09-25.md`
- `artifacts/m2-v2-legacy-matched-a-v1/`

Primary 10 historical seasons with identical target counts:

- +1 legacy MAE: 8.4087 pp; v2 state/growth: 1.7757 pp; fixed C2: 1.5435 pp
- +2 legacy MAE: 9.2056 pp; v2 state/growth: 2.4124 pp; fixed C2: 2.1531 pp

Important limitation: target rows are matched, but historical training snapshots are not perfectly vintage-matched. This is A-only and should not be generalized to B or to an overall three-way legacy/v2/v3 result.

### v2 versus v3

Use only `v2_v3_comparison.csv` from `2026/run_weekly_shadow_release_v5.R`, which guarantees the same source and effective panel. These rows measure output differences; they become forecast-accuracy evidence only after the corresponding targets are observed.

### M0

No verified common-ledger legacy-versus-v2 M0 performance artifact was identified. No M0 performance improvement claim should be made until truth, eligible origins, and scoring rows are explicitly matched.

## Documentation disposition

Current operational/current-state documentation points to API v3, release `5472d089...a853b`, launcher v5, and weekF12. Historical release/API documents retain old IDs only as historical evidence and are explicitly separated from the current stack.

Current entry points:

- `docs/v3-current-canonical-stack-2026-09-28.md`
- `docs/v3-canonical-component-inventory-2026-09-27.md`
- `docs/v3-legacy-v2-v3-comparison-plan-2026-09-28.md`
- `docs/v3-weekly-deployment-api-plan-2026-09-27.md`
- `docs/v3-weekly-deployment-api-operations-2026-09-27.md`

The machine-readable current inventory is:

`governance/v3_canonical_component_inventory_v1.csv`

## Independent audit results

- Liz documentation/comparison audit: **APPROVE WITH CAVEATS**. Main findings were stale old-release/current-state docs and comparison comparability limits; current docs and API binding were subsequently updated.
- Claude deployment/API audit: **REJECT** API v1/v2 as canonical and require a separately versioned weekF12 API binding. API v3, its tests, and retained execution evidence were subsequently created and validated.
- Liz statistical-lineage audit: **APPROVE WITH CAVEATS**. It supported the M0/M1/M2/release lineage. Its environment had `lattice 0.22.9` rather than governed `0.23.1`, so it could not independently validate the governed runtime environment; it also noted that >=weekF13 M2-B equivalence is supported by the rebind/equivalence chain rather than a single exhaustive bound forecast-replay assertion.

## Remaining caveats

1. **No production-host deployment has occurred.** Private NFS, service account, bearer token, site-specific systemd environment, mount identity, and production scheduler/timer have not been validated on the actual production host.
2. **Do not enable the timer yet.** First perform a reviewed live weekF12-or-later API v3 run on the production host, then a distinct cycle plus idempotent retry.
3. **The repository worktree remains uncommitted/untracked.** Content-addressed release/deployment identities provide byte-level evidence, but there is not yet a clean Git commit boundary for the current API v3/docs work.
4. Historical content-addressed releases bind historical documentation bytes. Updating current worktree docs can make old release validators fail when run against the modern worktree. Current release `5472d089...a853b` does not bind the current-state docs changed in this audit; its model/runtime release closure is unchanged.

## Disposition

The current weekF12 **model -> release -> transaction -> API v3 -> walk-forward** chain is suitable for **shadow deployment testing**. It is not production-promoted. The next operational milestone is the first real weekF12-or-later API v3 run on the production host using the exact governed release and private infrastructure.
