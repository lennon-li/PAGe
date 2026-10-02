# M2-v2 reviewed design — 2026-09-23

This is the parent-reviewed synthesis after delegated architecture design. It supersedes any recommendation that assumes influenza A and influenza B share one curve family by default.

## 1. Core objective

M2-v2 forecasts influenza positivity at +1 and +2 observed weeks. Unlike M1, which is primarily a timing/phase system, M2 owns short-horizon amplitude and trajectory prediction.

The design must support influenza A and influenza B as potentially different epidemic processes:

- different peak amplitudes;
- different rise/decline shapes;
- different peak timing;
- overlapping or sequential A/B waves within one season;
- different within-A subtype composition (H1N1/H3N2), which is a separate question from A-vs-B.

No eventual season dominance label may be used at runtime.

## 2. Blocking data-contract work

The current M1 campaign table is influenza-A only: `season, weekF, y, N, p`.

The archived Ontario ORVT feed contains separate `Influenza A` and `Influenza B` rows, and the historical private data schema contains influenza-B fields, but B is not represented in the current canonical M1/M2 redesign table.

Before modeling:

1. reconstruct a governed weekly A/B historical table;
2. determine whether A and B have truly type-specific denominators or a shared influenza-test denominator;
3. document typing/reporting latency and whether type/subtype counts are available at the forecast origin;
4. preserve raw counts, not just percentages.

If A and B use separate denominators, use type-specific binomial likelihoods. If they are mutually exclusive positive categories under one shared denominator, use a multinomial/compositional likelihood or another coherent joint count model rather than pretending two independent binomials are independent.

## 3. Do not assume a common A/B curve

The model family should explicitly contain a pooling ladder:

### C0 — no historical curve

Pure short-horizon autoregressive/state baseline using current positivity, recent change, test volume, lead, and M1 phase features.

Purpose: establish how much curve structure is actually needed.

### C1 — pooled A/B curve

One peak-relative trajectory family shared across A and B, with type-specific amplitude/intercept only.

This is the strongest pooling model and a useful small-sample baseline, not the assumed truth.

### C2 — partially pooled A/B curves — preferred starting hypothesis

A shared population trajectory plus a regularized type-specific deviation:

`g_k(tau) = g_0(tau) + delta_k(tau)`

where `k in {A,B}` and `delta_k` is deliberately very low dimensional / strongly penalized.

Amplitude is separate:

`logit p_{s,k,t+h} = curve_k(phase_{s,k,t+h}) + season/type amplitude state + live residual state + lead effect`.

This lets B differ in shape when supported, while shrinking toward A/shared geometry when B information is sparse.

### C3 — fully separate A and B curve families

Independent A and B trajectory shapes, while retaining common software/evaluation machinery.

This is an ablation / upper-flexibility candidate. It should only become preferred if nested LOSO demonstrates stable improvement for B without material A degradation.

The pooling choice C1/C2/C3 must be selected strictly within training folds. Outer-season results cannot be used to choose the family.

## 4. Timing/phase is type-specific if the biology requires it

The current integrated M1-v2 is an influenza-A timing model. Its timing handoff must not silently be reused as the influenza-B phase truth.

For influenza A, M2-v2 should consume the existing M1-v2 handoff directly:

- calibrated peak mean;
- raw/calibrated intervals;
- weeks to calibrated peak;
- peak-within +1/+2/+3 probabilities;
- passage probability/state;
- locked peak where applicable.

For influenza B, there are three candidates to test after B data reconstruction:

1. **B-specific causal timing stage** using the same restrained M1-v2 architecture but B data;
2. **relative phase-offset model**, where B timing is represented as an estimated B-vs-A peak offset with strong shrinkage;
3. **no explicit B peak model**, using only B current level/growth and calendar/A-phase features as a baseline.

Do not force B onto A's peak clock. A season can have an A peak followed by a materially later B wave.

## 5. Minimal first M2-v2 model

Start simpler than the legacy multi-smooth GAM.

For type `k`, season `s`, origin `t`, horizon `h in {1,2}`:

`Y_{s,k,t+h} ~ Binomial(N_{s,k,t+h}, p_{s,k,t+h})`

and initially model change from the observed current state rather than absolute future level:

`logit(p_{t+h}) = logit(p_t^*) + beta_h + f_phase_k(phase_target) + beta_g * growth_t + beta_N * logN_t + b_{s,k}`

where:

