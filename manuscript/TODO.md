# PAGe manuscript execution TODO

Last updated: 2026-09-01

Authoritative consolidated plan: [`PLAN.md`](PLAN.md)

Independent review record: [`REVIEW_LOG.md`](REVIEW_LOG.md)

This file is the execution checklist. Section numbers below group related work but do not override the phase order and exit gates in `PLAN.md`. Every checked item must link to its supporting decision record or artifact.

- **Current phase:** Phase 0, governance and evidence-definition blockers.
- **Blocked until the Ontario influenza go/no-go gate:** Ontario RSV model fitting and RSV-results drafting.

## 0. Ontario influenza evidence must precede RSV validation

Ming's 2026-09-01 independent review concluded **REVISE FIRST**. Complete this workstream before committing substantial effort to the Ontario RSV application.

- [ ] Re-derive the manuscript's frozen Ontario kit end to end through the governed `tune_*() -> validate_*() -> fit_*() -> freeze_*()` lifecycle and record every stage and kit identity.
- [ ] Treat the historical `v16-corrected` incumbent as contextual evidence unless its lineage becomes fully reconstructible.
- [ ] Resolve all genuinely tuned boundaries before freezing the manuscript kit.
- [ ] Recompute M1 validation results and either resolve or retire the conflicting historical peak-MAE values.
- [x] Complete the independent literature review and evidence matrix: [`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md) and [`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md).
- [ ] Obtain scientific-lead approval and freeze the literature-supported comparator and ablation set in the versioned analysis protocol.
- [ ] Prespecify one primary comparison, its horizon, metric, aggregation, uncertainty method, and interpretation threshold; classify all other comparisons as secondary or exploratory.
- [ ] Freeze the exact binomial NLL formula, normalization, combinatorial-term handling, sign convention, and weekly/seasonal aggregation.
- [ ] Record an expected interval width or detectable score difference under the planned season-level resampling method.
- [ ] Evaluate all seven planned Ontario comparators and ablations across eligible seasons using season-level resampling.
- [ ] Produce the canonical Ontario replay table with consistent season, horizon, phase, metric, artifact identity, and runtime fields.
- [ ] Write and version the ignition-labeling protocol; run label-perturbation and all-M0-label sensitivity analyses.
- [ ] Add a dated rationale for excluding 2011--12 and 2015--16, or include them in a prespecified sensitivity analysis.
- [ ] Define Ontario backfill and reporting-revision handling.
- [ ] Confirm data-custodian publication authorization and any research-ethics requirements.
- [ ] Document the provenance and rationale of the historical 0.02 NLL gate; treat it as historical rather than prespecified if provenance cannot be established.
- [ ] Pin the package version, repository commit, dependencies, and runtime environment used for manuscript analyses.
- [ ] Assign a named person to every accountable role before its phase begins.
- [ ] Run at least one simulation data-generating process that is structurally unfavorable to PAGe's templates.
- [ ] Hold a documented go/no-go review before the Ontario RSV application: proceed, narrow the claims, redesign, or retarget the journal based on the influenza evidence.

## Gap to close

The PAGe API can accept arbitrary weekly surveillance data, but the empirical evidence currently comes from Ontario influenza. A generic data adapter demonstrates software flexibility; it does not establish predictive validity for RSV.

Ontario RSV is the selected second-pathogen application. After the Ontario influenza evidence gate is passed and the RSV source audit is complete, run Ontario RSV through the full governed M0 -> M1 -> M2 workflow. The intended claim is **cross-pathogen workflow portability after pathogen-specific retraining within the same jurisdiction**, not direct transfer of an influenza-fitted model to RSV.

## 1. Freeze the Ontario RSV validation question

