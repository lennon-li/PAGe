# Methods draft

Last updated: 2026-09-11

This document is the canonical manuscript-facing Methods draft. It converts the
frozen decisions in [`ANALYSIS_PROTOCOL.md`](ANALYSIS_PROTOCOL.md) and the
implemented PAGe contracts into journal prose. Result-dependent values belong in
[`REPORTING_TEMPLATES.md`](REPORTING_TEMPLATES.md) and must be populated from
the immutable analysis manifest, not typed from memory.

The executed influenza replay differs from the frozen primary analysis.
This draft distinguishes executed methods from pending protocol-defined
comparisons; see the dated
[deviations record](ANALYSIS_DEVIATIONS_2026-09-08.md).

## Study design and objective

We evaluated PAGe (Phase-Aligned Gated Epidemic forecasting), a staged workflow
for weekly respiratory-virus surveillance. The workflow targets three linked
but separately evaluated outputs: epidemic ignition, the phase and peak of the
partially observed seasonal curve, and one- and two-week-ahead positivity
forecasts. PAGe was designed for prospective deployment and evaluated here by
exchangeable-season outer leave-one-season-out (LOSO) evaluation with
within-season walk-forward replay. Later calendar seasons intentionally trained
earlier holdouts. This evaluates transfer across the declared season set, not
historical availability of all training data at each calendar date.

The frozen primary forecast estimand is the observed two-week-ahead probabilistic
accuracy of the assembled PAGe workflow compared with a prespecified
calendar-week binomial generalized additive model (GAM). The comparison is
descriptive and remains pending. We did not perform hypothesis tests, calculate p-values, or make a
statistical-significance claim. Stage-level results, horizon one, phase
strata, component ablations, label sensitivities, calibration, and runtime
were secondary reporting targets.

## Surveillance data and data contract

For pathogen (v), season (s), and within-season week (t), the input data
contained (y_{vst}) positive tests and (N_{vst}) total tests. Weekly
positivity was defined as

\[
p_{vst}=y_{vst}/N_{vst},
\]

when (N_{vst}>0); weeks with zero total tests had missing positivity and were
not scored. The canonical PAGe data frame contained `season`, `weekF`, `y`,
`N`, `neg`, and `p`, where `neg = N - y`. The adapter also preserved unmapped
source metadata, such as dates, jurisdiction, source identifiers, and data
vintage.

Source-specific weekly data were converted through `prepare_page_data()` by
explicitly naming the positive-count, total-count or negative-count, season,
week, and optional season-start-year columns. The adapter did not fetch or
aggregate observations. Inputs were required to contain exactly one row per
season and week after any source-authorized aggregation. For calendar/MMWR
weeks, `weekF` was computed from the declared season origin (`start_week = 27`
by default) and the number of weeks in the season, allowing 52- and 53-week
seasons. Counts were required to be finite, non-negative whole numbers, with
positive counts no greater than total counts. Duplicate keys, inconsistent
redundant counts, impossible positivity values, and malformed season
identifiers caused validation failure.

### Temporal resolution and legacy implementation

The evaluated PAGe pipeline used one observation per season-week. The
calendar-GAM comparator used for the current comparison was constructed from
the same weekly surveillance counts, with one- and two-week-ahead targets.
The archived legacy source inspected for this analysis likewise selected
weekly positive and total counts and modelled them on a within-season week
coordinate. A daily date-to-week calendar was present in the historical
workspace, but it did not contain daily positive or testing counts and was not
used to fit the forecasting GAM. Therefore, a separate external daily legacy
fit, if intended, must be treated as a different comparator and verified from
its source before it is described as daily.

Daily observations could provide more information about within-week onset,
growth, reporting cycles, and peak timing, but they would not be directly
comparable to the current weekly estimand. A daily model would need to respect
the observation-availability cutoff, model serial and weekday dependence, and
aggregate daily predictions to the weekly target using target test volumes
before comparison. We therefore retained the weekly model as the baseline and
reserved finer-resolution development for a new, leakage-safe validation cycle.

