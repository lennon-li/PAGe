# V3 M1-B final disposition — pandemic-excluded

Date: 2026-09-26
Status: frozen research/shadow candidate for B peak timing; governed hard-passage interface closed

## Season policy

For M1-B, `2019-20` is excluded from all B timing fitting, policy selection, and scoring as `pandemic_transition`.

The canonical panel retains the season for provenance/audit. This is a B-specific exclusion and does not alter frozen v2 or A-specific historical artifacts.

`2018-19` remains an explicit `no_meaningful_B_activity / no_meaningful_B_peak` season.

Source policy:

`docs/v3-m1-b-season-policy-2026-09-26.md`

## Frozen M1-B architecture

M1-B is split into peak-location inference and passage uncertainty.

### Peak location — accepted shadow baseline

Use raw M1-B0:

- `fit_m1_v2_library()` from frozen `PAGe/R/m1_v2.R`;
- `m1_v2_peak_posterior()` from frozen `PAGe/R/m1_v2.R`;
- B amplitude grid `0.005:0.005:0.25`;
- runtime candidate step `0.1`;
- runtime `max_future_weeks = 16`;
- retrospective B peak truth from the reproducible v3 timing contract;
- B activity marker as the causal activation coordinate;
- no scalar bias calibration;
- no A-conditioned lag correction.

Chronological pandemic-excluded benchmark:

`artifacts/v3-m1-b0-excluding-pandemic-v1/`

Five scored outer seasons:

- 2017-18
- 2022-23
- 2023-24
- 2024-25
- 2025-26

Headline results:

- season-balanced MAE: `1.6573` weeks;
- season-balanced early-weighted MAE: `1.6580` weeks;
- season-balanced bias: `+1.5157` weeks (late);
- mean 90% interval coverage: `0.80`;
- worst-season MAE: `5.3225` weeks.

Four of five scored seasons have season MAE <= about `1.39` weeks. The major known failure is 2022-23, a late/low-amplitude B season with very little post-activation pre-peak information.

The late bias and 2022-23 miss are retained as known prospective-monitoring limitations. No additional historical bias correction or recalibration is allowed on these same seasons.

### Passage — continuous uncertainty only

Historical hard-threshold searching is closed. Binary passage decisions are forbidden through the governed M1-B helper interface. The lower-level frozen `m1_v2_passage_decision()` function remains an internal dependency of the broader v2 codebase and is not an approved M1-B/M2-B runtime API.

Existing pandemic-excluded selector:

`artifacts/v3-m1-b-passage-excluding-pandemic-v1/`

Activation-robust second-look study:

`artifacts/v3-m1-b-passage-robustness-v2/`

After excluding 2019-20:

- false-early seasons at activation shift `-1`: `0/5`;
- false-early seasons at nominal activation: `0/5`;
- false-early seasons at activation shift `+1`: `0/5`;
- nominal confirmed by peak+2: `2/5`;
- nominal mean delay penalty: `2.2` weeks;
- nominal median delay penalty: `3` weeks.

The 1,500-policy activation-robust grid did not improve nominal timeliness over the existing selector and was slower under activation `+1` sensitivity.

Further retrospective threshold tuning is stopped because the predeclared activation-robust study failed its timeliness criteria and this historical sample has already been inspected repeatedly.

Predeclared second-look verdict:

`historically_promising_second_look = FALSE`

### Allowed passage use

`m1_v2_passage_posterior()` may be computed as continuous shadow uncertainty.

Allowed downstream uses:

- `prob_peak_passed` as a continuous M2-B covariate/weight;
- posterior mixture or uncertainty weighting;
- shadow diagnostics;
- prospective monitoring.

Disallowed until prospective evidence:

- calling a binary passage decision through the governed M1-B/M2-B path;
- binary hard M2-B passage gate;
- production switch based on B passage confirmation;
- another retrospective B passage threshold search on the same historical seasons.


## Frozen shadow artifact

Current serialized artifact:

`artifacts/m1-b-v3-peak-v8/m1_b_v3_peak_artifact.rds`

Governed runtime helper:

`scripts/v3_m1_b_runtime_helpers_v7.R`

The validator requires the fitted library training seasons to exactly match artifact metadata, explicitly rejects 2019-20 and 2018-19 from the fitted library, and rejects any artifact that enables scalar calibration, A-conditioning, or a governed hard passage decision.
It also pins the governed runtime settings (`peak step=0.1`, `peak horizon=16`, `passage step=0.2`, `passage horizon=12`) and requires `hard_gate_eligible` to be exactly `FALSE`.

## M1-B operational state contract

M1-B exposes three conceptual states:

1. `inactive_no_timing_event`
2. `active_unconfirmed`
3. `confirmed_shadow_only`

These states are descriptive during v3 shadow evaluation.

Neither `inactive_no_timing_event` nor `active_unconfirmed` may be interpreted as an asserted pre-peak state. `confirmed_shadow_only` is not a binding M2-B gate.

## 2018-19 no-event contract

Causal prefix replay of the B activity detector over every prefix in weekF `8-40` produced no activation.

When activity is not detected:

- do not call the M1-B peak/passage runtime;
- emit `inactive_no_timing_event`;
- emit no positive timing gate.

Perturbing all 2018-19 B observations leaves subsequent M1-B training folds, libraries, inner histories, policies, and held-out paths unchanged.

## 2019-20 pandemic-transition exclusion checks

The season is absent from all M1-B training/scoring folds in the pandemic-excluded benchmark.

Perturbing all 2019-20 B observations leaves all later M1-B fold digests, libraries, inner histories, selected policies, and held-out paths unchanged.

## Evidence limitations

- This remains historical research with only five scored post-minimum-training seasons.
- B activity-rule parameters and B amplitude support were selected with knowledge of the historical archive.
- The passage-hardening exercise is explicitly a second historical look.
- The 2022-23 B peak remains a material peak-location failure.
- Prospective 2026-27 evidence is required before production promotion.

## Frozen M1-B decision

For v3 shadow development:

- **M1-A:** frozen M1-v2.
- **M1-B peak location:** raw pandemic-excluded M1-B0.
- **M1-B scalar calibration:** stopped.
- **M1-B A-conditioned lag model:** stopped.
- **M1-B hard passage gate:** stopped.
- **M1-B continuous peak/passage posterior:** allowed as shadow uncertainty.
- **M1-B no-event handling:** explicit inactive state.
- **M1-B training:** excludes 2019-20 and 2018-19; 2018-19 remains the no-event audit season.

The next downstream experiment may evaluate M2-B with either no timing input or continuous M1-B timing uncertainty. It must not use a retrospectively tuned hard B passage gate.
