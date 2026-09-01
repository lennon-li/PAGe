# PAGe manuscript review log

Last updated: 2026-09-01

## 2026-09-01 — Independent review of manuscript plan and gaps

### Review record

- **Reviewer:** Ming
- **Execution route:** Anthropic Claude subscription through Claude Code
- **Model:** Claude Opus 5
- **Reasoning level:** High
- **Scope:** Read-only review of `manuscript/PLAN.md`, `manuscript/TODO.md`, and selected PAGe project documentation
- **Restrictions:** No web access, private surveillance data, result artifacts, file edits, or helper agents
- **Outcome:** Completed successfully; no manuscript files were changed by the reviewer
- **Runtime:** Approximately 211 seconds
- **Reported usage:** 7 turns; 15,388 output tokens, including 8,006 reasoning tokens
- **Reported cost:** USD 1.200612

### Verdict

**REVISE FIRST.** The plan's governance is stronger than its present evidence base, and the gap-closure TODO gives external validation priority before the primary Ontario evidence is manuscript-ready. The current evidence does not yet support a credible submission to *Epidemics* because the primary comparative analysis, artifact lineage, and canonical replay results remain unresolved.

### Strengths to preserve

- Leakage-safe season governance and the prohibition on further tuning against the 2025--26 holdout.
- Honest reporting that the evaluated 2025--26 candidate failed the locked NLL gate while passing horizon and phase gates.
- Explicitly conditional, rather than fully nested, characterization of historical M2 LOSO.
- Separation of workflow portability after retraining from direct model transportability.
- Refusal to pool incompatible surveillance systems into one headline metric.
- Private-data protections, immutable result manifests, external-validation completion gates, and fallback strategies.

### Critical findings

1. **The primary Ontario application lacks scheduled comparative work.** Add an Ontario workstream before external validation to evaluate all prespecified baselines and ablations with season-level uncertainty.
2. **The working `v16-corrected` incumbent has incomplete historical lineage.** It cannot serve as the manuscript's headline model unless its specification is re-derived through the governed lifecycle. Retain the historical incumbent only as contextual evidence if lineage cannot be reconstructed.
3. **Season exclusions require prespecified justification.** Add a dated rationale for excluding 2011--12 and 2015--16, or reinstate them in a sensitivity analysis.

### High-priority findings

1. Write a reproducible manual ignition-labeling protocol; perturb labels and evaluate a variant using all M0 labels.
2. Declare one primary comparison and outcome. A candidate is full PAGe versus the calendar-week GAM using pooled two-week-ahead binomial NLL, with season-clustered uncertainty. Label other comparisons secondary or exploratory and document expected interval precision.
3. Resolve the conflicting historical M1 peak-MAE values through executable recomputation, or retire them.
4. Complete the literature review before freezing the final comparator set.
5. Prespecify simulation data-generating processes, including at least one process that is structurally unfavorable to PAGe's templates.
6. Confirm research-ethics requirements and data-custodian publication authorization before substantial manuscript analysis.
7. Document the origin and rationale for the 0.02 NLL acceptance gate. If it was not prespecified, emphasize effect estimates and uncertainty instead of presenting it as a confirmatory threshold.
8. Replace claims that the method is "prospectively deployable" with the more supportable wording "designed for prospective deployment and evaluated by retrospective walk-forward replay" until prospective deployment evidence exists.

### Additional findings

- Rename the planned "Nested-LOSO" figure to "Conditional LOSO."
- Specify whether NLL is binomial or Bernoulli and freeze the exact RMSE or Brier-type definition.
- Reduce the planned main-text display count; move approximately four or five tables to supplementary material and reserve more space for Results.
- Document how Ontario reporting backfill and revisions are handled.
- Assign owners, expected effort, and dated go/no-go decisions.
- Pin the package version used for the manuscript and time-box additions to the comparator set.
- State explicitly that readers cannot reproduce private Ontario numerical results from public materials alone; provide a public external or synthetic replication workflow.

