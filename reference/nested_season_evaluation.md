# Run the complete nested seasonal evaluation

Rotates every requested season through the outer holdout. Each outer
fold independently performs inner leave-one-season-out tuning, boundary
expansion, M2-versus-M1 adoption, frozen-kit fitting, and strict weekly
replay. Completed fold artifacts may be reused when \`resume = TRUE\`.
Every fold replay must pass the forecast-key completeness and
consistency checks before its rows contribute to the aggregate.

## Usage

``` r
nested_season_evaluation(
  data,
  holdouts = NULL,
  exclude = .default_nested_exclusions(),
  artifact_dir = NULL,
  checkpoint_dir = NULL,
  resume = TRUE,
  timing_labels = NULL,
  gate_nesting = c("full", "conditional"),
  ...
)
```

## Arguments

- data:

  Canonical multi-season surveillance data.

- holdouts:

  Seasons to hold out in turn. Defaults to every season not in
  \`exclude\`.

- exclude:

  Fixed excluded seasons. Defaults to the protocol exclusions
  \`"2011-12"\`, \`"2015-16"\`, \`"2020-21"\`, and \`"2021-22"\`.

- artifact_dir:

  Parent directory for one subdirectory per outer fold.

- checkpoint_dir:

  Optional parent checkpoint directory.

- resume:

  Reuse a completed \`outer_fold_result.rds\` when its recorded holdout
  matches the requested fold. Legacy results without shadow fields load
  with shadow status \`absent\`; they are not refit to add shadow
  evidence.

- timing_labels:

  Optional timing-v2 label object or list of objects; passed to each
  outer fold after that fold's holdout is isolated.

- gate_nesting:

  Inner-gate nesting depth forwarded to every outer fold. See
  \`train_outer_fold()\`; defaults to \`"full"\`.

- ...:

  Additional arguments passed to \`run_outer_fold()\`.

## Value

A \`page_nested_season_evaluation\` containing all fold results,
canonical out-of-fold predictions, and equal-season primary and
test-count-weighted sensitivity summaries.
