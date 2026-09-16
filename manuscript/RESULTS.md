> **Status (2026-09-15): PRIOR CYCLE** — commit 95c1c9f / CSV-label seasons / truncated 2025-26; not comparable with the new cycle. See drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

# Results

## Governed replay artifact completeness

The governed Ontario influenza replay was completed for all 11 declared
exchangeable holdout seasons. Each holdout used the other 10 eligible seasons
for training, while 2011–12, 2015–16, 2020–21, and 2021–22 remained fixed
exclusions. The M0→M1→M2 lifecycle completed before strict unseen-season
replay for every holdout. Later calendar seasons intentionally trained earlier
holdouts; the design is exchangeable-season outer LOSO with within-season
walk-forward prediction, not chronological training-only evaluation. The
execution record reports PAGe 0.2.0, shared source commit
`95c1c9f3e084844aa6b5f96219290ca64b66e082`, and authorized input
checksum `fa8add1b253944df5d853a2fb0456d7ac368657e073da0d97f909be95ca59c54`.
Strict reconciliation found 11 complete, 0 pending, 0 missing, and 0 invalid
seasonal artifacts. The machine-readable source is
[`holdout_reconciliation_principal.csv`](../results/audit/holdout_reconciliation_principal.csv),
with the accompanying report in
[`holdout_reconciliation.md`](../results/audit/holdout_reconciliation.md).

The publication audit found nonempty working-tree status in the run manifests.
Installed-package and executed-script hash provenance remains incomplete;
the shared commit does not establish complete execution-source identity.

## Seasonal replay performance

These are the executed whole-replay scores: trial-weighted within each season,
combining h1 and h2 over all available post-ignition origins, then summarized
with equal season weight. They are not the frozen primary h2/0--12-week
comparison. Inner M2 selection instead used `min_nll` on week/horizon-weighted
Bernoulli cross-entropy, not trial-weighted h2 NLL or one-standard-error
selection. M0 and M1 used their own detector and peak-error objectives; see
[`ANALYSIS_DEVIATIONS_2026-09-08.md`](ANALYSIS_DEVIATIONS_2026-09-08.md).

All 11 seasonal metric rows below are retained unchanged as valid descriptive
summaries of the archived replay. The 2026-09-07 audit reproduced their NLLs
from 655 exported prediction rows within 5e-13. This does not verify corrected
results: the post-peak raw-predictor bug fix is in progress, and its effects on
correction state, tuning, and replay forecasts remain unverified.

Across the 11 completed pipeline artifacts, the mean seasonal Bernoulli NLL
was 0.338 (median 0.338; range 0.173–0.564), and the mean seasonal MAE was
0.0325 (median 0.0267; range 0.0193–0.0656). These are descriptive
season-level summaries of the PAGe replay and do not represent a statistical
test or a claim of superiority over a comparator.

Ten seasons had the usual full replay coverage, with 57–73 prediction rows
per season. Their mean NLL was 0.315 and their mean MAE was 0.0292. The
2025–26 artifact completed the same governed pipeline but contained only 17
prediction rows because the available season input was partial; it is therefore
reported separately and is not interpreted as a full-season result.

The 11-season summary above includes this partial fold; the 10-season summary
is a coverage diagnostic, not a revised season selection. Partial 2025–26
observations also entered training for the other holdouts. This new fold is
distinct from the earlier acceptance replay, but is not untouched confirmation.

| Holdout season | Predictions | NLL | MAE | h1 MAE | h2 MAE |
|---|---:|---:|---:|---:|---:|
| 2012–13 | 67 | 0.384700 | 0.045078 | 0.040682 | 0.049526 |
| 2013–14 | 63 | 0.301311 | 0.038506 | 0.035040 | 0.042041 |
| 2014–15 | 65 | 0.419605 | 0.033898 | 0.028806 | 0.039097 |
| 2016–17 | 65 | 0.397904 | 0.038078 | 0.031634 | 0.044673 |
| 2017–18 | 63 | 0.337756 | 0.019278 | 0.016462 | 0.022155 |
| 2018–19 | 65 | 0.358829 | 0.026307 | 0.023469 | 0.029218 |
| 2019–20 | 59 | 0.213888 | 0.021923 | 0.019498 | 0.024406 |
| 2022–23 | 73 | 0.173092 | 0.019562 | 0.016106 | 0.023092 |
| 2023–24 | 61 | 0.230395 | 0.022673 | 0.017822 | 0.027711 |
| 2024–25 | 57 | 0.336284 | 0.026717 | 0.024195 | 0.029337 |
| 2025–26* | 17 | 0.563552 | 0.065553 | 0.047072 | 0.085408 |

*2025–26 had partial input coverage and is not a full-season estimate.

## Ignition and horizon-specific errors

The replayed ignition weeks ranged from 15 to 23 among the 10 full-coverage
seasons. Among those seasons, the mean h1 MAE was 0.0254 and the mean h2 MAE
was 0.0331. The corresponding medians were 0.0238 and 0.0293. These values
describe forecast error on the positivity scale. These ignition weeks are
detector outputs, not a completed ignition-error comparison with reference
labels or biological ground truth. The runner supplies `2025-26 = 19L`, but
its label source/date/hash and actual fold-filtered use remain unresolved.

## Restricted paired diagnostics and intervals

Paired PAGe/calendar-GAM diagnostics on identical h2 rows with
`0 <= t_since <= 12` are pending. The audit's PAGe-only restricted rescoring
demonstrates the window mismatch; it is not a paired comparison and does not
repair candidate selection. Any paired h1 diagnostic on the same origin window
is secondary. Missing paired rows and failed seasons must be accounted for.
No superiority conclusion or inferential testing is supported or planned.

The archived export did not retain interval bounds. Available M2 bounds are
conditional fitted-mean bands, not a validated full predictive distribution;
coverage, width, and interval-score results are not established here.

## Computational behavior

The nine newly regenerated seasonal kits required 3.319–3.786 hours each on
BCC with two concurrent seven-core jobs. Training and tuning were performed
once per target season. The resulting frozen kit was reused across all weekly
origins; weekly replay updated the detector, alignment state, forecast, and
online correction state without refitting the seasonal model.

## Results still required before submission

The current artifact bundle supports the archived descriptive PAGe replay table. It
does not yet provide the prespecified calendar-GAM comparator, the full
baseline/ablation table, label-sensitivity results, or the simulation results.
Those analyses must be generated with the same season folds before making any
comparative or attribution claim. Until then, the defensible result is that the
governed PAGe workflow completed consistently across the declared holdouts,
with substantial between-season variation and reduced coverage for 2025–26.
