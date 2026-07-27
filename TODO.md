# PAGe Audit Inventory and TODO

Last audited: 2026-07-27  
Repository state audited: `e2fb85918cc1ff8a4f6288ab465f426f0823d913` (`master`)  
Scope: package code, root/package mirrors, tests, scripts, reports, generated
documentation, workflow configuration, and references to saved result artifacts.

This is the authoritative reconciliation list until the conflicts below are
closed. A report or comment is not evidence that a run completed. Statuses mean:

- **Verified implemented**: implementation and relevant tests are committed.
- **Claimed result, unverified**: a numeric result is documented, but its source
  artifact and reproducible result summary are not committed.
- **Incomplete**: required implementation, execution, or evidence is absent.
- **Conflict**: committed sources make incompatible claims or cannot execute as
  described.

## Current state at a glance

| Area | Status | Audit conclusion |
|---|---|---|
| Package structure and public API | Verified implemented | Installable package source exists under `PAGe/`; high-level training, forecasting, plotting, validation, and promotion APIs are present. |
| Root/package R mirrors | Verified implemented | All 40 files in `R/` matched their counterparts in `PAGe/R/` byte-for-byte at the audited commit. |
| Input data contract | Verified implemented | Explicit loading, normalization, validation, and synthetic-season generation are implemented and tested. Private surveillance observations are not committed. |
| M0 ignition | Verified implemented in code | Build, tune, retrospective, and prospective runtime paths exist. Numerical production result still depends on ignored local artifacts. |
| M1 alignment | Verified implemented in code | Reference fitting, multi-template alignment, LOSO tuning, peak calibration, and prospective runtime paths exist. The canonical reported MAE is inconsistent across docs. |
| M2 forecasting | Verified implemented in code | Fold building, LOSO evaluation, grid planning, selection, production fitting, frozen runtime, online correction, and post-peak override exist. |
| M2 fold leakage controls | Verified implemented in code/tests | Fold-specific reference/M1 reconstruction and separate train/test manual-label interfaces are present. |
| Fully nested selection of M0/M1/M2 | Incomplete | M2 folds are rebuilt safely, but M0 and M1 hyperparameters are selected globally before the outer M2 evaluation. Current M2 validation is conditional on those choices, not fully nested over every modelling decision. |
| Frozen deployment | Verified implemented | `run_pipeline()`/`run_prospective_pipeline()` default to frozen deployment; weekly refit is explicit compatibility behavior. |
| 2025-26 holdout protection | Verified implemented in code/tests | `train_pipeline()` excludes 2025-26 by default and releases it only after a valid, passing, locked-threshold promotion report. |
| 2025-26 unseen M2 replay | Implemented, execution unverified | Replay and leakage rejection exist; the repository does not preserve the completed real-data replay, metrics, or promotion report. |
| 2025-26 final refit including season | Claimed, not verified | No committed artifact or summary proves a final production fit whose `training_seasons` includes 2025-26. The main retrain script actually excludes it by default. |
| v16 production specification | Implemented and consistently coded | High-level defaults use `k_f=4`, `k_e=2`, `alpha_state=0.15`, `k_sp=6`, `k_r=0`, `k_de=0`, `bias_alpha=0.05`, `bias_beta=0`. |
| v16 NLL 0.4175 | Claimed result, unverified | Repeated in README/docs, but the named result artifact is ignored, absent, and inconsistently named. |
| External/simple forecast baselines | Incomplete | Historical PAGe versions and internal ablations exist; LOCF, historical mean/median, unaligned forecast, and other prespecified external/simple baselines are not implemented as a canonical benchmark suite. |
| Publication-ready evaluation | Incomplete | NLL, Brier, RMSE, MAE, horizon and phase machinery partly exists; locked tables, calibration, interval evaluation, uncertainty, baseline comparisons, and a preserved confirmatory chain remain incomplete. |
| Reproducible public example | Partly implemented | Synthetic data generation exists, but there is no single executed public end-to-end reproduction of all manuscript tables and figures. Vignettes use `eval: false`. |
| Automated tests | Tests committed; run not verified here | 14 `testthat` files plus a helper are present. R was unavailable in the audit environment, so the suite could not be executed locally. |
| CI | Configured; latest result unverified | `R-CMD-check` and pkgdown workflows are committed. No combined status was returned for the audited commit. |

## Verified implementation inventory

