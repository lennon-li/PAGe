# Infer M1-v2 peak-passage probability

Uses the peak-relative library extending through peak +3 and permits the
candidate peak to lie in the recent past. \`prob_peak_passed\` is
evaluated at the release boundary \`origin_week + 1\`.

## Usage

``` r
m1_v2_passage_posterior(
  library,
  current_data,
  activation_week,
  origin_week,
  candidate_step = 0.1,
  max_future_weeks = 12
)
```

## Arguments

- library:

  A \`page_m1_v2_library\`.

- current_data:

  Current-season surveillance data.

- activation_week:

  Causal M0 detection time \`A\`.

- origin_week:

  Integer observed-week origin.

- candidate_step:

  Candidate peak-time grid spacing.

- max_future_weeks:

  Maximum future candidate support.

## Value

A one-row data frame with passage probabilities plus the underlying
posterior as an attribute named \`posterior\`.
