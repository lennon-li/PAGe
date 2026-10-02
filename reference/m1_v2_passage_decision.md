# Decide whether M1-v2 peak passage is confirmed

Confirmation uses two independent forms of causal evidence. The fast
branch requires a high passage posterior and an immediate observed
decline. The sustained branch permits a lower passage posterior only
after two consecutive declines and a material drop from the
post-activation running maximum.

## Usage

``` r
m1_v2_passage_decision(
  passage_history,
  current_data,
  activation_week,
  high_threshold = 0.95,
  low_threshold = 0.1,
  drop_fraction = 0.05,
  fast_drop_fraction = 0,
  min_post_activation = 4L
)
```

## Arguments

- passage_history:

  Data frame containing at least \`origin_week\` and
  \`prob_peak_passed\`; typically rows returned by
  \`m1_v2_passage_posterior()\` across sequential origins.

- current_data:

  Current-season surveillance data through the latest origin.

- activation_week:

  Causal M0 detection time.

- high_threshold:

  Minimum posterior passage probability for the fast branch. Must be at
  least 0.9 by contract.

- low_threshold:

  Minimum posterior passage probability for the sustained decline
  branch.

- drop_fraction:

  Required fractional decline from the post-activation running maximum
  for the sustained branch.

- fast_drop_fraction:

  Optional fractional decline from the post-activation running maximum
  required by the one-week fast branch. The validated M1-C rule uses 0:
  safety comes from a high passage posterior (\>=0.95) plus an actual
  immediate decline. Positive values are retained only for controlled
  sensitivity experiments.

- min_post_activation:

  Minimum integer observed weeks after activation before passage can be
  confirmed.

## Value

A one-row data frame describing the passage state.
