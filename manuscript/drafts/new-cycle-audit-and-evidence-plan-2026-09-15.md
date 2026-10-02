# Manuscript audit and new-cycle evidence plan

Draft 2026-09-15 (ming-manuscript). Audit and plan only; no manuscript file was
rewritten. Status labels: **CUR** = current cycle (usable once production
confirms), **PRIOR** = prior cycle (commit `95c1c9f`, integer timing, truncated
2025-26, v16 incumbent, `min_nll`/0-12 weights), **SUP** = superseded by a
production decision (retain only as history), **GOV** = cycle-independent
governance that still binds. Every production number now in the manuscript is
PRIOR or pre-fix and must not be presented as final.

## 1. Inventory and claim classification

| File | Claim / section | Class | Note |
|---|---|---|---|
| RESULTS.md | whole file: 11-row table (NLL/MAE), means 0.338/0.315, h1/h2 MAE, ignition 15-23, runtimes 3.3-3.8 h, 2025-26 17 rows partial, commit `95c1c9f`, checksum `fa8add1b` | PRIOR | Becomes "prior-cycle record" appendix or is dropped; never pooled with new cycle |
| RESULTS.md | "results still required" list (comparators, ablations, labels, simulation) | GOV | Still true |
| HOLDOUT_EXECUTION.md | run registry r3/r4, BCC 2x7 cores, commit `95c1c9f` | PRIOR | Keep as dated execution record |
| REPLAY_ARTIFACT_AUDIT.md | pre-refresh archive rows (`d60d023`, v5/v2 runs), final reconciliation 11/0/0/0 | PRIOR | Keep as dated audit |
| ANALYSIS_DEVIATIONS_2026-09-08.md | executed M0 loss (zero loss for d in [-1,0], `miss_penalty=0`, lexicographic rank), M1 `mae_weibull` + 0.05 min-gain, M2 `min_nll` equal-row CE, conditional inner M2 tuning, 2025-26 partial, `19L` | PRIOR | Accurate for prior cycle. Conditional-upstream-tuning paragraph is **SUP** by leakage fix F1 |
| ANALYSIS_DEVIATIONS | frozen-protocol restatement (h2, 0-12, trial-weighted, one-SE) | GOV | Frozen v1.4 definitions; still the registered primary |
| ANALYSIS_PROTOCOL.md v1.4 | 11 seasons, exclusions, 7 comparators, 4 ablations, 3 label sensitivities, descriptive-only, RSV gate, one kit per season | GOV | Binds |
| ANALYSIS_PROTOCOL.md | inner objective h2 NLL + one-SE; primary trial-weighted h2 0-12 | GOV (registered) / not executed | New cycle again deviates (phase weights, equal-week, min-gain); must be recorded, not silently replaced |
| ANALYSIS_PROTOCOL.md | Full PAGe = "canonical adaptive online bias correction" | SUP | Bias corrector now optional grid axis incl. off (D5) |
| ANALYSIS_PROTOCOL.md s.4 ablation 4 | no bias correction also disables post-peak override | CUR? | Needs production confirmation that post-peak override still exists in subset-M2 |
| GOVERNANCE_DECISIONS.md | G-01..G-09, 0.02 gate provenance, vintage rule | GOV | G-05 now matters: complete 2025-26 comes from PHO ORVT feed with tail revisions |
| ONTARIO_FLU_SEASON_DECLARATION.md | 11 seasons; 2025-26 "valid" | GOV | Coverage wording must change (complete, not partial) |
| IGNITION_LABEL_PROTOCOL.md | integer vector, `2025-26 = 19L`, "integer-valued" validation check | PRIOR/SUP | New cycle uses timing-v2 labels (ignition + observed peak), fractional target label+0.5 |
| METHODS.md s. data contract, targets, information boundary | weekly counts, `weekF`, vintage rule | GOV | Add calendar-length rule (F2) |
| METHODS.md s. M0 | integer lock week; no loss description | PRIOR | Replace with fractional paragraph + new loss (D2) |
| METHODS.md s. M1 | multi-template alignment, `logit_spread` | CUR (verify) | Add fractional coordinates, median anchor, identical tune/fit preprocessing (F3), init weights (F5) |
| METHODS.md s. M2 | full binomial GAM formula with season RE, `bam()` | SUP (inferred) | Production M2 is the M1-offset subset correction (`m2_subset_correction.R`); confirm |
| METHODS.md s. online correction | canonical `bias_alpha/beta`, 3rd same-sign residual trigger, post-peak M1 substitution, raw-predictor bug caveat | SUP | D5: optional, 2 same-sign weeks, logit cap, off in grid |
| METHODS.md s. validation L1-L3 | three-level nested LOSO, 11 outer, adoption rule | CUR (structure) | "conditional downstream-tuning limitation" is SUP by F1 |
| METHODS.md L3 | "partial 2025-26 contributed available observations" | SUP | Complete data |
| METHODS.md phase weights | 2 for weeks 0-12 after ignition, 1 later | SUP | D3 observed-peak three-phase 0/2/2/1 |
| METHODS.md selection | `min_nll`, equal-row CE, M1 min-gain | PRIOR | New-cycle selection text needed |
| METHODS.md comparators/ablations | 7 models, 4 ablations, 3 sensitivities | GOV | Only persistence, seasonal mean, calendar GAM exist in code (unreviewed) |
| METHODS.md outcomes | formula with 0-12 weights, test-count sensitivity, strata 0-3/4-12 | SUP (weights) / GOV (strata) | Rewrite weights; keep strata as secondary |
| METHODS.md L3 | "archived old M2" paired comparison | SUP | Replace with shadow M2 |
| PLAN.md | decisions 1-14; phase table; evidence requirements | GOV, except #2 | **#2 conflict**: "new search must begin a new cycle with a new holdout" but the new cycle reuses 2025-26 as an outer fold (see s.2 D-9) |
| PLAN.md #4, TODO | v16-corrected as confidence baseline | SUP | Now legacy context only, not comparator |
| SKELETON.md 4.2/4.3/4.5 | one-SE, h2 trial-weighted, origins ignition..+12 | GOV (registered) / not executed | Must show registered vs executed |
| SKELETON.md 4.1, 4.7 | historical 2025-26 acceptance replay separate | GOV | Still separate |
| TODO.md | Phase 0 checklist dated 2026-09-02 | PRIOR (stale) | Refresh after plan approval |
| REVIEW_LOG.md | 2026-09-01 reviews and dispositions | GOV (history) | Append-only; add new-cycle entry |
| PUBLICATION_AUDIT_2026-09-07.md | findings 1-6; restricted rescoring table (2025-26 partial, 8 rows) | PRIOR (numbers) / GOV (findings) | Findings 3 (post-peak raw predictor), 5 (provenance) need closure status from production |
| M2_MODEL_PROPOSAL.md + results/publication-repair-2026090{8,10}/ | subset-M2 experiments, phase-weighted expansions | PRIOR (development evidence) | Development-cycle history; not outer evidence |
| REPORTING_TEMPLATES.md | Tables 1-10, prediction schema | GOV | Add shadow-M2, gate-decision, weights-version, timing-mode columns |
| LITERATURE_*, EPIDEMICS_ARTICLE_SCAN.md | literature | GOV | Unaffected |
| drafts/validation-and-final-kit-methods-lean.md | recipe, gate 0.0012/0.002/0.95/no-degrade, shadow M2, final kit | CUR structure; SUP weights (0-12) | Update weights/bias/leakage text after Phase 2-3 freeze |
| drafts/fractional-timing-deviation-draft.md | fractional rationale, adoption date, 16/25 specs, 1.238 vs 1.213 | CUR (deviation) with PRIOR evidence | Evidence is integer-vs-fractional on pre-fix code; label as such |
| drafts/execution-record-2025-26-draft.md | r3/r4/r5 table, 0.5578 vs 0.5575 on 8 rows, M1 reuse, M2 parallel, platform | PRIOR/pre-fix | r5 and kit `05f78903` are pre-fix; not final |

