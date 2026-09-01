# PAGe analysis protocol

- Protocol version: 1.1
- Status: frozen core protocol
- Freeze date: 2026-09-01
- Amendment date: 2026-09-01
- Authorized by: project lead instruction to proceed
- Applies to: Ontario influenza reconstruction and, after its data gate, Ontario RSV

This protocol fixes the comparative and statistical analysis before the Ontario
RSV data are supplied. Dataset-specific season identifiers, source metadata,
publication permissions, and the package commit used for final computation are
intentionally not invented here. They must be appended before fitting, without
changing the rules below in response to outcomes.

## 1. Scientific estimands

PAGe is evaluated as the ordered chain

`ignition detection -> partial-curve phase and peak estimation -> h1/h2 forecast`.

The manuscript must report all three stage outputs. There is one confirmatory
model comparison so that the limited number of independent seasons is not
spent on multiple headline tests.

### 1.1 Confirmatory comparison

The confirmatory estimand is the equal-season mean difference in two-week-ahead
per-trial binomial negative log-likelihood (NLL):

\[
\Delta = \frac{1}{S}\sum_{s=1}^{S}
  \left(L_{s,\mathrm{PAGe}}-L_{s,\mathrm{calendar\ GAM}}\right),
\]

where each season-specific score is

\[
L_{s,m} =
\frac{\sum_{w \in \mathcal W_s}
[-y_{s,w+2}\log(\hat p_{s,w+2,m})
-(N_{s,w+2}-y_{s,w+2})\log(1-\hat p_{s,w+2,m})]}
{\sum_{w \in \mathcal W_s}N_{s,w+2}}.
\]

Here, `y` and `N` are positive and total tests, respectively. Predicted
probabilities are clipped to `[1e-12, 1 - 1e-12]`. The binomial combinatorial
term is omitted because it is constant across models for a given target. Thus
the score is Bernoulli cross-entropy averaged over trials, equivalently the
model-dependent portion of per-trial binomial NLL. Lower is better, so a
negative `Delta` favors PAGe.

Within a season, test counts weight weekly observations. Across seasons, every
season receives equal weight. A pooled score across all trials is secondary and
must not replace the equal-season confirmatory estimand.

### 1.2 Forecast origins and common rows

- The confirmatory horizon is `h = 2`; `h = 1` is secondary.
- The evaluation window is forecast origins from the held-out season's
  prospectively detected ignition through ignition plus 12 weeks, inclusive,
  where the target at `w + h` is observed.
- Every model is scored on identical season-origin-horizon rows.
- Every prediction, transformation, update, and model state at origin `w` may
  use information available no later than `w`.
- A season with no PAGe ignition or no valid forecast is a pipeline failure. It
  must be reported and cannot be silently removed. The confirmatory analysis
  stops for a documented protocol disposition if a paired season score cannot
  be formed.

The 2025--26 Ontario influenza replay is historical confirmatory evidence that
has already been examined. It is not converted retrospectively into a new
untouched test and is reported separately from the protocol-governed replay
estimate.

### 1.3 Stage estimands

M0 ignition performance is summarized by absolute ignition-week error,
signed detection delay, miss rate, and false-alarm rate. The reference labels
must come from the versioned ignition-labeling protocol; they cannot be changed
after model results are viewed.

M1 peak performance is summarized by prospective peak-week absolute error at
each eligible origin. The principal M1 summary is the season-equal,
within-season normalized weighted MAE using
`weight = exp(-(0.1 * weeks_before_peak)^2)`. Report unweighted MAE and peak
interval coverage when available. The observed peak is the earliest week at
the maximum final weekly positivity; a prespecified smoothed-peak sensitivity
analysis will assess ties and weekly noise.

These stage outcomes are required evidence, but they are not additional
confirmatory superiority tests. They establish whether the claimed staged
outputs work and identify where the chain fails.

## 2. Validation design and information boundary

### 2.1 Outer replay

Each eligible season is held out in turn. The held-out season is absent from:

- all model fitting and hyperparameter selection;
- scaling, imputation, feature selection, templates, and prior distributions;
- manual-label vectors supplied to training functions;
- analogue libraries and calibration or bias states; and
- boundary expansion and stopping decisions.

The held-out season is then replayed week by week. Final revised observations
may define evaluation targets but may not enter origin-time features. If true
vintage snapshots cannot be reconstructed, the affected analysis is explicitly
labelled a final-data retrospective replay and backfill is addressed by
sensitivity analysis; it is not described as a live prospective evaluation.

### 2.2 Inner tuning

All non-fixed hyperparameters are selected only from the outer training
seasons using inner leave-one-season-out replay. The inner objective is the
equal-season mean `h = 2` NLL defined above. PAGe stages are tuned in dependency
order: M0, then M1 using the selected M0, then M2 using the selected M0/M1
identities. A stage cannot be frozen while a genuinely tuned axis has an
unresolved boundary winner.

The selection rule is one standard error: choose the least complex candidate
whose inner score is within one inner-season standard error of the minimum.
Deterministic ties are broken by lower complexity and then canonical
configuration ID. The same rule applies to every tunable comparator.

