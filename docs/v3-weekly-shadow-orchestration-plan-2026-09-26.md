> **HISTORICAL ORCHESTRATION PLAN.** This plan predates the weekF12 canonical migration. Current execution uses launcher v5 and release `5472d089…da853b`; pre-weekF12 origins are not issued. See `docs/v3-current-canonical-stack-2026-09-28.md`.

# V3 combined weekly shadow orchestration plan

Date: 2026-09-26
Status: audited design; APPROVE WITH FIXES incorporated; ready for implementation

## Objective

Create one weekly v3 shadow runner that emits the final frozen A/B routing from a single typed A/B surveillance vintage without changing any model decisions.

Final v3 routing:

- `A +1 = exact A1 state/growth forecast`
- `A +2 = exact A1 state/growth forecast`
- `B +1 = exact B1 state/growth forecast`
- `B +2 = posterior-C2 when causal M1-B timing is available, otherwise exact B1`

The combined runner is shadow-only and cannot authorize production use.

## Frozen component decisions

### A timing

- M0-A: frozen M0-v2 policy.
- M1-A: frozen M1-v2 artifact.
- M0-A/M1-A are executed for monitoring/provenance only.
- M2-A must not consume the M1-A timing handoff because the v3 M2-A timing challenger failed its predeclared historical promotion threshold.

Final A disposition:

`docs/v3-m2-a-final-disposition-2026-09-26.md`

### A state forecast

Use the exact A baseline contained in the frozen governed M2-v2 artifact:

`artifacts/m2-v2-c2-governed-v1/m2_v2_c2_governed_fit.rds`

Call the governed runtime with `a_handoff = NULL`, then require for A rows:

- `c2_applied == FALSE`
- `timing_used == FALSE`
- `pred_selected == pred_baseline` exactly

The B rows returned by this v2 call are ignored.

### B timing / forecast

Use:

- `artifacts/m1-b-v3-peak-v8/m1_b_v3_peak_artifact.rds`
- `artifacts/m2-b-v3-shadow-v2/m2_b_v3_shadow_artifact.rds`
- `scripts/v3_m2_b_runtime_helpers_v2.R`

Final B disposition:

`docs/v3-m2-b-final-disposition-2026-09-26.md`

Routing remains frozen:

- B +1 exact B1
- B +2 posterior-C2 if causal timing is available, otherwise exact B1
- no hard passage gate
- lower-bound saturation monitoring only

## Input and source vintage

Reuse the audited ingestion/archive helpers from:

`2026/run_weekly_shadow_v2.R`

The combined runner resolves the source exactly once and constructs one typed A/B panel. A and B forecasts must use that same in-memory panel and archived source hash.

Supported inputs:

- live ORVT
- OLIS fallback
- explicit raw input
- explicit typed-panel replay input for tests/reproducibility

The runner writes one `typed_ab_weekly.csv` and one revision audit per run.

## Validated forecast window

The combined v3 shadow contract starts at:

`weekF >= 13`

Before weekF 13:

- archive and validate data normally;
- emit explicit `not_in_validated_window_before_weekF13` status;
- do not issue A or B numerical forecasts.

This keeps A/B v3 issuance on one common validated window.

## Runtime sequence

For a valid origin:

1. Validate required artifacts and package manifests before reading live data.
2. Resolve/archive one source vintage and construct one typed A/B panel.
3. Run the frozen M0-A detector on the A prefix.
4. Run frozen M1-A timing for monitoring/provenance.
5. Run frozen governed M2-v2 with `a_handoff = NULL` and select only the A rows; assert exact baseline routing.
6. Run frozen M2-B v3 helper for B +1 and B +2 using the same panel.
7. Merge exactly four rows into one combined forecast contract.
8. Write component diagnostics, revision audit, source/artifact provenance and status.

## Combined forecast contract

One row per type/horizon:

- `season`
- `origin_weekF`
- `type`
- `horizon`
- `forecast`
- `forecast_pct`
- `state_baseline`
- `state_baseline_pct`
- `route`
- `timing_available`
- `timing_reason`
- `activity_week`
- `prob_peak_passed`
- `supported_mass`
- `lower_bound_mass`
- `lower_bound_saturated`
- `model_version`
- `artifact_id`

