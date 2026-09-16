# PAGe manuscript skeleton for *Epidemics*

> **Status (2026-09-15): restructured for Epidemics (protocol v2.0 draft)**

Last updated: 2026-09-15

Status: **authoring guide; the standalone Methods draft and reporting schemas
are finalized, while numerical Results remain blocked by the evidence gates in
[`PLAN.md`](PLAN.md).**

Target journal: *Epidemics*, article type **Methodological Manuscript** (the
journal requires a clear biological/public-health application with novel
insight). Fallback: *Infectious Disease Modelling*. The `PAGe` R package is
reserved for a later, separate *R Journal* paper and is not a contribution of
this manuscript.

Source of truth for the evidence design:
[`drafts/ANALYSIS_PROTOCOL_v2.0-draft.md`](drafts/ANALYSIS_PROTOCOL_v2.0-draft.md)
and
[`drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md`](drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md).
Where older plan text conflicts with those drafts, the drafts control.

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

Scope rule: **Ontario influenza only.** RSV and every other pathogen are out of
scope for this manuscript (deviations register D-16). RSV may appear only in the
Future work subsection of the Discussion.

The manuscript must consistently say that PAGe is **designed for prospective
deployment and evaluated by retrospective walk-forward replay**. Training,
tuning, fitting, and freezing occur once for each target season; the same frozen
seasonal kit is reused at every weekly origin. Weekly M0 decisions, M1 alignment,
M2 forecasting, and permitted adaptive correction are state updates, not model
retraining. Report retrospective versus prospective status explicitly and label
the exposed `2025-26` season in every table (protocol v2.0 sections 0, 3, 6).

The canonical prose draft is [`METHODS.md`](METHODS.md). The canonical result,
table, figure, manifest, and quality-control schemas are in
[`REPORTING_TEMPLATES.md`](REPORTING_TEMPLATES.md).

## Paper-level argument

### Problem

Operational Ontario influenza surveillance must answer three linked questions
during a season: when has epidemic activity ignited, where are we relative to
the peak, and what positivity should be expected one and two weeks ahead.
Calendar week is an unstable coordinate for these decisions because ignition,
growth rate, and peak timing vary among seasons, so a phase-blind model mixes
epidemic states.

### Proposed solution

PAGe (Phase-Aligned Gated Epidemiology) decomposes the operational task into a
gated, application-first sequence evaluated for Ontario influenza:

1. M0 detects epidemic ignition from information available at the forecast
   origin.
2. M1 estimates current phase and peak timing by aligning the partial curve to
   historical templates.
3. M2 predicts positivity one and two weeks ahead using the aligned state and a
   frozen binomial GAM, with a governed adoption gate that falls back to M1 when
   the M2 gain is small or inconsistent.

### Claim to earn

The manuscript is an **application-first operational evaluation**, not a generic
framework or software paper. Its claims are limited to Ontario influenza
surveillance and are descriptive.

- **Co-primary claim 1 (operational baseline).** For the chronological seasons
  `2022-23` to `2025-26`, report how season-level PAGe phase-weighted
  Bernoulli cross-entropy compares with the deployed IRVRI legacy daily GAM,
  with every season's value shown. Negative contrasts favour PAGe.
  `[RESULT REQUIRED]`
- **Co-primary claim 2 (recipe performance).** Across the 11-fold exchangeable
  evaluation, report PAGe's season-equal score and its paired contrasts against
  the calendar-week GAM, mvgam `mod2AR`, persistence, and seasonal naive.
  `[RESULT REQUIRED]`
- **Secondary probabilistic claim.** Report WIS and central 50%/95% empirical
  coverage by phase and horizon, labelled as secondary and limited by the
  binomial predictive that ignores parameter uncertainty (protocol v2.0
  section 5.1). `[RESULT REQUIRED]`

All summaries are descriptive: season values, mean, median, SD, IQR, range, and
leave-one-season-out means. No p-values, confidence intervals, power, or
superiority decisions (protocol v2.0 sections 5.3, 6.4). The no-M1 alignment
ablation is a pre-identified descriptive attribution diagnostic and cannot
replace either co-primary comparison. Mixed or harmful seasons must be reported
directly and may not be replaced by a favourable secondary finding.
`[RESULT REQUIRED]`

## Section and word-budget map

