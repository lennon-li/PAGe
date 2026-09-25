# M2-v2 live-format shadow — 2026-27 weekF11

## Source and refresh policy

This refresh deliberately rebuilds the entire current-season A/B weekly panel rather than appending weeks 10-11 to the weekF09 cache.

The AgentPorter sandbox cannot currently resolve PHO's `ws1.publichealthontario.ca` raw-download host directly. The weekF11 input therefore comes from the local OLIS snapshot used by the IRVRI 2026-27 week-11 forecasting run:

`IRVRI/wf_output/olis_snapshot/hist_olis.RData`

That snapshot was built by `IRVRI/scripts/build_olis_snapshot.R` from the latest OLIS weekly extract and replaces all OLIS-covered weeks from the extract's first week onward. It therefore carries retrospective revisions rather than only newly appended weeks.

Artifacts:

`artifacts/m2-v2-live-shadow-2026-27-week11/`

## Retrospective revisions versus the Sep 18 ORVT cache

Comparing refreshed weeks 1-9 to the Sep 18 ORVT cache:

- Influenza A counts/denominators changed in 6 of 9 weeks.
- Influenza B counts/denominators changed in 6 of 9 weeks.
- Most changes were denominator revisions of 1-2 tests.
- WeekF09 had a material A revision: 73/5685 (1.2841%) -> 78/5905 (1.3209%).
- WeekF09 B changed from 3/5626 (0.0533%) -> 3/5843 (0.0513%).
- Maximum absolute A positivity revision over weeks 1-9 was 0.0368 percentage points.
- Maximum absolute B positivity revision was 0.0020 percentage points.

The full row-level audit is in:

`retro_revision_audit_week01_09.csv`

## Refreshed observed state

WeekF10 (week starting 2026-09-06):

- A: 112 / 6060 = 1.8482%
- B: 1 / 5989 = 0.0167%

WeekF11 (week starting 2026-09-13):

- A: 115 / 6599 = 1.7427%
- B: 2 / 6530 = 0.0306%

## Governed M2-v2 weekF11 shadow

No A timing handoff is yet bound into the current shadow kit, so A remains on the state/growth baseline. B remains before the minimum timing-gate week 18 and the operational B +2 gate is closed.

| type | horizon | stabilized current % | shadow forecast % | C2 applied | reason |
|---|---:|---:|---:|---|---|
| A | +1 | 1.7500 | 1.6773 | no | A timing unavailable |
| A | +2 | 1.7500 | 1.6679 | no | A timing unavailable |
| B | +1 | 0.0383 | 0.0307 | no | B +1 baseline-only policy |
| B | +2 | 0.0383 | 0.0317 | no | B gate closed / pre-gate |

## WeekF09 forecast scoring after refreshed truth arrived

The refreshed weekF10/weekF11 observations allow the prior weekF09 shadow to be scored.

Original weekF09 stale-cache forecast vs refreshed realized truth:

- A +1 absolute error: 0.0571 pp.
- A +2 absolute error: 0.0384 pp.
- B +1 absolute error: 0.0353 pp.
- B +2 absolute error: 0.0230 pp.

If weekF09 is recomputed using the retrospectively revised history, its forecasts change by about +0.083 pp for A and -0.0028 pp for B. This improves A +1 error to 0.0261 pp but worsens A +2 error to 0.1211 pp; B +1/+2 errors improve slightly.

This illustrates why each weekly shadow run must archive the exact vintage used at forecast time. Retrospective revised-data scoring and as-issued real-time scoring answer different questions and must remain separate.

## Next step

Build the current-season A M0/M1-v2 shadow stage using training seasons only through 2025-26, then rerun weekF11. If A remains pre-ignition, the current baseline-only forecast is confirmed. If governed M1-v2 timing becomes available, the A C2 correction can be exercised prospectively while legacy production remains unchanged.

## M0/M1-v2 shadow policy update — 2026-09-25

The current shadow timing stack has since been rebuilt with the promoted M0-v2 policy:

- classifier explicitly disabled (`use_cls = FALSE`);
- earliest calendar eligibility moved from week 13 to week 12;
- a three-week raw-positivity persistence window (`raw_nondec_n = 3`);
- each week-to-week decline is tolerated when it is no larger than **1 standard error** of the difference between the two weekly binomial positivity estimates (`raw_drop_se_tol = 1.0`);
- otherwise the validated 36-spec M0-v2 threshold family is unchanged.

Strict LOSO M0-v2 performance is unchanged from the prior validated detector (fractional MAE 0.366 weeks; zero >1-week false-early detections), and all 11 held-out ignition dates are exactly unchanged. The downstream governed M1-v2 replay is evaluated separately under the same final M0 artifact.

At the refreshed weekF11 origin, all four original non-classifier evidence votes pass. The weekF10-to-weekF11 decline is only -0.446 SE, so the new noise-tolerant persistence safeguard also passes. Ignition remains false solely because week 11 is before the new week-12 eligibility boundary. Week 12 is therefore the earliest possible ignition week if the epidemiologic evidence remains active and the next weekly decline, if any, is no larger than the 1-SE tolerance. The final full-history M1-v2 shadow stage trained only through 2025-26 is stored at `artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/` and returns a pre-ignition M2 handoff at weekF11.
