# PAGe manuscript skeleton for *Epidemics*

Last updated: 2026-09-01

Status: **authoring guide; Methods can be filled now, numerical Results remain
blocked by the evidence gates in [`PLAN.md`](PLAN.md).**

Working title: *PAGe: A staged framework for epidemic ignition, phase
alignment, and short-horizon respiratory-virus forecasting*

## How to use this skeleton

Fill the manuscript section by section in the recommended order at the end of
this file. Keep the following markers until the required evidence exists:

- `[DRAFT REQUIRED]` — prose can be written from frozen methods or verified
  sources.
- `[RESULT REQUIRED]` — insert only from the immutable canonical result set.
- `[CITATION REQUIRED]` — add only after checking the source itself.
- `[ARTIFACT REQUIRED]` — link the exact table, figure input, kit, or manifest.
- `[DECISION REQUIRED]` — a scientific or governance choice remains open.
- `[DATA REQUIRED]` — supplied data or its audit is still pending.
- `[NOT APPLICABLE]` — remove the subsection and associated claims if its gate
  fails.

The manuscript must consistently say that PAGe is **designed for prospective
deployment and evaluated by retrospective walk-forward replay**. Training,
tuning, fitting, and freezing occur once for each target season; the same frozen
seasonal kit is reused at every weekly origin. Weekly M0 decisions, M1 alignment,
M2 forecasting, and permitted adaptive correction are state updates, not model
retraining.

## Paper-level argument

### Problem

Calendar week is an unstable coordinate for seasonal respiratory-virus
epidemics because ignition, growth, and peak timing vary among seasons.

### Proposed solution

PAGe decomposes the operational task into an aligned sequence:

1. M0 detects epidemic ignition from information available at the forecast
   origin.
2. M1 estimates current phase and peak timing by aligning the partial curve to
   historical templates.
3. M2 predicts positivity one and two weeks ahead using the aligned state and a
   frozen binomial GAM with governed online correction.

### Claim to earn

The confirmatory claim concerns the **assembled PAGe workflow**, not phase
alignment in isolation. For eligible Ontario influenza seasonal replays, full
PAGe improves two-week-ahead per-trial binomial negative log-likelihood relative
to the prespecified calendar-week binomial GAM, with benefits and failures
characterized by season, horizon, and epidemic phase. `[RESULT REQUIRED]`

The full-PAGe versus no-M1-alignment ablation is the pre-identified descriptive
attribution diagnostic for phase alignment. It remains secondary and cannot
replace or multiply the confirmatory comparison. `[RESULT REQUIRED]`

Ontario RSV may support a narrower portability claim: the same workflow can be
retrained and evaluated for a second pathogen in the same jurisdiction. It
cannot establish direct transfer of an influenza-fitted model or broad
cross-jurisdiction generalizability. `[DATA REQUIRED] [RESULT REQUIRED]`

## Section and word-budget map

| Section | Draft target | Main job | Current status |
|---|---:|---|---|
| Abstract | <=250 words, pending final guide check | Compress problem, method, validation, findings, and implication | Blocked by Results |
| 1. Introduction | 700--800 | Establish the phase-misalignment gap and contributions | Ready after citation selection |
| 2. Data structure and forecasting targets | 500--600 | Define observations, seasons, targets, and governance | Partly ready; data decisions open |
| 3. PAGe methodology | 1,600--1,800 | Define M0, M1, M2, and seasonal/weekly algorithm | Ready from frozen protocol and package evidence |
| 4. Training and validation design | 900--1,100 | Establish leakage safety, comparators, metrics, and uncertainty | Ready except final season declarations |
| 5. Simulation design | 500--650 | Prespecify operating conditions and failure modes | Protocol required |
| 6. Applications and results | 1,600--1,900 | Report empirical and simulation evidence in claim order | Blocked by canonical results |
| 7. PAGe R package | 400--550 | Establish reproducible implementation and provenance | Partly ready; release evidence open |
| 8. Discussion | 700--850 | Interpret utility, mechanisms, failures, and scope | Blocked by Results |
| 9. Conclusion | 100--150 | State only the supported contribution | Blocked by Results |

Target body length: approximately 7,500--8,400 words before final journal
compression. Section ceilings sum to 8,400 words and remain inside the
8,400-word planning cap.

## Front matter

### Title page

- Title: `[DECISION REQUIRED]` retain the staged-framework working title only if
  the Phase-4 go/no-go memo supports the assembled-workflow contribution.
