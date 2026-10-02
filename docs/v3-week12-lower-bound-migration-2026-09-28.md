# PAGe v3 unified weekF12 lower-bound migration

## Decision

The canonical v3 shadow policy uses weekF12 as the minimum forecast origin.
M0-A retains `w_min=12`; the transferred B activity detector now records the
window as 12–40; M2-B requires `origin_weekF >= 12` and exact observations at
`origin-2:origin`. The three-observation rule remains a secondary data
sufficiency requirement and does not replace the explicit origin floor.

Ignition/timing eligibility and forecast issuance remain separate concepts.
They happen to share a lower bound of 12 in this release, but the detector
window does not itself authorize a forecast and the forecast-origin rule does
not manufacture timing availability.

All components remain `shadow_only_prospective_research`, with
`production_eligible=FALSE`. Model coefficients, training seasons, posterior
routing, A1/B1 state routes, the conditional C2 route, and lower-bound
monitoring are unchanged. The 2018-19 no-event treatment and 2019-20 pandemic
exclusion are unchanged.

## Superseded chains

- The B detector labeled 8–40 and the weekF13 forecast floor are superseded by
  the versioned 12–40 detector and explicit weekF12 issuance floor.
- The experimental early-origin, data-support-only policy that admitted
  origins from weekF3 is rejected as canonical policy. Its artifacts remain
  historical evidence and are not deleted.
- Prior accepted files and release directories remain inspectable and are not
  edited in place.

## WeekF12 support evidence

The deterministic machine summary is
`governance/v3_week12_support_summary_v1.csv`, derived only from the existing
`per_origin_predictions.csv` evidence. At origin weekF12:

| Component | Horizon | Seasons | MAE (percentage points) |
|---|---:|---:|---:|
| A | +1 | 8 | 0.2468658 |
| A | +2 | 8 | 0.3272633 |
| B | +1 | 7 | 0.1549206 |
| B | +2 | 7 | 0.1548968 |

B timing activations at weekF12 are 0. Consequently, B+2 at weekF12 is the
exact B1 fallback. These results are a support check only; they are not a
promotion decision and do not establish accuracy beyond the evaluated replay.

## Canonical versioned chain

- `artifacts/v3-b-activity-window12-40-v1/`
- `artifacts/v3-joint-timing-contract-v4/`
- `artifacts/m1-b-v3-peak-v10/`
- `artifacts/m2-b-v3-shadow-v5/`
- `2026/run_weekly_shadow_v3_week12_v1.R`
- `2026/run_weekly_m2_b_shadow_v5.R`
- `2026/run_weekly_shadow_release_v5.R`
- `artifacts/v3-shadow-release-v3/<release_id>/`

At weekF11 the combined runner emits four non-issued rows with reason
`not_in_validated_window_before_weekF12`. At weekF12 it emits finite A+1/A+2
using exact A1, finite B+1 using exact B1, and B+2 using exact B1 fallback when
timing is unavailable. No live weekF12 panel is fabricated; weekF12 execution
tests extend the current 2026-27 typed-panel shape only as an explicit fixture.
