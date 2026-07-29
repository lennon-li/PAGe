# Stage API inventory and target map

**Status:** design proposal; no implementation decision is encoded here.

PAGe should establish validated M0, M1, and M2 stage contracts before adding
or refactoring a high-level orchestration function. A later
`train_pipeline()` may compose those contracts; it must not contain the
only enforcement of stage gates.

## Design rules

1. Every training or tuning call receives an explicit normalized season
   selection. It never silently derives a training set from the data.
2. A stage may consume only a validated, frozen upstream stage artifact.
3. A tuning result is not a fitted stage artifact, and neither is a deployment
   artifact until it passes its stage gate.
4. M0/M1/M2 specifications and tuning methodology remain unchanged. This work
   makes their inputs, outputs, and failure states explicit.
5. Existing exports remain available as compatibility wrappers until the
   stable replacement is documented and tested.

## Existing public functions

### Shared data, artifacts, and orchestration

| Existing function | Current role | Issue for the target design |
|---|---|---|
| `prepare_surveillance_data()` | Canonicalizes surveillance input. | Retain as the data-entry contract. |
| `validate_surveillance_data()` | Validates canonical surveillance data. | Retain. |
| `simulate_flu_seasons()` | Produces public synthetic example/test data. | Supporting utility only; not a production stage API. Later make its output canonical. |
| `train_pipeline()` | Runs M0/M1/M2 tuning or fixed refresh in one call. | Current orchestration is ahead of explicit stage gates; later refactor to compose frozen stage APIs. |
| `assemble_kit()` | Combines M0/M1/M2 objects. | Retain only as the final gate-protected assembly operation. |
| `validate_page_kit()` | Validates runtime fields of a kit. | Retain; extend later to require frozen stage provenance. |
| `new_result_manifest()` / `validate_result_manifest()` | Records disclosure-safe provenance. | Retain; versioned extension is needed before it carries all season-set identities. |

### M0 — ignition

| Existing function | Current role | Target role |
|---|---|---|
| `build_m0(allD, exclude, ...)` | Fits the M0 component using a fixed parameter set. | Compatibility wrapper for `fit_m0()`. |
| `tune_m0(allD, loso_seasons, exclude, grid, ...)` | Runs M0 LOSO tuning. | Compatibility wrapper for `tune_m0()`. |
| `run_m0_detection()` / `run_m0()` | Runs prospective ignition detection. | Retain as the M0 runtime API. |

### M1 — alignment

| Existing function | Current role | Target role |
|---|---|---|
| `build_m1(allD, m0, exclude, ...)` | Fits reference/alignment state using M0. | Compatibility wrapper for `fit_m1()`. |
| `tune_m1(allD, m0, m1, loso_seasons, grid, ...)` | Runs M1 tuning. | Compatibility wrapper for `tune_m1()`. |
| `tune_m1_alignment()` | Lower-level historical alignment tuner. | Advanced/research API; not part of the stable stage contract. |
| `run_m1_alignment()` / `run_m1()` | Runs prospective alignment using M0 output. | Retain as the M1 runtime API. |

### M2 — forecast

| Existing function | Current role | Target role |
|---|---|---|
| `build_m2(allD, m0, m1, loso_seasons, grid, ...)` | Runs M2 LOSO tuning and selection inputs. | Compatibility wrapper for `tune_m2()`; its current name is misleading. |
| `train_m2(allD, m0, m1, best_spec, exclude, ...)` | Fits a fixed selected M2 specification. | Compatibility wrapper for `fit_m2()`. |
| `run_m2_forecast()` / `run_m2()` | Runs prospective M2 forecasting. | Retain as the M2 runtime API. |

### Current high-level runtime and replay

| Existing function | Current role | Target role |
|---|---|---|
| `run_prospective_pipeline()` / `run_pipeline()` | Executes M0 → M1 → M2 for one current season. | Retain after it verifies frozen stage provenance. |
| `replay_season_holdout()` | Replays one holdout season. | Keep as a compatibility wrapper around a later vectorized replay API. |

## Proposed stage contracts

### Shared selection and artifact functions

| Proposed function | Export | Contract |
|---|---|---|
| `validate_season_selection(data, training_seasons, exclude_seasons = character(), holdout_seasons = character(), application_seasons = character())` | yes | Returns a normalized `page_season_selection`; checks existence, duplicates, stable order, and set disjointness. |
| `season_selection(x)` | yes | Accessor for the normalized selection recorded in a stage result, kit, or replay result. |
| `.require_frozen_stage(x, stage)` | no | Internal guard used before a downstream stage or kit assembly consumes an artifact. |
| `.record_stage_provenance(...)` | no | Internal constructor for selection, upstream identities, configuration, folds, and status. |

### M0 API