- Authors, affiliations, corresponding author: `[DRAFT REQUIRED]`
- Short title: `[DRAFT REQUIRED]`

### Highlights

Draft three to five short, result-bearing bullets after Results are frozen.
Recent comparable articles use highlights, but exact submission requirements
must be rechecked against the live journal guide.

- PAGe links epidemic ignition, phase alignment, and short-horizon forecasting.
- One frozen model kit is trained per target season and reused at weekly origins.
- `[RESULT REQUIRED]` Primary two-week probabilistic comparison, including an
  explicit favorable, inconclusive, or harmful interpretation.
- `[RESULT REQUIRED]` One descriptive stage or failure-mode finding, labelled
  secondary rather than evidence of superiority.
- `[RESULT REQUIRED]` Ontario RSV portability finding only if completed and
  retained after the influenza go/no-go decision.

If the primary season-bootstrap interval contains zero, describe the result as
inconclusive and reconsider the title and journal path under the Phase-4 memo.
If the interval is wholly positive, report harm without substituting a favorable
secondary finding as the headline.

### Abstract

Use a compact problem-method-results-conclusion flow. Whether headings are
retained should follow the final journal-format audit.

- **Problem (35--40 words):** Why calendar-time pooling can mix epidemic phases.
- **Methods (75--85 words):** M0 -> M1 -> M2; once-per-season training;
  retrospective walk-forward seasonal replay; primary h2 NLL comparison.
- **Results (75--85 words):** `[RESULT REQUIRED]` Effect estimate, paired
  season-level uncertainty, h1/phase context, and RSV result if applicable.
- **Conclusion (30--40 words):** `[DECISION REQUIRED]` State the narrowest
  conclusion supported by the evidence.

The maxima of these drafting ranges total 250 words; do not exceed any range by
borrowing untracked words from another abstract component.
- Keywords: epidemic forecasting; influenza; epidemic phase; curve alignment;
  probabilistic forecasting; respiratory syncytial virus only if the RSV
  application is retained.

### Graphical abstract

Optional drafting asset pending the current author-guide check: depict one
seasonal kit trained once, then weekly `M0 -> M1 -> M2` state updates and
forecasts under a visible prospective-information boundary.

## 1. Introduction

### 1.1 Operational forecasting problem

- **Purpose:** Establish why ignition, peak timing, and one-/two-week forecasts
  matter to respiratory-virus surveillance decisions.
- **Claim:** Decision support needs both epidemic landmarks and calibrated
  short-horizon predictions.
- **Evidence:** Public-health forecasting and respiratory-virus literature.
- **Display:** None.
- **Status:** `[CITATION REQUIRED] [DRAFT REQUIRED]`

### 1.2 Why calendar time is an unstable epidemic coordinate

- **Purpose:** Explain onset, growth-rate, duration, amplitude, and peak-timing
  variation among seasons.
- **Claim:** Equal calendar weeks need not represent equal epidemic states.
- **Evidence:** Ontario descriptive evidence plus curve-registration and
  seasonal-epidemic literature.
- **Display:** Table 1 supplies season support; no result should be previewed
  before its audit.
- **Status:** `[CITATION REQUIRED] [RESULT REQUIRED]`

### 1.3 Existing mathematical, statistical, and machine-learning approaches

- **Purpose:** Review the three model families requested for this paper.
- **Claim:** Mechanistic models encode transmission structure; statistical
  models offer parsimonious and calibrated baselines; ML models capture
  nonlinear interactions but require adequate independent training support.
- **Evidence:** [`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md) and
  [`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md).
- **Display:** None; keep this synthesis selective.
- **Status:** `[DRAFT REQUIRED]`

### 1.4 Gap and contributions

- **Purpose:** State what is not addressed by forecasting alone.
- **Claim:** Few workflows jointly govern prospective ignition detection,
  partial-curve phase/peak alignment, probabilistic forecasting, once-per-season
  training, and artifact-level reproducibility.
- **Evidence:** Verified literature; avoid an absolute novelty claim.
- **Display:** Point forward to Figure 1.
- **Status:** `[CITATION REQUIRED] [DRAFT REQUIRED]`

End with four contributions: statistical decomposition, prospective-information
evaluation, Ontario influenza plus conditional Ontario RSV application, and the
PAGe R package.

## 2. Data structure and forecasting targets

### 2.1 Weekly surveillance contract

- **Purpose:** Define positive count, test denominator, positivity, week,
  season, and permitted metadata.
- **Claim:** The binomial count/denominator representation preserves varying
  weekly information.