- `p_t^*` is a stabilized current positivity estimate;
- `phase_target` is target-week phase derived from the appropriate causal timing state;
- `growth_t` is a restrained recent logit-scale change / EMA slope;
- `b_{s,k}` is a regularized season/type amplitude residual during training, excluded or integrated for a new season;
- `f_phase_k` follows the C1/C2/C3 pooling ladder.

The current observed level is intentionally dominant for a +1/+2 forecast. Historical curve shape should provide phase-aware drift, not override the actual current level.

## 6. Candidate feature set

### Required causal features

- type: A or B;
- horizon: +1/+2;
- origin and target week;
- current type-specific positivity/counts;
- recent 1-week change on stabilized logit scale;
- optional 2-week EMA level and slope;
- current test volume;
- M0/M1 state appropriate for that type;
- target-week weeks-to-peak / weeks-since-peak;
- passage state;
- M1 timing uncertainty width.

### Optional A/B composition feature

At origin `t`, if type counts are actually reported by then:

`share_A_t = A_positive_t / (A_positive_t + B_positive_t)`

or a stabilized trailing version.

It is causal only if the typing data were available at that forecast origin. Reported final-season A/B dominance is forbidden.

### Optional A-subtype feature

H1N1/H3N2 is separate from A/B. Test only as a weak, penalized within-A amplitude/variance modifier using contemporaneously available subtype counts.

Do not use eventual H1N1/H3N2 dominance and do not hard-split the A model by subtype with 11 seasons.

## 7. M1 uncertainty propagation

Do not reduce M1 to one timing point.

Predeclared progression:

- U0: calibrated mean only;
- U1: mean + interval width / passage probability as features;
- U2: posterior integration — evaluate the M2 phase term across M1 timing candidates and average predictions by M1 posterior mass.

U2 is conceptually preferred if it materially improves calibration, but U1 should be implemented first because it is auditable and cheap.

For B, uncertainty comes from the B timing representation, not automatically from A's M1 posterior.

## 8. Strict cross-fitting requirements

For outer test season `o`:

- no M0/M1/type-curve/M2 parameter may use season `o`;
- every M2 training row from season `r` must receive upstream M0/M1 features generated by models that excluded `r`;
- during inner selection with validation season `v`, upstream training-row features for season `r` must exclude `o`, `v`, and `r`;
- A and B rows from an excluded season are excluded together where a shared/hierarchical component is fitted.

Cache artifacts by full exclusion set + type schema + data hashes + upstream model identities.

## 9. Evaluation

Use one candidate-independent origin ledger.

Report at minimum, separately for A/B and h1/h2:

- binomial/log predictive score or NLL;
- MAE in percentage points;
- RMSE;
- bias;
- interval coverage and width;
- forecast availability;
- performance by phase relative to peak/passage.

Season-balanced aggregation is primary so seasons with more observations do not dominate.

Run both:

1. exchangeable-season outer LOSO;
2. expanding-window prior-seasons-only replay.

Do not select a model on a blended A+B score alone. Require no material degradation in either type, or predeclare a joint acceptance rule.

## 10. Predeclared ablation ladder

- B0: persistence / current-level baseline;
- B1: current level + growth, no M1;
- B2: B1 + M1 phase/timing features;
- B3-C1: shared A/B phase curve + type amplitude;
- B3-C2: partially pooled A/B phase curves;
- B3-C3: separate A/B curves;
- B4: best B3 + contemporaneous A/B share;
- B5: best B3/B4 + M1 uncertainty feature/integration;
- B6: A-only, add causal H1N1/H3N2 composition modifier.

Legacy M2 remains a sealed comparator for the A stream.

## 11. Failure/fallback contract

Expected states include A active/B pre-ignition, B active/A passed, only one type circulating, and mixed circulation.

Explicit reasons:

- `type_data_unavailable`;
- `type_denominator_unavailable`;
- `type_timing_unavailable`;
- `composition_not_yet_reported`;
- `insufficient_historical_B_support`;
- `target_out_of_season`;
- `upstream_identity_mismatch`.

Fallback must be visible. For example, if B timing is unavailable, use a declared B state-only model rather than substituting A timing silently.

## 12. Recommended sequence

1. Reconstruct and audit the historical A/B count table.
2. Plot/quantify A and B separately after each type's own retrospective peak alignment: raw amplitude, normalized shape, peak offsets, width, rise/decline asymmetry, and within-season A-B peak lag.
3. Establish B0/B1 baselines.
4. Decide whether B needs its own M0/M1 timing based on those empirical curves and causal detectability.
5. Implement C1/C2/C3 as a deliberately small pooling ladder.
6. Build strict cross-fitted M1/M2 training rows.
7. Run nested LOSO and chronological replay.
8. Only then test contemporaneous A/B share and within-A subtype composition.
9. Freeze the simplest model that materially improves numeric forecasts and calibration without hiding B degradation behind A performance.

