# M2 Implementation

## Main files

- `R/m2_training.R`
- `R/m2_nested_loso.R`
- `R/pipeline_runtime.R`
- `R/pipeline_bridge.R`
- `flualign/R/` mirror files with the same names

## Key functions

- `prep_stage2_joint()`: single source of truth for M2 feature engineering — all paths must pass through this
- `train_stage2_joint_prepped()`: fits the binomial GAM after data prep
- `train_stage2_joint()`: convenience wrapper — prep + fit in one call
- `m2_predict_one()`: shared prediction core for both evaluation and deployment
- `refit_stage2_weekly()`: weekly refit appending current-season rows to historical data
- `nested_loso_build_fold()`: constructs leakage-safe train/test fold objects
- `nested_loso_m2_train()`: trains M2 inside a fold
- `nested_loso_m2_eval_frozen_bias()`: evaluates fold forecasts with frozen GAM + sequential Holt bias correction (production-equivalent)
- `nested_loso_grid_search()`: full nested LOSO spec sweep
- `run_m2_forecast()`: deployment entry point
- `run_prospective_pipeline()`: top-level wrapper for M0 → M1 → M2

## Training flow

1. Build an M2 spec grid with `stage2_make_spec()`
2. For each held-out season, call `nested_loso_build_fold()` to create a leakage-safe fold
3. Recreate reference and M1 predictions using only training seasons (no leakage)
4. Build M2 features with `prep_stage2_joint()`
5. Train fold-specific GAMs with `train_stage2_joint()`
6. Score the held-out season with `nested_loso_m2_eval_frozen_bias()` (frozen GAM + Holt correction)
7. Select best spec; refit on all historical seasons with `nested_loso_refit_best()` → save to `m2_production.rds`

## Runtime flow

1. `load_prospective_kit()` loads ref cache, M0 params, and `m2_production.rds`
2. `run_m0_detection()` resolves ignition week
3. `run_m1_alignment()` generates per-week alignment state
4. `run_m2_forecast()` (frozen mode) iterates over eval weeks:
   - Updates Holt bias level from newly observed positivity
   - Calls `m2_predict_one()` with `include_season_re = FALSE` (frozen GAM)
   - Applies `bias_level` correction on the logit scale
5. Returns per-week forecast data frame with h1/h2 predictions and CIs

## Important implementation details

- `prep_stage2_joint()` is the critical consistency point; training, LOSO eval, and deployment must all call it
- `m2_predict_one()` centralises factor handling, excluded terms, soft caps, and CI behaviour
- Bias correction is **level-only Holt EMA** (`alpha = 0.4`), per-horizon, reset at peak transition
- `load_prospective_kit()` loads `hist_data` and `m1_train_preds` for weekly-refit consistency with tuning
- Retired/legacy functions live in `R/retired.R` — do not call them from new code

## Artifacts

- `data/m2_production.rds` — production GAM, spec, M1 train preds
- `data/nested_loso_v12_production.rds` — v12 LOSO results (best: NLL 33.49)
- `data/ref_production.rds` — reference curve, M1 hyperparams, hist_data
- `data/stage1_tuning.rds` — M0 ignition tuned params
- `data/m1_alignment_tuning_v3.rds` — M1 alignment tuning results

## References

- [[M2-Model]]
- [[M1-Implementation]]
- [[PAGe-Home]]
