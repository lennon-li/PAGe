# M2-v2 live-format shadow — 2026-27 weekF09

## Input provenance

This is the first M2-v2 run on the actual 2026-27 PHO ORVT operational feed rather than a retrospective reconstruction.

- season: `2026-27`
- origin: `weekF09`
- latest observation week end: `2026-09-05`
- ORVT cache retrieved: `2026-09-18T09:30:52Z`
- ORVT SHA-256: `f31f941548de5ca0336dd0bf946f1cb64e3a6c34e32becbceed333f9799382d5`
- source: PHO ORVT 2025-26 / 2026-27 lab-testing feed
- governed M2-v2 artifact: `m2v2g_e61427c696b16f7f23c6287bf684c0ff6e5fb9db11e379687d8a57fe9d13dd29`

The typed A/B panel is extracted from exact Ontario rows for `Influenza A` and `Influenza B`, so both use current ORVT type-specific denominators. No historical shared-denominator proxy is used for this live-format run.

Artifacts:

`artifacts/m2-v2-live-shadow-2026-27-week09/`

## Observed state through weekF09

At weekF09:

- Influenza A observed positivity = 73 / 5685 = 1.2841%.
- Influenza B observed positivity = 3 / 5626 = 0.0533%.
- stabilized current state used by M2-v2: A 1.2926%, B 0.0622%.

B is before the minimum gate week 18 and far below the 5% activity gate. The B gate status is therefore `insufficient_gate_history`.

No valid current A M1-v2 handoff is available in the frozen 2026-27 operational kit. This week-9 M2-v2 shadow therefore correctly treats A timing as unavailable. No C2 curve correction is applied to either type.

## Shadow forecasts

| type | horizon | stabilized current % | shadow forecast % | C2 applied | reason |
|---|---:|---:|---:|---|---|
| A | +1 | 1.2926 | 1.7911 | no | A timing unavailable |
| A | +2 | 1.2926 | 1.7811 | no | A timing unavailable |
| B | +1 | 0.0622 | 0.0520 | no | B +1 policy is baseline-only |
| B | +2 | 0.0622 | 0.0536 | no | B operational gate review closed / gate not yet eligible |

These are live-format shadow forecasts, not claims of realized predictive accuracy; their target weeks had not been observed in the cached data used for this run.

## Comparison with the frozen weekly operational run

The existing frozen 2026-27 weekF09 run completed successfully but wrote no M2 forecast rows at the latest origin. Its `forecast_h1h2.tsv` contains missing M1/M2 forecast values. The legacy `weekly_result.rds` likewise contains zero M2 prediction rows at the latest origin.

M2-v2 therefore provides a useful operational availability property even before timing becomes available: its state/growth baseline produces typed A/B +1/+2 shadow forecasts while preserving the rule that timing-dependent C2 corrections are disabled.

This is an availability observation, not yet evidence that the weekF09 numerical forecasts are more accurate than legacy M2, because legacy emitted no comparable forecast and future truth was not in this cache.

## Next operational requirement

Before later-season live shadowing can exercise the A C2 correction, construct and bind the current-season M1-v2 shadow stage using historical seasons through 2025-26 only. The production frozen kit must remain unchanged. The shadow kit should carry:

- governed current A M0/M1-v2 timing stage trained only on historical seasons;
- canonical governed M2-v2 C2 artifact;
- explicit typed A/B ORVT panel input;
- B +1 baseline-only policy;
- B +2 operational gate closed unless separately reviewed;
- exact fallback semantics when timing is unavailable or fails.