### Data and package interface

- [x] `load_flu_hist()` requires an explicit path, `PAGE_FLU_HIST_FILE`, or an
  actually present package file and fails clearly otherwise.
- [x] `prepare_surveillance_data()` and `validate_surveillance_data()` enforce
  the canonical `season`, `weekF`, `y`, `N`, `p`, and `neg` contract.
- [x] `simulate_flu_seasons()` provides deterministic synthetic data generation.
- [x] Public documentation, `NAMESPACE`, roxygen output, pkgdown configuration,
  package tests, and GitHub Actions configuration exist.
- [x] `R/` and `PAGe/R/` are synchronized at the audited commit.

### M0: ignition detection

- [x] Retrospective feature estimation and ignition labelling are implemented.
- [x] M0 fitting, grid tuning, LOSO scoring, and construction are implemented.
- [x] Prospective weekly ignition detection and locking are implemented.
- [x] High-level defaults are centralized in `pipeline_training.R`.
- [ ] Reconcile current canonical manual labels and M0 results with the stale
  root `task.md`, older scripts, and every rendered report.
- [ ] Preserve a machine-readable current M0 result summary with fold/season
  errors and provenance; do not rely on ignored `stage1_tuning.rds`.

### M1: alignment and peak estimation

- [x] Reference-curve fitting and accessors are implemented.
- [x] Multi-template logit-scale alignment and slope weighting are implemented.
- [x] LOSO walk-forward tuning and fold-aware peak calibration are implemented.
- [x] Prospective alignment, peak state, and post-peak freeze behavior exist.
- [x] Failed/deferred v17/v18 experiments are documented.
- [ ] Resolve whether the canonical locked-spec Weibull peak MAE is 1.275,
  1.276, or 1.338 weeks and identify the exact code/data/artifact behind it.
- [ ] Preserve one canonical M1 result table including fold seasons, coordinate
  system, manual-label version, ensemble scale, and artifact hash.
- [ ] Re-measure M1 after legitimately releasing 2025-26; do not call a fit
  including 2025-26 a holdout evaluation.

### M2: forecast model

- [x] Leakage-aware M2 fold construction and fold-specific M1 reconstruction
  are implemented.
- [x] Frozen-bias LOSO evaluation is implemented.
- [x] NLL, Brier, and RMSE calculations exist in low-level M2 evaluation.
- [x] The bounded v16-centered M2 grid planner is implemented and tested.
- [x] Minimum-NLL, one-standard-error, and Pareto selection are implemented.
- [x] Conservative racing interfaces are implemented; survivors still require
  full evaluation.
- [x] Final production fitting and kit assembly are implemented.
- [x] Runtime validates required kit fields and uses the frozen GAM by default.
- [x] Online season-effect and Holt-style bias correction paths exist.
- [x] The post-peak M1 override is implemented in runtime.
- [ ] Decide and document whether the post-peak override is part of the
  canonical v16 estimand. Re-evaluate the complete locked pipeline with that
  behavior, not only the pre-override GAM.
- [ ] Make one artifact/result name canonical. Current sources refer to both
  `fresh_nested_loso_v16_production.rds` and the undocumented
  `fresh_nested_loso_v16_postpeak.rds`.
- [ ] Preserve the complete v16 fold-level result summary that supports 0.4175.

### Prospective validation and promotion

- [x] `replay_season_holdout()` rejects a kit if the target season appears in
  `training_seasons`.
- [x] Replay forces frozen runtime and returns standardized overall, horizon,
  and phase summaries.
- [x] `check_promotion()` implements locked gates: at least 2% NLL improvement,
  no horizon MAE degradation above 5%, and no phase MAE degradation above 10%.
- [x] `train_pipeline()` validates the canonical promotion schema and will not
  release 2025-26 after a missing, malformed, custom-threshold, or failed report.
- [x] `scripts/acceptance/replay_2025_26.R` provides a manual acceptance entry
  point.
- [ ] Make the acceptance script save the replay, candidate metrics, incumbent
  metrics, canonical promotion report, and a compact provenance manifest.
- [ ] Run the real acceptance gate with both kits confirmed not to contain
  2025-26 in `training_seasons`.
- [ ] Preserve the passing/failing result before any refit includes 2025-26.
- [ ] Only after that result is frozen, refit the production model including
  2025-26 and preserve proof in `training_seasons`.

