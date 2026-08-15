# Source map

The installable package under `PAGe/` is the sole source of truth. Its R
source lives under `PAGe/R/`; there is no separate root-level mirror.

For operational loading, use
[`load_promoted_kit()`](https://lennon-li.github.io/PAGe/reference/load_promoted_kit.md)
with an immutable registry artifact and its deployment manifest.
[`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md)
is a strict component-level loader, not proof that acceptance or
promotion occurred.

| Area | Main package files | Responsibility |
|----|----|----|
| M0 | `m0_training.R`, `m0_retro.R`, `m0_runtime.R`, `flagIgnition.R` | Tune and run prospective ignition detection |
| M1 reference | `m1_reference.R`, `m1_reference_helpers.R` | Fit and expose the historical reference curve |
| M1 alignment | `m1_fit.R`, `m1_loso.R`, `m1_runtime.R`, `m1_multi_template.R` | Fit alignment, evaluate LOSO folds, and run the ensemble |
| M1 summaries | `m1_peak_status.R`, `m1_peak_summary.R` | Convert alignment fits to peak state and timing summaries |
| M2 | `m2_training.R`, `m2_spec_grid.R`, `m2_loso_*.R`, `m2_runtime.R` | Train, tune, evaluate, and run the forecast model |
| Stage contracts | `stage_contracts.R` | Validate season sets; create, validate, identify, and freeze governed M0/M1/M2 artifacts |
| Orchestration | `pipeline_training.R`, `pipeline_bridge.R`, `pipeline_runtime*.R` | Provide legacy-compatible builders, assemble governed or legacy kits, and coordinate sequential weekly execution |
| Diagnostics | `plot.R`, `plotRes.R`, `plotSeasonCurves.R` | Plot forecasts, fits, and detector behavior |
| Utilities | `utils.R`, `simulate.R`, `checkSeasonLength.R` | Shared helpers, example data, and validation |

The guarded training API follows the sequence validate selection, tune,
validate tuning, fit, freeze, and assemble. Runtime follows M0, then M1,
then M2. Legacy build/train verbs and
[`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
remain compatible while the high-level orchestrator is migrated.
Operational code should use the explicit stage gates when it needs
independent failure boundaries; see the
[walkthrough](https://lennon-li.github.io/PAGe/articles/pipeline-walkthrough.md).
