# Infer a future peak-time posterior with M1-v2

The origin convention is release based: origin \`w\` means the completed
aggregate for interval \`\[w, w+1)\` is available, so the continuous
as-of boundary is \`w + 1\`. This function returns a posterior
conditional on the peak still being in the future of that boundary.

## Usage

``` r
m1_v2_peak_posterior(
  library,
  current_data,
  activation_week,
  origin_week,
  candidate_step = 0.1,
  max_future_weeks = 14
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

  Maximum future support from the release boundary.

## Value

A \`page_m1_v2_forecast\` object.
