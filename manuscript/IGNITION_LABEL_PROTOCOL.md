> **Status (2026-09-15): PRIOR CYCLE** — commit 95c1c9f / CSV-label seasons / truncated 2025-26; not comparable with the new cycle. See drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

# Ontario influenza ignition-label protocol

- Protocol version: 1.1
- Freeze date: 2026-09-01
- Coordinate system: canonical M0 `weekF` with influenza season start at MMWR
  week 27
- Season scope: [`ONTARIO_FLU_SEASON_DECLARATION.md`](ONTARIO_FLU_SEASON_DECLARATION.md)

## Purpose and interpretation

The ignition label is the retrospective reference week used to evaluate M0 and
to supervise training seasons. It is not an externally validated biological
ground truth. For this manuscript, the canonical influenza vector includes
the 11-season rotating-holdout reference for `2025-26`, frozen from the
already-used authorized influenza data under the same retrospective rule. It
cannot be chosen from forecast performance.

The observed label for an outer replay season is never supplied to the
prospective detector. It is joined only after prediction for scoring.

## Existing canonical labels

The canonical eleven-label vector, in unshifted M0 coordinates, is:

```r
ignition_labels_m0 <- c(
  "2012-13" = 18L,
  "2013-14" = 20L,
  "2014-15" = 20L,
  "2016-17" = 19L,
  "2017-18" = 20L,
  "2018-19" = 19L,
  "2019-20" = 22L,
  "2022-23" = 15L,
  "2023-24" = 20L,
  "2024-25" = 23L,
  "2025-26" = 19L
)
```

The existing `2015-16 = 24L` label belongs only to its separately reported
special diagnostic cycle. It is not a principal-analysis training or scoring
label.

`2025-26 = 19L` is the frozen operational retrospective reference for the
current eleven-season analysis. It is recorded in the package label accessor
and this protocol; it remains an operational reference, not biological ground
truth.

## Label provenance

The vector above is reproduced in the current influenza training sources,
including `scripts/fresh_run/00_shared.R` and the ignition-training
documentation. Historical sources describe these as retrospective,
algorithm-defined reference labels derived with the full season available;
their independent expert-adjudication lineage is not reconstructible from the
public repository. The manuscript must therefore call them **frozen
retrospective reference labels**, not verified infection-onset ground truth.

## Fold-safe use

For outer fold `F`:

1. define `manual_labels_train <- ignition_labels_m0[names(ignition_labels_m0) != F]`;
2. fit and tune M0 using only the 10 fitting seasons and their labels;
3. run M0 on `F` with `manual_labels_test = NULL` and no week override;
4. freeze the resulting origin-by-origin detector output before joining the
   retrospective label for M0 error calculation;
5. rebuild M1 and M2 fold-local objects without `F` in their label vectors,
   templates, or fitting data; and
6. retain the exact named training-label vector and its hash in each fold
   manifest.

Supplying `F` through a shared label vector to `flagIgnition()`, M1, or M2 is
leakage. The affected checkpoint must be discarded and recomputed; reranking it
does not repair the fold.

## M1 coordinate handling

The vector above is always stored in unshifted M0 `weekF` coordinates. The
governed `tune_m1()` path may apply the historical one-week M1 coordinate offset
internally and must record the resulting vector in the M1 artifact. A script-
specific shifted vector must never replace the canonical M0 labels or be passed
back to M0.

## Prespecified sensitivities

The following are secondary sensitivity analyses and do not alter the frozen
principal labels:

1. subtract one week from every admissible training reference label;
2. add one week to every admissible training reference label; and
3. remove manual downstream overrides and use fold-specific M0-generated
   ignition states throughout M1/M2 training.

Each sensitivity uses the same 11 valid seasons and outer folds. It cannot add
one of the four excluded seasons or another season. Results are labelled
secondary and cannot replace the primary PAGe-versus-calendar-GAM result.

## Validation checks

Before model fitting, assert that:

- label names exactly equal the 11 valid season identifiers, including a
  verified non-approximate `2025-26` reference;
- values are finite, integer-valued, and in the valid `weekF` range;
- no excluded season is present;
- every outer test season is absent from `manual_labels_train`;
- `manual_labels_test` is `NULL` for prospective fold evaluation; and
- the canonical vector and every sensitivity vector are hash-bound in the
  analysis manifest.

Any failed assertion stops the run. Labels are never repaired interactively
after seeing model output.

## Required reporting

Methods must report the coordinate system, full label provenance limitation,
fold-safe withholding rule, and three sensitivities. Results must report M0
absolute error, signed delay, miss rate, false-alarm rate, and the sensitivity
of downstream conclusions to the alternate label rules.
