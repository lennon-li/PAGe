# Review and record a retrospective ignition label

Use the labeling workflow when a season has no verified retrospective ignition
week, or when a user wants to inspect an existing label. The workflow accepts
canonical PAGe weekly data (`season`, `weekF`, `y`, and `N` or `neg`). It keeps
the observations unchanged and makes the evidence visible before a label is
recorded.

```r
library(PAGe)

# `season_data` must contain one season in canonical weekF coordinates.
review <- review_ignition_label(
  season_data,
  smooth_window = 3L,
  p_threshold = 0.01,
  candidate_window = c(10L, 42L),
  confidence = 0.95
)

review$summary       # one-row season summary
review$candidates    # threshold-crossing candidates
review$peak_summary  # missingness, max week, ties/plateau candidates
review$peak_candidates
review$plot          # print or save with ggplot2::ggsave()

# After visual inspection, explicitly record the selected observed week.
label <- finalize_ignition_label(
  review,
  weekF = 19L,
  annotator = "analyst-id",
  note = "Sustained rise across the smoothed signal and observed counts."
)

peak <- finalize_peak_label(
  review, weekF = 25L, annotator = "analyst-id",
  note = "Highest sustained observed positivity."
)

# Or finalize both labels in one auditable object.
season_labels <- finalize_season_labels(review, ignition_weekF = 19L,
                                        peak_weekF = 25L)
ignition_labels <- season_labels$ignition_labels
peak_labels <- season_labels$peak_labels

# Build a named vector for training and create aligned data in a new object.
labels <- label$labels
aligned <- apply_ignition_labels(
  all_training_data,
  labels,
  anchor_week = 20L,
  n_weeks_col = "nW_true"
)
```

`review_ignition_label()` reports observed positivity, a centred moving mean,
the week-to-week smoothed slope, Wilson intervals, threshold crossings, and the
observed maximum. It also reports missing weeks and all tied or near-tied
maximum weeks according to `peak_tolerance`, and marks them on the plot. These
are review aids; the function does not silently choose either label.
`finalize_ignition_label()` and `finalize_peak_label()` reject unobserved weeks
and store the review data hash and selected week in provenance.

`apply_ignition_labels()` adds `iWeek`, `phase`, and the wrapped aligned
`newWeek` coordinate used by M1 and M2. It returns a new data frame and leaves
raw `y`, `N`, `neg`, and `p` untouched. For prospective holdout replay, omit
that season from `ignition_labels` and use the existing prospective M0 detector;
do not use a retrospective ignition or peak label in the holdout predictors.
Peak labels are evaluation/reference metadata and do not enter prospective M0,
M1, or M2 predictors. Ignition labels enter historical training through
`iWeek`, `phase`, and `newWeek`; held-out ignition remains prospective and is
joined only after replay for scoring.

The canonical retrospective reference vector includes `2025-26 = 19L` in
unshifted M0 `weekF` coordinates. This is a proposed and now frozen
**operational retrospective reference label**, based on the agreed sustained
evidence rule; it is not biological ground truth. It is available through
`page_manual_ignition_labels()` and is used only when that season is explicitly
part of historical training or retrospective scoring. When `2025-26` is the
outer holdout, the governed fold removes this label from training inputs and
joins it only after replay for M0 scoring.
