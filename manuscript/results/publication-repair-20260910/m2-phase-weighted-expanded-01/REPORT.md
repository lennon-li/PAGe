# M2 optional-term subset development experiment

This is a conditional development artifact using frozen M0/M1 artifacts. It is not a promotion or confirmation result.

Run directory: manuscript/results/publication-repair-20260910/m2-phase-weighted-expanded-01
Outer seasons: 11; configurations: 686; elapsed seconds: 30627.9

## Locked specification

The saved M1 logit is the mandatory binomial offset and the all-zero candidate is exact M1. The grid searches a ridge-penalized horizon intercept plus per-term k_z, k_u, and k_d values; zero omits a term and positive values create horizon-specific shrinkage smooths for z (EMA logit positivity), u (weeks since the first M0 declaration), and d (adjacent-week z growth). The tested basis values are 
0, 3, 4, 5, 6, 7, 8
; REML estimates smoothing penalties and EDF. Training seasons receive equal total trial weight.

Boundary audit status: review_required. See boundary_audit.csv; a selected positive edge requires an expanded pre-holdout run.

Selection is minimum equal-season inner NLL separately by horizon, with ties resolved by fewer enabled components and deterministic configuration ID. The all-off candidate is exactly M1 and is not fitted.

## Results

See aggregate.csv, selected.csv, outer.csv, timing.csv, lost_rows.csv, and training_declarations.csv. best_observed_subset is exploratory only and was not used for primary selection.

## Provenance and limitations

For every outer season, training phase was recomputed at each saved M1 origin by applying that outer kit's frozen M0 parameters to the corresponding training prefix through that origin. The outer target used its own completed unseen replay declaration only. No retrospective phase labels, M0/M1 refits, or outer outcomes entered configuration selection; historical outer seasons and upstream M0/M1 choices remain conditional development context.

Previous native-02 offset columns were joined on matched season-origin-horizon keys and are reported with population=matched_previous. Training declaration lineage is in training_declarations.csv; static-template/fallback M1 rows, unavailable phase rows, and nonadjacent growth rows are reported in lost_rows.csv; no candidate failures are silently omitted.