The historical conditional M2 LOSO results may be reported as reconstruction
context but cannot substitute for this fully nested manuscript analysis.

### 2.3 One training workflow per target season

For each target season, tuning, fitting, validation, freezing, and kit assembly
are completed once before that season's first operational forecast. This one
seasonal training workflow may contain the candidate fits and inner folds
required by Section 2.2, but it emits one frozen seasonal kit. The same kit is
then reused for every weekly origin in that season.

Weekly execution is state updating, not model retraining:

- M0 applies its frozen detector to data observed through the current week;
- M1 updates the current season's alignment, phase, peak estimate, and
  alignment uncertainty against frozen historical templates;
- M2 applies the frozen forecast model; and
- the prespecified adaptive bias state may update from newly observed residuals.

M0 parameters, M1 templates and hyperparameters, M2 coefficients, feature
ranges, and comparator parameters do not change within the season. Current
season observations cannot be added to a model-fitting dataset during weekly
replay. Training may run again only for the next season, after the current
season has been formally released under the data and holdout policy, producing
a new versioned kit identity.

Retrospective replay follows the same cadence: build one outer-fold kit for the
held-out season, then reuse it from the first through the last weekly replay
origin. Runtime reporting therefore separates one seasonal training time from
weekly state-update and forecast latency.

### 2.4 Missing observations and revisions

- No outcome is imputed for scoring.
- A missing lag may be imputed only within an outer fold using a rule fitted or
  fixed without the held-out future; a missingness indicator must accompany it.
- Duplicate season-week observations must be resolved by a documented source
  aggregation before the adapter is called.
- Revisions use origin-time vintages when reconstructible. Otherwise the final
  data are used consistently for every model and the limitation is disclosed.
- Model failures, unavailable forecasts, and excluded rows are retained in the
  canonical audit table with reason codes.

## 3. Frozen comparator set

Seven standalone models form the core comparison. No additional model may be
added because of its observed ranking.

1. **Persistence.** Use positivity observed at the forecast origin for both
   horizons. There are no tuned parameters.
2. **Seasonal naive.** At each origin and horizon, use the denominator-pooled
   historical positivity for the corresponding within-season target week from
   outer training seasons, with Jeffreys smoothing
   `(sum(y) + 0.5) / (sum(N) + 1)`.
3. **Calendar-week binomial GAM.** This is the confirmatory comparator. Fit a
   denominator-aware GAM with horizon, a cyclic within-season-week smooth,
   current logit positivity, one-week logit change, and horizon-specific smooth
   effects. It receives no M0 decision, aligned week, template, peak estimate,
   or alignment uncertainty. Candidate basis dimensions are `k_week = 6, 8,
   10` and `k_signal = 4, 6, 8`; selection follows Section 2.2.
4. **Lagged penalized binomial regression.** Use within-season sine/cosine
   terms, horizon, current and 1--3-week lagged logit positivity, first
   differences, and missingness indicators. Standardization is learned inside
   each outer fold. Elastic-net `alpha` is selected from `0, 0.5, 1`; lambda is
   selected by inner season replay using the one-standard-error rule.
5. **Historical-analogue continuation.** Compare the current partial curve
   with outer-training curves on the logit scale without time warping. Select
   the nearest `k = 1, 3, 5` seasons over trailing windows of `4, 6, 8` observed
   weeks, and predict the target as their denominator-pooled continuation.
   Distance ties are resolved by season identifier.
6. **Regularized gradient-boosted tree.** Fit a binomial-logistic boosted tree
   to the same generic features as model 4, using fractional outcome `y/N` and
   weight `N`. The frozen grid is `max_depth = 1, 2, 3`, `eta = 0.03, 0.10`,
   `min_child_weight = 1, 5`, `nrounds = 50, 150, 300`, `subsample = 0.8`,
   `colsample_bytree = 1`, `lambda = 1, 10`, and `alpha = 0`. Seed control and
   selection follow Sections 2.2 and 5.
7. **Full PAGe.** Run the governed M0 -> M1 -> M2 lifecycle with a frozen GAM,
   alignment-uncertainty covariates, and the canonical adaptive online bias
   correction. All stage and kit identities must be recorded.

The calendar GAM, elastic net, and full PAGe provide statistical-model
comparisons; the boosted tree supplies the machine-learning comparison; and
the analogue model directly tests the closest target-compatible mathematical
curve-continuation idea. The literature review covers SIR/SIRS filtering as the
principal mechanistic alternative. It is not a core numerical comparator
because a fair positivity analysis requires an additional latent-incidence to
testing observation model that the available data do not identify. A SIR/SIRS
model may be studied in simulations, but cannot be inserted into the empirical
ranking by a post-results amendment.

## 4. Frozen PAGe ablations and sensitivities

Structural ablations are refitted and retuned inside every outer fold.

1. **No ignition gate:** replace M0's learned ignition with the fixed analysis
   season start as the downstream anchor; retain M1 and M2.
2. **No M1 alignment:** retain M0, remove aligned week, template, peak, and
   spread inputs, and use within-season and time-since-ignition terms in M2.
