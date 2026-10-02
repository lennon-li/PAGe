# PAGe v3 canonical component inventory

Date: 2026-09-28  
Status: current canonical lineage; supersedes prior release and API bindings  
Machine-readable model inventory: `governance/v3_canonical_component_inventory_v1.csv`

## Current frozen components

- B season policy: `governance/v3_b_season_policy_v1.csv`.
- Timing contract: `artifacts/v3-joint-timing-contract-v4/` (B activity window 12–40).
- M0-A: frozen M0-v2 artifact in the canonical release.
- M1-A: frozen M1-v2 full-history stage.
- M2-A: governed M2-v2 state model; A +1/+2 use exact A1 state.
- M1-B: `artifacts/m1-b-v3-peak-v10/`; B-only continuous timing posterior, without scalar calibration, A-conditioning, or hard passage.
- M2-B: `artifacts/m2-b-v3-shadow-v5/`; +1 exact B1, +2 posterior-C2 when causal timing is available, otherwise exact B1.

## Evidence and execution

- M1-B evidence: pandemic-excluded chronological B timing benchmark.
- M2-A evidence: `artifacts/v3-m2-a-posterior-c2-chronological-v1/`; timing challenger did not qualify, so state-only is retained.
- M2-B evidence: `artifacts/v3-m2-b-posterior-c2-chronological-v3/`; +2 shadow-qualified lower-bound saturation monitoring caveat.
- Current prospective report: `docs/v3_week8_11_walkforward_2026_27.html` and `.qmd`.
- Current transaction launcher: `2026/run_weekly_shadow_release_v5.R`.
- Current content-addressed release: `artifacts/v3-shadow-release-v3/5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b/`.
- Release verification and operations helpers: `scripts/v3_shadow_release_helpers_v1.R`, `scripts/v3_shadow_ops_helpers_v1.R`.
- Current deployment API: API v3, contract `page-weekly-api-v3`; deployment bootstrap includes the v3 core/deployment helpers, builder, service, worker, preflight, and shared router.
- Minimum canonical forecast origin: weekF12. Outputs remain shadow-only (`production_eligible = FALSE`).

Older release IDs, `run_weekly_shadow_release_v3.R`/`v4.R`, and API v1/v2 policies refer to superseded historical artifacts. They are not current deployment components. Research/provenance artifact families remain historical evidence, including v1-v8 timing research and shadow-v1/v2 releases.

Deployment API: `page-weekly-api-v4`, bound to release `5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b` and launcher `2026/run_weekly_shadow_release_v5.R`. API v4 exposes M0/M1 monitoring plus M2 forecasts; it does not alter model logic.
