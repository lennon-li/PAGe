# Pipeline walkthrough

> **Caution**
>
> The API snippets below illustrate model development only. An in-memory
> [`check_promotion()`](https://lennon-li.github.io/PAGe/reference/check_promotion.md)
> result is not immutable release evidence. For a real release, use
> `docs/deployment-workflow.qmd` and preserve the acceptance, fixed-spec
> refresh, and deployment manifests before loading the promoted kit.

The examples are not executed during package builds because fitting and
nested validation are long-running.

## Prepare data and declare season sets

``` r

library(PAGe)

historical <- load_flu_hist("/authorized/path/flu_history.csv") |>
  prepare_surveillance_data()
selection <- validate_season_selection(
  historical,
  training_seasons = setdiff(
    sort(unique(historical$season)),
    c("2011-12", "2015-16", "2020-21", "2021-22", "2025-26")
  ),
  exclude_seasons = c("2011-12", "2015-16", "2020-21", "2021-22"),
  holdout_seasons = "2025-26",
  application_seasons = character()
)
```

PAGe does not bundle surveillance observations. The four season sets are
explicit and disjoint; 2025-26 remains outside every development fit.

## Guard M0, M1, and M2 independently

``` r

m0_tuning <- tune_m0(historical, selection = selection)
validate_m0_tuning(m0_tuning)
m0 <- fit_m0(historical, selection, m0_tuning$best_params) |>
  freeze_m0(m0_tuning)

m1_tuning <- tune_m1(historical, m0 = m0, selection = selection)
validate_m1_tuning(m1_tuning)
m1_best <- m1_tuning$best[1, , drop = FALSE]
m1_config <- m1_make_params(
  k_ref = m1_best$k_ref,
  temperature = m1_best$multi_temperature,
  rise_weight = m1_best$align_rise_weight,
  slope_window = m1_best$slope_window,
  slope_weight = m1_best$slope_weight
)
m1 <- fit_m1(historical, selection, m0, m1_config) |>
  freeze_m1(m1_tuning)

m2_grid <- if (exists("prior_m2_results", inherits = FALSE)) {
  plan_m2_grid(prior_m2_results, max_finalists = 6L, max_specs = 64L)
} else {
  default_m2_grid()
}
m2_tuning <- tune_m2(historical, selection, m0, m1, grid = m2_grid)
validate_m2_tuning(m2_tuning)
m2 <- fit_m2(historical, selection, m0, m1, m2_tuning$best_spec) |>
  freeze_m2(m2_tuning)

kit <- assemble_kit(m0, m1, m2)
validate_page_kit(kit)
```

Tuning, fitting, and freezing are distinct states. M1 requires a frozen,
selection-matched M0; M2 requires the exact frozen M0/M1 chain; governed
kit assembly rejects drafts and identity mismatches.

For a locked-spec compatibility refresh:

``` r

training <- train_pipeline(historical, mode = "refresh")
kit <- training$kit
```

[`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
now composes the guarded lifecycle above for both refresh and retune.
Use the explicit calls when a manual cycle must stop and be inspected at
each stage boundary.

## Replay and promote

Governed holdout evaluation uses `scripts/acceptance/replay_2025_26.R`,
not a bare in-memory
[`check_promotion()`](https://lennon-li.github.io/PAGe/reference/check_promotion.md)
report. The acceptance script writes a private decision bundle and
disclosure-safe manifest that bind the authorized data, candidate, and
incumbent by SHA-256.

After a passing decision, run `season2526/run_retrain_venkata.R` with
those saved artifacts and both kit paths. It verifies the hashes before
constructing the short-lived promotion evidence accepted by
[`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md).
R classes can be forged, so the retained and verified artifacts are the
production safety boundary.

## Retune and select

``` r

retuned <- train_pipeline(
  historical,
  mode = "retune",
  previous_results = prior_m2_results,
  selection_method = "min_nll", # or "one_se" / "pareto"
  racing = FALSE
)
```

The adaptive grid uses compatible prior results and expands around
promising boundaries. Optional racing requires a callback and cannot
replace final full nested-LOSO evaluation.

### Tuning tips

A winning parameter should usually be bracketed by tested values. When
it sits at a lower or upper grid edge, retain the current candidates and
add one valid level beyond that edge using adjacent observed spacing.
Rerun the same complete LOSO folds and selection rule. Start with
one-factor local neighbors; add targeted interactions only when fold
results suggest them.

Boundary values can be legitimate. Zero may mean an optional M2 smooth
is off, and probability, count, window, and basis-size parameters have
hard valid domains. Record each boundary as expanded, accepted as a
null/constraint, or unresolved at the computational cap.

For the default M1 grid, lower-edge selections at `k_ref=25` and
`slope_weight=8` suggest controlled next values of `20` and `4`,
respectively, if they remain selected after complete validation. For M2,
`plan_m2_grid(previous_results, max_finalists, max_specs)` retains the
incumbent and finalists, adds local neighbors, and expands valid winning
boundaries one adjacent step.

Stop when material axes are bracketed, a boundary has a documented
null/constraint interpretation, improvement is flat relative to fold
uncertainty, or the predeclared cap is reached. Finish all expansion
before opening the prospective holdout.

## Manual candidate cycle

For a manual pre-holdout run, stop after each gate and save the
resulting candidate only after all three stages are frozen. For the
current boundary cycle, reuse the already-frozen M0/M1 artifacts and
start at the M2 block; do not rerun a grid whose rows are already
scored.

``` r

m0_tuning <- tune_m0(historical, selection = selection, verbose = TRUE)
validate_m0_tuning(m0_tuning)
m0 <- fit_m0(historical, selection, m0_tuning$best_params) |>
  freeze_m0(m0_tuning)

m1_tuning <- tune_m1(historical, m0, selection = selection, verbose = TRUE)
validate_m1_tuning(m1_tuning)
m1_best <- m1_tuning$best[1, , drop = FALSE]
m1_config <- m1_make_params(
  k_ref = m1_best$k_ref,
  temperature = m1_best$multi_temperature,
  rise_weight = m1_best$align_rise_weight,
  slope_window = m1_best$slope_window,
  slope_weight = m1_best$slope_weight
)
m1 <- fit_m1(historical, selection, m0, m1_config) |>
  freeze_m1(m1_tuning)

m2_grid <- if (exists("prior_m2_results", inherits = FALSE)) {
  plan_m2_grid(prior_m2_results, max_finalists = 6L, max_specs = 64L)
} else {
  default_m2_grid()
}
m2_tuning <- tune_m2(historical, selection, m0, m1, grid = m2_grid,
                     verbose = TRUE)
validate_m2_tuning(m2_tuning)
m2 <- fit_m2(historical, selection, m0, m1, m2_tuning$best_spec) |>
  freeze_m2(m2_tuning)

candidate <- assemble_kit(m0, m1, m2)
validate_page_kit(candidate)
saveRDS(candidate, "results/candidate_pre_holdout.rds")
```

This candidate still excludes the untouched holdout and must be compared
with the pre-holdout incumbent through the governed acceptance workflow.

## Forecast

``` r

kit <- load_promoted_kit(
  kit_path =
    "/secure/PAGe/deployment-registry/<deployment-id>/promoted_kit.rds",
  deployment_manifest_path =
    "results/deployment-audit/<deployment-id>/deployment_manifest.json"
)
current <- prepare_surveillance_data(current_csv, season = "2026-27")
forecast <- run_pipeline(kit, current, mode = "frozen")
plot_forecast(forecast, history = historical)
```

Frozen-GAM prediction is the default; weekly refitting is an explicit
legacy compatibility option.
