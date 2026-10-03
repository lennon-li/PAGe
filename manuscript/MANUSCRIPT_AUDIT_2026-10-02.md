# PAGe Manuscript Workspace Audit - 2026-10-02

Auditor: Wei (research engineer / manuscript auditor)
Scope: `/home/yeli/repos/PAGe/manuscript/` and referenced package/artifact state
Package: `PAGe 0.3.0` on branch `dev/n-history` at commit `0baf0b9`
Target journal: *Epidemics*, article type **Methodological Manuscript**
Status: comprehensive audit; supersedes no prior record, adds no numerical claim

---

## Executive Summary

### What was done

A systematic audit of the core manuscript workspace was performed against the
current package (`PAGe 0.3.0`), the live `R CMD check` result, the canonical v3
shadow release, and the machine-readable artifacts under `artifacts/`,
`reports/`, and `docs/`. The seven required core files were read in full:

- `manuscript/SKELETON.md` (772 lines)
- `manuscript/METHODS.md` (585)
- `manuscript/RESULTS.md` (216)
- `manuscript/V3_IMPLEMENTATION_UPDATE_2026-09-28.md` (134)
- `manuscript/TODO.md` (263)
- `manuscript/REPORTING_TEMPLATES.md` (283)
- `manuscript/ANALYSIS_PROTOCOL.md` (349)

Placeholder gates, package-API references, `R CMD check` claims, data-sourcing
descriptions, the M0/M1/M2 architecture description, and every cited numeric
value were inventoried and cross-checked. This report is the deliverable; no
manuscript or package source was modified.

### Key findings

1. **Stale `R CMD check`/sandbox claims in 6 of 7 core files (highest
   priority, trivially fixable).** SKELETON, METHODS, RESULTS, TODO, PLAN, and
   V3_IMPLEMENTATION_UPDATE all state that a terminal full `R CMD check` is
   blocked/interrupted by the AgentPorter/R 4.6 sandbox. This is resolved:
   `PAGe.Rcheck/00check.log` (regenerated 2026-10-02 19:43) ends in
   `Status: 1 NOTE`, and commit `0baf0b9` is titled "resolve R CMD check errors,
   argument docs, and stale test hashes". The single NOTE is an
   `importFrom`/`utils` NAMESPACE note, not a sandbox failure.

2. **Numeric-claim traceability failure on the "authoritative" score-to-date
   values (blocking).** METHODS.md:75-77, RESULTS.md:69-74, and
   V3_IMPLEMENTATION_UPDATE:52-53 cite `A+1 0.4121391`, `A+2 0.6495239`,
   `B+1 0.02855612`, `B+2 0.04773192` as "current machine-readable CSV" values.
   No artifact in the repository contains these numbers. The only score-to-date
   CSV, `artifacts/v3-week8-11-walkforward-report-v1/m2_score_to_date_week8_11.csv`,
   and the independent `docs/v3-end-to-end-api-audit-2026-09-28.md:207-212`
   both report `A+1 0.4122`, `A+2 0.5535`, `B+1 0.0285`, `B+2 0.0481`. The A+2
   value differs by ~0.096 pp (~17% relative). The manuscript's claim that its
   values "supersede stale prose in the older end-to-end audit" is inverted:
   the older audit agrees with the CSV, the manuscript does not.

3. **Manuscript package/API section is written against superseded internal
   functions.** `page_v3_forecast()` (SKELETON:44, METHODS:52,
   V3_IMPLEMENTATION_UPDATE:88) and `page_train_workflow()`
   (SKELETON:41, METHODS:50, V3_IMPLEMENTATION_UPDATE:86) are **not exported**
   in `PAGe/NAMESPACE`; only their S3 `print` methods are registered. The
   0.3.0 public surface is `page_forecast()`, `page_train()`,
   `page_walkforward_report()`, `page_render_report()`,
   `page_load_surveillance()`, `aggregate_strata()`, `plot_forecast()`, etc.
   `train_pipeline()` is likewise internal. None of the new public functions
   are named in the manuscript.

4. **Data-sourcing and reporting narrative is stale.** Every core file describes
   only weekly final-data retrospective replay and an operational IRVRI legacy
   daily GAM comparator. There is **no mention** of the live zero-config PHO/ORVT
   network fetch (`getCurrentD(data = NULL)`), automated prospective intake of
   daily `.RData` snapshots, or the weekly Quarto/HTML walk-forward report
   pipeline (`reports/page_walkforward_2026-27_week12.qmd`/`.html`), all of
   which exist in the current package/workflow.

5. **M0/M1/M2 architecture is internally consistent in the controlling v3
   blocks but contradicted by un-quarantined prior-cycle prose.** The v3 header
   blocks (SKELETON:14-38, PLAN:5-33, METHODS:5-83, RESULTS:5-104,
   V3_IMPLEMENTATION_UPDATE) are mutually consistent: M0-A `raw-3`/one-SE drop
   at `w_min=12`; M1-A frozen v2; M2-A exact A1 state-only with posterior-C2
   gain ~4.04% below its 5% threshold; B window 12-40 with 2018-19 no-event and
   2019-20 excluded; M1-B v10 continuous peak-location posterior; M2-B v5
   routes +1 to B1 and +2 to posterior-C2 only with causal timing, else B1.
   However SKELETON §3.1 still specifies a "five signals / `N_req` of five
   gates / `timing_mode = "fractional"` / symmetric-absolute-error" M0, and
   METHODS §M0/§M1 still describe the five-signal detector and shift/dilation
   template alignment. Both are only partially flagged as prior cycle.

6. **Placeholder inventory: 94 gate markers in SKELETON.md**, plus 3 pending
   markers in PLAN.md and draft markers in `manuscript/drafts/`. Detail in
   Section 4. The Results-bearing gates dominate and remain blocked on
   comparator/simulation/prospective evidence; a substantial subset
   (DRAFT, package/artifact, Week 12) is immediately actionable.

