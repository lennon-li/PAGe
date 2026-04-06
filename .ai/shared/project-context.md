# PAGe Project Context

## Project Goal

PAGe (Phase-Aligned Gated Epidemic Forecasting) forecasts seasonal respiratory
virus percentage positivity 1 to 2 weeks ahead using surveillance data.

Primary deliverables:

1. A trained, validated forecasting model for 2-week-ahead positivity
   prediction.
2. The `flualign` R package, implemented as a clean, documented, installable
   package.

Evaluation must stay prospective and walk-forward. Avoid data leakage from
future seasons.

## Repository Layout

- `flualign/` is the installable package and source of truth for package code.
- `R/` is a root-level mirror of `flualign/R/` used for development
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
- Built-in historical data lives in `flualign/inst/extdata/flu_hist.csv` and
  `flualign/ref_curve.RData`.

## Current Status (2026-03-30)

**M0 (Ignition)** and **M1 (Alignment)** are complete and tuned. M1 uses
multi-template ensemble alignment: k_ref=25, temperature=0.25, shift=0
(LOSO Weibull-weighted peak MAE = 1.169 weeks across 153-spec grid search).

**M2 (Forecast)** is the next step. It should consume M1's alignment covariates
(τ, δ, peak_weekF, etc.) plus raw features (growth rate, current positivity) to
produce 2-week-ahead forecasts. See `docs/pipeline_overview.qmd` for M2 design.

Key data for M2 development:
- `data/m1_alignment_tuning_v3.rds` — M1 tuning results
- `data/stage1_tuning.rds` — M0 ignition tuned params
- `data/flu_testing_data.csv` — raw surveillance data
- `.claude/memory/` — project memory files for Claude continuity
- `.ai/shared/m2-handoff.md` — detailed handoff document

## Environment Notes

Scripts in `scripts/` have hardcoded Windows paths — set `wd` to the repo root
on your platform. Package code (`R/`, `flualign/R/`) and QMDs use relative paths.
