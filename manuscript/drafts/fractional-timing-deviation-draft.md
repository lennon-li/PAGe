# Analysis deviation: fractional ignition timing

Recorded: 2026-09-15. Status: documentation of an executed methodology
change and its disposition. Not a new preregistration, not an amendment to the
frozen primary analysis, and not a claim of improvement.

## What changed

The current cycle moves M0 ignition timing from an integer week estimate to a
fractional (decimal) `timing_mode`. The legacy integer estimate is retained as
`iWeek_hat`; fractional mode adds a decimal estimate `iWeek_hatF` and the
one-week bracket that contains it.

<!-- timing_pipeline_v2.R:41-51; timing_pipeline_v2.R:90-93; 2025/run_2025_ultimate.R:46-63 -->

## Why

Surveillance is aggregated by week, so the true onset or peak lies inside a
week, not on a week boundary. The coordinate treats week `w` as `[w, w + 1)`,
so `19.2` means 20 percent from the start of week 19 to the start of week 20.
Reporting a decimal estimate plus its one-week interval avoids presenting a
false exact week and gives users an interval instead.

<!-- timing_coordinates_v2.R:1-8; timing_training_adapter_v2.R:28-33 -->

## When it was adopted

The fractional timing API entered the package on 2026-09-14, after the
integer-cycle outer-holdout results (execution record 2026-09-02; Results
draft 2026-09-08) and after an integer 2025-26 replay
(`20260912T025500Z-ultimate-2025-26-r3`) were available. The change was
therefore made with knowledge of earlier holdout results. The fractional cycle
is a new development cycle: its holdouts cannot be presented as confirmation of
a prespecified choice, and integer-cycle results remain labelled as the prior
cycle and are not mixed with fractional results.

<!-- parent-verified cycle boundary; 2025/run_2025_ultimate.R:35-63 -->

## What it affects

- M0 targets and estimate: the fractional detector runs the existing detector,
  then interpolates the first adjacent classifier-probability crossing of the
  class threshold and emits the decimal `iWeek_hatF`; training
  targets become fractional (in the 2025-26 fold, training targets were the
  integer label plus 0.5, e.g. 2012-13 target 18.5).
- M1 anchor/coordinates: the fractional branch sets training `iWeekF` from the
  fractional timing truth and uses `anchor = median` of the training-season
  targets, replacing the integer anchor.
- M2 inputs: M2 consumes the alignment-derived features produced under the
  fractional M1 coordinates.

<!-- timing_pipeline_v2.R:53-90; timing_training_adapter_v2.R:12-26 and :39-73; m1_loso.R:317-346 (fractional branch sets iWeekF from timing_truth and anchor = median target) -->

## Evidence, stated without a superiority claim

The current evidence is mixed. In the 2025-26 fold over the same 25-spec M1
grid (inner-tuning scores, not holdout performance), fractional beat legacy in
16 of 25 specs (median weighted peak-week MAE difference -0.021 weeks); seasons
split 5/5. The adopted minimum-gain
specification scored 1.238 weeks fractional versus 1.213 legacy, so fractional
was not adopted on demonstrated improvement. The fractional M0-only outer run
completed 10 of 10 holdouts (decimal estimates 15.06-23.21) but lacks
source/package hashes. The prior governed 2025-26 replays both kept M1 because
M2 did not pass the minimum gain.

<!-- parent-verified: 16/25 specs, median -0.021 weeks, 5/5 seasons, adopted spec 1.238 vs 1.213; m0-outer-20260914T212734Z-fractional-r1 10/10, estimates 15.06-23.21, no hashes; prior replays 20260912T025500Z-ultimate-2025-26-r3 and 20260913T180000Z-ultimate-2025-26-fractional-e2e-r4 kept M1 -->

## What remains pending

- Label `+1` sensitivity. `[PENDING]`
- Methods text describing fractional mode. `[PENDING]`
- Regeneration of results under the fractional cycle. `[PENDING]`
- Source/package hashes for the fractional M0-only run. `[PENDING]`

<!-- parent-verified pending list -->

## Proposed replacement paragraph for METHODS.md "M0: prospective ignition detection"

> M0 detected the transition into the epidemic phase. Its detector combined
> five signals: a population-level ignition-classifier score, a rolling
> positivity sum, a smoothed positivity level, cumulative
> denominator-weighted prevalence, and a consecutive-increase signal. The
> detector evaluated an eligible within-season window and declared ignition at
> the earliest week for which at least `N_req` of the five gates were
> satisfied. In fractional timing mode, M0 additionally interpolated the first
> adjacent classifier-probability crossing of the class threshold to produce a
> decimal ignition-week estimate `iWeek_hatF`, bounded inside the one-week
> interval `[iWeek_bracket_lo, iWeek_bracket_hi]`. The detector's threshold and
> window parameters were selected only within the declared training seasons.
> The classifier was trained on season-specific windows around the reference
> ignition labels, and its population-level score excluded season-specific
> effects when transferred to a target season. Once the detector locked an
> ignition coordinate, that value was used by downstream weekly processing
> unless a prespecified, documented override was part of the analysis. A missed
> or unavailable ignition was retained as a pipeline failure; it was not
> silently removed.

<!-- adapted from METHODS.md:121-138; fractional additions from timing_pipeline_v2.R:41-51,90-93 and timing_coordinates_v2.R:1-8 -->

---

## Markers in this file

- `[PENDING]`: label `+1` sensitivity; Methods text update; results
  regeneration; fractional M0-only source/package hashes.
