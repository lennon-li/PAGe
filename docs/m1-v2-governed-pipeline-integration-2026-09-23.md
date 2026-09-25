# M1-v2 governed pipeline integration — 2026-09-23

## Scope

M1-v2 is integrated as a parallel timing stage. It does **not** replace the legacy M1 curve-alignment object currently consumed by legacy M2. This isolates the timing redesign from the later M2 amplitude redesign.

## Training artifact

New high-level API:

`build_m1_v2_timing()`

Inputs:

- completed historical surveillance data;
- retrospective k=8 GAM peak truth;
- governed `page_m1_v2_activation_table` created from an actual `page_m0_loso_result` via `m1_v2_activation_table_from_m0_loso()`, with integer release origin and decimal activation coordinate.

The returned `page_m1_v2_stage` contains:

- peak-aligned low-rank historical `library`;
- nested cross-fitted scalar timing `calibrator`;
- nested cross-fitted M1-C `passage_policy`;
- deterministic artifact identity;
- training season set and configuration;
- versioned M2 handoff contract declaration.

The passage policy is no longer a fixed descriptive threshold. Candidate M1-C policies are evaluated on inner cross-fitted passage histories from the training seasons. The M0 LOSO object used to construct those histories must contain exactly the same season universe as the M1-v2 training artifact, preventing the outer held-out season from leaking through M0 tuning. Selection prioritizes, in order:

1. number of false-early confirmations;
2. total early-confirmation magnitude;
3. misses by release-time peak+2;
4. mean confirmation delay;
5. conservative deterministic tie-breaks.

Inner passage histories continue through release-time peak+6 for the delay tie-break, while `miss_by_peak2` remains the primary miss criterion. An inner season still unconfirmed by +6 receives a +7-week delay penalty for tie-breaking.

The high-posterior branch is structurally restricted to thresholds >=0.95; the governed default candidate set uses 0.95 only.

Additional M1-C safety invariants:

- the one-week high-posterior branch requires posterior probability >=0.95 plus an actual immediate one-week decline; no additional drop-from-maximum floor is imposed in the validated default rule;
- the sustained branch uses the training-selected drop threshold but requires two truly consecutive observed-week declines;
- both training-policy evaluation and runtime eligibility use `ceiling(activation_week_decimal) + min_post_activation`;
- gaps in weekly surveillance cannot masquerade as consecutive decline evidence.

## Artifact integrity

The M1-v2 stage identity includes:

- M1 library hash recomputed from the actual fitted forecast/passage components, peak heights, fitted peak locations, truth, and configuration;
- calibration offset and calibration provenance, including canonical activation payload hash and M0 LOSO provenance;
- selected passage policy and passage-policy provenance;
- declared training-season set;
- versioned M2 output contract;
- stage configuration.

The peak-relative PC sign is anchored deterministically before bounds and hashes are constructed, avoiding BLAS/LAPACK sign ambiguity in artifact identity.

`assemble_kit()` accepts `m1_v2` as a final optional argument so existing positional calls remain backward compatible.

For governed in-memory kits, M1-v2 receives an additional governance identity bound to the base M0/M1/M2 kit governance identity and the M1-v2 artifact ID.

`validate_page_kit()` verifies:

- M1-v2 class;
- recomputed M1-v2 artifact identity;
- season-set agreement with governed season selection;
- M1-v2 governance identity.

The production reference bundle can persist `m1_v2`; `load_prospective_kit()` loads it when present. Legacy bundles remain valid when it is absent.

## Runtime stage

New API:

`run_m1_v2_timing()`

The stage runs sequentially from the locked M0 activation origin through the current observed prefix.

For every origin it keeps conceptually distinct:

### M1-F future timing

- raw future-conditioned peak posterior;
- raw posterior mean;
- calibrated peak mean;
- raw and calibrated 90% location interval endpoints;
- interval width;
- elapsed weeks since M0 activation and calibrated weeks remaining to peak;
- explicit `calibrated_mean_is_future` flag.

