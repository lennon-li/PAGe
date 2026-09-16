# Analysis deviations: new development cycle (DRAFT)

Draft 2026-09-15 (ming-oracle). Companion to
[`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md).
Status: not final. Dates, commit SHAs and decision records marked `[FREEZE]`
are filled at protocol freeze from production records (ASK A2).

## Scope and visibility

This register lists every change from the prior cycle (protocol v1.4 as
executed: commit `95c1c9f`, integer timing, CSV-label seasons, truncated
2025-26, conditional inner M2 tuning) to the new cycle. All changes were
decided after prior-cycle outer results, the 2026-09-07 publication audit,
2025-26 gate runs r3-r5, and the kit `05f78903` audit were visible. The new
cycle is therefore a new development cycle, not confirmation of any earlier
choice. Prior-cycle and new-cycle results are never pooled.

None of the entries below was selected by comparing new-cycle outer-fold
results; the protocol is frozen before those results exist.

## Register

| ID | Change | Date / record | Reason | Visible at decision | Affects |
|---|---|---|---|---|---|
| D-1 | Fractional ignition timing and timing-v2 labels (ignition and observed-peak one-week intervals replace the integer `ignition_labels_m0` vector): training targets label + 0.5; M0 decimal estimate with one-week bracket; M1 fractional coordinates and median anchor | 2026-09-14; package API entry `[FREEZE: commit]` | Weekly aggregation places onset inside a week; an interval avoids a false exact week | Prior 11-fold results; integer 2025-26 replay r3. Inner evidence mixed (fractional better in 16/25 M1 specs; adopted spec 1.238 vs 1.213 weeks) | M0, M1, M2 inputs |
| D-2 | Scoring weights by observed peak: pre-ignition 0, rise (ignition..peak-2) 2, turning window (peak-1..peak+3) 3, decline (after peak+3) 1, equal per week and season; replaces fixed 0-12-week break (2/1) | Lennon, 2026-09-15 (production plan D3) | Peak detection is the model's purpose; weight the turning window most, using the observed peak instead of a fixed window | Prior results; r3-r5 | M2 tuning, adoption gate, primary score |
| D-3 | Fully nested inner gate: inner season `s` rows use M1 fitted without `s`; training rows of season `r` use M1 fitted without `r` and `s` | Lennon, 2026-09-15 `[FREEZE: commit]` | Prior inner M2 scores used M1 fitted with the evaluated season (leakage); Liz re-review found partial isolation insufficient | Liz production-kit audit 2026-09-15 | M2 tuning, gate decisions |
| D-4 | Season length from the MMWR calendar, not observed coverage | `[FREEZE: fix F2 commit]` | Partial seasons produced wrong aligned week counts | Same audit | Data contract, M1 alignment |
| D-5 | Identical M1 preprocessing in tuning and fitting (`k_deriv`, `peak_weight_boost`); single N weighting in M1 initialization | `[FREEZE: fixes F3, F5 commits]` | Tuned values were evaluated under a different pipeline than fitted | Same audit | M1 |
| D-6 | M0 loss: symmetric absolute error on the fractional target with late penalty; misses kept missing with `detection_failed` accounting and scored in tuning at the legacy `w_max` error; `use_cls = FALSE` default and honoured | `[FREEZE: decision D2, fix F4 commits]` | Prior loss gave zero loss to errors in [-1, 0]; all 11 prior selections detected early (mean -0.40 weeks) | Same audit | M0 selection |
| D-7 | Complete 2025-26 season (53 July-start weeks) replaces the 20-week partial input | `[FREEZE: builder commit, checksum]` | Season completed; ORVT feed verified; revision differences benign | Prior partial-season results | All stages; 2025-26 fold and training membership |
| D-8 | Online bias corrector is an optional grid value (off included), trigger 2 same-sign weeks, logit cap fixed a priori, adopted only via the gate | `[FREEZE: decision D5]` | v1.4 fixed the correction as always on; its benefit was not established | Prior results | M2 |
| D-9 | 2025-26 kept as an outer fold although exposed; v1.4 plan decision #2 required a new holdout for any new search | Lennon, 2026-09-15 | Keep the 11-season universe; no untouched historical season exists | r3-r5, acceptance replay | Interpretation; 2026-27 prospective is the only untouched evidence |
| D-10 | M2-versus-M1 adoption gate (mean season gain >= max(floor, qt(0.95, n-1) SD/sqrt(n)), floors 0.0012 overall and 0.002 at h2; no season degradation) replaces one-SE selection for adopting M2 | Code defaults first committed `97f88d8` (2026-09-14); no derivation document | Operational fallback to M1 when M2 gain is small or inconsistent | Prior results; 2025-26 replays kept M1 | M2 adoption |
| D-11 | Peak-relative M2 terms (time since M1 peak estimate, peak-passed indicator) as grid families including off | `[FREEZE: included or not]` | Allow post-peak behaviour without runtime substitution | Prior results | M2 |
| D-12 | Recorded platform per run (cross-host only after equivalence check; SciNet for weekly data only), run-local library with hash check, recorded seeds and dependency versions | `[FREEZE: fix F6]` | Cross-platform numerical differences (up to 0.011 weeks M1 error) and a killed shared-library run | r4, Venkata reproduction | Reproducibility only |
| D-13 | Seasons derived from week dates starting MMWR week 27 (`page_season_calendar()`); source CSV label ignored | Lennon, 2026-09-15 `[FREEZE: commit]` | Prior runs grouped by CSV label (week 35-34), so weekF 1-8 of each season came from the following summer (112/749 rows) | Prior results, r5, kit `05f78903` | All stages; calendar comparators; ignition labels unaffected |
| D-14 | Primary structure: two co-primary descriptive blocks, (1) PAGe vs IRVRI legacy daily GAM on chronological seasons 2022-23 to 2025-26 (extra prior-only kits for 2022-23 to 2024-25), (2) Workflow A 11-fold PAGe with paired weekly comparators; calendar GAM no longer the single primary comparator | Lennon, 2026-09-15 | Compare against the model in operational use | Prior results; no comparator results | Primary estimand |
| D-15 | Comparator set narrowed: elastic net, historical analogue, boosted tree removed; IRVRI mvgam `mod2AR` added, fixed up front on rationale (IRVRI default), not tuned on flu | Lennon, 2026-09-15 | Prioritise operational and in-development comparators | No comparator results | Secondary comparisons |
| D-16 | RSV application dropped | Lennon, 2026-09-15 | Scope; influenza claims only | Prior influenza results | Scope; protocol v1.4 s.7 removed |
| D-17 | Primary score equal-week phase-weighted within season (v1.4: test-count-weighted h2, origins ignition to +12); both horizons scored | `[FREEZE]` | Match the tuning and gate objective | Prior results | Primary score; v1.4 line kept as sensitivity |
| D-18 | Forecast-availability contract and plain-shift alignment: `newWeek = weekF - iWeek + anchor` without clamp; out-of-domain rows excluded from template fitting and alignment support; out-of-support forecasts recorded unavailable; contrasts use rows available to all models | `[FREEZE: commit]` | Prior alignment clamped shifted weeks, silently distorting templates and forecasts (Liz findings 1, 3) | Liz re-review 2026-09-15 | M1, M2, common-row definition |
| D-19 | Walk-forward prefix before aggregation, including M0; week 53 not folded into 52 | `[FREEZE: commit]` | M0 folding could admit post-origin information (Liz finding 2) | Liz re-review 2026-09-15 | M0 |
| D-20 | Legacy M2 correction family not a governed default; research flag only, rejected by governed kits | `[FREEZE: commit]` | Governed kits must use the evaluated family | Production audit | M2 |
| D-21 | Failure disposition: a season without a paired score is reported and excluded from that contrast's mean; v1.4 stopped the primary comparison | Draft rule, 2026-09-15 `[FREEZE: confirm]` | Several comparators and a truncated daily snapshot make unpaired seasons likely; stopping would block all reporting | Prior results | Primary and secondary contrasts |
| D-22 | Structural ablations (v1.4 s.4): no M1 alignment kept in Workflow A; no ignition gate and no alignment uncertainty moved to simulation; no bias correction covered by the grid. Label sensitivities: M0-generated labels in Workflow A; -1/+1 shifts moved to simulation | Lennon, 2026-09-15 | Compute cost of 11-fold reruns; alignment is the core claim and M0 labels the most operational variant | Prior results | Attribution evidence |
| D-23 | (Superseded for this cycle by D-32: M1 fixed) M1 selection by 0.05-week minimum gain with simpler `k_ref` preference, not v1.4 one-SE (already executed in the prior cycle) | Code `select_m1_candidate()`; prior cycle | Practical simplification threshold | Prior results | M1 |
| D-24 | Origin window: all post-ignition origins with observed targets, h1 and h2 (v1.4: h2, ignition to +12) | Lennon, 2026-09-15 | Phase weights replace the fixed window | Prior results | Primary row set |
| D-25 | Probabilistic scores added: binomial (or posterior) predictive quantiles, WIS, 50%/95% coverage and width for all models (v1.4: intervals only if emitted, not compared) | Lennon, 2026-09-15 (target *Epidemics*) | EPIFORGE item 14; field norm for forecast evaluation | Journal-fit audit; no new-cycle results | Secondary outcomes |
| D-26 | FluSight-style baseline added as a standard external benchmark | Lennon, 2026-09-15 | EPIFORGE item 12 | Journal-fit audit; no comparator results | Comparators |
| D-27 | Target journal *Epidemics* and EPIFORGE 2020 reporting; main-text versus supplement placement fixed (protocol s.6) | Lennon, 2026-09-15 | Journal fit | Journal audits | Reporting only |
| D-28 | Real-time application section: final kit trained on all 11 seasons (no outer holdout), evaluated on 2026-27 as it happens with append-only timestamped logging and real-time vintages; reported up to the data available at submission | Lennon, 2026-09-15 | Only untouched evidence; operational relevance for *Epidemics*; EPIFORGE item 4 | No 2026-27 data exist | Results structure; operations logging |
| D-29 | Smaller tuning grids chosen using prior-cycle tuning results; boundary expansion kept | Lennon, 2026-09-15 (grids in protocol s.2; docs/m2-fix-plan-2026-09-15.md "Decisions recorded 2026-09-15") | Compute; prior-cycle selections concentrated in part of the grid | Prior-cycle tuning tables and selections (inner scores, not outer results) `[FREEZE: confirm no outer-fold results used]` | M0, M1, M2 search space |
| D-30 | mvgam `mod2AR` restricted to the four chronological seasons (prior-only history), with shortened warm-started chains under a prespecified pilot and diagnostics gate | Lennon, 2026-09-15 | MCMC cost; mvgam is a supplementary comparator | No comparator results | Supplementary comparisons |
| D-31 | Compute options recorded per run; validation uses the exact preset (caching and zero-weight skipping are result-identical); racing and `bam_discrete` are package features not used for validation | Lennon, 2026-09-15 | Compute | No new-cycle results | Reproducibility |
| D-32 | M1 hyperparameters fixed (`k_ref = 30`, `slope_weight = 16`) instead of tuned; prespecified sensitivity recipe `k_ref = 20`, `slope_weight = 12`; fully nested gate (`gate_nesting = "full"`, validation default) reselects every tuned upstream axis (here M0) and the full M2 selection within each season-excluded dataset; `"conditional"` is a package option not used for validation | Lennon, 2026-09-15 | Flat M1 surface (0.16-0.18 weeks over 25 specs), unstable `k_ref` ranking, M1 tuning 72-78% of wall time | Prior-cycle tuning tables, r5, all-season kit `05f78903` tuning (no new-cycle outer results) | M1, gate, compute |

## Consequences for reporting

- Prior-cycle numbers (11-fold table, r3-r5, acceptance replay) are not
  comparable with new-cycle numbers because D-1 to D-8, D-13, D-18 and D-19 change
  the data or the fitted models.
- The registered v1.4 primary line is reported as a sensitivity on new-cycle
  rows, so its estimand is not dropped.
- Entries marked `[DECISION]` must be resolved before freeze; entries marked
  `[FREEZE]` need their record before this file leaves draft.

Not a deviation: the Phase 1 grid-expansion spacing change was reverted to baseline (Liz finding 5). The planned partial-season handling (F7) was dropped because the complete 2025-26 season was supplied (D-7).