- **Evidence:** `prepare_page_data()` contract and source documentation.
- **Display:** Table 1.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 2.2 Ontario influenza application

- **Purpose:** Describe source, extraction, seasons, exclusions, reporting
  revisions, and authorization without exposing private rows.
- **Claim:** The declared data support leakage-safe seasonal replay.
- **Evidence:** Data-custodian record, season declaration, completeness audit.
  Include 2015--16 in the principal analysis when it passes the generic data-
  quality rules; do not exclude it solely as an ignition outlier. The treatment
  of 2011--12 remains `[DECISION REQUIRED]` pending a dated rationale or
  prespecified sensitivity analysis.
- **Display:** Table 1; Figure S1 for season curves if disclosure-safe.
- **Status:** `[DECISION REQUIRED] [ARTIFACT REQUIRED]`

### 2.3 Ontario RSV application

- **Purpose:** Describe the user-supplied Ontario RSV data and its suitability
  for pathogen-specific retraining.
- **Claim:** `[RESULT REQUIRED]` Data satisfy the prespecified denominator,
  season-support, completeness, revision, and publication criteria.
- **Evidence:** `ontario-rsv-data-audit.md`, source/version record, authorization.
- **Display:** Table 1; Figure S2 if authorized.
- **Status:** `[DATA REQUIRED] [NOT APPLICABLE if the RSV gate fails]`

### 2.4 Forecast and landmark targets

- **Purpose:** Define ignition week, phase, peak week, and h1/h2 positivity.
- **Claim:** The targets form one ordered operational pathway while remaining
  separately evaluable.
- **Evidence:** Frozen definitions and ignition-label protocol.
- **Display:** Figure 1.
- **Status:** `[DRAFT REQUIRED] [DECISION REQUIRED for ignition labels]`

### 2.5 Ethics, privacy, and governance

- **Purpose:** State ethics determination, data access, disclosure limits,
  backfill handling, and private/public reproducibility boundary.
- **Claim:** All reported evidence complies with source authorization and uses
  origin-available information where reconstructible.
- **Evidence:** Governance decision records.
- **Display:** None.
- **Status:** `[DECISION REQUIRED]`

## 3. PAGe methodology

Open with notation for season `s`, within-season week `t`, positives `y_st`,
tests `n_st`, positivity `p_st`, forecast horizon `h`, and origin information
set `F_st`. Every model input must be measurable with respect to `F_st`.

### 3.1 M0: prospective ignition detection

- **Purpose:** Define ignition, detector inputs, tuning target, gate state, and
  false/missed ignition behavior.
- **Claim:** M0 provides a reproducible start decision without future-season
  information.
- **Evidence:** Equations, algorithm, tuning lifecycle, label protocol.
- **Display:** Figure 1; full tuning grid in supplement.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 3.2 M1: partial-curve phase and peak alignment

- **Purpose:** Define historical templates, partial-curve matching, slope-
  similarity weighting, aligned coordinate, peak estimate, and `logit_spread`.
- **Claim:** M1 converts partial calendar-time observations into a phase
  representation and exposes alignment uncertainty for M2.
- **Evidence:** Mathematical definition, template eligibility, frozen M0
  dependency, M1 artifact identity, and the principal season-equal within-
  season-normalized weighted peak-week MAE with
  `weight = exp(-(0.1 * weeks_before_peak)^2)`. Define the observed peak as the
  earliest week at the maximum final positivity; also report unweighted MAE,
  peak-interval coverage when available, and the prespecified smoothed-peak
  sensitivity.
- **Display:** Figure 2 representative alignment; Figure S3 diagnostics.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 3.3 M2: one- and two-week probabilistic forecast

- **Purpose:** Define the binomial GAM, link scale, aligned predictors, season
  effects, horizons, predictive output, and adaptive bias state.
- **Claim:** M2 consumes M1 state without violating the origin information set.
- **Evidence:** Formula, frozen feature definitions, fit/freeze lifecycle.
- **Display:** Table 2.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 3.4 End-to-end seasonal training algorithm

- **Purpose:** Make cadence unambiguous.
- **Claim:** For target season `s`, tuning/training uses only declared prior
  seasons, creates one frozen seasonal kit, and does not repeat within `s`.
- **Evidence:** Pseudocode and governed `train_pipeline()` contract.
- **Display:** Figure 1 plus Algorithm 1.
- **Status:** `[DRAFT REQUIRED]`

Algorithm 1 must distinguish:

1. pre-season selection, tuning, validation, fitting, freezing, and kit
   assembly;
2. weekly ingestion and M0/M1/adaptive-state updates;
3. h1/h2 forecast generation; and
4. post-season artifact closure without retroactive modification.

### 3.5 Dependence, identifiability, and uncertainty propagation

- **Purpose:** Explain the exact M0 -> M1 -> M2 identity chain and which
  uncertainty enters downstream prediction.
- **Claim:** Governed assembly prevents mismatched stage artifacts, while
  `logit_spread` represents alignment uncertainty rather than full predictive
  uncertainty.
- **Evidence:** Stage contracts and ablation definitions.
- **Display:** Table 2.
- **Status:** `[DRAFT REQUIRED]`

## 4. Training and validation design

### 4.1 Season selection and information boundaries

- **Purpose:** Declare development, validation replay, and untouched holdout
  seasons for each pathogen.
- **Claim:** No held-out target season informs fold-specific tuning, features,
  labels, or model choice.
- **Evidence:** Season-selection declarations and leakage assertions.
- **Historical separation:** The examined 2025--26 replay is excluded from the
  new fully nested replay aggregate and reported separately as historical
  confirmatory evidence from a different model lineage.
- **Display:** Figure 3 timeline.
- **Status:** `[DECISION REQUIRED] [ARTIFACT REQUIRED]`

### 4.2 Tuning, boundary checks, and model freeze

- **Purpose:** Describe `tune -> validate -> fit -> freeze`, inner leave-one-
  season-out replay on the outer training seasons, dependency-ordered M0 -> M1
  -> M2 tuning, comparator tuning, boundary expansion, hard caps, and identity
  checks.
- **Claim:** All search occurs before holdout access. The inner objective is the
  equal-season h2 NLL; the one-standard-error rule selects the least complex
  eligible candidate, with deterministic ties by complexity then canonical
  configuration ID. The same rule applies to every tunable comparator, and
  every boundary winner is expanded or justified before freeze.
- **Evidence:** Boundary audit and artifact manifest.
- **Display:** Table S1.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 4.3 Retrospective walk-forward seasonal replay

- **Purpose:** Define the origin-by-origin replay using one seasonal kit from
  the prospectively detected ignition through ignition plus 12 weeks,
  inclusive, wherever the target at `w + h` is observed.
- **Claim:** Replay emulates the weekly information flow without claiming that
  it was an actual prospective deployment. The frozen seasonal kit is reused at
  every origin; weekly detector, alignment, forecast, and adaptive-correction
  changes are state updates rather than parameter retraining.
- **Evidence:** Canonical prediction table and replay code.
- **Display:** Figure 3.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 4.4 Comparators, ablations, and label sensitivities

- **Purpose:** Define the seven frozen core models, four structural ablations,
  and three ignition-label sensitivities.
- **Claim:** Comparisons cover persistence, historical analogue, statistical,
  and regularized ML alternatives while isolating PAGe components.
- **Fairness statement:** The calendar-week GAM intentionally excludes M0/M1
  state and PAGe's adaptive online correction and online season effect. Defend
  this as a comparison of complete deployable workflows and acknowledge that it
  does not isolate phase alignment; use the no-M1 ablation for descriptive
  attribution.
- **Evidence:** [`ANALYSIS_PROTOCOL.md`](ANALYSIS_PROTOCOL.md), sections 6--7.
- **Display:** Table 2.
- **Status:** `[DRAFT REQUIRED]`

### 4.5 Outcomes and confirmatory estimand

- **Purpose:** Define stage-level and forecast-level scores, the common origin
  window, and the disposition of model or pipeline failures.
- **Claim:** The sole confirmatory comparison is full PAGe minus calendar-week
  GAM on h2 per-trial binomial NLL, trial-weighted within season and equally
  weighted across seasons; negative values favor PAGe. State that this is
  Bernoulli cross-entropy per trial, equivalently the model-dependent portion of
  binomial NLL, with the combinatorial term omitted and predictions clipped to
  `[1e-12, 1 - 1e-12]`.
- **Exact score:** Reproduce the frozen protocol formula
  `L_s,m = sum_w[-y log(p_hat) - (N-y) log(1-p_hat)] / sum_w N` and
  `Delta = mean_s(L_s,PAGe - L_s,calendar-GAM)`, with `w` restricted to the
  common eligible h2 origins defined above.
- **Failure rule:** A season with no PAGe ignition or no valid paired forecast is
  reported as a pipeline failure and cannot be silently removed. If no paired
  season score can be formed, stop the confirmatory analysis for a documented
  protocol disposition.
