# main.R  —  Full LOSO grid tuning for lambda_w (Stage-2 M1)
#
# Layout expected on server:
#   test/
#     R/ignitionTraining.R
#     R/module_training.R
#     R/prospective_training.R
#     test.RData
#     main.R          <- this file
#
# Run from the test/ directory:
#   cd test && Rscript main.R

setwd(dirname(normalizePath(if (interactive()) "." else sys.frame(0)$ofile, mustWork = FALSE)))

# ── packages ────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(dplyr)
  library(mgcv)
  library(data.table)
})

# ── source functions ─────────────────────────────────────────────────────────
source("R/ignitionTraining.R")
source("R/module_training.R")
source("R/prospective_training.R")   # wins for shared function names

# ── load data ────────────────────────────────────────────────────────────────
load("test.RData")   # loads: alignedD, template_df, ignD
cat("Seasons:", paste(sort(unique(alignedD$season)), collapse = ", "), "\n")

# ── worker count ─────────────────────────────────────────────────────────────
nc <- max(1L, parallel::detectCores() - 1L)
cat("Workers:", nc, "\n\n")

# ── prospective features (needed by both paths) ──────────────────────────────
alignedD_prosp <- add_prospective_derivs_link(alignedD, k = 5L, eps = 1e-6, min_obs = 4L)

# ── output directory ─────────────────────────────────────────────────────────
out_dir <- "results"
dir.create(out_dir, showWarnings = FALSE)

# ============================================================
# PATH 1: tune_stage2_loso_shift_template  (prospective_training.R)
#
# Tunes: shift (delta), ramp K, template smoothness k_f, EWMA alpha, lambda_w
# Uses:  REML + fs smoothing term (k_s = 6 in default spec_base)
# ============================================================

cat("=== PATH 1: tune_stage2_loso_shift_template ===\n")

t1 <- system.time({
  tuned1 <- tune_stage2_loso_shift_template(
    dat           = alignedD_prosp,
    template_df   = template_df,
    shift_grid    = -2:2,                         # template alignment shifts
    K_grid        = 3:5,                          # ramp widths
    k_f_grid      = c(6L, 8L),                   # template smooth knots
    alpha_grid    = c(0.15, 0.25, 0.35),         # EWMA alpha
    lambda_w_grid = c(0, 0.05, 0.1, 0.2),        # time-decay rates
    eval_window   = 8L,                           # score only first 8 weeks post-ignition
    testSeason    = NULL,                         # NULL = all available seasons
    num.cores     = nc,
    verbose       = TRUE
  )
})
cat("PATH 1 elapsed:", round(t1["elapsed"] / 60, 1), "min\n")

saveRDS(tuned1, file.path(out_dir, "tuned1.rds"))
cat("Saved:", file.path(out_dir, "tuned1.rds"), "\n\n")

# Quick summary
r1 <- tuned1$results[tuned1$results$ok, ]
agg1 <- aggregate(mean_nll ~ lambda_w + delta + K + k_f + alpha_state,
                  data = r1, FUN = mean)
agg1 <- agg1[order(agg1$mean_nll), ]
cat("PATH 1 — top 10 specs by mean NLL:\n")
print(head(agg1, 10))

# ============================================================
# PATH 2: tune_stage2_loso_spec_grid_parallel  (module_training.R)
#
# Tunes: shift (delta), ramp Kr, template smoothness k_f, EWMA alpha,
#        pre-ignition buffer Kb, lambda_w
# Uses:  fREML + no fs term (k_s = 0) for speed
# ============================================================

cat("\n=== PATH 2: tune_stage2_loso_spec_grid_parallel ===\n")

source("R/module_training.R")   # restore module version of stage2_make_spec etc.

sg <- expand_grid_specs(
  delta_grid  = -2:2,
  Kr_grid     = 3:5,
  T_grid      = "S",
  k_f_grid    = c(6L, 8L),
  alpha_state = c(0.15, 0.25, 0.35),
  Kb_grid     = c(1L, 2L),
  k_w_grid    = 8L,
  k_s_grid    = 0L,    # no fs term (faster; add 6L if compute allows)
  k_e_grid    = 6L,
  k_n_grid    = 6L,
  k_1_grid    = 6L,
  k_2_grid    = 0L,
  verbose     = TRUE
)
cat("Base spec_grid rows:", nrow(sg$grid), "\n")

t2 <- system.time({
  tuned2 <- tune_stage2_loso_spec_grid_parallel(
    alignedD_prosp  = alignedD_prosp,
    template_df     = template_df,
    ignD            = ignD,
    spec_grid       = sg,
    seasons         = NULL,                      # NULL = all available seasons
    k_t             = 8L,                        # score window (weeks post-ignition)
    w_early         = 1,                         # uniform weighting in score window
    lambda_w_grid   = c(0, 0.05, 0.1, 0.2),
    workers         = nc,
    chunk_size      = 8L,
    nthreads        = 1L,
    verbose         = TRUE
  )
})
cat("PATH 2 elapsed:", round(t2["elapsed"] / 60, 1), "min\n")

saveRDS(tuned2, file.path(out_dir, "tuned2.rds"))
cat("Saved:", file.path(out_dir, "tuned2.rds"), "\n\n")

# Quick summary
bsg2 <- as.data.frame(tuned2$by_spec_grid)
cat("PATH 2 — top 10 specs by mean NLL:\n")
keep <- intersect(c("spec_id", "lambda_w", "delta", "Kr", "alpha_state", "Kb", "mean_nll"), names(bsg2))
print(head(bsg2[order(bsg2$mean_nll), keep], 10))

# ── save session info ────────────────────────────────────────────────────────
saveRDS(
  list(
    time_path1_min = round(t1["elapsed"] / 60, 2),
    time_path2_min = round(t2["elapsed"] / 60, 2),
    n_specs_path1  = length(tuned1$specs),
    n_specs_path2  = nrow(bsg2),
    session        = sessionInfo()
  ),
  file.path(out_dir, "run_meta.rds")
)

cat("\n=== DONE ===\n")
cat("Results in:", normalizePath(out_dir), "\n")
