#!/usr/bin/env Rscript
# ============================================================
# L2-fix smoke verification — v15-postfix best spec only
#
# Re-scores the single v15-postfix best spec under the L2-fixed eval loop
# (walk-forward estimateDerivs).  1 spec x 10 LOSO folds.
#
# Pre-L2 NLL (from data/nested_loso_v15_postfix_production.rds):  0.5959197
# Output: data/nested_loso_v15_postfix_l2verify.rds
#         data/nested_loso_v15_postfix_l2verify_ckpt.rds
# ============================================================

cat("=== L2-fix verification — v15-postfix best spec ===\n")
cat("Start:", format(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(PAGe)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(furrr)
  library(future)
  library(mgcv)
  library(MMWRweek)
  library(data.table)
})

for (f in c(
  "R/utils.R",
  "R/m0_retro.R", "R/flagIgnition.R",
  "R/m1_reference.R", "R/m1_reference_helpers.R",
  "R/m1_multi_template.R",
  "R/m2_spec_grid.R", "R/m2_training.R", "R/m2_nested_loso.R",
  "R/pipeline_bridge.R", "R/pipeline_runtime_helpers.R"
)) source(f)

n_cores <- max(1L, parallel::detectCores() - 1L)
cat("Cores available:", n_cores, "\n\n")

# ---- 1. Data ----
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

allD <- read.csv("data/flu_testing_data.csv") |>
  dplyr::select(
    season, week, year,
    start_year = seasonstart,
    date       = week_start_date,
    y          = pos_flua,
    N          = test_flu
  ) |>
  dplyr::mutate(
    neg     = N - y,
    date    = as.Date(date),
    nW_true = n_weeks_in_start_year(start_year),
    weekF   = ((week - 27L) %% nW_true) + 1L,
    p       = y / N
  ) |>
  dplyr::filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)
EXCLUDE_SEAS <- "2015-16"
flag_args <- list(
  p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L,
  min_window = 10L, w_min = 21L, w_max = 21L, d2_relax = -0.01
)

# ---- 2. Single spec grid (best spec from v15-postfix) ----
grid_v15_l2 <- tidyr::crossing(
  delta        = 0,
  Kr           = 1L,
  k_f          = 5L,
  k_e          = 2L,
  alpha_state  = 0.4,
  k_r          = 0L,
  k_de         = 0L,
  k_sp         = 2L,
  bias_alpha   = 0.5,
  bias_beta    = 0
)

cat("Verification grid: ", nrow(grid_v15_l2), "spec\n")

specs_l2 <- purrr::pmap(grid_v15_l2, function(delta, Kr, k_f, k_e, alpha_state,
                                                k_r, k_de, k_sp, bias_alpha, bias_beta) {
  stage2_make_spec(
    delta = delta, Kr = Kr, T = "S",
    k_f = k_f, k_e = k_e, alpha_state = alpha_state,
    k_r = k_r, k_de = k_de, k_sp = k_sp,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = bias_alpha,
    bias_beta  = bias_beta
  )
})
names(specs_l2) <- paste0(
  "d+", grid_v15_l2$delta,
  "_Kr", grid_v15_l2$Kr,
  "_kf", grid_v15_l2$k_f,
  "_ke", grid_v15_l2$k_e,
  "_as", grid_v15_l2$alpha_state,
  "_kr", grid_v15_l2$k_r,
  "_kde", grid_v15_l2$k_de,
  "_ksp", grid_v15_l2$k_sp,
  "_ba", grid_v15_l2$bias_alpha,
  "_bb", grid_v15_l2$bias_beta
)

cat("Spec name:", names(specs_l2), "\n\n")

test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("Test seasons (", length(test_seasons), "):", paste(test_seasons, collapse = ", "), "\n\n")

# ---- 3. Load M1 phase-1 cache ----
m1_cache_path <- "data/fresh_nested_loso_v15_phase1.rds"
if (!file.exists(m1_cache_path)) {
  stop("M1 phase-1 cache not found at: ", m1_cache_path)
}
m1_cache <- readRDS(m1_cache_path)
cat("Phase 1 cache loaded:", length(m1_cache), "folds.\n\n")

# ---- 4. Evaluate single spec across all LOSO folds ----
phase2_ckpt <- "data/nested_loso_v15_postfix_l2verify_ckpt.rds"

if (file.exists(phase2_ckpt)) {
  cv_results <- readRDS(phase2_ckpt)
  todo_spec_ids <- setdiff(names(specs_l2), names(cv_results))
  cat("Resuming:", length(cv_results), "done,", length(todo_spec_ids), "remaining\n\n")
} else {
  cv_results    <- list()
  todo_spec_ids <- names(specs_l2)
}

