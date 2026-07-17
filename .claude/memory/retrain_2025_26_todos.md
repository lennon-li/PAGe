# Retrain Pipeline TODOs (2025-26 Season Insights)

Following the autonomous retrain pipeline execution on the Venkata remote worker for the 2025-26 season, the following architectural and usability improvements were identified:

## 1. M2 Holdout Leakage Check (`replay_season_holdout`)
**Issue:** `replay_season_holdout()` correctly enforces strict holdout leakage prevention (`Holdout leakage: season X is present in kit training seasons`). However, this strict gate prevents us from using the built-in function to easily generate retrospective walk-forward evaluation plots on the training set (e.g., inside QMD reports).
**Action:** Add an `allow_leakage = FALSE` parameter to `replay_season_holdout()`. When `TRUE`, bypass the stop condition and run `run_prospective_pipeline` so we don't have to write custom loops for QMD plotting.

## 2. `future::multisession` Environment Isolation
**Issue:** When running the `train_pipeline` via `future::plan(multisession)` on a remote worker, the background R sessions crash if the user only loaded the package using `devtools::load_all()`. Background `future` sessions rely on `.libPaths()` and cannot inherit the devtools pseudo-installation, meaning they fail to find `PAGe` functions.
**Action:** Add a check in `train_pipeline()` (or the M2 grid runner) that detects if the user is running `load_all()` while requesting a `multisession` plan. If detected, warn/stop and instruct the user to run `devtools::install()` first.

## 3. PHO Data Ingestion (`getCurrentD`)
**Issue:** Appending the current season's live PHO data to the historical `.csv` required manual transformations (schema alignment, renaming `y`, `N`, `weekF` types, and handling overlapping edge weeks between the historical set and live pull).
**Action:** Implement an `append_live_surveillance(history_df, current_df)` helper function in the package that standardizes schemas, handles overlapping weeks (e.g., preferring the live feed for duplicates), and strictly outputs a `prepare_surveillance_data()` compliant dataframe.