- **Attribution diagnostic:** Full PAGe versus the no-M1-alignment ablation is
  the pre-identified descriptive diagnostic for alignment. It is secondary and
  does not support a separate confirmatory superiority claim.
- **Evidence:** Frozen formula and aggregation rules.
- **Display:** Table 3 and Figure 4.
- **Status:** `[DRAFT REQUIRED]`

Secondary outcomes: h1 NLL, positivity MAE, the frozen RMSE/Brier definition,
calibration summaries where support permits, M0 ignition error/miss rate, M1
weighted and unweighted peak-week MAE, early (`t_since = 0:3`) versus established
(`4:12`) performance, pre- versus post-peak performance, horizon degradation,
runtime, and failure rate. Final-data peak strata are used only for evaluation,
never as forecast inputs.

### 4.6 Uncertainty and multiplicity

- **Purpose:** Define 10,000 paired season bootstraps, sign-flip analysis,
  interval interpretation, and exploratory status of secondary contrasts.
- **Claim:** Inference respects season as the effective independent unit.
- **Precision statement:** Before result tables are opened, instantiate the
  frozen precision warning using the locked number of paired seasons and an
  outcome-blind planning standard deviation. For `S = 10`, record the
  approximate 95% half-width `0.715 * SD(Delta_s)` and 80% power threshold
  `0.996 * SD(Delta_s)`; the paired season bootstrap remains the reported
  uncertainty analysis. `[RESULT REQUIRED]` for the dataset-specific
  instantiation.
- **Evidence:** Frozen resampling code and seed record.
- **Display:** Figure 4; detailed intervals in Table S2.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 4.7 Confirmatory holdout and historical evidence

- **Purpose:** Separate the already-completed 2025--26 decision from any new
  development cycle.
- **Claim:** The evaluated candidate failed the locked NLL gate while passing
  horizon and phase gates; no further tuning against 2025--26 is allowed.
- **Evidence:** Existing acceptance replay and provenance record.
- **Provenance rule:** If prespecification of the historical `0.02` NLL gate
  cannot be documented, present it as a historical acceptance rule rather than
  a scientific minimum-important threshold, and emphasize the observed effect
  estimate and uncertainty.
- **Display:** Table S9 historical acceptance replay, separate from the governed
  primary comparison.
- **Status:** `[ARTIFACT REQUIRED] [DECISION REQUIRED]`

## 5. Simulation design

### 5.1 Data-generating processes

- **Purpose:** Vary onset, duration, amplitude, baseline, asymmetry, multiple
  waves, denominator, observation noise, missingness, reporting disruption,
  ignition error, and template mismatch.
- **Claim:** The simulation set includes both PAGe-compatible and structurally
  unfavorable processes.
- **Evidence:** Frozen simulation protocol, seeds, parameter grid, Monte Carlo
  precision calculation.
- **Display:** Table S3.
- **Status:** `[DECISION REQUIRED] [DRAFT REQUIRED]`

### 5.2 Simulation estimands and methods

- **Purpose:** Compare full PAGe, core baselines, and ablations under identical
  realizations.
- **Claim:** Component benefits can be linked to known timing/shape conditions.
- **Cadence:** Train and freeze one kit for each simulated target season under
  the same seasonal protocol used empirically; reuse it at every origin. Do not
  introduce per-origin parameter refitting unless it is part of a separately
  named comparator.
- **Evidence:** Paired simulation outputs and Monte Carlo uncertainty.
- **Display:** Figure 5.
- **Status:** `[ARTIFACT REQUIRED]`

## 6. Respiratory-virus applications and results

Use the same order as the prespecified claims. Report estimates with uncertainty
and season support before interpretation. Do not draft numerical prose from
console logs or isolated artifacts.

### 6.1 Data and frozen-kit audit

- **Purpose:** In no more than 200 words, reconcile the eligible-season and data
  support already defined in Section 2, then report package version, stage
  identities, boundary resolutions, and runtime support without repeating the
  data-source description.
- **Claim:** The evaluated kit and canonical result set satisfy protocol.
- **Display:** Table 2; refer back to Table 1 for data support.
- **Status:** `[RESULT REQUIRED] [ARTIFACT REQUIRED]`

### 6.2 M0 ignition performance

- **Purpose:** Report ignition error, miss/false-trigger behavior, and label
  sensitivity by season.
