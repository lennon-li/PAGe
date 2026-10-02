# PAGe M1/M2 Redesign Plan — Reconciled 2026-09-22

## Status

This is the reconciled preimplementation plan for the M1/M2 redesign.

It incorporates:

- the original September 21 first-principles redesign plan;
- the independent Claude Opus/high architecture audit;
- the independent Liz/Astra architecture audit.

The audits were strongly convergent. Their principal corrections are incorporated here as design contracts rather than optional suggestions.

This plan intentionally treats legacy M1-v1 as a frozen comparator. It is not the architecture to incrementally patch.

**Amendment — peak truth (2026-09-22):** expert annotation is now ignition-only. Continuous retrospective peak truth is derived by a separate frozen GAM measurement procedure over the completed season; see `docs/peak-truth-decision-2026-09-22.md`. Any earlier language in this document asking experts to provide decimal peak labels is superseded by that decision.

Development target:

- branch: `agent/m1-v2-from-first-principles`
- worktree: `PAGe-m1-v2`
- original base commit: `fd6a4e59437936550220d8c048046c8a361f9778`

Before implementation, repair and verify the worktree Git metadata. The current copied worktree has been observed to contain a broken `.git` pointer in some sandbox mounts. No governed implementation should proceed until branch identity and cleanliness can be verified locally.

The dirty legacy checkout must remain untouched. The sealed M1-v1 release must remain immutable.

---

# 1. Product objective

From an epidemiologist's perspective, PAGe should answer only the real-time questions that matter.

After weekF (week 8):

1. Has the seasonal epidemic started?

Once ignition is causally detected, at every weekly origin:

2. When will the epidemic peak occur?
3. What will the observed percentage be at `t + 1`?
4. What will the observed percentage be at `t + 2`?

The M0/M1/M2 decomposition is internal architecture, not the user-facing product.

Primary operational window:

- ignition detection through peak;
- peak + 1 week;
- peak + 2 weeks.

Late post-peak percentage forecasting is secondary. Once the peak has been confirmed as reached/passed, M1 should stop emitting a user-facing future peak forecast. M1 may continue maintaining internal state if M2 benefits from it.

---

# 2. Runtime dependency and stage responsibilities

The stages are active in the same episode but are not independent at a given origin.

The runtime dependency is:

`observations(as_of t) -> M0 state -> M1 posterior/passage state -> M1 features(t,h) -> M2 forecast(t+h)`

for `h in {1,2}`.

## 2.1 M0 — ignition detection

Purpose:

- determine causally whether the seasonal epidemic has started;
- activate M1/M2 forecasting;
- provide the runtime landmark from which the initial peak-time prior is conditioned.

Keep distinct:

- `I*`: expert decimal ignition truth;
- `A`: actual causal M0 detection origin;
- `T*`: expert decimal peak truth.

M1/M2 begin operational forecasting at `A`, not at `I*`.

Expert ignition remains scientifically useful for evaluating M0 and describing epidemic geometry, but it is not a runtime feature in a held-out season.

Missed, delayed, early, or post-peak M0 detection must remain visible in end-to-end evaluation. They must not silently remove hard origins from scoring.

## 2.2 M1 — peak timing only

Purpose:

- infer continuous peak time `T*`;
- quantify uncertainty;
- update sequentially as new weekly observations arrive;
- determine whether the primary peak has been reached/passed;
- stop public future-peak output after confirmation;
- optionally maintain internal phase/shape state for M2 after confirmation.

M1 is not judged on numeric t+1/t+2 percentage accuracy. It may generate common-curve/phase features for M2, but official peak timing remains M1's responsibility.

## 2.3 M2 — numeric forecasting only

Purpose:

Forecast the observed epidemic percentage at exactly:

- `t + 1`;
- `t + 2`.

M2 may use:

- all causally available observations;
- current M0 state;
- cross-fitted M1 peak-time summaries;
- cross-fitted common-curve/phase features;
- ignition-relative features based on the runtime detection clock;
- calendar information;
- other causally available covariates.

M2 must not use oracle peak or ignition truth for the held-out season.

---

# 3. Time coordinate and expert truth contract

This contract must be frozen before annotation tooling is implemented.

## 3.1 Canonical continuous time

Define one authoritative continuous season-time coordinate.

Requirements:

- specify exactly what integer week `w` represents;
- specify how decimal values such as `27.2` map to the weekly aggregation interval;
- specify whether reported weekly observations refer to interval start, midpoint, or release/origin time;
- explicitly map season time to epidemiological calendar identity/date;
- handle 52/53-week years and season rollover deterministically.

The new decimal labels must not pass through legacy integer timing normalization.

The repository currently contains legacy timing conventions that may not be mutually compatible. The redesign must choose one canonical convention and provide explicit adapters where legacy comparison requires them.

## 3.2 Expert annotation targets

For each of all 11 historical seasons, record at minimum:

- `season`;
- `ignition_week_decimal`;
- `peak_week_decimal`;
- optional `ignition_interval_low/high`;
- optional `peak_interval_low/high`;
- ambiguity/status flag;
- annotator;
- annotation_version;
- timestamp;
- data snapshot/hash;
- positivity definition/version;
- optional comment.

The point label is an expert reference for a latent within-week event inferred from weekly aggregates. It must not be described as directly observed biological sub-week truth.

## 3.3 Primary peak definition

Before labeling, define what counts as the operational primary peak in:

- a single sharp peak;
- a plateau;
- two nearly equal adjacent maxima;
- a later secondary wave;
- a season with no clearly labelable primary peak.

Allow ambiguous/unlabelable/censored cases. Do not force a falsely precise unique decimal peak when the epidemiological shape does not support one.

## 3.4 Annotation process

The initial tooling should be deliberately simple.

For 11 seasons / 22 primary event labels, prefer:

- static or Plotly review plots;
- explicit numeric entry;
- visible decimal markers;
- explicit confirmation;
- deterministic versioned storage.

Click/drag placement may be a convenience, but exact numeric values are authoritative.

Do not overengineer a custom annotation application before the labeling contract is settled.

To quantify label repeatability, perform at least one repeat labeling pass separated in time. If multiple experts are available later, preserve all raw annotations and adjudicate separately.

Annotation should be blinded to model predictions.

---

# 4. Three timing quantities that must not be conflated

For each season:

- `I*` = expert latent ignition time;
- `A` = causal M0 detection origin;
- `T*` = expert latent peak time.

Two distinct durations are scientifically useful:

`D_epi = T* - I*`

and

`D_runtime = T* - A`.

`D_epi` answers:

> How regular is the biological ignition-to-peak interval?

`D_runtime` answers:

> Once the deployed system actually detects ignition, how much time remains until the peak?

The official runtime M1 prior must be based on `D_runtime`, with `A` produced by season-excluded causal M0 replay.

Do not substitute `A` into a prior learned from `T* - I*`; that mechanically adds M0 detection error to the peak forecast.

Preserve negative `D_runtime` values if M0 detects after the expert peak. Missed ignition must also remain explicit rather than disappearing from the conditioning set.

---

# 5. First analyses before selecting M1-v2

No statistical M1-v2 family should be selected before the 11-season timing/shape geometry is characterized.

## 5.1 Expert biological timing geometry

Using all 11 expert-labeled seasons descriptively, summarize:

`D_epi = T* - I*`.

Report:

- individual season values;
- mean/median;
- SD/IQR/range;
- sensitivity to each season;
- ambiguous-label sensitivity.

This characterizes the epidemiological regularity of ignition-to-peak timing. It is not itself the runtime baseline.

## 5.2 Runtime timing geometry

Replay M0 causally with season exclusion and derive:

`D_runtime = T* - A`.

Report:

- detection delay `A - I*`;
- missed detection;
- early detection;
- post-peak detection;
- distribution of remaining time to peak conditional on actual runtime activation.

This distribution is the initial runtime M1 baseline/prior candidate.

## 5.3 Ignition-aligned trajectories

Align historical seasons at expert ignition for descriptive biology and at causal M0 detection for runtime relevance.

Inspect:

- activation origin;
- +1 observed week;
- +2 observed weeks;
- through peak +2.

Questions:

- how informative are the first one/two observations after activation?
- how similar are local increments and recent-history patterns?
- how much additional timing information exists beyond the detection-time prior?
- which seasons are genuine outliers?

Do not rely on a single edge slope estimate as a principal feature. Boundary derivatives are fragile; use the observed short trajectory or stable summaries.

## 5.4 Peak-aligned trajectories

Align completed historical seasons at expert peak `T*`.

