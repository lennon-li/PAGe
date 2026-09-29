# V3 M1-B final disposition

Date: 2026-09-25
Status: frozen research candidate for peak location; hard passage gating closed

## Final M1-B architecture

M1-B is split into two concepts:

1. **Peak location:** accepted as raw M1-B0 using the frozen M1-v2 peak-library/posterior mechanics adapted to B amplitude support.
2. **Peak passage:** no hard gate is approved from historical data. Passage posterior probability may be carried forward only as continuous uncertainty/shadow information.

## Peak-location model frozen for shadow work

The accepted B peak-location mechanics are:

- `fit_m1_v2_library()` from frozen `PAGe/R/m1_v2.R`;
- `m1_v2_peak_posterior()` from frozen `PAGe/R/m1_v2.R`;
- B amplitude grid `0.005:0.005:0.25`;
- retrospective B peak truth from the reproducible v3 timing contract;
- training excludes seasons without meaningful B peak truth;
- runtime activation/activity state comes from the exploratory B activity marker, not a supervised B ignition truth;
- no scalar peak-location bias calibration is applied.

Chronological raw baseline:

- six eligible B test seasons;
- season-balanced MAE about `1.87055` weeks;
- early-weighted MAE about `1.84207` weeks;
- worst-season MAE about `5.27418` weeks;
- 2018-19 is explicitly outside B peak-timing scoring because it has no meaningful B activity/peak event under the current contract.

## Branches closed by historical evidence

### A-conditioned M1-B1

Closed. The additive A-to-B lag-convolution/shared-lag assumption was not supported robustly by historical geometry and the tested branch did not justify promotion.

### Scalar M1-B calibration

Closed. Corrected chronological evaluation produced worse primary all-season MAE and early-weighted MAE than raw M1-B0.

### Hard M1-B passage gate

Closed for further historical threshold searching.

The activation-robust 1,500-policy second-look study produced:

- nominal false-early seasons: `0/6`;
- nominal confirmed by peak+2: `3/6`;
- nominal median delay7: `2.5` weeks;
- nominal mean delay7: `2.33` weeks;
- activation `-1` sensitivity: one false-early season (2019-20, one week early);
- activation `+1` sensitivity: zero false-early seasons.

Predeclared verdict:

`historically_promising_second_look = FALSE`

Therefore no additional historical B passage threshold grid search is allowed. A new threshold search on the same six seasons would be a post-hoc third look rather than credible validation.

## Passage-posterior contract

`m1_v2_passage_posterior()` may still be computed as a continuous uncertainty measure.

Allowed downstream uses:

- shadow diagnostics;
- continuous covariate/input to an M2-B challenger if evaluated causally;
- posterior mixture/uncertainty weighting;
- prospective monitoring.

Disallowed until prospective evidence:

- binary hard M2-B gate;
- production decision rule that treats historical passage confirmation as governed;
- another retrospective threshold search designed to remove the inspected 2019-20 failure.

## M1-B operational states

M1-B exposes three timing states:

1. `inactive_no_timing_event`
2. `active_unconfirmed`
3. `confirmed_shadow_only`

Only the third represents a passage confirmation, and it remains non-binding/shadow-only during prospective evaluation.

`inactive_no_timing_event` and `active_unconfirmed` must not be interpreted as an asserted pre-peak state.

## 2018-19 no-event contract

Causal prefix replay through weeks 8-40 showed no B activity activation on all 33 prefixes.

When no B activity is detected:

- no M1-B peak/passage runtime call is required;
- no passage confirmation is emitted;
- state is `inactive_no_timing_event`.

2018-19 remains excluded from B timing-library fitting and timing scoring.

## Evidence status

The passage-hardening study is explicitly a second-look historical analysis because the policy family was designed after earlier B passage outcomes had been inspected.

Even a passing historical result would have been eligible only for shadow use. The actual result failed the predeclared criteria.

The full-history peak-location artifact created after this disposition is therefore a **shadow/research artifact**, not a governed production model.

## Known review caveats

- Selected robust passage policies often landed on conservative grid boundaries because many policies tied on the primary safety/timeliness keys and conservative tie-breaks preferred larger thresholds.
- Extending those thresholds further would make confirmations later and cannot repair the failed timeliness criteria.
- The sustained-only diagnostic cannot perfectly disable the fast branch through `m1_v2_passage_decision()` because posterior/drop values can equal 1. This diagnostic does not affect the negative passage verdict.
- The B activity rule/window and B amplitude support were selected with knowledge of the historical archive, so prospective evidence remains essential.

## Frozen M1-B decision

For v3 shadow development:

- **M1-A:** frozen M1-v2.
- **M1-B peak location:** raw M1-B0.
- **M1-B scalar calibration:** stopped.
- **M1-B A-conditioned lag model:** stopped.
- **M1-B hard passage gate:** stopped.
- **M1-B continuous passage posterior:** allowed as shadow uncertainty only.
- **M1-B no-event handling:** explicit three-state contract.

The next downstream step may evaluate M2-B with either no timing input or continuous M1-B timing uncertainty. It must not use a retrospectively tuned hard B passage gate.
