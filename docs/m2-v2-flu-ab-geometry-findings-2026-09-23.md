# M2-v2 influenza A/B reconstruction and geometry findings — 2026-09-23

## Scope

This audit reconstructs separate weekly Influenza A and Influenza B series for the 11 redesign seasons and asks whether M2-v2 should assume one shared curve family, partially pooled type-specific curves, or fully separate A/B curves.

The result is a clear two-part answer:

1. **A and B require separate timing/phase states.**
2. **After each type is aligned to its own peak, normalized A and B shapes are similar enough that partial pooling is the best starting model rather than two unrelated shape families.**

## Reconstructed panel

Target seasons:

- 2012-13
- 2013-14
- 2014-15
- 2016-17
- 2017-18
- 2018-19
- 2019-20
- 2022-23
- 2023-24
- 2024-25
- 2025-26

The governed reconstruction contains 574 season-week rows, exactly matching the current Influenza-A campaign row count.

### Historical seasons through 2024-25

The manuscript-prepared historical dataset contains:

- Influenza A positives (`y`);
- influenza tests (`N`);
- Influenza B positives (`pos_flub`);
- reported A and B percent positivity.

For the first 10 redesign seasons, the A `y/N/p` values match the current M1 campaign **exactly**.

The historical table uses one `test_flu` denominator for both A and B. B count-ratio positivity and the reported B percentage differ by at most 0.000499 in probability (0.05 percentage points), consistent with the reported percentage being rounded to one decimal place.

For reconstruction and geometry, historical B uses the observed B positive count with the historical shared influenza-test denominator/proxy. This denominator regime is explicitly flagged; it must not be silently treated as identical to modern type-specific ORVT denominators in a final likelihood.

### 2025-26

2025-26 A and B are reconstructed from the frozen ORVT audit feed.

Unlike the historical table, ORVT has **type-specific A and B test denominators**. In 2025-26 the A and B denominators are not identical.

The 2024-25 overlap confirms that this is a denominator-schema distinction rather than a B-count disagreement:

- historical and ORVT B positive counts agree exactly in the overlap;
- ORVT A and B denominators differ by as much as 510 tests/week;
- historical B reported positivity versus ORVT B positivity can differ by about 0.000794 (0.079 percentage points) because of the denominator difference and historical rounding.

Therefore the eventual M2-v2 likelihood needs an explicit measurement/denominator regime. Geometry can be compared now; a single homogeneous binomial denominator assumption across all years would be incorrect.

## Retrospective peak geometry

Both types were smoothed with the restrained retrospective GAM procedure using k=8 for the point geometry. k=5/6/8/10 sensitivity is retained separately.

### Timing

Influenza B peaks **more than one week later than A in 10 of 11 seasons**.

- median `B peak - A peak`: **13.48 weeks**;
- mean lag: **12.10 weeks**;
- range: **-0.47 to +23.12 weeks**.

The only season without a materially later B peak is 2017-18:

- A peak: 31.64;
- B peak: 31.17;
- lag: -0.47 weeks.

Examples of strongly separated waves:

- 2012-13: B +14.66 weeks;
- 2013-14: B +13.68;
- 2014-15: B +13.48;
- 2016-17: B +12.53;
- 2018-19: B +14.25;
- 2022-23: B +23.12;
- 2025-26: B +16.98.

**Conclusion:** the current Influenza-A M1 timing handoff cannot be used as the Flu-B phase clock. B needs either its own M0/M1 timing stage or an explicitly tested B-relative timing model. Given the size and variability of the observed A-B lag, a fixed A-to-B offset is not adequate as the primary design.

## Amplitude

B is usually substantially lower-amplitude than A, but not always.

Median retrospective peak-amplitude ratio:

`B peak / A peak = 0.276`

Examples:

- 2018-19: 0.067;
- 2025-26: 0.124;
- 2024-25: 0.144;
- 2012-13: 0.204;
- 2013-14: 0.799;
- 2017-18: 0.921.

This is strong evidence that M2 amplitude needs a type effect and season-level adaptation. A common fixed amplitude scale for A and B is not credible.

## Peak-relative normalized shape

After each type is aligned to **its own** retrospective peak and divided by its own peak amplitude, A and B are much more similar.

Across tau = -8 to +8 weeks:

- median within-season A-vs-B normalized-shape correlation: **0.952**;
- median within-season normalized RMSE: **0.135**;
- pooled median A-vs-B curve correlation: **0.924**;
- pooled median curve RMSE: **0.104**.

Median half-maximum width:

- A: **11.29 weeks**;
- B: **10.43 weeks**.

This is not evidence that A and B are identical. Several seasons show meaningful normalized-shape differences, especially 2025-26, 2022-23, 2023-24, 2017-18, and 2019-20. It does show that a strongly regularized shared-shape component is plausible after type-specific timing and amplitude are separated.

## Smoothing sensitivity

Using k=5/6/8/10 and flagging peak ranges >1 week:

- A ambiguous peaks: 4/11;
- B ambiguous peaks: 6/11.

B ambiguity is expected to be greater because many B waves are lower-amplitude and late-season. B timing should therefore carry first-class uncertainty rather than one deterministic peak label.

B seasons with >1-week smoothing range include:

- 2012-13;
- 2018-19;
- 2019-20;
- 2022-23;
- 2023-24;
- 2024-25.

## M2 architecture decision

The empirical geometry supports the following hierarchy.

### Timing: separate

Use a **B-specific causal timing state**. The existing A M1-v2 handoff remains the A timing state.

The B timing implementation should initially reuse the restrained M1-v2 architecture where possible, but be trained/evaluated independently on B because:

- B peak is usually 10-20+ weeks after A;
- B peak uncertainty is larger;
- B can occasionally peak concurrently with A;
- a fixed lag model would fail in 2017-18 and substantially misrepresent several other seasons.

### Shape: partially pooled starting point

For M2-v2, the preferred first structured candidate remains:

`g_k(tau) = g_shared(tau) + delta_k(tau)`

with strongly regularized `delta_A` and `delta_B`.

This is justified because normalized own-peak shapes are correlated while not identical.

The frozen ablation ladder still needs:

- C1 pooled A/B shape;
- C2 partially pooled A/B shape;
- C3 fully separate A/B shape.

Nested LOSO decides whether C2 is actually better than C1/C3.

### Amplitude: type-specific and adaptive

Amplitude should not be pooled tightly across A/B. Current type-specific level, recent growth, and type-specific peak/phase state should dominate +1/+2 predictions.

H1N1/H3N2 remains a separate within-A modifier and should not be conflated with A/B type.

## Measurement implication for M2 likelihood

The 11-season A/B panel has two denominator regimes:

1. historical shared influenza-test denominator/proxy for B;
2. modern ORVT type-specific denominators.

Before a final count likelihood is frozen, M2-v2 should compare:

- a quasi-binomial / overdispersed likelihood robust to denominator-regime differences;
- a model using reported type-specific positivity as the response with test-volume weights;
- a count model with an explicit denominator-regime effect/sensitivity analysis.

Do not claim a single exact B binomial observation process across all 11 seasons without resolving this measurement change.

## Immediate next step

Build **B-specific M0/M1 timing prototypes** before fitting the structured M2 curve models.

The first question is whether the existing restrained M0/M1 machinery transfers to B with acceptable causal detection and peak-timing error despite low-amplitude seasons. Required outputs:

- expert/retrospective B ignition strategy;
- B M0 strict LOSO detection performance;
- B M1 strict LOSO peak timing and uncertainty;
- explicit low-signal failure states.

In parallel, M2 B0/B1 state-only baselines can be built using current B level and growth without waiting for a final B timing model. Those baselines are essential to quantify the incremental value of B timing.

## Artifacts

Generated under:

`artifacts/m2-v2-flu-ab-geometry-v1/`

Key files:

- `flu_ab_weekly_v1.csv` / `.rds`;
- `source_manifest.csv`;
- `orvt_2024_denominator_overlap_audit.csv`;
- `peak_sensitivity_k5_k6_k8_k10.csv`;
- `peak_sensitivity_ranges.csv`;
- `type_geometry_k8.csv`;
- `season_ab_geometry_k8.csv`;
- `peak_aligned_normalized_shape_grid.csv`;
- `peak_aligned_normalized_shape_medians.csv`;
- `summary_metrics.csv`.

Reconstruction/audit script:

`scripts/reconstruct_flu_ab_geometry_v1.R`
