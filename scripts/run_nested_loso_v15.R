#!/usr/bin/env Rscript
# ============================================================
# Nested LOSO M2 Grid Search — v15
#
# Changes from v14b:
#   - Phase 1 REBUILT with LOCKED M1 spec:
#       * slope_weight=8, slope_window=6 (v5-v7 LOSO optimum, MAE=1.275)
#       * dynamic_temp=FALSE (locked from ablation)
#       * slope-similarity uses aligned positions (u_hat per template)
#       * CI propagated from GAM SE (logit_spread now populated)
#   - New covariate: logit_spread (alignment uncertainty from M1 ensemble)
#       * k_sp ∈ {0, 2} — tests whether spread improves M2 calibration
#   - dz_ema now standardized (unit-variance) in prep_stage2_joint():
#       * dz_ema_sd stored in feature_ranges for LOSO/deployment parity
#       * k_de ∈ {0, 2} — re-tests growth-rate term after rescaling
#   - alpha_state centred on v14 optimum: {0.30, 0.35, 0.40, 0.45, 0.50}
#   - bias_beta fixed at 0.0 (confirmed optimal in v13/v14)
#   - bias_alpha includes 0.1 (v14 best was 0.2, check lower end)
#   - Grid: 4(k_f) x 2(k_e) x 5(as) x 3(k_r) x 2(k_de) x 2(k_sp) x 4(ba) x 1(bb)
#           = 1920 specs
#
# Output: data/nested_loso_v15_phase1.rds
#         data/nested_loso_v15_phase2.rds (resumable checkpoint)
#         data/nested_loso_v15_production.rds (final)
# ============================================================

