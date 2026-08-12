# PAGe Audit Inventory and TODO

Last reconciled: 2026-07-29
Repository baseline: `ab3aeb6` (`master`) plus the current audit implementation
patch
Scope: package code, root/package mirrors, tests, scripts, reports, generated
documentation, workflow configuration, and references to saved result artifacts.

This is the authoritative reconciliation list until the conflicts below are
closed. A report or comment is not evidence that a run completed. Statuses mean:

- **Verified implemented**: implementation and relevant tests are present and
  have been executed against the current source tree.
- **Implemented, execution unverified**: the governed code path and synthetic
  tests exist, but the required private-data operation and evidence have not
  been run or preserved here.
- **Claimed result, unverified**: a numeric result is documented, but its source
  artifact and reproducible result summary are not committed.
- **Incomplete**: required implementation, execution, or evidence is absent.
- **Conflict**: committed sources make incompatible claims or cannot execute as
  described.

## Current state at a glance

| Area | Status | Audit conclusion |
|---|---|---|
| Package structure and public API | Verified implemented | Installable package source exists under `PAGe/`; high-level training, forecasting, plotting, validation, and promotion APIs are present. |
| Guarded M0/M1/M2 stage lifecycle | Verified implemented in code/tests | Explicit season selection, tune/validate/fit/freeze states, frozen upstream guards, stable stage identities, guarded kit assembly, tamper checks, and legacy compatibility are implemented. `train_pipeline()` integration remains open. |
| Package source layout | Verified implemented | Package R source is consolidated under `PAGe/R/`; the retired root-level mirror is removed. |
| Input data contract | Verified implemented | Explicit loading, normalization, validation, and synthetic-season generation are implemented and tested. Private surveillance observations are not committed. |
| M0 ignition | Verified implemented in code | Build, tune, retrospective, and prospective runtime paths exist. Numerical production result still depends on ignored local artifacts. |
| M1 alignment | Verified implemented in code | Reference fitting, multi-template alignment, LOSO tuning, peak calibration, and prospective runtime paths exist. The canonical reported MAE is inconsistent across docs. |
| M2 forecasting | Verified implemented in code | Fold building, LOSO evaluation, grid planning, selection, production fitting, frozen runtime, online correction, and post-peak override exist. |
| M2 fold leakage controls | Verified implemented in code/tests | Fold-specific reference/M1 reconstruction and separate train/test manual-label interfaces are present. |
| Fully nested selection of M0/M1/M2 | Incomplete | M2 folds are rebuilt safely, but M0 and M1 hyperparameters are selected globally before the outer M2 evaluation. Current M2 validation is conditional on those choices, not fully nested over every modelling decision. |
| Frozen deployment | Verified implemented | `run_pipeline()`/`run_prospective_pipeline()` default to frozen deployment; weekly refit is explicit compatibility behavior. |
| 2025-26 holdout protection | Verified implemented in code/tests | `train_pipeline()` excludes 2025-26 by default and releases it only after a valid, passing, locked-threshold promotion report. |
| 2025-26 unseen M2 replay | Implemented, execution unverified | Replay and leakage rejection exist; the repository does not preserve the completed real-data replay, metrics, or promotion report. |
| 2025-26 final refit including season | Implemented, execution unverified | The governed fixed-spec refit validates the passing acceptance bundle/manifest and asserts that 2025-26 is released and included before immutable save. No real refit artifact or summary is preserved here. |
| v16 production specification | Implemented and consistently coded | High-level defaults use `k_f=4`, `k_e=2`, `alpha_state=0.15`, `k_sp=6`, `k_r=0`, `k_de=0`, `bias_alpha=0.05`, `bias_beta=0`. |
| v16 NLL 0.4175 | Claimed result, unverified | Repeated in README/docs, but the named result artifact is ignored, absent, and inconsistently named. |
| External/simple forecast baselines | Incomplete | Historical PAGe versions and internal ablations exist; LOCF, historical mean/median, unaligned forecast, and other prespecified external/simple baselines are not implemented as a canonical benchmark suite. |
| Publication-ready evaluation | Incomplete | NLL, Brier, RMSE, MAE, horizon and phase machinery partly exists; locked tables, calibration, interval evaluation, uncertainty, baseline comparisons, and a preserved confirmatory chain remain incomplete. |
| Reproducible public example | Partly implemented | Synthetic data generation, governance tests, and `scripts/public/synthetic_release_workflow.R --smoke` exist. No single public reproduction creates all manuscript tables and figures. |
| Automated tests | Repository suite and source-package check verified locally | The repository test suite, including 74 guarded stage-contract expectations, passes against the clean preflight installation. The earlier source build, vignette rebuild, and `R CMD check --no-manual` completed with no errors or warnings (two inherited static-analysis/environment notes). On 2026-07-29, the default development library could not load `devtools` because installed `fs` 1.6.5 is below a transitive `>= 2.1.0` requirement; the clean preflight library remains usable. |
| CI | Configured; execution pending | `R-CMD-check` now includes a bounded synthetic governance smoke step before the full package check; pkgdown remains separate. The updated workflow has not yet run on GitHub. |

