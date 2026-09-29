# V3 M1-B passage robustness plan v2

Date: 2026-09-26
Status: audited design revised for pandemic-season exclusion; ready for implementation

## Scope

Keep raw M1-B0 peak-location inference fixed. Harden only the B peak-passage selector.

M1-B season policy is defined in:

`docs/v3-m1-b-season-policy-2026-09-26.md`

For M1-B, `2019-20` is excluded from training and scoring as `pandemic_transition`. The canonical panel retains the season for audit. `2018-19` remains an explicit no-meaningful-B-activity/no-peak season.

This produces five chronologically scored B timing seasons:

- 2017-18
- 2022-23
- 2023-24
- 2024-25
- 2025-26

## Existing baseline after exclusion

Raw M1-B0 peak-location benchmark:

`artifacts/v3-m1-b0-excluding-pandemic-v1/`

Existing passage policy refit after exclusion:

`artifacts/v3-m1-b-passage-excluding-pandemic-v1/`

Existing passage policy is safe but late:

- false early under activation -1/0/+1: 0/5 for every shift;
- confirmed by peak+2: 2/5;
- mean delay penalty: 2.2 weeks;
- median delay penalty: 3 weeks.

Therefore the only permitted objective of this study is to improve timeliness while retaining zero-false-early safety.

## Second-look limitation

This is a second historical look. The policy family and activation-robust idea were designed after earlier B passage results were inspected.

A passing result can make the selector eligible for **v3 shadow use only**. It cannot establish a production hard gate. Prospective 2026-27 evidence is required before production promotion.

## Fixed components

- raw M1-B0 library mechanics from `PAGe/R/m1_v2.R`;
- B amplitude grid `0.005:0.005:0.25`;
- B activity marker/window `weekF 8-40`;
- B peak truth from the reproducible timing contract;
- chronological expanding-window outer folds;
- passage posterior mechanics from `m1_v2_passage_posterior()`;
- decision evidence structure from `m1_v2_passage_decision()`.

No new runtime covariates or season-specific rules are introduced.

## Candidate grid

The v1 audit identified boundary winners in the prior grid. The final predeclared grid is:

- `high_threshold`: `0.95, 0.975, 0.99`
- `low_threshold`: `0.10, 0.20, 0.30, 0.40, 0.50`
- `drop_fraction`: `0.03, 0.05, 0.08, 0.10, 0.12`
- `fast_drop_fraction`: `0, 0.03, 0.05, 0.08, 0.10`
- `min_post_activation`: `3, 4, 5, 6`

`high_threshold=0.99` is the hard upper constraint. Other edge selections are reported explicitly.

## Inner activation robustness

For every outer fold, only strictly earlier meaningful, non-excluded B seasons enter training.

Generate inner cross-fitted passage histories under:

- activation shift `-1`
- activation shift `0`
- activation shift `+1`

The same training season set is used for all shifts. Activation shifts affect only causal activation coordinates, never peak truth.

## Exact policy evaluation

For every candidate policy and each inner shift `s`:

- `n_false_early_s = sum(false_early)`
- `early_weeks_total_s = sum(early_weeks)`
- `n_miss_by_peak2_s = sum(confirm_origin is NA or confirm_origin > truth_confirm + 2)`
- `total_delay_penalty_s = sum(if confirmed then max(confirm_origin-truth_confirm,0) else 7)`

Across shifts:

- `worst_shift_n_false_early = max_s(n_false_early_s)`
- `worst_shift_early_weeks_total = max_s(early_weeks_total_s)`
- `all_shift_n_false_early = sum_s(n_false_early_s)`
- `all_shift_early_weeks_total = sum_s(early_weeks_total_s)`
- `worst_shift_n_miss_by_peak2 = max_s(n_miss_by_peak2_s)`
- `all_shift_n_miss_by_peak2 = sum_s(n_miss_by_peak2_s)`
- `worst_shift_total_delay_penalty = max_s(total_delay_penalty_s)`
- `all_shift_total_delay_penalty = sum_s(total_delay_penalty_s)`

Select lexicographically by the above eight keys, then deterministic conservative tie-breaks:

1. higher `high_threshold`
2. larger `fast_drop_fraction`
3. larger `drop_fraction`
4. larger `min_post_activation`
5. higher `low_threshold`

The resulting order is total and deterministic.