### Revised critical path recommended by the reviewer

1. Resolve inexpensive blockers: publication authorization, season-exclusion rationale, metric definitions, and LOSO terminology.
2. Re-derive the Ontario kit through the governed M0 -> M1 -> M2 lifecycle, resolve tuning boundaries, and recompute M1 results.
3. Complete the literature review, then freeze comparators.
4. Run the Ontario comparator and ablation analysis with season-clustered uncertainty and produce the canonical replay table.
5. Hold a go/no-go review. Continue to the external application if Ontario evidence supports a defensible methodological contribution; otherwise narrow the claims or retarget the manuscript.
6. Run prespecified simulations that include template-compatible and unfavorable data-generating processes.
7. Conduct the external public-data application only after the go/no-go decision.
8. Draft with fewer main-text displays and qualified prospective-deployment language.

### Decision evidence

Proceed with *Epidemics* if the re-derived Ontario kit is verified, the prespecified primary comparison shows a defensible benefit with season-clustered uncertainty, and publication authorization is confirmed. An external application remains desirable, but a defensible methods manuscript may proceed without it if simulations establish behavior under unfavorable conditions and generalization claims are deferred.

Retarget or redesign if the Ontario advantage is within resampling uncertainty, the governed kit cannot be re-derived, publication authorization is unavailable, or label-sensitivity analysis indicates that apparent gains depend mainly on manually chosen ignition labels.

### Disposition recorded 2026-09-01

The review was accepted for manuscript planning. Its Ontario-first ordering, conditional external application, governed-kit reconstruction, primary-comparison protocol, label sensitivity, season-exclusion rationale, precision assessment, simulation stress test, authorization checks, qualified deployment wording, conditional-LOSO terminology, artifact consolidation, and go/no-go criteria were incorporated into the authoritative [`PLAN.md`](PLAN.md) and operational [`TODO.md`](TODO.md).

This disposition means the recommendations have been scheduled and governed; it does not mean the underlying analyses or authorization tasks are complete. All scientific and operational items remain open until their exit evidence is linked from the checklist.

## 2026-09-01 — Dataset decision amendment

The project lead selected **Ontario RSV surveillance data** as the conditional second-pathogen application. This choice holds jurisdiction constant while evaluating pathogen-specific retraining, subject to the Ontario influenza go/no-go decision and a pre-fit RSV audit covering the exact source/version, weekly positive and total counts, season support, missingness, reporting revisions, access classification, licence or authorization, and publication permissions.

The selection does not authorize model fitting, establish that the data are public, or complete the scientific rationale. Those remain explicit open items in [`TODO.md`](TODO.md).

## 2026-09-01 — Independent two-track literature review

### Delegation record

Two independent read-only reviewers were deployed without access to private surveillance observations or result artifacts and without communication with each other.

| Reviewer | Route | Emphasis | Reported evidence/usage | Repository changes |
|---|---|---|---|---|
| Argie | Google Gemini 3.1 Pro High through Antigravity CLI (`agy`), Google AI Pro | Mathematical/mechanistic and statistical models | 21 checked sources; 8 permitted local-file reads and 5 scholarly web searches; token/cost telemetry not exposed | None |
| Liz | OpenAI GPT-5.6 Luna, high reasoning, through Codex CLI on the second OpenAI entitlement | Machine learning, probabilistic forecasting, and operational evaluation | 32 checked source locators; CLI reported 218,883 tokens; cost telemetry not exposed | None |

The successful Argie run followed discovery of the installed `agy` launcher. An initial planning-mode invocation stopped when a write action was automatically denied; it produced no review output and was rerun read-only without planning mode. Two Liz invocations failed at CLI argument parsing before model execution; the corrected invocation completed. Earlier attempted Wei and replacement-Jax routes produced no review output because destination-specific external access was not authorized; they were abandoned rather than bypassed.

