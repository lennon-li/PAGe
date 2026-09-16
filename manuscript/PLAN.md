# PAGe manuscript plan

Last updated: 2026-09-15

> **Amendment 2026-09-15: Epidemics target and new-cycle evidence**
>
> Source of truth:
> [`drafts/ANALYSIS_PROTOCOL_v2.0-draft.md`](drafts/ANALYSIS_PROTOCOL_v2.0-draft.md)
> and [`drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md`](drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md)
> (deviations D-14--D-27). This block steers the plan to the *Epidemics*
> Methodological Manuscript target; where it conflicts with older sections below,
> it controls.
>
> - Journal: *Epidemics*, article type **Methodological Manuscript** (clear
>   biological/public-health application with novel insight). Fallback
>   *Infectious Disease Modelling*. Reporting follows the EPIFORGE 2020 checklist (D-27).
> - Framing is application-first: operational Ontario influenza surveillance
>   forecasting (ignition, peak timing, 1--2-week positivity) at a public-health
>   agency, compared with the operational IRVRI legacy model (D-14).
> - Scope is Ontario influenza only; RSV is removed everywhere, including
>   fallbacks (D-16).
> - Two co-primary descriptive blocks: (1) PAGe versus the IRVRI legacy daily GAM
>   on chronological seasons `2022-23`--`2025-26`; (2) Workflow A 11-fold
>   exchangeable PAGe with paired comparators (D-14, D-17).
> - Scores: phase-weighted Bernoulli cross-entropy (log loss) primary; WIS and
>   50%/95% coverage secondary (D-17, D-25).
> - Comparators narrowed to persistence, seasonal naive, FluSight-style baseline,
>   M1 only, calendar GAM, and IRVRI mvgam `mod2AR`; elastic net, historical
>   analogue, and boosted tree removed (D-15, D-26).
> - `2025-26` is labelled **exposed**; the `2026-27` season is the only untouched
>   evidence and gets its own Real-time application section: final kit trained
>   on all 11 seasons, no outer holdout, reported to the submission date (D-9, D-28).
> - Structural ablations reduced: no-M1 stays in Workflow A; no ignition gate and
>   no alignment uncertainty move to simulation; bias off is a grid value (D-22).
> - Main text: the two co-primary blocks, persistence, seasonal naive,
>   FluSight-style baseline, M1 only, WIS/coverage, and M0/M1 stage summaries.
>   Supplement: mvgam, calendar GAM detail, no-M1 ablation, M0-label sensitivity,
>   weight/window sensitivities, reduced simulation, and package details
>   (protocol v2.0 section 6.7).
> - Length: about 6,500 words main text (Abstract 250; Introduction 750; Data
>   and targets 500; PAGe methods 1,700; Validation and evaluation 800; Results
>   1,300; Real-time application 500; Discussion 700; Conclusion 100).
> - Displays: Fig 1 workflow, Fig 2 representative season, Fig 3 season-level
>   co-primary contrasts, Fig 4 score/coverage by phase and horizon; Table 1 data
>   and exclusions, Table 2 models and information sets, Table 3 primary results.
> - The R package remains a reproducibility asset here; the package paper is a
>   later, separate submission to *The R Journal*.

## Manuscript configuration

- **Target journal:** *Epidemics*
- **Article type:** Methodological Manuscript (requires a clear biological/public-health application with novel insight)
- **Fallback journal:** *Infectious Disease Modelling*, then *BMC Infectious Diseases*
- **Reporting:** EPIFORGE 2020 checklist (D-27)
- **Working title:** *Phase-aligned gated forecasting of Ontario influenza positivity: an operational evaluation against a legacy surveillance model* [PENDING final wording]
- **Primary audience:** Public-health practitioners, infectious-disease modellers, and forecasting researchers
- **Internal drafting target:** About 6,500 words main text, excluding references and supplementary material; reconcile with the current journal guide before submission
- **Language:** English
- **Abstract drafting target:** Up to 250 words, unstructured, subject to final journal verification
- **Highlights drafting target:** 3--5 bullets, <=85 characters each
- **Graphical abstract:** Required as a separate file
- **Keywords drafting target:** Up to seven, subject to final journal verification
- **References:** Use one consistent style during drafting; convert to current journal style at submission
- **Draft format:** Markdown/Quarto initially; convert to the current journal submission format after the scientific content is stable

Journal references:

- [Epidemics: journal homepage](https://www.sciencedirect.com/journal/epidemics)
- [Epidemics: aims and scope](https://www.sciencedirect.com/journal/epidemics/about/aims-and-scope)
- [Epidemics: guide for authors](https://www.sciencedirect.com/journal/epidemics/publish/guide-for-authors)

Independent review status: **REVISE FIRST**. See [`REVIEW_LOG.md`](REVIEW_LOG.md) for Ming's 2026-09-01 review, prioritized gaps, decision criteria, and delegation audit record. The two-track literature synthesis is complete in [`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md) and [`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md). A journal-specific scan and fillable drafting guide are recorded in [`EPIDEMICS_ARTICLE_SCAN.md`](EPIDEMICS_ARTICLE_SCAN.md) and [`SKELETON.md`](SKELETON.md). The current-cycle analysis rules are drafted in [`drafts/ANALYSIS_PROTOCOL_v2.0-draft.md`](drafts/ANALYSIS_PROTOCOL_v2.0-draft.md) and the change register in [`drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md`](drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md); the prior-cycle protocol v1.4 and 11-season influenza universe remain the registered record in [`ANALYSIS_PROTOCOL.md`](ANALYSIS_PROTOCOL.md) and [`ONTARIO_FLU_SEASON_DECLARATION.md`](ONTARIO_FLU_SEASON_DECLARATION.md). Ignition labels are the timing-v2 one-week intervals of protocol v2.0. The RSV suitability gate is retired (D-16). External authorization and ethics decisions remain open in [`GOVERNANCE_DECISIONS.md`](GOVERNANCE_DECISIONS.md).

The manuscript-facing Methods prose is finalized in [`METHODS.md`](METHODS.md)
pending the protocol v2.0 freeze. The controlled reporting schemas for the
analysis manifest, canonical prediction table, tables, figures, and quality gates
are finalized in [`REPORTING_TEMPLATES.md`](REPORTING_TEMPLATES.md). Numerical
Results remain blocked until the corresponding evidence gates pass.

## Central research problem

Ontario public-health surveillance must forecast influenza test positivity one
to two weeks ahead, and report ignition timing and peak timing, while the
epidemic curve is still incomplete and its onset shifts between seasons. The
deployed legacy model is a daily, age-stratified GAM refit on a trailing window.
Weekly positivity curves vary substantially in onset, speed, amplitude, and peak
timing, so forecasting directly on calendar week can pool observations from
different epidemic phases and misalign the curve's turning point. PAGe addresses
this operational application through a sequential pipeline:

1. M0 prospectively detects epidemic ignition.
2. M1 aligns the partial current-season curve to historical epidemic templates.
3. M2 forecasts one- and two-week-ahead positivity using the aligned state, a frozen binomial GAM, and optional online correction.

The manuscript evaluates whether this operational decomposition improves
short-horizon forecasting over the deployed legacy model while maintaining a
leakage-safe, reproducible workflow.

## Provisional thesis

For Ontario influenza surveillance, explicit ignition gating and partial-curve
phase alignment followed by a phase-aware gated GAM may improve one- and
two-week-ahead probabilistic positivity forecasts relative to the operational
legacy model, while making the turning window and failure modes explicit and
keeping the weekly workflow reproducible under recorded provenance and
leakage-safe controls. The method is designed for prospective deployment and is
evaluated here by retrospective walk-forward replay; the PAGe R package is a
reproducibility asset for this claim, not the claim itself.

This proposed contribution will be assessed descriptively using the final
replay results. It must not be stated as an established conclusion before the
canonical results are complete.

## Intended contributions

### Applied contribution

- An operational Ontario influenza forecasting evaluation using 11 seasons of
  weekly positive and total test counts, with ignition timing, peak timing, and
  one- and two-week-ahead positivity as targets.
- Two co-primary descriptive blocks: full PAGe versus the deployed IRVRI legacy
  daily GAM on chronological seasons `2022-23`--`2025-26`, and an 11-fold
  exchangeable evaluation of the PAGe recipe with paired weekly comparators.
- Season-, horizon-, and epidemic-phase-specific results rather than a single
  pooled accuracy estimate, with WIS and 50%/95% coverage as secondary
  probabilistic summaries.
- Honest reporting of atypical seasons, pipeline failures, and the exposed
  `2025-26` fold.

### Methodological contribution

- A three-stage representation of seasonal influenza forecasting that separates
  ignition detection, phase alignment, and gated short-horizon prediction.
- A multi-template alignment procedure that updates epidemic phase and peak
  timing from the partial season observed to date.
- A binomial GAM forecast model on alignment-derived covariates with an explicit
  M2-versus-M1 adoption gate.
- A prospective-information validation design that separates tuning,
  exchangeable replay, chronological replay, and the final operational kit.

### Reproducibility asset

- The PAGe R package implementing M0, M1, M2, training, replay, and frozen
  prospective forecasting, used here to make the analysis traceable.
- Guarded stage lifecycles, artifact identities, and result manifests.
- Synthetic examples and tests distributable without private surveillance
  observations.
- A separate *The R Journal* package paper is planned after the main manuscript;
  the package is not a headline contribution of this paper.

## Research questions

1. Does full PAGe improve one- and two-week-ahead probabilistic forecasts of
   Ontario influenza positivity over the deployed IRVRI legacy model on
   chronological seasons, and over persistence and the FluSight-style baseline?
2. How does PAGe perform against the prespecified weekly comparators (calendar
   GAM, persistence, seasonal naive, FluSight-style baseline) in the 11-fold
   exchangeable evaluation, and against M1 only? (mvgam: supplementary, four
   chronological seasons.)
3. How does performance vary by forecast horizon, epidemic phase, season, and
   season type, including worst-season and pipeline-failure behaviour?
4. Are the probabilistic forecasts calibrated, and what are their WIS and
   50%/95% coverage?
5. Do M0 ignition accuracy and M1 peak-timing accuracy support the forecast
   claims, and does the no-M1 ablation attribute any gain to alignment?
6. Can the complete statistical workflow be reproduced through the documented
   R package without future-season leakage?

## Consolidated execution plan

### Authority and current status

This file is the authoritative manuscript plan. [`TODO.md`](TODO.md) is the operational checklist derived from it, and [`REVIEW_LOG.md`](REVIEW_LOG.md) preserves independent reviews and their audit records. If the files conflict, this plan controls until a dated amendment is recorded here.

- **Current decision:** **REVISE FIRST** following Ming's 2026-09-01 independent review; new-cycle scope set 2026-09-15 (this amendment).
- **Current phase:** Phase 0 governance, advancing Phase 1 protocol v2.0 freeze and Phase 2 production fixes in parallel.
- **Blocked work:** Headline Results drafting and submission formatting.
- **Application:** Ontario influenza only (RSV removed, D-16).
- **Target journal:** *Epidemics* Methodological Manuscript, conditional on a frozen protocol v2.0, a verified governed kit, the co-primary evidence blocks, and publication authorization.

### Decisions already fixed

1. The 2025--26 replay remains the historical acceptance decision already
   made: the evaluated candidate failed the locked NLL gate, although horizon
   and phase gates passed.
2. **Superseded by D-9 (2026-09-15):** the prior plan required a new holdout for
   any new-cycle search. There is no untouched historical season, so `2025-26`
   is retained as an outer fold labelled **exposed**, and the prospective
   `2026-27` season is the only untouched evidence for this cycle.
3. Historical M2 LOSO is conditional on globally selected M0/M1 choices and must not be described as fully nested validation.
> **Status (2026-09-15): PRIOR CYCLE** — commit 95c1c9f / CSV-label seasons / truncated 2025-26; not comparable with the new cycle. See drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md.

4. **Superseded by D-1--D-8 and D-20 (2026-09-15):** the historical
   `v16-corrected` incumbent and the legacy correction family are not governed
   defaults. The governed M2 family is `offset_subset_v1` on the M1 logit
   offset; the incumbent remains a confidence baseline only.
5. The headline Ontario model must be re-derived through the governed M0 -> M1 -> M2 lifecycle with recorded stage identities and resolved tuning boundaries.
6. Private Ontario observations will not enter the public repository. Public reproducibility will use synthetic data and permitted aggregate outputs.
7. The method is evaluated retrospectively by walk-forward replay and in real time on the 2026-27 season (final kit trained on all 11 seasons, no outer holdout, logged forecasts). Real-time evidence is reported only for the weeks available at submission and is not generalised beyond them.
8. Training, tuning, fitting, and freezing occur once for each target season. The resulting seasonal kit is reused across weekly origins; weekly M0 decisions, M1 alignment, and correction state are state updates rather than model retraining.
9. The historical 2025--26 acceptance replay belongs to a different artifact lineage and will be reported separately as a labelled historical record (protocol v2.0 section 6.1). Its new-cycle fold enters the 11-fold analysis on the same terms as every other valid season, but is not called untouched confirmation.
10. The principal Ontario influenza replay uses exactly the 11 non-excluded
    seasons already present in the current influenza workflow. No new influenza
    season data may be admitted under this protocol version.
11. `2011-12`, `2015-16`, `2020-21`, and `2021-22` remain outside the principal
    exchangeable-season set. `2015-16` is special diagnostic evidence only.
12. Scope is Ontario influenza only. RSV and other pathogens are out of scope (D-16).

### Headline question and co-primary comparisons

The manuscript reports two co-primary descriptive blocks under protocol v2.0
section 5.3:

1. **Operational baseline:** the season-equal mean of `L(PAGe) - L(legacy GAM)`
   on the four chronological seasons `2022-23`--`2025-26` (Tier 1 plus Tier 2
   prior-only PAGe kits), with every season's value shown.
2. **Recipe performance:** the Workflow A season-equal PAGe score across 11
   folds, with the paired contrasts against the calendar GAM, persistence,
   seasonal naive, FluSight-style baseline, and M1 only (mvgam in the
   supplement on the four chronological seasons).

The primary score is the phase-weighted Bernoulli cross-entropy (log loss) of
protocol v2.0 sections 2 and 5.1: equal weight per week within each phase band,
then equal weight per season. WIS and 50%/95% coverage are secondary. Negative
contrasts favour PAGe. All summaries are descriptive --- season values, mean,
median, SD, IQR, range, and leave-one-season-out means; no p-values, confidence
intervals, power, or superiority decisions. Row definitions, the
forecast-availability contract, and unavailable-forecast disposition follow
protocol v2.0 sections 5.2 and D-21.

### Stage-gated critical path

| Phase | Objective | Dependencies | Accountable role | Required deliverables | Exit gate | Status |
|---|---|---|---|---|---|---|
| 0. Governance | Resolve publication authorization and ethics blockers | None | Project lead and data steward | Publication authorization; ethics/REB determination; governance records | Every governance decision is dated and traceable | In progress: authorization and ethics pending |
| 1. Protocol v2.0 freeze | Freeze scoring weights, nested inner gate, recipe manifest, labels, comparator set, and season rules | Can proceed alongside Phase 0; must close before private results are opened | Manuscript and analysis leads | Frozen protocol v2.0; recipe manifest checksum; data checksums; freeze record | All `[FREEZE]` items resolved and every tuned boundary resolved or justified | Draft [`drafts/ANALYSIS_PROTOCOL_v2.0-draft.md`](drafts/ANALYSIS_PROTOCOL_v2.0-draft.md); 2026-09-15 decisions recorded |
| 2. Production fixes | Implement D-1--D-8, D-13, D-18--D-20 | Phase 1 freeze | Software lead | Fractional timing; MMWR season length; identical preprocessing; M0 loss; complete `2025-26`; fully nested inner gate; plain-shift alignment; walk-forward prefix; legacy-family research flag | Synthetic adapter and leakage tests pass | Pending |
| 3. Ontario reconstruction | Re-derive the governed M0 -> M1 -> M2 kit without holdout reuse | Phases 1--2 | Analysis and software leads | Frozen stage artifacts and identities; boundary audit; package version and commit; runtime records | Governed kit validates and every tuned boundary is resolved or justified | Pending |
| 4. Ontario evaluation | Run Workflow A 11-fold replay, chronological Tiers 1--2, legacy GAM adapter, comparators, intervals/WIS, and ablations | Verified Phase 3 kit | Analysis lead | Canonical replay table; two co-primary blocks; FluSight-style baseline; WIS/coverage; no-M1 ablation; M0/M1 stage summaries; artifact manifest | All eligible seasons reconcile to immutable outputs and independent checks pass | Pending |
| 5. Journal go/no-go | Decide whether the Ontario evidence supports the intended claim | Phase 4 evidence and authorization | Project lead with independent reviewer | Dated decision memo: proceed, narrow, redesign, or retarget | *Epidemics* path explicitly approved or replaced | Pending |
| 6. Simulation (reduced) | Characterize failure modes under a bounded stressor set | Frozen Phase 1 estimands; may run alongside Phases 3--4 | Statistical lead | Separate simulation protocol; reference DGP plus four stressors (timing shift, shape mismatch, bimodality, low testing volume); Monte Carlo outputs | Claims are bounded by demonstrated operating conditions | Pending; reduced per journal-fit audit |
| 7. Evidence freeze and drafting | Freeze displays and write the manuscript against verified evidence | Phases 4 and 6 | Manuscript lead | Immutable result directory; Methods; Results; Discussion; supplement; EPIFORGE 2020 checklist; availability and AI-use statements | Every numerical claim maps to an artifact; no critical evidence gaps remain | Pending |
| 8. Independent review and submission | Stress-test, revise, format, and submit | Phase 7 complete draft | Project lead and independent reviewers | Statistical review; revised manuscript; citation audit; package check; current journal-format audit; cover letter | Submission-readiness checklist passes | Pending |

### Phase 0 and Phase 1 decisions that must be closed

| Decision | Default position for planning | Required evidence | Owner | Due before |
|---|---|---|---|---|
| Ontario publication authorization | Not yet assumed | Written custodian decision and disclosure limits | Data steward | Phase 4 outputs are used publicly |
| Ethics or REB status | Determination required | Institutional or project-level determination | Project lead | Phase 3 |
| Influenza season universe and exclusions | Frozen: 11 equal valid seasons; `2011-12`, `2015-16`, `2020-21`, and `2021-22` remain excluded; any valid season may be the outer holdout | [`GOVERNANCE_DECISIONS.md`](GOVERNANCE_DECISIONS.md) and [`ONTARIO_FLU_SEASON_DECLARATION.md`](ONTARIO_FLU_SEASON_DECLARATION.md) | Scientific lead | Complete |
| Ontario backfill and revisions | Frozen: one common final-data snapshot with explicit retrospective limitation (G-05) | Protocol v2.0 section 1.3 and source metadata | Data lead | Analysis rule complete; source audit pending |
| Primary score | Frozen: phase-weighted Bernoulli cross-entropy; equal week within phase band then equal season; two co-primary blocks | Protocol v2.0 sections 2, 5.1--5.3 | Statistical lead | Complete in draft |
| Secondary probabilistic summaries | Frozen: binomial/posterior predictive quantiles, WIS, 50%/95% coverage and width | Protocol v2.0 section 5.1 (D-25) | Statistical lead | Complete in draft |
| Comparator set | Narrowed: persistence, seasonal naive, FluSight-style baseline, M1 only, calendar GAM, mvgam `mod2AR`; legacy GAM adapter | Protocol v2.0 section 4 and D-15/D-26 | Scientific lead | Complete in draft |
| Ignition labels | Frozen: timing-v2 one-week intervals, fold-safe withholding | Protocol v2.0 section 1.4 (D-1) | Analysis lead | Pending freeze record |
| M2-versus-M1 adoption gate | Frozen: mean season gain rule with floors and no-degradation condition; not reported as inference | Protocol v2.0 section 2 (D-10) | Statistical lead | Pending freeze record |
| Legacy GAM and mvgam adapters | `irvri_adapter_gam()` chronological Tiers 1--2 (local hosts only); mvgam `mod2AR` on the same four chronological seasons with prespecified MCMC settings and diagnostics gate | Protocol v2.0 sections 3.2 and 4 | Software lead | Reviewed on synthetic data before Phase 4 |
| EPIFORGE 2020 checklist | Complete all 19 items at drafting | EPIFORGE 2020 (Pollett et al. 2021) | Manuscript lead | Phase 7 |
| Manuscript package version | Pin the exact release or commit used for all final analyses | Package version, commit, lockfile/session information | Software lead | Phase 3 freeze |

### Ontario evidence requirements

The Ontario analysis is manuscript-ready only when all of the following exist in one immutable, manifest-bound result set:

1. A re-derived governed kit with validated M0, M1, and M2 identities.
2. A boundary audit covering every genuinely tuned parameter.
3. Recomputed M1 validation evidence or an explicit retirement of irreconcilable historical values.
4. A validated legacy GAM adapter and a fixed mvgam `mod2AR` specification.
5. Complete walk-forward predictions for every eligible replay season and horizon.
6. The two co-primary comparisons with complete season-specific results and descriptive aggregation.
7. Persistence, seasonal-naive, FluSight-style baseline, M1-only, and no-M1 ablation results.
8. M0-generated-label sensitivity results; `-1`/`+1` label shifts are simulation-only (D-22).
9. Binomial or posterior predictive quantiles, WIS, and 50%/95% coverage for every scored model.
10. A canonical replay table containing season, horizon, phase, target, prediction, score, model identity, artifact identity, and runtime provenance.
11. A reconciliation showing that all reported tables and figures derive from the same canonical inputs.
12. The historical 2025--26 holdout result reported unchanged and clearly separated from the new development cycle.

### Go/no-go decision after Ontario evaluation

Proceed with the *Epidemics* path when the governed influenza kit is verified,
publication is authorized, and the two co-primary blocks show a scientifically
and operationally defensible pattern across seasons, with calibrated
probabilistic forecasts. Mixed or small gains require a narrower claim and
supportive simulation evidence.

Narrow or retarget the manuscript when the co-primary contrasts are small,
inconsistent across seasons, driven by one season, or accompanied by material
pipeline failures; also narrow or retarget if kit reconstruction fails or
private-data publication is not authorized. Redesign the method or its claims
when ignition-label sensitivity indicates that apparent gains depend mainly on
manually selected labels. Record the decision in a dated memo and link it from
this plan.

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
- Request independent review at the Phase 5 go/no-go gate and again before submission.

## Manuscript structure

The operational section-by-section drafting guide is [`SKELETON.md`](SKELETON.md).
It follows the verified patterns in
[`EPIDEMICS_ARTICLE_SCAN.md`](EPIDEMICS_ARTICLE_SCAN.md) while retaining this
plan's scientific gates. If wording or section status differs, this plan and the
frozen analysis protocol control the scientific claim; the skeleton controls
drafting order and placeholder discipline.

### Abstract -- up to 250 words

State the operational forecasting problem (Ontario influenza positivity,
ignition, peak timing, and one- and two-week horizons), the PAGe pipeline, the
co-primary validation design, the main numerical findings from the two blocks,
and code availability. Unstructured. Do not write the final abstract until all
headline results are frozen.

### 1. Introduction -- approximately 750 words

- Motivate short-horizon influenza positivity forecasting for Ontario public-health decisions.
- Describe the operational problem: ignition timing, peak timing, and 1--2-week-ahead positivity while the season is incomplete.
- Explain why calendar time is an unstable epidemic coordinate across seasons.
- Review the main categories of seasonal-curve and infectious-disease forecasting approaches, including the operational legacy model.
- Identify the gap: phase alignment, gated adoption, and leakage control are rarely combined in one operational surveillance workflow.
- State the contributions and preview the empirical findings without overselling them.

### 2. Data and forecasting targets -- approximately 500 words

- Define season index, MMWR week, within-season week, positive tests, total tests, and observed positivity.
- Define the one- and two-week-ahead binomial forecasting targets and the ignition and peak-timing targets.
- Define the information available at each forecast origin (walk-forward prefix).
- Distinguish observed positivity from the underlying positivity probability.
- State the season construction (MMWR week 27 start), the 11 principal seasons, the 4 exclusions, denominator definition, and missing-data rules (protocol v2.0 sections 1.1--1.3).
- Justify the 1--2-week horizons against the operational decision context.
- State that the analysis is Ontario influenza only; the legacy GAM needs a separate daily, age-stratified series.

### 3. PAGe methods -- approximately 1,700 words

#### 3.1 M0: ignition detection

- Prospective threshold gates and sustained-elevation requirement.
- Eligibility window and ignition locking, fractional timing.
- Tuning objective and ignition-error definition (protocol v2.0 section 2).

#### 3.2 M1: phase alignment

- Historical reference/template construction.
- Shift, dilation, amplitude, and offset parameters.
- Multi-template weighting by fit and slope similarity.
- Peak estimate, alignment uncertainty, post-peak freezing, and the plain-shift alignment coordinate (D-18).

#### 3.3 M2: short-horizon forecasting

- Joint binomial GAM for horizons one and two on the M1 logit offset.
- Aligned-time, template, EWMA, derivative, and uncertainty features.
- Frozen model, optional online correction, and the M2-versus-M1 adoption gate.
- Forecast algorithm using information available through the current week only.

#### 3.4 End-to-end algorithm

- Show the sequential M0 -> M1 -> M2 weekly algorithm.
- Separate offline tuning/fitting from online forecasting.
- State explicitly that one seasonal training workflow produces one frozen kit that is reused for every weekly origin in that season.
- Provide pseudocode in the main paper and implementation detail in the supplement.

### 4. Validation and evaluation design -- approximately 800 words

- Declare disjoint training, exclusion, and application season sets (11 principal, 4 excluded).
- Describe Workflow A exchangeable 11-fold replay and the chronological Tiers 1--2, including the information-set asymmetries of the legacy GAM and mvgam (protocol v2.0 sections 3 and 4).
- Describe fold-specific construction of leakage-sensitive features and the fully nested inner M2 gate.
- Describe stagewise tuning and boundary expansion before freeze.
- Define the co-primary and secondary metrics, the common-row forecast-availability contract, and descriptive aggregation.
- State the exposed `2025-26` status and the real-time `2026-27` application design (section 6).
- Include one reproducibility/package paragraph (<=200 words) covering the PAGe R package, synthetic examples, a versioned code archive, and the separate *The R Journal* paper.

### 5. Results (retrospective) -- approximately 1,300 words

#### 5.1 Operational baseline block (chronological)

- Present the PAGe versus IRVRI legacy GAM season-equal contrast on `2022-23`--`2025-26`, with every season's value and descriptive summaries.
- Present the legacy GAM pre-ignition forecasts and Tier 1 row coverage as secondary.

#### 5.2 Recipe performance block (11-fold)

- Present the season-equal PAGe score across 11 folds with paired contrasts against the calendar GAM, persistence, seasonal naive, FluSight-style baseline, and M1 only.
- Report horizon- and phase-specific results, worst seasons, and pipeline failures.
- Present the no-M1 ablation result.
- Report M0 ignition error and M1 peak-timing error as stage summaries.
- Present WIS and 50%/95% coverage as secondary probabilistic summaries.
- Present the historical `2025-26` acceptance replay separately as a labelled historical lineage; do not pool it with new-cycle fold results.

### 6. Real-time application, 2026-27 -- approximately 500 words

- Final kit trained once on all 11 eligible seasons; no outer holdout. Evaluation is the new 2026-27 season as it happens.
- Frozen kit identity, append-only timestamped weekly logs, real-time data vintages; M1 only, production legacy GAM, persistence, and FluSight-style baseline run in parallel.
- Report weekly forecasts, ignition/peak timing, log loss, WIS and coverage up to the latest data available at submission, with the analysis date; later weeks added at revision.
- Report operational outcomes (missed weeks, errors, late data). Keep separate from retrospective results.

### 7. Discussion -- approximately 700 words

- Interpret the operational and statistical findings.
- Explain when phase alignment and gating appear useful and when they do not.
- Discuss the exposed `2025-26` fold and what the partial real-time 2026-27 season does and does not show.
- Address dependence on ignition labels, limited season count, atypical pandemic seasons, surveillance-system heterogeneity, final-data snapshots, and model misspecification.
- Discuss WIS/coverage findings and calibration limits.
- State public-health implications for Ontario influenza surveillance.
- Bound generalizability to Ontario influenza and identify the prospective `2026-27` season and future work.

### 8. Conclusion -- approximately 100 words

- One short paragraph restating the application, the co-primary findings, and the reproducibility asset. No new numbers.

### Data and software availability

- Publicly release the package, synthetic data generator, simulation code, and manuscript analysis scripts.
- Do not commit or distribute private Ontario surveillance observations; state the access restrictions and any controlled-access process.
- Provide synthetic examples that exercise the full package workflow.
- Archive a versioned code and aggregate-results release with a DOI (e.g. Zenodo) [PENDING].
- Provide disclosure-safe aggregate tables and figures only after organizational policy review.
- Submit the separate *The R Journal* package paper after the main manuscript [PENDING].

## Prespecified comparisons

The comparator set is frozen in protocol v2.0 section 4 (D-15, D-26):

1. IRVRI legacy daily GAM (operational baseline; chronological Tiers 1--2 only).
2. Calendar-week binomial GAM (registered v1.4 primary comparator, now secondary).
3. IRVRI mvgam `mod2AR` (fixed before any evaluation run).
4. Persistence.
5. FluSight-style baseline (standard external benchmark).
6. Seasonal naive (Jeffreys-pooled training seasons).
7. M1 only (internal reference).

Removed from v1.4: lagged elastic net, historical-analogue continuation, and
gradient-boosted tree. Required sensitivities are protocol v2.0 section 5.4:
legacy weights, the registered v1.4 primary line, test-count-weighted phase
score, daily-aggregated weekly targets, without `2025-26`, and fold-specific
M0-generated training labels. Structural ablations are protocol v2.0 section
5.4/D-22: no M1 alignment in Workflow A; no ignition gate and no alignment
uncertainty in simulation only; bias off is a grid value. No model may be added
in response to headline results.

The co-primary blocks summarize observed performance of the assembled PAGe
workflow; they cannot attribute any gain to phase alignment alone. The
prespecified no-M1 ablation is a descriptive attribution diagnostic and remains
secondary.

## Outcome measures

### Primary

- Phase-weighted Bernoulli cross-entropy (log loss), equal week within phase
  band then equal season (protocol v2.0 sections 2 and 5.1).
- Two co-primary descriptive blocks (protocol v2.0 section 5.3).

### Secondary

- Weighted interval score (WIS) on the positivity scale, with the same phase
  weights and aggregation.
- Empirical coverage of the central 50% and 95% intervals, and interval width.
- Positivity mean absolute error.
- M0 signed and absolute ignition error and miss rate, per fold.
- M1 weighted and unweighted peak-week MAE, per fold.
- Worst-horizon and worst-phase degradation; pipeline-failure rate.
- Runtime per training run and per weekly update.

The binomial predictive uses the realized target test count conditional on
`p_hat` and is labelled as ignoring parameter uncertainty; the legacy GAM and
mvgam use posterior predictive draws and the FluSight-style baseline uses its
own quantiles (protocol v2.0 section 5.1). Results must be stratified by horizon
and relevant epidemic phase. Report observed between-season variation
descriptively; no hypothesis tests.

## Planned displays

Main text (maximum 4 figures, 3 tables):

1. Fig 1: PAGe workflow schematic (M0 -> M1 -> M2).
2. Fig 2: Representative season, observed versus forecasts with 50%/95%
   intervals and detected ignition and peak.
3. Fig 3: Season-level co-primary contrasts.
4. Fig 4: Real-time 2026-27 weekly forecasts versus observations with intervals, all models.
5. Table 1: Data, seasons, and exclusions.
6. Table 2: Models and information sets.
7. Table 3: Primary results, including WIS and coverage by phase and horizon.

All figures must remain interpretable in grayscale and use accessible colours.

Supplement:

1. mvgam details and results.
2. Calendar GAM details.
3. No-M1 ablation.
4. M0-label sensitivity.
5. Weight and window sensitivities.
6. Simulation (reference DGP plus four stressors).
7. Package details (architecture, lifecycle, tests, version).
8. Full season-by-horizon replay tables, including the historical `2025-26`
   result as a separately labelled lineage.

## Evidence that must be reconciled before drafting Results

- Produce one canonical result table containing every eligible seasonal replay.
- Verify the provenance of each candidate and incumbent artifact.
- Resolve or explicitly retire the conflicting historical M1 peak-MAE values.
- Do not describe historical M2 LOSO as fully nested when M0/M1 choices were globally selected.
- Preserve the existing 2025--26 holdout decision: the evaluated candidate failed the locked NLL gate, although its horizon and phase gates passed.
- Do not tune further against 2025--26. Any new search begins a new pre-holdout development cycle; `2025-26` is retained as an exposed fold (D-9).
- Verify boundary winners and document expansions, null boundaries, or hard constraints.
- Confirm the legacy GAM adapter and mvgam `mod2AR` are validated on synthetic data before scoring.
- Record complete training and replay runtimes from machine-readable run records.
- Put all final manuscript result tables and figure inputs in a single immutable analysis directory.

## Literature-review workstreams

Search and synthesize literature on:

1. Short-horizon influenza and respiratory-virus forecasting.
2. Epidemic phase, curve registration, and functional alignment.
3. Change-point and epidemic-onset detection.
4. Dynamic generalized additive models and adaptive forecast correction.
5. Prospective, rolling-origin, and leave-one-season-out evaluation.
6. Forecast calibration and proper scoring rules for binomial surveillance data.
7. Statistical software for infectious-disease forecasting.

The literature review is complete in [`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md) and [`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md). It identifies existing implementations and compares their assumptions, data requirements, outputs, and relevance to PAGe. The resulting comparator set is frozen in protocol v2.0 section 4; additions in response to headline results are prohibited.

## Reproducibility package

The manuscript release should contain:

- A versioned PAGe package release.
- Installation and system requirements.
- A single public replication entry point.
- Fixed random seeds and recorded package versions.
- Synthetic data and a data dictionary reproducing the full API workflow.
- A versioned, citable code and aggregate-results archive with a DOI [PENDING].
- Public simulation inputs and outputs.
- Disclosure-safe manuscript tables and figures.
- A private-data analysis script accepting an authorized file path.
- A result manifest binding tables and figures to code and artifact identities.
- A test and package-check report.

## Drafting workflow

Draft in the order established by the consolidated critical path:

1. Write the reproducible Methods and protocol skeleton after Phase 1 freezes the analysis choices.
2. Do not draft headline Results until the Ontario Phase 4 evidence gate passes.
3. Draft Ontario Results directly from the immutable canonical replay inputs.
4. Draft Simulation Results after the reduced simulation completion gate.
5. Complete the dated Phase-5 go/no-go memo before drafting the Introduction,
   Discussion, or Conclusion.
6. Write the Introduction after the literature matrix, empirical contribution,
   and Phase-5 decision are stable.
7. Write the Discussion after all included comparators and sensitivity analyses are frozen.
8. Write the abstract last, using only traceable numerical findings.
9. Conduct citation, notation, data/code availability, numerical-claim, and writing-quality audits.
10. Complete independent review, one major revision round, journal formatting, supplement, cover letter, and disclosure statements.

Record all AI-assisted work and prepare a disclosure consistent with the Elsevier and journal policies in force at submission.

## Submission-readiness gates

The manuscript is ready for submission only when all of the following are true:

- [ ] The central thesis is supported or appropriately narrowed by the final evidence.
- [ ] The comparator set was prespecified and evaluated with leakage-safe walk-forward information boundaries.
- [ ] The two co-primary descriptive blocks are reported with season-specific values and descriptive aggregation.
- [ ] Probabilistic forecasts are reported with WIS and 50%/95% coverage.
- [ ] The exposed `2025-26` fold and the historical acceptance replay are labelled and not pooled with new-cycle results.
- [ ] Ontario influenza is the only application; no RSV or cross-pathogen claims or sections remain.
- [ ] All tuning boundaries are resolved or justified.
- [ ] All seasons appear in one canonical replay table with consistent definitions.
- [ ] Every table and figure is generated from a frozen analysis artifact.
- [ ] Every numerical claim is traceable to a result table or script.
- [ ] Private observations are absent from the public repository.
- [ ] Synthetic replication materials exercise the complete package workflow.
- [ ] Package tests and checks pass in the release environment.
- [ ] The EPIFORGE 2020 checklist is completed and attached.
- [ ] Data, code, conflicts, funding, ethics, and AI-use statements are complete.
- [ ] The final manuscript conforms to the current *Epidemics* Methodological Manuscript guide for authors.

## Fallback journal strategy

If the manuscript is not suitable for *Epidemics*:

1. Submit to *Infectious Disease Modelling* (near-exact scope, applied evaluations common, low APC).
2. Submit to *BMC Infectious Diseases* (scientifically-valid gate, low risk).
3. If the results are strong and the evidence is broadened beyond Ontario influenza (for example validated intervals plus additional jurisdictions or pathogens), consider the *International Journal of Forecasting* with its proper-scoring and reproducibility expectations.
4. The R package is submitted separately to *The R Journal* after the main manuscript, regardless of the main venue.