- **Claim:** `[RESULT REQUIRED]`
- **Display:** Table S4 complete stage results.
- **Status:** `[RESULT REQUIRED]`

### 6.3 M1 phase and peak performance

- **Purpose:** Report the frozen weighted peak-week MAE, unweighted MAE, peak-
  interval coverage where available, alignment diagnostics, and smoothed-peak
  sensitivity; resolve or retire conflicting historical peak-MAE values.
- **Claim:** `[RESULT REQUIRED]`
- **Display:** Figure 2, panel (a); Table S5.
- **Status:** `[RESULT REQUIRED]`

### 6.4 Primary h2 forecast comparison

- **Purpose:** Answer the confirmatory assembled-workflow question first in at
  least 300 words, including the effect estimate, uncertainty, season support,
  influence, and favorable/inconclusive/harm interpretation.
- **Claim:** `[RESULT REQUIRED]` State PAGe-minus-calendar-GAM NLL contrast,
  interval, sign-flip result, season count, and direction.
- **Display:** Figure 4 and Table 3; Figure 2, panel (b), provides one
  representative observed-versus-forecast trajectory with predictive intervals
  but does not substitute for the aggregate comparison.
- **Status:** `[RESULT REQUIRED]`

### 6.5 Historical 2025--26 holdout evidence

- **Purpose:** Report the already-examined acceptance replay unchanged and
  explicitly identify its candidate/incumbent lineage as different from the
  newly re-derived governed kit.
- **Claim:** The historical candidate failed its locked NLL gate while passing
  horizon and phase gates; this result is contextual evidence and is excluded
  from the new fully nested replay aggregate. `[RESULT REQUIRED]`
- **Display:** Table S9.
- **Status:** `[RESULT REQUIRED] [ARTIFACT REQUIRED]`

### 6.6 Secondary forecast, comparator, and ablation results

- **Purpose:** Report h1, all seven models, four ablations, calibration, and the
  named secondary strata without turning them into new primary tests. Treat
  full PAGe versus no-M1 alignment as the pre-identified descriptive
  attribution diagnostic.
- **Claim:** `[RESULT REQUIRED]`
- **Display:** Figure 4; Tables S2 and S6.
- **Status:** `[RESULT REQUIRED]`

### 6.7 Season heterogeneity and failure cases

- **Purpose:** Identify the prespecified worst season, horizon, and phase;
  early/established and pre/post-peak strata; failed origins; and conditions
  where alignment degrades performance. Label any additional regime narrative
  explicitly as exploratory and post hoc.
- **Claim:** `[RESULT REQUIRED]`
- **Display:** Figure S4 and complete canonical replay table.
- **Status:** `[RESULT REQUIRED]`

### 6.8 Simulation results

- **Purpose:** Report where alignment helps, is neutral, or harms prediction
  under the prespecified compatible and unfavorable data-generating processes.
- **Claim:** `[RESULT REQUIRED]`
- **Evidence:** Immutable simulation summaries reproduced by the public
  replication entry point.
- **Display:** Figure 5 and Table S3.
- **Status:** `[RESULT REQUIRED] [ARTIFACT REQUIRED]`

### 6.9 Ontario RSV application

- **Purpose:** Repeat the governed workflow after pathogen-specific retraining
  and one untouched RSV holdout. Training occurs once per RSV target season;
  weekly execution reuses the frozen RSV seasonal kit without retraining.
- **Claim:** `[RESULT REQUIRED]` Limit to workflow portability within Ontario.
- **Display:** Table 4 or Table S7; Figure S5.
- **Status:** `[DATA REQUIRED] [NOT APPLICABLE if the RSV gate fails]`

### 6.10 Cross-application synthesis and runtime

- **Purpose:** In no more than 250 words, compare component gains, calibration,
  failure modes, seasonal training time, and weekly update/forecast latency
  without pooling unlike NLLs.
- **Claim:** `[RESULT REQUIRED]`
- **Display:** Table 4 and Figure S6.
- **Status:** `[RESULT REQUIRED]`

## 7. PAGe R package and software verification

### 7.1 User-facing workflow and generic data adapter

- **Purpose:** Explain the package API from one user-supplied data frame through
  training, kit assembly, replay, and forecast.
- **Claim:** The interface is disease-agnostic at the data-contract level.
- **Evidence:** Exported functions, synthetic fixture, documentation.
- **Display:** Box 1, a compact package workflow and code path; do not reuse
  Figure 1 for software instructions.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 7.2 Guarded lifecycle and provenance