## 13. Current working recommendation

Do not split M1-A by H1N1/H3N2.

Do not force influenza B onto the influenza-A M1 timing curve.

For M2, begin from a **partially pooled A/B curve architecture (C2)**, but keep both pooled (C1) and separate (C3) shapes as predeclared competing candidates. The data should decide how much shape sharing is warranted.

The immediate engineering task is therefore not a GAM rewrite. It is the A/B historical data reconstruction plus a peak-aligned A-vs-B geometry audit. That audit determines the B timing contract and the correct M2 likelihood before model fitting begins.

## 13.1 Empirical A/B geometry update — 2026-09-23

The first governed A/B reconstruction and retrospective geometry audit is now complete (`artifacts/m2-v2-flu-ab-geometry-v1/`). It materially sharpens the design:

- Influenza B peaks >1 week later than A in **10/11** target seasons.
- Median B-minus-A peak lag is **13.48 weeks** (mean 12.10; range -0.47 to +23.12).
- Median B/A retrospective peak-amplitude ratio is **0.276**.
- After aligning each type to its own peak and normalizing by its own peak amplitude, median within-season A-vs-B shape correlation is **0.952** and the pooled median-curve correlation is **0.924**.
- B retrospective peak truth is more smoothing-sensitive: 6/11 B peaks versus 4/11 A peaks have a k=5/6/8/10 range >1 week.
- Historical B uses the legacy shared influenza-test denominator/proxy, whereas modern ORVT exposes type-specific A/B denominators. The likelihood must preserve this denominator-regime distinction.

**Updated design decision:** separate A and B timing/phase states are now required by the observed geometry. The preferred shape candidate remains C2 (partially pooled A/B curves), with C1 and C3 retained as nested-LOSO competitors. Flu B must not consume the Flu-A M1 clock as if it were its own phase.

## 13.2 Flu-B causal timing update — 2026-09-23

The B-specific timing/baseline prototype is complete (`artifacts/m2-v2-flu-b-timing-baselines-v1/`). It changes the recommended B timing architecture:

- A direct A-style M0-B transfer is poor: provisional strict-LOSO ignition MAE **3.00 weeks**, median **2.87**, max **8.64**, with 1/11 miss.
- Conditional on a good B history window, M1-B contains real peak information: oracle-activation season-balanced MAE **1.26 weeks**, versus **2.12 weeks** for a LOSO median ignition-to-peak duration rule.
- Feeding raw M0-B activations into M1-B degrades season-balanced MAE to **1.92 weeks**.
- A simpler causal availability design works better: a four-week B activity gate plus a short recent-history lookback, with no formal M0-B ignition state. The development candidate `max p_B >= 2%`, four-week B positives `>=40`, four-week lookback is available in 10/11 seasons and gives approximately **1.00-week season-balanced M1-B peak MAE**. The one unavailable season is the trace 2018-19 B wave (~1.2% retrospective peak).
- This timing result is insensitive to the modern denominator regime: the same candidate on the 10 historical shared-denominator seasons gives **1.03-week** season-balanced MAE.
- B passage is not ready. The transferred hybrid rule produces one false-early lock; a conservative `P(passed)>=0.95` + immediate-decline rule has zero false-early locks but only 6/10 by peak+2. B passage therefore remains unavailable/experimental.
- B0 persistence remains the numeric hurdle. The first persistence-plus-growth B1 is worse on both all-week and provisional-epidemic MAE.

**Updated B timing contract for M2 development:**

- `timing_unavailable` until a causal B activity gate opens;
- `timing_active` thereafter, using a B-specific M1-F posterior with a short gate-relative lookback and B-specific amplitude integration support;
- `passage_unavailable` by default; do not lock a B peak yet;
- timing abstention always falls back to the numeric B baseline and never removes a scoring row.

The next numeric experiment is B2: test whether the B timing posterior improves +1/+2 forecasts over B0 persistence. Only after B2 clears that hurdle should C1/C2/C3 historical A/B curve pooling be fitted.


## 13.3 Superseding B numeric/timing resolution — 2026-09-25

The later strict B baseline/timing work (`docs/m2-v2-b-timing-and-baselines-findings-2026-09-23.md`) supersedes the earlier development-only conclusions in §13.2 where they conflict.

Current B policy is:

