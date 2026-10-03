> **Status (2026-09-15): PRIOR CYCLE** — commit 95c1c9f / CSV-label seasons / truncated 2025-26; not comparable with the new cycle. See drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

# Results

## Current audited v3 evidence (2026-09-28)

This section reports current v3 implementation and prospective shadow evidence.
The prior-cycle table below is retained unchanged and is not a v3 result. The
canonical forecast release is
`5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b`, with
weekF12 as the minimum forecast origin and `production_eligible=FALSE`.

### Component-specific legacy and v2 comparisons

Available comparisons are stage-specific and use the evidence designs shown;
they do not establish a global ranking of legacy, v2, and v3.

| Comparison | Legacy | v2 | Evidence scope and caveat |
|---|---:|---:|---|
| M1 timing MAE | 1.375 weeks | 1.093 weeks | About 0.283 weeks lower for v2; 81 matched rows across 10 seasons; common ledger; M1 timing only |
| M2-A +1 MAE | 8.4087 pp | 1.7757 pp state/growth; 1.5435 pp fixed C2 | 10 seasons with identical target counts; training vintages not perfectly matched |
| M2-A +2 MAE | 9.2056 pp | 2.4124 pp state/growth; 2.1531 pp fixed C2 | Same matched-target and training-vintage caveat |
| M0 | Not available | Not available | No verified common-ledger legacy/v2 M0 performance metric |

The M1 result is from
[`common_ledger_vs_legacy_v16_strict_future_release.csv`](../artifacts/m1-v2-lowrank-posterior-v10-release-consistent/common_ledger_vs_legacy_v16_strict_future_release.csv).
The M2-A benchmark and its full target-count details are recorded in
[`m2-v2-legacy-matched-a-benchmark-2026-09-25.md`](../docs/m2-v2-legacy-matched-a-benchmark-2026-09-25.md).
These are descriptive matched historical differences, not inferential or
superiority claims. v3 does not replace all A components: M0-A, M1-A, and
M2-A are frozen/shared v2. The v3 increment is primarily its B-specific
timing/routing and governed weekF12 operation. No three-way A comparison is
presented.

### Current component evaluation

M0-A is frozen as `m0-v2-wmin12-raw3-se1-decimal-loso-v1` with `w_min=12`.
The raw-3 detector with one-SE drop tolerance retains the small weekF10-to-11
decline as stable. A direct diagnostic using predicted positivity near 1.677%
would ignite at weekF12; this is a counterfactual diagnostic, not observed
evidence. M2-A remains exact A1 state-only: governed posterior-C2 gain of about
4.04% at +2 did not clear the 5% promotion threshold.

For B, the activity/timing window is weeks 12–40; 2018–19 is a no-event timing
season and 2019–20 is excluded from B timing training and scoring. M1-B v10
preserves fitted-library behavior relative to v9 and gives chronological,
season-balanced peak-location MAE about 1.6573 weeks, early-weighted MAE 1.6580
weeks, and mean 90% coverage 0.80. The 2022–23 season is a known weak season.
M2-B v5 uses exact B1 at +1 and posterior C2 at +2 only when causal timing is
available; otherwise +2 is exact B1 fallback. Governed historical +2
season-balanced MAE was 0.514552 pp for B1 and 0.436010 pp for posterior C2
(15.26% lower); timing-active improvement was 24.91%; worst-season MAE was
1.172716 to 0.763391 pp. Lower-bound posterior saturation limits interpretation:
this supports a continuous phase/post-peak correction and does not establish
fine-grained calibrated peak timing.

At weekF12, support-only replay MAE was A+1 0.246866 pp (8 seasons), A+2
0.327263 pp (8), B+1 0.154921 pp (7), and B+2 state/fallback 0.154897 pp (7).
There were zero B timing activations at weekF12, so B+2 used exact B1. These
values describe support at the operational floor only; they are not promotion
evidence or an accuracy claim.

### 2026–27 diagnostic and prospective status

The weekF8–11 report is diagnostic and pre-issuance; the canonical release
does not issue forecasts before weekF12. The current authoritative CSV
score-to-date values are:

| Target | MAE (percentage points) | Scored targets |
|---|---:|---:|
| A +1 | 0.4121899 (~0.412) | 3 |
| A +2 | 0.5535410 (~0.554) | 2 |
| B +1 | 0.0284583 (~0.028) | 3 |
| B +2 | 0.0481438 (~0.048) | 2 |

These are diagnostic partial-season scores, not a completed prospective
evaluation. They supersede stale A+2/B+2 prose in the older end-to-end audit;
use the current machine-readable CSV. No observed weekF12+ result is available
yet. The prospective plan is to begin shadow issuance at the first eligible
weekF12+ origin, preserve the as-issued input/release provenance, and score only
after target observations become available. The release remains shadow-only.

### Package integration evidence

The stabilized PAGe 0.3.0 API provides `page_load_surveillance()` and
`aggregate_strata()` for data loading and aggregation, `page_train()` for
governed training, and `page_forecast()` for forecasting. The high-level
reporting APIs are `page_walkforward_report()` and `page_render_report()`.
Internal `v3_*` functions remain encapsulated private implementation details.
Full `R CMD build` and `R CMD check --no-manual` passed in Asgard on
`PAGe_0.3.0.tar.gz` (commit `0baf0b9`), with 0 ERRORs, 0 WARNINGs, and 1 NOTE
for standard unquoted global variables. All 7,143 unit tests across 136 test
files passed (0 failures, 0 errors, 18 skipped stale release-binding tests).
The three new vignettes rendered successfully. These software checks do not
change the shadow-only status of v3 or the distinction between retrospective
walk-forward replay and prospective deployment.

> **Evidence reconciliation note.** Values in this section come from current
> machine-readable v3 evidence and dated dispositions. They do not overwrite
> or reinterpret the prior-cycle replay that follows.

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
