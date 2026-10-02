# V3 M2-B shadow runtime contract

Date: 2026-09-26
Status: frozen shadow-only runtime contract

## Scope

This contract packages the historically qualified v3 M2-B candidate for prospective shadow evaluation only.

It does not authorize production routing or replacement of frozen v2.

## Frozen routing

- Horizon +1: exact B1 state/growth forecast.
- Horizon +2: posterior-C2 forecast when causal M1-B timing is available; otherwise exact B1.
- No hard M1-B passage decision.
- No M1-B scalar calibration.
- No A-conditioned M1-B timing.

## Runtime domain

- `origin_week >= 13`.
- Horizons: `1` and `2` only.
- Current B input must contain a single season with `weekF`, positive tests `y`, total tests `N`, and positivity `p` (typed `y_B/N_B/p_B` aliases may be normalized by the helper).
- At least three observations through the origin are required to compute B1 growth features.

## Season policy used for the fitted artifact

- 2019-20 is excluded from B state training, B timing training and B shape training as `pandemic_transition`.
- 2018-19 is included in B state training but excluded from B timing/shape training as the historical no-timing-event season.
- A shapes may include 2019-20 under the unchanged A policy.

Historical season-specific exclusions do not imply future seasons are forced inactive; prospective seasons use the causal B activity detector.

## Fitted components

### B1 state model

Full-history fit on completed eligible B seasons through 2025-26, excluding 2019-20.

Formula:

`cbind(y_target, N_target-y_target) ~ horizon_f + growth1 + growth2 + offset(logit_current)`

Family: quasi-binomial.

Stabilization: `(y+0.5)/(N+1)`.

### M1-B timing

Use the frozen artifact:

`artifacts/m1-b-v3-peak-v8/m1_b_v3_peak_artifact.rds`

Call the continuous passage posterior only through:

`scripts/v3_m1_b_runtime_helpers_v7.R`

The helper pins:

- passage candidate step `0.2`;
- max future horizon `12` weeks;
- hard passage decisions forbidden.

### C2 shape library

Build from:

`artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv`

using v3 timing-contract retrospective peaks.

- normalized peak-aligned tau grid: `-8` to `+8` by `0.25`;
- pooled contribution: all eligible A shapes plus eligible B shapes;
- B-specific contribution: eligible B shapes only;
- C2 log-ratio: `0.5 * pooled median + 0.5 * B median`;
- state/shape logit blend eta: `0.5`.

Unsupported posterior candidates contribute exact B1.

## Causal B activation

Use the frozen transferred-A-rule B activity detector parameters, with runtime window:

- `w_min = 8`;
- `w_max = min(40, origin_week)`.

The detector sees only the current-season prefix through the forecast origin.

If activity is not detected, timing is unavailable and the forecast falls back exactly to B1.

## Lower-bound monitoring definition

For the passage posterior candidate grid `T` with probabilities `w`:

- `lower_bound = min(T)`;
- `lower_bound_mass = sum(w[T <= lower_bound + 0.2])`;
- `lower_bound_saturated = lower_bound_mass >= 0.9`.

This is a monitoring stratum only. It never changes the forecast.

## Required output diagnostics

Each runtime forecast must expose:

- `forecast`;
- `B1_forecast`;
- `horizon`;
- `timing_available`;
- `timing_reason`;
- `activity_week`;
- `prob_peak_passed`;
- `posterior_mean_peak`;
- `supported_mass`;
- `lower_bound_mass`;
- `lower_bound_saturated`;
- M1-B artifact/library ID/hash;
- M2-B artifact ID/hash.

## Runtime prohibitions

The helper must reject:

- horizon other than 1 or 2;
- origin before weekF 13;
- hard-passage routing;
- production/promoted status in the artifact;
- wrong M1-B artifact version/hash;
- modified fixed C2 weights/eta;
- modified lower-bound monitoring definition;
- artifacts whose B training/shape season policy includes 2019-20 or whose B timing shapes include 2018-19.

## Prospective evaluation

2026-27 forecasts are as-issued prospective evidence.

Score +2 separately for:

1. all issued forecasts;
2. timing-active forecasts;
3. lower-bound-saturated forecasts;
4. non-saturated timing-active forecasts;
5. exact-B1 fallback forecasts.

Do not retune this artifact from 2026-27 outcomes during the shadow period.
