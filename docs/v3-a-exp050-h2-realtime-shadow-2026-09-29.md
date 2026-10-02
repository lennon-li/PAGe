# V3 A+2 EXP050 real-time shadow option — 2026-09-29

## Disposition

**Implemented as an optional API-side challenger. Canonical v3 A routing remains exact A1 for +1 and +2.**

The weekly API accepts:

- `a_shadow_option = "off"` — default, no challenger;
- `a_shadow_option = "exp050_h2"` — compute the experimental A+2 challenger after the canonical transaction succeeds.

The challenger is never substituted into the four canonical forecast rows, is never used by M0/M1/B routing, and is not used by the canonical positivity probability calibrator.

## Why +2 only

The leakage-free fixed-A1-form nested LOSO was rerun with `min_origin_week = 12` so the challenger is evaluated on the same earliest origin supported by canonical v3.

At +1, the paired one-SE selector chose OFF in 10/11 outer folds and the governed nested policy worsened MAE by about 2.1%. Therefore the API does not expose an A+1 N-history challenger.

At +2:

- EXP050 selected in 8/11 outer folds;
- EXP025 selected in 3/11;
- OFF selected in 0/11;
- OFF season-balanced MAE: 2.033645 percentage points;
- nested season-balanced MAE: 2.003085 percentage points;
- relative MAE gain: 1.5027%;
- season-balanced loss improved by 0.3493%;
- loss improved in 8/11 outer seasons;
- MAE improved in 6/11 outer seasons.

This is consistent enough to justify prospective shadow collection, but the magnitude is below the prior promotion threshold. The option is therefore deliberately `experimental_shadow` and `production_eligible = FALSE`.

Evidence directory:

`artifacts/m2-a-ntrend-fully-nested-loso-wmin12-v1/`

## Frozen challenger

Artifact:

`governance/v3_a_exp050_h2_shadow_v1.rds`

Artifact ID:

`a15bf7d814b4cb96b1b0f4d95f1a46f764ae0a9697010311adc109c0af327bc5`

The challenger is an **A1-form re-fit with an EXP050 test-volume term**. It does not hold the canonical A1 coefficients fixed. The fitted model is:

`cbind(y_target, N_target-y_target) ~ horizon_f + growth1 + growth2 + exp050 + offset(logit_current)`

with frozen coefficients:

- intercept: -0.09980471002947
- +2 horizon effect: -0.00851712250326
- `growth1`: 0.28506878154728
- `growth2`: 1.00355500035068
- `exp050`: -1.32334867972453

`EXP050` is calculated causally from exact test-volume history through the forecast origin:

- `d1 = log(N_t) - log(N_t-1)`
- `d2 = log(N_t-1) - log(N_t-2)`
- `d3 = log(N_t-2) - log(N_t-3)`
- `d4 = log(N_t-3) - log(N_t-4)`
- `EXP050 = (d1 + 0.5*d2 + 0.25*d3 + 0.125*d4) / 1.875`

The runtime rejects origins before weekF12 and rejects any prefix missing an exact week among `t-4,...,t`.

## API contract

Existing clients are unchanged. Omitting `a_shadow_option` is equivalent to `off`.

Default request:

```json
{"season":"2026-27","expected_release_id":"5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b"}
```

Challenger request:

```json
{"season":"2026-27","expected_release_id":"5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b","a_shadow_option":"exp050_h2"}
```

The option participates in the immutable request digest. Reusing an idempotency key with a different option is therefore rejected as a different request.

After the canonical weekly transaction succeeds, the worker creates a private, SHA-bound `a_shadow_snapshot.rds`. A successful result adds an `a_shadow` projection containing:

- canonical A+2 route and forecast;
- challenger A+2 forecast;
- percentage-point delta;
- current EXP050/growth features and N history;
- frozen artifact identity and historical evidence;
- `canonical_unchanged = true`.

If challenger generation or validation fails, the canonical run still succeeds and `a_shadow.status` is `unavailable`.

## Current 2026-27 application

The newest local operational OLIS snapshot available during this audit contains influenza A/B observations through 2026-09-19, which resolves to **weekF11**:

- A weekF11: 115 / 6599 = 1.7426883%;
- B weekF11: 2 / 6530 = 0.0306279%.

Canonical v3 has `w_min = 12`, so the current governed result is correctly `issued = FALSE`; there is no legitimate current A+2 canonical forecast and therefore no legitimate challenger delta yet.

For context only, the current weekF11 A test-volume history over weeks 7-11 is:

`5586, 5433, 5905, 6060, 6599`

which gives `EXP050 = 0.06161013`. This is **not** converted into a forecast because weekF11 is outside the validated challenger support.

The environment could not reach the live PHO ORVT endpoint (`Couldn't resolve host name`), so no fresher weekF12 source was substituted. The next valid prospective comparison should occur when a governed source supplies weekF12 (2026-09-20 through 2026-09-26).

A retained synthetic/governed weekF12 transaction was used only as an integration fixture. Its test volume is deliberately constant, so its numeric challenger delta is not interpreted as a real surveillance result.

## Tests

Targeted tests cover:

- frozen artifact identity/release binding;
- weekF12 support boundary;
- exact causal `t-4,...,t` construction;
- missing-week rejection;
- future-observation invariance;
- canonical A1 forecast preservation;
- OFF default and explicit `exp050_h2` request parsing;
- option-sensitive idempotency digests;
- run-bound snapshot SHA/schema validation;
- canonical A+2 parity;
- tampered snapshot fail-closed behavior without invalidating canonical forecasts.

## Interpretation

The API option is intended to collect prospective evidence, not to bypass retrospective model qualification. The existing fixed-A1-form nested LOSO remains the historical justification for carrying the challenger. The separately proposed broader full-M2 nested LOSO still requires strict pair/triple-excluded M1 cross-fitting before it can produce valid evidence.
