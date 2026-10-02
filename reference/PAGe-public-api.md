# Stable PAGe public API

These functions define the stable user-facing PAGe interface.
Development-generation labels such as v1, v2, and v3 are intentionally
absent from public function names. Historical versioned implementation
functions remain internal so frozen releases and repository-owned
reproduction workflows can retain exact provenance.

## Usage

``` r
page_train(...)
page_forecast(...)
page_models()
page_walkforward_report(...)
page_validate_kit(...)
aggregate_strata(...)
aggregate_strata_draws(...)
shared_denominator_correlation(...)
m0_fit(...)
m0_detect(...)
m1_fit(...)
m1_predict(...)
m1_peak_posterior(...)
m1_passage_posterior(...)
m2_fit(...)
m2_predict(...)
evaluate_forecasts(...)
replay_holdout(...)
verify_promotion(...)
```

## Arguments

- ...:

  Arguments passed to the corresponding governed PAGe implementation.
  See the function-specific examples and the public API walkthrough for
  the supported workflow.

## Details

`page_train()`, `page_forecast()`, `page_walkforward_report()`, and the
kit helpers are high-level PAGe workflows. `m0_*`, `m1_*`, and `m2_*`
functions provide the advanced scientific component interface.
`aggregate_strata()` and `aggregate_strata_draws()` support general
stratified aggregation, including pathogen types, age groups, regions,
sites, independent strata, explicit correlation/covariance structures,
and joint simulation draws.

The complete supported namespace is documented in `docs/public-api.qmd`
in the source repository.
