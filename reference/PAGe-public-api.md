# Stable PAGe public API

These functions define the stable user-facing PAGe interface.
Development-generation labels such as v1, v2, and v3 are intentionally
absent from public function names. Historical versioned implementation
functions remain internal so frozen releases and repository-owned
reproduction workflows can retain exact provenance.

## Details

[`page_train()`](https://lennon-li.github.io/PAGe/reference/page_train.md),
[`page_forecast()`](https://lennon-li.github.io/PAGe/reference/page_forecast.md),
[`page_walkforward_report()`](https://lennon-li.github.io/PAGe/reference/page_walkforward_report.md),
[`page_walkforward_qmd()`](https://lennon-li.github.io/PAGe/reference/page_walkforward_qmd.md),
and the kit helpers are high-level PAGe workflows. `m0_*`, `m1_*`, and
`m2_*` functions provide the advanced scientific component interface.
[`aggregate_strata()`](https://lennon-li.github.io/PAGe/reference/aggregate_strata.md)
and
[`aggregate_strata_draws()`](https://lennon-li.github.io/PAGe/reference/aggregate_strata_draws.md)
support general stratified aggregation, including pathogen types, age
groups, regions, sites, independent strata, explicit
correlation/covariance structures, and joint simulation draws.
[`page_render_report()`](https://lennon-li.github.io/PAGe/reference/page_walkforward_qmd.md)
is an alias for
[`page_walkforward_qmd()`](https://lennon-li.github.io/PAGe/reference/page_walkforward_qmd.md),
which emits a cumulative Quarto `.qmd` with per-origin as-of tabsets and
optionally renders it to HTML.

The complete supported namespace is documented in `docs/public-api.qmd`
in the source repository.

## See also

[`page_train`](https://lennon-li.github.io/PAGe/reference/page_train.md),
[`page_forecast`](https://lennon-li.github.io/PAGe/reference/page_forecast.md),
[`page_models`](https://lennon-li.github.io/PAGe/reference/page_models.md),
[`page_walkforward_report`](https://lennon-li.github.io/PAGe/reference/page_walkforward_report.md),
[`page_walkforward_qmd`](https://lennon-li.github.io/PAGe/reference/page_walkforward_qmd.md),
[`page_validate_kit`](https://lennon-li.github.io/PAGe/reference/page_validate_kit.md),
[`aggregate_strata`](https://lennon-li.github.io/PAGe/reference/aggregate_strata.md),
[`aggregate_strata_draws`](https://lennon-li.github.io/PAGe/reference/aggregate_strata_draws.md),
[`shared_denominator_correlation`](https://lennon-li.github.io/PAGe/reference/shared_denominator_correlation.md),
[`m0_fit`](https://lennon-li.github.io/PAGe/reference/m0_fit.md),
[`m0_detect`](https://lennon-li.github.io/PAGe/reference/m0_detect.md),
[`m1_fit`](https://lennon-li.github.io/PAGe/reference/m1_fit.md),
[`m1_predict`](https://lennon-li.github.io/PAGe/reference/m1_predict.md),
[`m1_peak_posterior`](https://lennon-li.github.io/PAGe/reference/m1_peak_posterior.md),
[`m1_passage_posterior`](https://lennon-li.github.io/PAGe/reference/m1_passage_posterior.md),
[`m2_fit`](https://lennon-li.github.io/PAGe/reference/m2_fit.md),
[`m2_predict`](https://lennon-li.github.io/PAGe/reference/m2_predict.md),
[`evaluate_forecasts`](https://lennon-li.github.io/PAGe/reference/evaluate_forecasts.md),
[`replay_holdout`](https://lennon-li.github.io/PAGe/reference/replay_holdout.md),
[`verify_promotion`](https://lennon-li.github.io/PAGe/reference/verify_promotion.md).
