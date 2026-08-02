# PAGe baseline evidence inventory

**Recorded:** 2026-08-01
**Repository commit:** `a3efbe4` (`agent/page-governance-audit`)
**Purpose:** Stage 0 baseline for the API-first reproduction plan. This record
does not certify a promotion or post-validation refresh. A later local frozen
acceptance replay is recorded in the status map and boundary expansion record;
it failed the NLL gate and therefore did not authorize either operation.

## Evidence boundaries

Private surveillance inputs and serialized R artifacts are intentionally
ignored by Git. This clone has no local copy of the following required
evidence files:

| Evidence | Expected identity or contract | Local status |
|---|---|---|
| Retune artifact | `season2526/retuned_pipeline.rds` (also preserved as `data/retuned_pipeline.rds` on Venkata); SHA-256 `894e38b85092c73090ddfc6900b8c259b751d7186ca9048be38dc3694f7ad422` | absent locally; hash matched at BCC and Venkata on 2026-07-29 |
| Prospective snapshot | `data/current_2025_26_from_default.rds`; SHA-256 `16e153068d1b19861c4bdd33581783c5d0745ce835bd2e8eadf993d5dda57ced` | absent locally; BCC metadata verified 45 unique 2025-26 weeks, `weekF` 9--53, complete `y` and `N` after filtering |
| Historical CSV | `data/flu_testing_data.csv`; SHA-256 `fa8add1b253944df5d853a2fb0456d7ac368657e073da0d97f909be95ca59c54` | absent locally; BCC hash captured |

The BCC/Venkata identities above were rechecked read-only on 2026-07-29. The
BCC artifact was read from commit `ab3aeb6`; Venkata matched both preserved
artifact paths. The private files are still unavailable in this clone. Do not
copy, regenerate, or use any of them until an authorized private-data run
begins.

Read-only retune-artifact metadata confirms `mode = "retune"` and a
`page_training_result` schema. Its 2025-26 holdout is present but
`status = "held_out"`, `released = FALSE`, and `promotion_pass = NULL`; the
effective exclusions are `2011-12`, `2015-16`, `2020-21`, `2021-22`, and
`2025-26`. The kit has exactly the ten eligible historical training seasons.
M1 recorded 20 candidates, with every MAE column missing and `n_seasons = 0`
for every candidate. M2 recorded 15 summary rows; its selected specification
used ten seasons and has Bernoulli NLL `0.4171031832`. These facts establish
historical artifact provenance, not a successful M1 retune or a governed
holdout decision.

The tracked `.gitignore` enforces this boundary: `data/`, `*.rds`, `*.RData`,
and raw CSV files are ignored; only disclosure-safe files under
`results/audit/` may be tracked. At this baseline, that directory contains
only its README.

## Source and API inventory

### Package identity

- Package: `PAGe` 0.2.0.
- Code source of truth: `PAGe/R/`; root `R/` is its development mirror.
- Export count: 53 (`PAGe/NAMESPACE`).
- Return classes currently constructed by the package: `page_forecast`,
  `page_training_result`, `page_promotion_report`, and
  `page_verified_promotion_evidence`.

### Exports

`assemble_kit`, `build_m0`, `build_m1`, `build_m2`, `checkSeasonLength`,
`check_promotion`, `default_m1_grid`, `default_m2_grid`, `getCurrentD`,
`hash_file_sha256`, `load_flu_hist`, `load_promoted_kit`,
`load_prospective_kit`, `m1_make_params`, `new_result_manifest`,
`plan_m2_grid`, `plot_cls_models_by_season`, `plot_det_facet`,
`plot_forecast`, `plot_ignition_detect_vs_truth`,
`plot_ignition_weekly_snapshots`, `plot_nested_loso_predictions`,
`plot_season_detection_table`, `plot_stage2`,
`plot_stage2_joint_fit_by_season`, `prepare_surveillance_data`,
`race_m2_candidates`, `read_result_manifest`, `replay_season_holdout`,
`resolve_week_override`, `run_m0`, `run_m0_detection`, `run_m1`,
`run_m1_alignment`, `run_m2`, `run_m2_forecast`, `run_pipeline`,
`run_prospective_pipeline`, `select_m2_candidate`, `simulate_flu_seasons`,
`stage2_make_spec`, `summarize_forecast_metrics`,
`summarize_replay_diagnostics`, `train_m2`, `train_pipeline`, `tune_m0`,
`tune_m1`, `tune_m1_alignment`, `validate_page_kit`,
`validate_result_manifest`, `validate_surveillance_data`,
`verify_promotion_evidence`, and `write_result_manifest`.

