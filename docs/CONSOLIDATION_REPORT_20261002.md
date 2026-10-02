# PAGe Consolidation Validation Report

Validation performed from `/home/yeli/repos/PAGe-consolidation` on 2026-10-01. The requested report filename uses the scheduled 2026-10-02 date.

## Consolidated layout

- `PAGe/` is the installable R package and sole package source, including runtime code under `PAGe/R/`, runtime assets under `PAGe/inst/`, and tests under `PAGe/tests/testthat/`.
- `2026/` contains the current weekly API and ORVT preflight entry points.
- `docs/`, `deploy/`, `governance/`, and `scripts/` retain documentation, deployment assets, governance material, and current utilities.
- `archive/legacy-season-runners/` holds the moved `2014/`, `2018/`, and `2025/` seasonal directories.
- `archive/legacy-training/` holds the former `scripts/fresh_run/` and retired root-level training/tuning scripts.
- `PAGe_0.3.0.tar.gz` is present at the repository root.

## Archive moves

The legacy seasonal directories `2014/`, `2018/`, and `2025/` were moved under `archive/legacy-season-runners/`. The retired training scripts, including `fresh_run/`, nested LOSO runners, M1 tuning scripts, and M2 rebuild scripts, were moved under `archive/legacy-training/`. Current weekly deployment scripts remain in `2026/` and current package sources remain in `PAGe/`.

## Installation and focused tests

The stale `/tmp/page-consolidation-lib/00LOCK*` directory was removed and `R CMD INSTALL -l /tmp/page-consolidation-lib PAGe` was run. The staged install output was cut off by the command time limit, but the installed package loaded successfully afterward from that library and its packaged fixtures/models were present.

| Focused test | Result |
| --- | --- |
| `test-v3-walkforward-report.R` (requested command) | **Failed**: fixture lookup succeeded on rerun, but the report function errored because `page_aggregate_strata()` is referenced but not defined anywhere in the repository package sources. Initial invocation also failed fixture lookup during the interrupted install. |
| `test-v3-weekly-api-orvt-readiness.R` | **Passed**, 18 expectations; no skips or failures. |
| `test-v3-package-runtime.R` | **Failed**, 11 failures (7 passed): test execution did not load the package namespace, so calls to `page_v3_models()` and `page_v3_forecast()` were unresolved. |
| `test-v3-weekly-api-v4-monitoring.R` | **Passed**, 2 expectations; **11 skipped** because the retained weekF12 transaction is unavailable. |

For diagnosis, loading `PAGe` before `testthat::test_file()` allowed the walk-forward test to reach the report code, where the missing helper error above occurred. This indicates the requested `test_file()` invocation alone does not provide the package test environment assumed by some test files.

## Week-12 forecast identity

Using the installed `PAGe` package and the packaged report-support fixture `extdata/v3-week12/report-support/week12_panel_fixture.csv`, `PAGe::page_v3_forecast(..., season = "2026-27", origin_weekF = 12)` returned:

| Virus | Horizon | Forecast positivity |
| --- | ---: | ---: |
| Flu A | +1 | 3.51705404452420% |
| Flu A | +2 | 3.49768310318725% |
| Flu B | +1 | 0.037855165827212% |
| Flu B | +2 | 0.039378396168781% |

These match the retained governed Week-12 identity values at the displayed precision. The forecast reported `shadow_only; issued` and `production eligible: FALSE`.

## ORVT preflight

Ran the requested `R_LIBS_USER=/tmp/page-consolidation-lib Rscript 2026/run_page_orvt_source_preflight_v1.R --help`. It exited with an error, `Arguments must use --key=value.` The script currently has no help option and requires `--result-path`; therefore this command did not perform a live ORVT preflight or produce a preflight result. A reproducible live-source outcome remains unverified.

## Clutter and known limitations

The named clutter targets (`PAGe.Rcheck/`, `docs/scratch_v16_params.rds`, and `test/test.RData`) were absent when checked, so no further deletion was needed.

Outstanding validation issues are the undefined `page_aggregate_strata()` dependency in the walk-forward report, package test harness assumptions for `test_file()`, and the unsupported `--help` flag in the ORVT preflight script. The ORVT live source itself was not checked. No claim is made here about a complete package test suite or production eligibility; the forecast remains shadow-only.
