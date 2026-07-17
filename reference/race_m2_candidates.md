# Conservatively race M2 candidates before full nested LOSO

Conservatively race M2 candidates before full nested LOSO

## Usage

``` r
race_m2_candidates(
  grid,
  evaluator,
  stages = c(3L, 6L),
  min_survivors = 3L,
  confidence = 0.95,
  full_evaluator,
  ...
)
```

## Arguments

- grid:

  Candidate grid containing spec_id.

- evaluator:

  Callback evaluator(grid, stage, ...) returning fold-level spec_id and
  bernoulli_nll rows for a partial stage.

- stages:

  Increasing deterministic stage sizes passed to evaluator.

- min_survivors:

  Minimum number retained at every stage.

- confidence:

  Confidence level for mean-NLL intervals.

- full_evaluator:

  Required callback run once on final survivors. It must perform full
  nested LOSO; partial racing results are never final rankings.

- ...:

  Additional callback arguments.

## Value

Racing history, survivors, and the full evaluator result.