- **Purpose:** Describe stage identities, matching-chain validation, manifests,
  holdout declarations, and promotion evidence.
- **Claim:** The software prevents important classes of stage mismatch and
  undeclared season reuse.
- **Evidence:** Tests and package contracts.
- **Display:** Table 2; Table S8 test matrix.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 7.3 Reproducibility and release

- **Purpose:** Separate public synthetic replication from authorized private-
  data reproduction.
- **Claim:** Readers can execute the complete public workflow and reproduce all
  published simulation summaries from recorded seeds within manifest-defined
  numerical tolerances. Private Ontario numerical results require authorized
  inputs.
- **Evidence:** Versioned release, lockfile/session information, package check,
  public replication entry point, and a Table S8 acceptance check that compares
  regenerated simulation summaries with the manifest-bound published values.
- **Display:** Table S8.
- **Status:** `[ARTIFACT REQUIRED]`

## 8. Discussion

### 8.1 Principal findings

Lead with the primary h2 estimate, then M0/M1 findings, h1/phase context,
failure cases, simulations, and RSV only if completed. `[RESULT REQUIRED]`

- If the upper interval is below zero, describe evidence favoring the assembled
  PAGe workflow.
- If the interval contains zero, describe the comparison as inconclusive and
  follow the Phase-4 decision memo rather than promoting a secondary result.
- If the interval is wholly positive, report harm and narrow, redesign, or
  retarget as directed by the memo.

### 8.2 Why phase alignment helped or did not help

Interpret the mechanism through onset variability, template match, alignment
uncertainty, adaptive correction, and ablations. Attribute a phase-alignment
effect only through the pre-identified full-PAGe versus no-M1 diagnostic and
the broader ablation pattern. Do not infer mechanism from the confirmatory
assembled-workflow contrast alone. `[RESULT REQUIRED] [CITATION REQUIRED]`

### 8.3 Relation to mathematical, statistical, and ML forecasting

Position PAGe as a staged statistical workflow that borrows historical epidemic
shape without claiming to replace mechanistic transmission models or establish
deep-learning superiority. `[DRAFT REQUIRED] [CITATION REQUIRED]`

### 8.4 Operational implications

Discuss the linked ignition/peak/forecast outputs, once-per-season training,
weekly latency, calibration, and what a surveillance team can act on. Keep
retrospective replay distinct from real-time deployment. `[RESULT REQUIRED]`

### 8.5 Limitations

Cover at least: effective season count; manual ignition labels; historical M1
conflict; conditional rather than fully nested historical M2 LOSO; reporting
backfill; private-data reproducibility; atypical pandemic seasons; template
misspecification; the calendar comparator's lack of M0/M1 state, adaptive online
correction, and online season effect; Ontario-only jurisdiction; one or two
pathogens; and no direct proof of prospective impact. `[DRAFT REQUIRED]
[RESULT REQUIRED]`

### 8.6 Generalizability and next validation

Distinguish API generality, retraining portability, model transportability, and
actual external validity. Propose prospective multi-season and multi-
jurisdiction evaluation. `[DRAFT REQUIRED]`

## 9. Conclusion

Use three sentences:

1. What PAGe decomposes and why.
2. The narrow empirical result with its uncertainty. `[RESULT REQUIRED]`
3. The bounded operational/reproducibility implication, without claiming
   prospective effectiveness.

The second sentence must follow the same favorable, inconclusive, or harmful
branch used in Section 8.1. A null or harmful primary result cannot be replaced
by a favorable secondary result.

## Declarations

- Ethics approval or determination: `[DECISION REQUIRED]`
- Consent to participate/publication: `[DECISION REQUIRED or not applicable]`
- Data availability: describe Ontario restrictions and any RSV terms.
- Code and package availability: `[ARTIFACT REQUIRED]`
- Funding: `[REQUIRED]`
- Competing interests: `[REQUIRED]`
- CRediT authorship statement: `[REQUIRED]`
- Acknowledgements: `[REQUIRED]`
- AI-assisted work disclosure: summarize planning, review, coding, and writing
  assistance under the policy in force at submission.
- Epidemic-forecast reporting checklist: `[DECISION REQUIRED]` select and
  complete an applicable checklist, or document why none is suitable.

## Main-text display map

