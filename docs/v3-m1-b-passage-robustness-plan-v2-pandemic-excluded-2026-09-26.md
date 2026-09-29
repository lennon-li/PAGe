# V3 M1-B passage robustness plan v2 — pandemic-transition exclusion

Date: 2026-09-26
Status: CLOSED / DO NOT IMPLEMENT. Final audit found this design had already been executed in `artifacts/v3-m1-b-passage-robustness-v2/` with `historically_promising_second_look = FALSE`. Historical hard-threshold searching is closed; see `docs/v3-m1-b-final-disposition-2026-09-26.md`. Retained only as an audit record.

## Objective

Harden the unresolved M1-B passage state while keeping the accepted raw M1-B0 peak-location model fixed.

This is a second-look historical robustness study. A passing result can make the passage selector eligible for **M2-B shadow integration only**. A production hard gate still requires prospective confirmation.

## B modeling population

The canonical archive is unchanged. Modeling eligibility is explicit in:

`artifacts/v3-joint-timing-contract-v2/modeling_eligibility_v3.csv`

B exclusions:

- `2018-19`: no meaningful B activity / no meaningful B peak;
- `2019-20`: pandemic-transition season; retained for audit but excluded from all M1-B training, tuning, calibration, passage-policy selection and scoring.

The remaining B timing seasons are:

- 2012-13
- 2013-14
- 2014-15
- 2016-17
- 2017-18
- 2022-23
- 2023-24
- 2024-25
- 2025-26

Chronological outer scoring begins once at least four prior eligible B seasons exist. The scored outer seasons are therefore:

- 2017-18
- 2022-23
- 2023-24
- 2024-25
- 2025-26

## Fixed components

- raw M1-B0 peak-location mechanics from `PAGe/R/m1_v2.R`;
- B amplitude grid `0.005:0.005:0.25`;
- candidate step `0.1`;
- peak max-future horizon `16` weeks for the raw B0 benchmark;
- passage candidate step `0.2`;
- passage max-future horizon `12` weeks;
- causal B activity marker from the timing contract;
- chronological expanding-window folds;
- no changes to frozen `PAGe/R` code.

## Operational M1-B state

M1-B exposes exactly three states:

1. `inactive_no_timing_event`
2. `active_unconfirmed`
3. `confirmed`

Only `confirmed` may later act as a positive passage gate. `inactive_no_timing_event` and `active_unconfirmed` must never be interpreted as equivalent to a positive gate.

## Policy family

Keep the existing `m1_v2_passage_decision()` evidence structure.

Candidate grid:

- `high_threshold`: `0.95, 0.975, 0.99`
- `low_threshold`: `0.10, 0.20, 0.30, 0.40, 0.50`
- `drop_fraction`: `0.03, 0.05, 0.08, 0.10, 0.12`
- `fast_drop_fraction`: `0, 0.03, 0.05, 0.08, 0.10`
- `min_post_activation`: `3, 4, 5, 6`

`high_threshold=0.99` is treated as the hard ceiling. Edge flags must be recorded for all selected parameters.

## Activation uncertainty

For each inner held-out training season, construct passage histories under activation shifts:

- `-1`
- `0`
- `+1`

Both integer activation origin and decimal activation are shifted consistently.

The same raw B timing library is used because library fitting does not consume activation. All passage histories and policy scoring are recomputed under each activation shift.

## Deterministic robust policy selection

For candidate policy `q` and shift `s in {-1,0,+1}`, define across inner held-out seasons:

- `FE_s(q)`: number of seasons confirmed before `truth_confirm`;
- `EW_s(q)`: total false-early weeks, `sum(max(0, truth_confirm-confirm_origin))`;
- `MISS2_s(q)`: number of seasons with no confirmation by `truth_confirm+2`;
- `PDELAY_s(q)`: total penalized delay, where `delay=max(0, confirm_origin-truth_confirm)` and an unconfirmed season is assigned `7` weeks.

Aggregate keys:

- `worst_shift_n_false_early = max_s FE_s`
- `worst_shift_early_weeks_total = max_s EW_s`
- `all_shift_n_false_early = sum_s FE_s`
- `all_shift_early_weeks_total = sum_s EW_s`
- `worst_shift_n_miss_by_peak2 = max_s MISS2_s`
- `all_shift_n_miss_by_peak2 = sum_s MISS2_s`
- `worst_shift_penalized_delay_total = max_s PDELAY_s`
- `all_shift_penalized_delay_total = sum_s PDELAY_s`

Lexicographic selection order:

1. `worst_shift_n_false_early`
2. `worst_shift_early_weeks_total`
3. `all_shift_n_false_early`
4. `all_shift_early_weeks_total`
5. `worst_shift_n_miss_by_peak2`
6. `all_shift_n_miss_by_peak2`
7. `worst_shift_penalized_delay_total`
8. `all_shift_penalized_delay_total`
9. higher `high_threshold`
10. larger `fast_drop_fraction`
11. larger `drop_fraction`
12. larger `min_post_activation`
13. higher `low_threshold`

