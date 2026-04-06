# M2 Handoff: What's Done and What's Next

## Status as of 2026-07-14

**M0 (Ignition Detection)**: Complete and tuned. Detects season start prospectively.

**M1 (Alignment)**: Complete and tuned. Multi-template ensemble alignment with:
- k_ref=25, multi_temperature=0.25, template_shift=0, align_rise_weight=1.0
- LOSO Weibull-weighted peak MAE = 1.169 weeks (153-spec grid search)
- Uses factor-smooth (FS) reference curves via `estimateRef(method="fs")`

**M2 (Forecast)**: Implemented. Joint binomial GAM (`mgcv::bam`) for h=1,2
week-ahead positivity prediction. Two deployment modes:

- **`frozen`** — Uses pre-trained GAM without refitting. Fastest.
- **`weekly_refit`** — Refits the GAM each week with current-season data appended
  to historical training data. Adapts to the live season.

Best tuned spec (v8 nested LOSO): `Kr=1, k_f=7, k_e=2, alpha_state=0.02, k_1=4`.

## M2 Architecture

M2 consumes M1 alignment covariates + raw features to produce 2-week-ahead forecasts.

### GAM Formula (tuned spec)
```
cbind(y_lead, N_lead - y_lead) ~ -1 + lead + s(season, bs='re')
  + s(logit_f_eff, by=lead, bs='ts', k=7)  # M1-based template
  + s(z_ema, by=lead, bs='ts', k=2)        # EWMA state
  + s(d1_now, by=lead, bs='ts', k=4)       # logit-scale slope
```

### Key Functions
- `prep_stage2_joint()` (m2_training.R) — single source of truth for feature engineering
- `train_stage2_joint()` (m2_training.R) — GAM training wrapper
- `refit_stage2_weekly()` (m2_training.R) — weekly refit combining hist + current
- `run_m2_forecast()` (pipeline_runtime.R) — deployment prediction (both modes)
- `run_prospective_pipeline()` (pipeline_runtime.R) — full M0→M1→M2 wrapper
- `nested_loso_grid_search()` (m2_nested_loso.R) — LOSO grid search for tuning

### Key Data Files
- `data/m2_production.rds` — trained M2 GAM + spec
- `data/ref_production.rds` — reference curve and M1 params
- `data/m1_alignment_tuning_v3.rds` — M1 tuning results
- `data/stage1_tuning.rds` — M0 ignition tuned params
- `data/flu_testing_data.csv` — raw surveillance data