7. **One positive confirmation.** The bounded legacy/v2 and v3 numeric
   comparisons in RESULTS.md/METHODS.md/V3_IMPLEMENTATION_UPDATE all match their
   cited artifacts and the independent `docs/v3-end-to-end-api-audit` (M1 MAE
   1.375 vs 1.093 weeks; M2-A 8.4087/1.7757/1.5435 and 9.2056/2.4124/2.1531;
   M1-B 1.6573/1.6580/0.80; M2-B 0.514552/0.436010/15.26%/24.91%/
   1.172716->0.763391; weekF12 support A+1 0.246866, A+2 0.327263, B+1
   0.154921, B+2 0.154897).

### Prioritized roadmap to submission

**P0 - correctness and consistency (days, in-repo):**
1. Replace all six stale `R CMD check`/sandbox claims with the verified
   `Status: 1 NOTE` result and the `PAGe.Rcheck/00check.log` + commit hash.
2. Resolve the score-to-date numeric mismatch: regenerate the authoritative
   CSV from the current v3 runtime, then repoint/fix METHODS:75-77,
   RESULTS:69-74, V3_IMPLEMENTATION_UPDATE:52-53 (expected A+2 ~0.5535, not
   0.6495).
3. Rewrite the package subsection to the 0.3.0 public API; retire
   `page_v3_forecast()`/`page_train_workflow()`/`train_pipeline()` as
   user-facing.
4. Update data sourcing/reporting to describe live PHO/ORVT fetch, prospective
   daily snapshot intake, and the walk-forward Quarto/HTML report.

**P1 - evidence to populate co-primary results (weeks):**
5. Reconcile SKELETON §3-§4 and METHODS prior-cycle prose with the v3
   architecture (or formally quarantine it).
6. Run and preserve the legacy-GAM and calendar-week-GAM paired comparisons on
   common rows, plus WIS/50%/95% coverage, to unblock Tables 3/4 and Figures 3/4.
7. Assemble the canonical prediction table and manifest for one analysis ID.

**P2 - external/governance (weeks-months):**
8. Obtain REB/ethics determination and data-custodian publication authorization.
9. Capture and score the first observed 2026-27 weekF12+ shadow transaction.
10. Complete the prespecified simulation suite.

**P3 - assembly (weeks):**
11. Build modular Quarto manuscript, `.bib`, figure/table generation, EPIFORGE
    2020 checklist, and journal recheck.
12. Finalize title/keywords, authors/CRediT, funding, competing interests.

---

## 1. Audit Method and Provenance

Evidence sources:

| Source | What it establishes |
|---|---|
| `PAGe.Rcheck/00check.log` | Current check result, `Status: 1 NOTE` (2026-10-02 19:43) |
| `git log` (`0baf0b9`) | Check-fix commit on `dev/n-history` |
| `PAGe/DESCRIPTION` | Version `0.3.0` |
| `PAGe/NAMESPACE` | Authoritative exported public API |
| `PAGe/R/public_api.R`, `training_workflow.R`, `v3_runtime.R`, `getCurrentD.R` | Definition/export status of named functions |
| `artifacts/v3-week8-11-walkforward-report-v1/m2_score_to_date_week8_11.csv` | Only score-to-date CSV |
| `docs/v3-end-to-end-api-audit-2026-09-28.md:207-212` | Independent score-to-date statement |
| `reports/page_walkforward_2026-27_week12.qmd/.html` | Week 12 report |
| `artifacts/current-week-input/week12/` | Week 12 runtime inputs/intervals |
| `docs/v3-current-canonical-stack-2026-09-28.md` | Canonical v3 component identities |
| `artifacts/orvt-week12-readiness-2026-10-01/readiness_summary.md` | Week 12 readiness, live-source plan |
| `manuscript/*.md` | The audited documents |

The audit distinguishes four claim classes: (a) verified current, (b) stale but
trivially correctable, (c) blocked on evidence not yet generated, and
(d) governance/external pending.

---

## 2. Document-by-Document Findings

### 2.1 `SKELETON.md`

Role: controlling authoring guide and section/word-budget map. Its v3 header
block (lines 7-54) is current and authoritative.

| Location | Finding | Class |
|---|---|---|
| 41-44 | Package subsection names `page_train_workflow()`, `train_pipeline()`, `page_v3_forecast()` - internal/non-exported. | Stale API |
| 44 | "terminal full `R CMD check` summary remains open ... AgentPorter/R 4.6 sandbox" - resolved. | Stale check |
| 16-38 | Current A/B routing and comparison-account table - consistent with v3. | Verified |
| 46-48 | "Methods draft and reporting schemas are finalized, while numerical Results remain blocked" - still true. | Verified |
| 67-75 | Marker legend for all six gates. | Reference |
| 127-143 | Co-primary claim placeholders (5x RESULT). | Blocked |
| 152-157 | Section-budget status: Sections 3-4 say "Rewrite from protocol v2.0 draft (METHODS.md is prior cycle)". | Known stale, flagged |
| 332-343 | §3.1 M0 "five signals ... `N_req` of the five gates", `timing_mode="fractional"`, symmetric-absolute-error loss - contradicts v3 raw-3/SE1 M0. Section itself is not marked PRIOR CYCLE. | Architecture conflict |
| 345-359 | §3.2 M1 shift/dilation `a,b,delta` template description - v2 template form, not the v3 B continuous peak-location posterior. | Architecture conflict |
| 361-372 | §3.3 M2 `offset_subset_v1` binomial GAM - v2 form; does not describe v3 A1 state-only vs B posterior-C2 routing. | Architecture conflict |
| 376-386 | §3.4 adoption gate `max(floor, qt(0.95,n-1)*SD/sqrt(n))` - v2.0 gate; distinct from the ~4.04%/5% posterior-C2 promotion threshold. The two are never disambiguated. | Clarity conflict |
| 597-626 | §6 real-time 2026-27 "final kit trained once on all 11 eligible seasons"; current canonical release is a frozen shadow release (`production_eligible=FALSE`) with no observed weekF12+ run. | Tension |
| 684-701 | Declarations: data/code availability, ethics, CRediT, competing, funding, EPIFORGE. | Mixed |

### 2.2 `METHODS.md`

Role: canonical manuscript-facing Methods prose. Its leading v3 block (5-83) is
current; the body is prior-cycle prose retained as historical evidence.