## 2. Deviations the new cycle must record

All were adopted after prior-cycle outer results were visible, so the new
cycle is a new development cycle, not confirmation. Each entry needs: date,
decision ID, what changed, why, results visible at the time, affected
estimand/stage, and code pointer.

| ID | Deviation | ANALYSIS_DEVIATIONS (new dated file) | METHODS | RESULTS |
|---|---|---|---|---|
| D-1 | Fractional timing (`timing_mode="fractional"`, label+0.5 targets, `iWeek_hatF` + bracket, M1 median anchor) | Yes; adopted 2026-09-14 after integer results; evidence mixed | M0, M1 coordinates | Report timing mode per fold; label `+/-1` sensitivity; no integer/fractional pooling |
| D-2 | Scoring weights: observed-peak three-phase (pre 0 / rise 2 / turning peak-2..peak+4 2 / decline 1), equal week and season; replaces 0-12 break; applies to M2 tuning + gate; replay reports new and legacy weights | Yes; also restate divergence from registered trial-weighted h2 primary | Outcomes and selection; fitting weights documented separately | Primary table under new weights; legacy-weight and registered-primary (h2, 0-12, trial-weighted) as labelled sensitivities |
| D-3 | Season-held-out upstream M1 for M2 rows and gate (F1 leakage fix) | Yes; prior-cycle inner M2 scores and gate decisions were optimistic (direction unverified) | Validation L1-L2; remove "conditional tuning" limitation | Note prior gate decisions not comparable |
| D-4 | Calendar length from season calendar (`nW_true`), not observed max (F2) | Yes | Data contract | Affected folds/rows if any |
| D-5 | M1 tune/fit preprocessing identical (`k_deriv`, `peak_weight_boost`) (F3); init-GLM double weighting removed (F5) | Yes (grouped as correctness fixes) | M1 | None beyond regenerated numbers |
| D-6 | M0 loss: symmetric absolute loss on fractional target + late penalty (D2); misses kept missing, `use_cls=FALSE` honoured (F4) | Yes; prior selections all early (mean -0.40 wk) | M0 selection objective | M0 signed/absolute error, miss rate per fold |
| D-7 | Complete 2025-26 data (replaces 20-week partial); source = ORVT builder; revision diff benign | Yes; plus G-05 vintage statement | Data, season support | 2025-26 in main aggregate if coverage complete; revision sensitivity if vintages exist |
| D-8 | Optional online bias corrector: grid axis with off, 2 same-sign trigger, logit cap fixed a priori; adopted only via gate (D5) | Yes; protocol s.3 item 7 said "canonical" correction | Online correction | Fraction of folds selecting bias on; ablation 4 becomes partly redundant |
| D-9 | 2025-26 reused as outer fold despite PLAN #2 ("new holdout") and its earlier acceptance replay and r3/r4/r5 gate runs | Yes; must state 2025-26 is not untouched and 2026-27 prospective season is the only untouched evidence | Validation design | Leave-2025-26-out summary as influence line |
| D-10 | Adoption gate itself (min gain 0.0012 / h2 0.002 / 0.95 bound / no-degrade) replaces one-SE for M2 vs M1 | Yes if not already recorded; confirm date/value provenance | Selection | Gate decisions per fold |
| D-11 | Peak-relative M2 terms (`origin - t_peak_hat`, peak-passed, `logit_spread`) grid families (Phase 3) | Yes if adopted | M2 | Selected family per fold |
| D-12 | Platform pinning (single BLAS/LAPACK), run-local library, RNG seed recording (F7) | Reproducibility section, not an analysis deviation | Software and reproducibility | Platform manifest table |