### Documentation sources (21 QMD files)

- Package/example: `PAGe/inst/example/fluA1.qmd`.
- Package articles: `PAGe/vignettes/articles/{forecast-training,ignition-training,pipeline-overview,pipeline-walkthrough,prospective-deployment,source-map}.qmd`.
- Root articles: `docs/{deployment-workflow,estimateRef,flu_forecasting,forecast_training,ignition_training,loso_walkforward,m1_m2_stacking,peak_detection_tuning,pipeline_overview,pipeline_walkthrough,prospective_deployment,run,source_map}.qmd`.
- Private-data workflow article: `season2526/reproduce_retrain.qmd`.

`docs/workflow-status.md` is the source-level status map. Rendered HTML is a
historical snapshot and must not be used as completion evidence.

### Script inventory (100 R scripts)

| Location | Count | Status |
|---|---:|---|
| `scripts/` root | 77 | historical tuning, diagnostics, and compatibility scripts; consult `docs/workflow-status.md` before use |
| `scripts/acceptance/` | 2 | canonical opt-in holdout replay/evidence workflow |
| `scripts/fresh_run/` | 16 | research-only historical workflow |
| `scripts/promotion/` | 2 | canonical immutable registration workflow |
| `scripts/public/` | 1 | public synthetic lifecycle workflow |
| `season2526/` | 2 | canonical post-acceptance fixed-spec refit support |

## Artifact schemas and immutable provenance

`new_result_manifest()` creates the disclosure-safe
`page_result_manifest` schema (version 1). Its canonical provenance order is:

`code_commit`, `run_timestamp`, `r_version`, `package_versions`,
`input_fingerprint`, `seasons`, `exclusions`, `row_counts`, `spec_id`,
`training_seasons`, `source_artifact_hashes`, `fold_ids`, and
`evaluation_seasons`.

`validate_page_kit()` requires `m0_params`, `ref`, `hyper`, `M1_PARAMS`,
`m2_production`, and `best_spec`; frozen operation does not require raw
historical data. `verify_promotion_evidence()` uses the separate
`page_verified_promotion_evidence` schema (version 1) and validates the
decision bundle, manifests, kit identities, and data fingerprint.

Every new run must record the exact code commit and use immutable result and
manifest paths. Mutable `current` aliases are not an accepted deployment
contract.

## Numerical-claim status

| Claim | Classification | Baseline interpretation |
|---|---|---|
| 113 tests / 504 expectations, fresh install, source build, vignette rebuild, and `R CMD check` passed on `a3efbe4` | historical audit result | not rerun in this Stage 0 inventory |
| Historical M2 Bernoulli NLL `0.4171031832` in the retune artifact | historical-only | rechecked read-only from BCC metadata; this is not 2025-26 validation |
| README historical M2 NLL `0.4175` | unverified | a rounded/possibly different historical claim; no supporting local private artifact is available |
| M1 Weibull peak MAE values `1.338` and `1.275` | unverified/conflicting | do not select or change an M1 specification from these values |
| 2025-26 peak testing volume `39,290` and `logN` `10.58` | unverified historical documentation claim | raw snapshot is absent locally |
| Boundary-expansion acceptance replay | verified local evidence, failed gate | `bias_alpha=0` improved NLL by `0.0000482` versus the `0.02` threshold; horizon and phase gates passed; no refit or promotion |

Numbers embedded in legacy scripts are configuration or historical-research
annotations unless a future immutable artifact, manifest, and reproducible
run verify them. The governed acceptance thresholds are API policy, not
observed performance: 2% NLL improvement, at most 5% horizon-MAE degradation,
and at most 10% phase-MAE degradation.

## Stage 0 gate assessment

- No current evidence was overwritten. **Verified locally**: this change adds
  only this disclosure-safe inventory.
- The 2025-26 snapshot was not used for model development. **Verified**:
  aggregate metadata and hashes were read remotely without transferring data.
- Repository status and project-memory status agree on the current commit,
  private-data boundary, and incomplete validation state. **Verified locally
  for repository state and by read-only BCC/Venkata metadata capture for the
  named artifact claims.**

Stage 0 evidence preservation is complete. Stage 1 may begin only with the
season-selection API and synthetic-data contract; it must not alter M0/M1/M2
specifications, the tuning workflow, LOSO methodology, or private-data
pipelines.