Focus on the operational window from approximately the typical runtime activation lead through peak +2.

Measure:

- shared rise geometry;
- peak sharpness/plateau behavior;
- amplitude variation;
- width variation;
- early decline variation;
- dimensionality of between-season shape variation.

The late decline must not drive common-curve complexity.

## 5.5 Information accumulation by origin

At each causal origin after activation, measure how much trajectory data improve inference beyond the runtime prior.

Compare progressively:

1. calendar-only/climatology baseline;
2. expert-ignition timing baseline, descriptive only;
3. runtime M0-detection prior;
4. runtime prior + current level/history;
5. runtime prior + one post-detection observation;
6. runtime prior + two post-detection observations;
7. richer regularized shape evidence only if justified.

The purpose is to learn what the data can identify, not to maximize tuning complexity.

---

# 6. M1-v2 statistical principles

## 6.1 Direct peak-time inference

Parameterize the primary target directly as continuous peak time `T*`.

Do not recreate the old architecture where an abstract phase shift/dilation is optimized and peak time is recovered indirectly afterward.

## 6.2 Minimal first model family

The first serious M1-v2 candidate should be simple, explicit, and probabilistic.

A reasonable initial family to test is a finite-grid/discretized continuous-time filter over candidate peak times:

`P(T* | data through t, activation A)`

with initialization from the season-excluded empirical/runtime prior over `T* - A`.

For each candidate `T*`, use a strongly regularized peak-relative historical shape model to evaluate how compatible the observed prefix is with that timing.

This is a candidate to test, not a mandatory final architecture.

Do not add fPCA, hierarchical random shapes, free dilation, or free width until simpler models fail for a diagnosed reason.

## 6.3 Observation model must be explicit

Before fitting, define:

- whether modeling occurs on probability, logit, count, or another scale;
- how weekly aggregation is represented;
- whether denominators `N` are available and used;
- how overdispersion is handled;
- how changing denominators/revision noise affect likelihood strength.

A beta-binomial, binomial with overdispersion, or tempered residual likelihood may be reasonable candidates, but the exact family remains open until the data contract is inspected.

The uncertainty update must not become falsely overconfident simply because many correlated weekly residuals are multiplied as if independent.

## 6.4 Sequential information-consumption rule

Choose exactly one of these semantics:

A. recompute from the original prior and the complete available prefix at every origin; or

B. perform a mathematically equivalent incremental conditional update using only genuinely new information.

Never update last week's posterior using a likelihood that reuses the entire prefix, because that double-counts previous observations and artificially contracts uncertainty.

Define behavior for:

- duplicate deliveries;
- missing weeks;
- revised historical weeks;
- out-of-order observations;
- save/resume replay.

The runtime state must retain consumed observation identities and data revision identity.

## 6.5 Peak-relative shape must be timing-identifiable

Calling a latent parameter `T*` does not solve timing confounding if the shape model itself can shift its maximum.

The shape model must define what relative time zero means.

Possible contracts:

- zero is constrained to the primary maximum;
- zero is an expert-defined event anchor that may correspond to a plateau interval;
- plateau/multiple-peak cases use an interval rather than a unique maximum.

Any shape basis must be constrained or diagnosed so derivative-like/shift-like directions cannot silently exchange shape variation for timing variation.

## 6.6 Favor low-dimensional historical variation

Legacy M1-v1 factor-smooth fits were highly flexible and showed weak identifiability.

Candidate historical representations, in order of increasing complexity:

1. one strongly regularized canonical peak-relative curve;
2. canonical curve + very small low-rank deviations;
3. functional PCA/low-rank basis;
4. hierarchical probabilistic shape model.

Only move down this list when the simpler representation fails under the declared validation procedure.

## 6.7 No free dilation initially

Do not include freely optimized width/dilation in the initial M1-v2.

If width variation later proves necessary, prefer a strongly regularized historical distribution and integrate over its uncertainty rather than freely maximizing width at each origin.

## 6.8 Positive amplitude and other nuisance parameters

If amplitude scaling is required, guarantee positivity, e.g. `b = exp(beta)`.

Regularize nuisance parameters around historically plausible values.

Do not let flexible amplitude/baseline terms absorb timing misfit without diagnosis.

## 6.9 Uncertainty is first-class

M1 must maintain a probability distribution or calibrated approximation over peak time.