| Location | Finding | Class |
|---|---|---|
| 5-83 | Current v3 architecture, package surface, weekF12/support scores, score-to-date table. | Verified except score values |
| 21-28 | M0-A raw-3/SE1, M2-A state-only, posterior-C2 4.04% < 5%. | Verified |
| 33-44 | B window 12-40, M1-B v10, M2-B v5 tables. | Verified |
| 50-52 | `page_train_workflow()`, `train_pipeline()`, `page_v3_forecast()` internal. | Stale API |
| 60 | "terminal full `R CMD check` summary remains unresolved ... sandbox interrupts" - resolved. | Stale check |
| 75-77 | Score-to-date `A+2 0.6495239` etc. - not in any artifact (CSV says ~0.5535). | Numeric error |
| 201, 251, 295, 394, 407, 424, 437, 497 | Explicit "PRIOR CYCLE" / "SUPERSEDED" banners. | Correctly flagged |
| 205-220 | §M0 five-signal detector description (prior cycle). | Flagged stale |
| 222-249 | §M1 shift/dilation template alignment (prior cycle M1). | Flagged stale |
| 253-329 | §M2 GAM formula, online correction, post-peak handling. | Flagged stale; partially relevant |
| 331-475 | Seasonal cadence and three-level nested design. | Frozen-methods prose; usable |
| 477-570 | Comparators, ablations, outcomes, privacy. | Frozen-methods prose |
| 572-585 | Software/reproducibility; says manifest provenance incomplete. | Still true |

### 2.3 `RESULTS.md`

Role: results draft. Contains a current v3 evidence block (5-104) and a
prior-cycle replay block (106-216).

| Location | Finding | Class |
|---|---|---|
| 5-104 | Current v3 component comparisons, package evidence, 2026-27 diagnostic. | Verified |
| 67-74 | Score-to-date table: `A+2 0.6495239` - mismatches CSV (~0.5535). | Numeric error |
| 91 | "A terminal full `R CMD check` summary remains open because the current sandbox interrupts..." - resolved. Also cites a stale "28 test failures" historical check. | Stale check |
| 106-126 | Governed replay completeness: 11 complete, 0 pending; PAGe 0.2.0, commit `95c1c9f`; checksum. | Prior cycle, flagged |
| 128-175 | 11-season replay table (mean NLL 0.338, MAE 0.0325; 10-season 0.315/0.0292; 2025-26 partial 17 rows). | Prior cycle, flagged |
| 177-198 | Ignition/horizon errors, restricted paired diagnostics. | Prior cycle, flagged |
| 200-206 | Computational behavior (3.3-3.8 h/kit). | Prior cycle, flagged |
| 208-216 | "Results still required before submission" - accurate gap list. | Verified |

### 2.4 `V3_IMPLEMENTATION_UPDATE_2026-09-28.md`

Role: dated v3 evidence ledger. Dated 2026-09-29 in the body despite the
filename date; internally current.

| Location | Finding | Class |
|---|---|---|
| 7-43 | Canonical release/components; matches `docs/v3-current-canonical-stack`. | Verified |
| 45-57 | WeekF12 support replay + 2026-27 diagnostic. | Verified |
| 52-53 | Score-to-date values mismatch CSV. | Numeric error |
| 59-77 | Bounded legacy/v2 comparisons - match artifacts. | Verified |
| 79-121 | Package/API status, probability layer. | Verified except API naming |
| 86-88 | `page_train_workflow()`, `page_v3_forecast()` internal. | Stale API |
| 91-94 | "A terminal full `R CMD check` summary remains incomplete in this sandbox" - resolved. | Stale check |
| 123-134 | Five remaining manuscript gates; gate 1 is now satisfied. | Partial |

### 2.5 `TODO.md`

Role: execution checklist. Active v3 gates (5-33) plus a large archived
prior-cycle RSV checklist (35-263) explicitly marked superseded.

| Location | Finding | Class |
|---|---|---|
| 18, 20 | `[x]` tarball install + suites; `[x]` vignettes. | Done |
| 19 | `[ ]` "Obtain a terminal full `R CMD check` ... sandbox interrupts" - now satisfiable. | Actionable |
| 21-22 | `[ ]` reconcile results; authoritative CSV values. | Blocked by numeric fix |
| 23-25 | `[ ]` first observed weekF12+ shadow run; score later. | External/future |
| 26-29 | `[ ]` pin versions; ethics/REB + custodian authorization. | External |
| 35-263 | RSV/multi-pathogen archived checklist - explicitly not active. | Historical |

**Risk:** the RSV checklist is ~228 lines of unchecked `[ ]` items at the end of
the file. Although a header says it is superseded, an inattentive reader or a
tool that counts unchecked boxes could misread it as active work. Recommend
moving it to `drafts/` or collapsing it into an explicit archive note.

### 2.6 `REPORTING_TEMPLATES.md`

Role: canonical table/figure/manifest schemas. Marked "not frozen"
(line 1, dated 2026-09-15).

| Location | Finding | Class |
|---|---|---|
| 1 | Status "updated for protocol v2.0 draft - not frozen". | Should be re-dated |
| 5 | "Last updated: 2026-09-15". | Stale timestamp |
| 79 | Table 2 lists "IRVRI legacy daily GAM ... Daily by-age positives and tests". Meanwhile `docs` and the live pipeline describe weekly PHG/ORVT data usage; confirm the legacy comparator's true resolution before shipping the "daily" label. | Verify |
| 74-83 | Model registry uses `{{...}}` placeholders. | Blocked |
| 96-213 | Tables 4-10 are result templates. | Blocked |
| 229-237 | Figure specs reference Figure 5 (simulation) although main text caps at 4 figures; Figure 5 is simulation/supplement. Clarify. | Minor |
| 239-261 | Canonical prediction-table schema - good, matches protocol §8. | Verified |
| 263-283 | Final quality gate checklist. | Reference |

### 2.7 `ANALYSIS_PROTOCOL.md`

Role: frozen protocol v1.4, prior cycle. Header explicitly says it is to be
superseded by `drafts/ANALYSIS_PROTOCOL_v2.0-draft.md`.

