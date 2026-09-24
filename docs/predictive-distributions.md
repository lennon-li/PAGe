# Weekly predictive distributions

PAGe can represent uncertainty about a forecast as draws on the outcome scale,
then answer threshold questions such as `P(next week > 0.02)`. The
`page_predictive_distribution` object is model-agnostic: a forecasting engine
can construct it from its own predictive draws with
`new_page_predictive_distribution()`, or implement the
`predictive_distribution()` S3 method for its forecast class.

## Experimental residual adapter

`fit_forecast_calibrator()` builds an experimental adapter from genuine
out-of-sample weekly forecasts. Rows must identify season, forecast origin,
horizon, point forecast, positive count, and test count. If an observed
proportion is supplied, it is checked against the counts. The adapter applies a
Jeffreys empirical-logit correction to observed counts and samples residuals on
the logit scale. Consequently, the adapter's default outcome is labelled
`positivity_jeffreys_smoothed`: its threshold probabilities target the
Jeffreys-smoothed rate and can differ from probabilities for the raw observed
ratio `y/N`, especially when weekly test counts are small. Sampling first
selects a season uniformly, then an origin within that season. Training
forecasts within `eps` of 0 or 1 are excluded, and the adapter refuses target
point forecasts in that boundary range rather than extrapolating residuals
there. Each horizon is calibrated separately. The resulting distribution is
marginal over the phases and test volumes in the calibration data; it does not
model dependence between multiple future weeks.

Example interface with synthetic data:

```r
oos <- data.frame(
  season = rep(c("s1", "s2", "s3"), each = 2),
  eval_week = rep(10:11, 3), lead = 1L,
  p_hat = rep(c(0.01, 0.02), 3),
  y_lead = c(1, 2, 2, 3, 1, 4), N_lead = 100
)
oos$p_obs <- oos$y_lead / oos$N_lead

cal <- fit_forecast_calibrator(
  oos, predictor_id = "my-fixed-forecast-protocol-v1",
  out_of_sample = TRUE
)
```

`predictor_id` is a caller attestation that the calibration rows and target
forecast use the same fixed forecasting protocol. The current adapter can
compare identifiers but cannot prove that attestation. Calibration seasons
must precede the forecast season and the target season must not occur in the
calibration seasons; the adapter checks overlap, not chronology. It trims
season keys and canonicalizes common `YYYY/YY` labels to `YYYY-YY`, but other
aliases must be normalized by the caller.

For a forecast object with a registered method:

```r
d <- predictive_distribution(forecast, calibrator = cal, horizon = 1L)
probability_above(d, 0.02)
probability_below(d, 0.01, inclusive = TRUE)
distribution_quantile(d)
```

Threshold probabilities are empirical proportions of the generated draws.
Their `mc_se` and `mc_interval` attributes describe finite-draw simulation
error only, not uncertainty in the fitted residual pool. The reported numbers
of seasons and origins describe the calibration pool; seasons are the
independent units, and the minimum three-season requirement is only a basic
guard, not evidence that tail probabilities are reliable.

The residual adapter remains marked `experimental`. No real-data, untouched
season evaluation is bundled here, so its probabilities must not be described
as empirically calibrated. Validate it prospectively on untouched seasons
before using probabilities for decisions. Use model-native predictive draws
where available; the residual adapter pools observation and forecast variation
and does not separately identify them.

## Peak-week probabilities

Forecast engines can implement `peak_week_distribution()` and return the same
distribution object. `probability_peak_before(x, week)` answers
`P(peak week < week)`; set `inclusive = TRUE` for `P(peak week <= week)`.
Thresholds use the scale declared by the engine. For a discrete weighted
distribution, exact atom weights are used and Monte Carlo error attributes are
`NA`. Use `distribution_weights()` alongside `distribution_draws()` to inspect
the weighted atoms. Weighted quantiles are left-continuous inverse-CDF atom
quantiles. Strict and inclusive queries differ when the threshold equals an atom,
including fractional week atoms.

PAGe's current `page_forecast` adapter uses the latest M1 template peak
ensemble (or an explicit `origin_week`). It reports the weighted spread across
templates, whose weights are tuned for point alignment and are not posterior
probabilities. The result is labelled experimental and is not calibrated to
the eventual observed peak. It excludes within-template fit uncertainty and
observation-process uncertainty. A failed latest M1 origin is returned as
unavailable; the adapter never silently substitutes an older origin. Peak
weeks are converted to the PAGe `weekF` coordinate using the ignition and
reference anchor recorded at that origin. The future calibration target, once
evaluated with untouched seasons, is the earliest integer weekF attaining the
maximum observed positivity.

Atoms outside the season's `[1, n_weeks]` support are omitted and their
original weight is reported as `dropped_mass`. Renormalizing after this removal
conditions on an in-season peak and can shift the reported probabilities in
either direction; mass beyond the end of the season shifts them earlier, while
mass before week 1 shifts them later. Inspect the dropped mass. A threshold at
or before the forecast origin is flagged `partly_observed`: observed weeks
bearing on that event are already available, but the current template ensemble
does not condition its peak atoms on the observed maximum so far.

```r
d_peak <- peak_week_distribution(forecast)
probability_peak_before(d_peak, week = 20)
probability_peak_before(forecast, week = 20, inclusive = TRUE)
```

A third-party engine can expose its own peak atoms without inheriting PAGe
model internals:

```r
peak_week_distribution.my_forecast <- function(forecast, ...) {
  new_page_predictive_distribution(
    draws = forecast$peak_weeks,
    weights = forecast$peak_weights,
    outcome = "season_peak_week",
    scale = "week_of_year",
    support = c(1, forecast$n_weeks),
    target = list(n_weeks = forecast$n_weeks),
    status = "experimental"
  )
}
```
