# Default parameter-specific M2 NLL gain caps

The caps are applied to matched adjacent comparisons during governed M2
boundary inspection. A value of zero means that only a non-improving
move (an exact tie or a deterioration) is stopped by the practical-gain
rule. Smoothing dimensions use the thresholds documented in the tuning
playbook; structural axes use zero because their scales are discrete and
not directly comparable to NLL changes on continuous axes.

## Usage

``` r
default_m2_nll_gain_caps()
```

## Value

A named non-negative numeric vector covering every tuned M2 axis.