| Location | Finding | Class |
|---|---|---|
| 1 | "FROZEN v1.4, PRIOR CYCLE". | Correctly flagged |
| 42-71 | Primary estimand h2 trial-weighted binomial NLL, equal-season. | Prior cycle |
| 110-187 | Outer/inner replay, one-training-run cadence. | Prior cycle |
| 189-234 | Seven-comparator set. | Prior cycle |
| 236-255 | Four structural ablations + label sensitivities. | Prior cycle |
| 295-317 | Ontario RSV data gate - superseded (`PLAN` scope is influenza-only). | Superseded |
| 344-349 | Amendment 1.1. | Historical |

**Risk:** v1.4 and the v2.0 draft define different primary analyses (h2
trial-weighted NLL + one-SE selection vs phase-weighted Bernoulli CE + gates).
The manuscript still points to both. Until v2.0 is frozen and promoted, the
manuscript's "frozen protocol" status is ambiguous.

### 2.8 Other files (context, not in the required set)

- `PLAN.md:30` repeats the stale check gate; `PLAN.md:465,467,584` carry three
  `[PENDING]` items (Zenodo DOI, R Journal paper).
- `PUBLICATION_AUDIT_2026-09-07.md:45` references "local sockets ... sandbox
  restriction" (2026-09-07; now obsolete context).
- `README.md` is current and correctly states code may call the public API while
  reproductions may use internals.
- `drafts/ANALYSIS_PROTOCOL_v2.0-draft.md` carries active `[FREEZE: ...]`
  markers (e.g. scoring weights not yet wired, line 98; adoption-gate h1 floor,
  line 100). These must be resolved before the v2.0 protocol can be called
  frozen.
- `drafts/` contains 15 `[PENDING]` markers across three draft files.

---

## 3. Stale-Claim Reconciliation

### 3.1 `R CMD check` / sandbox claims

| File:line | Current claim | Reality (2026-10-02) |
|---|---|---|
| SKELETON.md:44 | check summary open; sandbox terminates calls | Resolved: `Status: 1 NOTE` |
| METHODS.md:60 | check unresolved; sandbox interrupts | Resolved |
| RESULTS.md:91 | check open; sandbox interrupts; cites 28 test failures | Resolved; test suite green |
| TODO.md:19 | obtain terminal check; sandbox interrupts | Actionable, now satisfied |
| V3_IMPLEMENTATION_UPDATE:94 | check incomplete in sandbox | Resolved |
| PLAN.md:30 | obtain terminal check | Resolved |

Evidence: `PAGe.Rcheck/00check.log` (mtime 2026-10-02 19:43) concludes
`Status: 1 NOTE`; the NOTE is a NAMESPACE hint to add
`importFrom("stats","ave")`, `importFrom("utils","combn","head")`. Commit
`0baf0b9` is the explicit check-fix commit. Note that an older
`artifacts/v3-probability-api-audit-2026-09-29/00check.log` shows
`3 WARNINGs, 2 NOTEs` (vignette/`inst/doc` warnings) from a pre-fix state; it
must not be used as the current result.

Recommendation: replace the stale sentence in all six locations with a short
verified statement, e.g. "`R CMD check --no-manual` passes with 0 ERRORs,
0 WARNINGs, and 1 NOTE (NAMESPACE `importFrom` hint) at commit `0baf0b9`
(`PAGe.Rcheck/00check.log`)."

### 3.2 Deprecated / internal API references

Authoritative exported API (`PAGe/NAMESPACE`): `page_forecast`,
`page_forecast_now`, `page_train`, `page_walkforward_report`,
`page_walkforward_qmd`, `page_render_report`, `page_load_surveillance`,
`page_label_ignitions`, `page_save_kit`, `page_load_kit`, `page_validate_kit`,
`page_models`, `page_season_calendar`, `aggregate_strata`,
`aggregate_strata_draws`, `plot_forecast`, `prepare_surveillance_data`,
`validate_surveillance_data`, `validate_season_selection`,
`season_selection`, `replay_holdout`, `check_promotion`,
`verify_promotion`, `evaluate_forecasts`, `m0_detect`, `m0_fit`, `m1_fit`,
`m1_predict`, `m1_passive_posterior`-family, `m2_fit`, `m2_predict`,
`shared_denominator_correlation`.

| Referenced in manuscript | Definition | Exported? | Correct 0.3.0 replacement |
|---|---|---|---|
| `page_v3_forecast()` (SKELETON:44, METHODS:52, V3_UPDATE:88) | `PAGe/R/v3_runtime.R:671` | No (only `print.page_v3_forecast`) | `page_forecast()` / `page_forecast_now()` |
| `page_train_workflow()` (SKELETON:41, METHODS:50, V3_UPDATE:86) | `PAGe/R/training_workflow.R:196` | No (only `print.page_training_workflow`) | `page_train()` |
| `train_pipeline()` (SKELETON:42,383; METHODS:51) | internal | No | governed internal contract; describe as implementation detail |
| `page_save_kit()` / `page_load_kit()` | `training_workflow.R:289/307` | Yes | keep |
| `page_label_ignitions()` | `training_workflow.R:31` | Yes | keep |

`getCurrentD()` (`PAGe/R/getCurrentD.R`) is also not exported, yet the task
brief describes it as a live zero-config entry point. Either export/document it
as public or describe the live fetch through `page_load_surveillance()` /
`page_forecast_now()` in the manuscript. The manuscript presently names none of
these.

Recommendation: rewrite the package subsection around
`page_train() -> page_forecast() -> page_walkforward_report()/page_render_report()`
with `page_load_surveillance()` for sourcing, and relegate
`page_v3_forecast()`/`train_pipeline()` to Appendix H as internals used by the
frozen historical release.

### 3.3 Data-sourcing and reporting staleness

Current capabilities not reflected in any core manuscript file:

- Live zero-config network fetch of PHO ORVT testing data via
  `getCurrentD(data = NULL, season = "2026-27")`, resolving
  `.../ORVT_Lab_Testing_Data_2025-26_2026-27.csv`
  (`artifacts/orvt-week12-readiness-2026-10-01/readiness_summary.md:11`).
- Automated prospective ingestion of daily/`.RData` snapshots and A/B typed
  panel construction.
- Weekly walk-forward Quarto/HTML reports with per-origin tabsets
  (`reports/page_walkforward_2026-27_week10.*`, `_week12.*`); Week 12 shows the
  latest origin and M0/M1/M2 outputs.