These keys give a deterministic total ordering.

### Inner feasibility veto

A selected outer-fold policy is not passage-eligible if:

`inner_worst_shift_n_false_early > 0`.

The selected row must also report inner miss rate and edge flags.

## Outer replay

For each eligible outer test season:

1. use only strictly earlier B-eligible seasons;
2. exclude 2018-19 and 2019-20 regardless of calendar position;
3. fit the raw B timing library;
4. build inner cross-fitted passage histories under `-1/0/+1` activation shifts;
5. select and freeze one robust passage policy;
6. replay the outer season with nominal activation;
7. separately replay outer activation `-1` and `+1` with the **same frozen library and selected policy**.

Outer activation sensitivity does not retrain the policy.

## Replay and scoring horizon

Runtime replay must continue through `max(heldout_weekF)` and must not stop at a horizon defined from retrospective truth.

Truth is used only for scoring.

For a season with decimal B peak `T`:

`truth_confirm = ceiling(T)-1`.

Scoring censors timeliness at `truth_confirm+6`; if unconfirmed by then, assign penalized delay `7`.

`confirmed_by_peak2` means exactly:

`confirm_origin <= truth_confirm + 2`.

## No-event handling

2018-19 remains excluded from B timing fitting/scoring.

Required causal check:

- replay the causal B activity detector on every 2018-19 prefix through the 8-40 activity window;
- verify it never activates;
- output operational state `inactive_no_timing_event` throughout;
- generate no positive passage confirmation.

Also preserve the existing inactive-season exclusion perturbation test: materially perturbing 2018-19 B observations must not change later eligible fold libraries, predictions or selected passage policies.

A pseudo-activation replay on 2018-19 may be reported as a non-veto diagnostic only.

## Existing-policy and sustained-only comparisons

### Existing selector comparison

Reproduce the existing nominal B passage rows exactly where the same modeling population applies:

- `confirm_origin`
- branch
- policy values

At shift 0, also verify the script evaluator matches `fit_m1_v2_passage_policy()$evaluation` on the frozen sub-grid.

### Sustained-only diagnostic

Use the selected robust policy's sustained parameters but disable the fast branch by setting:

- `high_threshold = 1`
- `fast_drop_fraction = 1`

Assert no decision uses branch `high_posterior_decline`.

This is diagnostic only and is not separately tuned.

## Leakage/integrity tests

Required:

1. strict outer fold isolation;
2. strict inner fold isolation;
3. future-observation perturbation invariance for outer activation `-1/0/+1`;
4. outer peak-truth perturbation changes scoring only, never predictions or passage decisions;
5. exact raw B0 nominal posterior reproduction;
6. deterministic repeated policy selection;
7. no-event prefix replay for 2018-19;
8. inactive-season exclusion perturbation check;
9. 2019-20 absent from every B training, tuning and scoring ledger;
10. source hashes and plan hash recorded before execution;
11. no frozen `PAGe/R` modifications;
12. unexpected empty histories/numerical failures captured in `failures.csv`.

## Acceptance criteria

The primary outer population is the five scored seasons:

- 2017-18
- 2022-23
- 2023-24
- 2024-25
- 2025-26

`historically_promising_second_look = TRUE` only if all conditions hold:

- every outer fold passes the inner feasibility veto;
- nominal outer false-early seasons = `0/5`;
- activation `-1` outer false-early seasons = `0/5`;
- activation `+1` outer false-early seasons = `0/5`;
- at least `4/5` nominal seasons confirm by `truth_confirm+2`;
- nominal median penalized delay <= `2` weeks;
- nominal mean penalized delay <= `2.5` weeks;
- all leakage/integrity checks pass;
- no unexpected replay failures.

Even `0/5` false-early has substantial statistical uncertainty because the sample is small; therefore a passing result is shadow-eligible only.

## Outputs

Write only to:

`artifacts/v3-m1-b-passage-robustness-v2-pandemic-excluded/`

Required files:

- `outer_fold_ledger.csv`
- `selected_policy_by_outer_fold.csv`
- `policy_scores_by_outer_fold.csv`
- `inner_passage_history.csv`
- `outer_passage_by_season.csv`
- `outer_activation_sensitivity.csv`
- `comparison_existing_policy.csv`
- `sustained_only_diagnostic.csv`
- `no_event_prefix_check.csv`
- `inactive_exclusion_perturbation_check.csv`
- `future_perturbation_checks.csv`
- `truth_perturbation_checks.csv`
- `raw_B0_reproduction_checks.csv`
- `failures.csv`
- `acceptance_criteria.csv`
- `overall_verdict.csv`
- `source_manifest.csv`
- `benchmark_config.csv`

## Decision

If accepted:

- raw M1-B0 remains the B peak-location model;
- this robust passage policy becomes eligible for M2-B **shadow** integration only.

If rejected:

- raw M1-B0 remains peak-location-only;
- hard M1-B passage gating is stopped;
- M2-B must use continuous timing uncertainty or no timing gate rather than another threshold search.