if (length(todo_spec_ids) > 0) {
  # Only 1 spec — no need for parallel outer loop; run sequentially
  spec_id  <- todo_spec_ids[[1L]]
  spec     <- specs_l2[[spec_id]]

  cat("Evaluating spec:", spec_id, "\n")
  cat("Folds: ", length(test_seasons), "\n\n")

  fold_scores <- vector("list", length(test_seasons))
  fold_preds  <- vector("list", length(test_seasons))
  names(fold_scores) <- names(fold_preds) <- test_seasons

  for (test_s in test_seasons) {
    cat(" Fold:", test_s, "... ")
    t0 <- proc.time()[["elapsed"]]
    fc <- m1_cache[[test_s]]

    m2_fit <- tryCatch(
      nested_loso_m2_train(
        fold           = fc$fold,
        m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
        spec           = spec,
        method         = "REML",
        verbose        = FALSE
      ),
      error = function(e) { cat("TRAIN ERROR:", conditionMessage(e), "\n"); NULL }
    )

    manual_labels_train_fold <- manual_labels[setdiff(names(manual_labels), test_s)]
    eval_out <- tryCatch(
      nested_loso_m2_eval_frozen_bias(
        allD                = allD,
        fold                = fc$fold,
        m2_fit              = m2_fit,
        m1_test_preds       = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
        spec                = spec,
        eval_window         = 12L,
        bias_alpha          = spec$bias_alpha,
        manual_labels_train = manual_labels_train_fold,
        manual_labels_test  = NULL,
        flag_args           = flag_args,
        verbose             = FALSE
      ),
      error = function(e) { cat("EVAL ERROR:", conditionMessage(e), "\n"); NULL }
    )

    elapsed <- round(proc.time()[["elapsed"]] - t0, 1)
    if (is.null(eval_out)) {
      fold_scores[[test_s]] <- tibble::tibble(
        season = test_s, n = NA_integer_,
        mean_nll = NA_real_, bernoulli_nll = NA_real_,
        brier = NA_real_, rmse_p = NA_real_
      )
      fold_preds[[test_s]] <- tibble::tibble()
      cat("FAILED (", elapsed, "s)\n")
    } else {
      fold_scores[[test_s]] <- eval_out$scores
      fold_preds[[test_s]]  <- eval_out$predictions
      cat(sprintf("NLL=%.4f (%s s)\n", eval_out$scores$bernoulli_nll, elapsed))
    }
  }

  cv_results[[spec_id]] <- list(
    scores      = dplyr::bind_rows(fold_scores),
    predictions = dplyr::bind_rows(fold_preds)
  )
  saveRDS(cv_results, phase2_ckpt)
} else {
  cat("Spec already evaluated -- loading from checkpoint.\n\n")
}

# ---- 5. Report ----
spec_id     <- names(specs_l2)[[1L]]
res         <- cv_results[[spec_id]]
per_season  <- res$scores[, c("season", "bernoulli_nll")]
post_l2_nll <- mean(per_season$bernoulli_nll, na.rm = TRUE)

# Pre-L2 values (from data/nested_loso_v15_postfix_production.rds)
pre_l2_overall <- 0.5959197
pre_l2_by_season <- c(
  "2012-13" = 0.8125069,
  "2013-14" = 0.6894446,
  "2014-15" = 0.7231725,
  "2016-17" = 0.5348495,
  "2017-18" = 0.4857981,
  "2018-19" = 0.4706086,
  "2019-20" = 0.6780325,
  "2022-23" = 0.4926177,
  "2023-24" = 0.4428110,
  "2024-25" = 0.6293559
)

delta_overall <- post_l2_nll - pre_l2_overall

cat("\n========================================\n")
cat("L2-fix Verification Results\n")
cat("========================================\n")
cat(sprintf("Pre-L2 NLL  : %.7f\n", pre_l2_overall))
cat(sprintf("Post-L2 NLL : %.7f\n", post_l2_nll))
cat(sprintf("Delta       : %+.7f\n", delta_overall))
cat("\nPer-season breakdown:\n")
cat(sprintf("%-10s  %-10s  %-10s  %s\n", "season", "pre-L2", "post-L2", "delta"))
cat(strrep("-", 48), "\n")

for (s in sort(per_season$season)) {
  pre  <- pre_l2_by_season[s]
  post <- per_season$bernoulli_nll[per_season$season == s]
  cat(sprintf("%-10s  %.7f  %.7f  %+.7f\n", s, pre, post, post - pre))
}

cat("\nDecision:\n")
if (abs(delta_overall) < 0.001) {
  cat("  |delta| < 0.001 -- L2 is IMMATERIAL for this spec. Phase 3 DONE.\n")
} else if (abs(delta_overall) < 0.01) {
  cat("  |delta| in [0.001, 0.01) -- Flag but Phase 3 still DONE.\n")
} else {
  cat("  |delta| >= 0.01 -- FULL v15-postfix RE-TUNE needed. STOP.\n")
}

# Save full result
results_l2 <- list(
  spec_id      = spec_id,
  per_season   = per_season,
  post_l2_nll  = post_l2_nll,
  pre_l2_nll   = pre_l2_overall,
  delta        = delta_overall,
  cv_results   = cv_results,
  grid         = grid_v15_l2
)
saveRDS(results_l2, "data/nested_loso_v15_postfix_l2verify.rds")
cat("\nResults saved to data/nested_loso_v15_postfix_l2verify.rds\n")
cat("End:", format(Sys.time()), "\n")