## Conflict ledger

### C01 — `run_retrain_venkata.R` does not include 2025-26 in training

The script loads and appends 2025-26, then calls:

```r
train_pipeline(allD, mode = "retune")
```

The default is `prospective_holdout = "2025-26"` with no promotion report, so
`train_pipeline()` removes 2025-26 from all tuning and final fitting. The output
message and filename imply a completed inclusive retrain, but the code does the
opposite.

- [ ] Require a previously saved, passing canonical promotion report.
- [ ] Pass it explicitly to `train_pipeline()`.
- [ ] Assert `retuned$holdout$status == "released"`.
- [ ] Assert `"2025-26" %in% retuned$kit$m2_production$training_seasons`.
- [ ] Fail before saving if either assertion is false.

### C02 — `reproduce_retrain.qmd` is not executable as described

- It claims an exact reproduction incorporating 2025-26.
- It does not apply the tuned M1 parameters when rebuilding M1 for M2.
- It calls `assemble_kit(m2_trained)`, but `assemble_kit()` requires M0, M1, and
  M2 inputs.
- It evaluates training seasons with a kit trained on them, while
  `replay_season_holdout()` correctly rejects that leakage.
- The note saying `train_pipeline(allD, mode="retune")` is equivalent is false
  because the default holdout remains active.

- [ ] Replace the document with a two-phase reproduction:
  1. untouched 2025-26 replay and frozen promotion decision;
  2. post-decision production refit including 2025-26.
- [ ] Use the high-level API consistently or correctly propagate the tuned M0,
  tuned M1 parameters, selected M2 spec, and full `assemble_kit()` inputs.
- [ ] Use genuine outer holdout/LOSO kits for retrospective evaluation.
- [ ] Turn execution on for the compact verification sections.

### C03 — Completed runs are not auditable from the repository

`data/`, `results/`, `*.rds`, and `*.csv` are ignored. That appropriately keeps
private observations and large models out of Git, but it also removes every
artifact needed to verify claimed results.

- [ ] Keep private data and model objects ignored.
- [ ] Commit small disclosure-safe summaries under `results/audit/` by adding a
  narrow `.gitignore` exception for approved `.json`/`.csv`/`.md` manifests.
- [ ] Record SHA-256 hashes for non-committed source artifacts.
- [ ] Record code commit, run timestamp, R/package versions, input-data
  fingerprint, seasons, exclusions, row counts, spec ID, and training seasons.
- [ ] Record fold-level metrics without disclosing row-level surveillance data.

### C04 — v16 result identity is inconsistent

- README, agent context, and reports claim canonical NLL 0.4175.
- `m1-improvement-attempts-2026-04.md` reports v16 NLL 0.42646.
- `forecast_training.qmd` calls 0.42646 a research expansion and 0.4175 a later
  canonical validation.
- Scripts write `fresh_nested_loso_v16_production.rds`.
- Context files cite `fresh_nested_loso_v16_postpeak.rds`, for which no writer
  exists in committed code.

- [ ] Identify the exact source run for 0.4175.
- [ ] Verify that its selected spec, evaluated spec, runtime behavior, seasons,
  phases, and score definition match the claimed deployed pipeline.
- [ ] Retire or relabel every superseded number.
- [ ] Generate one locked primary analysis table from the canonical artifact.

### C05 — M1 canonical result is inconsistent

- Agent context and some reports claim 1.275 weeks.
- The April improvement note claims 1.276 on the logit-scale ensemble.
- `pipeline_overview.qmd` claims 1.338 on the logit-scale ensemble and calls
  1.275 an older probability-scale result.

- [ ] Re-run or recover the canonical logit-scale artifact.
- [ ] Decide the single locked result and update generated context via
  `.ai/shared/` plus `scripts/sync-agent-context.R`.
- [ ] State the coordinate system and manual-label version beside the metric.

### C06 — Bias-correction parameters are described inconsistently

- The v16 high-level spec uses `bias_alpha=0.05`.
- Older skill/docs describe base `bias_alpha=0.4`.
- Runtime may raise alpha to 0.7 after consecutive same-sign residuals.
- Some low-level defaults remain 0.2 or 0.4 for compatibility.

- [ ] Distinguish structural spec value, runtime adaptive rule, and legacy
  fallback values in one canonical specification.
