# M0 Implementation

## Main files

- `R/m0_training.R`
- `R/m0_runtime.R`
- `flualign/R/m0_training.R`
- `flualign/R/m0_runtime.R`

## Key functions

- `fitIgnition()`: fits the ignition scoring model on labeled historical data
- `detectIgnitionBySeason_M0v2()`: applies the four-gate ignition logic
- `detectIgnition_oneSeason()`: single-season wrapper used in runtime code
- `tuneIgnitionGrid_M0v2()`: grid-search tuning for detector thresholds
- `loso_M0v2()`: strict LOSO evaluation that refits per fold
- `run_ignition_weekly()`: prospective weekly monitoring entry point

## Training flow

1. Build training labels around known ignition windows with `fitIgnition()`
2. Fit scoring models on historical seasons
3. Tune gate parameters with `tuneIgnitionGrid_M0v2()`
4. Validate prospectively with `loso_M0v2()`
5. Save tuned parameters to `data/stage1_tuning.rds`

## Runtime flow

1. `load_prospective_kit()` loads `stage1_tuning.rds`
2. `run_m0_detection()` in `R/pipeline_runtime.R` calls `run_ignition_weekly()`
3. If ignition is found, the locked week is carried into M1
4. Optional manual override can replace the automatic ignition week

## Important implementation details

- M0 is designed to be prospective: only data available up to the current week is used
- The locked ignition week becomes the coordinate anchor for the rest of the pipeline
- Runtime code is separated from training code so deployment can use frozen tuned parameters

## Adjacent code

- Pipeline wrapper: `R/pipeline_runtime.R`
- Bridge helpers: `R/pipeline_bridge.R`
- Training scripts: `scripts/tune_targeted.R`, `scripts/weighted_vote.R`

## References

- [[M0-Model]]
- [[M1-Implementation]]
