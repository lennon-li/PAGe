# Stabilize a decimal peak estimate using only causal prior state

The causal candidate limits the movement of the current raw peak
estimate relative to the previous stabilized estimate. The current raw
interval width is retained and translated by the bounded center update,
so the output remains decimal and continues to represent current
uncertainty.

## Usage

``` r
.m1_stabilize_peak(
  t_peak,
  t_peak_ci,
  previous_state = NULL,
  max_jump_weeks = 2
)
```

## Arguments

- t_peak:

  Numeric scalar raw peak estimate.

- t_peak_ci:

  Numeric length-2 raw peak interval.

- previous_state:

  Optional prior same-season stabilized peak state.

- max_jump_weeks:

  Positive numeric maximum center movement per origin.

## Value

A list with stabilized \`t_peak\`, \`t_peak_ci\`, and the bounded
\`jump\` from the previous stabilized center.
