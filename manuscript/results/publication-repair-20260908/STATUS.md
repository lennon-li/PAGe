# Publication repair status — 2026-09-08

## Implemented and checked

- Raw M2 link predictions are retained before online bias, caps and post-peak
  M1 substitution, in runtime and frozen tuning evaluation.
- Replay retains conditional fitted-mean bounds, raw predictors, stage objects,
  and a full origin/horizon ledger. No-scorable replay returns explicit failure;
  alignment exceptions are distinguished from pre-ignition states.
- Methods, Results and the dated deviations record distinguish executed
  objectives from the frozen protocol without changing the historical table.
- Independent persistence, seasonal-naive, calendar-GAM and analogue diagnostic
  implementations have origin-time feature and outer-season exclusion tests.
- Targeted correction/evaluation/publication tests passed (116 expectations),
  plus 16 replay-sidecar expectations. Earlier runtime/reproduction regression
  tests also passed. Documentation regenerated; `git diff --check` passed.
  Full package release checks and coverage thresholds are not certified here.

## Completed diagnostic analyses

The repaired-runtime replay completed all 11 seasons in 1,734.8 seconds
(28m55s), with 655 matched archived prediction keys and no source changes.
The four comparator diagnostics completed in 874.6 seconds (14m35s), using 138
paired h2 rows (13 per full season and 8 for 2025--26). Results are confined to
this directory; archives are unchanged. No recurrent model monitoring was
scheduled.

The aggregate h2, ignition-offset 0--12, trial-weighted results were:

| Model | Equal-season NLL | Pooled-trial NLL | Equal-season weighted MAE |
|---|---:|---:|---:|
| PAGe repaired runtime | 0.4628 | 0.4382 | 0.0541 |
| PAGe archived pre-repair | 0.4628 | 0.4382 | 0.0541 |
| Calendar GAM | 0.4613 | 0.4364 | 0.0476 |
| Persistence | 0.4684 | 0.4439 | 0.0556 |
| Historical analogue | 0.4809 | 0.4732 | 0.0732 |
| Seasonal naive | 0.4917 | 0.4843 | 0.0841 |

The repaired and archived PAGe h2 equal-season NLLs were 0.462821 and
0.462840, respectively; the mean seasonal change was -0.000019. The calendar
GAM was numerically best in this diagnostic, but every selected calendar and
analogue configuration was at a declared grid edge. These comparator results
are therefore bounded diagnostics, not a final superiority claim or a fully
nested publication analysis.

The detailed rows are in
[`comparison_h2_0_12.csv`](comparison_h2_0_12.csv),
[`replay/20260908T125939/summary.json`](replay/20260908T125939/summary.json),
and [`comparators/summary.json`](comparators/summary.json).

## 2014–15 discrepancy diagnosis

The maximum repaired-versus-archived difference is -0.008247437 in positivity
at 2014--15, evaluation week 28, h1: -0.8247 percentage points. It is not a
row, target, season, or horizon mismatch; all 65 keys match. The archived
implementation reconstructed the prior raw GAM link as
`qlogis(p_hat) - bias`, although `p_hat` had already passed through the fitted
soft cap. In that season's preceding week-27 h1 prediction, the fitted
training positivity maximum/soft-cap knee was 0.3574 while the emitted capped
probability was about 0.3929. The inverse-logit reconstruction therefore
understated the raw link and inflated the next residual/bias update. The repaired runtime
uses the raw GAM link returned directly by `predict(..., type="link")`; this
isolated change produces the 0.8247-point shift. The maximum change in every
other 2014--15 row is 0.0042 percentage points.

The row-level investigation is retained in
[`delta_2014-15.csv`](delta_2014-15.csv). This is a bug-correction effect,
not evidence to discard the repaired result; it should be reported as a
software/reproducibility deviation and sensitivity, not silently merged with
the archived numbers.

A controlled replay using identical saved M1 curves and the same fitted kit
now reproduces the repaired predictions exactly (maximum absolute error zero).
Changing only the residual-logging formula gives a week-28 h1 difference of
-0.008247359, explaining the archived discrepancy to within 7.8e-8 positivity.
See [`controlled_residual_comparison.json`](controlled_residual_comparison.json)
and `scripts/publication_reconcile.R`. The consolidated comparison CSV has also
been regenerated with 66 unique season/model rows, removing the 11 duplicated
archived-PAGe entries. Aggregate means are unchanged by this correction.

## Required terminal audit and remaining publication gaps

1. Verify all 11 replay statuses, source stability, failure accounting and
   matched prediction deltas before interpreting corrected-runtime scores.
2. Review comparator convergence and boundary flags. Inner comparator windows
   condition on archived ignition estimates; these results are explicitly
   diagnostic, not a fully nested publication-ready comparator analysis.
3. Produce peak-error-by-origin and ignition-error reporting from saved stage
   objects, with verified reference-label provenance and partial-season flags.
4. Assess effects of the residual-state correction on historical tuning.
   Frozen-kit replay does not correct prior fitting or candidate selection.
5. Finish ablations, label sensitivity, simulation/uncertainty evidence and
   release checks. Do not describe this patch set as publication completion.

Same 11 eligible seasons, four exclusions and 10-training/1-holdout design;
no new observations, hypothesis tests, promotion, commit or push.