The raw M1-F posterior is required to have candidate peak times strictly greater than the release boundary `origin + 1`. If the full post-M0 history becomes longer than the fixed peak-relative template domain, only observations older than the maximum candidate/template overlap are trimmed; the most recent supported history is retained and the origin remains forecastable.

### M1-C passage

- unconditioned passage posterior evidence;
- `P(peak passed by release boundary)`;
- probability peak is in the next +1/+2/+3 weeks;
- causal observed-decline evidence;
- policy-selected passage confirmation state.

When passage is first confirmed, runtime locks the **calibrated mean of the unconditioned passage posterior**, not the future-conditioned M1-F mean. `locked_peak_week` and `locked_at_origin` are then carried forward.

Calibration does not alter passage probabilities or passage state.

## Versioned M2 handoff

Handoff version:

`m1-v2-to-m2-v1`

Current fields:

- `m1_v2_artifact_id`;
- `season`;
- `state`: `pre_ignition`, `active`, `future_only`, `passage_only`, `passage_confirmed`, or `unavailable`;
- `origin_week`;
- `asof_boundary`;
- `activation_week`;
- `raw_peak_posterior` candidate/probability grid;
- `raw_peak_mean`;
- `calibrated_peak_mean`;
- `calibrated_mean_is_future`;
- explicit `raw_peak_q05`, `raw_peak_q95`, `calibrated_peak_q05`, `calibrated_peak_q95`;
- calibrated aliases `peak_q05`, `peak_q95`, and `interval_width_90`;
- `weeks_elapsed_since_activation`;
- `weeks_to_calibrated_peak`;
- `prob_peak_passed`;
- `prob_peak_within_1w`, `prob_peak_within_2w`, `prob_peak_within_3w`;
- `locked_peak_week` and `locked_at_origin` after M1-C confirmation;
- `calibration_offset_week`;
- selected passage-policy parameters.

`validate_m1_v2_handoff()` enforces release-boundary identity, elapsed/remaining clock identities, raw-posterior normalization and future support, raw/calibrated interval ordering and width identity, probability ranges/monotonicity, calibrated future-state flag, and required locked-peak fields after passage.

Direct `run_m1_v2_timing()` calls also verify the M1-v2 governance identity when the base kit is governed, and fail hard if the runtime season is present in the M1-v2 training artifact.

## Pipeline behavior

`run_prospective_pipeline()` now invokes M1-v2 when the kit contains it and returns:

- `m1_v2_timing`;
- `m1_v2_handoff`;
- `m1_v2_status`.

Legacy M1 alignment and legacy M2 forecasts are still run exactly as before. Missing M1-v2 artifacts return `status = "unavailable"` rather than breaking old kits.

## Verification to date

Focused direct-source tests after independent review and fixes:

- M1-v2 core: 41 passing assertions;
- M1-v2 pipeline integration: 27 passing assertions;
- no focused failures or assertion warnings.

Repository R syntax check:

- 74 package R files parse successfully.

Authoritative governed 11-season replay with nested historical M0 activations:

- all 103/103 primary origins have finite raw and calibrated M1-F predictions;
- active integer metric: **1.373248**;
- native calibrated decimal metric: **1.246155**;
- raw native decimal metric: **1.349451**;
- M1-C false-early confirmations: **0/11**;
- M1-C confirmed by release-time peak+2: **10/11**;
- median confirmation delay among confirmations: **0.5 week**;
- mean confirmation delay among confirmations: **0.8 week**.

The only peak+2 miss is 2012-13. 2018-19, which previously exposed an unsafe 0.90 fast threshold in strict outer replay, now confirms at its release-time truth origin under the structural 0.95 fast-branch floor.

Full namespace/package loading remains blocked by the local R dependency stack (`ns_registry_env()` is defunct). Direct-source tests and syntax checks are therefore the authoritative worktree verification in this environment; tests that call the stale installed `PAGe::` namespace are not treated as worktree regression evidence.

## Strict outer nesting

The authoritative replay re-runs M0 LOSO inside each outer M1 training-season universe. For an outer held-out season, every historical activation used by M1 calibration or M1-C policy selection is therefore generated without that outer season. The resulting activation table carries the nested M0 context/provenance hash into the M1-v2 artifact identity.