cat("=== Nested LOSO M2 grid search (v15 — fixed M1 + Bernoulli NLL) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(flualign)
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

params        <- readRDS("data/stage1_tuning.rds")$best_params
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

# ---- 2. M1 settings (LOCKED spec from v5-v7 LOSO grid, MAE=1.275) ----
M1 <- list(
  k_ref = 25L, ref_method = "fs", temperature = 0.25,
  rise_weight = 1.0, trough_weight = 0.1, peak_decay = 0.3,
  slope_weight = 8.0,   # ← LOCKED: interior optimum over {0 … 30}
  slope_window = 6L,    # ← LOCKED: optimal window (4,6,8,10,12 tested)
  dynamic_temp = FALSE, dynamic_temp_pivot = 10L
)

test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("Test seasons (", length(test_seasons), "):", paste(test_seasons, collapse = ", "), "\n\n")

# ---- 3. v15 spec grid ----
# bias_beta=0.0 confirmed optimal; alpha_state centred on v14 best (0.40)
# New dimensions: k_sp (logit_spread smooth) + k_de (dz_ema, now standardized)
grid_v15 <- tidyr::crossing(
  delta       = 0L,
  Kr          = 1L,
  k_f         = c(2L, 3L, 4L, 5L),
  k_e         = c(2L, 3L),
  alpha_state = c(0.30, 0.35, 0.40, 0.45, 0.50),
  k_r         = c(0L, 2L, 3L),
  k_de        = c(0L, 2L),   # ← NEW: dz_ema term (standardized, safe to test)
  k_sp        = c(0L, 2L),   # ← NEW: logit_spread alignment uncertainty term
  bias_alpha  = c(0.1, 0.2, 0.3, 0.4),
  bias_beta   = 0.0
)

specs_v15 <- purrr::pmap(grid_v15, function(delta, Kr, k_f, k_e, alpha_state,
                                              k_r, k_de, k_sp, bias_alpha, bias_beta) {
  stage2_make_spec(
    delta = delta, Kr = Kr, T = "S",
    k_f = k_f, k_e = k_e, alpha_state = alpha_state,
    k_r = k_r, k_de = k_de, k_sp = k_sp,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = bias_alpha, bias_beta = bias_beta
  )
})
names(specs_v15) <- paste0(
  "d+", grid_v15$delta,
  "_Kr", grid_v15$Kr,
  "_kf", grid_v15$k_f,
  "_ke", grid_v15$k_e,
  "_as", grid_v15$alpha_state,
  "_kr", grid_v15$k_r,
  "_kde", grid_v15$k_de,
  "_ksp", grid_v15$k_sp,
  "_ba", grid_v15$bias_alpha,
  "_bb", grid_v15$bias_beta
)

cat("Grid size:", length(specs_v15), "specs\n\n")

# ============================================================
# PHASE 1: Rebuild M1 cache with FIXED M1 (forced rebuild)
# ============================================================
cat("=== PHASE 1: Rebuilding M1 cache with fixed M1 ===\n")
cat("  Fixes: slope-similarity uses aligned positions; SE propagated from GAM\n")
cat("  NOT loading any prior cache — full rebuild required.\n\n")

# In smoke-test mode only build one fold
p1_seasons <- if (Sys.getenv("SMOKE_TEST", unset = "0") == "1")
  test_seasons[1L] else test_seasons

m1_cache <- list()
future::plan(future::multisession, workers = n_cores)

for (test_s in p1_seasons) {
  cat(sprintf("[%s] Building fold + M1...\n", test_s))
  t0 <- proc.time()[["elapsed"]]

  fold <- tryCatch(
    nested_loso_build_fold(
      allD = allD, test_season = test_s, exclude_seasons = EXCLUDE_SEAS,
      k_ref = M1$k_ref, ref_method = M1$ref_method,
      manual_labels = manual_labels, verbose = FALSE
    ),
    error = function(e) { message("  ERROR building fold: ", conditionMessage(e)); NULL }
  )
  if (is.null(fold)) next

  m1_train <- tryCatch(
    m1_walkforward_multi(
      allD = allD, ref = fold$ref, hyper = fold$hyper, params = params,
      seasons = fold$train_seasons, temperature = M1$temperature,
      rise_weight = M1$rise_weight, trough_weight = M1$trough_weight,
      peak_decay = M1$peak_decay, slope_weight = M1$slope_weight,
      slope_window = M1$slope_window, dynamic_temp = M1$dynamic_temp,
      dynamic_temp_pivot = M1$dynamic_temp_pivot, parallel = TRUE, verbose = FALSE
    ),
    error = function(e) { message("  ERROR m1_train: ", conditionMessage(e)); NULL }
  )

  m1_test <- tryCatch(
    m1_walkforward_predictions(
      seasonD = allD[allD$season == test_s, ], ref = fold$ref, hyper = fold$hyper,
      params = params, temperature = M1$temperature, rise_weight = M1$rise_weight,
      trough_weight = M1$trough_weight, peak_decay = M1$peak_decay,
      slope_weight = M1$slope_weight, slope_window = M1$slope_window,
      dynamic_temp = M1$dynamic_temp, dynamic_temp_pivot = M1$dynamic_temp_pivot
    ),
    error = function(e) { message("  ERROR m1_test: ", conditionMessage(e)); NULL }
  )

  m1_cache[[test_s]] <- list(fold = fold, m1_train = m1_train, m1_test = m1_test)
  cat(sprintf("  Done in %ds | train rows: %d | test rows: %d\n\n",
              round(proc.time()[["elapsed"]] - t0),
              if (!is.null(m1_train)) nrow(m1_train) else 0L,
              if (!is.null(m1_test))  nrow(m1_test)  else 0L))
}

if (Sys.getenv("SMOKE_TEST", unset = "0") != "1") {
  saveRDS(m1_cache, "data/nested_loso_v15_phase1.rds")
  cat("Saved Phase 1 cache to data/nested_loso_v15_phase1.rds\n")
}
cat("Phase 1 complete:", length(m1_cache), "folds.\n\n")

# ============================================================
# SMOKE TEST — run 1 fold × 1 spec, check bernoulli_nll + CI
# ============================================================
if (Sys.getenv("SMOKE_TEST", unset = "0") == "1") {
  cat("=== SMOKE TEST: 1 fold × 1 spec ===\n")
  test_s     <- test_seasons[1]
  fc         <- m1_cache[[test_s]]
  smoke_id   <- names(specs_v15)[which(
    grid_v15$k_f == 4L & grid_v15$k_e == 2L &
    grid_v15$alpha_state == 0.40 & grid_v15$k_r == 2L &
    grid_v15$k_de == 0L & grid_v15$k_sp == 0L &
    grid_v15$bias_alpha == 0.2
  )[1]]
  smoke_spec <- specs_v15[[smoke_id]]
  cat("Test season:", test_s, " | Spec:", smoke_id, "\n")

  m2_fit <- nested_loso_m2_train(
    fold           = fc$fold,
    m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
    spec           = smoke_spec,
    method         = "REML",
    verbose        = TRUE
  )
  eval_out <- nested_loso_m2_eval_frozen_bias(
    allD          = allD,
    fold          = fc$fold,
    m2_fit        = m2_fit,
    m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
    spec          = smoke_spec,
    eval_window   = 12L,
    manual_labels = manual_labels,
    flag_args     = flag_args,
    verbose       = FALSE
  )
  cat("Smoke test scores:\n")
  print(eval_out$scores)
  cat("Predictions columns:", paste(names(eval_out$predictions), collapse = ", "), "\n")
  stopifnot("bernoulli_nll" %in% names(eval_out$scores))
  stopifnot(all(c("p_lo", "p_hi") %in% names(eval_out$predictions)))
  cat("=== SMOKE TEST PASSED ===\n")
  quit(save = "no")
}

# ============================================================
# PHASE 2: Evaluate all v15 specs (frozen GAM + Holt + R2)
# ============================================================
cat("=== PHASE 2: M2 grid search (v15 — frozen + Holt + online RE) ===\n")

new_spec_ids <- names(specs_v15)
cat("Total v15 specs to evaluate:", length(new_spec_ids), "\n\n")

phase2_ckpt <- "data/nested_loso_v15_phase2.rds"

if (file.exists(phase2_ckpt)) {
  cv_results_new <- readRDS(phase2_ckpt)
  todo_spec_ids  <- setdiff(new_spec_ids, names(cv_results_new))
  cat("Resuming:", length(cv_results_new), "done,", length(todo_spec_ids), "remaining\n\n")
} else {
  cv_results_new <- list()
  todo_spec_ids  <- new_spec_ids
}

if (length(todo_spec_ids) > 0) {
  cat("(", length(todo_spec_ids), "specs x", length(test_seasons), "folds)\n\n")
  batch_size   <- n_cores
  todo_batches <- split(todo_spec_ids, ceiling(seq_along(todo_spec_ids) / batch_size))
  future::plan(future::multisession, workers = n_cores)

  for (bi in seq_along(todo_batches)) {
    batch <- todo_batches[[bi]]
    cat(sprintf("Batch %d/%d (%d specs)...", bi, length(todo_batches), length(batch)))
    t0 <- proc.time()[["elapsed"]]

    batch_results <- furrr::future_map(
      stats::setNames(batch, batch),
      function(spec_id) {
        spec        <- specs_v15[[spec_id]]
        fold_scores <- vector("list", length(test_seasons))
        fold_preds  <- vector("list", length(test_seasons))
        names(fold_scores) <- names(fold_preds) <- test_seasons

        for (test_s in test_seasons) {
          fc <- m1_cache[[test_s]]

          m2_fit <- tryCatch(
            nested_loso_m2_train(
              fold           = fc$fold,
              m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
              spec           = spec,
              method         = "REML",
              verbose        = FALSE
            ),
            error = function(e) NULL
          )

          eval_out <- tryCatch(
            nested_loso_m2_eval_frozen_bias(
              allD          = allD,
              fold          = fc$fold,
              m2_fit        = m2_fit,
              m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
              spec          = spec,
              eval_window   = 12L,
              manual_labels = manual_labels,
              flag_args     = flag_args,
              verbose       = FALSE
            ),
            error = function(e) NULL
          )

          if (is.null(eval_out)) {
            fold_scores[[test_s]] <- tibble::tibble(
              season = test_s, n = NA_integer_,
              mean_nll = NA_real_, bernoulli_nll = NA_real_,
              brier = NA_real_, rmse_p = NA_real_
            )
            fold_preds[[test_s]] <- tibble::tibble()
          } else {
            fold_scores[[test_s]] <- eval_out$scores
            fold_preds[[test_s]]  <- eval_out$predictions
          }
        }
        list(scores = dplyr::bind_rows(fold_scores), predictions = dplyr::bind_rows(fold_preds))
      },
      .options = furrr::furrr_options(seed = TRUE)
    )

    cv_results_new <- c(cv_results_new, batch_results)
    saveRDS(cv_results_new, phase2_ckpt)

    elapsed    <- round(proc.time()[["elapsed"]] - t0)
    batch_nlls <- sapply(batch_results, function(r)
      round(mean(r$scores$bernoulli_nll, na.rm = TRUE), 4))
    cat(sprintf(" %ds | bernoulli_nll range: %.4f–%.4f\n",
                elapsed, min(batch_nlls, na.rm = TRUE), max(batch_nlls, na.rm = TRUE)))
  }

  future::plan(future::sequential)
} else {
  cat("All specs already evaluated — skipping.\n\n")
}

# ============================================================
# Assemble v15 results and report
# ============================================================
cat("\n=== Assembling v15 results ===\n")

cv_results_all <- cv_results_new[names(specs_v15)]
cat("Total specs:", length(cv_results_all), "\n")

all_scores <- purrr::imap_dfr(cv_results_all, ~ dplyr::mutate(.x$scores, spec_id = .y))

summary_df <- all_scores |>
  dplyr::group_by(spec_id) |>
  dplyr::summarise(
    n_seasons     = dplyr::n(),
    bernoulli_nll = mean(bernoulli_nll, na.rm = TRUE),
    mean_nll      = mean(mean_nll,      na.rm = TRUE),
    brier         = mean(brier,         na.rm = TRUE),
    rmse_p        = mean(rmse_p,        na.rm = TRUE),
    .groups       = "drop"
  ) |>
  dplyr::arrange(bernoulli_nll)

best_id   <- summary_df$spec_id[1]
best_spec <- specs_v15[[best_id]]

cat("\n=== Top 20 specs by Bernoulli NLL ===\n")
print(utils::head(summary_df[, c("spec_id","bernoulli_nll","mean_nll","brier","rmse_p")], 20), n = 20)
cat("\nBest spec:", best_id, "\n")
cat("Best spec params:\n")
print(unlist(best_spec[c("k_f", "k_e", "alpha_state", "k_r", "k_de", "bias_alpha", "bias_beta")]))

# Boundary check
cat("\n=== alpha_state boundary check ===\n")
as_summary <- summary_df |>
  dplyr::mutate(alpha_state = as.numeric(sub("^.*_as([0-9.]+)_.*$", "\\1", spec_id))) |>
  dplyr::group_by(alpha_state) |>
  dplyr::summarise(min_bern_nll = min(bernoulli_nll, na.rm = TRUE), .groups = "drop") |>
  dplyr::arrange(alpha_state)
print(as_summary)

cat("\n=== bias_alpha boundary check ===\n")
ba_summary <- summary_df |>
  dplyr::mutate(bias_alpha = as.numeric(sub("^.*_ba([0-9.]+)_.*$", "\\1", spec_id))) |>
  dplyr::group_by(bias_alpha) |>
  dplyr::summarise(min_bern_nll = min(bernoulli_nll, na.rm = TRUE), .groups = "drop") |>
  dplyr::arrange(bias_alpha)
print(ba_summary)

results <- list(
  scores       = all_scores,
  summary      = summary_df,
  best_spec_id = best_id,
  best_spec    = best_spec,
  cv_results   = cv_results_all,
  grid         = grid_v15
)
saveRDS(results, "data/nested_loso_v15_production.rds")

cat("\nResults saved to data/nested_loso_v15_production.rds\n")
cat("End:", format(Sys.time()), "\n")
