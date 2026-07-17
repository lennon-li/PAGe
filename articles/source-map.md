# Source map

The installable package under `PAGe/` is the source of truth. The
repository’s root-level `R/` directory is a development mirror and must
remain synchronized when implementation files are changed.

| Area | Main package files | Responsibility |
|----|----|----|
| M0 | `m0_training.R`, `m0_retro.R`, `m0_runtime.R`, `flagIgnition.R` | Tune and run prospective ignition detection |
| M1 reference | `m1_reference.R`, `m1_reference_helpers.R` | Fit and expose the historical reference curve |
| M1 alignment | `m1_fit.R`, `m1_loso.R`, `m1_runtime.R`, `m1_multi_template.R` | Fit alignment, evaluate LOSO folds, and run the ensemble |
| M1 summaries | `m1_peak_status.R`, `m1_peak_summary.R` | Convert alignment fits to peak state and timing summaries |
| M2 | `m2_training.R`, `m2_spec_grid.R`, `m2_loso_*.R`, `m2_runtime.R` | Train, tune, evaluate, and run the forecast model |
| Orchestration | `pipeline_training.R`, `pipeline_bridge.R`, `pipeline_runtime*.R` | Build kits and coordinate sequential weekly execution |
| Diagnostics | `plot.R`, `plotRes.R`, `plotSeasonCurves.R` | Plot forecasts, fits, and detector behavior |
| Utilities | `utils.R`, `simulate.R`, `checkSeasonLength.R` | Shared helpers, example data, and validation |

The high-level public API follows five verbs: build, tune, train,
assemble, and run. Lower-level functions remain documented for advanced
diagnostics and method development, but operational code should prefer
the high-level entry points shown in the
[walkthrough](https://lennon-li.github.io/PAGe/articles/pipeline-walkthrough.md).