- [ ] Remove silent legacy fallback from the canonical production path or emit
  a hard warning when required spec fields are absent.
- [ ] Ensure LOSO evaluation uses exactly the same correction rule as the
  deployed pipeline being claimed.

### C07 — Production artifact naming and promotion are incomplete

The v16 production script writes `data/fresh_m2_production.rds` and compares it
with `data/m2_production.rds`; it does not perform a canonical promotion/copy
step. Documentation nevertheless calls `data/m2_production.rds` the deployed
v16 kit.

- [ ] Add an explicit, gated promotion command that never overwrites the
  incumbent before acceptance passes.
- [ ] Save incumbent and candidate identities in the promotion manifest.
- [ ] Make deployment load the promoted artifact by immutable ID or verified
  manifest, not by an ambiguous mutable filename alone.

### C08 — Fresh prospective script contains kit-schema drift

`load_prospective_kit()` returns `m2_production`, but
`scripts/fresh_run/06_prospective.R` prints `fresh_kit$m2$spec_version`. The same
script later creates `kit_kf5$m2`, although runtime uses `m2_production`.

- [ ] Replace `$m2` references with `$m2_production`.
- [ ] Add a smoke test that executes the fresh prospective entry point through
  kit loading before any expensive replay.

### C09 — Runtime fallback configuration is stale

If `M1_PARAMS` is absent from a legacy reference cache,
`load_prospective_kit()` falls back to `slope_weight=0.5`,
`slope_window=4`, and `dynamic_temp=TRUE`. Current locked defaults are
`slope_weight=8`, `slope_window=6`, and `dynamic_temp=FALSE`.

- [ ] Fail closed for a canonical kit missing `M1_PARAMS`, or use the single
  centralized locked default with an explicit provenance warning.
- [ ] Remove outdated v12 fallback-spec discovery from the canonical v16 load
  path.

### C10 — Data documentation conflicts with the repository

Generated agent context says built-in data live at
`PAGe/inst/extdata/flu_hist.csv`, but that file is absent. Package code and
README correctly say surveillance observations are not distributed.

- [ ] Update `.ai/shared/project-context.md`.
- [ ] Regenerate `AGENTS.md` and `CLAUDE.md`; do not edit generated files
  directly.

### C11 — Old and current workflows coexist without a retirement map

Root `task.md`, v2-v18 tuning scripts, old weekly-refit documentation, current
frozen deployment, v14/v15/v16 production builders, and generated HTML all
remain discoverable. Some are useful research history, but their status is not
machine-readable and they contradict current defaults.

- [ ] Create `docs/workflow-status.md` listing each entry point as
  `canonical`, `research-only`, `superseded`, or `broken`.
- [ ] Put a clear banner on superseded QMDs and scripts.
- [ ] Move no files until references are mapped; then archive rather than
  silently delete research history.
- [ ] Re-render HTML only after source QMD conflicts are resolved.

### C12 — M0/M1 selection is not fully nested inside M2 outer folds

`train_pipeline(mode="retune")` tunes M0 and M1 on the non-holdout historical
set, locks those hyperparameters, then performs fold-aware M2 evaluation. The
M2 fold internals are leakage-aware, but the overall model-development
evaluation does not repeat M0/M1 hyperparameter selection inside every outer
fold.

- [ ] Choose one defensible claim:
  - implement full nested selection for all stages; or
  - label historical M2 LOSO as conditional validation and use untouched
    2025-26 as the confirmatory evaluation.
- [ ] Prefer the second path for the primary paper unless full nesting is
  computationally justified and completed.

## Required work, ordered

### P0 — Establish the auditable ground truth

- [ ] Fix C01, C02, C03, C04, C05, C07, C08, C09, and C10.
- [ ] Add a disclosure-safe result-manifest schema and validator.
- [ ] Recover local Venkata artifacts, inspect rather than trust filenames, and
  inventory for each object:
  - object class and schema;
  - `holdout$status`;
  - selected `best_spec_id`;
  - `training_seasons`;
  - fold/evaluation seasons;
  - overall, horizon, phase, and per-season metrics;
  - source code commit and file hash.
- [ ] Classify each recovered artifact as incumbent, candidate-before-holdout,
  holdout replay, promotion report, or post-promotion refit.
- [ ] Reject any artifact whose provenance cannot establish that 2025-26 was
  unseen at evaluation time.

### P0 — Complete the 2025-26 evaluation-to-refit chain

