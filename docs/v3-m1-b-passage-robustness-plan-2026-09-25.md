# V3 M1-B passage robustness plan

Date: 2026-09-25
Status: audited, revised, ready for implementation
Study type: second-look historical robustness study; not a clean holdout

## Objective

Harden the unresolved M1-B passage state without changing the accepted raw M1-B0 peak-location baseline.

The question is narrow:

> Given a causal B activity activation and the raw M1-B0 passage posterior, can a passage-confirmation policy selected on prior seasons remain safe under plausible activation timing uncertainty?

This work does **not** retune B peak-location estimation and does **not** use the failed scalar calibration branch.

## Evidence status and second-look limitation

This policy family and activation-robust selection rule were designed after inspection of the existing six-season B passage replay, including the 2019-20 false-early behavior. Therefore this is explicitly a **second-look historical robustness study**.

A successful result may make the candidate eligible only for **M2-B shadow integration**. It cannot establish a governed hard timing gate. Prospective 2026-27 evidence is required before production promotion.

The SHA-256 of this plan must be recorded before the first benchmark run and written into the output manifest.

## Fixed components

Frozen for this study:

- raw M1-B0 peak-location mechanics from `PAGe/R/m1_v2.R`;
- B amplitude grid `0.005:0.005:0.25`;
- canonical panel and retrospective B peak truth;
- B activity detector/marker from the reproducible timing contract;
- chronological expanding-window outer folds;
- passage candidate step `0.2`;
- passage maximum future support `12` weeks;
- late scoring horizon `6` weeks after truth-confirm;
- 2018-19 explicit no-meaningful-B-activity/no-B-peak state.

The current B activity marker remains an exploratory operational activation, not biological ignition truth. Its detector/window were selected with knowledge of the full archive; that limitation must be carried into every verdict.

## Why a new selector is justified

The frozen A-oriented passage selector optimizes on one activation coordinate per training season. The existing B benchmark showed passage sensitivity to a one-week activation perturbation.

This study changes **policy-selection robustness only**. It does not alter the raw M1-B0 posterior model.

## Policy family

The causal evidence structure remains identical to `m1_v2_passage_decision()`.

### Fast branch

Requires:

- high posterior probability that peak has passed;
- immediate observed one-week decline;
- minimum drop from post-activation maximum;
- minimum post-activation age.

### Sustained branch

Requires:

- lower passage-probability threshold;
- two consecutive observed declines;
- minimum drop from post-activation maximum;
- minimum post-activation age.

No new covariates, season identities, or season-specific rules are introduced.

## Predeclared candidate grid

Candidate family:

- `high_threshold`: `0.95, 0.975, 0.99`
- `low_threshold`: `0.10, 0.20, 0.30, 0.40, 0.50`
- `drop_fraction`: `0.03, 0.05, 0.08, 0.10, 0.12`
- `fast_drop_fraction`: `0, 0.03, 0.05, 0.08, 0.10`
- `min_post_activation`: `3, 4, 5, 6`

`high_threshold = 0.99` is a hard ceiling because probabilities arbitrarily close to 1 are numerically unstable as tuning targets and `m1_v2_passage_decision()` requires the value to lie in `[0.95,1]`.

The other axes include one adjacent step beyond boundaries selected by the earlier v2 grid. Every selected policy must record whether it lies on each grid boundary.

Grid size: `3 * 5 * 5 * 5 * 4 = 1500` candidate policies. Although large relative to the number of seasons, each candidate is only a threshold combination over the same two-branch rule. Overfitting risk is handled by strict outer chronology, activation-shift stress selection, conservative tie-breaks, explicit second-look labeling, and prospective confirmation before production use.

## Activation uncertainty for inner robustness

For every inner held-out training season, generate causal passage histories under:

- `activation_shift = -1`
- `activation_shift = 0`
- `activation_shift = +1`

Shift both activation origin and decimal activation consistently.

For each outer fold, the B library and policy are trained only from seasons strictly earlier than the outer test season. Inner peak libraries remain cross-fitted within those training seasons.

## Exact robust policy-selection objective

For candidate policy `j`, activation shift `s in {-1,0,+1}`, and inner held-out season `i`, define:

- `FE(i,s,j)` = 1 if confirmation is before `truth_confirm`, else 0;
- `EW(i,s,j)` = false-early weeks, else 0;
- `MISS(i,s,j)` = 1 if no confirmation by `truth_confirm + 2`, else 0;
- `D7(i,s,j)` = confirmation delay if finite, otherwise 7 weeks.