Expected routes:

- A1/A2: `exact_A1_state`
- B1: `exact_B1_state`
- B2 active: `posterior_C2`
- B2 fallback: `exact_B1_fallback`

## A monitoring outputs

Even though A timing cannot alter the forecast, preserve:

- M0-A signals/detection
- M1-A timing output/runtime object
- M1-A status/artifact ID

This preserves visibility into the full A timing stack without violating the final M2-A decision.

## B monitoring outputs

Preserve the M2-B diagnostics already required by its runtime contract:

- timing available/fallback reason
- causal activity week
- probability peak passed
- posterior mean peak
- supported posterior mass
- lower-bound mass
- lower-bound saturation flag
- M1-B/M2-B IDs/hashes

## Audited fail-closed additions

The pre-implementation audit required the following implementation details, which are part of the frozen orchestration contract:

- preflight is a hard barrier before any live/replay source resolver is called;
- M0-A, M1-A, governed M2-v2, M1-B and M2-B artifact hashes/identities are pinned and validated;
- the canonical M2-B package manifest itself has a pinned SHA-256 and every manifest dependency is re-hashed;
- typed-panel validation checks finite valid A/B counts, derived proportions, one season, unique contiguous weekF coverage, and date consistency when date columns are present;
- issued forecasts require exact `origin-2:origin` weekly support;
- exactly four type/horizon rows must be emitted at valid origins and every route has an explicit numerical postcondition;
- before weekF 13 exactly four non-issued rows are emitted and no forecast function is called;
- `production_eligible = FALSE` is machine-readable in predictions/provenance/status and no production or hard-passage enabling option exists.

## Provenance / preflight

Before source ingestion:

- verify the canonical M2-B v2 package manifest byte-for-byte;
- validate M1-B v8 and M2-B v2 artifacts;
- validate the frozen governed M2-v2 artifact used for A baseline;
- validate frozen M0/M1-A artifacts and their required policy/spec identities;
- record SHA-256 for every artifact and the combined runner itself.

A manifest or artifact mismatch is a hard failure.

## Leakage / routing tests

Required tests:

1. before weekF 13 all four rows are non-issued with explicit pre-window status;
2. A +1/+2 equal governed A baseline exactly at a valid origin;
3. A timing output may change but cannot alter A forecast because no handoff is passed to M2;
4. B +1 equals B1 exactly;
5. B +2 weak/no timing equals B1 exactly;
6. B +2 active timing uses posterior-C2 and exposes monitoring diagnostics;
7. A and B rows share the same source/panel vintage;
8. 2019-20 cannot enter the frozen B artifact/package training lists;
9. no hard M1-B passage route is callable through the combined runner;
10. production eligibility remains explicitly false;
11. M2-B package manifest tampering is rejected before source ingestion;
12. governed M2-v2 A artifact drift is rejected;
13. revision audit behavior matches the existing weekly runners;
14. repeated typed-panel replay is deterministic apart from timestamps/run paths.

## Outputs

Runner:

`2026/run_weekly_shadow_v3.R`

Default output root:

`results/weekly-shadow-v3/`

Per run:

- `typed_ab_weekly.csv`
- `revision_audit.csv` when applicable
- `revision_summary.tsv`
- `m0_a_signals.csv`
- `m0_a_detection.csv`
- `m1_a_runtime.rds`
- `m1_a_timing.csv` when available
- `a_state_runtime.rds`
- `b_v3_runtime.rds`
- `combined_predictions.csv`
- `forecast_summary.tsv`
- `provenance.tsv`
- `status.tsv`

## Governance

This runner is prospective shadow only.

It must never:

- modify frozen v2 artifacts;
- promote v3 to production;
- enable A posterior-C2 timing correction;
- enable a B hard passage gate;
- retune any historical threshold from 2026-27 results.

Prospective scoring should preserve the B lower-bound-saturation strata and report A/B horizons separately.
