# Prospective Deployment Review

Scope reviewed on 2026-04-04:

- `docs/pipeline_overview.qmd`
- `docs/prospective_deployment.qmd`
- `docs/forecast_training.qmd`
- `docs/m1_m2_stacking.qmd`
- `R/pipeline_runtime.R`
- `R/pipeline_bridge.R`
- `R/m2_training.R`
- `R/m2_runtime.R`

This note records the problems that still appear to hold after a fresh scan of
the current pipeline code and Quarto docs, with emphasis on the 2025-26
walk-forward deployment path.

## Confirmed findings

### 1. The documented weekly `M_2` refit is not what the current deployment path executes

The overview says that after ignition, `M_2` is refit each week on historical
data plus current-season rows, with `refit_stage2_weekly()` as the key runtime
function.

But the active deployment code path in `run_prospective_pipeline()` calls
`run_m2_forecast()`, which:

- loads a frozen prefit model from `kit$m2_production$fit`
- constructs one-row `newdata` snapshots
- calls `stats::predict()` directly on that frozen fit
- never calls `refit_stage2_weekly()`

So the 2025-26 runtime shown in `prospective_deployment.qmd` is a
"predict-from-frozen-production-fit" path, not the "weekly refit" path
described in the architecture docs.

References:

- `docs/pipeline_overview.qmd:175`
- `docs/pipeline_overview.qmd:177`
- `docs/pipeline_overview.qmd:191`
- `docs/pipeline_overview.qmd:201`
- `docs/prospective_deployment.qmd:136`
- `docs/prospective_deployment.qmd:147`
- `R/pipeline_runtime.R:300`
- `R/pipeline_runtime.R:311`
- `R/pipeline_runtime.R:403`
- `R/m2_training.R:647`

### 2. The walk-forward cache can silently serve stale deployment results

`docs/prospective_deployment.qmd` caches the full walk-forward object at
`data/deploy_wf_cache.rds` and reuses it whenever the file exists.

There is no invalidation tied to:

- new 2025-26 observations
- `MANUAL_IGN_WEEK`
- code changes in the runtime path
- changes to the loaded kit or tuned spec

That means the HTML page can easily display old deployment results while
appearing current.

References:

- `docs/prospective_deployment.qmd:89`
- `docs/prospective_deployment.qmd:142`
- `docs/prospective_deployment.qmd:155`

### 3. The bridge helper `run_m0_m1_m2_weekly()` is still out of sync with the Stage-2 runtime API

`run_m0_m1_m2_weekly()` currently calls:

- `build_stage2_pseudo_prospective_list(currentSeason = ..., kit = ..., iWeek_hat = ...)`
- `stage2_predict_series(..., exclude = exclude, ...)`

But the actual Stage-2 runtime signatures are:

- `build_stage2_pseudo_prospective_list(currentSeason, template_df, best_mean_nll, iWeek_hat, ...)`
- `stage2_predict_series(pp, stage2_fit, which, horizons, alpha_state, ref_col, exclude_season_re, interval, level, ...)`

So the bridge helper is still passing unsupported arguments and omitting
required ones. If someone treats `run_m0_m1_m2_weekly()` as the canonical
deployment function, it is not reliable in its current form.

References:

- `R/pipeline_bridge.R:361`
- `R/pipeline_bridge.R:393`
- `R/pipeline_bridge.R:409`
- `R/m2_runtime.R:74`
- `R/m2_runtime.R:262`

### 4. The overview still overstates the deployment gating logic for `M_2`

The overview says:

> Within each week: `M_1` aligns -> if `state == "aligning"`, `M_2` refits and forecasts.

The actual current deployment code does not enforce that gate. In
`run_m2_forecast()`, the only state skipped is `pre_ignition`; any non-null
`M_1` result, including `post_peak`, continues to the `M_2` prediction block.

This may or may not match the intended scientific behavior, but it is a
documentation/runtime mismatch right now.

References:

- `docs/pipeline_overview.qmd:191`
- `R/pipeline_runtime.R:341`

### 5. The deployment page describes the current-season `M_2` step as "The production GAM predicts", which matches the code but conflicts with the architecture writeup

The deployment page now explicitly says:

- "`M_2` — Forecast: The production GAM predicts ..."

That matches the current implementation in `run_prospective_pipeline()`.
But it conflicts with the overview and training docs that describe an online
weekly refit.

This is not a separate algorithm bug; it is a documentation split-brain:

- `pipeline_overview.qmd` and `forecast_training.qmd` describe weekly refit
- `prospective_deployment.qmd` and `pipeline_runtime.R` execute frozen-fit prediction

That split makes it too easy to misread 2025-26 results.

References:

- `docs/prospective_deployment.qmd:136`
- `docs/pipeline_overview.qmd:175`
- `docs/forecast_training.qmd:339`
- `R/pipeline_runtime.R:311`

## What I rechecked that looks improved

I specifically rechecked the earlier concern that `M_2` training used
optimistic historical `M_1` features built from a single production reference.

The current joint LOSO path in `loso_m1_m2_joint()` now appears to do the right
high-level thing:

- fit the reference on training seasons only
- run `M_1` walk-forward on training seasons
- train `M_2` with those `M_1` predictions
- run `M_1` walk-forward on the held-out test season
- evaluate `M_2` on that held-out season

So that specific training/deployment mismatch is not a confirmed current issue
from this re-scan.

References:

- `docs/forecast_training.qmd:374`
- `docs/m1_m2_stacking.qmd:176`
- `R/pipeline_bridge.R:550`
- `R/pipeline_bridge.R:603`

## Practical implication for the 2025-26 results

The suspicious 2025-26 behavior can plausibly come from deployment-path logic,
not only from model weakness.

The highest-probability causes are:

1. the runtime is using a frozen `M_2` fit instead of the documented weekly
   refit
2. the deployment cache may be serving stale outputs
3. there is no single canonical runtime path because the bridge helper and the
   active deployment function disagree

## Recommended fix order

1. Decide which deployment behavior is actually intended:
   weekly `refit_stage2_weekly()` or frozen-fit prediction.
2. Make `pipeline_overview.qmd`, `forecast_training.qmd`,
   `prospective_deployment.qmd`, and `R/pipeline_runtime.R` agree on that
   choice.
3. Remove or invalidate `deploy_wf_cache.rds` based on season data, kit hash,
   or code version.
4. Repair `run_m0_m1_m2_weekly()` so it matches the current Stage-2 runtime
   function signatures, or stop exposing it as a supported path.