3. **No alignment uncertainty:** retain alignment point estimates but remove
   `logit_spread` and all other alignment-uncertainty inputs.
4. **No adaptive bias correction:** set the online correction to zero and
   disable adaptive transitions and post-peak overrides.

Required label sensitivities are: shift all admissible retrospective ignition
labels by `-1` week, shift them by `+1` week, and use fold-specific M0-generated
labels for all downstream training without manual overrides. The historical
2015--16 exclusion is not allowed solely because it is an ignition outlier; it
is included in the principal analysis when its data pass the generic quality
rules and may also be shown in a labelled historical-exclusion sensitivity.

## 5. Uncertainty, precision, and interpretation

The independent resampling unit is season. For the primary paired differences
`Delta_s`:

- report the mean, median, standard deviation, and every season-specific value;
- construct a two-sided 95% percentile interval from 10,000 paired
  season-cluster bootstrap resamples using seed `20260901`;
- report a paired sign-flip randomization p-value, enumerating all assignments
  when `S <= 20` and using 100,000 deterministic-seed assignments otherwise;
  and
- report leave-one-season-out influence on the mean contrast.

The interpretation threshold is zero NLL difference. Evidence favors PAGe only
when the point estimate is negative and the upper 95% season-bootstrap limit is
below zero. An interval containing zero is inconclusive, regardless of the
pooled weekly score. A wholly positive interval indicates harm. Magnitude is
reported in NLL units and relative to the comparator; no unsupported clinical
minimum-important difference is invented.

Precision is limited by the number of seasons. Before opening model-result
tables, instantiate the following feasibility calculation with the locked
number of paired seasons and an outcome-blind planning standard deviation. For
`S = 10`, a conventional paired-mean 95% interval has approximate half-width
`0.715 * SD(Delta_s)`, and 80% power at two-sided alpha 0.05 requires a mean
difference of approximately `0.996 * SD(Delta_s)`. These standardized values
are the prespecified precision warning; the bootstrap interval remains the
reported uncertainty analysis.

Secondary contrasts receive compatible season-bootstrap intervals but are
descriptive. No isolated secondary p-value supports a superiority claim.

## 6. Secondary outcomes and strata

- `h = 1` and the combined `h = 1, 2` forecast scores;
- trial-weighted and week-weighted Brier score and RMSE of positivity;
- trial-weighted and week-weighted MAE;
- calibration intercept and slope when estimable;
- early (`t_since = 0:3`) and established (`t_since = 4:12`) strata;
- pre-peak and post-peak evaluation strata, defined from final observations
  only for stratified evaluation, never as forecast inputs;
- worst season, worst horizon, and worst phase;
- forecast availability, model failures, and stage and total runtime; and
- interval coverage, width, and interval score when a model emits intervals.

Influenza and RSV results use identical definitions where the data support
them, but are reported separately. Their NLL values are not pooled into one
headline estimate.

## 7. Ontario RSV data gate

Ontario RSV may enter model fitting only if all criteria below pass:

- positive and total tests, or positive and negative tests, are available for
  every scored week;
- stable weekly date/MMWR and season identifiers can be constructed;
- at least eight complete eligible seasons are available for nested replay,
  with ten preferred; six or seven seasons permit only explicitly exploratory
  estimation, not the planned superiority claim;
- each included season has at least 80% of expected weekly observations and no
  unexplained gap longer than two consecutive weeks in the ignition-to-peak
  analysis window;
- duplicates, suppression, impossible counts, zero denominators, 52/53-week
  transitions, and revisions can be audited;
- the most recent complete eligible season can be reserved before fitting; and
- access classification, publication permission, and any ethics or privacy
  requirements are documented.

Ontario RSV was selected because holding jurisdiction and surveillance context
approximately constant while changing pathogen provides a focused test of
workflow portability after pathogen-specific retraining. It does not test
direct influenza-to-RSV parameter transport.

## 8. Reproducibility and canonical artifacts

All final outputs live under one immutable
`manuscript/results/<analysis-id>/` directory and share one canonical
prediction table. At minimum each row records application, pathogen, season,
outer fold, origin week, target week, horizon, evaluation phase, `y`, `N`,
observed positivity, prediction and interval, model/configuration ID, M0/M1/M2
artifact identities where applicable, data-vintage status, runtime, warning,
and failure code.

The manifest records protocol checksum, data checksum or controlled-data
locator, package version, Git commit, dependency lock, R and OS versions,
random seeds, stage identities, file checksums, and the code used for every
table and figure. Private surveillance rows remain outside the public
repository.

## 9. Amendment rule

The frozen core may be amended before outcome-bearing model results are opened
only to resolve an implementation impossibility, data-contract incompatibility,
or factual error. Every amendment requires a new version, date, rationale,
affected estimand, and declaration of which results were already visible.
After results are opened, changes are sensitivity analyses or a new development
cycle; they do not replace the registered primary analysis.

### Amendment 1.1

The project lead clarified on 2026-09-01 that training occurs only once per
season. Section 2.3 now distinguishes the single seasonal training workflow
from weekly frozen-kit state updates. This clarification changes no estimand,
comparator, metric, season weighting, or result already viewed.
