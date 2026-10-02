# Build numeric timing targets for opt-in M0 training

Build numeric timing targets for opt-in M0 training

## Usage

``` r
prepare_timing_training_data_v2(data, labels)
```

## Arguments

- data:

  Weekly training data with season and weekF.

- labels:

  Timing-v2 label object or list of objects.

## Value

A copy of `data` with numeric `ignition_target_weekF` and
`peak_observed_weekF` columns.