- [x] State the RSV question: can the same PAGe workflow be retrained for Ontario RSV and evaluated with leakage-safe walk-forward replay?
- [x] Explicitly exclude direct influenza-to-RSV model transfer from the primary claim.
- [x] Hold jurisdiction constant and evaluate pathogen contrast: Ontario influenza versus Ontario RSV.
- [ ] Freeze RSV dataset suitability criteria before data profiling or model fitting.
- [x] Record the Ontario RSV selection in the manuscript evidence log.
- [ ] Record the scientific rationale for choosing Ontario RSV.

## 2. Audit and document the selected Ontario RSV dataset

Required characteristics:

- [ ] Weekly observations over enough seasons for training, tuning, and a final holdout.
- [ ] Positive counts and total tests, or positive and negative counts, so the binomial target is preserved.
- [ ] Stable week and season identifiers or enough date information to construct them.
- [ ] Access, licence, and publication terms documented, including whether observations or only code/aggregates may be shared.
- [ ] Versioned download, archive, or retrieval date.
- [ ] Documentation of revisions, reporting delays, suppression, and missingness.

Selection fixed:

- [x] Ontario RSV surveillance data selected as the second-pathogen application.
- [ ] Identify the exact source table/file, owner, extraction method, and source version.
- [ ] Confirm whether the source is public, controlled access, or private.

Selection deliverable:

- [ ] Create `manuscript/ontario-rsv-data-audit.md` with source/access information, licence or authorization, schema, season count, completeness, denominator availability, revision behavior, and final suitability decision.

## 3. Define the Ontario RSV analysis before fitting

- [ ] Define season start and end rules.
- [ ] Define included, excluded, training, validation, and final holdout seasons.
- [ ] Reserve the most recent complete eligible season as the untouched holdout.
- [ ] Define missing-week and reporting-revision handling.
- [ ] Define ignition labels without consulting holdout outcomes.
- [ ] Freeze the primary metric as binomial negative log-likelihood.
- [ ] Freeze secondary metrics, phase definitions, and uncertainty method.
- [ ] Freeze comparator and ablation definitions.
- [ ] Define boundary-expansion stopping rules before tuning.
- [ ] Hash or otherwise version the protocol before model fitting.

## 4. Build one Ontario RSV input data frame

- [ ] Retrieve the authorized RSV data with a scripted, versioned process where permitted.
- [ ] Put all eligible Ontario RSV observations into one data frame.
- [ ] Preserve source identifiers and retrieval metadata as columns or sidecar metadata.
- [ ] Map the data through `prepare_page_data()` using explicit outcome, total/negative, week, season, and start-year columns.
- [ ] Check duplicate season-week rows.
- [ ] Check missing, negative, non-integer, and impossible counts.
- [ ] Check positivity limits and zero denominators.
- [ ] Verify 52/53-week boundaries and season transitions.
- [ ] Document any aggregation performed before the PAGe adapter.

## 5. Add package tests for the Ontario RSV schema

- [ ] Add a synthetic fixture matching the Ontario RSV source schema without containing restricted observations.
- [ ] Test exact column mapping and MMWR/within-season conversion.
- [ ] Test first and last seasonal weeks, including a 53-week year if present.
- [ ] Test missing denominator, duplicate week, impossible count, and malformed season failures.
- [ ] Test that metadata columns survive mapping.
- [ ] Run the adapter test and full package suite.
- [ ] Run package checks in a bounded environment and record pre-existing versus new findings.

## 6. Run the Ontario RSV M0 -> M1 -> M2 workflow

- [ ] Run data preflight and support audit.
- [ ] Tune, validate, fit, and freeze M0 using training seasons only.
- [ ] Inspect every genuinely tuned M0 boundary and resolve it before M1.
- [ ] Tune, validate, fit, and freeze M1 using a matching frozen M0.
- [ ] Inspect every genuinely tuned M1 boundary and resolve it before M2.
- [ ] Tune, validate, fit, and freeze M2 using matching frozen M0/M1 identities.
- [ ] Inspect M2 boundaries and apply prespecified stopping rules.
- [ ] Assemble and validate the Ontario RSV PAGe kit.
- [ ] Record stage and total runtimes from machine-readable status files.
- [ ] Preserve immutable tuning summaries, kit identity, selection, and manifests.