Desired behavior:

- broad near activation if evidence is limited;
- generally narrower as informative observations accumulate;
- able to widen when new data genuinely contradict the previous belief;
- wider for out-of-family seasons;
- stable enough to avoid multi-week oscillation from small noise.

Public lock does not imply statistical uncertainty is zero. After confirmation, preserve a frozen posterior or explicit locked-time uncertainty for internal M2 use if needed.

---

# 7. M1 public, internal, and failure contracts

## 7.1 Public output before passage

At every active origin before passage confirmation:

- decimal peak point estimate;
- uncertainty interval/quantiles;
- optionally probability that peak occurs within next 1/2/3 weeks.

## 7.2 Public output after passage

Once primary peak passage is confirmed:

- stop emitting a future peak forecast;
- expose a simple `peak_reached_or_passed` status;
- optionally show the locked peak estimate/interval if useful.

## 7.3 Internal state after passage

M1 may continue supplying M2 with:

- locked/frozen peak posterior summaries;
- peak-relative phase;
- common-curve features;
- probability mass around the current/previous week;
- internal confidence state.

## 7.4 Failure states

Runtime state must distinguish at least:

- `pre_ignition`;
- `active`;
- `passage_confirmed`;
- `insufficient_data`;
- `m1_failed`;
- `season_ended`.

M2 fallback behavior must be explicit when M1 is unavailable or fails.

No silent fallback to stale M1 features is allowed.

---

# 8. Peak-passage confirmation

Peak inference and peak-passage confirmation are separate tasks.

M1-F:

- estimates `P(T* | data_t)`.

M1-C:

- decides whether enough causal evidence exists to stop the public future-peak forecast and lock the operational state.

Candidate evidence may include:

- posterior mass that `T* <= current time`;
- observed decline relative to recent maximum;
- persistence across multiple origins;
- protection against one-week reporting noise.

False-early passage confirmation is likely operationally more harmful than slightly late confirmation because it suppresses a still-relevant peak forecast. The loss/selection rule should reflect that asymmetry explicitly if epidemiologically appropriate.

Secondary-peak policy must be predeclared. Default: once the operational primary peak is confirmed, later bumps do not reopen the original peak forecast unless a specific exceptional rule is defined and validated.

---

# 9. M1-to-M2 interface

The interface schema must be defined before model fitting, even if some optional fields remain experimental.

Each feature row must include:

- season/episode ID;
- origin time;
- target time;
- horizon;
- coordinate version;
- feature scale/version;
- availability/status;
- upstream model bundle ID;
- feature schema version.

Candidate compact M1 fields:

- `peak_point`;
- `peak_interval_width` or `peak_sd`;
- `prob_peak_within_1w`;
- `prob_peak_within_2w`;
- `prob_peak_passed`;
- `locked_peak_if_any`.

Common-curve features must be defined precisely.

## 9.1 Absolute posterior-averaged curve features

Possible feature:

`E[g(t+h-T*) | data_t]`.

Caution: averaging shifted absolute curves can flatten the peak when timing uncertainty is broad.

## 9.2 Relative growth/shape features

Also test relative features that condition on the known current level/shape, for example expected change on a stable link scale:

`E[link(g(t+h-T*)) - link(g(t-T*)) | data_t]`.

These may be more robust to timing uncertainty than an uncertain absolute percentage baseline.

## 9.3 Uncertainty semantics

`curve_mean` and `curve_sd` must specify exactly what uncertainty is integrated:

- peak-time uncertainty;
- amplitude uncertainty;
- shape uncertainty;
- other nuisance uncertainty.

Common-curve uncertainty is not the same as the final observed-percentage forecast interval. M2 must separately account for residual/observation uncertainty.

## 9.4 Cross-fitting requirement

For any historical M2 training row from season `r`, the M0/M1/common-curve features used for that row must be generated from upstream models that excluded `r`, and also excluded whatever outer/inner evaluation seasons are required by the current validation fold.

M2 must never train on unrealistically oracle-like in-sample M1 features.

---

# 10. Validation and exclusion design

All performance claims must be season-level and causal.

Weekly origins are repeated measures within season, not independent samples.

## 10.1 Outer LOSO remains required

LOSO measures exchangeable-season generalization.

No held-out season's expert ignition/peak truth may enter its runtime features.