Recommended file: `manuscript/ANALYSIS_DEVIATIONS_<freeze-date>.md`, written
after production freezes the recipe and **before** any new-cycle outer
results are opened, with an explicit "results visible" list (prior cycle
11-fold table, r3/r4/r5, kit `05f78903` audit). If the recipe is frozen
before outcomes, protocol v2.0 (pre-outcome for this cycle) is preferable to a
post-hoc deviation; PLAN.md/PROTOCOL change-control require a new version either
way.

## 3. Evidence plan

### 3.1 Primary outer evidence (Workflow A)

- 11 outer folds, one fixed recipe, one platform, fresh run IDs, detached.
- Per fold save: gate decision + inner gains (`inner_gate_decision.rds`),
  selected hyperparameters per stage, boundary reports, M1 and gate-applied
  forecasts, **shadow M2** forecasts when the gate kept M1, per-row
  season/origin/horizon/target week/phase/weights (new and legacy)/y/N.
- Headline outcome (new cycle): phase-weighted Bernoulli CE, h1+h2 and h2,
  equal-season. Registered v1.4 primary (h2, ignition..+12, trial-weighted,
  PAGe vs calendar GAM) computed on the same rows as a labelled line, so the
  registered estimand is never dropped.
- 2025-26 reported inside the aggregate (complete data) plus leave-2025-26-out.

### 3.2 Comparators (same folds, same rows, same scoring)

