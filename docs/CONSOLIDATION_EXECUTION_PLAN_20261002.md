# PAGe Repository Consolidation Execution Plan

Date: 2026-10-02  
Author: Fury (Hermes Agent Orchestrator)  
Source Handoff: Jax handoff (Agent 7)  
Target Repository: `/home/yeli/repos/PAGe`

---

## 1. Executive Summary & Strategy

The objective is to consolidate all valid PAGe development across `/home/yeli/repos/PAGe`, `/home/yeli/repos/PAGe-m1-v2`, and `/home/yeli/repos/PAGe-m2-a-full` into exactly one canonical production code line and two clearly isolated research lines:

```text
master (Canonical Production Pipeline & R Package)
├── dev/n-history (Test-volume / N-history prediction research only)
└── dev/survival-peak (Survival / hazard peak-timing research only)
```

### Safety Rules & Execution Governance
1. All existing branch states and commits are frozen and tagged under `archive/pre-consolidation-20261002/*`.
2. No branches will be deleted until all useful commits/files are verified reachable from `master`, `dev/n-history`, `dev/survival-peak`, or recovery tags.
3. No git force-pushes or remote pushes will occur.
4. `.serena/` and user local configs remain strictly preserved and untouched.
5. Consolidation will assemble the production baseline on `consolidation/production-20261002` first, run validation gates (R CMD build/check, Week-12 forecast identity check, walk-forward report generation, and API v4 preflight), and only promote to `master` upon passing all gates.

---

## 2. Recovery Tags (Phase 0 Complete)

The following recovery tags have been created and verified in `/home/yeli/repos/PAGe`:
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

Additionally, uncommitted working tree diffs in `/home/yeli/repos/PAGe-m1-v2` were exported to `/tmp/page-m1-v2-uncommitted.patch`, and the `/home/yeli/repos/PAGe-m2-a-full` workspace was archived to `/tmp/page-m2-a-full-source-backup.tar.gz`.

---

## 3. Comprehensive File Classification