- ORVT official-schema end-to-end rehearsal PASS (manual panel vs ORVT-derived
  panel zero delta; A+1 3.51705%, A+2 3.49768%, B+1 0.03786%, B+2 0.03938%;
  routes A exact state, B+1 exact state, B+2 exact fallback)
  (`readiness_summary.md:32-49`).

MANUSCRIPT-FACING GAP: METHODS/RESULTS still frame all evidence as
"final-data retrospective replay with no origin-time vintages" and do not
mention the live fetch or the report pipeline. The Data and forecasting targets
section (SKELETON §2) must add the live/prospective sourcing description. This
directly supports *Epidemics*' "operational evidence separated from retrospective
evidence" requirement (EPIDEMICS_ARTICLE_SCAN:55-57).

Minor caveat to record: the live PHO fetch cannot be verified from the
sandboxed execution host (outbound DNS unavailable), so the Friday live check is
still an external verification (`readiness_summary.md:14,74-82`). The system
site library still has PAGe 0.2.0 (`readiness_summary.md:72`).

---

## 4. Placeholder and Evidence-Gate Inventory

### 4.1 Counts

`SKELETON.md` (the only core file carrying gate markers):

| Gate | Count | Nature |
|---|---:|---|
| `[DRAFT REQUIRED]` | 25 | Prose writable from frozen methods/verified sources |
| `[RESULT REQUIRED]` | 29 | Needs canonical immutable result set |
| `[CITATION REQUIRED]` | 5 | Needs verified sources |
| `[ARTIFACT REQUIRED]` | 19 | Needs linked table/figure/kit/manifest |
| `[DECISION REQUIRED]` | 7 | Scientific/governance choice |
| `[DATA REQUIRED]` | 2 | Supplied data/audit pending |
| `[NOT APPLICABLE]` | 1 | Remove if gate fails |
| `[PENDING]` | 2 | Data availability, ethics |
| `[REQUIRED]` | 4 | CRediT, competing, funding, acknowledgements |
| **Total** | **94** | |

Other files: `PLAN.md` 3x `[PENDING]`; `drafts/execution-record-2025-26-draft.md`
4x, `drafts/fractional-timing-deviation-draft.md` 5x,
`drafts/simulation-design-draft.md` 3x; `drafts/ANALYSIS_PROTOCOL_v2.0-draft.md`
carries `[FREEZE: ...]` markers (not counted as gates above).

### 4.2 Categorization and immediate-actionability

**A. Populate immediately from existing package/artifact/code:**

- Package workflow and reproducibility prose (SKELETON §4.8; the `[DRAFT]`
  package sentence at 41-44 once re-API'd) - the frozen-cadence, kit-identity,
  and vignette facts are available.
- Figure 1 workflow (SKELETON:707, "Design-ready").
- Figure 2 representative season: inputs exist in
  `artifacts/current-week-input/week12/forecast_intervals_week8_12_exact_vintage.csv`
  and the walk-forward report.
- Table 1 data/seasons/exclusions (SKELETON:711): derivable from
  `ONTARIO_FLU_SEASON_DECLARATION.md` and the Week 12 typed panel.
- Table 2 models/information sets (SKELETON:712): derivable from
  `docs/v3-current-canonical-stack-2026-09-28.md` and
  `reports/page_walkforward_2026-27_week12.qmd`.
- Week 12 and diagnostic score reporting (once the numeric mismatch is fixed).
- Title candidate, keywords shortlist, AI-use disclosure draft.

**B. Blocked on results not yet generated (in-repo work):**

- Co-primary block 1 (legacy GAM chronological contrast) - needs the deployed
  legacy comparator replay on common rows.
- Co-primary block 2 (11-fold exchangeable paired contrasts) - needs calendar
  GAM, mvgam `mod2AR`, persistence, seasonal naive on identical rows.
- WIS and 50%/95% coverage by phase/horizon.
- M0/M1 stage-level result tables (Tables S4-S5).
- Ablations, label sensitivities, simulations.
- Figures 3-4 and Table 3.

**C. Pending prospective/external events:**

- `[DATA REQUIRED]` (§6.2 real-time results): the first observed 2026-27
  weekF12+ transaction and its scored targets; no observed weekF12+ result
  exists yet.
- Live PHO Friday fetch verification.

**D. Governance/administrative (author/custodian/institution):**

- Ethics/REB determination (`[DECISION]`/`[PENDING]`, SKELETON:692).
- Data-custodian publication authorization and disclosure limits (SKELETON:301,
  689; TODO:99).
- Author list, affiliations, CRediT, funding, competing interests
  (SKELETON:173, 695-698).
- Journal-format recheck immediately before submission (SKELETON:180).
- Zenodo/archive DOI (PLAN:465,584) and the separate R Journal paper (PLAN:467).

---

## 5. Results and Artifact Cross-Check

### 5.1 Bounded legacy/v2/v3 comparisons - VERIFIED

| Claim (manuscript) | Value | Independent source | Match |
|---|---|:--:|:--:|
| M1 timing MAE legacy vs v2 | 1.375 vs 1.093 wk; 81 rows / 10 seasons | `docs/v3-end-to-end-api-audit:224-228`; `artifacts/m1-v2-lowrank-posterior-v10-release-consistent/common_ledger_vs_legacy_v16_strict_future_release.csv` | Yes |
| M2-A +1 | 8.4087 vs 1.7757 (state/growth) / 1.5435 (fixed C2) | `docs/v3-end-to-end-api-audit:241`; `docs/m2-v2-legacy-matched-a-benchmark-2026-09-25.md` | Yes |
| M2-A +2 | 9.2056 vs 2.4124 / 2.1531 | `docs/v3-end-to-end-api-audit:242` | Yes |
| M0 | Not established either side | `docs/v3-end-to-end-api-audit:250-252` | Yes |
| M1-B v10 peak-location MAE | ~1.6573 wk; early-weighted 1.6580; 90% cov 0.80 | V3 ledger; `artifacts/m1-b-v3-peak-v10/` | Consistent |
| M2-B v5 +2 | B1 0.514552 vs C2 0.436010 (15.26%); timing-active 24.91%; worst 1.172716->0.763391 | V3 ledger; `docs/v3-m2-b-final-disposition-2026-09-26.md` | Consistent |
| WeekF12 support replay | A+1 0.246866 (8), A+2 0.327263 (8), B+1 0.154921 (7), B+2 0.154897 (7) | V3 ledger; `docs/v3-week12-lower-bound-migration-2026-09-28.md` | Consistent |

### 5.2 Score-to-date - MISMATCH (blocking)

Manuscript (`METHODS.md:75-77`, `RESULTS.md:69-74`,
`V3_IMPLEMENTATION_UPDATE:52-53`):

| Target | Manuscript value | `m2_score_to_date_week8_11.csv` | `docs/v3-end-to-end-api-audit:207-212` | Delta |
|---|---:|---:|---:|---:|
| A +1 | 0.4121391 | 0.4121899 | ~0.4122 | +0.00005 |
| A +2 | 0.6495239 | 0.5535410 | ~0.5535 | **+0.0960** |
| B +1 | 0.02855612 | 0.0284583 | ~0.0285 | +0.00010 |
| B +2 | 0.04773192 | 0.0481438 | ~0.0481 | -0.00041 |

The CSV is the only machine-readable score-to-date file found; a repo-wide
search for the manuscript's four strings finds them **only in the manuscript
files**. The manuscript's statements that these values "supersede stale
A+2/B+2 prose in an older end-to-end audit" (METHODS:78, RESULTS:77,
V3_UPDATE:53-54) are therefore reversed. This violates the project's own
traceability rule (`REPORTING_TEMPLATES.md:15`, `SKELETON.md:768-772`) and must
be corrected before submission. If a later authoritative CSV exists, it must be
preserved in-repo and cited; otherwise the manuscript numbers are unsupported.

