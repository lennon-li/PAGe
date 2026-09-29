# V3 M1-B season inclusion policy

Date: 2026-09-26
Status: active for v3 B-specific M1/M2 research

## Policy

The canonical surveillance panel remains unchanged and retains all historical seasons for provenance and audit.

For **v3 B-specific M1/M2 modeling**, season `2019-20` is excluded from:

- B peak-timing model fitting;
- B passage-policy fitting/selection;
- B chronological benchmark scoring;
- B activation-robustness scoring;
- any M2-B timing-gate training derived from M1-B;
- v3 M2-B state-model fitting;
- v3 M2-B chronological forecast scoring and model selection.

Reason: `pandemic_transition`.

The season is retained in source/canonical artifacts and may be shown descriptively, but it has zero model-selection weight.

Season `2018-19` remains a separate explicit `no_meaningful_B_activity / no_meaningful_B_peak` season and is not converted into a finite B peak target.

For v3 M2-B, season `2018-19` remains eligible for **state-only** forecasting/training, but its timing correction is forced to exactly zero.

The 2019-20 exclusion applies only to v3 B-specific modeling. It does not retroactively alter frozen v2 metrics or A-specific truth/artifacts. Because the v3 M2-B state baseline excludes 2019-20, its B1 metrics are a new v3 benchmark and must not be numerically compared as if they were the reviewed M2-v2 B1 benchmark.
