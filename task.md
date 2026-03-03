# Ignition Detection Parameter Tuning Task

## Context

We are tuning ignition detection parameters using objects and functions
already loaded from `data/data.RData`.

The `.RData` contains: - Data objects such as: `alignedD`,
`template_df`, etc. - Functions such as: `loso_M0v2`, `fitIgnition`,
`detectIgnitionBySeason_M0v2`, etc.

Use these existing functions.\
Do NOT rewrite the pipeline from scratch.

The authoritative model description and call squenece is in:
  
  -   `docs/flu_forecasting.qmd`

Read that file first before making any structural changes.

------------------------------------------------------------------------
  
  ## Definitions
  
  -   **Q_tune** = seasons used in LOSO tuning folds.
-   **Q_all** = ALL seasons in `alignedD`, INCLUDING `"2015-16"`.

Important:
  
  -   `"2015-16"` must be excluded from LOSO folds.
-   `"2015-16"` must be included in final evaluation (Q_all).

------------------------------------------------------------------------
  
  ## Starting Grid
  
  Start from the current grid:
  
  ``` r
grid_loso <- CJ(
  cls_thr   = c(0.20, 0.22, 0.24, 0.26, 0.28),
  p_thr     = c(0.008, 0.009, 0.010),
  prev_thr  = c(0.005, 0.006, 0.007),
  n_consec  = c(4L, 5L, 6L),
  L         = 2L,
  eps       = 0,
  K_sum     = c(4L, 5L, 6L),
  p_sum_thr = c(0.045, 0.050, 0.055, 0.060),
  N_req     = 4L,
  w_min     = 13L,
  w_max     = 30L,
  sorted = FALSE
)
```

You may:
  
  -   Expand locally around good regions.
-   Add or remove parameters if it improves generalization.
-   Keep search controlled (avoid exploding grid size unnecessarily).
We are on Windows PowerShell.
Use multicore parallelism, but do NOT use mclapply (no forking on Windows).
Prefer future::plan(multisession, workers = ncores) or PSOCK clusters.
Expose a --cores flag in scripts/auto_from_rdata.R and pass it into tune_args$ncores (and mgcv nthreads if relevant).
Default cores to 10 (or detectCores()).
------------------------------------------------------------------------
  
  ## Tuning Procedure
  
  1.  Run LOSO tuning using:
  
  ``` r
tuned <- loso_M0v2(
  dat  = alignedD,
  grid = as.data.frame(grid_loso),
  score_col = "p_cls_p",
  drop_seasons = c("2015-16"),
  exSeason_tune = NULL,
  fit_args = list(
    fit_base = TRUE, fit_slope = FALSE, fit_fs = FALSE,
    event_k = 1L, lead = 1L, A_pre = 6L, B_post = 6L,
    k_week = 6L, k_p = 8L, k_fs = 4L,
    select = FALSE, verbose = FALSE
  ),
  tune_args = list(
    miss_penalty = 20,
    lambda = 20,
    kappa = 2,
    gamma = 25,
    gamma_late = 25,
    iWeek = TRUE,
    ncores = 10L,
    verbose = FALSE,
    progress_every = 200L
  ),
  verbose = TRUE
)
```

2.  Fit ignition model on ALL seasons:
  
  ``` r
ign_fit_all <- fitIgnition(
  dat = alignedD,
  fit_base = TRUE, fit_slope = FALSE, fit_fs = FALSE,
  event_k = 1L, lead = 1L, A_pre = 6L, B_post = 6L,
  k_week = 6L, k_p = 8L,
  verbose = TRUE
)
```

3.  Detect ignition on ALL seasons:
  
  ``` r
det_all <- detectIgnitionBySeason_M0v2(
  ign_fit = ign_fit_all,
  params  = tuned$best_params,
  score_col = "p_cls_p",
  keep_signals = TRUE,
  iWeek = TRUE,
  verbose = TRUE
)
```

I have already ran this and my best params are

|          |      x|
|:---------|------:|
|cls_thr   |  0.260|
|p_thr     |  0.009|
|prev_thr  |  0.006|
|p_sum_thr |  0.050|
|eps       |  0.000|
|n_consec  |  5.000|
|L         |  2.000|
|K_sum     |  5.000|
|N_req     |  4.000|
|w_min     | 13.000|
|w_max     | 30.000|


 det_all$compare
    season iWeek_true iWeek_hat diff
1  2012-13         17        17    0
2  2013-14         20        20    0
3  2014-15         19        19    0
4  2015-16         27        14  -13
5  2016-17         19        19    0
6  2017-18         22        20   -2
7  2018-19         19        19    0
8  2019-20         21        21    0
9  2022-23         13        15    2
10 2023-24         19        20    1
11 2024-25         21        23    2
------------------------------------------------------------------------
  
  
  your job is to find the best set including 2015-16 in the evaluation
  
  
  ## Selection Criterion (CRITICAL)
  
  Selection must be based on **Q_all (ALL seasons including "2015-16")**.

Let `diff` be the column in `det_all$compare` representing predicted
minus truth.

Define:
  
  ``` r
abs_diff <- abs(det_all$compare$diff)
max_abs_diff_all  <- max(abs_diff, na.rm = TRUE)
mean_abs_diff_all <- mean(abs_diff, na.rm = TRUE)
```

### Hard Constraint

The chosen parameter set must satisfy:
  
  ``` r
max_abs_diff_all <= 2
```

across ALL seasons.

### If No Grid Satisfies Constraint

If no parameter set satisfies `max_abs_diff_all <= 2`:
  
  -   Expand grid gradually around best region.
-   Re-run tuning.
-   Continue until:
  -   A satisfying set is found, OR
-   It is clearly infeasible within reasonable parameter ranges.

If infeasible, return the set minimizing `max_abs_diff_all`.

------------------------------------------------------------------------
  
  ## Tie-Break Rules
  
  Among parameter sets satisfying the hard constraint:
  
  1.  Minimize `mean_abs_diff_all`
2.  Then minimize LOSO score
3.  Prefer simpler parameter sets

------------------------------------------------------------------------
  
  ## Required Outputs
  
  Save to `results/`:
  
  1.  `leaderboard.csv` containing for each grid row:
  
  -   all grid parameters
-   LOSO score
-   max_abs_diff_all
-   mean_abs_diff_all

2.  `best_params.rds`

3.  `det_all_compare.csv`

4.  `run_meta.rds` describing:
  
  -   grid size explored
-   whether constraint satisfied
-   final metrics

------------------------------------------------------------------------
  
  ## Operational Rule
  
  Primary command to run and iterate on:
  
  ``` bash
Rscript scripts/auto_from_rdata.R --rdata=data/inputs.RData --out=results --mode=all
```

Repeat editing and re-running until:
  
  -   The hard constraint is satisfied, OR
-   You demonstrate infeasibility with evidence.

Do NOT change model structure unless explicitly necessary. Do NOT
silently relax the \<=2 constraint, prompt changes before implementation if you believe it is feasible.