| Comparator | Code | Status | Needed |
|---|---|---|---|
| Persistence | `baseline_persistence()` | exists, unreviewed | review + run on all 11 folds |
| Seasonal mean (seasonal-naive, Jeffreys) | `baseline_seasonal_mean()` | exists, unreviewed | check denominator pooling matches protocol s.3 item 2 |
| Calendar-week binomial GAM (primary) | `baseline_calendar_gam()` | exists, unreviewed | grid k_week {6,8,10} x k_signal {4,6,8}; selection rule must be declared (one-SE per protocol, or deviation) |
| M1-only (always-M1) | pipeline | available | from fold outputs |
| Lagged elastic net, analogue, boosted tree | none | missing | decision: implement or record protocol narrowing (deviation) |
| RSV | none | out of scope until influenza go/no-go + data gate | propose: defer; Discussion only |

### 3.3 Adoption-rule evidence

Per fold, from inner gate + outer shadow:

1. Inner gain (overall, h2) vs outer gain of M2 over M1 on the held-out season;
   scatter with 11 points, sign agreement count.
2. Three policies on identical rows: always-M1, always-M2 (tuned M2 regardless
   of gate), gate. Equal-season mean, per-season deltas, worst season,
   number of harmed seasons.
3. Selection stability: selected values per stage across folds; count of
   boundary expansions.
4. Threshold sensitivity curve (gain threshold vs outer policy loss) labelled
   post-hoc descriptive, never used to re-select.
5. Same inner-vs-outer check for M1 min-gain / prefer-simpler.

Descriptive only; no tests (protocol s.5).

### 3.4 Secondary

Label `-1/+1/M0-only` sensitivities; the 4 ablations (at least no-M1 and
no-bias, which is now a grid value); horizon and phase strata; M0 ignition
error and miss rate; M1 weighted peak MAE per fold; runtime per fold and
weekly latency; prior-cycle 11-fold table and 2025-26 acceptance replay as
separately labelled history; interval claims limited to conditional bands
unless production adds predictive intervals.

## 4. Manuscript work order (after plan approval)

1. Wei (bulk): mark every PRIOR/SUP passage in place with a dated status
   banner; no numeric edits. Review by ming-manuscript.
2. Draft new deviations file / protocol v2.0 once production freezes recipe.
3. Rewrite METHODS M0/M1/M2/correction/selection/weights from frozen code.
4. RESULTS skeleton with `[PENDING new-cycle]` placeholders bound to artifact
   paths; fill only from production NOTIFY.
5. Refresh PLAN/TODO; REVIEW_LOG entry.

## 5. Review disposition (channel #5, ming-page APPROVE WITH NOTES)

- Q1 resolved: new-cycle M2 = `offset_subset_v1` (s(z), s(u), s(d) by horizon, all-off = M1). METHODS full-GAM section SUP. Post-peak M1 substitution is legacy runtime only; protocol ablation 4 wording must change. PUBLICATION_AUDIT finding 3 N/A unless Phase 3 adds peak terms.
- Q4 resolved: fold outputs will carry y, N, season, origin, h, t_since, observed-peak phase, both weight versions, M1/gate/shadow-M2 p (Phase 2 requirement).
- Q6 resolved: gate defaults 0.0012 / 0.002 in `nested_season_evaluation.R:367-368`, first committed `97f88d8` (2026-09-14); no-degrade and t-allowance in same function; no derivation document. Disclose as a-priori choice; freeze in protocol v2.0.
- Q2 decided (Lennon, 2026-09-15): 2025-26 outer fold labelled "exposed" (D-9). Q3 decided: PROTOCOL v2.0 frozen before any new-cycle fold is viewed. Q5 open (comparator scope).
- Reviewer family same as author (Claude); a GPT review pass is optional.

## 6. Proposed comparator: IRVRI mvgam (Lennon request, 2026-09-15; scope open)

Source (read-only): `/home/yeli/repos/IRVRI@2e71d7c`, `R/wf_train.R` (5 finalist specs: mod2AR, mod2GP, mod5GP, mod6AR, mod6RW), `R/wf_season.R`, `R/wf_evaluate.R`, `R/wf_cv_frame.R`, `R/wf_metrics.R`. Stack present on Asgard (mvgam, cmdstanr 2.39.0, IRVRI).