## Verified implementation inventory

### Data and package interface

- [x] `load_flu_hist()` requires an explicit path, `PAGE_FLU_HIST_FILE`, or an
  actually present package file and fails clearly otherwise.
- [x] `prepare_surveillance_data()` and `validate_surveillance_data()` enforce
  the canonical `season`, `weekF`, `y`, `N`, `p`, and `neg` contract.
- [x] `simulate_flu_seasons()` provides deterministic synthetic data generation.
- [x] Public documentation, `NAMESPACE`, roxygen output, pkgdown configuration,
  package tests, and GitHub Actions configuration exist.
- [x] Package R source is consolidated under `PAGe/R/`.
- [x] `validate_season_selection()` records mutually disjoint training,
  exclusion, holdout, and application seasons.
- [x] M0, M1, and M2 expose independent tuning-validation, draft-fit, and
  freeze gates; downstream stages verify frozen upstream identities.
- [x] Governed `assemble_kit()` and `validate_page_kit()` preserve and verify
  season selection plus M0/M1/M2 artifact identities.
- [ ] Refactor `train_pipeline()` to compose the guarded stage lifecycle while
  preserving its current refresh/retune compatibility contract.

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
- [ ] Because the coded `k_ref=25` and `slope_weight=8` values sit at the lower
  edges of the default grid, run a pre-holdout controlled extension (for
  example `k_ref=20`, `slope_weight=4`) on identical folds, or preserve a
  defensible boundary-acceptance decision.
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
- [x] The acceptance script saves the replay, candidate metrics, incumbent
  metrics, canonical promotion report, and a compact provenance manifest.
- [x] The fixed-spec refit and immutable promotion/registry entry points
  validate the complete source-hash chain and refuse output collisions.
- [ ] Run the real acceptance gate with both kits confirmed not to contain
  2025-26 in `training_seasons`.
- [ ] Preserve the passing/failing result before any refit includes 2025-26.
- [ ] If the preserved real decision passes, execute the fixed-spec refit,
  verify 2025-26 in `training_seasons`, and register the resulting kit.

## Conflict ledger

### C01 — Post-acceptance refit inclusion

**Status: implementation resolved; private execution/evidence open.**

`season2526/run_retrain_venkata.R` now requires the immutable acceptance
decision bundle, its disclosure-safe manifest, the exact accepted candidate
and incumbent kits, and authorized data. It runs
`train_pipeline(mode = "refresh")` with artifact-bound verified promotion
evidence and the accepted fixed configuration rather than retuning after
viewing the holdout.

- [x] Require and validate a previously saved, passing canonical decision and
  its source hashes.
- [x] Reject bare promotion reports and pass evidence constructed by
  `verify_promotion_evidence()` from the exact hash-bound artifacts.
- [x] Assert `retuned$holdout$status == "released"`.
- [x] Assert `"2025-26" %in% retuned$kit$m2_production$training_seasons`.
- [x] Fail before saving if the release, inclusion, or fixed-spec assertions
  are false.
- [ ] Execute the private refit after a preserved real passing decision and
  retain its disclosure-safe manifest.

### C02 — Governed refit source document

**Status: implementation resolved; private execution/evidence open.**

The QMD no longer claims an in-sample retrospective replay or an already
completed inclusive retrain. It documents the one-way acceptance-to-refresh
subsequence and leaves all private execution disabled.

- [x] Replace the document with a two-phase reproduction:
  1. untouched 2025-26 replay and frozen promotion decision;
  2. post-decision production refit including 2025-26.
- [x] Use the governed high-level refresh path and propagate the exact accepted
  M0, M1, M2, and runtime settings.
- [x] Remove the invalid in-sample retrospective-evaluation claim; Phase 1
  requires genuine pre-holdout kits.
- [x] Keep only compact disclosure-safe schema checks executable when rendered.
- [ ] Render a fresh HTML snapshot only after source documentation and
  authorized disclosure-safe evidence are ready.

### C03 — Completed runs are not auditable from the repository

**Status: manifest/evidence infrastructure resolved; real result evidence
open.**

`data/`, `results/`, `*.rds`, and `*.csv` are ignored. That appropriately keeps
private observations and large models out of Git, but it also removes every
artifact needed to verify claimed results.

- [x] Keep private data and model objects ignored.
- [x] Allow small disclosure-safe summaries under `results/audit/` through a
  narrow `.gitignore` exception for approved `.json`/`.csv`/`.md` manifests.
- [x] Implement SHA-256 binding for non-committed source artifacts.
- [x] Implement the canonical schema for code commit, run timestamp, R/package
  versions, input-data
  fingerprint, seasons, exclusions, row counts, spec ID, and training seasons.
- [x] Reject row-level payloads from disclosure-safe manifests and write
  aggregate acceptance metrics/diagnostics separately.
- [ ] Execute the private workflows and preserve approved disclosure-safe
  summaries, including the fold/season-level metrics needed for scientific
  claims.

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

**Status: implementation resolved; canonical numerical re-evaluation open.**