| Proposed function | Export | Preconditions | Output / gate |
|---|---|---|---|
| `tune_m0(data, selection, grid, ...)` | yes | Canonical data; non-empty training seasons. | `page_m0_tuning`; every evaluated fold is recorded. |
| `validate_m0_tuning(x)` | yes | M0 tuning result. | Rejects zero evaluable folds, non-finite selection metrics, missing selected configuration, or mismatched folds. |
| `fit_m0(data, selection, config, ...)` | yes | Valid selection; a fixed M0 configuration. | `page_m0_fit` in `draft` state. |
| `freeze_m0(fit, tuning = NULL)` | yes | Valid fit; if tuned, validated M0 tuning result with matching selection/configuration. | Immutable `page_m0_fit` in `frozen` state. |
| `run_m0(m0, current_data, ...)` | yes | Frozen M0 artifact or a validated frozen kit. | Current ignition state. |

### M1 API

| Proposed function | Export | Preconditions | Output / gate |
|---|---|---|---|
| `tune_m1(data, selection, m0, grid, ...)` | yes | Frozen M0 with exactly matching training selection. | `page_m1_tuning`; all fold-level alignment results recorded. |
| `validate_m1_tuning(x)` | yes | M1 tuning result. | Rejects zero evaluable seasons, all-missing metrics, non-finite selected metric, or missing selected configuration. This closes the current M1 failure mode. |
| `fit_m1(data, selection, m0, config, ...)` | yes | Frozen M0 and valid fixed M1 configuration. | `page_m1_fit` in `draft` state. |
| `freeze_m1(fit, tuning = NULL)` | yes | Valid fit and, when relevant, validated matching tuning. | Immutable `page_m1_fit` in `frozen` state. |
| `run_m1(m1, current_data, m0_state, ...)` | yes | Frozen M1 and M0 runtime state with matching provenance. | Alignment and peak-state result. |

### M2 API

| Proposed function | Export | Preconditions | Output / gate |
|---|---|---|---|
| `tune_m2(data, selection, m0, m1, grid, ...)` | yes | Frozen M0/M1 with matching selection. | `page_m2_tuning`; M2 fold summaries and candidate grid provenance. |
| `validate_m2_tuning(x)` | yes | M2 tuning result. | Rejects invalid grid identity, incomplete folds, non-finite selected metric, or absent selected specification. |
| `fit_m2(data, selection, m0, m1, config, ...)` | yes | Frozen M0/M1 and validated fixed M2 specification. | `page_m2_fit` in `draft` state. |
| `freeze_m2(fit, tuning = NULL)` | yes | Valid fit and, when relevant, validated matching tuning. | Immutable `page_m2_fit` in `frozen` state. |
| `run_m2(m2, current_data, m1_state, ...)` | yes | Frozen M2 and matching M1 runtime state. | One- and two-week forecasts. |

## Dependency and gate map

```text
canonical data + season selection
              |
              v
      tune_m0 -> validate_m0_tuning -> fit_m0 -> freeze_m0
                                                  |
                                                  v
      tune_m1 -> validate_m1_tuning -> fit_m1 -> freeze_m1
                                                  |
                                                  v
      tune_m2 -> validate_m2_tuning -> fit_m2 -> freeze_m2
                                                  |
                                                  v
                                   assemble_kit -> validate_page_kit
                                                  |
                                                  v
                      run_m0 -> run_m1 -> run_m2 -> run_pipeline
```

Each `tune_*()` consumes only selected training seasons. Its LOSO folds are
constructed only from `selection$training_seasons`. Holdout and application
seasons cannot enter a tuning or fit input. `freeze_*()` records the exact
upstream artifact identities; a downstream stage must reject a mismatch.

## Compatibility sequence

1. Introduce `page_season_selection`, stage result classes, and internal
   guards without changing M0/M1/M2 algorithms.
2. Implement the M0 contract and tests, then M1, then M2. Do not begin a
   downstream implementation before its upstream gate passes.
3. Keep `build_m0()`, `build_m1()`, `build_m2()`, and `train_m2()` as
   documented compatibility wrappers; emit lifecycle guidance rather than
   removing exports.
4. Refactor `train_pipeline()` only after the three independent stage
   contracts work and are integration-tested.
5. Add vectorized replay and manifest-schema migration after the stage
   artifacts have stable provenance fields.

## Required test layers

- Unit tests for selection validation and each `validate_*_tuning()` gate.
- Per-stage tests for missing seasons, overlap, duplicate IDs, zero folds,
  all-missing metrics, non-finite metrics, and upstream identity mismatch.
- Integration tests proving that M1 rejects an unfrozen M0, M2 rejects an
  unfrozen/mismatched M1, and kit assembly rejects any unfrozen component.
- Synthetic end-to-end test only after all stage contracts pass independently.