For each shift `s`:

- `FE_s(j) = sum_i FE(i,s,j)`
- `EW_s(j) = sum_i EW(i,s,j)`
- `MISS_s(j) = sum_i MISS(i,s,j)`
- `D7_s(j) = sum_i D7(i,s,j)`

Aggregate keys:

- `worst_shift_n_false_early = max_s FE_s`
- `worst_shift_early_weeks_total = max_s EW_s`
- `all_shift_n_false_early = sum_s FE_s`
- `all_shift_early_weeks_total = sum_s EW_s`
- `worst_shift_n_miss_by_peak2 = max_s MISS_s`
- `all_shift_n_miss_by_peak2 = sum_s MISS_s`
- `worst_shift_delay7_total = max_s D7_s`
- `all_shift_delay7_total = sum_s D7_s`

Select lexicographically by:

1. `worst_shift_n_false_early`
2. `worst_shift_early_weeks_total`
3. `all_shift_n_false_early`
4. `all_shift_early_weeks_total`
5. `worst_shift_n_miss_by_peak2`
6. `all_shift_n_miss_by_peak2`
7. `worst_shift_delay7_total`
8. `all_shift_delay7_total`
9. prefer higher `high_threshold`
10. prefer larger `fast_drop_fraction`
11. prefer larger `drop_fraction`
12. prefer larger `min_post_activation`
13. prefer higher `low_threshold`

The parameter tie-break keys create a deterministic total order.

### Inner-feasibility gate

For the selected policy in each outer fold, record:

- `inner_worst_shift_n_false_early`
- `inner_worst_shift_n_miss_by_peak2`
- `inner_all_shift_miss_rate`

Any outer fold whose selected policy has `inner_worst_shift_n_false_early > 0` fails M2-B eligibility, even if the outer held-out result happens to be safe.

## Outer chronological replay

For each eligible B test season:

1. training seasons are strictly earlier seasons with meaningful B peak truth;
2. fit the raw B library from those seasons only;
3. generate inner cross-fitted passage histories under activation shifts `-1/0/+1`;
4. select one robust policy using the exact objective above;
5. freeze the library and selected policy;
6. replay the outer test season at nominal activation (`shift=0`);
7. replay outer test activation `-1` and `+1` as sensitivity **without refitting the library or policy**.

This differs from the earlier calibration sensitivity benchmark, which shifted training and test activations together. Comparison rows using the earlier semantics must be labelled separately.

## Truth-independent outer replay horizon

Predictions and passage decisions must be generated through `max(held$weekF)` and must not stop based on the retrospective peak truth.

Truth is used only after replay to score:

- false-early behavior;
- confirmation by `truth_confirm + 2`;
- delay;
- censoring/penalty summaries through `truth_confirm + 6`.

Therefore perturbing outer peak truth cannot alter generated passage probabilities or decisions.

## Truth and metrics

For retrospective decimal B peak `T`:

`truth_confirm = ceiling(T) - 1`

`confirmed_by_peak2` means exactly:

`confirm_origin <= truth_confirm + 2`

Primary safety metrics:

- number of false-early seasons;
- total false-early weeks;
- maximum false-early magnitude.

Timeliness metrics:

- confirmed by peak+2;
- delay relative to `truth_confirm`;
- mean delay with unconfirmed seasons assigned 7 weeks;
- median delay with unconfirmed seasons assigned 7 weeks;
- number of unconfirmed seasons.

With only six outer timing seasons, even observing `0/6` false-early seasons leaves substantial uncertainty; the approximate 95% upper bound on a per-season false-early rate is about 39%. Historical zero-failure behavior is therefore necessary but not sufficient for production governance.

## No-event handling and three-state contract

2018-19 has no finite B peak target and is excluded from passage-policy training and timing scoring.

M1-B exposes exactly three operational timing states:

1. `inactive_no_timing_event`
2. `active_unconfirmed`
3. `confirmed`

Only `confirmed` is a positive passage signal. `inactive_no_timing_event` and `active_unconfirmed` must not be interpreted as positive passage or as an asserted pre-peak state.

### Required 2018-19 checks

