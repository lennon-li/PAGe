> **SUPERSEDED — HISTORICAL EXPERIMENTAL WEEKF3 POLICY.** Current canonical minimum origin is weekF12. See [the current canonical stack](v3-current-canonical-stack-2026-09-28.md).

# PAGe v3 early-origin shadow release disposition

Date: 2026-09-28
Status: shadow-only prospective release candidate

## Decision

Replace the previous weekF13 forecast-issuance gate with a data-support rule: issue forecasts whenever the strict typed panel contains three consecutive weekly observations through the exact origin.

This is a support-contract change, not a fitted-model change and not an ignition-policy change.

## Unchanged model decisions

- A/M0 ignition parameters remain frozen, including fallback `w_min=12`.
- A/M1 remains frozen M1-v2.
- A +1/+2 remain exact A1 state forecasts.
- B activity detection remains weekF 8-40.
- B/M1 remains v9.
- B +1 remains exact B1.
- B +2 remains posterior-C2 only when causal timing is available; otherwise exact B1.
- Hard B passage remains forbidden.
- All outputs remain shadow-only and `production_eligible=FALSE`.

## Evidence

Strict chronological replay admitting origins whenever at least three observations exist adds weekF3-12 origins without changing fold chronology or training data.

Early-origin-only state performance:

- A +1 MAE: 0.4178 pp across 8 scored seasons.
- A +2 MAE: 0.4184 pp across 8 scored seasons.
- B +1 MAE: 0.1368 pp across 7 scored seasons.
- B +2 state/fallback MAE: 0.1507 pp across 7 scored seasons.
- B timing activations before weekF13: 0.

Expanded B chronological replay retains the accepted later timing correction benefit. A timing correction remains not promoted. A determinism replay passes.

The current 2026-27 weekF11 panel produces finite state forecasts under the relaxed rule while B timing remains unavailable:

- A +1: 1.67726744%
- A +2: 1.66785435%
- B +1: 0.03120795%
- B +2: 0.03246380% (exact B1 fallback)

## Versioning

The previous content-addressed release remains historical evidence and is not mutated. The relaxed contract is delivered by newly versioned M2-B helper/artifact, combined runner, standalone B runner, transaction launcher, tests, and a new content-addressed release family.
