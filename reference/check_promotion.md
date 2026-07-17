# Check whether a candidate forecast model qualifies for promotion

Check whether a candidate forecast model qualifies for promotion

## Usage

``` r
check_promotion(
  candidate,
  incumbent,
  min_nll_improvement = 0.02,
  max_horizon_degradation = 0.05,
  max_phase_degradation = 0.1
)
```

## Arguments

- candidate, incumbent:

  Metric lists returned by summarize_forecast_metrics().

- min_nll_improvement:

  Required relative Bernoulli NLL improvement.

- max_horizon_degradation:

  Maximum relative MAE degradation at any lead.

- max_phase_degradation:

  Maximum relative MAE degradation in any phase.

## Value

A versioned `page_promotion_report` with canonical schema, aggregate
gates, reasons, thresholds, and per-horizon and per-phase details.
Promotion passes only when every gate passes; zero or missing incumbent
baselines fail safely. The schema supports consistency checks; it does
not provide cryptographic provenance or authenticity.