Harmonization required before it is a fair comparator:
1. Same authorized influenza CSV, 11 seasons, exclusions, and outer folds (`history = "all_other"` = exchangeable LOSO, holdout masked after origin).
2. Same row set: PAGe origin/horizon rows (h1, h2), not IRVRI's `(t0, t0+h_eval]` window with `p_thresh`; week-53 handling and season start (IRVRI collapses 53 into 52, PAGe `weekF` keeps 53) must map to identical target weeks.
3. Export per-row posterior-mean p (and draws) keyed by season/origin/h; score with the PAGe scorer (phase-weighted CE, legacy weights, registered h2 trial-weighted). LPD/CRPS only as mvgam-specific secondaries (PAGe has no draws).
4. Spec choice prespecified in PROTOCOL v2.0: one declared spec, or inner-fold selection among finalists. Pre-tuned priors must be re-derived within each outer fold's training seasons (current priors are RSV-based).
5. Cadence disclosed: mvgam refits (MCMC) at every origin; PAGe uses one frozen kit per season. Comparison is of deployable workflows.
6. Compute: 11 seasons x ~25-35 origins x spec(s) x 4 chains x 1000 iter; needs a production run plan.

## 7. Comparator decision (Lennon, 2026-09-15)

- Baseline: IRVRI legacy production GAM (`irvri_adapter_gam()`, `R/wf_adapter_gam.R`): per-age-stratum `mgcv::gam(cbind(pos, neg) ~ s(date, bs="cr"), REML, select=TRUE)` on the last 365 days of DAILY counts, knots every 14 days re-derived per refit, strata combined by test-weighted daily-to-weekly aggregation; refit at every origin.
- Second comparator: one IRVRI mvgam spec, to be chosen later.
- Application: influenza data.
- Open implications:
  1. Legacy GAM needs daily counts by age (`date`, `age.`, `pos`, `neg/tests`; OLIS via `irvri_wf_real_data(pathogen = "flu")`). PAGe influenza input is weekly aggregate; METHODS says no daily counts exist in the historical PAGe workspace. Need a daily influenza source whose weekly all-ages aggregate reproduces PAGe's `y`/`N` for all 11 seasons, or a documented target mismatch.
  2. "Choose mvgam after results" is outcome-dependent unless selection uses inner-fold scores only (or a prespecified rule in PROTOCOL v2.0). Choosing on outer-fold results must be labelled post hoc, with all five specs reported.
  3. Calendar-week GAM (registered primary comparator in v1.4) status: keep as secondary, or replace by the IRVRI legacy GAM as primary (deviation in v2.0).
  4. Legacy GAM information set: rolling 365 days only, not other seasons; mvgam under `all_other` uses later seasons. Disclose as information-set asymmetry.

## 8. Added deviation D-13: season construction (ming-page channel #9, Lennon decision)

| ID | Deviation | ANALYSIS_DEVIATIONS | METHODS | RESULTS |
|---|---|---|---|---|
| D-13 | Seasons are July-start (MMWR week 27 of Y to week 26 of Y+1) derived from week dates; `weekF = ((MMWR week - 27) mod nW(Y)) + 1`, `nW` from the MMWR calendar of Y. Prior cycle grouped by the PHO/CSV season label (week 35-34), so weekF 1-8 of each season were rows from the following summer (112/749 rows; e.g. `2025/run_2025_ultimate.R:118-127`). | Yes, as data-construction fix. All prior-cycle results (11-fold table, r3-r5, kit `05f78903`) used the mislabelled construction. Ignition labels unaffected (all > weekF 8). | Data contract text already states `start_week = 27`; add that execution previously deviated and that season membership is date-derived, not source-label-derived. Pairs with D-4 (calendar length). | Note prior-cycle numbers are not comparable. Most exposed: pre-ignition M0 windows, M1 templates/reference curve, and calendar-week comparators (calendar GAM, seasonal naive). Complete 2025-26 = 53 July-start weeks. |

Also check for the IRVRI comparators: IRVRI `irvri_wf_seasonize()` season/week definition and week-53 collapse must map to the same July-start weeks (plan s6 item 2).

## 9. Legacy daily GAM comparison design (first comparator; draft for Lennon)

### Why the latest season

The legacy GAM is one continuous daily series refit on the trailing 365 days
at each origin; it never uses other seasons, so it is inherently
chronological. PAGe's outer design is exchangeable LOSO, where earlier
holdouts are trained on later seasons. For the latest season, 2025-26, the
PAGe outer fold trains only on the 10 earlier seasons, so it is also
chronological. That is the one fold where both methods see only the past, and
it needs no extra PAGe run.

### Tiers