| File / Directory | Origin / Path | Classification | Disposition / Target |
|---|---|---|---|
| `PAGe/R/v3_walkforward_report.R` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`PAGe/R/`) |
| `PAGe/inst/report/v3_walkforward_report_template.html` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`PAGe/inst/report/`) |
| `PAGe/inst/extdata/v3-week12/report-support/*` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`PAGe/inst/extdata/v3-week12/report-support/`) |
| `PAGe/man/page_v3_walkforward_report.Rd` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`PAGe/man/`) |
| `PAGe/tests/testthat/test-v3-walkforward-report.R` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`PAGe/tests/testthat/`) |
| `PAGe/tests/testthat/test-v3-weekly-api-orvt-readiness.R` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`PAGe/tests/testthat/`) |
| `PAGe/tests/testthat/test-v3-weekly-api-v4-monitoring.R` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`PAGe/tests/testthat/`) |
| `2026/run_page_orvt_source_preflight_v1.R` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`2026/`) |
| `scripts/reproduce_weekly_orvt_v1.sh` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`scripts/`) |
| `scripts/verify_weekly_reproducibility_v1.py` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`scripts/`) |
| `2026/page_weekly_api_v4.R` (updates) | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`2026/`) |
| `2026/run_page_weekly_api_preflight_v4.R` (updates) | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`2026/`) |
| `2026/run_page_weekly_api_v4.R` (updates) | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`2026/`) |
| `2026/run_page_weekly_api_worker_v4.R` (updates) | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`2026/`) |
| `deploy/systemd/*` (v4 trigger & unit fixes) | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`deploy/systemd/`) |
| `docs/training_walkthrough.qmd` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`docs/`) |
| `docs/realtime_deployment_walkthrough.qmd` | `PAGe-m1-v2` | PRODUCTION | Move to `master` (`docs/`) |
| `docs/pipeline_walkthrough.qmd` (updates) | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`docs/`) |
| `docs/deployment-workflow.qmd` (updates) | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`docs/`) |
| `docs/v3-weekly-deployment-api-*` | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`docs/`) |
| `scripts/v3_weekly_api_helpers_v4.R` (updates) | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`scripts/`) |
| `scripts/v3_weekly_api_deployment_helpers_v4.R` (updates) | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`scripts/`) |
| `scripts/build_v3_weekly_api_deployment_v4.R` (updates) | `PAGe-m1-v2` | PRODUCTION | Apply to `master` (`scripts/`) |
| `2026/run_page_a_shadow_snapshot_v1.R` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `PAGe/R/m2_ntrend_shadow.R` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `PAGe/man/*ntrend_shadow*.Rd` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `PAGe/tests/testthat/test-m2-ntrend-shadow.R` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `PAGe/tests/testthat/test-v3-a-shadow-api.R` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `docs/*ntrend*`, `docs/*test-volume*`, `docs/*exp050*` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `scripts/analyze_test_volume_*` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `scripts/build_v3_a_exp050_shadow_v1.R` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `scripts/evaluate_m2_a_ntrend_shadow_v1.R` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `scripts/run_m2_a_ntrend_fully_nested_loso_v1.R` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `scripts/v3_a_shadow_helpers_v1.R` | `PAGe-m1-v2` | N-HISTORY | Route to `dev/n-history` |
| `scripts/m2_nhistory_nested_*.R` | `PAGe-m2-a-full` | N-HISTORY | Route to `dev/n-history` |
| `scripts/run_m2_nhistory_*.R` | `PAGe-m2-a-full` | N-HISTORY | Route to `dev/n-history` |
| `scripts/*m2_nhistory_bcc*.sh` | `PAGe-m2-a-full` | N-HISTORY | Route to `dev/n-history` |
| `test/m2-nhistory-nested/*` | `PAGe-m2-a-full` | N-HISTORY | Route to `dev/n-history` |
| `BCC_DEPLOY_FULL_*.md`, `BCC_RUNBOOK_*.md`, `LOCAL_AGENT_HANDOFF_BCC_V2.md` | `PAGe-m2-a-full` | N-HISTORY | Route to `dev/n-history` |
| `scripts/m1_survival_peak_*.R` | `PAGe-m2-a-full` | SURVIVAL | Route to `dev/survival-peak` |
| `scripts/run_m1_survival_peak_*.R` | `PAGe-m2-a-full` | SURVIVAL | Route to `dev/survival-peak` |
| `tests/research/test_m1_survival_peak_*.R` | `PAGe-m2-a-full` | SURVIVAL | Route to `dev/survival-peak` |
| `2014/`, `2016/`, `2017/`, `2018/`, `2019/`, `2022/` | `PAGe` | HISTORICAL-ARCHIVE | Move to `archive/legacy-season-runners/` |
| `2025/` (legacy cycle & ultimate runners) | `PAGe` | HISTORICAL-ARCHIVE | Move to `archive/legacy-season-runners/2025/` |
| `scripts/fresh_run/` | `PAGe` | HISTORICAL-ARCHIVE | Move to `archive/legacy-training/fresh_run/` |
| Root legacy tuning/rebuild scripts (`run_nested_loso_v*.R`, etc.) | `PAGe` | HISTORICAL-ARCHIVE | Move to `archive/legacy-training/` |
| `PAGe.Rcheck/` | `PAGe` | DISCARDABLE | Remove local check directory |
| `docs/scratch_v16_params.rds`, `test/test.RData` | `PAGe` | DISCARDABLE | Remove scratch files (untracked/local) |
| `.serena/` | `PAGe`, `PAGe-m1-v2` | USER-STATE | Retain untouched in working tree |
| `artifacts/` (intermediate run data & logs) | `PAGe-m1-v2`, `PAGe-m2-a-full` | REVIEW / EXTERNAL-STORAGE | Retain in respective workspaces; do NOT commit large artifacts into git |

---

## 4. Commit & Branch Salvage Map

