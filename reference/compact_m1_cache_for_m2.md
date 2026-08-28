# Compact a complete M1 LOSO cache for M2

A complete Phase 1 cache retains the reference fit and alignment objects
used to generate M1 predictions. M2 only needs the aligned training
data, per-fold template metadata, and the already generated M1
train/test predictions. This function preserves the latter inputs while
dropping the M1-only reference and hyperparameter payload before
parallel M2 evaluation.

## Usage

``` r
compact_m1_cache_for_m2(m1_cache)
```

## Arguments

- m1_cache:

  Named list of complete Phase 1 fold artifacts, as produced internally
  by
  [`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md).

## Value

A named list with the M2-only fold handoff. The original cache is not
modified.
