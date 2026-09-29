# PAGe v3 calibrated M1-B chronological benchmark plan

Date: 2026-09-25
Status: audited revision; conditional research benchmark, not governed promotion

## Objective

Build a calibrated, B-only M1-B stage by reusing the frozen M1-v2 timing machinery without modifying frozen package code.

M1-A remains frozen M1-v2. The failed A-conditioned M1-B1 branch remains stopped.

This benchmark is **conditional on the current globally selected B activity rule**. It is not called governed because the B activity rule/window was selected with knowledge of all historical seasons. A later governance pass must refit/freeze activation causally before any production claim.

## Frozen machinery

Reuse unchanged:

- `fit_m1_v2_library()`
- `m1_v2_peak_posterior()`
- `m1_v2_passage_posterior()`
- `m1_v2_passage_decision()`
- `fit_m1_v2_bias_calibrator()`
- `m1_v2_apply_bias_calibration()`
- `fit_m1_v2_passage_policy()`
- `build_m1_v2_timing()`

## Type-B inputs

Canonical panel:

`artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv`

Timing/activity contract:

`artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv`

Use:

- `y_B -> y`
- `N_B -> N`
- `p_B -> p`
- B retrospective peak truth only when `B_peak_status == retrospective_peak_truth`
- B transferred-rule activity marker only as causal activation state

2018-19 remains reviewed `no_meaningful_activity / no_meaningful_peak` and is excluded from B peak fitting/scoring.

## Activation provenance adapter

Frozen M1-v2 training deliberately requires a `page_m1_v2_activation_table`. For B research, create an explicit adapter carrying the required integrity attributes but **never claiming M0-A provenance**.

Adapter fields:

- `season`
- `activation_origin_week = B_activity_integer`
- `activation_week_decimal = B_activity_weekF`

Adapter attributes:

- `m0_loso_context_id = "v3-B-activity-A-rule-transfer-w8_40:<timing-contract-sha>"`
- `activation_provenance_id = sha256(marker payload + timing-contract hash + B detector RDS hash)`
- `activation_payload_hash` computed using the frozen `.m1_v2_activation_payload()` hashing rule

Class:

`c("page_m1_v2_activation_table", "data.frame")`

This is a research compatibility adapter only. Artifacts must label activation semantics as `exploratory_transferred_A_rule`, not M0 truth.

## Known activation limitation

Current B activity markers use A-rule parameters and an 8–40 B window selected with knowledge of the full historical archive. Therefore:

- results are conditional on a globally selected activation rule;
- this benchmark cannot support production/governance promotion by itself;
- B activation ±1 week sensitivity is required;
- a future governance pass must refit/freeze activation strictly chronologically or prospectively.

## B-specific configuration

Reuse frozen M1-v2 defaults except B amplitude integration support:

- `k = 8`
- peak grid `0.01`
- tau grid `0.1`
- B amplitude grid `seq(0.005, 0.25, by = 0.005)`
- calibration origins `4`
- calibration candidate step `0.2`
- passage candidate step `0.2`
- scored posterior candidate step `0.1`

The B amplitude grid was selected with knowledge of the full archive and is disclosed as research support selection, not outer-fold tuning.

## Chronological folds

Use the existing expanding-window ledger. For each eligible B test season:

`training seasons = strictly earlier seasons ∩ meaningful B peak seasons`

Minimum support remains four training B seasons for parity with the existing B0 benchmark.

2017-18 is predeclared **low-support** because its outer fold has only four B timing seasons and inner calibration fits can have only three seasons.

Report headline metrics both:

- all eligible test seasons;
- excluding low-support 2017-18.

## Stage construction

For each chronological fold, build the complete type-B stage in one call:

`build_m1_v2_timing(..., amplitude_grid = B_AMP_GRID)`

using only prior meaningful-B training seasons and their B activation adapter.

Record:

- stage artifact ID;
- library hash;
- calibration offset;
- passage-policy selected thresholds;
- all calibrator per-season signed errors;
- all calibrator inner predictions;
- observation regimes represented in the fold.

## Calibration diagnostics

The historical observation regime changes materially across seasons, so every result must be stratified by test-season denominator regime.

Record per fold:

- calibration offset;
- inner season signed errors;
- whether any calibration origin has `asof_boundary > B_peak_truth`;
- count of proxy-regime versus type-specific training seasons.

Diagnostic-only sensitivity:

- for folds after 2022-23, recompute the scalar calibrator excluding 2022-23 from the calibrator estimation while leaving the library unchanged;
- label this diagnostic only; it cannot be promoted from the same run.

## Peak forecast evaluation

Use exactly the existing B0 test-season/origin set.

For every origin:

1. compute raw B posterior;
2. apply fold-trained scalar calibration;
3. save raw and calibrated mean/median/MAP/q05/q95;
4. score raw and calibrated outputs against B peak truth.

No silent origin dropping. Any error is written as an explicit failure row and causes the benchmark to fail unless predeclared as unsupported.

Calibration alters location summaries only; raw passage posterior remains unchanged.

## Passage replay

Replay sequentially from B activation through:

`min(season_end, (ceiling(B_peak_truth) - 1) + 6)`

using:

- `m1_v2_passage_posterior()`
- fold-selected policy from `fit_m1_v2_passage_policy()`
- all selected thresholds including `fast_drop_fraction`

Record first confirmation, branch, false-early status, early magnitude, confirmed by peak+2, and delay.

2018-19 receives an explicit runtime/evaluation row:

- `activity_detected = FALSE`
- `M1_B_state = inactive_no_meaningful_activity`
- `timing_scored = FALSE`

No peak or passage is forced.

## Leakage and integrity tests

At every scored origin:

- perturb future B observations -> raw/calibrated prediction unchanged;
- perturb future B observations -> passage posterior/history through origin unchanged;
- calibrator/passage policy library hash equals fold library hash;
- held-out test peak truth is absent from fitting inputs;
- later seasons absent from fold training.

Additional checks:

- perturbing 2018-19 must not affect any fold where it is excluded from meaningful-B timing training;
- exact B0 raw recomputation must match the existing chronological baseline;
- activation ±1 week sensitivity must be emitted separately.

## Predeclared interpretation thresholds

This research stage is considered **historically promising** only if all are met:

- calibrated season-balanced MAE <= raw B0 MAE;
- calibrated early-weighted MAE <= raw B0 early-weighted MAE;
- worst-season calibrated MAE no worse than raw by more than 0.5 week;
- at most 2 scored seasons worsen in MAE;
- passage false-early seasons = 0;
- calibrated 90% interval coverage >= 0.70;
- no leakage/integrity failure.

Meeting these thresholds does **not** make the stage governed because activation remains globally selected.

## Required outputs

`artifacts/v3-m1-b-calibrated-chronological-v1/`

- `fold_ledger.csv`
- `stage_ledger.csv`
- `calibrator_inner_predictions.csv`
- `per_origin_predictions.csv`
- `per_season_metrics.csv`
- `summary_metrics.csv`
- `summary_excluding_low_support.csv`
- `metrics_by_denominator_regime.csv`
- `passage_by_season.csv`
- `passage_summary.csv`
- `future_perturbation_checks.csv`
- `activation_sensitivity.csv`
- `calibrator_leave_2022_diagnostic.csv`
- `inactive_no_event_seasons.csv`
- `source_manifest.csv`
- `benchmark_config.csv`

## Decision path

If the calibrated B-only stage fails the predeclared thresholds, retain raw M1-B0 and stop calibration complexity.

If it passes, the next step is a separate activation-governance exercise before M1-B can be called governed or connected to a production M2-B timing gate.