## 10.2 Nested selection / stacking exclusions

Let:

- `o` = outer test season;
- `v` = inner validation season;
- `r` = season contributing an M2 training row.

Required upstream exclusions:

| Purpose | Seasons excluded from upstream fitting |
|---|---|
| Outer test features for `o` | `o` |
| M2 training features for `r`, within outer fold `o` | `o, r` |
| Inner validation features for `v` | `o, v` |
| M2 training features for `r` while validating on `v` | `o, v, r` |

Apply these exclusions to every tuned upstream component that can affect a feature or selection decision, including:

- M0 selection;
- detection-time priors;
- common-curve fitting;
- normalization;
- shape rank/df selection;
- passage thresholds;
- M1 calibration;
- M2 selection;
- interval calibration.

Cache fitted artifacts by complete exclusion/training set, data hash, label hash, specification, and code identity.

## 10.3 Candidate-independent evaluation ledger

Evaluation rows must be declared independently of the candidate model's own activation or stopping behavior.

A model cannot improve its score by:

- detecting ignition late and thereby avoiding hard origins;
- confirming passage early and thereby removing later difficult origins;
- abstaining without an explicit penalty/coverage accounting.

Reference truth may define evaluation windows. Model state defines runtime output availability, not which rows exist in the scoring ledger.

Track unavailable forecasts with explicit reasons.

## 10.4 M1 primary metrics

Evaluate decimal peak timing on fixed/common origins with season-balanced aggregation.

Report:

- decimal MAE;
- median absolute error;
- fraction within +/-0.5 week;
- fraction within +/-1 week;
- fraction with error >=2 weeks;
- signed error;
- per-season paired results;
- denominators/coverage.

A two-week miss is operationally large.

Stratify by true lead time to peak, not only weeks since ignition/detection.

## 10.5 M1 probabilistic metrics

Report:

- interval coverage;
- interval width;
- proper score for the peak-time distribution where practical;
- calibration of peak within next 1/2/3 weeks;
- uncertainty evolution by true lead time;
- week-to-week posterior movement.

## 10.6 Peak-passage metrics

Report:

- false early confirmation;
- confirmation delay;
- missed confirmation;
- locked peak accuracy;
- post-lock invariance;
- inappropriate reopening.

## 10.7 M2 metrics

Evaluate separately at horizon +1 and +2.

Define whether phase strata refer to origin or target week.

Report at minimum:

- MAE by horizon;
- season-balanced aggregate;
- per-season paired differences;
- forecast coverage/availability;
- calibration/interval coverage if probabilistic.

Late decline must not dominate selection.

## 10.8 End-to-end service metrics

In addition to conditional forecast accuracy, report service-level coverage:

- fraction of seasons with timely ignition detection;
- origins with active M1/M2 service;
- missed/delayed activation;
- false early passage;
- unavailable forecasts;
- fallback usage.

This prevents a model from appearing accurate only because it produces fewer forecasts.

---

# 11. Chronological and prospective evidence

LOSO is necessary but not sufficient for every claim.

Use two retrospective views:

1. season-level LOSO for exchangeable-season generalization;
2. expanding-window / prior-seasons-only replay for chronological transfer.

Within-season causality alone does not prevent a LOSO model from learning from seasons that occurred later in calendar time than the held-out season.

Where historical data revisions/availability timestamps are not reproducible, label the exercise as retrospective final-data replay.

Previously studied historical seasons are not untouched prospective evidence simply because the architecture is new.

Reserve prospective claims for a recipe frozen before future outcomes are observed. The next genuinely prospective season should be treated as a high-value confirmation set.

---

# 12. Required baselines

Before sophisticated models, establish simple baselines under the same exclusion/scoring contracts.

## 12.1 M1 baselines

1. calendar-only/climatological peak-time distribution;
2. expert biological `T* - I*` distribution, descriptive benchmark only;
3. runtime mean remaining duration from `T* - A`;
4. runtime median remaining duration;
5. empirical runtime distribution of `T* - A`;
6. minimal causal updates from recent observations.

Any complex M1-v2 must materially improve on the runtime detection-time baseline, not merely on a weaker calendar baseline.

## 12.2 M2 baselines

At minimum:

