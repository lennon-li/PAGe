# Executed-analysis deviations and publication audit disposition

Recorded: 2026-09-08. Status: post-results reconciliation, not a new
preregistration or an amendment to the frozen primary analysis.

## Evidence and visibility

The 11-season replay results and the 2026-09-07 publication audit were already
visible when this record was written. Sources are the
[publication audit](PUBLICATION_AUDIT_2026-09-07.md),
[manuscript runner](../scripts/run_manuscript_holdout.R), and the selection and
scoring implementations identified below. This is a documentation repair, not
a rerun, candidate reselection, or independent verification of historical
training. Current source does not substitute for a hash-bound executed snapshot.

The existing version 1.4 [protocol](ANALYSIS_PROTOCOL.md) remains frozen:
primary h2, origins from detected ignition through +12 weeks inclusive,
trial-weighted NLL within season, equal-season aggregation, calendar-GAM
comparison on common rows, and one-standard-error inner selection. No primary
definition, comparator, exclusion, or season membership is retrospectively
changed. No hypothesis tests, p-values, inferential intervals, or superiority
decision are added.

## Executed choices versus frozen definitions

| Component | Executed analysis | Disposition |
|---|---|---|
| M0 selection | Detector-error objective and lexicographic error ranking, not h2 forecast NLL or one-SE | Recorded deviation |
| M1 selection | Weighted peak-week MAE (`mae_weibull`); `min_gain = 0.05`, `prefer_simpler = TRUE` | Recorded deviation; practical-gain rule is not one-SE |
| M2 selection | `select_m2_candidate(method = "min_nll")` | Recorded deviation from one-SE |
| Inner M2 score | Bernoulli cross-entropy averaged equally over weekly/horizon rows for h1 and h2 within season, then equally across seasons | Not trial-weighted h2-only primary objective |
| Final reported score | Target-denominator-weighted Bernoulli NLL over both horizons and full available post-ignition season | Retain all 11 whole-replay metrics as descriptive executed results |
| Primary-window paired diagnostics | h2, `0 <= t_since <= 12`, identical PAGe/calendar-GAM rows | Pending; cannot repair selection retrospectively |

### Stage objective details

In [M0 tuning](../PAGe/R/pipeline_training.R), `tune_m0()` uses
`lambda = 20`, `gamma = 25`, and zero `kappa`, `gamma_late`, and
`miss_penalty`. For ignition error `d = detected - reference`, the
[detector scorer](../PAGe/R/m0_training.R) defines adjusted error
`a = max(d, 0) + max(-1 - d, 0)`, allowing a one-week-early detection without
loss. Its score is `sum(a + 25 * max(a - 2, 0)) + 20 * max(a)` over
evaluable detections. Selection ranks `n_over2`, `n_late_over2`, `max_abs`,
`n_miss`, then `score` lexicographically. Misses therefore remain a ranking
criterion despite their zero additive penalty. This is a detector objective,
not a uniform forecast-NLL objective for all stages.

M1 uses season-equal, within-season-normalized weighted peak-week MAE,
with weights `exp(-(0.1 * weeks_before_peak)^2)`. The runner calls
[`select_m1_candidate()`](../PAGe/R/stage_contracts.R) with a 0.05-week
minimum-gain preference: choose the smallest boundary-admissible `k_ref`
within 0.05 weeks of the best score. The runner declares `k_ref` hard bounds
10--52. This practical simplification threshold is not a standard error.

The [inner M2 evaluator](../PAGe/R/m2_loso_eval.R) computes
`-mean(p_obs * log(p_hat) + (1 - p_obs) * log(1 - p_hat))` over available
weekly/horizon rows, clipping probabilities to `[1e-12, 1 - 1e-12]`.
The tuning summary averages these fold scores equally. In contrast, the
[final replay scorer](../PAGe/R/evaluation_gates.R) uses target test counts
as row weights. Both scores omit the model-independent binomial combinatorial
term, but their weighting and target support differ. The runner also applies
stage boundary-expansion/stopping rules, including axis-specific M2 minimum
NLL gains; those rules do not implement one-SE selection.

