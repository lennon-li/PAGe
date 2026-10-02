> **SUPERSEDED — HISTORICAL EXPERIMENTAL WEEKF3 POLICY.** Current canonical minimum origin is weekF12. See [the current canonical stack](v3-current-canonical-stack-2026-09-28.md).

# PAGe v3 early-origin shadow runtime contract

Date: 2026-09-28
Status: superseded historical experiment

## Purpose

Replace the arbitrary weekF13 forecast-issuance gate with a data-support rule. This change does not alter fitted model parameters, A/M0 ignition policy, M1-A, M1-B, B activity detection, M2-A routing, or M2-B timing/C2 routing.

## Forecast support

A forecast origin is supported when the strict typed weekly panel contains at least three consecutive observations through the exact origin: `origin-2`, `origin-1`, and `origin`.

There is no epidemiologic calendar-week minimum for state forecast issuance. Before three-week support, all four A/B +1/+2 rows are `not_issued` with reason `insufficient_state_history`.

## Ignition/timing are independent

- Frozen A/M0 parameters remain unchanged, including `w_min=12` for fallback ignition logic. Core/raw ignition semantics remain unchanged.
- B causal activity detection remains unchanged with window weekF 8-40.
- A +1/+2 remain exact A1 state forecasts and never use timing/C2.
- B +1 remains exact B1 state forecast.
- B +2 uses posterior-C2 only when the unchanged causal B activity detector and M1-B posterior are available; otherwise it equals exact B1 fallback.
- No hard passage gate is introduced.

Thus forecast issuance does not imply ignition. Pre-ignition state forecasts are allowed while timing remains unavailable.

## Evidence

Strict chronological early-origin replay removes only the prior `weekF >= 13` scoring filter while preserving fold chronology, prior-season training, perturbation/leakage tests, model fits, routes, and timing rules.

Newly admitted weekF3-12 origins:

- A state +1 MAE: approximately 0.418 percentage points across 8 scored seasons.
- A state +2 MAE: approximately 0.418 percentage points across 8 scored seasons.
- B state +1 MAE: approximately 0.137 percentage points across 7 scored seasons.
- B state +2 MAE: approximately 0.151 percentage points across 7 scored seasons.
- B timing activations before weekF13: 0.

Expanded B chronological evaluation retains the accepted +2 timing correction benefit at later active origins. A remains state-only because the timing challenger still does not meet its promotion criterion.

Evidence directories:

- `artifacts/v3-m2-a-early-origin-support-v1/`
- `artifacts/v3-m2-a-early-origin-support-v1-determinism/`
- `artifacts/v3-m2-b-early-origin-support-v1/`

## Versioning

The existing content-addressed release `17eec173e218042146b3ddb775699cf522b4e8075743102de869344e9f0ef57e` remains immutable and retains the weekF13 issuance contract.

The relaxed rule is delivered only through newly versioned M2-B helper/artifact, combined runner, standalone B runner, and a new content-addressed shadow release.

All outputs remain shadow-only and `production_eligible=FALSE`.
