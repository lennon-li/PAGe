# PAGe Project Context

## Project Goal

PAGe (Phase-Aligned Gated Epidemic Forecasting) forecasts seasonal respiratory
virus percentage positivity 1 to 2 weeks ahead using surveillance data.

Primary deliverables:

1. A trained, validated forecasting model for 2-week-ahead positivity
   prediction.
2. The `PAGe` R package, implemented as a clean, documented, installable
   package.

Evaluation must stay prospective and walk-forward. Avoid data leakage from
future seasons.

## Repository Layout

- `PAGe/` is the installable package and source of truth for package code.
- `R/` is a root-level mirror of `PAGe/R/` used for development
  convenience. Keep mirrored files in sync when editing.
- `docs/` contains Quarto documentation. `pipeline_overview.qmd` is the main
  architecture reference.
- `scripts/` contains pipeline entry points, tuning scripts, and diagnostics.
- `test/` contains the standalone LOSO grid-tuning harness.
- `data/` and `results/` are gitignored input and output directories.

## Pipeline Overview

The forecasting pipeline is:

`M0 (Ignition Detection) -> M1 (Alignment) -> M2 (Forecast)`

Within a week, execution is sequential: M1 runs before M2 because M2 consumes
alignment-derived covariates from M1.

## Project Conventions

- Prefer `future::plan(multisession)` for parallel work on Windows.
- After fitting the reference GAM, use the reference accessors rather than
  passing raw GAM objects around.
- In Quarto docs, do not use body-level h1 headings; the YAML `title:` already
  provides the page h1.
- Historical surveillance observations are private and are not distributed with
  the package. Supply an authorized CSV explicitly to `load_flu_hist(path)`,
  or set `PAGE_FLU_HIST_FILE`; `prepare_surveillance_data()` then enforces the
  canonical contract. `simulate_flu_seasons()` supplies synthetic example data.
- A future package distribution may bundle `inst/extdata/flu_hist.csv`, but it
  is absent from this repository and must not be assumed to exist. `ref_curve.RData`
  is likewise not a portable public-data input contract.

## Current Status (audited 2026-07-27)

**M0 (Ignition)** and **M1 (Alignment)** are implemented and have historical
tuning workflows. M1 uses multi-template alignment with slope-similarity
weighting; the published historical peak-MAE values conflict and are not yet a
verified canonical result. The ensemble operates on the logit scale and emits
`logit_spread` (alignment uncertainty) for M2.

**M2 (Forecast)** implements a frozen-GAM deployment path with adaptive online
bias correction. The high-level API defaults to frozen deployment; weekly refit
is explicit compatibility/research behavior. The v16 parameterization is coded
as the locked incumbent, but recorded M2 NLL values and saved-artifact names
remain unverified because the private artifacts are absent. Do not present the
current historical M2 LOSO as fully nested validation: it is conditional on
globally selected M0/M1 choices. Untouched 2025-26 is the intended confirmatory
evaluation, and no replay or post-promotion refit is verified by this repository.

See `docs/workflow-status.md` for the status of legacy scripts, rendered HTML,
and the safe production entry points.

Key data for M2 development:
- `data/m1_alignment_tuning_combined.rds` — full M1 grid (67 specs, v5–v7)
- `data/m1_alignment_tuning_v7.rds` — latest M1 grid (k_ref × slope_weight)
- `data/stage1_tuning.rds` — M0 ignition tuned params
- `data/flu_testing_data.csv` — raw surveillance data
- `.claude/memory/` — project memory files for Claude continuity
- `.ai/shared/m2-handoff.md` — detailed handoff document

## Environment Notes

Scripts in `scripts/` have hardcoded Windows paths — set `wd` to the repo root
on your platform. Package code (`R/`, `PAGe/R/`) and QMDs use relative paths.