1. Replay `detectIgnitionBySeason_M0v2_timing()` causally on every weekly prefix through the B activity window `8-40`; no prefix may activate.
2. With no activity detection, no M1-B passage posterior/confirmation may be generated.
3. Preserve the existing exclusion perturbation check: material changes to 2018-19 B observations must not affect later folds that exclude it from timing training.
4. Optional non-veto diagnostic: pseudo-activate 2018-19 to quantify downstream passage risk if M0-B were ever to fire falsely.

## Comparison targets

### Existing B passage selector

Reproduce nominal rows from:

`artifacts/v3-m1-b-calibrated-chronological-v2/passage_by_season.csv`

for:

- selected policy parameters;
- `confirm_origin`;
- confirmation branch.

At shift 0, the custom evaluator must also match `fit_m1_v2_passage_policy()$evaluation` exactly on the frozen sub-grid:

- `high_threshold = 0.95`
- `fast_drop_fraction = 0`
- `min_post_activation in {3,4}`
- frozen low/drop values.

### Sustained-only diagnostic

Disable the fast branch by using:

- `high_threshold = 1`
- `fast_drop_fraction = 1`

and assert that `confirmation_branch` is never `high_posterior_decline`.

Reuse the robust policy's sustained parameters (`low_threshold`, `drop_fraction`, `min_post_activation`); do not independently tune a sustained-only policy.

## Leakage and integrity tests

Required:

1. strict outer fold isolation;
2. strict inner fold isolation;
3. future-observation perturbation invariance for outer shifts `-1/0/+1`;
4. outer peak-truth perturbation changes scoring only, never generated posterior/decision paths;
5. shifted training activations are confined to inner training histories;
6. nominal existing-selector reproduction passes exactly for confirm origin, branch, and policy;
7. custom shift-0 evaluator matches frozen fitter evaluation on the frozen sub-grid;
8. 2018-19 prefix activation check produces no activation;
9. 2018-19 exclusion perturbation remains invariant for later folds;
10. deterministic policy selection on repeated evaluation;
11. selected B library retains amplitude grid `0.005:0.005:0.25`;
12. passage `candidate_step = 0.2` and `max_future_weeks = 12` are explicit;
13. no empty inner-history failures are silently ignored;
14. source/artifact hashes recorded, including this plan before execution;
15. frozen `PAGe/R` code remains unchanged.

Implementation must explicitly handle the small evaluator differences between `fit_m1_v2_passage_policy()` and `m1_v2_passage_decision()` and assert they agree on the reference shift-0 grid.

## Primary acceptance criteria

The overall historical label is:

`historically_promising_second_look`

It is `TRUE` only if all of the following hold:

### Nominal outer activations

- `0` false-early seasons;
- at least `4/6` eligible seasons satisfy `confirm_origin <= truth_confirm + 2`;
- median delay7 <= `2` weeks;
- mean delay7 <= `2.5` weeks;
- no unhandled replay failures.

### Outer activation robustness

Using the **same fixed outer-fold library and policy**:

- activation `-1`: `0` false-early seasons;
- activation `+1`: `0` false-early seasons.

### Inner feasibility and integrity

- every outer fold selected policy has `inner_worst_shift_n_false_early = 0`;
- all causal/integrity checks pass;
- deterministic policy selection passes;
- no-event contract passes.

Any failure vetoes M2-B timing-gate eligibility.

## Outputs

Write once to:

`artifacts/v3-m1-b-passage-robustness-v1/`

Required files:

- `outer_fold_ledger.csv`
- `selected_policy_by_outer_fold.csv`
- `policy_scores_by_outer_fold.csv`
- `inner_passage_history.csv`
- `outer_passage_by_season.csv`
- `outer_activation_sensitivity.csv`
- `comparison_existing_policy.csv`
- `sustained_only_diagnostic.csv`
- `no_event_check.csv`
- `future_perturbation_checks.csv`
- `truth_perturbation_checks.csv`
- `inactive_exclusion_perturbation_check.csv`
- `failures.csv`
- `acceptance_criteria.csv`
- `overall_verdict.csv`
- `source_manifest.csv`
- `benchmark_config.csv`

Selected-policy output must include boundary flags for every policy parameter.

## Decision after this study

If `historically_promising_second_look = TRUE`:

- raw M1-B0 remains the peak-location model;
- the activation-robust passage selector becomes eligible for **M2-B shadow integration only**;
- production hard gating remains blocked until prospective evidence.

If false:

- raw M1-B0 remains peak-location-only;
- hard M1-B passage gating is stopped;
- M2-B must use continuous timing uncertainty or no timing gate rather than another historical threshold search.
