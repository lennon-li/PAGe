# PAGe current canonical stack

Date: 2026-09-28  
Status: current canonical shadow stack  
Canonical minimum origin: **weekF12**

## Release identity

The content-addressed forecast release is `artifacts/v3-shadow-release-v3/5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b`. Its authoritative launcher is `2026/run_weekly_shadow_release_v5.R`. This release enforces origin weekF12 and remains **shadow-only** (`production_eligible = FALSE`). Do not edit its contents or treat another release ID as current.

## Model components

- **M0-A:** `artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds`; frozen ignition policy with `w_min=12`.
- **M1-A:** `artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/m1_v2_stage.rds`; frozen M1-v2 timing stage.
- **B timing contract:** `artifacts/v3-joint-timing-contract-v4/`; B activity window is 12–40.
- **M1-B:** `artifacts/m1-b-v3-peak-v10/`; fitted library is behavior-preserving relative to v9 and rebound to the weekF12 timing contract.
- **M2-A:** `artifacts/m2-v2-c2-governed-v1/m2_v2_c2_governed_fit.rds`; A +1/+2 use exact A1 state.
- **M2-B:** `artifacts/m2-b-v3-shadow-v5/`; B +1 exact B1, B +2 posterior-C2 only when causal timing is available, otherwise exact B1 fallback; minimum origin weekF12.
- The current component lineage and evidence are summarized in [the canonical component inventory](v3-canonical-component-inventory-2026-09-27.md).

## API deployment

The current shadow API contract is **API v4** (`page-weekly-api-v4`), implemented by `scripts/v3_weekly_api_helpers_v4.R`, `scripts/v3_weekly_api_deployment_helpers_v4.R`, and `scripts/build_v3_weekly_api_deployment_v4.R`. Service, worker, preflight, and HTTP adapter entry points are `2026/run_page_weekly_api_v4.R`, `2026/run_page_weekly_api_worker_v4.R`, `2026/run_page_weekly_api_preflight_v4.R`, and `2026/page_weekly_api_v4.R`. API v4 binds the same forecast release above and executes only launcher v5. It adds a disclosure-safe monitoring projection sourced only from validated v3 child-run artifacts: A M0 ignition, A M1 peak posterior, B M1 timing state, plus the existing M2 forecasts. The stable HTTP route prefix remains `/v1` as the wire route schema; that does not denote the internal API contract version.

The API and model outputs are shadow-only. No promotion, production serving, timer activation, or release switching is authorized by this stack index. See the [API v4 operations runbook](v3-weekly-deployment-api-operations-2026-09-27.md).

## Current walk-forward report

The current prospective report is `docs/v3_week8_11_walkforward_2026_27.html` (source: `docs/v3_week8_11_walkforward_2026_27.qmd`). It reports the 2026-27 weekF11 walk-forward evidence. This is a report of the available evaluation origin, not an exception to the weekF12 canonical forecast-issuance minimum.

## Comparison policy

Use [the legacy/v2/v3 comparison plan](v3-legacy-v2-v3-comparison-plan-2026-09-28.md). Compare only common targets, common ledgers, and same-source/same-panel weekly transactions. Historical v1/v2 releases and older API policies are superseded and retained only as immutable evidence; they are not current deployment targets.

## Current operational monitoring surface

Use API v4 for weekF12+ shadow operations. It adds governed M0/M1 monitoring projection to the existing M2 result without changing the forecast release or launcher. See `docs/v3-weekly-api-v4-monitoring-2026-09-28.md`.
