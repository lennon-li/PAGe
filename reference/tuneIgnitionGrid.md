# Grid search ignition detection parameters (OS-aware parallel)

Tunes ignition detection thresholds over a parameter grid by repeatedly
calling the legacy season detector and comparing predicted ignition
weeks to historical "true" ignition weeks inferred from \`phase==1\`.

## Usage

``` r
tuneIgnitionGrid(
  dat,
  grid,
  miss_penalty = 20,
  lambda = 10,
  sum_tol = 0,
  ncores = 10L,
  verbose = TRUE,
  progress_every = 200L
)
```

## Arguments

- dat:

  Multi-season data.frame with required columns.

- grid:

  data.frame of parameter combinations. Any missing parameter columns
  among \`cls_thr\`, \`p_cum_thr\`, \`p_thr\`, \`prev_thr\`,
  \`n_consec\`, \`N\`, \`w_min\`, \`w_max\` will be filled with defaults
  (see below).

- miss_penalty:

  Numeric. Penalty added per missing season detection
  (\`iWeek_hat=NA\`). Default 20.

- lambda:

  Numeric. Weight on the worst-case absolute error \`max_abs\` in the
  combined \`score\`. Default 10.

- sum_tol:

  Numeric \>= 0. Tolerance applied when forming the candidate set after
  minimizing \`sum_abs\`: keep rows with \`sum_abs \<= min_sum +
  sum_tol\`. Default 0.

- ncores:

  Integer \>= 1. Number of cores. If 1, runs serially. Default 10.

- verbose:

  Logical. If \`TRUE\`, prints progress and best result summary. Default
  \`TRUE\`.

- progress_every:

  Integer. Master-side progress update frequency (in number of grid
  rows). Default 200.

## Value

A list with:

- best_params:

  Named list of best parameter values (subset of columns in \`grid\`).

- results:

  data.frame = \`grid\` plus evaluation metrics (\`score\`, \`sum_abs\`,
  \`max_abs\`, \`n_miss\`, \`mean_abs\`, \`sd_abs\`).

- best_row:

  Single-row data.frame containing the best parameter set and its
  metrics.

## Details

The evaluation is parallelized in an OS-aware way: - Windows: PSOCK
cluster (\`parallel::makeCluster()\` + \`parLapply()\`) - Linux/macOS:
forked processes (\`parallel::mclapply()\`)

\## Required columns \`dat\` must contain: - \`season\`, \`weekF\`,
\`phase\`, \`p\`, \`p_cls_p\`, \`y\`, \`N\`

\## Truth definition For each season, the "true" ignition week is:
\`iWeek_true = min(weekF\[phase == 1\])\`.

\## Scoring For each parameter set, the function computes: - \`diff =
iWeek_hat - iWeek_true\` - \`sum_abs = sum(abs(diff))\` across seasons
(ignoring \`NA\` diffs) - \`max_abs = max(abs(diff))\` across seasons
(worst-case; \`Inf\` if all missing) - \`n_miss =\` number of seasons
with \`iWeek_hat = NA\` - \`score = sum_abs + lambda \* max_abs +
miss_penalty \* n_miss\`

Selection is lexicographic: 1) minimize \`sum_abs\` 2) among parameter
sets with \`sum_abs \<= min(sum_abs) + sum_tol\`, minimize \`max_abs\`
3) tie-breakers: minimize \`n_miss\`, then minimize \`score\`
