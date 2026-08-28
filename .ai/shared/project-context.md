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

- `PAGe/` is the installable package and the sole source of package code.
- Package R source lives under `PAGe/R/`; do not add or restore a root-level
  `R/` mirror.
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
- Inspect every genuinely tuned axis for a boundary winner before freezing a
  stage. Expand one adjacent valid step, or document a meaningful null/hard
  constraint. Keep all expansion pre-holdout and follow
  `docs/tuning-playbook.md`.
- Supervise long-running local jobs with a detached, zero-token OS watchdog.
  Do not keep a persistent AI goal/session alive for periodic polling, and do
  not schedule recurring model wake-ups, unless the user explicitly approves
  both the cadence and a token budget. The AI handles launch/preflight, resumes
  on a detected exception, and performs one bounded terminal audit. Watchdogs
  write compact machine-readable status; AI log reads must be bounded and must
  exclude generated HTML and full warning streams. Follow
  `docs/long-job-supervision.md`.

## Current Status (audited 2026-08-01)

The package exposes guarded stage lifecycles for M0, M1, and M2. A governed
workflow declares disjoint season sets with `validate_season_selection()`, then
runs `tune_*() -> validate_*_tuning() -> fit_*() -> freeze_*()` in stage order.
M1 requires a frozen matching M0; M2 requires the exact frozen M0/M1 identity
chain; governed `assemble_kit()` rejects drafts and provenance mismatches.
`train_pipeline()` composes these contracts for both refresh and retune modes,
including explicit season selection and governed M2 racing full evaluation;
its compatibility result shape is preserved through payload unwrapping.

**M0 (Ignition)** and **M1 (Alignment)** are implemented and have historical
tuning workflows. M1 uses multi-template alignment with slope-similarity
weighting; the published historical peak-MAE values conflict and are not yet a
verified canonical result. The ensemble operates on the logit scale and emits
`logit_spread` (alignment uncertainty) for M2.

**M2 (Forecast)** implements a frozen-GAM deployment path with adaptive online
bias correction. The high-level API defaults to frozen deployment; weekly refit
is explicit compatibility/research behavior. The existing private
`v16-corrected` frozen kit is now the working incumbent (`alpha_state=0.20`,
`k_sp=8`, `bias_alpha=0.05`); its exact historical lineage is not fully
reconstructible, so it is retained as a confidence baseline. A local
boundary-only evaluation selected a
`bias_alpha=0` candidate, but its frozen `2025-26` acceptance replay failed the
locked NLL gate (`0.0000482` improvement versus `0.02` required); horizon and
phase gates passed. The incumbent remains accepted, and no refit or promotion
occurred. Do not present the historical M2 LOSO as fully nested validation: it
is conditional on globally selected M0/M1 choices. Further tuning against this
holdout is prohibited; any search must begin a new pre-holdout cycle.

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
on your platform. Package code (`PAGe/R/`) and QMDs use relative paths.

## Current run state (2026-08-16)

- Canonical artifact root: `/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812`.
  This is the BCC-backed archive mounted on Asgard; `/mnt/storage1` is
  currently read-only and is not a destination for new artifacts.
- Audited holdout replays are preserved for 2016-17, 2017-18, 2018-19,
  2022-23, 2023-24, 2024-25, and 2025-26. Counts differ with ignition and
  observed holdout coverage because each row is an origin/horizon forecast.
- `2015/run_2015_api_cycle.R` is the governed 2015-16 runner. It excludes the
  holdout from training, settles M0 before M1 and M1 before M2, expands
  unresolved boundaries, saves stage artifacts, and performs a strict unseen
  replay under `holdouts-and-docs/2015-16` in the canonical archive.