### 5.3 Week 12 current numbers (report-level, verified)

From `reports/page_walkforward_2026-27_week12.qmd:19-25` (source
`artifacts/current-week-input/week12/`):

- Season 2026-27; latest observed origin **Week 12** (week ending 26 Sep 2026).
- Influenza A positivity 2.956% (212 / 7,172); Influenza B 0.028% (2 / 7,089).
- M0 ignition detected at Week 12.
- M1 timing peak Week 20.21 (90% interval 17.08-23.28).
- M2 outlook: A +1 3.517% (W13), A +2 3.497% (W14); B +1 0.038%, B +2 0.039%.
  This matches the ORVT rehearsal values (`readiness_summary.md:42-45`).
- Weeks 8-11 are as-of tabs and pre-issuance (M2 not issued before Week 12).

Note: the Week 12 `.qmd`/`.html` contains **no score-to-date table**; score
reporting remains the Week 8-11 diagnostic CSV. The manuscript's "Week 12"
score-to-date is therefore not published in the report and, as shown in §5.2,
does not trace to any artifact.

### 5.4 Prior-cycle replay (historical, retained unchanged)

`RESULTS.md:144-173` reports mean seasonal NLL 0.338 (range 0.173-0.564), mean
MAE 0.0325 (range 0.0193-0.0656); 10 full seasons mean NLL 0.315 / MAE 0.0292;
partial 2025-26 17 rows NLL 0.563552 / MAE 0.065553. These are explicitly
labelled prior cycle (`RESULTS.md:1,106-159`), tied to PAGe 0.2.0 and commit
`95c1c9f`, and must never be pooled with v3 results. No independent
recomputation was attempted in this audit; the internal arithmetic is coherent.

### 5.5 Artifact footprint observations

- No file named `canonical_prediction_table` exists; the manuscript still lacks
  the single canonical table required by `ANALYSIS_PROTOCOL.md:319-327` and
  `REPORTING_TEMPLATES.md:239-261`.
- `manuscript/results/` holds only `publication-repair-20260908` and
  `publication-repair-20260910` trees; no immutable manuscript final-results
  directory under one analysis ID exists yet.
- The canonical v3 release `5472d089...a853b` is shadow-only
  (`production_eligible=FALSE`); the Week 12 run used the release-compatible
  runtime `artifacts/orvt-week12-readiness-2026-10-01/release-runtime-5472-v1/`.

---

## 6. M0 / M1 / M2 Architecture Alignment

### 6.1 Consistent current architecture (controlling blocks)

| Stage | A route | B route |
|---|---|---|
| M0 | frozen `m0-v2-wmin12-raw3-se1-decimal-loso-v1`, `w_min=12`, raw-3 with one-SE drop tolerance | B-specific activity/timing window 12-40; 2018-19 no-event; 2019-20 excluded from B timing |
| M1 | frozen M1-A v2 timing | M1-B v10 continuous peak-location posterior |
| M2 | exact A1 state-only at +1/+2; posterior-C2 gain ~4.04% below 5% threshold | +1 exact B1; +2 posterior-C2 only when causal timing available, else exact B1 fallback |

Sources agree: SKELETON:14-38, PLAN:5-33, METHODS:5-83 (esp. 21-44),
RESULTS:5-104 (esp. 37-61), V3_IMPLEMENTATION_UPDATE:7-43,
`docs/v3-current-canonical-stack-2026-09-28.md`. The only numeric risk is the
score-to-date table (§5.2); the architecture narrative itself is aligned.

### 6.2 Conflicting / stale architecture prose

1. **SKELETON §3.1 (332-343)** prescribes an M0 with "five signals ... at least
   `N_req` of the five gates", `timing_mode="fractional"`, and a
   symmetric-absolute-error loss with late penalty. The v3 M0-A is the raw-3/SE1
   detector. The section is assigned "Rewrite from protocol v2.0 draft", but it
   is not individually marked PRIOR CYCLE and directly contradicts the header
   block.
2. **SKELETON §3.2/§3.3 (345-372)** describe the v2 template-alignment M1 and
   the `offset_subset_v1` M2 without the A1-state-only vs B posterior-C2
   routing or the causal-timing fallback.
3. **METHODS §M0 (205-220)** and **§M1 (222-249)** carry the prior-cycle
   five-signal detector and shift/dilation template alignment. These are
   correctly banner-flagged (201, 251) but remain in the canonical Methods file
   and will be mistaken for current prose if the banners are stripped during
   assembly.