| Section | Draft target | Main job | Current status |
|---|---:|---|---|
| Abstract | <=250 words, unstructured | Compress problem, method, validation, findings, and implication | Blocked by Results |
| 1. Introduction | 750 | Establish the operational Ontario problem and contributions | Ready after citation selection |
| 2. Data and forecasting targets | 500 | Define observations, seasons, targets, and governance | Partly ready; data decisions open |
| 3. PAGe methods (M0, M1, M2, adoption gate) | 1,700 | Define the stage chain and the adoption gate | Rewrite from protocol v2.0 draft (METHODS.md is prior cycle) |
| 4. Validation and evaluation design | 800 | Seasons and information boundary; chronological and exchangeable designs; comparators; scores incl. WIS/coverage; reproducibility | Rewrite from protocol v2.0 draft (METHODS.md is prior cycle) |
| 5. Results (retrospective) | 1,300 | Report co-primary blocks, probabilistic scores, stage results | Blocked by canonical results |
| 6. Real-time application, 2026-27 | 500 | Final kit on all 11 seasons, no outer holdout; logged weekly forecasts and scores to the submission date | Blocked by 2026-27 data |
| 7. Discussion | 700 | Findings, public-health implications, literature, limitations, future work | Blocked by Results |
| 8. Conclusion | 100 | State only the supported contribution | Blocked by Results |

Main-text target: approximately 6,500 words, inside the *Epidemics* planning
envelope. Do not exceed any section budget by borrowing untracked words from
another section.

## Front matter

### Title page

- Title: `[DECISION REQUIRED]` must flag forecasting/prediction research
  (EPIFORGE item 1) and foreground the Ontario influenza surveillance
  application; do not retain the staged-framework working title unchanged.
  Working candidate: *Phase-aligned forecasting of Ontario influenza
  positivity: an operational evaluation of the PAGe pipeline against the legacy
  surveillance model*.
- Authors, affiliations, corresponding author: `[DRAFT REQUIRED]`
- Short title: `[DRAFT REQUIRED]`

### Highlights

Three to five short, result-bearing bullets, each **<=85 characters**, drafted
after Results are frozen. Placeholders below are length-checked at drafting
time; final requirements must be rechecked against the live journal guide.

- PAGe forecasts Ontario influenza positivity by aligning epidemic phase.
- `[RESULT REQUIRED]` Co-primary contrast against the operational legacy GAM.
- `[RESULT REQUIRED]` Score and coverage finding, labelled secondary.
- `[RESULT REQUIRED]` One practical public-health implication for surveillance.

The headline must reflect the complete observed season-level pattern, including
mixed or harmful seasons, without substituting a favourable secondary finding.

### Abstract

Unstructured, **<=250 words**, problem-method-results-conclusion flow.

- **Problem (35--40 words):** Why calendar-time models mix epidemic phases and
  why Ontario surveillance needs ignition, peak, and short-horizon outputs.
- **Methods (75--85 words):** M0 -> M1 -> M2 with the adoption gate;
  once-per-season training; retrospective walk-forward replay; co-primary
  descriptive blocks; WIS and 50%/95% coverage as secondary.
- **Results (75--85 words):** `[RESULT REQUIRED]` Co-primary contrasts,
  season-level variation, horizon/phase context, and coverage.
- **Conclusion (30--40 words):** `[DECISION REQUIRED]` State the narrowest
  conclusion supported by the evidence, limited to Ontario influenza.

The maxima of these drafting ranges total 250 words; do not exceed any range by
borrowing untracked words from another abstract component.

### Graphical abstract

Required as a separate file per the journal guide. Depict one seasonal kit
trained once, then weekly `M0 -> M1 -> M2` state updates and 1--2-week
positivity forecasts under a visible prospective-information boundary, with the
legacy GAM shown as the operational comparator. `[ARTIFACT REQUIRED]`

### Keywords

Up to seven: influenza; forecasting; epidemic phase; surveillance; probabilistic
forecasting; Ontario; public health. `[DECISION REQUIRED]` final selection.

## 1. Introduction

### 1.1 Operational forecasting problem

- **Purpose:** Establish why ignition, peak timing, and one-/two-week positivity
  forecasts matter to Ontario public-health surveillance decisions, and justify
  the 1--2-week horizon against decision needs (EPIFORGE item 13).
- **Claim:** Decision support needs both epidemic landmarks and calibrated
  short-horizon predictions.
- **Evidence:** Public-health forecasting and respiratory-virus literature;
  protocol v2.0 sections 5.2 and 6.
- **Display:** None.
- **Status:** `[CITATION REQUIRED] [DRAFT REQUIRED]`

### 1.2 Why calendar time is an unstable epidemic coordinate

