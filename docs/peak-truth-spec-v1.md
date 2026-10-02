# Retrospective Peak Truth Specification v1

Status: frozen measurement specification for the M1/M2 redesign retrospective peak target.

## Point estimate

For each completed season, fit:

```r
mgcv::gam(
  cbind(y, N - y) ~ s(weekF, bs = "cr", k = 8),
  family = quasibinomial(),
  method = "REML"
)
```

Evaluate the fitted response on a 0.01-week grid over the observed season and define the retrospective continuous peak point as the grid location with maximum fitted positivity.

## Why k = 8

Before freezing the specification, peak location was audited at `k = 5, 6, 8, 10` across all 11 completed seasons.

Relative to the within-season median peak across those four smooths, `k = 8` had the smallest overall deviation:

- mean absolute deviation: 0.228 week;
- median absolute deviation: 0.110 week;
- maximum absolute deviation: 0.710 week.

The alternative k values had larger mean deviations (approximately 0.41-0.48 week) and larger worst-case deviations.

## Smoothing-sensitivity interval

The point estimate alone must not imply false sub-week certainty.

For every season, also compute the minimum and maximum peak location across `k = 5, 6, 8, 10`.

Store:

- `peak_week_decimal`: k=8 point estimate;
- `peak_sensitivity_low`: minimum across the four k values;
- `peak_sensitivity_high`: maximum across the four k values;
- `peak_sensitivity_range`: high - low;
- `peak_ambiguous`: TRUE when the range exceeds 1.0 week.

This interval is a model-specification sensitivity diagnostic, not a formal confidence interval.

## Ambiguous seasons in the initial 11-season set

Under the >1.0-week rule, the following are smoothing-sensitive:

- 2017-18;
- 2018-19;
- 2023-24;
- 2025-26 (1.10 weeks; borderline but above threshold).

These seasons remain in evaluation but their peak truth should not be treated as sub-week precise.

## Runtime prohibition

This GAM uses the complete retrospective season and therefore defines evaluation truth only. It must never be used as a runtime feature or fit to suffix data unavailable at a forecasting origin.

## Versioning

Specification ID: `retrospective-gam-peak-v1-k8`.

Any later change to response family, basis, k, smoothing selection, grid resolution, or ambiguity threshold requires a new truth-specification version and full rescoring.