4. **Adoption-gate terminology collision.** SKELETON:376-386 / v2.0 draft
   define an M2-vs-M1 adoption gate `mean gain >= max(floor, qt(0.95,n-1)*SD/
   sqrt(n))`. Separately, M2-A posterior-C2 uses a **5% promotion threshold**
   (METHODS:27-28, RESULTS:42, V3_UPDATE:26). The manuscript never explicitly
   distinguishes "adoption gate" from "posterior-C2 promotion threshold", which
   invites reader error.
5. **Real-time section tension.** SKELETON §6 asserts a final kit trained on all
   11 seasons applied to 2026-27; the current operational reality is a frozen
   shadow release `production_eligible=FALSE` with no observed weekF12+ run yet
   (V3_UPDATE:11,45-57; TODO:23-25). The plan is legitimate but must be written
   as plan-not-result.
6. **Prior-cycle vs new-cycle protocol coexistence.** `ANALYSIS_PROTOCOL.md`
   (v1.4) and `drafts/ANALYSIS_PROTOCOL_v2.0-draft.md` are both cited as
   authority. The v2.0 draft still has unresolved `[FREEZE: ...]` items
   (scoring-weights wiring, adoption-gate h1 floor). Until v2.0 is frozen, the
   manuscript cannot claim a single frozen protocol for the current results.

---

## 7. Assembly Plan for *Epidemics*

### 7.1 Journal requirements (from `EPIDEMICS_ARTICLE_SCAN.md` and scope)

- Article type: **Methodological Manuscript**, requiring a clear
  biological/public-health application with novel insight (SKELETON:50-54).
- Method-forward structures are normal; the information boundary belongs in
  Methods; hybrid components must be decomposed before evaluation; Results
  should be organized by scientific targets (horizon, phase, peak, prospective
  status); comparators and uncertainty are central; operational and
  retrospective evidence must be separated; reproducibility must be visible
  (scan items 1-9).
- Reporting: EPIFORGE 2020 19-item checklist as an appendix
  (SKELETON:699-701); AI-use, CRediT, competing-interest, funding, data/code,
  and ethics declarations.
- Target: ~6,500 words main text, <=250-word unstructured abstract, four
  figures, three tables (SKELETON:145-161, 703-717).
- Fallback journal: *Infectious Disease Modelling* (SKELETON:52). Recheck the
  live guide immediately before formatting.

### 7.2 Proposed modular Quarto structure

Create a renderable manuscript project rather than a monolithic file:

```
manuscript/
  _quarto.yml                  # project, pdf+docx, elsevier csl, bibliography
  references.bib               # from LITERATURE_MATRIX.md / LITERATURE_REVIEW.md
  manuscript.qmd               # master: front matter, includes, abstract
  sections/
    01-introduction.qmd
    02-data-and-targets.qmd
    03-methods.qmd             # M0/M1/M2 + adoption gate + cadence
    04-validation.qmd
    05-results.qmd
    06-real-time-2026-27.qmd
    07-discussion.qmd
    08-conclusion.qmd
    declarations.qmd
  figures/                     # generated PDFs/PNGs, committed by checksum
  tables/                      # generated TeX/CSV from canonical table
  supplements/
    appendix-a-notation.qmd ... appendix-i-epiforge.qmd
```

Master file uses Quarto includes:

```markdown
{{< include sections/01-introduction.qmd >}}
```

Key conventions:

- `format: pdf` (preprint/Elsevier) and `format: docx` for journal submission;
  `csl: elsevier-harvard.csl`; `number-sections: true`; `fig-cap`/`tbl-cap`.
- No body-level `#` h1 (repo Quarto convention; use the title YAML).
- Every numeric value in Results is a Quarto inline R expression bound to the
  canonical prediction table, so tables/figures/text cannot drift (directly
  prevents the §5.2 mismatch class).
- Build figures with knitr/R from `manuscript/scripts/` or the package
  `plot_forecast()`/`page_render_report()` output; store figure-input CSVs
  under `manuscript/results/<analysis-id>/`.
- Keep the four-figure/three-table main text; move Figures 5+ and Tables S1-S8
  to `supplements/`.

### 7.3 Section mapping and word budget

| Quarto section | Skeleton source | Budget | Current readiness |
|---|---|---:|---|
| Abstract | SKELETON:190-205 | 250 | Blocked by results |
| 1 Introduction | SKELETON:219-270 | 750 | Ready after citations |
| 2 Data and targets | SKELETON:272-323 | 500 | Needs live-sourcing update + decisions |
| 3 Methods | SKELETON:325-407 | 1,700 | Rewrite to v3; un-quarantine conflicts |
| 4 Validation/evaluation | SKELETON:409-533 | 800 | Rewrite to v2.0 frozen protocol |
| 5 Results | SKELETON:535-595 | 1,300 | Blocked by comparator evidence |
| 6 Real-time 2026-27 | SKELETON:597-626 | 500 | Blocked by first weekF12+ run |
| 7 Discussion | SKELETON:628-669 | 700 | Blocked by results |
| 8 Conclusion | SKELETON:671-682 | 100 | Blocked by results |

Bibliography: convert `LITERATURE_MATRIX.md` entries (the scan already verified
eight DOIs) into `references.bib`; add the EPIFORGE 2020 record
(`10.1371/journal.pmed.1003793`).

### 7.4 Assembly risks to control

- Do not let inline numbers be typed; bind all to the canonical table.
- Resolve the v2.0 protocol `[FREEZE]` items before calling the design frozen.
- Keep prior-cycle prose in `manuscript/history/` or clearly fenced, not inline
  with current methods.

---

## 8. Prioritized Roadmap to Submission