The primary application was Ontario influenza using the season universe fixed
in the versioned Ontario season declaration. Ontario RSV was a conditional
second application. It was evaluated only after an independent source audit
confirmed weekly denominators, season support, missingness, revisions, access
classification, and permission to report the resulting evidence. Influenza
and RSV were not pooled into one headline estimate. A pathogen-specific model
was retrained for each application; no influenza-fitted parameters were
transported to RSV.

## Forecast targets and information boundary

The forecast origin was week (t), and the target for horizon (h) was the
positive count and denominator at week (t+h), with (h\in\{1,2\}). At each
origin, all predictors, transformations, alignment states, and correction
states were constructed from information available no later than week (t).
Final revised observations could define retrospective scoring targets, but they
could not enter origin-time predictors. When origin-time data vintages could
not be reconstructed, the analysis was labelled a final-data retrospective
replay rather than actual prospective deployment.

Ignition was defined by the versioned ignition-label protocol. For a labelled
season, the retrospective reference was the earliest within-season week with
`phase == 1`; this is an operational reference label, not an independently
validated biological ground truth. Peak week was the earliest week attaining
the maximum final observed weekly positivity. A prespecified smoothed-peak
sensitivity remains pending. The runner uses the frozen operational reference
`2025-26 = 19L`; when that season is held out, the label is excluded from
training and joined only after replay for scoring.

## PAGe workflow

PAGe was implemented as the ordered chain (M0\rightarrow M1\rightarrow M2).
The three stages were governed by explicit fit, validation, freeze, identity,
and assembly contracts. A downstream stage could not be frozen or assembled
with a missing or mismatched upstream identity.

> **Status (2026-09-15): PRIOR CYCLE** — commit 95c1c9f / CSV-label seasons / truncated 2025-26; not comparable with the new cycle. See drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

### M0: prospective ignition detection

M0 detected the transition into the epidemic phase. Its detector combined five
signals: a population-level ignition-classifier score, a rolling positivity
sum, a smoothed positivity level, cumulative denominator-weighted prevalence,
and a consecutive-increase signal. The detector evaluated an eligible
within-season window and declared ignition at the earliest week for which at
least `N_req` of the five gates were satisfied. The detector's threshold and
window parameters were selected only within the declared training seasons.

The classifier was trained on season-specific windows around the reference
ignition labels. Its population-level score excluded season-specific effects
when transferred to a target season. During replay, M0 was applied repeatedly
to the as-of data through the current week. Once the detector locked an
ignition week, that value was used by downstream weekly processing unless a
prespecified, documented override was part of the analysis. A missed or
unavailable ignition was retained as a pipeline failure; it was not silently
removed from the evaluation.

### M1: partial-curve phase and peak alignment

M1 represented the observed partial curve in an epidemic-phase coordinate. A
reference curve was estimated from eligible training seasons after M0-derived
alignment and expressed on the logit scale. For each candidate historical
template (g_j), the observed curve was aligned using a shift τ, optional
scale parameters (a,b), and a dilation δ:

\[
u_{stj}=\frac{t_{st}-\tau_{sj}}{1+\delta_{sj}},
\qquad
\operatorname{logit}(p_{st})\approx a_{sj}+b_{sj}g_j(u_{stj}).
\]

Alignment was estimated using a denominator-aware binomial objective with
prespecified rising-limb, peak, and post-peak weighting. A ridge penalty was
used for dilation where specified by the alignment contract. The resulting
templates were combined with a softmax ensemble based on alignment loss and a
recent growth-rate similarity term. The ensemble produced a phase-aligned
positivity trajectory and a peak estimate. The effective aligned forecast
feature was the ensemble prediction at the future target coordinate.

M1 also produced `logit_spread`, the weighted standard deviation of template
predictions on the logit scale. This quantity represented disagreement among
alignment templates; it was an uncertainty covariate for M2 and was not
interpreted as the complete predictive interval. All M1 states were recomputed
from the partial curve available at each weekly origin using the frozen
training templates and hyperparameters.

> **Status (2026-09-15): PRIOR CYCLE** — commit 95c1c9f / CSV-label seasons / truncated 2025-26; not comparable with the new cycle. See drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

### M2: probabilistic positivity forecasting

M2 modelled the future positive and negative counts with a binomial GAM. The
training response for horizon (h) was

