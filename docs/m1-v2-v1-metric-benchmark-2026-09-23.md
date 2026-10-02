# M1-v2 against the frozen M1-v1 metric — 2026-09-23

## Benchmark definition

The frozen M1-v1 contract identifies the active benchmark as:

`primary_prepeak_integer_mae_season_balanced_early_weighted`

The metric is evaluated on 92 primary origins across the 10 legacy seasons. For each season, origins run from the frozen integer M0 lock through the frozen integer peak, inclusive. Per-origin weight is:

`exp(-(0.1 * (origin_weekF - m0_locked_weekF))^2)`

The season-level weighted absolute errors are averaged equally across seasons.

Frozen M1-v1 value:

- active integer metric: **1.1561215766545 weeks**;
- secondary decimal metric: **1.25244569886422 weeks**.

The replay script asserts exact reproduction of 1.1561215766545 before candidate scoring.

## Exact frozen-contract replay

M1-v2 was replayed through the package API using:

- the same 10-season universe;
- strict outer LOSO (9 training seasons / 1 held-out season);
- the same 92 primary origins;
- the same frozen M0 anchor;
- base-R rounding of the posterior mean for the active integer metric;
- current k=8 retrospective GAM peak truth only for M1-v2 training.

When scored against the immutable frozen v1 observed-argmax truth:

- M1-v1: **1.1561**;
- M1-v2 uncalibrated: **1.8366**;
- M1-v2 nested bias calibrated: **1.4800**.

Therefore M1-v2 does **not** beat the immutable frozen benchmark truth. This must remain explicit.

The primary reason is a target-definition mismatch. Frozen v1 truth is the observed weekly positivity argmax (with a local parabolic decimal companion), while M1-v2 is trained to a smoothed latent k=8 GAM peak. The largest disagreements occur in seasons such as 2013-14, 2014-15, and 2023-24.

An oracle global time offset cannot solve this mismatch: the best frozen-truth active score over offsets from -2 to +1 weeks is approximately **1.403**, still well above 1.156.

## Same metric formula, same 92 origins, current truth

To separate model quality from the changed scientific target, both models were also scored on the same 92 origins with the same M1-v1 metric formula but against the current k=8 GAM peak truth.

Uncalibrated:

- frozen v1 predictions rescored: **1.3403**;
- M1-v2: **1.4837**.

M1-v2 has a systematic late bias of roughly +0.6 to +0.8 weeks depending on posterior formulation.

### Strict nested calibration

A training-only calibration experiment was run. For each outer held-out season:

1. only the other 9 legacy seasons were available;
2. inner predictions were generated with libraries excluding both the outer season and each inner target season;
3. calibration used a fixed a-priori subset: the first four primary origins per inner season;
4. each inner season contributed equal total weight;
5. the learned mean signed bias was subtracted from the outer M1-v2 posterior mean.

The learned outer-fold corrections ranged from approximately **-0.72 to -0.96 weeks**, with no held-out outcome leakage.

Current-truth results on the same 92 origins:

- uncalibrated M1-v2 active integer metric: **1.4837**;
- nested-calibrated M1-v2 active integer metric: **1.3044**;
- frozen v1 predictions rescored against current truth: **1.3403**.

Thus, under the current scientific peak truth and the exact M1-v1 metric formula, nested-calibrated M1-v2 is modestly better than v1.

Native continuous current-truth MAE also improves:

- uncalibrated: **1.3801**;
- nested calibrated: **1.2349**.

This calibration result is exploratory until incorporated as a governed training-time step and replayed end-to-end.

## Full 11-season current extension

The M1-v1 metric formula was extended to all 11 current seasons. This is not the frozen contract and must not be labeled as such.

For each season:

- start origin = cross-fitted current M0 integer detection;
- end origin = rounded current k=8 GAM peak;
- origins are inclusive;
- early weighting uses the current integer M0 detection;
- M1-v2 training is strict 10-season LOSO.

103 origins are scored.

Uncalibrated:

- active integer metric: **1.5288**;
- native decimal metric: **1.3495**.

Strict nested training-only bias calibration across all 11 seasons:

- active integer metric: **1.3732**;
- native decimal metric: **1.2462**.

Outer-fold calibration offsets range from approximately **-0.55 to -0.84 weeks**.

The calibration helps strongly in 2013-14, 2014-15, 2019-20, 2023-24, and 2025-26, while it worsens some already-early/long-shape seasons (notably 2016-17, 2017-18, 2018-19, and 2024-25). This means a single training-fold mean-bias correction is useful but not the final calibration model.

## Other explored explanations

### Future conditioning

Allowing recent-past candidate peak times (unconditioned peak posterior) did not materially improve the v1 metric. The gap is not primarily caused by future-only candidate support.

### Amplitude prior

Increasing the amplitude-prior standard deviation helps only modestly. Best explored current-truth active score was about **1.419**, insufficient to explain the bias.

### Two peak-anchored PCs

A second constrained shape PC raises explained normalized-shape variance to approximately **99.6-99.8%**, but does not improve the benchmark materially:

- frozen integer metric: ~1.806;
- current-truth integer metric: ~1.453.

Therefore missing low-rank shape flexibility is not the dominant source of the remaining error.

## Interpretation

Two statements must remain separate:

1. **Immutable historical benchmark:** M1-v2 does not beat M1-v1's 1.156 score when judged against v1's old observed-argmax truth.
2. **Current scientific target:** using the same v1 metric formula and same origins, strictly nested-calibrated M1-v2 reaches 1.304 versus 1.340 for v1 predictions when both are judged against the current latent GAM peak truth.

The frozen benchmark remains valuable as a continuity comparator, but it cannot be treated as the truth target for a model whose explicit purpose is latent peak-time inference.

## Next M1 work

Do not add more PCs or AUC features.

The next controlled experiment should replace the scalar training-fold bias correction with a very small calibration model learned strictly inside training folds. Candidate inputs should be limited to quantities available at forecast time and already produced by M1, for example:

- posterior interval width / skew;
- elapsed time since M0;
- current estimated amplitude nuisance;
- possibly a low-amplitude indicator learned from the posterior rather than eventual subtype.

Any calibration model must be nested inside outer LOSO. A constant global correction chosen from held-out results is not acceptable.
