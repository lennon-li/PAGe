# M1 Implementation

## Main files

- `R/m1_reference.R`
- `R/m1_hyperparams.R`
- `R/m1_runtime.R`
- `R/m1_multi_template.R`
- `R/m1_loso.R`
- `flualign/R/` mirror files with the same names

## Key functions

- `flagIgnition()`: prepares training seasons using ignition labels
- `alignIgnition()`: shifts seasons into aligned-week space
- `estimateRef()`: fits the reference representation, including the FS template curves
- `learn_alignment_hyperparams()`: calibrates bounds and alignment hyperparameters
- `align_multi_template()`: aligns to each training-season template and ensembles them
- `run_alignment_prospective()`: single-template runtime path
- `run_alignment_prospective_multi()`: multi-template runtime path used by the tuned pipeline
- `loso_walkforward()`: prospective M1 evaluation across held-out seasons
- `tune_m1_alignment()`: grid search over M1 hyperparameters

## Training flow

1. Use `flagIgnition()` and `alignIgnition()` to put historical seasons into a common aligned space
2. Fit the reference object with `estimateRef()`
3. Learn calibration and alignment bounds with `learn_alignment_hyperparams()`
4. Run `loso_walkforward()` so each held-out season is forecast prospectively week by week
5. Tune the multi-template settings with `tune_m1_alignment()`
6. Persist the reference and M1 parameters into the production cache consumed at runtime

## Runtime flow

1. `load_prospective_kit()` loads `ref`, `hyper`, and stored `M1_PARAMS`
2. `run_m1_alignment()` in `R/pipeline_runtime.R` starts at `max(walk_start, iWeek_locked)`
3. For each evaluation week, it slices the current season up to that week
4. It calls `run_alignment_prospective_multi()` to get current-state alignment results
5. The returned `params_df`, `m1_curves`, and per-week objects are passed into M2

## Important implementation details

- The tuned deployment path is multi-template, not a single pooled reference
- Dynamic temperature broadens the ensemble early and sharpens it later
- Slope-aware weighting adjusts template weights using recent growth behavior
- Alignment freezing after peak is a design constraint, not just a plotting choice

## Adjacent code

- Pipeline wrapper: `R/pipeline_runtime.R`
- M2 bridge helpers: `R/pipeline_bridge.R`
- Tuning script: `scripts/tune_m1_alignment.R`

## References

- [[M1-Model]]
- [[M2-Implementation]]