- **Purpose:** Explain onset, growth-rate, duration, amplitude, and peak-timing
  variation among Ontario seasons.
- **Claim:** Equal calendar weeks need not represent equal epidemic states.
- **Evidence:** Ontario descriptive evidence plus curve-registration and
  seasonal-epidemic literature; protocol v2.0 sections 1.2 and 2.
- **Display:** Table 1 supplies season support; no result should be previewed
  before its audit.
- **Status:** `[CITATION REQUIRED] [RESULT REQUIRED]`

### 1.3 Existing mathematical, statistical, and machine-learning approaches

- **Purpose:** Situate PAGe among operational and statistical forecasting
  approaches, including the IRVRI legacy daily GAM in use at the agency.
- **Claim:** Mechanistic models encode transmission structure; statistical
  models offer parsimonious and calibrated baselines; phase-aware pipelines
  target the alignment problem directly.
- **Evidence:** [`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md) and
  [`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md); protocol v2.0 section 4.
- **Display:** None; keep this synthesis selective.
- **Status:** `[DRAFT REQUIRED]`

### 1.4 Gap and contributions

- **Purpose:** State what forecasting alone leaves unaddressed for operational
  Ontario surveillance.
- **Claim:** Few operational workflows jointly govern prospective ignition
  detection, partial-curve phase/peak alignment, probabilistic forecasting, a
  governed adoption gate, and artifact-level reproducibility.
- **Evidence:** Verified literature; avoid an absolute novelty claim.
- **Display:** Point forward to Figure 1.
- **Status:** `[CITATION REQUIRED] [DRAFT REQUIRED]`

End with the contributions: a staged phase-aware workflow, prospective-
information evaluation against the operational legacy model, an Ontario
influenza application with calibrated probabilistic scores, and a reproducible
implementation package distributed separately.

## 2. Data and forecasting targets

### 2.1 Weekly surveillance contract

- **Purpose:** Define positive count, test denominator, positivity, MMWR-based
  season and week, and permitted metadata.
- **Claim:** The binomial count/denominator representation preserves varying
  weekly information, and date-derived seasons with `start_week = 27L` fix the
  within-season coordinate.
- **Evidence:** `prepare_page_data()` and `PAGe::page_season_calendar()`
  contracts; protocol v2.0 section 1.2.
- **Display:** Table 1.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 2.2 Ontario influenza application

- **Purpose:** Describe source, extraction, the 11 principal seasons, the 4
  exclusions, reporting revisions, and authorization without exposing private
  rows.
- **Claim:** The declared data support leakage-safe seasonal replay; all
  analyses are final-data retrospective replays and revision effects are a
  stated limitation.
- **Evidence:** Data-custodian record, completeness audit,
  [`GOVERNANCE_DECISIONS.md`](GOVERNANCE_DECISIONS.md),
  [`ONTARIO_FLU_SEASON_DECLARATION.md`](ONTARIO_FLU_SEASON_DECLARATION.md);
  protocol v2.0 sections 1.1 and 1.3. Use exactly the 11 current-workflow
  principal seasons; do not add influenza seasons. Keep `2011-12`, `2015-16`,
  `2020-21`, and `2021-22` outside the principal aggregate.
- **Display:** Table 1.
- **Status:** `[ARTIFACT REQUIRED] [DECISION REQUIRED for authorization]`

### 2.3 Forecast and landmark targets

- **Purpose:** Define ignition week, phase, peak week, and h1/h2 positivity,
  including the timing-v2 one-week interval labels.
- **Claim:** The targets form one ordered operational pathway while remaining
  separately evaluable.
- **Evidence:** `prepare_page_data()` / timing-v2 labels and
  [`IGNITION_LABEL_PROTOCOL.md`](IGNITION_LABEL_PROTOCOL.md); protocol v2.0
  sections 1.2 and 1.4.
- **Display:** Figure 1.
- **Status:** `[DRAFT REQUIRED]`

### 2.4 Ethics, privacy, and governance

- **Purpose:** State ethics determination, data access, disclosure limits,
  backfill handling, and the private/public reproducibility boundary.
- **Claim:** All reported evidence complies with source authorization and uses
  origin-available information where reconstructible.
- **Evidence:** Governance decision records; protocol v2.0 section 7.
- **Display:** None.
- **Status:** `[DECISION REQUIRED]`

## 3. PAGe methods