\[
(y_{s,t+h}, N_{s,t+h}-y_{s,t+h}),
\]

stacked across horizons and eligible seasons. The model included a horizon
factor and a season random effect, with specification-dependent terms for the
aligned template feature, aligned week, the observed state, residual amplitude,
testing volume, rate of change, and alignment spread. In the general package
form, the smooth terms were selected by the frozen stage specification; terms
with basis dimension zero were omitted. The canonical formula can therefore be
written schematically as

\[
\begin{aligned}
\operatorname{logit}(p_{s,t+h}) ={}& \alpha_h+b_s
 + f_{h}(\operatorname{logit} f^{\mathrm{eff}}_{s,t+h})
 + q_h(\operatorname{newWeek}_{s,t+h})\\
 &+ e_h(z_{s,t})+r_h(z_{s,t}-\operatorname{logit}f^{\mathrm{eff}}_{s,t+h})
 + v_h(\log N_{s,t})\\
 &+ d_h(\Delta z_{s,t})+u_h(\operatorname{logit\_spread}_{s,t}).
\end{aligned}
\]

Here (f^{\mathrm{eff}}) was the M1-aligned template prediction after the
declared shift and ignition ramp, (z_{s,t}) was a recursively updated
exponentially weighted mean of observed logit positivity, and Δz was its
one-week change. The ramp weight was zero at ignition and increased linearly to
one over the specified ramp length. Feature ranges learned in the training
fold were reused for target-season prediction and prevented uncontrolled
extrapolation.

The model was fitted with `mgcv::bam()` using a binomial likelihood and the
method specified by the frozen fitting contract. For a new target season, the
season random effect and other season-dependent terms unavailable at forecast
time were excluded. The GAM was fitted once as part of the seasonal kit and
was not refitted at each weekly origin.

> **Status (2026-09-15): SUPERSEDED by D-8** — see drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

### Online correction and post-peak handling

The residual definition below is the intended algorithm, not a verified
account of the archived correction state. The audit found that post-peak M1
substitution preceded reconstruction of the stored raw GAM predictor;
probability caps could also prevent exact reconstruction. The parent's
raw-predictor fix is in progress as of 2026-09-08. Corrected forecasts, tuning
scores, and replay results have not been verified in this manuscript.

The frozen GAM forecast was optionally adjusted on the logit scale using an
online level-and-trend state. When an earlier forecast became observable, its
raw residual was computed as observed logit positivity minus the uncorrected
GAM linear predictor. The correction state was updated recursively using the
canonical `bias_alpha` and `bias_beta` values stored in the kit. After the
third consecutive same-sign residual, the prespecified higher level-update
rate was used. The online season effect was estimated from post-ignition
observations with shrinkage toward zero. These updates used only observations
available by the current origin.

After the aligned M1 trajectory indicated that the peak had passed, the
canonical runtime action substituted the M1 trajectory for the M2 point and
interval forecast while continuing to update the correction state as defined
by the implementation. The frozen no-adaptive-bias ablation also disables
post-peak overrides; its results remain pending.

Before substitution, M2 bounds were constructed from
`eta +/- 1.96 * se.fit` and transformed to the probability scale. These are
conditional fitted-mean bands, not a full predictive distribution for future
observed positivity. They do not fully propagate observation variation,
upstream estimation, selected parameters, online-correction uncertainty, or
surveillance revisions. Using `logit_spread` as a covariate does not establish
predictive coverage. The archived replay export did not retain bounds, so
interval performance is not established by the current results.

## Seasonal training cadence

For each target season, the complete training workflow was run once. The
workflow selected training seasons, tuned M0, validated and froze M0, estimated
and tuned M1 using the matching frozen M0, and tuned, fitted, and froze M2
using the matching M0/M1 identity chain. The result was one immutable seasonal
kit containing stage specifications, fitted objects, feature ranges, source
metadata, and provenance identities.

The same kit was reused for all weekly origins in the target season. Weekly
M0 detection, M1 alignment, M2 prediction, online residual correction, and
peak-state transitions were state updates rather than retraining. A new
seasonal kit could be trained only for a subsequent declared season after the
current season was closed under the data and holdout policy.

## Validation and replay design