## Inner feasibility veto

For the selected policy in every outer fold, record:

- `inner_worst_shift_n_false_early`
- `inner_worst_shift_n_miss_by_peak2`
- `inner_worst_shift_total_delay_penalty`

If `inner_worst_shift_n_false_early > 0`, that outer fold fails passage eligibility regardless of its held-out result.

## Outer replay semantics

Once selected, the policy and B library remain fixed.

Replay held-out B under outer activation shifts `-1/0/+1` by shifting **only the held-out activation coordinate**. Training data, training activations, library, and selected policy do not change.

Replay origins through `max(heldout$weekF)`. Retrospective truth is used only after replay for scoring; it never determines the prediction/replay horizon.

## Passage states

Operational M1-B state is exactly one of:

- `inactive_no_timing_event`
- `active_unconfirmed`
- `confirmed`

Only `confirmed` is a positive timing-gate candidate. `inactive_no_timing_event` and `active_unconfirmed` must not be interpreted as positive or as a pre-peak gate.

## 2018-19 no-event contract

For 2018-19:

1. replay the B activity detector on every weekly prefix through the candidate window;
2. require no activation within `weekF 8-40`;
3. output `inactive_no_timing_event`;
4. output `positive_timing_gate = FALSE`;
5. retain the existing exclusion-perturbation test showing 2018-19 observations do not affect later B timing folds.

A pseudo-activation passage replay may be reported diagnostically, but it has no decision weight.

## Comparison targets

Report:

1. existing pandemic-excluded passage selector;
2. activation-robust selector;
3. sustained-only diagnostic using the robust selector's sustained parameters, with fast branch disabled by `high_threshold=1` and `fast_drop_fraction=1`; assert no `high_posterior_decline` branch occurs.

## Integrity tests

Required:

1. strict outer fold isolation;
2. strict inner fold isolation;
3. no 2019-20 row enters M1-B training/scoring;
4. future-observation perturbation invariance for outer shifts `-1/0/+1`;
5. held-out peak-truth perturbation changes scoring only, not passage predictions;
6. nominal raw B0 peak-posterior summaries reproduce `artifacts/v3-m1-b0-excluding-pandemic-v1/` to numerical tolerance;
7. shift-0 inner evaluator agrees with frozen `fit_m1_v2_passage_policy()` on the frozen sub-grid;
8. deterministic policy selection under repeated scoring;
9. 2018-19 prefix detector never activates in weekF `8-40`;
10. source/plan hashes recorded;
11. frozen `PAGe/R` code unchanged.

## Acceptance criteria

This second-look study is `historically_promising_second_look = TRUE` only if all hold on the five eligible nominal outer seasons:

- 0 false-early seasons;
- at least 4/5 confirmed by `truth_confirm + 2`;
- median delay penalty <= 2 weeks;
- mean delay penalty <= 2.5 weeks;
- every outer fold passes the inner feasibility veto;
- all integrity tests pass;
- no unexpected replay failures.

Outer activation robustness veto:

- activation `-1`: 0 false-early seasons;
- activation `+1`: 0 false-early seasons.

A passing historical result is eligible only for prospective v3 shadow use.

## Failure decision

If the robust selector fails:

- retain raw M1-B0 peak location;
- keep the existing conservative passage state for descriptive/shadow diagnostics only;
- do not use a hard M1-B passage gate in M2-B;
- future M2-B timing integration must use continuous posterior uncertainty or no timing gate rather than another post-hoc threshold search.

## Artifact tree

Write once to:

`artifacts/v3-m1-b-passage-robustness-v2/`

Required outputs:

- `outer_fold_ledger.csv`
- `selected_policy_by_outer_fold.csv`
- `policy_scores_by_outer_fold.csv`
- `inner_passage_history.csv`
- `inner_selected_policy_evaluation.csv`
- `outer_passage_by_season.csv`
- `outer_activation_sensitivity.csv`
- `comparison_existing_policy.csv`
- `sustained_only_diagnostic.csv`
- `no_event_prefix_check.csv`
- `future_perturbation_checks.csv`
- `truth_perturbation_checks.csv`
- `raw_B0_reproduction_checks.csv`
- `failures.csv`
- `acceptance_criteria.csv`
- `overall_verdict.csv`
- `source_manifest.csv`
- `benchmark_config.csv`
