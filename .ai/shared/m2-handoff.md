# M2 Handoff: What's Done and What's Next

## Status as of 2026-03-30

**M0 (Ignition Detection)**: Complete and tuned. Detects season start prospectively.

**M1 (Alignment)**: Complete and tuned. Multi-template ensemble alignment with:
- k_ref=25, multi_temperature=0.25, template_shift=0, align_rise_weight=1.0
- LOSO Weibull-weighted peak MAE = 1.169 weeks (153-spec grid search)
- Uses factor-smooth (FS) reference curves via `estimateRef(method="fs")`
- Experimental slope weighting + dynamic temperature added (marginal improvement)

**M2 (Forecast)**: NOT YET IMPLEMENTED — this is the next step.

## M2 Architecture (from pipeline_overview.qmd)

M2 produces 1-2 week ahead positivity forecasts using M1's alignment outputs as covariates.

### Inputs from M1 (per eval_week)
Available in `params_df` from `loso_walkforward()`:
- `tau` — time shift estimate
- `delta` — dilation estimate
- `a`, `b` — intercept and amplitude
- `t_peak` — estimated peak timing (aligned scale)
- `peak_weekF` — estimated peak week (calendar scale)
- `peak_passed` — boolean flag
- `iWeek_hat` — estimated ignition week
- `eval_week` — current weekF

### Raw features to add
- Current positivity `p` and recent trend (Δp over last 2-3 weeks)
- Growth rate (logit-scale slope)
- Weeks since ignition (`eval_week - iWeek_hat`)
- Template weights from multi-template ensemble (which historical season matches best)

### Why M2 matters
M1 alignment is shape-matching — it can't adapt when the current season is unlike any template. 2025-26 peaked at weekF=25 (latest in training data), and M1 overestimated peak by 2-3 weeks consistently. M2 can learn these systematic biases from features like growth rate (steep rise → earlier peak than M1 predicts).

### Training data
`loso_walkforward()` produces `params_df` and `forecast_df` per season via LOSO. The `params_df` rows (one per season × eval_week) are the natural training set for M2, with true peak timing and true positivity as targets.

## Key files for M2 development

### Must read first
- `docs/pipeline_overview.qmd` — full architecture description including M2 section
- `flualign/R/loso_alignment.R` — `loso_walkforward()` (produces M1 outputs for M2)
- `flualign/R/align_multi_template.R` — multi-template alignment (produces weights, per-template diagnostics)

### Data files
- `data/m1_alignment_tuning_v3.rds` — M1 tuning results (153 specs)
- `data/align_multi_cache.rds` — will be regenerated; LOSO walkforward cache with best M1 params
- `data/stage1_tuning.rds` — M0 ignition detection tuned params
- `data/flu_testing_data.csv` — raw surveillance data

### Existing M2 scaffolding
Check `docs/pipeline_overview.qmd` section on M2 for the planned architecture. No M2 code exists yet.

## Server setup notes

1. Install R packages: `install.packages(c("dplyr", "tidyr", "ggplot2", "mgcv", "gamm4", "gratia", "furrr", "future", "purrr", "gt", "plotly", "MMWRweek", "data.table"))`
2. Install flualign: `devtools::install("flualign")` from the repo root
3. For parallel work: `future::plan(multisession)` — adjust worker count for server cores
4. Scripts in `scripts/` have hardcoded Windows paths (`C:/Users/lennon.li/...`) — use `here::here()` or set `wd` to repo root on the server
5. QMDs use relative paths and should work from `docs/` directory
6. Memory files are in `.claude/memory/` within the repo for reference
