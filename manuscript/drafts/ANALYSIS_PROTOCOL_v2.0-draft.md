# PAGe analysis protocol, version 2.0 (DRAFT, not frozen)

- Protocol version: 2.0 draft
- Status: **DRAFT**. Not frozen. Values marked `[FREEZE]` are filled from the
  production recipe manifest at freeze; items marked `[DECISION]` need a
  project-lead decision before freeze.
- Draft date: 2026-09-15 (ming-oracle)
- Supersedes on freeze: [`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) v1.4
  for the new development cycle. v1.4 remains the registered record of the
  prior cycle and is not edited.
- Applies to: Ontario influenza only.
- Target journal: *Epidemics* (Methodological Manuscript), reported to EPIFORGE 2020 (Lennon, 2026-09-15).
- Deviations register: [`ANALYSIS_DEVIATIONS_new-cycle-draft.md`](ANALYSIS_DEVIATIONS_new-cycle-draft.md)

## 0. Pre-outcome statement and exposure

This protocol is frozen before any new-cycle outer-fold, comparator, or
final-kit forecast is opened. The freeze record lists the code commit, the
recipe manifest checksum, the data checksums, and the date and time.

Already visible when this version was drafted, and therefore not
confirmatory:

- the prior-cycle 11-fold replay (commit `95c1c9f`, integer timing, CSV-label
  seasons, truncated 2025-26) and its publication audit;
- 2025-26 gate runs r3, r4, r5 and the unpromoted kit `05f78903`;
- the historical 2025-26 acceptance replay and the `v16-corrected` incumbent;
- prior-cycle tuning grids and selections, used to narrow the new-cycle grids
  (D-29);
- inner-tuning development experiments under
  `manuscript/results/publication-repair-2026090{8,10}/`.

`2025-26` was exposed during recipe development. It stays an outer fold,
labelled **exposed**. The only untouched evidence for this cycle is the
prospective 2026-27 season (Section 6.3).

## 1. Data and season construction

### 1.1 Season universe

The 11 principal seasons and 4 exclusions are unchanged from v1.4
([`ONTARIO_FLU_SEASON_DECLARATION.md`](../ONTARIO_FLU_SEASON_DECLARATION.md)):
principal `2012-13, 2013-14, 2014-15, 2016-17, 2017-18, 2018-19, 2019-20,
2022-23, 2023-24, 2024-25, 2025-26`; excluded `2011-12, 2015-16, 2020-21,
2021-22`. No season is added.

### 1.2 Season and week coordinates

Seasons start at MMWR week 27 and are derived from week dates with
`PAGe::page_season_calendar(dates, start_week = 27L)`; the source season label
is ignored. `weekF = ((MMWR week - 27) mod nW(Y)) + 1`, where `nW(Y)` (52 or
53) comes from the MMWR calendar of the season start year, never from observed
coverage. `weekF` is chronological within the date-derived season; weeks do
not wrap across seasons.

**Alignment coordinate.** `newWeek = weekF - iWeek + anchor` is a plain shift
(no modulo, no clamp). Shifted rows outside the template domain (1-52) are
flagged and excluded from template fitting and from online alignment support.
A forecast whose target falls outside support is recorded as unavailable with
a reason code.

**Walk-forward prefix rule.** Inputs at origin `t`, for every stage including
M0, contain no week after `t`; this is asserted in code. Week 53 is never
folded into week 52.

### 1.3 Inputs

| Input | Use | Identity recorded at freeze |
|---|---|---|
| Weekly influenza positives and tests, 11 seasons, complete 2025-26 (53 weeks) | PAGe, persistence, seasonal naive, calendar GAM, mvgam | Builder commit, file checksum `[FREEZE]` |
| Daily influenza positives and tests by age stratum, 2019-12-29 to 2026-03-28 (`hist2026-04-01.RData`, element `flu`) | IRVRI legacy GAM only | File checksum `[FREEZE]`; private, never copied; processed only on local hosts (Asgard/BCC), never on SciNet |

Both are single final-data snapshots. All analyses are final-data
retrospective replays: no model receives origin-time vintages, and revision
effects are a stated limitation (G-05).

### 1.4 Labels

Timing-v2 retrospective reference labels (ignition week and observed peak
week, each as a one-week interval), replacing the integer
`ignition_labels_m0` vector of `IGNITION_LABEL_PROTOCOL.md` v1.1 (D-1) for all 11 seasons `[FREEZE: label vector
and checksum]`. Labels are operational references, not biological ground
truth. A held-out season's label is withheld from training and joined only for
scoring.

## 2. PAGe recipe (the object evaluated)

The recipe is fixed as a whole; hyperparameter values are its outputs.

| Component | Rule |
|---|---|
| Timing | `timing_mode = "fractional"`; training targets at label + 0.5; M0 emits decimal ignition estimate with its one-week bracket |
| M0 | Detector grid tuned by inner LOSO; loss = symmetric absolute error on fractional target plus late-detection penalty; misses retained as missing with `detection_failed` accounting and scored in tuning at the legacy `w_max` error, so a miss never beats a late detection `[FREEZE: confirm; docs/m2-fix-plan-2026-09-15.md:29 still says "not w_max"]`; classifier gate off by default (`use_cls = FALSE`) `[FREEZE: grid, penalty]` |
| Grids | All grids are declared in the recipe manifest. Grid ranges were narrowed using prior-cycle tuning results (prior-cycle-informed, D-29); boundary expansion remains active, so a narrowed range can still grow. Starting grids (Lennon, 2026-09-15): M0 unchanged from the prior cycle (36 specifications); M1 fixed at `k_ref = 30`, `slope_weight = 16` (single-value grids; Lennon, 2026-09-15, D-32); M2 stage A `intercept` {FALSE, TRUE} x `k_z` {0, 3, 4, 5} x `k_u` {0, 7, 8, 9} x `k_d` {0, 3, 4, 5, 6, 7} (192); M2 stage B (Phase 3) the top 2 stage-A specifications x `k_tau` {0, 3, 4, 5} x `conf_scale` {none, peak_ci}. Prior-cycle evidence used (descriptive, not confirmatory): all h1 M2 specifications within 0.0012 NLL; `k_u = 8` selected in all four horizon runs; M1 tuning took 72-78% of wall time; the M1 surface spanned only 0.16-0.18 weeks across 25 specifications, `k_ref` rankings reversed between the 2025-26 fold and the all-season kit, `k_ref` 30/40/50 were within 0.013 weeks, and `slope_weight` 12-20 was consistently best `[FREEZE: source artifact paths]`. No hyperparameter is removed from the package: recipes fix values through single-value grids so other applications can tune them |
| M1 | Multi-template alignment with `k_ref = 30`, `slope_weight = 16` fixed (not tuned in this cycle); identical preprocessing in tuning and fitting. The M1 selection rule (weighted peak-week MAE, weight `exp(-(0.1 * weeks_before_peak)^2)`, `min_gain = 0.05` weeks, prefer simpler `k_ref`) applies only when M1 axes have more than one value |
| M2 | Governed family `offset_subset_v1` on the M1 logit offset (the legacy correction family is available only under an explicit research flag and is rejected by governed kits) (terms `s(z)`, `s(u)`, `s(d)` by horizon; all-off equals M1); optional peak-relative terms `[FREEZE: included or not]`; optional online bias corrector with off in grid (`bias_alpha` in `[FREEZE]`, trigger 2 same-sign weeks, logit cap `[FREEZE]`) |
| Inner gate (fully nested) | Package option `gate_nesting = "full"` (default; used for all validation runs). For each inner gate season `s`, every tuned upstream axis and the full M2 selection are rerun on the data without `s` (in this cycle M0 and M2; M1 is fixed), then rows of `s` use M1 fitted without `s` and training rows of every other season `r` use M1 fitted without both `r` and `s`. Nothing fitted or selected on `s` enters the correction evaluated on `s` (Lennon, 2026-09-15). The alternative `gate_nesting = "conditional"` (M2 selection only, outer-selected M0/M1 passed through; evidence labelled conditional on upstream selection) is a package feature not used for validation `[FREEZE: implementation commit]` |
| Scoring weights (tuning and gate) | `page_scoring_weights()`, scope M2 tuning and adoption gate, phases by observed peak week (Lennon, 2026-09-15): pre-ignition 0; rise (ignition to peak-2) 2; turning window (peak-1 to peak+3) 3; decline (after peak+3) 1. Equal weight per week, then per season. All 11 principal seasons are complete, so no inner season has a censored peak; a censored peak would make the protocol stop for a dated amendment. `[FREEZE: pending wiring; scoring_weights.R:1-3 is not yet used by tuning or the gate, which still use the 0-12-week contract]` |
| Boundaries | Every genuinely tuned axis with a boundary winner is expanded one valid step or recorded as a hard/null constraint before freeze |
| Adoption gate | Per season, gain = phase-weighted M1 score minus M2 score (equal-week, then equal-season). M2 is used only if the mean gain >= `max(floor, qt(0.95, n - 1) * SD / sqrt(n))`, overall (floor `0.0012`) and for each horizon (h2 floor `0.002`; h1 floor `[FREEZE: min_gain_by_horizon for h1]`; the code applies the per-horizon rule to every horizon, m2_baseline_decision.R:368), and no season degrades (`max_season_degradation = 0`); otherwise forecasts equal M1. The 0.95 bound is a decision threshold only; it is not reported as inference `[FREEZE: confirm]` |
| Compute options | All validation runs use `page_compute_options()` preset `"exact"`: result-identical caching and skipping of zero-weight predictions on; M2 racing off; M2 fit engine `gam`. The recorded options are part of run provenance and kit metadata, and governed freeze rejects unrecorded options. The `"fast"` preset (racing, `bam_discrete`) is described only as a package feature without validation evidence |
| Cadence | One training run per target season yields one frozen kit; weekly steps update detector, alignment and correction state only |
| Platform | Recorded platform per run (BLAS/LAPACK, OS, CPU, R and package versions), run-local library with source/install hash check, recorded RNG seeds. Runs may span Asgard and BCC only after a recorded cross-host equivalence check; SciNet may be used for weekly-data runs only `[FREEZE: hosts and equivalence evidence]` |

## 3. Validation designs

### 3.1 Exchangeable outer evaluation (Workflow A)

Each of the 11 seasons is held out once; the recipe runs on the other 10 and
the held-out season is replayed walk-forward with the frozen kit. When the gate
keeps M1, the tuned M2 is also replayed as a **shadow** column that never
alters the fold's decision or reported forecast. This is exchangeable-season
LOSO, not chronological validation.

### 3.2 Chronological evaluation (for the legacy GAM)

The IRVRI legacy GAM is a single daily series refit on the trailing 365 days;
it cannot use other seasons. It is compared only on seasons where PAGe is also
trained on earlier seasons only:

- **Tier 1 (required):** `2025-26`. Its Workflow A fold is already
  chronological.
- **Tier 2 (required; Lennon, 2026-09-15):** `2022-23`, `2023-24`, `2024-25`,
  each with an additional PAGe kit trained on all earlier principal seasons
  (expanding window). Tier 2 kits are evaluation-only and are not Workflow A
  folds. `2022-23` is trained on 7 pre-pandemic seasons. They use the same fixed recipe (full retuning inside each kit) and July-start seasons, the same origin window and scoring rows as Section 5.2, and the same daily-data cutoff rule.

### 3.3 Final operational kit (Workflow B)

The recipe runs once on all 11 seasons to produce the 2026-27 kit. It has no
performance estimate of its own; Workflow A is its estimate.

## 4. Comparators

| Model | Role | Data | Design | Tuning |
|---|---|---|---|---|
| IRVRI legacy GAM (`irvri_adapter_gam()`) | **Operational baseline** | Daily by age | Chronological tiers (3.2); refit at every origin | None; production settings (`num_days = 365`, 14-day knots, summer thinning, three strata) |
| Calendar-week binomial GAM | Registered v1.4 primary comparator, now secondary | Weekly | Workflow A | `k_week` {6, 8, 10} x `k_signal` {4, 6, 8}, inner LOSO; one-SE rule as v1.4 (simplest setting within one inner-season SE of the minimum; ties by complexity, then configuration ID) |
| IRVRI mvgam, one specification | Statistical time-series comparator (supplement) | Weekly (PAGe input) | Chronological seasons 2022-23 to 2025-26 only (`history = "prior_only"`); refit at every origin; MCMC rules below | `mod2AR`, fixed before any evaluation run (see below) |
| Persistence | Floor | Weekly | Both designs | None |
| FluSight-style baseline | Standard external benchmark | Weekly | Both designs | None: median = last observed positivity; predictive quantiles from the empirical distribution of week-to-week positivity changes in the training data at the same horizon, symmetrized |
| Seasonal naive (Jeffreys-pooled training seasons at the same July-season `weekF`) | Floor | Weekly | Workflow A | None |
| M1 only | Internal reference | Weekly | Both designs | From recipe |

Removed from v1.4: lagged elastic net, historical-analogue continuation,
gradient-boosted tree (D-15).

**Information set and cadence (disclosed asymmetries).**

| Model | Training span | Seasons pooled | Resolution | Refit cadence | Row anchor |
|---|---|---|---|---|---|
| PAGe | 10 (or earlier, Tier 2) whole seasons | Yes | Weekly, all ages | Once per season; weekly state updates | Own detected ignition |
| M1 only | As PAGe | Yes | Weekly | Once per season | PAGe rows |
| IRVRI legacy GAM | Trailing 365 days | No | Daily, by age stratum | Every origin | PAGe rows |
| IRVRI mvgam | All earlier principal seasons (target masked after origin) | Yes | Weekly | Every origin (MCMC) | PAGe rows |
| Calendar GAM | 10 whole seasons | Yes | Weekly | Once per season | PAGe rows |
| Persistence / seasonal naive | Origin value / training seasons | No / yes | Weekly | None | PAGe rows |

Per-origin refitting gives the IRVRI comparators a refresh advantage; the
legacy GAM has a shorter information span and finer resolution. Scored rows
are anchored at PAGe's detected ignition, so the row set is not neutral. These
are stated limitations. Legacy GAM strata used are recorded from the data at
freeze.

**mvgam specification.** `mod2AR` (IRVRI `R/wf_train.R`: binomial,
season random effect, cyclic seasonal trend smooth with season-specific
deviations, AR(1) latent trend), fixed by the project lead on 2026-09-15
before any evaluation run, on the rationale that it is IRVRI's default
specification in its operational as-of-week comparisons. No flu pilot and no
outer-result-based choice. Informative priors, if used, are re-derived inside
each fold's training seasons; otherwise default priors.

**mvgam MCMC rules.** Chains may be shortened and warm-started from the
previous origin's fit, with chain count, warmup, and sampling length fixed
before evaluation `[FREEZE: chains, warmup, samples]` after a pilot on a
season that is not scored (`[FREEZE: pilot season]`, trained on its earlier
seasons only). Every fit passes a diagnostics gate: R-hat < 1.01 for all
monitored parameters and effective sample size at or above
`[FREEZE: ESS threshold]`. Failed fits are rerun once with longer prespecified
chains `[FREEZE: fallback lengths]`; fits failing again are recorded as
unavailable with reason `mcmc_diagnostics`. Diagnostics are reported per fit.

## 5. Outcomes and scoring

### 5.1 Score

Bernoulli cross-entropy per week, clipped to `[1e-12, 1 - 1e-12]`:
`CE = -q log(p_hat) - (1 - q) log(1 - p_hat)`, `q = y/N` at the target week.
Season score = phase-weighted mean over the season's scored rows with weights
from Section 2; seasons then averaged with equal weight.

**Probabilistic scores (secondary, all models).** Each model's predictive
distribution for target positivity is summarised by quantiles at levels
0.01, 0.025, 0.05, 0.10, ..., 0.95, 0.975, 0.99 (23 levels). For PAGe, M1,
calendar GAM and seasonal naive, the predictive distribution is
`Binomial(N_target, p_hat) / N_target`, conditional on the realized target
test count; a sensitivity uses the origin-week count. This binomial predictive
ignores parameter uncertainty in `p_hat` and is labelled as such. The IRVRI
legacy GAM and mvgam use their posterior predictive draws; the FluSight-style
baseline uses its own quantiles. Reported: weighted interval score (WIS) on
the positivity scale with the same phase weights and aggregation as 5.1,
empirical coverage of the central 50% and 95% intervals, and interval width.

### 5.2 Common rows

Rows are keyed by `season`, `origin_week_start_date`, `h`,
`target_week_start_date`. All models in a contrast are scored on identical
rows (Lennon, 2026-09-15): every origin from the week of
PAGe's detected ignition to the last season week whose target is observed,
`h` in {1, 2}; the phase weights (Section 2) set the emphasis. A row is
scorable when the target has `N > 0` (reason code `zero_tests` otherwise) and
a forecast is available from every model in the contrast
(forecast-availability contract). The PAGe-only recipe score uses all PAGe
scorable rows; each paired contrast uses the intersection for that pair.

All rows, including unavailable forecasts and failures, stay in the canonical
table with reason codes; unavailable rows are excluded from scores, never
imputed. A season whose paired score cannot be formed (no PAGe ignition, or no
common rows) is reported as a pipeline failure, shown in every season-level
table, and excluded from that contrast's mean with the count stated; the
contrast does not stop (D-21). For week-53 seasons (`2014-15`, `2025-26`),
rows outside the alignment domain are counted per season
`[FREEZE: domain 1-52 or nW(Y); season_calendar.R:85 uses 52]`.

For the legacy GAM, rows whose target week ends after the daily data end
(2026-03-28) are not scorable; the Tier 1 coverage (rows, phases covered) is
reported, and a full-season weekly-only contrast (PAGe versus weekly
comparators) is a sensitivity.

### 5.3 Primary comparisons

Two co-primary descriptive blocks (Lennon, 2026-09-15):

1. **Operational baseline:** season-equal mean of
   `L(PAGe) - L(legacy GAM)` on the four chronological seasons
   `2022-23` to `2025-26` (Tiers 1 and 2), with every season's value shown.
2. **Recipe performance:** Workflow A season-equal PAGe score across 11 folds,
   with the paired contrasts against calendar GAM, persistence, seasonal
   naive, FluSight-style baseline and M1 only. The supplementary mvgam
   comparison uses the four chronological seasons of block 1.

Negative contrasts favour PAGe. All summaries are descriptive: season values,
mean, median, SD, IQR, range, and leave-one-season-out means. No p-values,
confidence intervals, power, or superiority decisions.

### 5.4 Sensitivities (same rows)

- Sensitivity recipe with M1 `k_ref = 20`, `slope_weight = 12` (prespecified, D-32) `[DECISION: design and seasons where it is run]`.
- Legacy weights (2 for target weeks 0-12 after detected ignition, 1 later).
- Registered v1.4 primary line: h2, origins ignition to +12, trial-weighted.
- Test-count-weighted phase score.
- Legacy GAM contrast scored against daily-aggregated weekly targets.
- Without `2025-26` (exposure influence).
- Fold-specific M0-generated training labels in Workflow A (one extra 11-fold run). Label shifts `-1` / `+1` week are run in simulation only.
- Structural ablations: no M1 alignment in Workflow A (one extra 11-fold run); no ignition gate and no alignment uncertainty in simulation only; bias off is a grid value (D-22).

### 5.5 Stage and adoption-rule evidence

- M0: signed and absolute ignition error, miss rate, per fold.
- M1: weighted and unweighted peak-week MAE, per fold.
- Gate: per fold inner gain versus outer gain of M2 over M1 (shadow when
  kept); always-M1, always-M2, and gate policies on identical rows; number of
  harmed seasons; selected hyperparameters and boundary expansions across
  folds. A gain-threshold curve may be shown only as post hoc description.

### 5.6 Secondary

h1 and h2 separately; phase strata (rise, turning, decline); positivity MAE;
legacy GAM pre-ignition forecasts alone; weekly paired differences over time;
runtime per training run and per weekly update. The fitted-mean bands
(`eta +/- 1.96 se`) are not reported as predictive intervals; the predictive
quantiles of 5.1 are used instead.

## 6. Reporting and interpretation

1. Prior-cycle results are reported, if at all, only as a labelled historical
   record and never pooled with new-cycle results.
2. The 2025-26 fold is labelled exposed in every table.
3. Real-time application 2026-27 (section 6.1).
4. Claims are limited to Ontario influenza. RSV and other pathogens are out of
   scope.
5. Simulation evidence (separate simulation protocol) bounds generalization
   claims.
6. Reporting follows the EPIFORGE 2020 checklist (Pollett et al., PLOS Med
   2021, doi:10.1371/journal.pmed.1003793), including retrospective versus
   prospective status, horizon justification, benchmark, uncertainty, data and
   code availability, and generalisability.
7. Placement for *Epidemics*: main text reports the two co-primary blocks,
   persistence, seasonal naive, FluSight-style baseline, M1 only, WIS and
   coverage, and M0/M1 stage summaries; supplement reports mvgam, calendar GAM
   details, the no-M1 ablation, M0-label sensitivity, weight and window
   sensitivities, simulation, and package details.

### 6.1 Real-time application, 2026-27

A separate section and results block, distinct from the retrospective
evaluation. Here training and evaluation are separated in time rather than by
an outer holdout: the model is trained once on all 11 eligible seasons
(Workflow B final kit, section 3.3) and evaluated on the new 2026-27 season as
it happens. There is no outer fold and no held-out historical season. Results
are labelled real-time and never pooled with the retrospective blocks.

- **Models:** the frozen 2026-27 final kit, M1 only from the same kit, the
  production IRVRI legacy GAM as run operationally, persistence, and the
  FluSight-style baseline. The kit identity is recorded before the first
  forecast; no refit, retuning, or kit change during the season. An unplanned
  change ends that model's real-time record and is reported.
- **Logging:** every weekly forecast (all models, h1 and h2, quantiles) is
  written to an append-only log with forecast timestamp, data-vintage
  timestamp, input checksum, and kit/code identity before the target week's
  data exist. Forecasts not logged in time are excluded and counted.
- **Data:** the weekly feed and daily extract as available at each origin
  (real-time vintages, including reporting delay). Scoring uses the data
  available at the analysis date, with a final-data rescore when the season
  closes.
- **Scores:** the same phase-weighted log loss, WIS and coverage as section 5.
  Phases need the observed peak, so scores before the peak is confirmed are
  labelled provisional.
- **Extent reported:** the season up to the latest data available at
  submission, stated with its analysis date; later weeks are added in revision
  or an update.
- **Operational outcomes:** missed weeks, pipeline errors, late data, and M0
  not detecting ignition are reported, not removed.

## 7. Reproducibility

One immutable results directory per analysis with one canonical prediction
table (keys of 5.2 plus model ID, configuration ID, kit identity, weights
version, timing mode, gate decision, shadow flag, fit status, runtime). The
manifest records protocol checksum, code commit, package and dependency
versions, platform, seeds, data checksums, and table/figure code. Private
rows stay outside the repository; only aggregates are published.

## 8. Amendment rule

After freeze, changes before outcomes are opened require a new version with
date, rationale, affected estimand, and a list of results visible. Changes
after outcomes are opened are sensitivity analyses or a new cycle.

## Freeze checklist

- [ ] Phase 1 and season fixes committed and reviewed (commit SHA)
- [ ] Phase 2 scoring contract and Phase 3 M2 families committed
- [ ] Recipe manifest (grids, weights, gate, bias axis, timing, labels) with checksum
- [ ] Data builder commit and checksums (weekly and daily)
- [ ] Platform manifest
- [x] Decisions (Lennon, 2026-09-15): origin window; ablations; primary structure; Tier 2; mvgam `mod2AR`; calendar-GAM one-SE; label sensitivities
- [ ] Adapter code for legacy GAM and mvgam reviewed on synthetic data
- [ ] Project-lead sign-off with date and time
