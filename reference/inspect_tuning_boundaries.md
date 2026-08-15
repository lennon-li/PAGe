# Inspect tuning boundaries and optionally warn about unresolved edges

Reports every genuinely tuned numeric axis and marks an edge winner as
\`expand_required\`, unless that value is a predeclared null/drop. The
report is deliberately separate from the hard freeze gate so users can
inspect a result, expand its grid, and resume tuning from the same
checkpoint.

## Usage

``` r
inspect_tuning_boundaries(
  x,
  stage = c("M0", "M1", "M2"),
  grid = NULL,
  warn = TRUE,
  null_axes = NULL
)
```

## Arguments

- x:

  A stage tuning result, or a data frame containing the tuning grid.

- stage:

  One of \`"M0"\`, \`"M1"\`, or \`"M2"\`.

- grid:

  Optional complete grid. When omitted, uses \`x\$grid\`.

- warn:

  Logical; emit a warning when a non-null edge requires expansion.

- null_axes:

  Optional names of axes whose zero value is an accepted drop/null.
  Stage defaults are used when omitted.

## Value

A data frame with tested range, selected value, boundary, decision, and
reason for every varying numeric axis.
