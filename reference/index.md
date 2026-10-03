# Package index

## Data and simulation

Load, validate, and simulate surveillance data.

- [`load_flu_hist()`](https://lennon-li.github.io/PAGe/reference/load_flu_hist.md)
  : Load historical influenza surveillance data
- [`getCurrentD()`](https://lennon-li.github.io/PAGe/reference/getCurrentD.md)
  : Fetch and tidy current-season PHO respiratory surveillance data
- [`simulate_flu_seasons()`](https://lennon-li.github.io/PAGe/reference/simulate_flu_seasons.md)
  : Simulate synthetic flu seasons for package examples
- [`checkSeasonLength()`](https://lennon-li.github.io/PAGe/reference/checkSeasonLength.md)
  : Compute in-season length for each season
- [`resolve_week_override()`](https://lennon-li.github.io/PAGe/reference/resolve_week_override.md)
  : Resolve a week estimate with an optional manual override

## Build and train

Construct model stages and assemble a deployment kit.

- [`build_m0()`](https://lennon-li.github.io/PAGe/reference/build_m0.md)
  : Build aligned training data using M0 ignition detection
- [`build_m1()`](https://lennon-li.github.io/PAGe/reference/build_m1.md)
  : Build M1 reference curve and alignment hyperparameters
- [`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md)
  : Build M2 forecast model via nested LOSO grid search
- [`train_m2()`](https://lennon-li.github.io/PAGe/reference/train_m2.md)
  : Fit the M2 production GAM on all training seasons
- [`assemble_kit()`](https://lennon-li.github.io/PAGe/reference/assemble_kit.md)
  : Bundle trained artifacts for prospective deployment

## Tune and specify

Tune model stages and create model specifications.

- [`tune_m0()`](https://lennon-li.github.io/PAGe/reference/tune_m0.md) :
  Tune M0 ignition detection hyperparameters via LOSO grid search
- [`tune_m1()`](https://lennon-li.github.io/PAGe/reference/tune_m1.md) :
  Tune M1 alignment hyperparameters via LOSO grid search
- [`tune_m1_alignment()`](https://lennon-li.github.io/PAGe/reference/tune_m1_alignment.md)
  : LOSO grid search over M1 alignment hyperparameters
- [`default_m1_grid()`](https://lennon-li.github.io/PAGe/reference/default_m1_grid.md)
  : Return the default M1 alignment tuning grid
- [`default_m2_grid()`](https://lennon-li.github.io/PAGe/reference/default_m2_grid.md)
  : Return the default M2 forecast tuning grid
- [`m1_make_params()`](https://lennon-li.github.io/PAGe/reference/m1_make_params.md)
  : Construct an M1 alignment parameter list
- [`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md)
  : Create a Stage-2 training specification (hyperparameters + derived
  objects)

## Prospective runtime

Run individual stages or the complete weekly pipeline.

- [`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md)
  : Load pre-built model artifacts for prospective deployment
- [`run_m0_detection()`](https://lennon-li.github.io/PAGe/reference/run_m0_detection.md)
  [`run_m0()`](https://lennon-li.github.io/PAGe/reference/run_m0_detection.md)
  : Run M0 ignition detection for the current season
- [`run_m1_alignment()`](https://lennon-li.github.io/PAGe/reference/run_m1_alignment.md)
  [`run_m1()`](https://lennon-li.github.io/PAGe/reference/run_m1_alignment.md)
  : Walk-forward M1 alignment for the current season
- [`run_m2_forecast()`](https://lennon-li.github.io/PAGe/reference/run_m2_forecast.md)
  [`run_m2()`](https://lennon-li.github.io/PAGe/reference/run_m2_forecast.md)
  : Run M2 forecast using M1 alignment outputs
- [`run_prospective_pipeline()`](https://lennon-li.github.io/PAGe/reference/run_prospective_pipeline.md)
  [`run_pipeline()`](https://lennon-li.github.io/PAGe/reference/run_prospective_pipeline.md)
  : Run the full M0 -\> M1 -\> M2 walk-forward pipeline for one season

## Plotting and diagnostics

- [`plot_cls_models_by_season()`](https://lennon-li.github.io/PAGe/reference/plot_cls_models_by_season.md)
  : Plot classifier scores by season and model
- [`plot_det_facet()`](https://lennon-li.github.io/PAGe/reference/plot_det_facet.md)
  : Plot ignition detection results (faceted)
- [`plot_forecast()`](https://lennon-li.github.io/PAGe/reference/plot_forecast.md)
  : Plot a PAGe 2-week-ahead forecast
- [`plot_ignition_detect_vs_truth()`](https://lennon-li.github.io/PAGe/reference/plot_ignition_detect_vs_truth.md)
  : Plot truth vs detected ignition week by season (faceted)
- [`plot_ignition_weekly_snapshots()`](https://lennon-li.github.io/PAGe/reference/plot_ignition_weekly_snapshots.md)
  : Extract Stage-2 hyperparameters from tuning output
- [`plot_nested_loso_predictions()`](https://lennon-li.github.io/PAGe/reference/plot_nested_loso_predictions.md)
  : Plot nested LOSO predictions by season
- [`plot_nll_sensitivity()`](https://lennon-li.github.io/PAGe/reference/plot_nll_sensitivity.md)
  : Plot metric sensitivity across tuning-grid parameters
- [`plot_season_detection_table()`](https://lennon-li.github.io/PAGe/reference/plot_season_detection_table.md)
  : Per-season ignition detection signal table
- [`plot_stage2()`](https://lennon-li.github.io/PAGe/reference/plot_stage2.md)
  : Plot observed vs Stage-2 forecasts across pseudo-prospective
  snapshots
- [`plot_stage2_joint_fit_by_season()`](https://lennon-li.github.io/PAGe/reference/plot_stage2_joint_fit_by_season.md)
  : Prepare Stage-2 M1 features from aligned prospective data
- [`plotRes()`](https://lennon-li.github.io/PAGe/reference/plotRes.md) :
  Plot alignment results against history and reference curve
- [`plotSeasonCurves()`](https://lennon-li.github.io/PAGe/reference/plotSeasonCurves.md)
  : Plot observed vs fitted positivity by season, with ignition week in
  title

## Lower-level M0, M1, and M2 helpers

Building blocks for advanced development and evaluation.

- [`alignIgnition()`](https://lennon-li.github.io/PAGe/reference/alignIgnition.md)
  : Align within-season week index by shifting ignition to a common
  anchor week
- [`align_forecast_pipeline_dilate()`](https://lennon-li.github.io/PAGe/reference/align_forecast_pipeline_dilate.md)
  : Align and forecast using dilated reference curve
- [`align_multi_template()`](https://lennon-li.github.io/PAGe/reference/align_multi_template.md)
  : Multi-template ensemble alignment and forecast
- [`detectIgnitionBySeason_M0v2()`](https://lennon-li.github.io/PAGe/reference/detectIgnitionBySeason_M0v2.md)
  : Prospective ignition detection (M0v2) across seasons
- [`detectIgnitionBySeason_M0v2_timing()`](https://lennon-li.github.io/PAGe/reference/detectIgnitionBySeason_M0v2_timing.md)
  : Detect ignition with an opt-in fractional week estimate
- [`detectIgnition_oneSeason()`](https://lennon-li.github.io/PAGe/reference/detectIgnition_oneSeason.md)
  : Single-season wrapper around detectIgnitionBySeason_M0v2
- [`detectIgnition_oneSeason_timing_v2()`](https://lennon-li.github.io/PAGe/reference/detectIgnition_oneSeason_timing_v2.md)
  : Single-season fractional M0 detector helper
- [`estimateDerivs()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs.md)
  : Estimate smoothed positivity and derivatives (d1/d2) by season using
  binomial GAMs
- [`estimateDerivs_walkforward()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs_walkforward.md)
  : Compute derivatives for a single season in a causal (walk-forward)
  manner
- [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md)
  : Estimate a reference (template) curve for influenza positivity
- [`estimate_season_re_online()`](https://lennon-li.github.io/PAGe/reference/estimate_season_re_online.md)
  : Estimate season random effect causally from accumulated observations
- [`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md)
  : Fit ignition classifier scores (Stage-1)
- [`fitIgnition_timing_v2()`](https://lennon-li.github.io/PAGe/reference/fitIgnition_timing_v2.md)
  : Fit the M0 classifier using fractional timing targets
- [`fit_final_pipeline()`](https://lennon-li.github.io/PAGe/reference/fit_final_pipeline.md)
  : Fit the final deployment pipeline after nested evaluation
- [`fit_m0()`](https://lennon-li.github.io/PAGe/reference/fit_m0.md) :
  Fit an M0 ignition configuration (draft artifact)
- [`fit_m1()`](https://lennon-li.github.io/PAGe/reference/fit_m1.md) :
  Fit an M1 alignment configuration (draft artifact)
- [`fit_m1_v2_bias_calibrator()`](https://lennon-li.github.io/PAGe/reference/fit_m1_v2_bias_calibrator.md)
  : Fit the M1-v2 early-bias calibrator
- [`fit_m1_v2_library()`](https://lennon-li.github.io/PAGe/reference/fit_m1_v2_library.md)
  : Fit the M1-v2 peak-relative historical library
- [`fit_m1_v2_passage_policy()`](https://lennon-li.github.io/PAGe/reference/fit_m1_v2_passage_policy.md)
  : Fit the M1-v2 passage-confirmation policy
- [`fit_m2()`](https://lennon-li.github.io/PAGe/reference/fit_m2.md) :
  Fit an M2 forecast configuration (draft artifact)
- [`fit_m2_a_ntrend_shadow()`](https://lennon-li.github.io/PAGe/reference/fit_m2_a_ntrend_shadow.md)
  : Tune a causal test-volume trend for the M2-A state forecast
- [`fit_m2_offset_correction()`](https://lennon-li.github.io/PAGe/reference/fit_m2_offset_correction.md)
  : Fit a regularized binomial M2 offset correction.
- [`fit_peak_calibration()`](https://lennon-li.github.io/PAGe/reference/fit_peak_calibration.md)
  : Fit peak calibration model from LOSO walk-forward results
- [`flagIgnition()`](https://lennon-li.github.io/PAGe/reference/flagIgnition.md)
  : Flag influenza ignition week (4-rule minimal version)
- [`forecast_post_peak_gam()`](https://lennon-li.github.io/PAGe/reference/forecast_post_peak_gam.md)
  : Post-peak GAM forecast without further alignment
- [`inject_m1_into_snapshots()`](https://lennon-li.github.io/PAGe/reference/inject_m1_into_snapshots.md)
  : Replace logit_f_eff in M2 snapshots with M1's aligned prediction
- [`learn_alignment_hyperparams()`](https://lennon-li.github.io/PAGe/reference/learn_alignment_hyperparams.md)
  : Learn tau/delta bounds and penalty from historical seasons
- [`loso_walkforward()`](https://lennon-li.github.io/PAGe/reference/loso_walkforward.md)
  : Walk-forward alignment evaluation with LOSO reference curves
- [`m1_fit()`](https://lennon-li.github.io/PAGe/reference/m1_fit.md) :
  Fit M1
- [`m1_make_params()`](https://lennon-li.github.io/PAGe/reference/m1_make_params.md)
  : Construct an M1 alignment parameter list
- [`m1_passage_posterior()`](https://lennon-li.github.io/PAGe/reference/m1_passage_posterior.md)
  : Compute the M1 peak-passage posterior
- [`m1_peak_posterior()`](https://lennon-li.github.io/PAGe/reference/m1_peak_posterior.md)
  : Compute the M1 peak-time posterior
- [`m1_predict()`](https://lennon-li.github.io/PAGe/reference/m1_predict.md)
  : Predict timing with M1
- [`m1_v2_activation_table_from_m0_loso()`](https://lennon-li.github.io/PAGe/reference/m1_v2_activation_table_from_m0_loso.md)
  : Construct governed M1-v2 activations from an M0 LOSO result
- [`m1_v2_apply_bias_calibration()`](https://lennon-li.github.io/PAGe/reference/m1_v2_apply_bias_calibration.md)
  : Apply M1-v2 early-bias calibration to forecast summaries
- [`m1_v2_passage_decision()`](https://lennon-li.github.io/PAGe/reference/m1_v2_passage_decision.md)
  : Decide whether M1-v2 peak passage is confirmed
- [`m1_v2_passage_posterior()`](https://lennon-li.github.io/PAGe/reference/m1_v2_passage_posterior.md)
  : Infer M1-v2 peak-passage probability
- [`m1_v2_peak_posterior()`](https://lennon-li.github.io/PAGe/reference/m1_v2_peak_posterior.md)
  : Infer a future peak-time posterior with M1-v2
- [`m1_walkforward_multi()`](https://lennon-li.github.io/PAGe/reference/m1_walkforward_multi.md)
  : Run M1 walk-forward for multiple seasons (parallelized)
- [`m1_walkforward_predictions()`](https://lennon-li.github.io/PAGe/reference/m1_walkforward_predictions.md)
  : Run M1 walk-forward for one season and collect predictions at target
  weeks
- [`m2_fit()`](https://lennon-li.github.io/PAGe/reference/m2_fit.md) :
  Fit M2
- [`m2_offset_baseline()`](https://lennon-li.github.io/PAGe/reference/m2_offset_baseline.md)
  : Return the exact no-correction M1 baseline on the probability scale
- [`m2_predict()`](https://lennon-li.github.io/PAGe/reference/m2_predict.md)
  : Predict with M2
- [`m2_predict_one()`](https://lennon-li.github.io/PAGe/reference/m2_predict_one.md)
  : Predict M2 positivity from a fitted Stage-2 GAM (single row)
- [`m2_subset_config()`](https://lennon-li.github.io/PAGe/reference/m2_subset_config.md)
  : Build a governed M2 offset-subset configuration
- [`m2_subset_grid()`](https://lennon-li.github.io/PAGe/reference/m2_subset_grid.md)
  : Build the governed M2 offset-subset candidate grid
- [`m2_v2_c2_governed_contract()`](https://lennon-li.github.io/PAGe/reference/m2_v2_c2_governed_contract.md)
  : Governed M2-v2 C2 contract
- [`nested_loso_build_fold()`](https://lennon-li.github.io/PAGe/reference/nested_loso_build_fold.md)
  : Build a single LOSO fold: training alignment + reference curve
- [`nested_loso_cv()`](https://lennon-li.github.io/PAGe/reference/nested_loso_cv.md)
  : Nested M1 -\> M2 leave-one-season-out cross-validation
- [`nested_loso_grid_search()`](https://lennon-li.github.io/PAGe/reference/nested_loso_grid_search.md)
  : Nested LOSO grid search over M2 specs
- [`nested_loso_m1_test()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m1_test.md)
  : Run M1 walk-forward on the held-out test season
- [`nested_loso_m1_train()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m1_train.md)
  : Run M1 walk-forward predictions on training seasons
- [`nested_loso_m2_eval_frozen_bias()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m2_eval_frozen_bias.md)
  : Evaluate M2 using a frozen GAM with walk-forward bias correction
- [`nested_loso_m2_eval_weekly_refit()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m2_eval_weekly_refit.md)
  : Evaluate a Stage-2 spec using weekly GAM refit on the test season
- [`nested_loso_m2_train()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m2_train.md)
  : Train M2 model on one LOSO fold
- [`nested_loso_refit_best()`](https://lennon-li.github.io/PAGe/reference/nested_loso_refit_best.md)
  : Refit M2 on all historical data with a chosen spec
- [`nested_loso_run_fold()`](https://lennon-li.github.io/PAGe/reference/nested_loso_run_fold.md)
  : Run a complete nested LOSO fold
- [`nested_season_evaluation()`](https://lennon-li.github.io/PAGe/reference/nested_season_evaluation.md)
  : Run the complete nested seasonal evaluation
- [`peak_status_from_align()`](https://lennon-li.github.io/PAGe/reference/peak_status_from_align.md)
  : Determine whether the epidemic peak has passed
- [`peak_summary_from_fit()`](https://lennon-li.github.io/PAGe/reference/peak_summary_from_fit.md)
  : Summarise the peak of an aligned seasonal fit
- [`run_alignment_prospective()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective.md)
  : Prospective alignment and peak detection for one season
- [`run_alignment_prospective_multi()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective_multi.md)
  : Prospective multi-template alignment wrapper
- [`stage2_build_joint_formula()`](https://lennon-li.github.io/PAGe/reference/stage2_build_joint_formula.md)
  : Build the joint Stage-2 mgcv formula from a spec
- [`stage2_exclude_newseason()`](https://lennon-li.github.io/PAGe/reference/stage2_exclude_newseason.md)
  : Terms to exclude for new-season prediction
- [`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md)
  : Create a Stage-2 training specification (hyperparameters + derived
  objects)
- [`stage2_predict_series()`](https://lennon-li.github.io/PAGe/reference/stage2_predict_series.md)
  : Produce per-snapshot Stage-2 forecast series (h1/h2) on the
  target-week axis
- [`stage2_spec_from_tuning()`](https://lennon-li.github.io/PAGe/reference/stage2_spec_from_tuning.md)
  : Extract best Stage-2 spec from a tuning result

## Internal and legacy topics

Compatibility helpers and implementation details.

- [`add_prospective_derivs_link()`](https://lennon-li.github.io/PAGe/reference/add_prospective_derivs_link.md)
  : Prospective (real-time safe) derivatives of positivity on the logit
  scale
- [`aggregate_strata()`](https://lennon-li.github.io/PAGe/reference/aggregate_strata.md)
  : Aggregate stratified forecasts
- [`aggregate_strata_draws()`](https://lennon-li.github.io/PAGe/reference/aggregate_strata_draws.md)
  : Aggregate joint forecast draws across strata
- [`alignIgnition()`](https://lennon-li.github.io/PAGe/reference/alignIgnition.md)
  : Align within-season week index by shifting ignition to a common
  anchor week
- [`align_forecast_pipeline_dilate()`](https://lennon-li.github.io/PAGe/reference/align_forecast_pipeline_dilate.md)
  : Align and forecast using dilated reference curve
- [`align_multi_template()`](https://lennon-li.github.io/PAGe/reference/align_multi_template.md)
  : Multi-template ensemble alignment and forecast
- [`apply_ignition_labels()`](https://lennon-li.github.io/PAGe/reference/apply_ignition_labels.md)
  : Apply finalized ignition labels to canonical training data
- [`apply_timing_labels_v2()`](https://lennon-li.github.io/PAGe/reference/apply_timing_labels_v2.md)
  : Apply timing-v2 labels to canonical surveillance data
- [`as_manual_labels_v2()`](https://lennon-li.github.io/PAGe/reference/as_manual_labels_v2.md)
  : Convert timing-v2 labels to the M0/M1 training label contract
- [`as_timing_targets_v2()`](https://lennon-li.github.io/PAGe/reference/as_timing_targets_v2.md)
  : Extract fractional timing targets from timing-v2 labels
- [`assemble_kit()`](https://lennon-li.github.io/PAGe/reference/assemble_kit.md)
  : Bundle trained artifacts for prospective deployment
- [`assert_loso_test_season_absent()`](https://lennon-li.github.io/PAGe/reference/assert_loso_test_season_absent.md)
  : Assert a LOSO test season is absent from supplied ignition labels
- [`baseline_calendar_gam()`](https://lennon-li.github.io/PAGe/reference/baseline_calendar_gam.md)
  : Calendar-week binomial GAM comparator
- [`baseline_persistence()`](https://lennon-li.github.io/PAGe/reference/baseline_persistence.md)
  : Persistence baseline forecasts
- [`baseline_seasonal_mean()`](https://lennon-li.github.io/PAGe/reference/baseline_seasonal_mean.md)
  : Seasonal-mean baseline forecasts
- [`boundary_action_plan()`](https://lennon-li.github.io/PAGe/reference/boundary_action_plan.md)
  : Build the next action for a tuning result
- [`build_m0()`](https://lennon-li.github.io/PAGe/reference/build_m0.md)
  : Build aligned training data using M0 ignition detection
- [`build_m1()`](https://lennon-li.github.io/PAGe/reference/build_m1.md)
  : Build M1 reference curve and alignment hyperparameters
- [`build_m1_v2_timing()`](https://lennon-li.github.io/PAGe/reference/build_m1_v2_timing.md)
  : Build the governed M1-v2 timing artifact
- [`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md)
  : Build M2 forecast model via nested LOSO grid search
- [`build_retrospective_peak_truth_v1()`](https://lennon-li.github.io/PAGe/reference/build_retrospective_peak_truth_v1.md)
  : Build frozen retrospective peak truth v1 for one or more seasons
- [`build_stage2_pseudo_prospective_list()`](https://lennon-li.github.io/PAGe/reference/build_stage2_pseudo_prospective_list.md)
  : Build pseudo-prospective Stage-2 snapshot list (current season)
- [`checkSeasonLength()`](https://lennon-li.github.io/PAGe/reference/checkSeasonLength.md)
  : Compute in-season length for each season
- [`check_promotion()`](https://lennon-li.github.io/PAGe/reference/check_promotion.md)
  : Check whether a candidate forecast model qualifies for promotion
- [`check_scale_identifiability()`](https://lennon-li.github.io/PAGe/reference/check_scale_identifiability.md)
  : Check if scaling (b) is identifiable yet, with a more sensitive rule
- [`compact_m0_artifact_for_m1()`](https://lennon-li.github.io/PAGe/reference/compact_m0_artifact_for_m1.md)
  : Compact a complete M0 artifact for the M1 handoff
- [`compact_m1_cache_for_m2()`](https://lennon-li.github.io/PAGe/reference/compact_m1_cache_for_m2.md)
  : Compact a complete M1 LOSO cache for M2
- [`compare_m1_m2()`](https://lennon-li.github.io/PAGe/reference/compare_m1_m2.md)
  : Compare M1 and M2 forecasts
- [`compile_expert_ignition_annotations()`](https://lennon-li.github.io/PAGe/reference/compile_expert_ignition_annotations.md)
  : Compile expert ignition annotations to flat storage rows
- [`decide_m2_vs_m1()`](https://lennon-li.github.io/PAGe/reference/decide_m2_vs_m1.md)
  : Decide whether an M2 candidate earns adoption over M1
- [`default_m1_grid()`](https://lennon-li.github.io/PAGe/reference/default_m1_grid.md)
  : Return the default M1 alignment tuning grid
- [`default_m1_hard_caps()`](https://lennon-li.github.io/PAGe/reference/default_m1_hard_caps.md)
  : Return the governed M1 hard-cap defaults
- [`default_m2_grid()`](https://lennon-li.github.io/PAGe/reference/default_m2_grid.md)
  : Return the default M2 forecast tuning grid
- [`default_m2_nll_gain_caps()`](https://lennon-li.github.io/PAGe/reference/default_m2_nll_gain_caps.md)
  : Default parameter-specific M2 NLL gain caps
- [`detectIgnitionBySeason_M0v2()`](https://lennon-li.github.io/PAGe/reference/detectIgnitionBySeason_M0v2.md)
  : Prospective ignition detection (M0v2) across seasons
- [`detectIgnitionBySeason_M0v2_timing()`](https://lennon-li.github.io/PAGe/reference/detectIgnitionBySeason_M0v2_timing.md)
  : Detect ignition with an opt-in fractional week estimate
- [`detectIgnition_oneSeason()`](https://lennon-li.github.io/PAGe/reference/detectIgnition_oneSeason.md)
  : Single-season wrapper around detectIgnitionBySeason_M0v2
- [`detectIgnition_oneSeason_timing_v2()`](https://lennon-li.github.io/PAGe/reference/detectIgnition_oneSeason_timing_v2.md)
  : Single-season fractional M0 detector helper
- [`.expert_timing_schema_version`](https://lennon-li.github.io/PAGe/reference/dot-expert_timing_schema_version.md)
  : Expert decimal ignition annotation contract
- [`estimateDerivs()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs.md)
  : Estimate smoothed positivity and derivatives (d1/d2) by season using
  binomial GAMs
- [`estimateDerivs_walkforward()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs_walkforward.md)
  : Compute derivatives for a single season in a causal (walk-forward)
  manner
- [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md)
  : Estimate a reference (template) curve for influenza positivity
- [`estimate_season_re_online()`](https://lennon-li.github.io/PAGe/reference/estimate_season_re_online.md)
  : Estimate season random effect causally from accumulated observations
- [`evaluate_forecasts()`](https://lennon-li.github.io/PAGe/reference/evaluate_forecasts.md)
  : Evaluate forecasts with nested season validation
- [`expand_grid_specs()`](https://lennon-li.github.io/PAGe/reference/expand_grid_specs.md)
  : Expand a hyperparameter grid into Stage-2 spec objects (ALL
  hyperparams can vary)
- [`expand_tuning_grid()`](https://lennon-li.github.io/PAGe/reference/expand_tuning_grid.md)
  : Expand a tuning grid at every unresolved winner boundary
- [`expert_ignition_annotation_sheet()`](https://lennon-li.github.io/PAGe/reference/expert_ignition_annotation_sheet.md)
  : Create a blank ignition annotation sheet
- [`extract_nll_sensitivity()`](https://lennon-li.github.io/PAGe/reference/extract_nll_sensitivity.md)
  : Extract metric sensitivity across tuning-grid parameters
- [`finalize_expert_ignition_review()`](https://lennon-li.github.io/PAGe/reference/finalize_expert_ignition_review.md)
  : Finalize numeric expert ignition after review
- [`finalize_ignition_label()`](https://lennon-li.github.io/PAGe/reference/finalize_ignition_label.md)
  : Finalize a reviewed ignition label
- [`finalize_peak_label()`](https://lennon-li.github.io/PAGe/reference/finalize_peak_label.md)
  : Finalize a reviewed peak label
- [`finalize_season_labels()`](https://lennon-li.github.io/PAGe/reference/finalize_season_labels.md)
  : Finalize ignition and peak labels together
- [`finalize_season_timing_v2()`](https://lennon-li.github.io/PAGe/reference/finalize_season_timing_v2.md)
  : Record user supplied ignition and peak timing labels
- [`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md)
  : Fit ignition classifier scores (Stage-1)
- [`fitIgnition_timing_v2()`](https://lennon-li.github.io/PAGe/reference/fitIgnition_timing_v2.md)
  : Fit the M0 classifier using fractional timing targets
- [`fit_final_pipeline()`](https://lennon-li.github.io/PAGe/reference/fit_final_pipeline.md)
  : Fit the final deployment pipeline after nested evaluation
- [`fit_m0()`](https://lennon-li.github.io/PAGe/reference/fit_m0.md) :
  Fit an M0 ignition configuration (draft artifact)
- [`fit_m1()`](https://lennon-li.github.io/PAGe/reference/fit_m1.md) :
  Fit an M1 alignment configuration (draft artifact)
- [`fit_m1_v2_bias_calibrator()`](https://lennon-li.github.io/PAGe/reference/fit_m1_v2_bias_calibrator.md)
  : Fit the M1-v2 early-bias calibrator
- [`fit_m1_v2_library()`](https://lennon-li.github.io/PAGe/reference/fit_m1_v2_library.md)
  : Fit the M1-v2 peak-relative historical library
- [`fit_m1_v2_passage_policy()`](https://lennon-li.github.io/PAGe/reference/fit_m1_v2_passage_policy.md)
  : Fit the M1-v2 passage-confirmation policy
- [`fit_m2()`](https://lennon-li.github.io/PAGe/reference/fit_m2.md) :
  Fit an M2 forecast configuration (draft artifact)
- [`fit_m2_a_ntrend_shadow()`](https://lennon-li.github.io/PAGe/reference/fit_m2_a_ntrend_shadow.md)
  : Tune a causal test-volume trend for the M2-A state forecast
- [`fit_m2_offset_correction()`](https://lennon-li.github.io/PAGe/reference/fit_m2_offset_correction.md)
  : Fit a regularized binomial M2 offset correction.
- [`fit_peak_calibration()`](https://lennon-li.github.io/PAGe/reference/fit_peak_calibration.md)
  : Fit peak calibration model from LOSO walk-forward results
- [`flagIgnition()`](https://lennon-li.github.io/PAGe/reference/flagIgnition.md)
  : Flag influenza ignition week (4-rule minimal version)
- [`forecast_post_peak_gam()`](https://lennon-li.github.io/PAGe/reference/forecast_post_peak_gam.md)
  : Post-peak GAM forecast without further alignment
- [`format_current_for_stage2()`](https://lennon-li.github.io/PAGe/reference/format_current_for_stage2.md)
  : Format current-season observations for Stage-2 refit
- [`fractional_alignment_coordinates_v2()`](https://lennon-li.github.io/PAGe/reference/fractional_alignment_coordinates_v2.md)
  : Apply fractional timing to an M1 alignment result
- [`freeze_m0()`](https://lennon-li.github.io/PAGe/reference/freeze_m0.md)
  : Freeze an M0 draft artifact
- [`freeze_m1()`](https://lennon-li.github.io/PAGe/reference/freeze_m1.md)
  : Freeze an M1 draft artifact
- [`freeze_m2()`](https://lennon-li.github.io/PAGe/reference/freeze_m2.md)
  : Freeze an M2 draft artifact
- [`g_ref_safe()`](https://lennon-li.github.io/PAGe/reference/g_ref_safe.md)
  : Global shim: reference curve clamped to support
- [`getCurrentD()`](https://lennon-li.github.io/PAGe/reference/getCurrentD.md)
  : Fetch and tidy current-season PHO respiratory surveillance data
- [`get_full_cycle_weeks()`](https://lennon-li.github.io/PAGe/reference/get_full_cycle_weeks.md)
  : Number of epidemiological weeks in a full season cycle
- [`get_gam_cls()`](https://lennon-li.github.io/PAGe/reference/get_gam_cls.md)
  : Extract a classifier GAM from various container objects
- [`get_newWeek_from_week()`](https://lennon-li.github.io/PAGe/reference/get_newWeek_from_week.md)
  : Map surveillance week to newWeek index in a season
- [`hash_file_sha256()`](https://lennon-li.github.io/PAGe/reference/hash_file_sha256.md)
  : Compute a SHA-256 file fingerprint
- [`inject_m1_into_snapshots()`](https://lennon-li.github.io/PAGe/reference/inject_m1_into_snapshots.md)
  : Replace logit_f_eff in M2 snapshots with M1's aligned prediction
- [`inspect_tuning_boundaries()`](https://lennon-li.github.io/PAGe/reference/inspect_tuning_boundaries.md)
  : Inspect tuning boundaries and optionally warn about unresolved edges
- [`learn_alignment_hyperparams()`](https://lennon-li.github.io/PAGe/reference/learn_alignment_hyperparams.md)
  : Learn tau/delta bounds and penalty from historical seasons
- [`legacy_model_settings()`](https://lennon-li.github.io/PAGe/reference/legacy_model_settings.md)
  : Return the explicitly selected Legacy Model settings
- [`load_flu_hist()`](https://lennon-li.github.io/PAGe/reference/load_flu_hist.md)
  : Load historical influenza surveillance data
- [`load_promoted_kit()`](https://lennon-li.github.io/PAGe/reference/load_promoted_kit.md)
  : Load a promoted PAGe deployment kit
- [`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md)
  : Load pre-built model artifacts for prospective deployment
- [`loso_walkforward()`](https://lennon-li.github.io/PAGe/reference/loso_walkforward.md)
  : Walk-forward alignment evaluation with LOSO reference curves
- [`m0_detect()`](https://lennon-li.github.io/PAGe/reference/m0_detect.md)
  : Detect epidemic ignition with M0
- [`m0_fit()`](https://lennon-li.github.io/PAGe/reference/m0_fit.md) :
  Fit M0
- [`m1_fit()`](https://lennon-li.github.io/PAGe/reference/m1_fit.md) :
  Fit M1
- [`m1_make_params()`](https://lennon-li.github.io/PAGe/reference/m1_make_params.md)
  : Construct an M1 alignment parameter list
- [`m1_passage_posterior()`](https://lennon-li.github.io/PAGe/reference/m1_passage_posterior.md)
  : Compute the M1 peak-passage posterior
- [`m1_peak_posterior()`](https://lennon-li.github.io/PAGe/reference/m1_peak_posterior.md)
  : Compute the M1 peak-time posterior
- [`m1_predict()`](https://lennon-li.github.io/PAGe/reference/m1_predict.md)
  : Predict timing with M1
- [`m1_v2_activation_table_from_m0_loso()`](https://lennon-li.github.io/PAGe/reference/m1_v2_activation_table_from_m0_loso.md)
  : Construct governed M1-v2 activations from an M0 LOSO result
- [`m1_v2_apply_bias_calibration()`](https://lennon-li.github.io/PAGe/reference/m1_v2_apply_bias_calibration.md)
  : Apply M1-v2 early-bias calibration to forecast summaries
- [`m1_v2_passage_decision()`](https://lennon-li.github.io/PAGe/reference/m1_v2_passage_decision.md)
  : Decide whether M1-v2 peak passage is confirmed
- [`m1_v2_passage_posterior()`](https://lennon-li.github.io/PAGe/reference/m1_v2_passage_posterior.md)
  : Infer M1-v2 peak-passage probability
- [`m1_v2_peak_posterior()`](https://lennon-li.github.io/PAGe/reference/m1_v2_peak_posterior.md)
  : Infer a future peak-time posterior with M1-v2
- [`m1_walkforward_multi()`](https://lennon-li.github.io/PAGe/reference/m1_walkforward_multi.md)
  : Run M1 walk-forward for multiple seasons (parallelized)
- [`m1_walkforward_predictions()`](https://lennon-li.github.io/PAGe/reference/m1_walkforward_predictions.md)
  : Run M1 walk-forward for one season and collect predictions at target
  weeks
- [`m2_fit()`](https://lennon-li.github.io/PAGe/reference/m2_fit.md) :
  Fit M2
- [`m2_offset_baseline()`](https://lennon-li.github.io/PAGe/reference/m2_offset_baseline.md)
  : Return the exact no-correction M1 baseline on the probability scale
- [`m2_predict()`](https://lennon-li.github.io/PAGe/reference/m2_predict.md)
  : Predict with M2
- [`m2_predict_one()`](https://lennon-li.github.io/PAGe/reference/m2_predict_one.md)
  : Predict M2 positivity from a fitted Stage-2 GAM (single row)
- [`m2_subset_config()`](https://lennon-li.github.io/PAGe/reference/m2_subset_config.md)
  : Build a governed M2 offset-subset configuration
- [`m2_subset_grid()`](https://lennon-li.github.io/PAGe/reference/m2_subset_grid.md)
  : Build the governed M2 offset-subset candidate grid
- [`m2_v2_c2_governed_contract()`](https://lennon-li.github.io/PAGe/reference/m2_v2_c2_governed_contract.md)
  : Governed M2-v2 C2 contract
- [`makeTable()`](https://lennon-li.github.io/PAGe/reference/makeTable.md)
  : Summarise alignment fit as a one-row tibble
- [`make_g_ref_fun()`](https://lennon-li.github.io/PAGe/reference/make_g_ref_fun.md)
  : Build reference link-scale function from a fitted GAM
- [`make_g_ref_mu_se()`](https://lennon-li.github.io/PAGe/reference/make_g_ref_mu_se.md)
  : Build reference mean/SE function from GAM (link scale)
- [`make_soft_cap_fn()`](https://lennon-li.github.io/PAGe/reference/make_soft_cap_fn.md)
  : Build a soft positivity cap function from a fitted Stage-2 GAM
- [`mark_season_weeks()`](https://lennon-li.github.io/PAGe/reference/mark_season_weeks.md)
  : Mark in-season weeks based on a positivity threshold
- [`migrate_r_packages()`](https://lennon-li.github.io/PAGe/reference/migrate_r_packages.md)
  : Migrates user-installed R packages from an old R version to the
  current (new) R version.
- [`negloglik_tau_delta()`](https://lennon-li.github.io/PAGe/reference/negloglik_tau_delta.md)
  : Negative log-likelihood for tau/delta alignment
- [`nested_loso_build_fold()`](https://lennon-li.github.io/PAGe/reference/nested_loso_build_fold.md)
  : Build a single LOSO fold: training alignment + reference curve
- [`nested_loso_cv()`](https://lennon-li.github.io/PAGe/reference/nested_loso_cv.md)
  : Nested M1 -\> M2 leave-one-season-out cross-validation
- [`nested_loso_grid_search()`](https://lennon-li.github.io/PAGe/reference/nested_loso_grid_search.md)
  : Nested LOSO grid search over M2 specs
- [`nested_loso_m1_test()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m1_test.md)
  : Run M1 walk-forward on the held-out test season
- [`nested_loso_m1_train()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m1_train.md)
  : Run M1 walk-forward predictions on training seasons
- [`nested_loso_m2_eval_frozen_bias()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m2_eval_frozen_bias.md)
  : Evaluate M2 using a frozen GAM with walk-forward bias correction
- [`nested_loso_m2_eval_weekly_refit()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m2_eval_weekly_refit.md)
  : Evaluate a Stage-2 spec using weekly GAM refit on the test season
- [`nested_loso_m2_train()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m2_train.md)
  : Train M2 model on one LOSO fold
- [`nested_loso_refit_best()`](https://lennon-li.github.io/PAGe/reference/nested_loso_refit_best.md)
  : Refit M2 on all historical data with a chosen spec
- [`nested_loso_run_fold()`](https://lennon-li.github.io/PAGe/reference/nested_loso_run_fold.md)
  : Run a complete nested LOSO fold
- [`nested_season_evaluation()`](https://lennon-li.github.io/PAGe/reference/nested_season_evaluation.md)
  : Run the complete nested seasonal evaluation
- [`new_expert_ignition_annotation()`](https://lennon-li.github.io/PAGe/reference/new_expert_ignition_annotation.md)
  : Create one expert decimal ignition annotation
- [`new_m2_v2_b_gate_review()`](https://lennon-li.github.io/PAGe/reference/new_m2_v2_b_gate_review.md)
  : Bind a reviewed B timing gate decision document
- [`new_m2_v2_b_soft_timing_handoff()`](https://lennon-li.github.io/PAGe/reference/new_m2_v2_b_soft_timing_handoff.md)
  : Build a provisional type-B soft-timing handoff for M2-v2
- [`new_result_manifest()`](https://lennon-li.github.io/PAGe/reference/new_result_manifest.md)
  : Construct a disclosure-safe result manifest
- [`num_deriv()`](https://lennon-li.github.io/PAGe/reference/num_deriv.md)
  : Numerical central-difference derivative
- [`page_aggregate_strata()`](https://lennon-li.github.io/PAGe/reference/page_aggregate_strata.md)
  : Aggregate stratified forecasts with explicit dependence
- [`page_aggregate_strata_draws()`](https://lennon-li.github.io/PAGe/reference/page_aggregate_strata_draws.md)
  : Aggregate joint posterior or simulation draws across strata
- [`page_forecast()`](https://lennon-li.github.io/PAGe/reference/page_forecast.md)
  : Forecast with the current PAGe production release
- [`page_forecast_now()`](https://lennon-li.github.io/PAGe/reference/page_forecast_now.md)
  : Produce a real-time forecast from a frozen kit and any supported
  source
- [`page_label_ignitions()`](https://lennon-li.github.io/PAGe/reference/page_label_ignitions.md)
  : Interactively review and label seasonal ignition weeks
- [`page_load_kit()`](https://lennon-li.github.io/PAGe/reference/page_load_kit.md)
  : Load and validate a frozen PAGe deployment kit
- [`page_load_surveillance()`](https://lennon-li.github.io/PAGe/reference/page_load_surveillance.md)
  : Load current-season surveillance data from any supported source
- [`page_manual_ignition_labels()`](https://lennon-li.github.io/PAGe/reference/page_manual_ignition_labels.md)
  : Pre-verified historical manual ignition labels
- [`page_models()`](https://lennon-li.github.io/PAGe/reference/page_models.md)
  : Inspect the current PAGe production model bundle
- [`page_phase_weights()`](https://lennon-li.github.io/PAGe/reference/page_phase_weights.md)
  : Derive per-row phase weights from observed ignition and peak weeks
- [`page_save_kit()`](https://lennon-li.github.io/PAGe/reference/page_save_kit.md)
  : Save a validated frozen PAGe deployment kit
- [`page_scoring_weights()`](https://lennon-li.github.io/PAGe/reference/page_scoring_weights.md)
  : Construct a phase-based scoring-weight contract
- [`page_season_calendar()`](https://lennon-li.github.io/PAGe/reference/page_season_calendar.md)
  : Derive the PAGe July-start season calendar from surveillance dates
- [`page_shared_denominator_correlation()`](https://lennon-li.github.io/PAGe/reference/page_shared_denominator_correlation.md)
  : Multinomial correlation for mutually exclusive shared-denominator
  strata
- [`page_train()`](https://lennon-li.github.io/PAGe/reference/page_train.md)
  : Train the PAGe forecasting system
- [`page_train_workflow()`](https://lennon-li.github.io/PAGe/reference/page_train_workflow.md)
  : Label ignition, train PAGe, and return a deployable frozen kit
- [`page_v3_forecast()`](https://lennon-li.github.io/PAGe/reference/page_v3_forecast.md)
  : Generate a shadow-only PAGe v3 two-pathogen forecast
- [`page_v3_models()`](https://lennon-li.github.io/PAGe/reference/page_v3_models.md)
  : Load and validate the frozen PAGe v3 weekF12 model bundle
- [`page_v3_walkforward_report()`](https://lennon-li.github.io/PAGe/reference/page_v3_walkforward_report.md)
  : Render the PAGe v3 walk-forward HTML report
- [`page_validate_kit()`](https://lennon-li.github.io/PAGe/reference/page_validate_kit.md)
  : Validate a PAGe kit
- [`page_version_metrics()`](https://lennon-li.github.io/PAGe/reference/page_version_metrics.md)
  : Verified PAGe version-comparison metrics
- [`page_walkforward_qmd()`](https://lennon-li.github.io/PAGe/reference/page_walkforward_qmd.md)
  [`page_render_report()`](https://lennon-li.github.io/PAGe/reference/page_walkforward_qmd.md)
  : Render a PAGe Quarto walk-forward report
- [`page_walkforward_report()`](https://lennon-li.github.io/PAGe/reference/page_walkforward_report.md)
  : Render the PAGe walk-forward report
- [`peak_status_from_align()`](https://lennon-li.github.io/PAGe/reference/peak_status_from_align.md)
  : Determine whether the epidemic peak has passed
- [`peak_summary_from_fit()`](https://lennon-li.github.io/PAGe/reference/peak_summary_from_fit.md)
  : Summarise the peak of an aligned seasonal fit
- [`plan_m2_grid()`](https://lennon-li.github.io/PAGe/reference/plan_m2_grid.md)
  : Plan a bounded M2 tuning grid
- [`plan_training()`](https://lennon-li.github.io/PAGe/reference/plan_training.md)
  : Plan a governed PAGe training run without fitting or launching
  workers
- [`plotRes()`](https://lennon-li.github.io/PAGe/reference/plotRes.md) :
  Plot alignment results against history and reference curve
- [`plotSeasonCurves()`](https://lennon-li.github.io/PAGe/reference/plotSeasonCurves.md)
  : Plot observed vs fitted positivity by season, with ignition week in
  title
- [`plot_cls_models_by_season()`](https://lennon-li.github.io/PAGe/reference/plot_cls_models_by_season.md)
  : Plot classifier scores by season and model
- [`plot_det_facet()`](https://lennon-li.github.io/PAGe/reference/plot_det_facet.md)
  : Plot ignition detection results (faceted)
- [`plot_forecast()`](https://lennon-li.github.io/PAGe/reference/plot_forecast.md)
  : Plot a PAGe 2-week-ahead forecast
- [`plot_ignition_detect_vs_truth()`](https://lennon-li.github.io/PAGe/reference/plot_ignition_detect_vs_truth.md)
  : Plot truth vs detected ignition week by season (faceted)
- [`plot_ignition_weekly_snapshots()`](https://lennon-li.github.io/PAGe/reference/plot_ignition_weekly_snapshots.md)
  : Extract Stage-2 hyperparameters from tuning output
- [`plot_nested_loso_predictions()`](https://lennon-li.github.io/PAGe/reference/plot_nested_loso_predictions.md)
  : Plot nested LOSO predictions by season
- [`plot_nll_sensitivity()`](https://lennon-li.github.io/PAGe/reference/plot_nll_sensitivity.md)
  : Plot metric sensitivity across tuning-grid parameters
- [`plot_season_detection_table()`](https://lennon-li.github.io/PAGe/reference/plot_season_detection_table.md)
  : Per-season ignition detection signal table
- [`plot_stage2()`](https://lennon-li.github.io/PAGe/reference/plot_stage2.md)
  : Plot observed vs Stage-2 forecasts across pseudo-prospective
  snapshots
- [`plot_stage2_joint_fit_by_season()`](https://lennon-li.github.io/PAGe/reference/plot_stage2_joint_fit_by_season.md)
  : Prepare Stage-2 M1 features from aligned prospective data
- [`predict_m2_a_ntrend_shadow()`](https://lennon-li.github.io/PAGe/reference/predict_m2_a_ntrend_shadow.md)
  : Predict from an M2-A test-volume-trend shadow artifact
- [`predict_m2_offset_correction()`](https://lennon-li.github.io/PAGe/reference/predict_m2_offset_correction.md)
  : Predict an M2 offset correction and return its residual link
  contribution.
- [`preflight_support_audit()`](https://lennon-li.github.io/PAGe/reference/preflight_support_audit.md)
  : Preflight support audit for M0/M1/M2
- [`prep_stage2_joint()`](https://lennon-li.github.io/PAGe/reference/prep_stage2_joint.md)
  : Prepare Stage-2 joint stacked data using a spec or tuned row
- [`prepare_page_data()`](https://lennon-li.github.io/PAGe/reference/prepare_page_data.md)
  : Prepare arbitrary surveillance data for the PAGe pipeline
- [`prepare_surveillance_data()`](https://lennon-li.github.io/PAGe/reference/prepare_surveillance_data.md)
  : Prepare surveillance data for PAGe
- [`prepare_timing_training_data_v2()`](https://lennon-li.github.io/PAGe/reference/prepare_timing_training_data_v2.md)
  : Build numeric timing targets for opt-in M0 training
- [`race_m2_candidates()`](https://lennon-li.github.io/PAGe/reference/race_m2_candidates.md)
  : Conservatively race M2 candidates before full nested LOSO
- [`read_result_manifest()`](https://lennon-li.github.io/PAGe/reference/read_result_manifest.md)
  : Read a PAGe result manifest
- [`refit_stage2_weekly()`](https://lennon-li.github.io/PAGe/reference/refit_stage2_weekly.md)
  : Refit Stage-2 GAM with current-season data for weekly prospective
  forecasting
- [`replay_holdout()`](https://lennon-li.github.io/PAGe/reference/replay_holdout.md)
  : Replay a frozen holdout season
- [`replay_season_holdout()`](https://lennon-li.github.io/PAGe/reference/replay_season_holdout.md)
  : Replay a season that was unseen by a pre-trained kit
- [`resolve_week_override()`](https://lennon-li.github.io/PAGe/reference/resolve_week_override.md)
  : Resolve a week estimate with an optional manual override
- [`retrospective_gam_peak_sensitivity()`](https://lennon-li.github.io/PAGe/reference/retrospective_gam_peak_sensitivity.md)
  : Audit peak-location sensitivity across simple GAM basis dimensions
- [`retrospective_gam_peak_truth()`](https://lennon-li.github.io/PAGe/reference/retrospective_gam_peak_truth.md)
  : Derive retrospective continuous peak truth from a completed season
  using GAM
- [`review_expert_ignition()`](https://lennon-li.github.io/PAGe/reference/review_expert_ignition.md)
  : Review one season for expert decimal ignition annotation
- [`review_expert_ignition_set()`](https://lennon-li.github.io/PAGe/reference/review_expert_ignition_set.md)
  : Build expert ignition review objects for all seasons
- [`review_ignition_label()`](https://lennon-li.github.io/PAGe/reference/review_ignition_label.md)
  : Review a season before assigning its retrospective ignition label
- [`review_season_timing_v2()`](https://lennon-li.github.io/PAGe/reference/review_season_timing_v2.md)
  : Review one season for timing-v2 labels
- [`run_alignment_prospective()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective.md)
  : Prospective alignment and peak detection for one season
- [`run_alignment_prospective_multi()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective_multi.md)
  : Prospective multi-template alignment wrapper
- [`run_ignition_weekly()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md)
  : Run M0 ignition detection week-by-week (walk-forward)
- [`run_ignition_weekly_timing_v2()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly_timing_v2.md)
  : Run prospective M0 with fractional ignition timing
- [`run_m0_detection()`](https://lennon-li.github.io/PAGe/reference/run_m0_detection.md)
  [`run_m0()`](https://lennon-li.github.io/PAGe/reference/run_m0_detection.md)
  : Run M0 ignition detection for the current season
- [`run_m1_alignment()`](https://lennon-li.github.io/PAGe/reference/run_m1_alignment.md)
  [`run_m1()`](https://lennon-li.github.io/PAGe/reference/run_m1_alignment.md)
  : Walk-forward M1 alignment for the current season
- [`run_m1_v2_timing()`](https://lennon-li.github.io/PAGe/reference/run_m1_v2_timing.md)
  : Run the redesigned M1-v2 timing stage
- [`run_m2_forecast()`](https://lennon-li.github.io/PAGe/reference/run_m2_forecast.md)
  [`run_m2()`](https://lennon-li.github.io/PAGe/reference/run_m2_forecast.md)
  : Run M2 forecast using M1 alignment outputs
- [`run_m2_v2_c2_governed_runtime()`](https://lennon-li.github.io/PAGe/reference/run_m2_v2_c2_governed_runtime.md)
  : Run the governed M2-v2 C2 forecast path
- [`run_outer_fold()`](https://lennon-li.github.io/PAGe/reference/run_outer_fold.md)
  : Train and replay one outer-held-out season
- [`run_prospective_pipeline()`](https://lennon-li.github.io/PAGe/reference/run_prospective_pipeline.md)
  [`run_pipeline()`](https://lennon-li.github.io/PAGe/reference/run_prospective_pipeline.md)
  : Run the full M0 -\> M1 -\> M2 walk-forward pipeline for one season
- [`score_ignition_timing_v2()`](https://lennon-li.github.io/PAGe/reference/score_ignition_timing_v2.md)
  : Score fractional M0 detections against midpoint ignition labels
- [`score_params()`](https://lennon-li.github.io/PAGe/reference/score_params.md)
  : Score an ignition-threshold grid on historical seasons
- [`score_peak_timing_v2()`](https://lennon-li.github.io/PAGe/reference/score_peak_timing_v2.md)
  : Score peak timing against the observed peak week
- [`season_selection()`](https://lennon-li.github.io/PAGe/reference/season_selection.md)
  : Extract the season selection from a stage artifact
- [`select_m1_candidate()`](https://lennon-li.github.io/PAGe/reference/select_m1_candidate.md)
  : Select an M1 candidate with a practical-gain backoff rule
- [`select_m2_candidate()`](https://lennon-li.github.io/PAGe/reference/select_m2_candidate.md)
  : Select an M2 candidate from full nested-LOSO results
- [`shared_denominator_correlation()`](https://lennon-li.github.io/PAGe/reference/shared_denominator_correlation.md)
  : Shared-denominator multinomial correlation
- [`simulate_flu_seasons()`](https://lennon-li.github.io/PAGe/reference/simulate_flu_seasons.md)
  : Simulate synthetic flu seasons for package examples
- [`stage2_build_joint_formula()`](https://lennon-li.github.io/PAGe/reference/stage2_build_joint_formula.md)
  : Build the joint Stage-2 mgcv formula from a spec
- [`stage2_exclude_newseason()`](https://lennon-li.github.io/PAGe/reference/stage2_exclude_newseason.md)
  : Terms to exclude for new-season prediction
- [`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md)
  : Create a Stage-2 training specification (hyperparameters + derived
  objects)
- [`stage2_predict_series()`](https://lennon-li.github.io/PAGe/reference/stage2_predict_series.md)
  : Produce per-snapshot Stage-2 forecast series (h1/h2) on the
  target-week axis
- [`stage2_spec_from_tuning()`](https://lennon-li.github.io/PAGe/reference/stage2_spec_from_tuning.md)
  : Extract best Stage-2 spec from a tuning result
- [`summarize_forecast_metrics()`](https://lennon-li.github.io/PAGe/reference/summarize_forecast_metrics.md)
  : Summarize prospective forecast metrics
- [`summarize_replay_diagnostics()`](https://lennon-li.github.io/PAGe/reference/summarize_replay_diagnostics.md)
  : Summarize aggregate replay diagnostics
- [`train_m2()`](https://lennon-li.github.io/PAGe/reference/train_m2.md)
  : Fit the M2 production GAM on all training seasons
- [`train_outer_fold()`](https://lennon-li.github.io/PAGe/reference/train_outer_fold.md)
  : Train a nested-tuned PAGe kit
- [`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
  : Train all PAGe pipeline components
- [`train_stage2_joint()`](https://lennon-li.github.io/PAGe/reference/train_stage2_joint.md)
  : Train Stage-2 joint model
- [`tuneIgnitionGrid()`](https://lennon-li.github.io/PAGe/reference/tuneIgnitionGrid.md)
  : Grid search ignition detection parameters (OS-aware parallel)
- [`tuneIgnitionGrid_M0v2()`](https://lennon-li.github.io/PAGe/reference/tuneIgnitionGrid_M0v2.md)
  : Grid-search tuning for M0v2 ignition detector
- [`tune_m0()`](https://lennon-li.github.io/PAGe/reference/tune_m0.md) :
  Tune M0 ignition detection hyperparameters via LOSO grid search
- [`tune_m1()`](https://lennon-li.github.io/PAGe/reference/tune_m1.md) :
  Tune M1 alignment hyperparameters via LOSO grid search
- [`tune_m1_alignment()`](https://lennon-li.github.io/PAGe/reference/tune_m1_alignment.md)
  : LOSO grid search over M1 alignment hyperparameters
- [`tune_m2()`](https://lennon-li.github.io/PAGe/reference/tune_m2.md) :
  Tune M2 with an explicit governed season selection
- [`tune_peak_detection()`](https://lennon-li.github.io/PAGe/reference/tune_peak_detection.md)
  : Tune peak detection parameters using pre-computed walk-forward
  results
- [`validate_expert_ignition_annotation()`](https://lennon-li.github.io/PAGe/reference/validate_expert_ignition_annotation.md)
  : Validate an expert ignition annotation
- [`validate_m0_tuning()`](https://lennon-li.github.io/PAGe/reference/validate_m0_tuning.md)
  : Validate an M0 tuning result
- [`validate_m1_tuning()`](https://lennon-li.github.io/PAGe/reference/validate_m1_tuning.md)
  : Validate an M1 tuning result
- [`validate_m1_v2_handoff()`](https://lennon-li.github.io/PAGe/reference/validate_m1_v2_handoff.md)
  : Validate the M1-v2 to M2 handoff contract
- [`validate_m2_tuning()`](https://lennon-li.github.io/PAGe/reference/validate_m2_tuning.md)
  : Validate an M2 tuning result
- [`validate_m2_v2_c2_governed_artifact()`](https://lennon-li.github.io/PAGe/reference/validate_m2_v2_c2_governed_artifact.md)
  : Validate a governed M2-v2 C2 artifact
- [`validate_page_kit()`](https://lennon-li.github.io/PAGe/reference/validate_page_kit.md)
  : Validate a PAGe deployment kit
- [`validate_result_manifest()`](https://lennon-li.github.io/PAGe/reference/validate_result_manifest.md)
  : Validate a disclosure-safe result manifest
- [`validate_season_selection()`](https://lennon-li.github.io/PAGe/reference/validate_season_selection.md)
  : Validate and normalize a season selection
- [`validate_surveillance_data()`](https://lennon-li.github.io/PAGe/reference/validate_surveillance_data.md)
  : Validate canonical PAGe surveillance data
- [`verify_promotion()`](https://lennon-li.github.io/PAGe/reference/verify_promotion.md)
  : Verify promotion evidence
- [`verify_promotion_evidence()`](https://lennon-li.github.io/PAGe/reference/verify_promotion_evidence.md)
  : Verify Artifact-Bound Holdout Promotion Evidence
- [`write_expert_ignition_annotations()`](https://lennon-li.github.io/PAGe/reference/write_expert_ignition_annotations.md)
  : Save versioned expert ignition annotations
- [`write_result_manifest()`](https://lennon-li.github.io/PAGe/reference/write_result_manifest.md)
  : Write a PAGe result manifest