| Display | Scientific job | Source status |
|---|---|---|
| Figure 1 | Statistical M0 -> M1 -> M2 dependency chain | Design-ready |
| Figure 2 | One representative season: (a) partial-curve alignment and peak estimate; (b) observed and h1/h2 forecast trajectories with predictive intervals | `[ARTIFACT REQUIRED]` |
| Figure 3 | Once-per-season training, weekly frozen-kit updates, replay, and holdout information boundary | Design-ready |
| Figure 4 | Governed primary h2 contrast with season-level uncertainty | `[RESULT REQUIRED]` |
| Figure 5 | Simulation operating conditions and failure modes | `[RESULT REQUIRED]`; supplement by default |
| Table 1 | Data sources, seasons, exclusions, denominators, observations | `[ARTIFACT REQUIRED]` |
| Table 2 | Stage specifications, seven models, four ablations, identities | `[ARTIFACT REQUIRED]` |
| Table 3 | Governed Ontario primary h2 comparison and uncertainty | `[RESULT REQUIRED]` |
| Table 4 | RSV/cross-application synthesis | Conditional; supplement by default |
| Box 1 | User-facing package workflow from data frame to frozen kit, replay, and forecast | `[ARTIFACT REQUIRED]` |

The main-text planning target is four figures and three tables, following the
independent display-economy review recorded in [`REVIEW_LOG.md`](REVIEW_LOG.md),
not a measured journal rule. Figure 5 and Table 4 enter the main text only if
they are necessary to the final claim and the current journal guide permits;
otherwise place them in the supplement.

## Supplement skeleton

- Appendix A: Notation and complete M0/M1/M2 equations.
- Appendix B: Season declarations, information-boundary audit, and ignition-
  label protocol.
- Appendix C: Complete tuning grids, boundary actions, and frozen identities.
- Appendix D: Full M0 and M1 stage-level results.
- Appendix E: Canonical season-by-origin-by-horizon replay table and all model
  comparisons.
- Appendix F: Phase, worst-season, calibration, ablation, and label-sensitivity
  analyses.
- Appendix G: Simulation protocol, parameters, seeds, Monte Carlo uncertainty,
  public-replication acceptance check, and extended results.
- Appendix H: Ontario RSV audit and results, if completed.
- Appendix I: Package API, tests, runtime logs, computational environment, and
  reproducibility manifest.

Supplementary table assignments:

- Table S1: complete tuning grids and boundary actions (Appendix C).
- Table S2: full secondary forecast metrics and intervals (Appendix E).
- Table S3: simulation summaries and Monte Carlo uncertainty (Appendix G).
- Tables S4--S5: M0 and M1 stage-level results (Appendix D).
- Table S6: ablations and attribution diagnostics (Appendix F).
- Table S7: Ontario RSV validation, if completed (Appendix H).
- Table S8: package validation and public-replication acceptance (Appendix I).
- Table S9: historical 2025--26 acceptance replay and lineage (Appendix E),
  excluded from the governed replay aggregate.

## Recommended drafting order

1. Section 2.1 and 2.4, then Sections 3 and 4 from the frozen protocol and
   verified package contracts.
2. Section 7 from the package API, tests, and release evidence.
3. Section 5.1--5.2 after the simulation protocol is frozen.
4. Sections 6.1--6.8 only from the immutable Ontario and simulation result
   directories.
5. Complete the dated `PLAN.md` Phase-4 go/no-go memo before drafting the
   Introduction, Discussion, Conclusion, or any Ontario RSV Results.
6. Sections 6.9--6.10 only after the Phase-4 proceed decision, the user-supplied
   RSV data gate, and the full RSV evidence freeze.
7. Section 1 after the empirical contribution, go/no-go decision, and citation
   set are stable.
8. Section 8 after every included result and sensitivity analysis is frozen.
9. Conclusion, title, highlights, and abstract last, following the prespecified
   favorable/inconclusive/harm branch.
10. Declarations, references, supplement, journal-format audit, and numerical-
   claim traceability audit before independent review.

### Sections safe to draft after this architecture revision

- Sections 2.1 and 2.4, while retaining their open data/label markers.
- Sections 3.1--3.5, excluding numerical tuning or historical peak-MAE claims.
- Sections 4.2--4.6, with the dataset-specific precision value left as
  `[RESULT REQUIRED]`.
- Sections 7.1--7.2 from verified package contracts, without claiming package-
  check or runtime results that do not yet exist.
- Sections 1.3, 8.3, and 8.6 as standalone blocks, to be reintegrated only after
  the Phase-4 go/no-go decision.

## Section completion rule

A section is complete only when every claim has a verified citation or immutable
artifact, every number maps to a canonical table, every conditional paragraph
has passed its gate, and no placeholder remains silently unresolved.