1. persistence / last observation;
2. simple local-change model;
3. no-M1 causal model;
4. M1 point-timing feature only;
5. common-curve feature only;
6. common-curve + M1 uncertainty;
7. frozen legacy comparator where meaningfully rescored under compatible truth/windows.

The sealed v1 integer MAE is not directly comparable to a new decimal target unless rescored on a common ledger.

---

# 13. Sequential state and ledger contract

Separate four artifact classes:

1. annotation truth;
2. offline learned model artifacts;
3. mutable runtime episode state;
4. immutable forecast/evaluation ledgers.

Reference truth must not live inside runtime state.

Minimum runtime M1 state should include:

```text
season_id
episode_id
origin_time
as_of_cutoff
ignition_detect_origin
peak_posterior_state
peak_point_estimate
peak_interval
peak_passage_state
locked_peak_if_any
consumed_observation_ids
data_revision_id
state_schema_version
model_bundle_id
rng_state_if_needed
```

M1 feature rows for M2 should additionally include:

```text
target_time
horizon
feature_availability
feature_reason
feature_schema_version
coordinate_version
scale_version
upstream_bundle_id
```

Requirements:

- save/resume replay must reproduce uninterrupted replay;
- duplicate ingestion must be idempotent or rejected;
- out-of-order/revised observations must have explicit behavior;
- future/suffix data changes must not alter earlier immutable forecasts;
- unsupported feature/model bundle combinations must fail explicitly;
- M2 cannot consume stale M1 features from a previous origin.

---

# 14. Reproducibility and governance

Every experiment should record:

- git commit;
- branch/worktree identity;
- training/exclusion sets;
- outer/inner split identity;
- data snapshot/hash;
- annotation label version/hash;
- coordinate contract version;
- model specification;
- hyperparameters/priors;
- selection/calibration procedure;
- random seed/RNG state if relevant;
- per-origin predictions;
- uncertainty outputs;
- runtime state transitions;
- availability/fallback reasons;
- metrics;
- artifact hashes.

The annotation truth set is versioned independently from model releases.

No experiment may silently mutate historical labels or overwrite a previous annotation version.

---

# 15. Legacy M1-v1 policy

The sealed comparator remains frozen.

Do not mutate:

`results/releases/m1-release-v1.0.0`

Legacy findings remain evidence about failure modes:

- reproducibility achieved;
- large season-specific timing failures;
- little aggregate directional bias;
- weak template-ranking signal;
- optimizer max-evaluation frequency;
- severe parameter/template instability;
- unconstrained post-fit negative scale bug;
- unclear peak-passage semantics;
- incomplete diagnostic serialization;
- highly flexible factor-smooth historical templates;
- poor identifiability of phase/dilation on partial trajectories.

Do not carry forward `tau`, `delta`, template softmax, or independent-origin refitting merely for compatibility.

If the legacy comparator is used in the new evaluation, rescore it on the new truth and candidate-independent ledger where possible without altering its sealed artifacts.

---

# 16. Implementation phases

## Phase 0 — repair governance boundary

Before statistical implementation:

- repair/verify the `PAGe-m1-v2` Git worktree metadata;
- verify branch identity and clean status;
- preserve the dirty legacy checkout untouched;
- preserve the sealed v1 release;
- freeze this reconciled plan as the governing preimplementation document.

## Phase 1 — freeze time/annotation contract

Detailed implementation plan: `docs/m1-v2-phase1-implementation-plan-2026-09-22.md`.

Compatibility rule: the existing `timing_v2` integer-pair labeling API is retained only for legacy reproduction. The redesign uses a separate expert-decimal annotation schema governed by `docs/timing-annotation-contract-v1.md`; redesign code must not silently convert expert decimals through legacy pair normalization.

Deliver documentation/tests for:

- canonical continuous season coordinate;
- mapping to epidemiological calendar/date;
- weekly observation/release timing semantics;
- primary-peak definition;
- ambiguity/plateau/multiwave handling;
- annotation schema version.

Decision gate:

Do not collect final expert labels until these semantics are explicit.

## Phase 2 — expert labeling

Deliver:

- simple review plots / numeric-entry workflow;
- deterministic versioned storage;
- 11-season expert ignition and peak labels;
- repeat labeling pass;
- ambiguity intervals/status where needed;
- frozen first annotation release.

## Phase 3 — causal replay and descriptive geometry

Deliver:

