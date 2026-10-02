# Simplified M2 comparison

Status: `complete_diagnostic_only`. This is a bounded, post-holdout comparison and is not a production promotion or prospective confirmation.

## Design

- 11 complete exchangeable outer seasons; each frozen kit supplies 10 M2 training seasons and the current outer target season is excluded from the fit.
- Candidates: archived M1 alone; M1-logit offset plus penalized horizon intercepts; and that model plus horizon-specific `s(z_ema, by = lead, bs = "ts", k = 3)`.
- The fitted correction uses REML, `gamma = 1.4`, equal total trial weight per training season, no spread term, no residual term, no season random effect, no online bias correction, and no post-peak switch.
- Inner LOSO selects minimum equal-season NLL separately for h1 and h2; exact ties prefer M1, then intercept, then smooth. Feature clamping is recomputed from each inner training split and the outer target is clamped to the full outer-training range.
- Primary outer origins are `t_since = 0:12`, scored with trial-weighted NLL and MAE within season, then equal-season averaged. Available rows are h1 = 139 and h2 = 138; the h2 count matches the expected 138-row reconciliation.

## Equal-season outer results

| Horizon | Variant | NLL | MAE |
|---:|---|---:|---:|
| 1 | M1 | 0.443750 | 0.031232 |
| 1 | offset + intercept | 0.443606 | 0.030095 |
| 1 | offset + smooth | **0.443390** | **0.029552** |
| 1 | current raw M2 | 0.443892 | 0.030146 |
| 1 | current complete M2 | 0.447485 | 0.040079 |
| 1 | selected simplified model | **0.443390** | **0.029552** |
| 2 | M1 | 0.460079 | 0.050304 |
| 2 | offset + intercept | 0.459821 | 0.049205 |
| 2 | offset + smooth | 0.459201 | 0.047712 |
| 2 | current raw M2 | **0.458218** | **0.044964** |
| 2 | current complete M2 | 0.462821 | 0.054065 |
| 2 | selected simplified model | 0.459285 | 0.047943 |

The inner rule selected the smooth candidate for all 11 h1 folds and for 8 of 11 h2 folds; it selected M1 for h2 in 2013–14, 2019–20, and 2023–24. The selected h2 aggregate is therefore slightly worse than the smooth candidate because it follows the pre-specified inner rule, not the outer results.

Among the five fixed comparator variants (M1, both simplified candidates, current raw M2, and current complete M2), the observed outer NLL winners were:

| Horizon | M1 | Intercept | Smooth | Current raw | Current complete |
|---:|---:|---:|---:|---:|---:|
| 1 | 2 | 1 | 2 | 6 | 0 |
| 2 | 0 | 1 | 2 | 7 | 1 |

These are descriptive outer comparisons after the holdouts had already been inspected, not valid new tuning evidence.

Per-season selected-model metrics:

| Season | h1 choice | h1 NLL | h1 MAE | h2 choice | h2 NLL | h2 MAE |
|---|---|---:|---:|---|---:|---:|
| 2012–13 | smooth | 0.540880 | 0.032368 | smooth | 0.545830 | 0.050050 |
| 2013–14 | smooth | 0.464329 | 0.042304 | M1 | 0.472678 | 0.068340 |
| 2014–15 | smooth | 0.560169 | 0.047872 | smooth | 0.588700 | 0.075495 |
| 2016–17 | smooth | 0.491830 | 0.041955 | smooth | 0.514000 | 0.043770 |
| 2017–18 | smooth | 0.364691 | 0.014429 | smooth | 0.382809 | 0.025463 |
| 2018–19 | smooth | 0.378505 | 0.017684 | smooth | 0.401668 | 0.028120 |
| 2019–20 | smooth | 0.405582 | 0.017609 | M1 | 0.407857 | 0.031638 |
| 2022–23 | smooth | 0.347721 | 0.029663 | smooth | 0.345294 | 0.052281 |
| 2023–24 | smooth | 0.334801 | 0.022861 | M1 | 0.348064 | 0.044170 |
| 2024–25 | smooth | 0.448861 | 0.026551 | smooth | 0.472930 | 0.047330 |
| 2025–26 | smooth | 0.539921 | 0.031779 | smooth | 0.572310 | 0.060720 |

## Complexity and timing

The run completed in 93.36 seconds wall time under R 4.6.1 with single-threaded BLAS/OpenMP settings. Fold elapsed time ranged from 4.25 to 9.41 seconds; measured inner fitting time totaled 58.75 seconds. Outer-fit intercept EDF ranged from 1.62 to 1.99 and smooth EDF from 2.34 to 3.95. Training rows ranged from 582 to 638, with 0–2 rows dropped per outer fold for missing saved M1 values.

## Verification

- Targeted prototype tests: 18 expectations passed, 0 failures, 0 warnings; local source loaded with `devtools::load_all("PAGe")`.
- `styler` completed on the touched package R and test files; both comparison scripts parsed successfully.
- No-fit preflight: 11 kits, 10 training seasons per kit, unique saved-M1 keys, valid replay fields, and positive available rows in both horizons.
- Independent score audit: 1,662 saved score rows recomputed from the private predictions; maximum NLL difference `5.0e-16`, maximum MAE difference `4.9e-17`.
- All 22 saved candidate fits converged. The fitted correction models contain no `logit_f_eff` coefficient; M1 remains a formula offset.
- Private predictions and fits are under `private/.gitignore`. No M0/M1 fitting, retuning, production-kit overwrite, promotion, commit, or push occurred.

## Provenance and limitations

The authorized raw input SHA-256 is `fa8add1b253944df5d853a2fb0456d7ac368657e073da0d97f909be95ca59c54`. The complete source, registry, kit, and replay hashes are recorded in `status.json`; the final source hashes are also recorded there. The watchdog record is `/tmp/page-m2-simplified-native-02-watch/watchdog.tsv`.

This comparison is conditional on archived M0/M1 artifacts and historical M2 feature settings. Archived M1 values were reused and were not newly season-cross-fitted, so this is not fully nested prospective validation. Previously inspected outer seasons remain development data, and 2025–26 is partial. The observed raw-M2 h2 lead is therefore a result of this diagnostic comparison, not a production recommendation. No candidate is promoted by this run.