## Outer holdouts and internal conditional tuning

The declared design is exchangeable-season outer LOSO with within-season
walk-forward predictions: 11 holdouts, 10 training seasons per fold, and fixed
exclusions 2011--12, 2015--16, 2020--21, and 2021--22. Later calendar seasons
intentionally train earlier holdouts. It is not chronological outer validation
or evidence that those training observations were historically available at
each forecast date. Within a replay, origin-time features and state updates
must still exclude future observations.

Internal M2 tuning rebuilds inner reference fits while holding upstream M0/M1
hyperparameters at choices selected on the outer training set. Those internal
scores are conditional on fixed upstream hyperparameters, not independent
end-to-end nested validation with upstream reselection in every inner fold.
This does not itself imply global outer leakage or invalidate an excluded
outer fold. It must not be conflated with historical M2 experiments using
globally selected upstream choices across their evaluation seasons.

The partial 2025--26 season remains one of the 11 folds and supplies only its
available observations when training the other folds. Equal membership is not
equal coverage. Its new governed fold is distinct from the earlier acceptance
replay but is not untouched confirmation. The runner's `2025-26 = 19L` label
does not establish source/date/hash provenance or actual fold-filtered use;
these remain unresolved, without an inferred provenance or leakage finding.

## Interpretation and pending checks

- **Retained:** all 11 existing seasonal metric rows and their whole-replay
  descriptive summaries. The prior audit reproduced seasonal NLLs from 655
  exported rows within 5e-13. Ten replays have 57--73 rows and extend to
  +28--36 post-ignition weeks; the partial 2025--26 replay has 17 rows.
- **Pending:** paired h2/0--12 PAGe/calendar-GAM diagnostics on identical
  eligible rows, with target-count weighting, equal-season contrasts, and
  explicit missing-row/failure accounting. Secondary paired h1 diagnostics
  should use the same origin window. The audit's PAGe-only restricted scores
  are diagnostic rescoring, not completed comparator evidence.
- **Not repaired by rescoring:** the selection-rule and inner-objective
  deviations. A protocol-aligned selection analysis would require recoverable
  inner candidate predictions and potentially reranking, refitting, and replay,
  or new tuning where evidence is unavailable. After outcome access, such work
  must be labelled a sensitivity analysis or new development cycle, not a
  replacement preregistration. No such computation is authorized by this record.
- **NOT verified:** corrected post-peak results. The parent is repairing raw-GAM
  predictor capture before bias, caps, and M1 substitution. Deterministic
  transition tests, runtime/evaluator parity, and effects on tuning and replay
  are pending. Archived metric reproducibility does not prove the intended
  residual-state algorithm was executed correctly or that point forecasts are
  unchanged by the fix.
- **Limited interval claim:** current M2 bounds from `eta +/- 1.96 * se.fit`
  are conditional fitted-mean bands, not full predictive intervals. They do
  not fully propagate observation, upstream, selection, online-correction, or
  revision uncertainty. Archived replay bounds are unavailable, so predictive
  coverage is not demonstrated. The `brier` field likewise denotes squared
  error of aggregate positivity rather than individual Bernoulli Brier score.
- **Pending provenance:** recoverable executed script/package hashes and
  environment records. Shared commit/input identifiers and nonempty
  working-tree manifests do not establish a fully reproducible execution
  snapshot. No 2025 label provenance or corrected numerical results are invented.

## Documentation disposition

Methods now separates executed choices from frozen definitions and pending
comparisons. Results retains the original numerical table and identifies its
whole-replay scope. The protocol receives only a dated audit cross-reference;
its primary definitions remain unchanged. Comparator, ablation, stage-level,
label-sensitivity, and uncertainty evidence remain required before submission.