### Canonical Production Baseline Stack
The production line is anchored on `origin/master` (`b639e38`), incorporating:
1. `f982746`: Governed M1 and M2 v2 forecasting stack.
2. `6c64ce8`: Canonical v3 forecasting and weekF12 operations (`page_v3_forecast()`, models `m0_a`, `m1_a`, `m1_b`, `m2_a`, `m2_b`).
3. `cbac857` (selective): Immutable v3 probability API diagnostics and calibrator governance.
4. `PAGe-m1-v2` working tree additions:
   - Walk-forward report API (`page_v3_walkforward_report()`, template, report support data, tests).
   - Official ORVT ingestion and reproducibility pipeline (`run_page_orvt_source_preflight_v1.R`, `reproduce_weekly_orvt_v1.sh`, `verify_weekly_reproducibility_v1.py`).
   - Weekly API v4 monitoring, systemd trigger fixes (`page-weekly-api-v4.service` dependency).
   - Production documentation walkthroughs (`training_walkthrough.qmd`, `realtime_deployment_walkthrough.qmd`).
5. Evaluated PR fixes:
   - `cfc78b4` (`release/latest-package`): boundary-aware resumable tuning API.
   - `98644c3` (`fix/copilot-review-comments`): doc and storage reconciliation.

### Obsolete / Experimental Isolation
- `feature/peak-week-probability-api` / `asgard-sync-20261001` (`50f92e5`): The `peak_week_distribution.R` implementation remains strictly labelled as experimental / uncalibrated (spread across templates only) and is not presented as calibrated production peak timing.
- `agent/m1-v2-from-first-principles` (`cbac857`): Fully integrated into production consolidation; original branch ref retired once verified reachable.
- `agent/page-governance-audit` & `agent/page-governance-pr`: Ancestors of the v3 stack, fully represented.

---

## 5. Execution Steps

### Step 1: Initialize Consolidation Branch
In `/home/yeli/repos/PAGe`:
Create `consolidation/production-20261002` off `origin/master` (`b639e38`).

### Step 2: Integrate Governed v3 Core & Production Assets
Bring in:
- Core v3 package sources from `agent/m1-v2-from-first-principles`.
- `v3_walkforward_report.R`, templates, and support files from `PAGe-m1-v2`.
- ORVT operational preflight and reproducibility scripts from `PAGe-m1-v2`.
- Weekly API v4 monitoring and systemd files from `PAGe-m1-v2`.
- Documentation walkthroughs from `PAGe-m1-v2`.
- Resumable tuning API and copilot doc fixes.
- Ensure `.gitignore` unignores `PAGe/inst/extdata/**` and `PAGe/inst/report/**` so required runtime fixtures are tracked properly.

### Step 3: Archive Legacy Implementations
Move root legacy season folders (`2014`, `2016`, `2017`, `2018`, `2019`, `2022`, old `2025` runners) and `scripts/fresh_run/` into `archive/`. Clean disposable local outputs (`PAGe.Rcheck/`, scratch RDS).

### Step 4: Verification Gates
1. `R CMD build PAGe`
2. `R CMD check --no-manual --no-vignettes PAGe_*.tar.gz`
3. Run focused package tests:
   - `test-v3-package-runtime.R`
   - `test-v3-walkforward-report.R`
   - `test-v3-weekly-api-orvt-readiness.R`
   - `test-v3-weekly-api-v4-monitoring.R`
4. Verify Week-12 forecast identity against canonical targets (Flu A +1: ~3.517%, +2: ~3.498%; Flu B +1: ~0.0379%, +2: ~0.0394%).
5. Run ORVT reproducibility preflight check.

### Step 5: Promote to `master`
Fast-forward or reset `master` to `consolidation/production-20261002`.

### Step 6: Spawn Isolated Research Branches
1. From the new `master` tip, branch `dev/n-history`:
   - Add all N-history files from `PAGe-m1-v2` and `PAGe-m2-a-full`.
   - Commit cleanly.
2. From the new `master` tip, branch `dev/survival-peak`:
   - Add all survival files from `PAGe-m2-a-full`.
   - Commit cleanly.

### Step 7: Final Documentation & Report
Write `docs/CONSOLIDATION_REPORT_20261002.md`.
Retire redundant local branches (`asgard-sync-20261001`, `feature/peak-week-probability-api`, `agent/page-governance-audit`, `agent/page-governance-pr`, `agent/m1-v2-from-first-principles`, `release/latest-package`, `fix/copilot-review-comments`).
