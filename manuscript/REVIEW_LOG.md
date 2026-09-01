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

The consolidated review is recorded in [`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md), with 26 retained sources in [`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md). The literature-synthesis checklist item is complete. Comparator selection is not yet frozen: the scientific lead must approve the core set and decide whether the empirical-Bayes or mechanistic comparator is feasible before the analysis protocol is versioned.