We used a three-level nested seasonal walk-forward design. The unit of
separation was the influenza season, and the information boundary was also
enforced within each season: a forecast made at origin week (t) could use only
observations available through week (t). The three levels had distinct roles.

### Level 1: model fitting on nine seasons

Within a given outer fold, one of the 10 outer-training seasons was designated
as the inner holdout. A candidate stage specification was fitted using the
remaining nine seasons and replayed week by week on that inner-held-out season.
This was repeated for every candidate configuration. For M0, M1, and M2, model
construction followed the pipeline order, and any upstream object used by a
downstream stage was built without observations from the season currently
being replayed except where the conditional downstream-tuning limitation below
applied.

This level answered the local fitting question: **when a candidate is learned
from nine historical seasons, how well does it transfer to the tenth season
without using that season's future observations?** It produced the
season-specific walk-forward losses needed for tuning and revealed candidate
failures, unstable fits, and winning hyperparameters at a search-grid boundary.
The package implemented these candidate replays within `tune_m0()`,
`tune_m1()`, and `tune_m2()`.

### Level 2: hyperparameter selection across 10 inner holdouts

Each of the 10 outer-training seasons served once as the inner holdout, giving
10 inner walk-forward replays, each based on nine fitting seasons. For each
candidate, we first calculated its phase-weighted score within each inner
season and then averaged the 10 season-specific scores with equal weight. These
scores were used to select stage hyperparameters, expand a grid when a non-null
winning value lay on a searchable boundary, and apply the prespecified
minimum-gain rule comparing M2 with M1. If M2 did not clear that rule, the
selected forecasting procedure reverted to the exact M1 baseline. After all
choices were fixed, the selected M0, M1, and M2 procedure was fitted to all 10
outer-training seasons to create one frozen kit for the outer holdout.

This level answered the model-selection question: **which configuration should
be deployed to the outer-held-out season, and is the estimated gain from M2
large and consistent enough to justify using it instead of M1?** No score from
the outer-held-out season entered these choices. The package function
`train_outer_fold()` implemented this complete inner-tuning and kit-building
level, including resumable checkpoints and round-specific artifacts.

### Level 3: evaluation across 11 outer holdouts

> **Status (2026-09-15): PRIOR CYCLE** — commit 95c1c9f / CSV-label seasons / truncated 2025-26; not comparable with the new cycle. See drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

Each of the 11 eligible seasons was held out in turn. Within an outer fold, all
model fitting, hyperparameter selection, scaling, template construction,
imputation rules, labels supplied to training, calibration states, boundary
decisions, and the M2-versus-M1 adoption decision used only the other 10
seasons. The resulting frozen kit was then replayed through the outer-held-out
season week by week. The held-out season was replayed over its full available
post-ignition support, combining h1 and h2 rather than restricting origins to
ignition through +12. The partial 2025--26 season also contributed available
observations as a training member in the other folds; equal membership does not
imply equal observation coverage.

> **Status (2026-09-15): PRIOR CYCLE** — commit 95c1c9f / CSV-label seasons / truncated 2025-26; not comparable with the new cycle. See drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

This level answered the generalization question: **how does the complete
training, tuning, boundary-expansion, and M2-adoption procedure perform when
transferred to an unseen season?** The 11 outer replays yielded paired
season-specific metrics for M1, new M2, and the archived old M2 where compatible
predictions were available. Their equal-season aggregate quantified average
gain, the frequency and magnitude of improvement or harm, horizon- and
phase-specific performance, and whether the minimum-gain fallback protected
against harmful M2 deployments. The 11 fitted kits were validation artifacts,
not an ensemble for deployment. `run_outer_fold()` performed one complete
outer replay, and `nested_season_evaluation()` rotated that call across the 11
seasons and formed the equal-season aggregate. After the analysis procedure was
fixed, `fit_final_pipeline()` fitted one final kit using all 11 seasons for
deployment to 2026--27; that incoming season would provide the subsequent
prospective evaluation.

> **Status (2026-09-15): PRIOR CYCLE** — commit 95c1c9f / CSV-label seasons / truncated 2025-26; not comparable with the new cycle. See drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