- causal season-excluded M0 replay for all seasons;
- `I*`, `A`, `T*` table;
- M0 detection-delay analysis;
- biological `T* - I*` distribution;
- runtime `T* - A` distribution;
- ignition/detection-aligned trajectory panels;
- peak-aligned trajectory panels;
- early post-activation information analysis;
- simple runtime prior performance;
- chronological/prior-only descriptive replay where possible.

Decision gate:

Determine whether a complex M1 model is justified at all.

## Phase 4 — empty causal state/feature ledger

Before fitting sophisticated M1/M2, implement the runtime schema and exclusion-aware feature-generation skeleton:

- state serialization;
- observation-consumption bookkeeping;
- candidate-independent evaluation ledger;
- availability/failure reasons;
- model/feature provenance assertions;
- cross-fitting hooks.

This phase ensures later models cannot bypass causal/provenance contracts.

## Phase 5 — minimal M1 baseline

Implement:

- season-excluded runtime `T* - A` prior;
- decimal peak distribution;
- deterministic weekly recomputation or mathematically valid incremental update;
- explicit uncertainty;
- no free dilation;
- no legacy template weighting.

Compare against the fixed simple baselines.

## Phase 6 — minimal peak-relative shape evidence

Start with one strongly regularized canonical peak-relative curve.

Evaluate:

- whether it improves M1 timing beyond the detection-time prior;
- whether zero remains a valid/identifiable peak anchor;
- whether shape likelihood is calibrated;
- whether added uncertainty contracts appropriately.

Only add low-rank deviations if the canonical curve fails for a diagnosed reason.

## Phase 7 — peak-passage state machine

Implement independently with:

- causal evidence;
- persistent explicit state;
- asymmetric false-early vs late-confirmation evaluation if justified;
- explicit lock;
- no silent reopening;
- declared secondary-peak policy.

## Phase 8 — freeze M1-to-M2 interface

Finalize the compact feature schema after ablation evidence.

Test at minimum:

- no M1 features;
- peak point only;
- peak uncertainty summaries;
- absolute common-curve features;
- relative growth/shape features.

Do not expose large opaque latent vectors without evidence.

## Phase 9 — M2 redesign

Build specifically for +1/+2 forecasts using only cross-fitted upstream features.

Selection must occur inside the declared nested exclusion procedure.

M2 complexity must earn itself against no-M1 and simple baselines.

## Phase 10 — end-to-end release candidate

Run:

- strict outer LOSO;
- nested/cross-fitted upstream feature generation;
- candidate-independent scoring ledger;
- chronological/prior-seasons-only replay where feasible;
- full M0/M1/M2 service-coverage analysis.

Produce:

- user-facing output ledger;
- M0 detection ledger;
- M1 peak posterior ledger;
- passage ledger;
- M2 +1/+2 forecast ledger;
- calibration diagnostics;
- per-season paired failure analysis;
- availability/fallback analysis;
- frozen release manifest.

---

# 17. Decisions intentionally left open until empirical characterization

Do not prematurely lock:

- exact peak-time probabilistic family;
- exact likelihood/observation model;
- exact common-curve smoother/df;
- whether fPCA is needed;
- whether width/dilation is needed at all;
- exact amplitude model;
- exact peak-passage threshold;
- exact M2 learner;
- whether M2 needs full posterior vs compact summaries;
- whether absolute or relative common-curve features are superior.

These decisions must be earned by the 11-season geometry and the declared validation procedure.

---

# 18. Immediate next actions

1. Repair and verify the new worktree Git metadata.
2. Freeze the canonical decimal-time/primary-peak annotation contract.
3. Build only the minimal expert-labeling workflow.
4. Label all 11 seasons and repeat the labeling pass.
5. Freeze/version the first annotation set.
6. Replay M0 causally with season exclusion and derive actual detection origins `A`.
7. Quantify both `T* - I*` and runtime `T* - A`.
8. Build the candidate-independent causal evaluation ledger and cross-fitting skeleton.
9. Evaluate the simple runtime prior before fitting any sophisticated shape model.
10. Only then select the first minimal M1-v2 likelihood/shape candidate.

The statistical redesign should begin from the empirical question:

> Once the deployed system has actually detected ignition, how much uncertainty remains about the peak, how quickly do the next one or two observations reduce it, and what is the minimum identifiable shape model needed to improve that inference without leaking information or overstating certainty?