| Tier | Seasons | PAGe kit | Legacy GAM | Status in paper |
|---|---|---|---|---|
| 1 | 2025-26 | New-cycle outer fold 2025-26 (post-fix; not r5 / `05f78903`) | Walk-forward over 2024-07..2026-06 daily series | First comparison; descriptive, n = 1 season, labelled "exposed" (D-9) |
| 2 (optional) | 2022-23, 2023-24, 2024-25 (+2025-26) | Extra prior-only kits per season (expanding window; 2022-23 trains on 7 pre-pandemic seasons) | Same walk-forward | Chronological sensitivity; needs daily flu back to 2021-07 and 3 extra PAGe recipe runs |
| 3 | 2026-27 | Final operational kit | Production weekly run | Only untouched evidence; weekly side-by-side log |
| - | Other exchangeable folds | Outer folds | Walk-forward | Not a fair contrast (information-set asymmetry); report legacy scores only descriptively, if at all |

### Common rows and scoring (Tier 1)

1. Season/week: July-start MMWR (D-13). IRVRI `irvri_wf_seasonize()` defaults to `start_week = 35` and `flu_week` is a sequential row index; set `start_week = 27` and map by epiweek date, not row index. Handle week 53 by date (2025-26 has 53 weeks); do not use IRVRI's 53->52 collapse for scoring.
2. Origin = end of MMWR week t (Saturday); legacy fit uses daily rows with date <= that Saturday; PAGe uses weekly rows through week t. Same final-data snapshot for both (G-05).
3. Targets: weekly all-ages y, N for weeks t+1, t+2. Reconcile daily-aggregated weekly counts with PAGe's weekly input for 2025-26 first; any mismatch is documented and PAGe is scored on its own target.
4. Legacy output: weekly posterior-mean p per (origin, h), from IRVRI `predictions` (one row per cutoff/week; h = week - cutoff). Future test volumes use its 28-day mean fallback (no leakage).
5. Primary rows: PAGe forecast rows (detected ignition onward, h1 and h2). Score both with the same PAGe scorer: new three-phase weights (D-2), legacy 0-12 weights, and the registered h2 trial-weighted line.
6. Secondary: legacy GAM pre-ignition forecasts alone (PAGe emits none); per-week paired differences over time; by phase (rise/turning/decline) and horizon; MAE on positivity.
7. No intervals comparison (PAGe bands are not predictive intervals); no tests.

### Interpretation limits

One season cannot support a general claim; 2025-26 was exposed during
recipe development; legacy GAM uses daily input and age strata, PAGe weekly
all-ages. State all three.

### Needs

- Daily OLIS influenza extract by age (`date`, `age.`, `pos`, `neg`/`tests`) covering 2024-07-01..2026-06-30 at least (Tier 2: from 2021-07), authorized path only.
- Legacy settings as in production: `num_days = 365`, 14-day knots, summer thinning, strata, reporting lag at origin.
- New-cycle PAGe 2025-26 outer-fold predictions (A3).
- Runner owner: IRVRI legacy adapter run keyed to PAGe origins (IRVRI side or a PAGe script), executed by production.

### s9 review disposition (ming-page #12, APPROVE WITH NOTES)

- Per-row fold export confirmed as new-cycle output, keyed by July season + origin weekF + MMWR year/week; after season fix and Phase 2 spec.
- Season mapping: call the PAGe package season-calendar function (name pending, e.g. `page_season_calendar`); never IRVRI `start_week = 35` or row-index `flu_week`.
- Tier 1 BLOCKED on data: daily OLIS influenza extract (`OLIS_RESP_AGG_DAILY.csv`) is not on Asgard; Lennon to supply location and reporting-lag convention. Gate: daily->weekly aggregates must reproduce PAGe weekly y/N (exact-match rate, aggregates only).
- Adapter: ming-manuscript owns design/spec; Wei implements after PROTOCOL v2.0 freeze in a claimed path outside PAGe/R (proposed `scripts/comparators/irvri_gam_adapter.R`); Claude/GPT review before results. Claiming that path needs Lennon to extend ming-manuscript scope.

## 10. Decisions and data (Lennon, 2026-09-15)

- RSV: dropped from the manuscript (no RSV application or supplement). PROTOCOL v2.0 removes the RSV gate/s.7; Discussion may name it as future work.
- ming-oracle write scope extended to `scripts/comparators/` (adapter path).
- Daily source: `~/FLU/hist2026-04-01.RData` `r$flu` (daily x age, 2019-12-29..2026-03-28). Consequences: Tier 1 targets after 2026-03-28 unscorable (late 2025-26 decline truncated); Tier 2 data-feasible; single vintage, so final-data retrospective. Spec: `irvri-legacy-gam-adapter-spec-2026-09-15.md`.