- [ ] Freeze the candidate and incumbent kits, both excluding 2025-26.
- [ ] Replay all available 2025-26 weeks with frozen runtime only.
- [ ] Save candidate/incumbent metrics and the canonical promotion report.
- [ ] Report ignition timing, h=1/h=2 metrics, phase metrics, calibration,
  uncertainty/coverage, and interval scores.
- [ ] Record the decision before fitting on 2025-26.
- [ ] If promotion passes, refit with the exact promoted specification and
  include 2025-26.
- [ ] Save a production manifest proving the final training-season list.
- [ ] Do not revise the confirmed specification after viewing the holdout
  result; any later revision starts a new development cycle.

### P1 — Complete publication-grade comparisons

- [ ] Implement a prespecified benchmark suite:
  - last observation carried forward;
  - historical seasonal mean/median;
  - unaligned GAM;
  - simple autoregressive/logit-GAM;
  - template-only forecast;
  - EMA/state-only forecast;
  - a recognized influenza baseline if its inputs are available.
- [ ] Implement canonical ablations:
  - no M0 gate;
  - no M1 phase alignment;
  - no online season-effect correction;
  - no `logit_spread`;
  - no bias correction;
  - no post-peak M1 override.
- [ ] Evaluate all models on identical folds/weeks with the same score
  definitions.
- [ ] Add season-level uncertainty for score differences.

### P1 — Complete scientific validation

- [ ] Lock and document the primary estimand, forecast issue/target weeks,
  exclusions, and score weighting.
- [ ] Justify trial-weighted versus week-weighted Bernoulli cross-entropy and
  report sensitivity to both.
- [ ] Add calibration intercept/slope and plots by horizon.
- [ ] Add empirical interval coverage and a proper interval score.
- [ ] Report NLL, Brier, RMSE/MAE, horizon, phase, and per-season results from
  one canonical prediction table.
- [ ] Independently document ignition-label definition, assessor/process,
  timing relative to tuning, and sensitivity to alternative labels.
- [ ] Add downstream sensitivity to early/late ignition errors.
- [ ] Add peak-week sensitivity: raw maximum, smoothed peak, peak plateau, and
  within ±1/±2 week accuracy.
- [ ] Document jurisdiction, population, specimen/testing denominator, testing
  strategy changes, revisions/delays, pathogen/subtype, and intended decision
  use before making surveillance claims.

### P1 — Public reproducibility

- [ ] Build one small synthetic dataset in the canonical raw input schema.
- [ ] Add an executed end-to-end synthetic example covering train, replay,
  promotion, refit, and forecast with a deliberately small grid.
- [ ] Add a public-data replication if licensing and source stability permit.
- [ ] Add a data dictionary and provenance template.
- [ ] Add a frozen R dependency environment.
- [ ] Provide one command that recreates every public table and figure from
  disclosure-safe inputs and manifests.

### P2 — Repository consolidation

- [ ] Replace root `task.md` with an archive pointer or clearly mark it as a
  historical M0 task after preserving its provenance.
- [ ] Establish one canonical workflow entry point for refresh, retune,
  acceptance, promotion, and post-promotion refit.
- [ ] Add manifest validation and entry-point smoke tests to CI.
- [ ] Add Windows and macOS package checks if cross-platform support is claimed.
- [ ] Regenerate roxygen docs, vignettes, pkgdown, `AGENTS.md`, and `CLAUDE.md`
  after canonical sources are reconciled.
- [ ] Run the complete test suite and `R CMD check`; record the first fully
  passing commit in this file.

## Definition of done

The audit is resolved only when all of the following are true:

1. One canonical specification, one M1 result, and one M2 result are named.
2. Every reported number is generated from a committed disclosure-safe summary
   linked to a hashed source artifact and exact code commit.
3. The untouched 2025-26 replay is preserved before any inclusive refit.
4. The promotion decision is reproducible and the final production model's
   `training_seasons` are explicit.
5. Code, scripts, tests, README, QMD sources, rendered HTML, package docs,
   agent context, and saved manifests make the same claims.
6. Benchmark, ablation, calibration, interval, and sensitivity analyses needed
   for the intended surveillance paper are complete.
7. The public synthetic reproduction and the private real-data reproduction
   both run from a single documented command.
8. Package tests and `R CMD check` pass on the canonical commit.

