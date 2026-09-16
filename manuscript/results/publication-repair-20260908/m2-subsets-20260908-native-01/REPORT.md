# M2 optional-term subset development experiment

This is a conditional development artifact using frozen M0/M1 artifacts. It is not a promotion or confirmation result.

Run directory: /home/yeli/repos/PAGe/manuscript/results/publication-repair-20260908/m2-subsets-20260908-native-01
Outer seasons: 11; configurations: 16; elapsed seconds: 562.028

## Locked specification

The saved M1 logit is a mandatory binomial offset. Four switches are shared across h1/h2: a ridge-penalized horizon intercept, horizon-specific shrinkage smooths for z (EMA logit positivity), u (weeks since the first M0 declaration), and d (adjacent-week z growth). k=3, bs='ts', REML, gamma=1.4; training seasons receive equal total trial weight.

Selection is minimum equal-season inner NLL separately by horizon, with ties resolved by fewer enabled components and deterministic configuration ID. The all-off candidate is exactly M1 and is not fitted.

## Results

See aggregate.csv, selected.csv, outer.csv, timing.csv, and lost_rows.csv. best_observed_subset is exploratory only and was not used for primary selection.

## Provenance and limitations

Declarations were independently recomputed from each season's own unseen replay M0 rows and matched to the saved locked declaration. The runner did not use retrospective phase labels, refit M0/M1, or inspect outer outcomes for configuration selection. Historical outer seasons and upstream M0/M1 choices remain conditional development context.

Previous native-02 offset columns were joined on matched season-origin-horizon keys and are reported with population=matched_previous. Static-template/fallback M1 rows and nonadjacent growth rows are reported in lost_rows.csv; no candidate failures are silently omitted.

## Numeric comparison

Equal-season mean Bernoulli NLL / MAE on the primary rows were:

| variant | h1 NLL | h1 MAE | h2 NLL | h2 MAE |
|---|---:|---:|---:|---:|
| M1 | 0.443750 | 0.031232 | 0.460079 | 0.050304 |
| selected16 | 0.442907 | 0.027198 | 0.457201 | 0.041542 |
| raw M2 | 0.443892 | 0.030146 | 0.458218 | 0.044964 |
| complete M2 | 0.447485 | 0.040079 | 0.462821 | 0.054065 |
| previous offset smooth | 0.443390 | 0.029552 | 0.459201 | 0.047712 |
| previous selected | 0.443390 | 0.029552 | 0.459285 | 0.047943 |

Selected16 NLL deltas versus M1 were -0.000843 (h1) and -0.002877 (h2). It was worse than M1 in 1/11 seasons for each horizon. The exploratory outer-selected subset reached 0.442510 (h1) and 0.456029 (h2), but was not used by the locked rule.

Selected configuration frequencies were identical by horizon: `i0_z0_u1_d1` 7/11, `i0_z1_u0_d1` 1/11, `i1_z0_u1_d1` 1/11, `i1_z1_u0_d1` 1/11, and `i1_z1_u1_d1` 1/11. Here `i`, `z`, `u`, and `d` indicate the four switches in the locked specification.

Per-season selected16 minus M1 deltas (NLL; MAE) were:

| season | h1 NLL | h1 MAE | h2 NLL | h2 MAE |
|---|---:|---:|---:|---:|
| 2012-13 | -0.001734 | -0.010071 | -0.004213 | -0.015838 |
| 2013-14 | -0.001768 | -0.005528 | -0.005869 | -0.014759 |
| 2014-15 | -0.000984 | -0.005873 | -0.003884 | -0.015146 |
| 2016-17 | -0.001968 | -0.007436 | -0.006087 | -0.019453 |
| 2017-18 | +0.001471 | +0.006000 | +0.006997 | +0.015287 |
| 2018-19 | -0.000059 | -0.002051 | -0.000828 | -0.003202 |
| 2019-20 | -0.000146 | -0.000008 | -0.001293 | -0.001790 |
| 2022-23 | -0.000279 | -0.000703 | -0.001957 | -0.004162 |
| 2023-24 | -0.000589 | -0.003337 | -0.001468 | -0.004538 |
| 2024-25 | -0.000020 | -0.000114 | -0.000091 | +0.001102 |
| 2025-26 | -0.003199 | -0.015251 | -0.012960 | -0.033880 |

## Fit and integrity audit

All 176 outer configuration fits converged; no inner cells failed. EDF ranged from 0 to 13.95 (median 5.89). One fit emitted the compact warning category `Fitting terminated with step failure - check results carefully`; its fit remained marked converged and is retained in timing.csv. Lost-row accounting found 0 fallback/static-template rows, 0 nonadjacent-growth rows, and 363 unavailable target-boundary rows (the same rows are also flagged as invalid target keys), with no silent candidate-specific dropping. The primary population contains 139 h1 and 138 h2 rows; matched previous comparators use the same counts.

The independent score audit in audit_recomputed_scores.csv matches stored scores to maximum absolute differences below 5e-16 for NLL and 5e-17 for MAE. audit_integrity.csv records exact all-off/M1 identity and 11/11 prefix-safe feature checks. Compute elapsed time was 562 seconds under single-thread BLAS/OMP; the watchdog log is watchdog.tsv with resource samples in watchdog_resources.tsv.
