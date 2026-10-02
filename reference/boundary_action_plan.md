# Build the next action for a tuning result

Combines the raw optimizer result, governed candidate selection,
boundary reports, and (when needed) the next resumable grid. This is
read-only and does not score or mutate the supplied tuning object.

## Usage

``` r
boundary_action_plan(
  tuning,
  stage = c("M0", "M1", "M2"),
  hard_caps = NULL,
  selection_method = c("min_nll", "one_se", "pareto"),
  steps = NULL,
  max_specs = NULL,
  m1_min_gain = 0.05,
  m1_prefer_simpler = TRUE
)
```

## Arguments

- tuning:

  A \`page_m0_tuning\`, \`page_m1_tuning\`, or \`page_m2_tuning\`
  result.

- stage:

  One of \`"M0"\`, \`"M1"\`, or \`"M2"\`.

- hard_caps:

  M1 hard-cap policy. Defaults to \`default_m1_hard_caps()\`.

- selection_method:

  M2 selection rule.

- steps:

  Optional adjacent expansion steps passed to \`expand_tuning_grid()\`.

- max_specs:

  Optional expanded-grid row cap.

- m1_min_gain:

  Practical-gain backoff for M1 boundary planning, in weeks. Forwarded
  to \`select_m1_candidate()\`.

- m1_prefer_simpler:

  Logical; prefer the simplest boundary-safe M1 candidate within
  \`m1_min_gain\`. Forwarded to \`select_m1_candidate()\`.

## Value

A \`page_boundary_action_plan\` containing raw/final selections,
reports, unresolved axes, and \`next_grid\` (or \`NULL\` when settled).
