# Compute ignition-to-peak time weights for alignment loss

Creates per-observation weights that emphasise the rising limb (ignition
to peak) of the reference curve. Pre-peak trough weeks receive a low
weight, the ignition-to-peak region receives a boosted weight, and weeks
after the peak decay exponentially back toward 1.

## Usage

``` r
compute_align_weights(
  t,
  g_ref_fun,
  trough_weight = 0.1,
  rise_weight = 3,
  peak_decay = 0.3,
  n_weeks = 52L
)
```

## Arguments

- t:

  Numeric vector of newWeek values (observed data).

- g_ref_fun:

  Reference curve function on logit scale.

- trough_weight:

  Weight for pre-rising-limb weeks (default 0.1).

- rise_weight:

  Weight for ignition-through-peak weeks (default 3.0).

- peak_decay:

  Exponential decay rate after peak (default 0.3).

- n_weeks:

  Integer; template domain length (default 52).

## Value

Numeric vector of time weights, same length as `t`.
