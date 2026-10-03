# Deploy a Frozen PAGe Kit and Forecast New Weeks

This vignette starts from a kit created by
[`page_train()`](https://lennon-li.github.io/PAGe/reference/page_train.md)
or another governed PAGe training path. Deployment is an R-package
operation: the model does not require a shell installer or a systemd
service.

## Load the frozen kit

``` r

library(PAGe)
kit <- page_load_kit("artifacts/my-page-kit.rds")
```

[`page_load_kit()`](https://lennon-li.github.io/PAGe/reference/page_load_kit.md)
calls `page_validate_kit(..., mode = "frozen")` before returning the
object.

## Forecast a current season

[`page_forecast_now()`](https://lennon-li.github.io/PAGe/reference/page_forecast_now.md)
resolves the current surveillance source, runs the frozen prospective
pipeline, and returns the latest-origin forecast together with ignition
state and source provenance.

``` r

current_season <- data.frame(
  season = "2026-27",
  weekF = 1:12,
  y = c(1, 2, 2, 3, 4, 6, 9, 15, 25, 40, 65, 92),
  N = rep(5000, 12)
)
current_season$p <- current_season$y / current_season$N

now <- page_forecast_now(
  kit,
  source = current_season,
  season = "2026-27"
)

now$ignition
now$forecast
now$source
```

Pre-ignition seasons may legitimately return zero forecast rows in the
generic kit workflow. That is a valid model state, not an API error.

## Forecast from a file or supported live source

[`page_load_surveillance()`](https://lennon-li.github.io/PAGe/reference/page_load_surveillance.md)
and
[`page_forecast_now()`](https://lennon-li.github.io/PAGe/reference/page_forecast_now.md)
support the package’s real-time source adapters. Keep the resolved
source provenance with every forecast.

``` r

now <- page_forecast_now(
  kit,
  source = "path/to/current-surveillance.csv",
  season = "2026-27"
)
```

For a scheduled deployment, run the same R call from your preferred
scheduler (RStudio Connect, Posit Connect, cron, batch scheduler, CI, or
another R process). The forecasting contract remains in the package;
scheduling infrastructure is separate.

## Canonical pretrained v3

If you want the audited pretrained Influenza A/B v3 weekF12 model rather
than a kit trained from your own data, use
[`page_forecast()`](https://lennon-li.github.io/PAGe/reference/page_forecast.md).
Its canonical runtime bundle is shipped with PAGe and validated by hash
at runtime. M0/M1 retain exact canonical bytes; M2 ships deterministic
runtime-only projections that preserve source artifact IDs and source
SHA-256 provenance without bundling historical target-count frames.

``` r

v3 <- page_forecast(
  "path/to/hist_olis.RData",
  season = "2026-27"
)

v3
v3$monitoring$A$m0
v3$monitoring$A$m1
v3$monitoring$B$m1
v3$forecasts
```

The canonical v3 runtime is shadow-only and does not issue forecasts
before weekF12.
