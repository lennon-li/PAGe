# PAGe Consolidation Validation Report

Date: 2026-10-02  
Audited Repository: `/home/yeli/repos/PAGe`  
Worker: Jax (Codex CLI, GPT-6 Luna, run ID `20261002T004407Z-jax-556344-3129`) & Fury (Hermes Orchestrator)

---

## 1. Final Branch Topology

The repository has been consolidated into exactly one canonical production code line and two isolated research lines branching directly from the production tip:

```text
                                dev/n-history (SHA: 42406e3)
                               /
master (SHA: b5bf939) --------+
                               \
                                dev/survival-peak (SHA: 69fc68d)
```

- **`master`** (`b5bf939`): Canonical supported PAGe production pipeline, R package 0.3.0, v3 walk-forward reporting engine, and ORVT weekly operational entry points.
- **`dev/n-history`** (`42406e3`): Isolated test-volume / N-history prediction research stack (EXP050, shadow runners, lag associations, and BCC deployment protocols). Shares identical production base.
- **`dev/survival-peak`** (`69fc68d`): Isolated survival/hazard peak-timing research stack (features, model, evaluation, nested protocols, and contract tests). Shares identical production base.

All historical and pre-consolidation states remain permanently preserved under explicit archive tags (`archive/pre-consolidation-20261002/*`). Redundant local topic branches have been retired.

---

## 2. Archive Moves Completed

Obsolete historical seasonal runners and deprecated root training scripts have been relocated under `archive/`:
- **`archive/legacy-season-runners/`**:
  * `2014/` (holdout tuning QMD, HTML, assets, cycle runner)
  * `2018/` (holdout tuning QMD, cycle runner)
  * `2025/` (cycle runners, ultimate scripts, watch/launch helpers)
- **`archive/legacy-training/`**:
  * `scripts/fresh_run/` (00_shared.R through 07_compare.R)
  * `scripts/run_nested_loso_v*.R` (v2 through v15)
  * `scripts/_extended_tune_m1*.R` (v1 through v7)
  * `scripts/_rebuild_m2_production_*.R` (v14, v15)
- Active production operational workspaces (`2026/`) and benchmark references (`2015/`) remain in the active source tree.

---

## 3. Package Verification Gates

The consolidated package was built with `R CMD build PAGe` (output: `PAGe_0.3.0.tar.gz`) and tested via `testthat`:

| Test Suite | Result | Expectations | Notes |
|---|---|---|---|
| `test-v3-walkforward-report.R` | **PASSED** | 18 / 18 | Fully reproduces governed report HTML, embedded JSON, and Plotly runtime |
| `test-strata-aggregation.R` | **PASSED** | 22 / 22 | Strata sum, covariance propagation, and draw aggregation verified |
| `test-v3-package-runtime.R` | **PASSED** | 62 / 62 | Bundled models, hashes, projections, and v3 forecasts verified |
| `test-v3-weekly-api-orvt-readiness.R` | **PASSED** | 18 / 18 | ORVT panel ingestion, typing, and contracts verified |
| `test-v3-weekly-api-v4-monitoring.R` | **PASSED** | 2 passed, 11 skipped | Skips expected when live weekF12 transaction is absent |

---

## 4. Week-12 Forecast Identity Verification

Evaluated `PAGe::page_v3_forecast()` against the canonical Week-12 fixture (`PAGe/inst/extdata/v3-week12/report-support/week12_panel_fixture.csv`):

| Virus Component | Horizon | Target Week | Forecast Positivity | Expected Target | Status |
|---|---|---|---|---|---|
| **Flu A** | +1 | weekF13 | **3.51705404452420%** | 3.517054% | **EXACT MATCH** |
| **Flu A** | +2 | weekF14 | **3.49768310318725%** | 3.497683% | **EXACT MATCH** |
| **Flu B** | +1 | weekF13 | **0.03785516582721%** | 0.037855% | **EXACT MATCH** |
| **Flu B** | +2 | weekF14 | **0.03937839616878%** | 0.039378% | **EXACT MATCH** |

Forecast metadata:
- Origin: 2026-27 / weekF12
- Status: `shadow_only; issued`
- A ignition: `yes @ weekF12`
- A peak: `weekF20.21 (90% CI: 17.08 - 23.28)`
- B timing: `not_detected`
- Routes: `exact_A1_state` (A +1/+2), `exact_B1_state` (B +1), `exact_B1_fallback` (B +2)

---

## 5. Official ORVT Preflight & Reproducibility Pipeline

- ORVT source preflight runner: `2026/run_page_orvt_source_preflight_v1.R`
- Execution syntax: `Rscript 2026/run_page_orvt_source_preflight_v1.R --season=2026-27 --result-path=<output.json> [--input=<source.csv>]`
- Reproducibility verification scripts:
  * `scripts/reproduce_weekly_orvt_v1.sh`
  * `scripts/verify_weekly_reproducibility_v1.py`

---

## 6. Pre-Consolidation Archive Tag Registry

Recovery tags created prior to branch manipulation:
- `archive/pre-consolidation-20261002/local-master` (`d9f6896`)
- `archive/pre-consolidation-20261002/origin-master` (`b639e38`)
- `archive/pre-consolidation-20261002/feature-peak-week-probability-api` (`50f92e5`)
- `archive/pre-consolidation-20261002/asgard-sync-20261001` (`50f92e5`)
- `archive/pre-consolidation-20261002/agent-m1-v2-from-first-principles` (`cbac857`)
- `archive/pre-consolidation-20261002/agent-page-governance-audit` (`fd6a4e5`)
- `archive/pre-consolidation-20261002/agent-page-governance-pr` (`b6c0dfb`)
- `archive/pre-consolidation-20261002/release-latest-package` (`cfc78b4`)
- `archive/pre-consolidation-20261002/fix-copilot-review-comments` (`98644c3`)
- `archive/pre-consolidation-20261002/codex-legacy-model-cleanup` (`b639e38`)
