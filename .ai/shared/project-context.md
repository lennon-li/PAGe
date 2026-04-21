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
- Built-in historical data lives in `PAGe/inst/extdata/flu_hist.csv` and
  `PAGe/ref_curve.RData`.

## Current Status (2026-04-21)

**M0 (Ignition)** and **M1 (Alignment)** are complete and tuned. M1 uses
multi-template ensemble alignment with slope-similarity weighting:
k_ref=25, temperature=0.25, slope_weight=8.0, slope_window=6, dynamic_temp=FALSE, ref_method="fs"
(LOSO Weibull-weighted peak MAE = 1.275 weeks across 67-spec grid search, v5–v7).
Ensemble operates on logit scale; outputs logit_spread (alignment uncertainty)
propagated to M2.

**M2 (Forecast)** is tuned through v15-postfix. Production kit at
`data/m2_production.rds` (v15-postfix spec: k_f=5, k_e=2, alpha_state=0.40,
k_r=0, k_de=0, k_sp=2, delta=0, Kr=1, bias_alpha=0.5, bias_beta=0). Frozen GAM
+ adaptive Holt EMA bias correction (level-only β=0; bias_alpha=0.5 tuned via
LOSO and robustness probe). 7200-spec nested LOSO (v15-postfix), Bernoulli NLL
= 0.5959 pre-L2 / 0.5796 post-L2 (L2 fix: walk-forward estimateDerivs in test
fold). Entry-point: `scripts/run_nested_loso_v15_postfix.R`.

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