| # | Priority | Action | Owner | Blocking? | Effort |
|---|---|---|---|---|---|
| 1 | P0 | Replace 6 stale `R CMD check`/sandbox claims with verified `Status: 1 NOTE` + commit/log path | Manuscript | Yes (credibility) | Hours |
| 2 | P0 | Regenerate authoritative score-to-date CSV; fix A+2 etc. in 3 files; preserve CSV in-repo | Analysis + Manuscript | Yes | Hours-days |
| 3 | P0 | Rewrite package subsection to 0.3.0 public API (`page_train`, `page_forecast`, `page_walkforward_report`, `page_render_report`, `page_load_surveillance`); demote internals | Manuscript | Yes | Day |
| 4 | P0 | Add live PHO/ORVT sourcing + walk-forward report description to Data section | Manuscript | Yes | Day |
| 5 | P1 | Quarantine/rewrite SKELETON §3-§4 and METHODS prior-cycle M0/M1 prose to v3 architecture | Manuscript | Yes | Days |
| 6 | P1 | Freeze and promote `ANALYSIS_PROTOCOL_v2.0-draft.md`; resolve all `[FREEZE]` markers; retire v1.4 authority | Methods lead | Yes | Days |
| 7 | P1 | Produce canonical prediction table + manifest under one analysis ID | Analysis | Yes | Days-weeks |
| 8 | P1 | Run legacy-GAM (chronological) and calendar-GAM/mvgam/persistence/seasonal-naive (11-fold) paired comparisons; WIS + 50%/95% coverage | Analysis | Yes | Weeks |
| 9 | P1 | Populate Tables 1-3, Figures 1-4 from canonical artifacts | Manuscript | Yes | Days after #7-8 |
| 10 | P2 | Obtain REB/ethics determination | Institution | Yes (submission) | Weeks-months |
| 11 | P2 | Obtain data-custodian publication authorization + disclosure limits | Custodian | Yes | Weeks |
| 12 | P2 | Capture/score first observed 2026-27 weekF12+ shadow transaction | Operations | Section 6 only | Season-timed |
| 13 | P2 | Run simulation suite (reference DGP + four stressors) | Analysis | Bounds claims | Weeks |
| 14 | P3 | Build modular Quarto manuscript, `.bib`, generated figures/tables; wire inline numbers | Manuscript | Yes | Week |
| 15 | P3 | Complete EPIFORGE 2020 checklist appendix; recheck live journal guide | Manuscript | Yes | Day |
| 16 | P3 | Finalize title/keywords, authors/CRediT, funding, competing interests, AI-use | Authors | Yes | Days |
| 17 | P3 | Archive code+aggregates with DOI; schedule separate R Journal paper | Authors | No (post-submission) | Weeks |

Critical path: #2 (numeric fix) and #7-#8 (comparator evidence) gate the entire
Results section and the two co-primary claims; #10-#11 gate submission.

---

## Appendix A. Evidence Reference Index

| Reference | Detail |
|---|---|
| `PAGe.Rcheck/00check.log` | `Status: 1 NOTE`; NAMESPACE `importFrom` hint; mtime 2026-10-02 19:43 |
| Commit `0baf0b9` | "fix(pkg): resolve R CMD check errors, argument docs, and stale test hashes" |
| `PAGe/DESCRIPTION` | `Version: 0.3.0` |
| `PAGe/NAMESPACE` | Exported public API (see §3.2) |
| `PAGe/R/v3_runtime.R:671` | `page_v3_forecast()` definition (not exported) |
| `PAGe/R/training_workflow.R:196,289,307,31` | `page_train_workflow()`, `page_save_kit()`, `page_load_kit()`, `page_label_ignitions()` |
| `PAGe/R/public_api.R:16,29,79,128` | `page_train()`, `page_forecast()`, `page_walkforward_report()`, `page_render_report()` |
| `PAGe/R/getCurrentD.R` | Live PHO ORVT resolver (not exported) |
| `artifacts/v3-week8-11-walkforward-report-v1/m2_score_to_date_week8_11.csv` | A+1 0.4121899; A+2 0.5535410; B+1 0.0284583; B+2 0.0481438 |
| `docs/v3-end-to-end-api-audit-2026-09-28.md:207-212` | A+1 ~0.4122; A+2 ~0.5535; B+1 ~0.0285; B+2 ~0.0481 |
| `reports/page_walkforward_2026-27_week12.qmd:19-25,116-134` | Week 12 numbers |
| `artifacts/current-week-input/week12/forecast_intervals_week8_12_exact_vintage.csv` | Week 8-12 interval inputs |
| `artifacts/orvt-week12-readiness-2026-10-01/readiness_summary.md` | ORVT live path; A/B forecasts; routes; site-library 0.2.0 caveat |
| `docs/v3-current-canonical-stack-2026-09-28.md` | Canonical v3 component identities |
| `docs/m2-v2-legacy-matched-a-benchmark-2026-09-25.md` | M2-A benchmark |
| `artifacts/m1-v2-lowrank-posterior-v10-release-consistent/common_ledger_vs_legacy_v16_strict_future_release.csv` | M1 timing ledger |
| `drafts/ANALYSIS_PROTOCOL_v2.0-draft.md:95-100` | Unresolved `[FREEZE]` items |

## Appendix B. Claim-Class Summary

| Class | Count | Examples |
|---|---:|---|
| Verified current | - | v3 architecture, bounded legacy/v2 comparisons, Week 12 report numbers |
| Stale but correctable | 6 check claims + ~6 API refs + sourcing narrative | `R CMD check`, `page_v3_forecast`, live fetch |
| Numeric error (blocking) | 1 table (4 values) | Score-to-date A+2 and others |
| Architecture conflict | 4 clusters | SKELETON §3, METHODS prior-cycle M0/M1, gate terminology, real-time tension |
| Blocked on evidence | 29 RESULT + 19 ARTIFACT gates | co-primary comparisons, WIS/coverage, stage tables, simulations |
| External/governance | 7 DECISION + 2 DATA + 2 PENDING + 4 REQUIRED | REB, custodian auth, authors, funding |

## Appendix C. Recommended Immediate Patch List

1. `SKELETON.md:41-44`, `METHODS.md:50-52,60`, `RESULTS.md:91`,
   `TODO.md:19`, `PLAN.md:30`, `V3_IMPLEMENTATION_UPDATE:86-94`:
   correct check claims and API names.
2. `METHODS.md:75-77`, `RESULTS.md:69-74`, `V3_IMPLEMENTATION_UPDATE:52-53`:
   correct score-to-date values against a regenerated canonical CSV.
3. `REPORTING_TEMPLATES.md:1,5`: re-date and re-state freeze status.
4. `MANUSCRIPT` package subsection + `SKELETON §2`: add live-PHO/ORVT sourcing
   and walk-forward report description.
5. `TODO.md:35-263`: relocate the archived RSV checklist to `drafts/` to prevent
   active-work misreading.
