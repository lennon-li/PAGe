# PAGe manuscript plan

Last updated: 2026-09-01

## Manuscript configuration

- **Target journal:** *Epidemics*
- **Article type:** Original methodological research
- **Working title:** *PAGe: Phase-aligned gated forecasting for seasonal respiratory-virus epidemics*
- **Primary audience:** Infectious-disease modellers, epidemiologists, forecasting researchers, and public-health practitioners
- **Internal drafting target:** 7,500--8,500 words, excluding references and supplementary material; reconcile with the current journal guide before submission
- **Language:** English
- **Abstract drafting target:** Up to 250 words, subject to final journal verification
- **Keywords drafting target:** Up to six, subject to final journal verification
- **References:** Use one consistent style during drafting; convert to current journal style at submission
- **Draft format:** Markdown/Quarto initially; convert to the current journal submission format after the scientific content is stable

Journal references:

- [Epidemics: journal homepage](https://www.sciencedirect.com/journal/epidemics)
- [Epidemics: aims and scope](https://www.sciencedirect.com/journal/epidemics/about/aims-and-scope)
- [Epidemics: guide for authors](https://www.sciencedirect.com/journal/epidemics/publish/guide-for-authors)

Independent review status: **REVISE FIRST**. See [`REVIEW_LOG.md`](REVIEW_LOG.md) for Ming's 2026-09-01 review, prioritized gaps, decision criteria, and delegation audit record. The two-track literature synthesis is complete in [`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md) and [`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md); comparator approval and protocol freeze remain open.

## Central research problem

Weekly respiratory-virus positivity curves vary substantially in epidemic onset, speed, amplitude, and peak timing. Forecasting directly on calendar week can therefore pool observations from different epidemic phases. PAGe addresses this problem through a sequential pipeline:

1. M0 prospectively detects epidemic ignition.
2. M1 aligns the partial current-season curve to historical epidemic templates.
3. M2 forecasts one- and two-week-ahead positivity using the aligned state, a frozen binomial GAM, and adaptive online correction.

The manuscript will evaluate whether this decomposition improves short-horizon forecasting while maintaining a leakage-safe, operationally reproducible workflow.

## Provisional thesis

Explicit ignition gating and partial-curve phase alignment may provide a useful representation for forecasting seasonal respiratory-virus positivity when epidemic timing varies between seasons, while the PAGe R package makes the sequential method trainable, testable, and reproducible under explicit provenance and holdout controls. The method is designed for prospective deployment and is evaluated here by retrospective walk-forward replay.

This is a hypothesis to be supported or qualified by the final experiments. It must not be stated as an established conclusion before the canonical results are complete.

## Intended contributions

### Statistical contribution

- A three-stage representation of seasonal epidemic forecasting that separates ignition detection, phase alignment, and short-horizon prediction.
- A multi-template alignment procedure that updates epidemic phase and peak timing from the partial season observed to date.
- A binomial GAM forecast model that incorporates alignment-derived covariates, online season effects, and adaptive bias correction.
- A prospective-information validation design that separates tuning, retrospective walk-forward replay, confirmatory holdout evaluation, and post-acceptance refresh.

### Applied contribution

- A complete Ontario influenza application using weekly positive and total test counts.
- If authorized by the Ontario influenza go/no-go decision, a second-pathogen application using Ontario RSV surveillance data.
- Season-, horizon-, and epidemic-phase-specific evaluation rather than a single pooled accuracy estimate.
- Honest reporting of atypical seasons, failure cases, and the 2025--26 confirmatory holdout decision.

### Software contribution

- The PAGe R package implementing M0, M1, M2, training, replay, and frozen prospective forecasting.
- A generic data-frame adapter that maps user-specified outcome, total, week, season, and start-year columns to the PAGe data contract.
- Guarded stage lifecycles, artifact identities, boundary checks, result manifests, and promotion-evidence validation.
- Synthetic examples and tests that can be distributed without releasing private surveillance observations.

The package API is generic, but predictive validity outside Ontario influenza must not be claimed unless the Ontario RSV application is completed. If undertaken, the RSV analysis will test whether the method can be retrained for a second pathogen within the same jurisdiction; it will not imply that an influenza-fitted model transfers unchanged to RSV or that findings generalize beyond Ontario.

## Research questions

1. Does phase-aligned gated forecasting improve one- and two-week-ahead probabilistic accuracy over simpler calendar-time and persistence baselines?
2. Which components of M0, M1, and M2 account for any observed improvement?
3. How does performance vary by forecast horizon, epidemic phase, and season type?
4. How robust is PAGe to onset shifts, curve-shape variation, low testing volume, observation noise, and ignition error?
5. If the Ontario influenza evidence gate is passed, can the same prespecified PAGe workflow be retrained and evaluated for Ontario RSV?
6. Can the complete statistical workflow be reproduced through a documented R package without future-season leakage?

## Consolidated execution plan

### Authority and current status

This file is the authoritative manuscript plan. [`TODO.md`](TODO.md) is the operational checklist derived from it, and [`REVIEW_LOG.md`](REVIEW_LOG.md) preserves independent reviews and their audit records. If the files conflict, this plan controls until a dated amendment is recorded here.

- **Current decision:** **REVISE FIRST** following Ming's 2026-09-01 independent review.
- **Current phase:** Phase 0, governance and evidence-definition blockers.
- **Blocked work:** Headline Results drafting, Ontario RSV model fitting, and submission formatting.
- **Primary application:** Ontario influenza.
- **Selected conditional application:** Ontario RSV, undertaken only after the Ontario influenza go/no-go gate and an RSV data-support and authorization audit.
- **Target journal:** *Epidemics*, conditional on a verified Ontario kit, defensible comparative evidence, and publication authorization.

### Decisions already fixed

1. The 2025--26 replay remains the untouched confirmatory holdout decision already made: the evaluated candidate failed the locked NLL gate, although horizon and phase gates passed.
2. No specification may be tuned further against 2025--26. Any new search must begin a documented pre-holdout development cycle with a new holdout.
3. Historical M2 LOSO is conditional on globally selected M0/M1 choices and must not be described as fully nested validation.
4. The historical `v16-corrected` incumbent is a confidence baseline, not the manuscript's headline model, unless its complete lineage becomes reconstructible.
5. The headline Ontario model must be re-derived through the governed M0 -> M1 -> M2 lifecycle with recorded stage identities and resolved tuning boundaries.
6. Private Ontario observations will not enter the public repository. Public reproducibility will use synthetic data and any Ontario RSV materials that its access terms permit.
7. Cross-application claims concern workflow portability after pathogen-specific retraining, not transfer of an Ontario-fitted model.
8. Ontario influenza and RSV scores will not be pooled into one headline estimate without a prespecified and scientifically justified weighting model.
9. The method will be described as designed for prospective deployment and evaluated by retrospective walk-forward replay; evidence of actual prospective deployment will not be implied.
10. Ontario RSV is the selected second-pathogen dataset. This fixes the pathogen and jurisdiction, but not the source version, eligible seasons, holdout, access classification, or publication permissions.

### Headline statistical question and proposed primary comparison

The headline question is whether full PAGe improves two-week-ahead probabilistic forecasting of Ontario influenza positivity over a calendar-week binomial GAM that excludes ignition gating and phase alignment.

The proposed primary contrast is full PAGe minus the calendar-week GAM on binomial negative log-likelihood at horizon two, evaluated across eligible Ontario seasonal replays. The sign convention, score normalization, handling of the binomial combinatorial term, aggregation across weeks, and season-level resampling interval must be frozen in a versioned analysis protocol before this comparison is run. A lower score must consistently indicate better performance. Horizon one, persistence, seasonal-naive forecasts, other ablations, phase-specific results, and worst-season results are secondary unless the protocol explicitly promotes one before analysis.

### Stage-gated critical path

| Phase | Objective | Dependencies | Accountable role | Required deliverables | Exit gate | Status |
|---|---|---|---|---|---|---|
| 0. Governance | Resolve inexpensive scientific and authorization blockers | None | Project lead and data steward | Publication authorization; ethics determination; season-exclusion rationale; Ontario revision/backfill rule; documented origin of the 0.02 NLL gate | Every governance decision is dated and traceable | In progress |
| 1. Evidence protocol | Complete literature synthesis and freeze estimands, metrics, labels, comparators, season sets, and uncertainty methods | Phase 0 authorization can proceed in parallel, but must close before private results are released | Manuscript and analysis leads | Literature matrix; versioned analysis protocol; ignition-label protocol; comparator freeze; display plan | No outcome-driven analytical choices remain open | Pending |
| 2. Ontario reconstruction | Re-derive the headline M0 -> M1 -> M2 kit without holdout reuse | Phase 1 protocol | Analysis and software leads | Frozen stage artifacts and identities; boundary audit; package version; M1 recomputation; runtime records | Governed kit validates and every tuned boundary is resolved or justified | Pending |
| 3. Ontario evaluation | Run replays, baselines, ablations, label sensitivity, and uncertainty analysis | Verified Phase 2 kit | Analysis lead | Canonical replay table; primary comparison; secondary analyses; disclosure-safe tables; artifact manifest | All eligible seasons reconcile to immutable outputs and independent checks pass | Pending |
| 4. Journal go/no-go | Decide whether the Ontario evidence supports the intended contribution | Phase 3 evidence and authorization | Project lead with independent reviewer | Dated decision memo: proceed, narrow, redesign, or retarget | *Epidemics* path is explicitly approved or replaced | Pending |
| 5. Simulation | Characterize behavior, failure modes, and template mismatch | Frozen Phase 1 estimands; may be implemented alongside Phases 2--3 | Statistical lead | Prespecified simulation protocol; favorable and unfavorable data-generating processes; Monte Carlo uncertainty; reproducible outputs | Claims are bounded by demonstrated operating conditions | Pending |
| 6. Ontario RSV application | Test workflow portability after pathogen-specific retraining within Ontario | Phase 4 proceed decision and RSV data protocol | Analysis and data leads | RSV data audit; adapter tests; frozen RSV kit; untouched RSV holdout replay; runtime and manifest | RSV completion gate passes, or fallback is documented | Conditional; dataset selected |
| 7. Evidence freeze and drafting | Freeze displays and write the manuscript against verified evidence | Phases 3--5 and Phase 6 if undertaken | Manuscript lead | Immutable result directory; Methods; Results; Discussion; supplement; availability and AI-use statements | Every numerical claim maps to an artifact; no critical evidence gaps remain | Pending |
| 8. Independent review and submission | Stress-test, revise, format, and submit | Phase 7 complete draft | Project lead and independent reviewers | Statistical review; revised manuscript; citation audit; package check; current journal-format audit; cover letter | Submission-readiness checklist passes | Pending |

### Phase 0 and Phase 1 decisions that must be closed

| Decision | Default position for planning | Required evidence | Owner | Due before |
|---|---|---|---|---|
| Ontario publication authorization | Not yet assumed | Written custodian decision and disclosure limits | Data steward | Phase 2 outputs are used publicly |
| Ethics or REB status | Determination required | Institutional or project-level determination | Project lead | Phase 2 |
| Exclusion of 2011--12 and 2015--16 | Justify prospectively or include as sensitivity | Dated epidemiological/data-quality rationale | Scientific lead | Protocol freeze |
| Ontario backfill and revisions | Use only information available at each replay origin where reconstructible; otherwise state the limitation | Source metadata and extraction history | Data lead | Protocol freeze |
| Primary NLL definition | Binomial NLL at horizon two | Exact formula, normalization, and aggregation rule | Statistical lead | Protocol freeze |
| Primary uncertainty analysis | Season-level resampling | Resampling unit, interval type, repetitions, seed, and small-season justification | Statistical lead | Protocol freeze |
| Precision feasibility | Quantify what the available number of seasons can resolve | Expected interval width or detectable score difference under season-level resampling | Statistical lead | Protocol freeze |
| Primary comparator | Calendar-week binomial GAM without M0/M1 | Literature matrix and fair prospective implementation | Scientific lead | Protocol freeze |
| Ignition labels | Reproducible protocol plus perturbation analysis | Labeling instructions, provenance, inter-rule or perturbation checks | Analysis lead | Phase 2 |
| Historical 0.02 NLL gate | Preserve as historical only unless prespecification is documented | Dated provenance and rationale | Project lead | Results interpretation |
| Final comparator set | Seven recommended standalone models plus explicit PAGe ablations, with optional additions time-boxed | Literature matrix and implementation feasibility | Scientific lead | Protocol freeze |
| Second-pathogen dataset | Ontario RSV selected; no fitting before the Ontario influenza go/no-go | Source/version record, access and publication terms, denominators, season count, revisions, and missingness | Data lead | Phase 6 |
| Manuscript package version | Pin the exact release or commit used for all final analyses | Package version, commit, lockfile/session information | Software lead | Phase 2 freeze |

### Ontario evidence requirements

The Ontario analysis is manuscript-ready only when all of the following exist in one immutable, manifest-bound result set:

1. A re-derived governed kit with validated M0, M1, and M2 identities.
2. A boundary audit covering every genuinely tuned parameter.
3. Recomputed M1 validation evidence or an explicit retirement of irreconcilable historical values.
4. Complete walk-forward predictions for every eligible replay season and horizon.
5. The primary PAGe versus calendar-week GAM comparison with season-clustered uncertainty.
6. Persistence, seasonal-naive, and all prespecified component-ablation results.
7. Ignition-label perturbation and all-M0-label sensitivity analyses.
8. A canonical replay table containing season, horizon, phase, target, prediction, score, model identity, artifact identity, and runtime provenance.
9. A reconciliation showing that all reported tables and figures derive from the same canonical inputs.
10. The historical 2025--26 holdout result reported unchanged and clearly separated from any new development cycle.

### Go/no-go decision after Ontario evaluation

Proceed with the *Epidemics* path when the governed influenza kit is verified, publication is authorized, and the prespecified primary comparison shows a defensible benefit whose season-level uncertainty excludes no benefit. If the primary estimate is favorable but imprecise, narrow the efficacy claim and require supportive simulations before proceeding. The Ontario RSV application may then strengthen cross-pathogen workflow-portability evidence but cannot rescue an unsupported influenza headline result.

Narrow or retarget the manuscript when the primary contrast remains within resampling uncertainty, kit reconstruction fails, or private-data publication is not authorized. Redesign the method or its claims when ignition-label sensitivity indicates that apparent gains depend mainly on manually selected labels. Record the decision in a dated memo and link it from this plan.

### Evidence and artifact organization

All final analytical products must be collected under one immutable analysis identifier in `manuscript/results/<analysis-id>/`. That directory should contain or reference, through checksummed manifests:

- the frozen protocol and season-selection declaration;
- package and artifact identities;
- canonical prediction and replay tables;
- stage, comparator, ablation, simulation, and sensitivity summaries;
- runtime and environment records;
- table and figure input files;
- generated disclosure-safe tables and figures; and
- a manifest mapping every manuscript result to code, inputs, and checksums.

Private observations must remain outside the public repository. The public release should preserve scripts, synthetic inputs, permitted aggregate outputs, and an authorized file-path interface for reproducing the private-data workflow.

### Plan maintenance

- Update phase status only when its exit gate is supported by recorded evidence.
- Record scientific changes as dated amendments; do not overwrite holdout or prespecification history.
- Assign a named person to each accountable role before that phase begins.
- Link completed checklist items in [`TODO.md`](TODO.md) to their supporting artifact or decision record.
- Request independent review at the Phase 4 go/no-go gate and again before submission.

## Manuscript structure

### Abstract -- up to 250 words

State the forecasting problem, methodological contribution, validation design, main numerical findings from every completed application, and package availability. Do not write the final abstract until all headline results are frozen.

### 1. Introduction -- approximately 800 words

- Motivate timely respiratory-virus forecasting for public-health decisions.
- Explain why calendar time is an unstable epidemic coordinate across seasons.
- Review the main categories of infectious-disease and seasonal-curve forecasting approaches.
- Identify the gap: prospective phase alignment and operational leakage control are rarely treated as one statistical workflow.
- State the contributions and preview the empirical findings without overselling them.

### 2. Data structure and forecasting target -- approximately 550 words

- Define season index, MMWR week, within-season week, positive tests, total tests, and observed positivity.
- Define the one- and two-week-ahead binomial forecasting targets.
- Define the information available at each forecast origin.
- Distinguish observed positivity from the underlying positivity probability.
- State the season construction, exclusions, denominator definition, and missing-data rules separately for each completed application.
- Explain which elements of the workflow are shared and which are pathogen-specific.

### 3. PAGe methodology -- approximately 1,800 words

#### 3.1 M0: ignition detection

- Prospective threshold gates and sustained-elevation requirement.
- Eligibility window and ignition locking.
- Tuning objective and ignition-error definition.

#### 3.2 M1: phase alignment

- Historical reference/template construction.
- Shift, dilation, amplitude, and offset parameters.
- Multi-template weighting by fit and slope similarity.
- Peak estimate, alignment uncertainty, and post-peak freezing.

#### 3.3 M2: short-horizon forecasting

- Joint binomial GAM for horizons one and two.
- Aligned-time, template, EWMA, derivative, and uncertainty features.
- Frozen model, online season effect, and adaptive bias correction.
- Forecast algorithm using information available through the current week only.

#### 3.4 End-to-end algorithm

- Show the sequential M0 -> M1 -> M2 weekly algorithm.
- Separate offline tuning/fitting from online forecasting.
- Provide pseudocode in the main paper and implementation detail in the supplement.

### 4. Training and validation design -- approximately 900 words

- Declare disjoint training, exclusion, holdout, and application season sets.
- Describe fold-specific construction of leakage-sensitive features.
- Describe stagewise tuning and boundary expansion before holdout access.
- Distinguish conditional M2 LOSO from fully nested evaluation of all three stages.
- Explain retrospective seasonal replay, confirmatory holdout replay, and promotion gates.
- Define the primary and secondary metrics and their uncertainty estimates.

### 5. Simulation study -- approximately 900 words

Vary the following factors:

- Epidemic onset shift.
- Peak timing and epidemic duration.
- Amplitude and baseline positivity.
- Symmetric versus asymmetric curve shape.
- Single- versus multi-wave seasons.
- Testing volume and binomial noise.
- Missing weeks or reporting disruptions.
- Ignition detection error.
- Template mismatch and alignment uncertainty.

Compare the full method with the prespecified baselines and ablations. Report Monte Carlo uncertainty for every simulation summary.

### 6. Respiratory-virus applications and results -- approximately 1,600 words

#### 6.1 Ontario influenza

- Describe the authorized Ontario weekly surveillance data and season selection.
- Present M0 ignition accuracy and M1 peak-timing accuracy separately.
- Present M2 forecast performance by season, horizon, and epidemic phase.
- Compare against all prespecified baselines.
- Present historical replays in one canonical table.
- Present the 2025--26 holdout result as confirmatory evidence.

#### 6.2 Ontario RSV, if authorized

- Audit the selected Ontario RSV source, version, access terms, season support, denominators, reporting revisions, and missingness before fitting models.
- Recreate the full data contract from one authorized weekly RSV data frame.
- Retrain PAGe end to end using the same governed lifecycle and prespecified analysis rules.
- Reserve a final season as an untouched confirmatory holdout.
- Report stage-level and forecast-level metrics using definitions harmonized with the Ontario analysis.

#### 6.3 Cross-application synthesis

- Compare patterns of benefit and failure without pooling incompatible surveillance systems into one headline estimate.
- Separate workflow portability from direct model transportability.
- Report atypical seasons and material failure cases rather than averaging them away.
- Include training and replay runtimes.

### 7. PAGe R package -- approximately 750 words

- Package architecture and the M0/M1/M2 API.
- Generic `prepare_page_data()` interface and canonical data contract.
- Guarded `tune_*() -> validate_*() -> fit_*() -> freeze_*()` lifecycle.
- Kit assembly, artifact identity, manifests, and promotion evidence.
- Synthetic and public-data workflows that readers can run without private Ontario data.
- Package tests, platform information, installation, and versioned release.

### 8. Discussion -- approximately 650 words

- Interpret the statistical and operational findings.
- Explain when phase alignment appears useful and when it does not.
- Discuss the implications of the confirmatory holdout result.
- Address dependence on ignition labels, limited season count, atypical pandemic seasons, surveillance-system heterogeneity, and model misspecification.
- Separate generic software capability from evidence of cross-disease transportability.
- Identify prospective multi-pathogen and multi-jurisdiction deployment as future work.

### Data and software availability

- Publicly release the package, synthetic data generator, simulation code, and manuscript analysis scripts.
- Do not commit or distribute private surveillance observations.
- Prepare a data-availability statement describing the Ontario access restrictions and any controlled-access process.
- Archive a versioned Ontario RSV retrieval/preparation script and any distributable inputs, subject to source access and licence terms.
- Provide disclosure-safe aggregate tables only after confirming they meet organizational policy.

## Prespecified comparisons

The final comparator set must be selected before generating the headline results. The literature-supported recommendation and rationale are recorded in [`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md). At minimum it should include:

1. Last-observation or persistence forecast.
2. Seasonal-naive forecast using the corresponding historical week.
3. Calendar-week binomial GAM without ignition gating or alignment.
4. Forecast model with M0 but without M1 alignment.
5. PAGe without adaptive bias correction.
6. PAGe without alignment-uncertainty features.
7. Full PAGe.

The completed literature review recommends adding a low-dimensional lagged penalized binomial model, a prospective historical-analogue continuation model, and one regularized tree model to the core comparison. A Gaussian process, empirical-Bayes full-curve model, and SIR/SIRS ensemble-filter model are time-boxed optional additions. The scientific lead must approve the final set and freeze it in the analysis protocol; no model may be added in response to headline results.

## Outcome measures

### Primary

- Binomial negative log-likelihood, preserving weekly test denominators.

### Secondary

- Mean absolute error in positivity.
- Root mean squared error or Brier-type score, with the exact definition fixed before analysis.
- Calibration intercept/slope or reliability summaries where season counts permit.
- M0 ignition-week absolute error and miss rate.
- M1 peak-week absolute error.
- Worst-horizon and worst-phase degradation.
- Runtime and failure rate.

Results must be stratified by horizon and relevant epidemic phase. Uncertainty should account for clustering within seasons, preferably through season-level resampling or a clearly justified alternative.

## Planned figures

1. Statistical and operational M0 -> M1 -> M2 workflow.
2. Conditional-LOSO, replay, and holdout timeline showing information boundaries.
3. Representative partial-curve alignment sequence for one season.
4. Observed and forecast trajectories for Ontario influenza and, if completed, Ontario RSV.
5. Forecast performance by horizon and epidemic phase.
6. Simulation or ablation results across timing and shape mismatch.
7. Influenza-versus-RSV comparison of component gains and failure modes.
8. Calibration or forecast-error distribution, if supported by the final sample size.

All figures must remain interpretable in grayscale and use accessible colours.

## Planned tables

Main text, subject to the journal's current limits:

1. Data sources, pathogens, seasons, exclusions, and observation counts.
2. M0, M1, and M2 components, frozen specifications, baselines, and ablations.
3. Ontario stage-level and forecast comparisons, including the canonical replay summary.
4. Simulation and, if completed, Ontario RSV synthesis.

Supplement:

1. Full M0 and M1 stage-level validation results.
2. Complete season-by-horizon replay table.
3. Phase-specific, worst-season, and sensitivity results.
4. Full simulation results.
5. Ontario RSV validation details, if undertaken.
6. Package validation, runtime, and reproducibility environment.

## Evidence that must be reconciled before drafting Results

- Produce one canonical result table containing every eligible seasonal replay.
- If Phase 6 is authorized, freeze the Ontario RSV source version, season definitions, exclusions, comparators, and holdout before model fitting.
- If Phase 6 is authorized, complete the end-to-end Ontario RSV application without using its holdout for tuning or manual-label construction.
- Verify the provenance of each candidate and incumbent artifact.
- Resolve or explicitly retire the conflicting historical M1 peak-MAE values.
- Do not describe historical M2 LOSO as fully nested when M0/M1 choices were globally selected.
- Preserve the existing 2025--26 holdout decision: the evaluated candidate failed the locked NLL gate, although its horizon and phase gates passed.
- Do not tune further against 2025--26. Any new search begins a new pre-holdout development cycle.
- Verify boundary winners and document expansions, null boundaries, or hard constraints.
- Record complete training and replay runtimes from machine-readable run records.
- Put all final manuscript result tables and figure inputs in a single immutable analysis directory.

## Literature-review workstreams

Search and synthesize literature on:

1. Short-horizon multi-pathogen respiratory-virus forecasting.
2. Epidemic phase, curve registration, and functional alignment.
3. Change-point and epidemic-onset detection.
4. Dynamic generalized additive models and adaptive forecast correction.
5. Prospective, rolling-origin, and leave-one-season-out evaluation.
6. Forecast calibration and proper scoring rules for binomial surveillance data.
7. Statistical software for infectious-disease forecasting.

The literature review is complete in [`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md) and [`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md). It identifies existing implementations and compares their assumptions, data requirements, outputs, and relevance to PAGe. The resulting comparator set still requires scientific-lead approval and protocol freeze.

## Reproducibility package

The manuscript release should contain:

- A versioned PAGe package release.
- Installation and system requirements.
- A single public replication entry point.
- Fixed random seeds and recorded package versions.
- Synthetic data reproducing the full API workflow.
- If Phase 6 is completed, a versioned Ontario RSV retrieval and preparation workflow with public or restricted status documented.
- Public simulation inputs and outputs.
- Disclosure-safe manuscript tables and figures.
- A private-data analysis script accepting an authorized file path.
- A result manifest binding tables and figures to code and artifact identities.
- A test and package-check report.

## Drafting workflow

Draft in the order established by the consolidated critical path:

1. Write the reproducible Methods and protocol skeleton after Phase 1 freezes the analysis choices.
2. Do not draft headline Results until the Ontario Phase 3 evidence gate passes.
3. Draft Ontario Results directly from the immutable canonical replay inputs.
4. Draft Simulation Results after the simulation completion gate.
5. Add Ontario RSV Methods and Results only if Phase 6 is authorized and completed.
6. Write the Introduction after the literature matrix and empirical contribution are stable.
7. Write the Discussion after all included applications and sensitivity analyses are frozen.
8. Write the abstract last, using only traceable numerical findings.
9. Conduct citation, notation, data/code availability, numerical-claim, and writing-quality audits.
10. Complete independent review, one major revision round, journal formatting, supplement, cover letter, and disclosure statements.

Record all AI-assisted work and prepare a disclosure consistent with the Elsevier and journal policies in force at submission.

## Submission-readiness gates

The manuscript is ready for submission only when all of the following are true:

- [ ] The central thesis is supported or appropriately narrowed by the final evidence.
- [ ] The comparator set was prespecified and evaluated with leakage-safe walk-forward information boundaries.
- [ ] If Phase 6 was authorized, Ontario RSV completed the full governed workflow with an untouched final holdout; otherwise, cross-pathogen claims and RSV manuscript sections are absent.
- [ ] Claims distinguish method portability after retraining from direct cross-pathogen model transportability.
- [ ] All tuning boundaries are resolved or justified.
- [ ] All seasons appear in one canonical replay table with consistent definitions.
- [ ] The 2025--26 holdout is reported without post-holdout tuning.
- [ ] Every table and figure is generated from a frozen analysis artifact.
- [ ] Every numerical claim is traceable to a result table or script.
- [ ] Private observations are absent from the public repository.
- [ ] Synthetic replication materials exercise the complete package workflow.
- [ ] Package tests and checks pass in the release environment.
- [ ] Data, code, conflicts, funding, ethics, and AI-use statements are complete.
- [ ] The final manuscript conforms to the current *Epidemics* guide for authors.

## Fallback journal strategy

If the combined paper is not suitable for *Epidemics*:

1. Submit the method-and-medical-application version to *Statistics in Medicine*.
2. Submit a respiratory-virus-focused version to *Influenza and Other Respiratory Viruses* after reducing it to that journal's article length.
3. Reframe toward forecasting evaluation for the *International Journal of Forecasting*.
4. If the package becomes the primary contribution and every reported result can be exactly reproduced publicly, restructure for the *Journal of Statistical Software*.
