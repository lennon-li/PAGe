# Operational Methods: Weekly Positivity Forecasting for 2026-27

Draft for epidemiologists and surveillance analysts who use the weekly
outputs. Source citations are kept in HTML comments. Pending values are marked
`[PENDING]`; unverified claims are marked `[VERIFY]`.

## Purpose and outputs

The pipeline forecasts seasonal respiratory virus percent positivity 1 and 2
weeks ahead from weekly surveillance data. Each weekly run produces:

- an estimated percent positivity for each horizon (h1 = 1 week ahead, h2 = 2
  weeks ahead), with an uncertainty band;
- an ignition status: whether M0 has declared the transition into the epidemic
  phase;
- an ignition-week estimate reported as a decimal value with the one-week
  interval that contains it, not a single exact week;
- a peak-timing estimate from M1 alignment. The user-facing one-week interval
  format for peak timing is `[PENDING]` (not yet implemented in the output).

<!-- timing_training_adapter_v2.R:28-33 (target is the midpoint of the normalized pair; lower/upper labels retained); timing_training_adapter_v2.R:57-66 -->

## Data

The input is a weekly table of positive tests (`y`) and total tests (`N`) for
each season-week. The canonical season coordinate is `weekF`, and the season
starts at MMWR week 27. Historical surveillance observations are private and
are not distributed with the package; supply an authorized CSV path
explicitly.

<!-- METHODS.md:57 (weekF from declared season origin, start_week = 27); IGNITION_LABEL_PROTOCOL.md:5-6 (season start at MMWR week 27); GOVERNANCE_DECISIONS.md:31 (G-07: do not release private Ontario rows) -->

## Pipeline

The pipeline is the ordered chain M0 (ignition detection) -> M1 (phase
alignment) -> M2 (forecast correction). A frozen seasonal kit is trained once
and reused every week. Weekly production runs update only the detector,
alignment, and online-correction state; they never refit or retune the frozen
kit. This is the package's default deployed behavior. The 2026-27 kit is
planned to use fractional timing (`timing_mode = "fractional"`); the package
default remains legacy integer timing. `[PENDING]` final configuration.

<!-- AGENTS.md current status (frozen-GAM deployment default; weekly refit is explicit compatibility behavior); run_2025_ultimate.R:5-9 (boundary expansion, adoption gate, fallback, strict replay delegated to the frozen API); timing_pipeline_v2.R:1-5 (legacy archive path is the default; fractional helpers are opt-in) -->

## Fractional (decimal) timing

The timing coordinate treats week `w` as the half-open interval `[w, w + 1)`,
so `19.2` means 20 percent of the way from the start of observed week 19 to
the start of observed week 20. Because surveillance is aggregated by week, the
true onset or peak can lie anywhere inside a week. In fractional mode, M0 runs
the usual weekly detector and then interpolates the first adjacent crossing of
the classifier-probability threshold to give a decimal ignition estimate
(`iWeek_hatF`) together with its one-week bracket (`iWeek_bracket_lo`,
`iWeek_bracket_hi`). Training targets are the reviewed label placed at the
middle of its week (label + 0.5). Users therefore see an interval rather than
a false exact week.

<!-- timing_coordinates_v2.R:1-8 (week w is [w, w+1); 19.2 = 20 percent); timing_pipeline_v2.R:41-51 (decimal iWeek_hatF); timing_pipeline_v2.R:90-93 (estimate and bracket); timing_training_adapter_v2.R:28-33 -->

## Training and selection

Principal seasons are 2012-13, 2013-14, 2014-15, 2016-17, 2017-18, 2018-19,
2019-20, 2022-23, 2023-24, 2024-25, and 2025-26. Fixed exclusions are
2011-12, 2015-16, 2020-21, and 2021-22. The operational kit is trained on all
eligible seasons. Its hyperparameters are chosen by leave-one-season-out tuning
within those seasons: each candidate is scored on every season while trained
on the others. Tuned axes are expanded one adjacent valid step when a boundary
winner is found, and a minimum-gain rule governs adoption. In the 2025-26 gate
protocol the M1 minimum gain is 0.05 weeks of peak-timing error and the M2
minimum gain is 0.0012 in log loss (NLL) overall, with 0.002 at h2. If M2 does not beat M1 by the required gain, M1 is
used (the "keep M1" fallback). Final 2026-27 kit hyperparameters are
`[PENDING]`.

<!-- run_2025_ultimate.R:35-63 (protocol arguments and season sets); ANALYSIS_DEVIATIONS_2026-09-08.md:29 (M1 min_gain 0.05); ANALYSIS_DEVIATIONS_2026-09-08.md:48-53 (practical-gain rule, k_ref bounds); ANALYSIS_DEVIATIONS_2026-09-08.md:65-69 (11 holdouts, fixed exclusions) -->

## Weighting

M2 candidates are scored with 2:1 early-versus-late weighting: weight 2 for
weeks 0-12 after ignition, weight 1 afterward, and weight 0 before ignition.
Weeks count equally regardless of test volume (`score_scale = "equal_week"`),
and each season contributes equally. M1 candidates are scored on peak-timing
error instead.

<!-- run_2025_ultimate.R:46-63 (pre_ignition_weight 0, early_weight 2, early_max_t_since 12, late_weight 1, score_scale equal_week); ANALYSIS_DEVIATIONS_2026-09-08.md:48 (season-equal weighted objective) -->

## Uncertainty and limitations

- M1 `logit_spread` is the weighted disagreement among alignment templates.
  It is an uncertainty covariate for M2, not a full predictive interval.
- M2 bands from `eta +/- 1.96 * se.fit` are conditional fitted-mean bands, not
  validated predictive intervals. They do not fully propagate observation,
  upstream, selection, online-correction, or revision uncertainty, and
  predictive coverage is not demonstrated.
- The 2025-26 season supplies only its available observations; equal season
  membership is not equal observational coverage.
- Surveillance revisions and backfill can change recent weeks. `[VERIFY]`
- The model is trained and evaluated for influenza only; it is not validated
  for RSV or other pathogens.

<!-- METHODS.md:162-167 (logit_spread is template disagreement, not the complete predictive interval); ANALYSIS_DEVIATIONS_2026-09-08.md:113-118 (conditional fitted-mean bands, no demonstrated coverage); ANALYSIS_DEVIATIONS_2026-09-08.md:83-88 (partial 2025-26; equal membership is not equal coverage) -->

## Governance

A candidate kit must pass the release gates before replacing the incumbent.
The package function `check_promotion()` encodes the operational
candidate-versus-incumbent release controls, including the relative-NLL gate.
Weekly outputs are reviewed before publication. `[VERIFY]` for the weekly
review step.

<!-- GOVERNANCE_DECISIONS.md:54-65 (check_promotion encodes operational release controls; G-06 records the relative-NLL gate as operational, not a scientific threshold); GOVERNANCE_DECISIONS.md:94 (evaluation_gates.R) -->

## Status of this draft

Validation of the 2025-26 holdout run (r5) is in progress. Final kit
hyperparameters are NOT yet fixed. Every value that is pending is marked
`[PENDING]`.

<!-- parent-verified run state 2026-09-15: r5 launched 2026-09-15 01:49 UTC, status in progress -->

---

## Markers in this file

- `[PENDING]`: final 2026-27 kit hyperparameters.
- `[VERIFY]`: surveillance revisions/backfill behavior; RSV validation scope;
  weekly review-before-publication step.