## 7. Evaluate without leakage

- [ ] Produce complete walk-forward predictions for every eligible validation season.
- [ ] Verify that each held-out season is absent from all fold-specific training objects and manual labels.
- [ ] Evaluate persistence and seasonal-naive baselines.
- [ ] Evaluate the calendar-week GAM without gating/alignment.
- [ ] Evaluate the prespecified PAGe component ablations.
- [ ] Replay the final RSV holdout exactly once after all choices are frozen.
- [ ] Do not tune or revise the selected specification in response to the RSV holdout.
- [ ] If a new search is required, start and document a new development cycle with a new holdout.

## 8. Harmonize results across applications

- [ ] Use identical metric definitions for Ontario influenza and RSV.
- [ ] Use identical horizon and epidemic-phase labels where scientifically meaningful.
- [ ] Keep source-specific metrics separate when surveillance processes are not comparable.
- [ ] Do not pool influenza and RSV NLL into one headline number without a justified weighting model.
- [ ] Compare component gains, calibration patterns, and failure modes across applications.
- [ ] Create one canonical manuscript table per application plus a cross-application synthesis table.
- [ ] Store all final table and figure inputs in one immutable manuscript-results directory.

## 9. Complete simulations and sensitivity analyses

- [ ] Simulate pathogen-like variation in onset, duration, amplitude, and curve asymmetry.
- [ ] Include single- and multi-wave epidemics.
- [ ] Vary denominator size and binomial observation noise.
- [ ] Include missing weeks and reporting disruptions.
- [ ] Perturb ignition labels and template similarity.
- [ ] Evaluate the full method, baselines, and ablations under the same scenarios.
- [ ] Report Monte Carlo uncertainty and random seeds.
- [ ] Identify conditions where phase alignment harms rather than helps forecasts.

## 10. Update the manuscript evidence package

- [ ] Update the title and abstract to use respiratory-virus rather than Ontario-specific framing.
- [ ] Add the Ontario RSV data source and protocol to Methods.
- [ ] Add separate Ontario influenza and RSV subsections to Results.
- [ ] State clearly that each pathogen-specific model was retrained.
- [ ] Add a cross-application synthesis without overstating generalizability.
- [ ] Update limitations to cover surveillance-system heterogeneity and limited pathogen count.
- [ ] Add public data, code, package, conflicts, funding, ethics, and AI-use statements.
- [ ] Verify the current *Epidemics* author guide immediately before formatting.

## 11. Ontario RSV completion gate

Do not make a multi-pathogen portability claim until all boxes below are checked:

- [ ] The Ontario RSV source, access classification, licence or authorization, and publication permissions are documented.
- [ ] The analysis protocol predates model fitting and holdout access.
- [ ] The full stage lifecycle completed with resolved boundaries.
- [ ] Fold and label leakage checks passed.
- [ ] Baselines and ablations used prespecified definitions.
- [ ] The final RSV holdout was evaluated once and was not used for tuning.
- [ ] Runtime, failures, and negative findings are reported.
- [ ] Public replication materials reproduce the RSV analysis or its permitted synthetic/disclosure-safe equivalent.
- [ ] Claims are limited to the pathogens, jurisdictions, targets, and horizons actually evaluated.

## Fallbacks if Ontario RSV is unsuitable

1. Use a public RSV dataset from another jurisdiction, preserving cross-pathogen validation while adding jurisdictional heterogeneity.
2. Use another public respiratory-virus target only after confirming denominator compatibility; do not silently treat incidence as positivity.
3. Retain Ontario influenza as the sole application, narrow the claims, and revert the target journal to *Statistics in Medicine*.
4. Split the work into an infectious-disease methods paper and a later package/software paper.