- The v16 high-level spec uses `bias_alpha=0.05`.
- Historical notes/rendered docs describe base `bias_alpha=0.4`.
- Runtime raises alpha to 0.7 after two same-sign transitions, meaning on the
  third consecutive same-sign residual.
- Historical research scripts retain explicit 0.2 or 0.4 settings, while
  current package defaults use the canonical base alpha 0.05 and beta 0.

- [x] Distinguish structural spec value, runtime adaptive rule, and legacy
  fallback values in one canonical specification.
- [x] Remove silent legacy fallback from the canonical production path: strict
  mode errors, while explicitly requested compatibility modes warn.
- [x] Ensure LOSO evaluation and frozen runtime use the same correction
  resolver and adaptive transition rule.
- [ ] Re-run the private canonical evaluation to establish results for exactly
  the deployed correction rule.

### C07 — Production artifact naming and promotion are incomplete

**Status: implementation resolved; real promotion execution open.**

Legacy v16 builder scripts still use mutable local filenames, but they are
classified as research-only. The canonical release path is now the gated,
immutable registry workflow.

- [x] Add an explicit, gated promotion command that never overwrites the
  incumbent before acceptance passes.
- [x] Save incumbent and candidate identities and the full upstream hash chain
  in the promotion manifest.
- [x] Make deployment load the promoted artifact by immutable ID and verified
  manifest, not by an ambiguous mutable filename alone.
- [ ] Run the real promotion after a preserved passing acceptance/refit chain.

### C08 — Fresh prospective script contains kit-schema drift

**Status: schema drift resolved; manual kit-smoke path implemented.**

The audited script mixed `$m2` and `$m2_production`. It now uses the canonical
`m2_production` schema and exposes a manual kit-only smoke flag that exits
before live data or replay. No automated test currently invokes that script.

- [x] Replace `$m2` references with `$m2_production`.
- [x] Add a manual `--kit-smoke` entry point that exits after kit loading and
  before any expensive replay.
- [ ] Add an automated test or CI command that executes that kit-smoke path.

### C09 — Runtime fallback configuration is stale

**Status: resolved for the canonical path; compatibility modes remain
explicit.**

The audited loader silently substituted stale M1 and M2 fallbacks. Strict mode
now rejects incomplete canonical artifacts; compatibility behavior is opt-in
and warns.

- [x] Fail closed for a canonical kit missing `M1_PARAMS`; the opt-in
  `locked_defaults` mode uses the centralized locked default with an explicit
  warning.
- [x] Remove outdated v12 fallback-spec discovery from the canonical v16 load
  path.

### C10 — Data documentation conflicts with the repository

**Status: resolved in canonical source and regenerated agent context.**

Generated agent context now matches package code and README: authorized
surveillance observations are not distributed.

- [x] Update `.ai/shared/project-context.md`.
- [x] Regenerate `AGENTS.md` and `CLAUDE.md`; do not edit generated files
  directly.

### C11 — Old and current workflows coexist without a retirement map

**Status: status map and first retirement banner implemented; broader
archival/render cleanup remains open.**

Root `task.md`, v2-v18 tuning scripts, old weekly-refit documentation, current
frozen deployment, v14/v15/v16 production builders, and generated HTML all
remain discoverable. The status map now classifies their intended use; selected
source-level banners and archival/render cleanup remain.

- [x] Create `docs/workflow-status.md` listing each entry point as
  `canonical`, `research-only`, `superseded`, or `broken`.
- [x] Put a clear historical/superseded banner on root `task.md`.
- [ ] Add source-level banners to other high-risk superseded QMDs/scripts where
  the status map alone is insufficient.
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

- [x] Implement the code-path remediations for C01, C02, C03, and C06-C10,
  plus the C11 workflow map.
- [ ] Resolve the scientific/artifact conflicts C04 and C05, execute the
  private C03 evidence chain, and finish the remaining C11 archival/render
  cleanup.
- [x] Add a disclosure-safe result-manifest schema, validator, immutable
  JSON/RDS I/O, and hash-verified promoted-kit loader.
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

- [x] Build one small deterministic synthetic dataset in the canonical raw
  input schema for the public governance smoke workflow.
- [x] Add a bounded public synthetic release-chain smoke command covering
  candidate/incumbent acceptance, fixed refresh, promotion, and verified load
  without private data.
- [ ] Extend the public reproduction to create all manuscript tables and
  figures from a deliberately small, fully fitted grid.
- [ ] Add a public-data replication if licensing and source stability permit.
- [ ] Add a data dictionary and provenance template.
- [ ] Add a frozen R dependency environment.
- [ ] Provide one command that recreates every public table and figure from
  disclosure-safe inputs and manifests.

### P2 — Repository consolidation

- [x] Clearly mark root `task.md` as a historical M0 task while preserving its
  content and provenance.
- [ ] Replace it with an archive pointer only after references are mapped.
- [ ] Establish one canonical workflow entry point for refresh, retune,
  acceptance, promotion, and post-promotion refit.
- [x] Add bounded manifest, holdout-release, acceptance, refit, promotion, and
  registry smoke tests to CI. The first GitHub execution remains pending.
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