- **B1 is the always-available numeric baseline**, not persistence alone. The retained B1 is current stabilized B level plus one- and two-week logit growth and horizon, with current level entering as an offset.
- Strict exchangeable LOSO B1 versus persistence improves season-balanced MAE by approximately **9.6% at +1** and **19.9% at +2**.
- Expanding-window chronological B1 versus persistence improves MAE by approximately **13.7% at +1** and **15.5% at +2**.
- A universal B-M0 ignition detector is **not promoted**. The later provisional-target LOSO diagnostic remains too unstable for use as a universal B activation clock.
- B timing is operationally available only after the conservative causal epidemic gate: origin week >=18, trailing four-week B positives >=40, and trailing four-week maximum B positivity >=5%.
- B timing is a **soft posterior state**, not a governed discrete peak lock. The passage-lock diagnostic is safe but too slow.
- Strict nested model selection rejects B timing at **+1 in every outer fold** and selects a timing correction at **+2 in every outer fold**. Low-signal/timing-unavailable B remains exactly B1.

Therefore the current M2-v2 B routing contract is:

- B +1: exact B1;
- B +2 before/without the reviewed gate: exact B1;
- B +2 after the gate: B1 plus a B-specific timing/shape correction;
- never substitute the A clock for B timing.

## 13.4 C1/C2/C3 resolution and chronological update — 2026-09-25

The C1/C2/C3 shape-pooling ladder has now been evaluated under both exchangeable and prior-seasons-only contracts.

### Exchangeable strict outer evaluation

Training-only inner shape-family selection chose **C2 in all 11 outer folds**. Aggregate selected-family gains versus the matched type-specific state/growth baseline were approximately:

- A +1: **10.7% MAE improvement**;
- A +2: **8.65%**;
- B +1: **exact baseline by policy**;
- B +2: **7.71%**.

### Prior-seasons-only chronological replay

The parent-reviewed replay is `scripts/run_m2_ab_curve_ratio_chronological_c123_v2.R` with artifacts in `artifacts/m2-v2-ab-curve-ratio-chronological-c123-v2/`.

Key chronology constraints are explicit:

- baseline learning begins only once >=3 prior seasons exist;
- shape-family selection requires >=4 prior seasons;
- governed A timing requires >=5 prior seasons because the inner prior-only M0 LOSO is rank-deficient before then;
- every A M0/M1/calibration fit uses only prior seasons;
- every B timing library uses only prior seasons and the current target prefix;
- timing-unavailable rows are exact baseline fallbacks;
- B +1 is exact B1.

Training-only chronological family selection chooses:

- no family through 2016-17 because history is insufficient;
- C2 in 2017-18;
- C3 in 2018-19, with a very small inner-RMSE advantage over C2;
- C2 in every target season from 2019-20 through 2025-26.

Thus C2 is selected in **6 of 7** chronologically selectable seasons and is near-tied with C3 in the remaining season.

A fixed-C2 replay, preserving the same hard fallbacks and avoiding a runtime family selector, yields season-balanced chronological MAE changes versus the matched baseline:

- A +1: **1.23% improvement**;
- A +2: **6.75% improvement**;
- B +1: **0% / exact baseline**;
- B +2: **9.71% improvement**.

Among rows/seasons where a C2 correction is actually active rather than falling back:

- A +1: approximately **2.5%** MAE improvement, with mixed season-level robustness (4 better, 2 worse);
- A +2: approximately **10.4%** improvement, **6/6 active seasons better**;
- B +2: approximately **32.2%** improvement, **2/2 active seasons better**.

A +1 remains the robustness-sensitive branch: fixed C2 worsens 2018-19 slightly and worsens 2025-26 more materially, although there is no monotonic late-era degradation and the aggregate remains positive. A +2 and gated B +2 are the strongest supported C2 uses.

### Current research architecture decision

Promote **fixed C2** to the current **research M2-v2 curve family**. Do not carry the C1/C2/C3 selector into runtime; retain C1/C3 as evaluation/ablation comparators.

C2 means:

- a pooled A/B peak-relative log-drift template;
- a strongly constrained type-specific deviation, currently represented by a fixed 0.5 pooled/type shrinkage blend;
- current observed type-specific state remains the amplitude anchor;
- timing-unavailable cases fall back exactly to the type-specific state/growth baseline.

Production runtime promotion is still blocked on governance/packaging, explicit denominator-regime likelihood treatment, and stabilization/versioning of the B timing gate. The legacy M2 comparator is separately frozen in `docs/m2-v2-v1-metric-benchmark-2026-09-25.md`; raw legacy and M2-v2 metrics must not be compared without a matched ledger.