### Consolidation and citation audit

Both reviewers independently concluded that the manuscript should center the dependency structure `ignition -> partial-curve phase/peak -> probabilistic forecast`, rather than frame PAGe as only a one- or two-week predictor. Both identified empirical-Bayes/historical-analogue epidemic curves and compartmental data-assimilation systems as the closest conceptual competitors. Both advised against making high-capacity neural models primary Ontario comparators because the effective independent sample is the number of seasons, not the number of weekly rows.

The parent reviewer deduplicated the source sets and rechecked the citations supporting the main recommendations against primary or official locators. One Argie-supplied DOI for the CDC 2013--14 influenza challenge was incorrect and was replaced with the verified DOI `10.1186/s12879-016-1669-x`; no uncorrected agent bibliography was copied into the manuscript record.

### Disposition

The consolidated review is recorded in [`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md), with 26 retained sources in [`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md). The literature-synthesis checklist item is complete.

### Protocol disposition recorded 2026-09-01

Following the project lead's instruction to proceed, the core analysis was frozen in [`ANALYSIS_PROTOCOL.md`](ANALYSIS_PROTOCOL.md). It defines seven standalone models, four structural PAGe ablations, ignition-label sensitivities, a single confirmatory PAGe-versus-calendar-GAM contrast at horizon two, equal-season aggregation, paired season-level uncertainty, and the Ontario RSV data-suitability gate. The empirical core includes statistical, historical-analogue, and regularized machine-learning comparators. SIR/SIRS filtering remains represented in the mathematical review and planned simulations but is excluded from the empirical ranking because a fair analysis would require an additional latent-incidence-to-test-positivity observation model not identified by the available surveillance target.

Frozen protocol v1.0 SHA-256: `b2ab3075d040b8b4c2e3ce71187cde3922e36c8f95f217808db29052d112acff`.

### Training-cadence amendment recorded 2026-09-01

The project lead clarified that the complete training and tuning workflow runs once per target season and emits one frozen seasonal kit. Weekly M0 detection, M1 phase/peak alignment, M2 forecasting, and the permitted adaptive correction update state against that kit without retraining model parameters. The clarification is recorded as protocol v1.1 and does not change the frozen estimands or comparator set.

Frozen protocol v1.1 SHA-256: `04ce726af5dbc603c9568373101f789000a482708f8d4878040632af80a1b6ee`.

## 2026-09-01 — *Epidemics* article scan and manuscript skeleton

### Delegation record

- **Reviewer:** Argie
- **Execution route:** Google AI Pro through Antigravity CLI (`agy`)
- **Model:** Gemini 3.1 Pro High
- **Reasoning level:** High
- **Scope:** Read-only scan of eight comparable *Epidemics* articles plus the
  existing manuscript plan, protocol, literature synthesis, TODO, and review log
- **External evidence:** Crossref, Semantic Scholar, ScienceDirect/DOI records,
  and PubMed Central
- **Reported tool use:** Eight local-file views, four web searches, and three
  read-only API-query commands
- **Repository changes:** None by the reviewer

An attempted Antigravity internal-file write was denied because the delegation
packet authorized read-only work. Argie returned its report in the interactive
session instead. The parent reviewer independently verified all eight article
titles, journal records, publication years, and DOI locators against official
ScienceDirect results.

### Parent disposition

Argie's eight-article set and broad design recommendations were retained, but
the claim that comparable papers use one rigid IMRaD section order was narrowed:
the verified articles are consistently method-forward but vary in their exact
top-level headings. Detailed structural evidence was also weaker for records
available only through metadata and indexed text than for open full text.

The verified scan is preserved in
[`EPIDEMICS_ARTICLE_SCAN.md`](EPIDEMICS_ARTICLE_SCAN.md). Its synthesis informed
the fillable [`SKELETON.md`](SKELETON.md), which now serves as the
section-by-section authoring guide. The skeleton keeps the paper centered on the
aligned operational chain `ignition -> phase/peak -> h1/h2 forecast`, records the
once-per-season training cadence, separates retrospective replay from actual
prospective deployment, limits the main-text display plan, and marks every
unsupported numerical or conditional claim.