Executed selection was stage-specific. M0 used its detector-error objective,
with a one-week-early tolerance and lexicographic ranking of large errors,
large late errors, worst adjusted error, misses, and penalized score. M1 used
weighted peak-week MAE (`mae_weibull`), with
`select_m1_candidate(min_gain = 0.05, prefer_simpler = TRUE)` preferring the
smallest boundary-admissible `k_ref` within 0.05 weeks of the best score.
M2 used `select_m2_candidate(method = "min_nll")`. Its inner Bernoulli
cross-entropy weighted weekly/horizon rows equally across both horizons within
each season, then averaged season scores equally. It was not trial-weighted
h2-only selection and did not use the one-standard-error rule.

> **Status (2026-09-15): SUPERSEDED by D-2** — see drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

For the expanded M1--M2 comparison, we used a prespecified phase-weighted
weekly score for both inner candidate selection and outer-season replay. The
evaluation time for a forecast was the target week relative to detected
ignition, (t_{mathrm{target}}=u+h), where (u) was the forecast origin and
(h) was the horizon. Targets from ignition through the operational
ignition-to-peak window (weeks 0--12) received weight 2; later targets received
weight 1. Thus, the period in which the forecast is used to anticipate the
approaching seasonal peak contributed at least twice as much as the later
post-peak period. Within each season, the weighted weekly score was normalized
by the sum of its week weights, and seasonal scores were then averaged equally
across the held-out seasons. The same rule was applied when comparing M1, the
new M2 specification, and the archived old-M2 predictions. A secondary
sensitivity analysis multiplied these phase weights by the number of target
tests; test count was therefore not part of the primary weighting rule.

The package exposed exclusions, candidate grids, phase weights and phase break,
gain thresholds, uncertainty and degradation limits, boundary expansion
controls, minimum training-season count, and computational controls as named
arguments with documented defaults. Each executed value was stored with the
fold protocol and bound to its resume identity, so an artifact could not be
silently reused under a changed analysis policy.

Internal M2 tuning rebuilt inner reference fits with upstream M0/M1
hyperparameters fixed at choices selected on the outer training set. Its scores
are conditional tuning evidence, not independent end-to-end nested validation
with upstream hyperparameters reselected inside every inner fold. This
limitation does not itself imply global outer-holdout leakage: the outer
holdout remains excluded from training and selection under the contracts.
The previously examined 2025--26 season is not untouched confirmation.

The earlier frozen primary analysis specified h2, origins 0--12 after detected
ignition, trial-weighted within-season NLL, equal-season aggregation, and
one-standard-error selection. Those settings are retained as a historical
reference; the expanded M1--M2 comparison uses the phase-weighted protocol
above. Every genuinely tuned axis was checked for a boundary winner by
expanding one adjacent valid step or recording a meaningful hard or null
constraint before the stage was frozen.

## Comparators and ablations

The prespecified core comparison contained persistence, a denominator-pooled
seasonal-naive forecast, a calendar-week binomial GAM, a lagged penalized
binomial regression, historical-analogue continuation, a regularized
gradient-boosted tree, and full PAGe. The calendar-week GAM was the primary
comparator and received no M0 gate, aligned week, template, peak estimate, or
alignment-spread input. The analogue model operated on the logit scale without
time warping. Mechanistic SIR/SIRS filtering was reviewed as a mathematical
alternative and reserved for simulation because the available positivity data
do not identify the required latent-incidence-to-testing observation model for
a fair empirical comparison.

Four structural ablations were prespecified: no ignition gate, no M1
alignment, no alignment uncertainty, and no adaptive bias correction. The
full-PAGe versus no-M1 comparison was the descriptive attribution diagnostic
for alignment; it did not replace the primary full-workflow comparison. Three
label sensitivities shifted admissible ignition labels by one week earlier, one
week later, or replaced manual downstream labels with fold-specific M0 labels.

> **Status (2026-09-15): PRIOR CYCLE** — commit 95c1c9f / CSV-label seasons / truncated 2025-26; not comparable with the new cycle. See drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

## Outcomes and descriptive scoring

For model (m) and season (s), the expanded comparison score was the
phase-weighted weekly Bernoulli cross-entropy. Let
(q_{s,t}=y_{s,t+h}/N_{s,t+h}) denote observed positivity and let
(w_{s,t}) equal 2 for target weeks 0--12 after detected ignition and 1 for
later target weeks. Then

