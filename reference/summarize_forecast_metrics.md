# Summarize prospective forecast metrics

Computes trial-weighted Bernoulli negative log likelihood (NLL) and
absolute-error summaries by forecast horizon and epidemic phase. If no
explicit phase column is supplied, phase is deterministically defined
from t_since: values below 0 are pre-ignition, values from 0 through 3
are early, and values of 4 or greater are late.

## Usage

``` r
summarize_forecast_metrics(
  predictions,
  phase_col = NULL,
  phase_break = 4,
  eps = 1e-12
)
```

## Arguments

- predictions:

  Prediction data frame containing p_hat, observed probability (p_obs,
  or y_lead/N_lead), horizon (lead), and phase information.

- phase_col:

  Optional name of an existing phase column.

- phase_break:

  Non-negative boundary between early and late phases.

- eps:

  Probability clipping value.

## Value

A list with overall, horizon, and phase tables.