- **Article-scan SHA-256:**
  `106b8057698d19fa1b9261c1c75c3df1abd67b28f138a5d92489dadd29e064c0`
- **Manuscript-skeleton SHA-256:**
  `d504d6c5fafb4c8baa00a1ac3c36260987b4ae6b3a6c10421c8a13bee1993378`

## 2026-09-01 — Opus review of journal skeleton and disposition

### Review record

- **Reviewer:** Ming
- **Execution route:** First-party Anthropic subscription through Claude Code
- **Model:** Claude Opus 5
- **Reasoning level:** High
- **Scope:** Read-only review of the journal skeleton against the manuscript
  plan, frozen analysis protocol, article scan, TODO, and review log
- **Restrictions:** No web access, private surveillance observations, result
  artifacts, file edits, or helper agents
- **Outcome:** Completed successfully; no repository files were changed by the
  reviewer
- **Runtime:** Approximately 411 seconds
- **Reported usage:** 10 turns; 31,882 output tokens, including 13,720 reasoning
  tokens
- **Reported cost:** USD 2.0808515

A CodeGraph context hook injected package information outside the bounded review
packet. The reviewer disclosed the injection and stated that it was not used;
the parent disposition below does not rely on those package claims.

### Verdict

**MINOR REVISION** with 76% confidence. The architecture was judged strong, but
the skeleton omitted several frozen protocol details and over-attributed the
primary assembled-workflow contrast to phase alignment.

### Findings accepted and implemented

- Added the ignition-to-plus-12 evaluation window, inner LOSO selection,
  one-standard-error rule, comparator tuning rule, exact clipped per-trial NLL,
  pipeline-failure disposition, M1 weighted peak metric, and named secondary
  strata.
- Reframed the confirmatory claim as full PAGe versus calendar-week GAM. The
  no-M1 ablation is now the pre-identified descriptive attribution diagnostic
  and remains secondary.
- Assigned the historical 2025--26 acceptance replay its own Results subsection
  and supplementary table, identified its different lineage, and excluded it
  from the new governed replay aggregate.
- Marked the provenance of the historical `0.02` NLL gate as an unresolved
  decision, added favorable/inconclusive/harm result branches, and inserted the
  Phase-4 go/no-go memo before claim-bearing drafting.
- Rebalanced the maximum body budget to 8,400 words and the abstract to exactly
  250 words, simplified the main displays, added a representative forecast
  trajectory, and moved simulation findings from Methods to Results.
- Reconciled the 2015--16 rule across files: include it in the principal
  analysis when generic quality criteria pass, with historical exclusion only
  as a prespecified sensitivity.
- Required the public replication entry point to reproduce the simulation
  summaries from recorded seeds within manifest-defined tolerances.

### Parent qualification

The official article record does support the physics-informed neural-network
paper's trained-once description. That observation remains contextual and is
not used to justify PAGe's independently frozen once-per-season cadence. Claims
about a four-figure/three-table norm and operational Discussion ordering were
relabeled as manuscript design judgments because the scan did not measure them
across the full article set. The scan also now states that no dedicated software
or package article was represented.

### Post-review artifact identities

- **Article-scan SHA-256:**
  `b89339f3e4f7b9088eb64ac4437358512c6bac860e405d95b298716611617667`
- **Manuscript-skeleton SHA-256:**
  `2423072c1bd203886a0ec914d7ce27e41951ef223d347c54d3a33b6b3af47c0e`
- **Frozen analysis protocol v1.1 SHA-256 (semantically unchanged;
  formatting-normalized):**
  `04ce726af5dbc603c9568373101f789000a482708f8d4878040632af80a1b6ee`