\[
L_{s,m}=\frac{\sum_{t\in\mathcal W_s}w_{s,t}\left[-q_{s,t}\log(\hat p_{s,t+h,m})
-(1-q_{s,t})\log(1-\hat p_{s,t+h,m})\right]}
{\sum_{t\in\mathcal W_s}w_{s,t}}.
\]

Predictions were clipped to `[1e-12, 1 - 1e-12]`. This is Bernoulli
cross-entropy averaged over forecast weeks and is the model-dependent portion
of the binomial NLL. For the expanded comparison, each week received phase
weight 2 when its target was in weeks 0--12 after detected ignition and weight
1 thereafter. The per-season score was the weighted mean over available
forecast weeks, and the 11 seasonal values were retained before equal-season
aggregation. The test-count-weighted score was reported only as a sensitivity
analysis, formed by multiplying the phase weight by the number of target tests.
The primary contrast is

\[
\Delta=\frac{1}{S}\sum_s
\left(L_{s,\mathrm{PAGe}}-L_{s,\mathrm{calendar\ GAM}}\right).
\]

Negative values would favour PAGe on a paired replay. The pending comparison
will report every
season-specific contrast, equal-season mean and median, standard deviation,
interquartile range, minimum, maximum, and leave-one-season-out means. These
are descriptions of observed heterogeneity, not inferential uncertainty.

Planned secondary forecast measures are horizon-specific and include Brier score,
positivity RMSE, MAE, calibration intercept and slope when estimable, forecast
availability, and interval coverage, width, and interval score when intervals
are available with their estimand labelled. The implementation's `brier` field
is squared error of aggregate positivity, not individual Bernoulli Brier score.
Secondary strata are early (`t_since = 0--3`) versus established
(`4--12`) post-ignition, and pre-peak versus post-peak. Final-data peak labels
were used only to define evaluation strata, never as forecast inputs.

Pending outer-holdout stage summaries will report M0 absolute and signed
ignition-week error, miss rate, and
false-alarm or detection-delay measures supported by the detector audit. M1 will be
summarized by season-equal, within-season-normalized weighted peak-week MAE,
with weights \(\exp[-(0.1d)^2]\), where (d) was weeks before the observed
peak. Unweighted MAE and peak-interval coverage were secondary.

A season with no valid PAGe ignition or no valid paired forecast was retained as
a pipeline failure with a reason code. It could not be silently removed. The
historical 2025--26 acceptance replay was reported separately because it has a
different artifact lineage and was not used as evidence for the new governed
replay aggregate.

## Missing observations, revisions, and privacy

No outcome was imputed for scoring. Any feature-state treatment for a missing
lag was fixed or learned within the outer training fold and was accompanied by
an audit flag. Duplicate season-week observations were resolved before the
adapter using a documented source aggregation. When reconstructible, analyses
used origin-time data vintages; otherwise a common final-data snapshot was used
and the retrospective limitation was disclosed. Missing rows, unavailable
forecasts, warnings, and failures remained in the canonical audit table.

Private surveillance observations were not committed to the public repository.
Public replication materials consisted of the PAGe package, synthetic data,
simulation code, analysis code, and disclosure-safe aggregate outputs. Any
Ontario data release or aggregate display remained subject to the data
custodian's authorization, access terms, and applicable ethics determination.

## Software and reproducibility

The analysis was implemented in R using PAGe. The required final
analysis manifest must record the package version, Git commit, dependency lock,
R and operating-system versions, random seeds, source/data-vintage metadata,
protocol checksum, stage and kit identities, file checksums, runtime, and code
used to create every table and figure. Inspected run manifests record a shared
commit and input checksum but nonempty working-tree status. Executed
script/package hashes, dependency lock, session, seed, and protocol-hash
provenance remain incomplete. A shared commit alone does not identify the
complete executed workflow. Final tables and figures must be generated from
one canonical prediction table under a single analysis ID.
The reporting schemas and required fields are specified in
[`REPORTING_TEMPLATES.md`](REPORTING_TEMPLATES.md).