Open with notation for season `s`, within-season week `t`, positives `y_st`,
tests `n_st`, positivity `p_st`, forecast horizon `h`, and origin information
set `F_st`. Every model input must be measurable with respect to `F_st`, and all
tuning and fitting inputs must precede the origin (protocol v2.0 section 1.2).

### 3.1 M0: prospective ignition detection

- **Purpose:** Define ignition, detector inputs, the fractional timing target
  (`timing_mode = "fractional"`), the symmetric-absolute-error loss with late
  penalty, gate state, and false/missed ignition behavior.
- **Claim:** M0 provides a reproducible start decision without future-season
  information; misses are retained as missing with `detection_failed`
  accounting.
- **Evidence:** Equations, algorithm, tuning lifecycle, label protocol; protocol
  v2.0 sections 1.4 and 2 (M0 row).
- **Display:** Figure 1; full tuning grid in supplement.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 3.2 M1: partial-curve phase and peak alignment

- **Purpose:** Define historical templates, partial-curve matching,
  slope-similarity weighting, the plain-shift aligned coordinate
  `newWeek = weekF - iWeek + anchor`, peak estimate, and `logit_spread`.
- **Claim:** M1 converts partial calendar-time observations into a phase
  representation and exposes alignment uncertainty for M2; out-of-domain rows
  are excluded rather than clamped.
- **Evidence:** Mathematical definition, template eligibility, frozen M0
  dependency, M1 artifact identity; protocol v2.0 section 2 (M1 row) and
  section 5.5. Report the season-equal within-season-normalized weighted
  peak-week MAE with `weight = exp(-(0.1 * weeks_before_peak)^2)`; also report
  unweighted MAE and the prespecified smoothed-peak sensitivity.
- **Display:** Figure 2 representative alignment; Figure S3 diagnostics.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 3.3 M2: one- and two-week probabilistic forecast

- **Purpose:** Define the governed `offset_subset_v1` binomial GAM on the M1
  logit offset, link scale, horizon-indexed terms, predictive output, and the
  optional online bias corrector as a grid value.
- **Claim:** M2 consumes M1 state without violating the origin information set;
  the legacy correction family is available only under an explicit research
  flag and is rejected by governed kits.
- **Evidence:** Formula, frozen feature definitions, fit/freeze lifecycle;
  protocol v2.0 section 2 (M2 row).
- **Display:** Table 2.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 3.4 Adoption gate and end-to-end seasonal algorithm

- **Purpose:** Define the M2-versus-M1 adoption gate, the per-season phase
  weighting, and the once-per-season cadence that makes it unambiguous.
- **Claim:** For target season `s`, tuning/training uses only declared prior
  seasons and creates one frozen seasonal kit that is reused at every weekly
  origin; M2 is adopted only if the mean phase-weighted gain clears
  `max(floor, qt(0.95, n - 1) * SD / sqrt(n))` overall and per horizon with no
  season degrading, and otherwise forecasts equal M1.
- **Evidence:** Pseudocode and governed `train_pipeline()` contract; protocol
  v2.0 section 2 (gate and cadence rows) and section 5.5.
- **Display:** Figure 1 plus Algorithm 1.
- **Status:** `[DRAFT REQUIRED]`

Algorithm 1 must distinguish:

1. pre-season selection, tuning, validation, fitting, freezing, and kit
   assembly;
2. weekly ingestion and M0/M1/adaptive-state updates;
3. h1/h2 forecast generation and gate application; and
4. post-season artifact closure without retroactive modification.

### 3.5 Dependence, identifiability, and uncertainty propagation

- **Purpose:** Explain the exact M0 -> M1 -> M2 identity chain and which
  uncertainty enters downstream prediction.
- **Claim:** Governed assembly prevents mismatched stage artifacts, while
  `logit_spread` represents alignment uncertainty rather than full predictive
  uncertainty; the binomial predictive ignores parameter uncertainty and is
  labelled as such.
- **Evidence:** Stage contracts, ablation definitions, and protocol v2.0
  section 5.1.
- **Display:** Table 2.
- **Status:** `[DRAFT REQUIRED]`

## 4. Validation and evaluation design

### 4.1 Seasons and information boundary

- **Purpose:** Declare the exchangeable folds, the chronological tiers, and the
  untouched evidence, with the retrospective/prospective boundary explicit.
- **Claim:** No held-out target season informs fold-specific tuning, features,
  labels, or model choice; `2025-26` is labelled **exposed** in every table and
  the only untouched evidence is the prospective `2026-27` season.
- **Evidence:** Protocol v2.0 sections 0, 1.1, 3.1, and 3.2; deviations D-9.
- **Display:** Figure 1 shows the information boundary; no separate timeline
  figure in the main text (max four figures).
- **Status:** `[DECISION REQUIRED] [ARTIFACT REQUIRED]`

### 4.2 Tuning, boundary checks, and model freeze

- **Purpose:** Describe `tune -> validate -> fit -> freeze`, inner
  leave-one-season-out replay on the outer training seasons, dependency-ordered
  M0 -> M1 -> M2 tuning, fully nested inner-gate isolation, boundary expansion,
  hard caps, and identity checks.
- **Claim:** All search occurs before holdout access, and every boundary winner
  is expanded or justified before freeze.
- **Evidence:** Boundary audit and artifact manifest; protocol v2.0 section 2
  and section 5.5.
- **Display:** Table S1.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`
- **User guidance (methods framing):** recommend that users start from a modest grid and expand only where the winner lies on a boundary; state that the reported grids were narrowed using prior-cycle tuning results and that boundary expansion stayed active (protocol v2.0 s.2, D-29). Explain that no hyperparameter is removed from the package: this Ontario influenza recipe fixes M1 (`k_ref = 30`, `slope_weight = 16`) with single-value grids because its tuning surface was flat, while other applications can tune it (D-32).

### 4.3 Chronological and exchangeable designs

- **Purpose:** Define the two co-primary designs: (a) the exchangeable 11-fold
  leave-one-season-out replay (`Workflow A`), and (b) the chronological design
  used for the legacy GAM, with Tier 1 `2025-26` and Tier 2 `2022-23`,
  `2023-24`, `2024-25` expanding-window kits.
- **Claim:** Replay emulates the weekly information flow without claiming an
  actual prospective deployment; the chronological comparison trains PAGe on
  earlier seasons only, matching the legacy GAM's constraint.
- **Evidence:** Protocol v2.0 sections 3.1--3.3 and 5.2; canonical prediction
  table and replay code.
- **Display:** Figure 1; design detail in the supplement.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 4.4 Comparators and information sets

- **Purpose:** Define the comparator set and the disclosed information-set and
  cadence asymmetries (training span, pooled seasons, resolution, refit
  cadence, row anchor).
- **Claim:** Comparisons cover the operational baseline (IRVRI legacy GAM),
  the calendar-week GAM, mvgam `mod2AR`, persistence, seasonal naive, and M1
  only, while acknowledging that scorable rows are anchored at PAGe's detected
  ignition and that the legacy GAM has a shorter span but finer resolution and
  per-origin refitting.
- **Evidence:** Protocol v2.0 section 4, including the `mod2AR` specification
  fixed by the project lead on 2026-09-15 before any evaluation run; deviations
  D-14, D-15, D-26.
- **Display:** Table 2.
- **Status:** `[DRAFT REQUIRED]`

### 4.5 Outcomes and co-primary comparisons

- **Purpose:** Define the phase-weighted Bernoulli cross-entropy score, the
  common-row contract, the two co-primary descriptive blocks, and the
  disposition of model or pipeline failures.
- **Claim:** The primary score is the phase-weighted mean over each season's
  scorable rows, then equally averaged across seasons; negative PAGe-minus-
  comparator contrasts favour PAGe.
- **Exact score:** Reproduce the frozen formula
  `CE = -q log(p_hat) - (1 - q) log(1 - p_hat)`, `q = y/N`, clipped to
  `[1e-12, 1 - 1e-12]`, with weights pre-ignition 0, rise 2, turning window 3,
  decline 1 (protocol v2.0 sections 2 and 5.1).
- **Common rows:** All contrasted models are scored on identical rows keyed by
  season, origin, horizon, and target week; unavailable rows stay in the
  canonical table with reason codes and are never imputed.
- **Failure rule:** A season whose paired score cannot be formed is reported as
  a pipeline failure, shown in every season-level table, and excluded from that
  contrast's mean with the count stated; the contrast does not stop (deviation
  D-21).
- **Evidence:** Protocol v2.0 sections 5.1--5.3 and 6.
- **Display:** Figure 3 and Table 3.
- **Status:** `[DRAFT REQUIRED]`

### 4.6 Probabilistic scores: WIS and coverage

- **Purpose:** Define the predictive quantiles and the secondary probabilistic
  scores.
- **Claim:** WIS and empirical coverage of the central 50% and 95% intervals
  are reported on the positivity scale with the same phase weights and
  aggregation as the primary score; for PAGe, M1, the calendar GAM, and
  seasonal naive the predictive distribution is `Binomial(N_target, p_hat) /
  N_target`, which ignores parameter uncertainty.
- **Evidence:** Protocol v2.0 section 5.1; deviations D-25; EPIFORGE item 14.
- **Display:** Figure 4; Table S2.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 4.7 Descriptive aggregation and sensitivities

- **Purpose:** Define complete season-level reporting, descriptive summaries,
  and the prespecified sensitivity set.
- **Claim:** Every valid season is weighted equally; report each difference,
  the mean, median, SD, IQR, range, and leave-one-season-out mean, and do not
  report hypothesis tests, p-values, confidence intervals, power, or
  significance decisions.
- **Sensitivities:** Legacy weights, the registered v1.4 primary line,
  test-count weighting, daily-aggregated legacy targets, dropping exposed
  `2025-26`, fold-specific M0-generated training labels, the no-M1 ablation,
  and the simulation-only ablations (protocol v2.0 section 5.4).
- **Evidence:** Protocol v2.0 sections 5.3, 5.4, and 6.1.
- **Display:** Figure 4; detailed season values in Table S2.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

### 4.8 Reproducibility and package

- **Purpose:** In <=200 words, state the reproducibility boundary: one
  immutable results directory per analysis with one canonical prediction table
  and a manifest recording protocol checksum, code commit, package and
  dependency versions, platform, seeds, and data checksums.
- **Claim:** Readers can execute the complete public workflow and reproduce
  published simulation summaries from recorded seeds using the `PAGe` R package
  and synthetic examples; private Ontario numerical results require authorized
  inputs and only aggregates are published.
- **Evidence:** Protocol v2.0 section 7; versioned code archive with DOI,
  lockfile/session information, and synthetic-data dictionary. Package API,
  tests, and runtime detail are supplement-only (Appendix I).
- **Display:** Data and code availability statement; Table S8.
- **Status:** `[DRAFT REQUIRED] [ARTIFACT REQUIRED]`

## 5. Results

Use the same order as the prespecified claims. Report estimates with
descriptive summaries and season support before interpretation. Do not draft
numerical prose from console logs or isolated artifacts.

### 5.1 Data and pipeline failures

- **Purpose:** In no more than 200 words, reconcile the eligible-season and
  data support already defined in Section 2, then report package version, stage
  identities, boundary resolutions, and every season treated as a pipeline
  failure with its reason code.
- **Claim:** The evaluated kit and canonical result set satisfy protocol, and
  no failed season is silently removed.
- **Display:** Table 1; refer back to Section 2.
- **Status:** `[RESULT REQUIRED] [ARTIFACT REQUIRED]`

### 5.2 Co-primary block 1: legacy GAM (chronological)

- **Purpose:** Report the season-equal mean of `L(PAGe) - L(legacy GAM)` on the
  four chronological seasons `2022-23` to `2025-26`, with every season's value
  shown and the Tier 1 coverage (rows, phases) stated.
- **Claim:** `[RESULT REQUIRED]` State the PAGe-minus-legacy-GAM contrast,
  season count, mean, median, observed spread, range, and direction.
- **Display:** Figure 3 and Table 3.
- **Status:** `[RESULT REQUIRED]`

### 5.3 Co-primary block 2: 11-fold exchangeable evaluation

- **Purpose:** Report Workflow A season-equal PAGe score across the 11 folds
  and the paired contrasts against the calendar-week GAM, mvgam `mod2AR`,
  persistence, and seasonal naive. The exposed `2025-26` fold is labelled.
- **Claim:** `[RESULT REQUIRED]` State each paired contrast, season count,
  mean, median, observed spread, range, direction, and influence.
- **Display:** Figure 3 and Table 3; Figure 2 panel (b) provides one
  representative observed-versus-forecast trajectory with intervals but does
  not substitute for the aggregate comparison.
- **Status:** `[RESULT REQUIRED]`

### 5.4 Probabilistic scores by phase and horizon

- **Purpose:** Report WIS, central 50%/95% coverage, and interval width by
  phase and horizon, labelled secondary and with the binomial-ignores-
  parameter-uncertainty caveat.
- **Claim:** `[RESULT REQUIRED]`
- **Display:** Figure 4.
- **Status:** `[RESULT REQUIRED]`

### 5.5 Stage results: M0, M1, and the adoption gate

- **Purpose:** Report M0 signed/absolute ignition error and miss rate, M1
  weighted and unweighted peak-week MAE, and gate behavior (inner versus outer
  gain, always-M1 versus always-M2 versus gate policies, harmed-season count,
  selected hyperparameters and boundary expansions across folds).
- **Claim:** `[RESULT REQUIRED]`
- **Display:** Tables S4 and S5; Figure 2 panel (a).
- **Status:** `[RESULT REQUIRED]`

Simulation evidence (reference data-generating process plus four decisive
stressors) is reported in the supplement and is referenced here in one sentence
to bound generalization claims. `[RESULT REQUIRED]`

## 6. Real-time application, 2026-27

Separate from the retrospective evaluation. Training and evaluation are
separated in time, not by an outer holdout: the final kit is trained once on
all 11 eligible seasons and applied to the 2026-27 season as it happens.
Protocol v2.0 draft section 6.1.

### 6.1 Operational setup

- **Purpose:** Describe the frozen final kit (trained on all 11 seasons, no
  held-out season), the weekly run, append-only timestamped forecast logs,
  real-time data vintages with reporting delay, and the models run in parallel
  (M1 only, production IRVRI legacy GAM, persistence, FluSight-style baseline).
- **Claim:** Every reported forecast was logged before its target was observed,
  with a fixed kit identity for the whole season.
- **Evidence:** Kit identity record, weekly log with timestamps and checksums.
- **Status:** `[ARTIFACT REQUIRED]`

### 6.2 Real-time results

- **Purpose:** Report the season up to the latest data available at
  submission (analysis date stated): weekly forecasts against observations
  with intervals, detected ignition and peak timing, phase-weighted log loss,
  WIS and coverage for each model, with provisional phases before the peak is
  confirmed.
- **Claim:** `[RESULT REQUIRED]`
- **Operational outcomes:** missed weeks, pipeline errors, late data, detection
  failures.
- **Display:** Figure 4.
- **Status:** `[RESULT REQUIRED] [DATA REQUIRED]`

## 7. Discussion

### 7.1 Principal findings

Lead with the complete co-primary season-level patterns and descriptive
summaries, then M0/M1 stage findings, probabilistic-score context, and failure
cases. State mixed or harmful results directly rather than promoting a
favourable secondary result. `[RESULT REQUIRED]`

### 7.2 Operational implications for public health

Discuss the linked ignition/peak/forecast outputs, once-per-season training,
weekly update latency, calibration, and what an Ontario surveillance team can
act on, while keeping retrospective replay distinct from real-time deployment
(EPIFORGE items 15 and 18). `[RESULT REQUIRED] [DRAFT REQUIRED]`

### 7.3 Comparison with literature

Position PAGe as a staged, phase-aware statistical workflow evaluated for
operational influenza surveillance; compare with published forecasting and
alignment approaches and avoid claiming to replace mechanistic transmission
models or to establish deep-learning superiority. `[DRAFT REQUIRED]
[CITATION REQUIRED]`

### 7.4 Limitations

Cover at least: single jurisdiction (Ontario) and single pathogen; the
exchangeable design in which 10 of 11 folds train on later seasons; the exposed
`2025-26` season; final-data replay with no origin-time vintages; the binomial
predictive intervals ignoring parameter uncertainty; information-set and
cadence asymmetries (PAGe row anchoring, legacy-GAM span/resolution/refit);
effective season count and pandemic-era exclusions; manual/timing-v2 ignition
labels; template misspecification; and real-time evidence from a single, possibly partial, season.
`[DRAFT REQUIRED] [RESULT REQUIRED]`

### 7.5 Future work

Propose prospective multi-season and multi-jurisdiction evaluation, extension
to other respiratory pathogens (including RSV), and the separate *R Journal*
software paper. Distinguish API generality, retraining portability, model
transportability, and actual external validity; bound generalizability to
Ontario influenza in the meantime (EPIFORGE item 19). `[DRAFT REQUIRED]`

## 8. Conclusion

Use three sentences:

1. What PAGe decomposes and why, for Ontario influenza surveillance.
2. The narrow empirical result and observed between-season variation.
   `[RESULT REQUIRED]`
3. The bounded operational/reproducibility implication, without claiming
   prospective effectiveness.

The second sentence must represent the full observed pattern. A mixed or
harmful primary result cannot be replaced by a favourable secondary result.

## Declarations

- Data availability: private Ontario surveillance data are not redistributed;
  state the authorized-access route, that only aggregates are published, and
  that `simulate_flu_seasons()` supplies synthetic examples under the documented
  data contract. `[PENDING]`
- Code availability: versioned code archive with DOI and package version,
  manifest, and synthetic replication entry point. `[ARTIFACT REQUIRED]`
- Ethics approval or authorization: `[DECISION REQUIRED] [PENDING]`
- AI-assisted work disclosure: summarize planning, review, coding, and writing
  assistance under the policy in force at submission.
- CRediT authorship statement: `[REQUIRED]`
- Competing interests: `[REQUIRED]`
- Funding: `[REQUIRED]`
- Acknowledgements: `[REQUIRED]`
- EPIFORGE 2020 reporting checklist: complete the 19-item checklist (Pollett et
  al., PLOS Med 2021, doi:10.1371/journal.pmed.1003793) as an appendix; mark any
  item that cannot be satisfied and explain why. `[DRAFT REQUIRED]`

## Main-text display map

| Display | Scientific job | Source status |
|---|---|---|
| Figure 1 | PAGe workflow schematic: M0 -> M1 -> M2 with adoption gate | Design-ready |
| Figure 2 | Representative season: observed vs forecasts with 50%/95% intervals and detected ignition/peak | `[ARTIFACT REQUIRED]` |
| Figure 3 | Season-level co-primary contrasts | `[RESULT REQUIRED]` |
| Figure 4 | Real-time 2026-27: weekly forecasts vs observations with intervals, all models | `[RESULT REQUIRED]` |
| Table 1 | Data, seasons, exclusions, denominators, observations | `[ARTIFACT REQUIRED]` |
| Table 2 | Models and information sets | `[ARTIFACT REQUIRED]` |
| Table 3 | Primary results, including WIS and coverage by phase and horizon | `[RESULT REQUIRED]` |

The main text carries exactly four figures and three tables, following the
display-economy review recorded in [`REVIEW_LOG.md`](REVIEW_LOG.md). Everything
else belongs in the supplement.

## Supplement skeleton

- Appendix A: Notation and complete M0/M1/M2 equations.
- Appendix B: Season declarations, information-boundary audit, and ignition-
  label protocol.
- Appendix C: Complete tuning grids, boundary actions, and frozen identities.
- Appendix D: Full M0 and M1 stage-level results.
- Appendix E: Canonical season-by-origin-by-horizon replay table and all model
  comparisons, including the mvgam `mod2AR` results and calendar-GAM details.
- Appendix F: No-M1-alignment ablation, M0-label sensitivity, weight and window
  sensitivities, and calibration.
- Appendix G: Simulation protocol (reference data-generating process plus four
  stressors under favorable/unfavorable conditions), parameters, seeds, Monte
  Carlo uncertainty, and extended results.
- Appendix H: Package API, tests, runtime logs, computational environment, and
  reproducibility manifest.
- Appendix I: EPIFORGE 2020 checklist.

Supplementary table assignments:

- Table S1: complete tuning grids and boundary actions (Appendix C).
- Table S2: full secondary forecast metrics, WIS, coverage, and intervals
  (Appendix E).
- Table S3: simulation summaries and Monte Carlo uncertainty (Appendix G).
- Tables S4--S5: M0 and M1 stage-level results (Appendix D).
- Table S6: ablations and attribution diagnostics, including the no-M1
  alignment ablation (Appendix F).
- Table S7: mvgam and calendar-GAM detail (Appendix E).
- Table S8: package validation and public-replication acceptance (Appendix H).

## Recommended drafting order

1. Use [`METHODS.md`](METHODS.md) as the prose source for Sections 2--4 and
   [`REPORTING_TEMPLATES.md`](REPORTING_TEMPLATES.md) as the controlled schema
   for tables, figures, and manifests.
2. Section 4.8 and the data/code declarations from verified package contracts,
   without claiming package-check or runtime results that do not yet exist.
3. Sections 3.1--3.5 and 4.1--4.7, excluding numerical tuning or historical
   peak-MAE claims.
4. Sections 5.1--5.5 only from the immutable Ontario result directories.
5. Section 5.6 after the `2026-27` season closes and is scored.
6. Section 1 after the empirical contribution, go/no-go decision, and citation
   set are stable.
7. Section 6 after every included result and sensitivity analysis is frozen.
8. Conclusion, title, highlights, abstract, and graphical abstract last,
   reflecting the complete observed primary-result pattern.
9. Supplements, EPIFORGE checklist, journal-format audit, and numeric-claim
   traceability audit before independent review.

## Section completion rule

A section is complete only when every claim has a verified citation or immutable
artifact, every number maps to a canonical table, every conditional paragraph
has passed its gate, and no placeholder remains silently unresolved.
