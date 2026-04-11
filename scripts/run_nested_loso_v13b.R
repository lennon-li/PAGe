#!/usr/bin/env Rscript
# ============================================================
# Nested LOSO M2 — v13b: alpha_state boundary extension
#
# v13 showed alpha_state monotonically improving through 0.30 (grid boundary).
# This script extends to {0.35, 0.40, 0.45, 0.50} with best fixed params:
#   k_f=4, k_e=2, k_r=2, k_de=0, bias_beta=0.0
# bias_alpha varied in {0.3, 0.4, 0.5} to check interaction with alpha_state.
#
# Grid: 4 x 3 = 12 new specs (+ 3 anchor specs from v13 for cross-check)
# Reuses Phase 1 cache from v13.
#
# Output: data/nested_loso_v13b_production.rds
# ============================================================

cat("=== Nested LOSO M2 v13b — alpha_state boundary extension ===\n")
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

test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("Test seasons (", length(test_seasons), "):", paste(test_seasons, collapse = ", "), "\n\n")

# ---- 2. Load M1 cache ----
cat("Loading M1 cache...\n")
for (src in c("data/nested_loso_v13_phase1.rds", "data/nested_loso_v12_phase1.rds")) {
  if (file.exists(src)) { m1_cache <- readRDS(src); cat("Loaded:", src, "\n\n"); break }
}

# ---- 3. v13b spec grid ----
# Anchor at alpha_state=0.30 (best in v13) + extension to 0.50
grid_v13b <- tidyr::crossing(
  delta       = 0L,
  Kr          = 1L,
  k_f         = 4L,
  k_e         = 2L,
  alpha_state = c(0.30, 0.35, 0.40, 0.45, 0.50),
  k_r         = 2L,
  k_de        = 0L,
  bias_alpha  = c(0.3, 0.4, 0.5),
  bias_beta   = 0.0
)

specs_v13b <- purrr::pmap(grid_v13b, function(delta, Kr, k_f, k_e, alpha_state,
                                                k_r, k_de, bias_alpha, bias_beta) {
  stage2_make_spec(
    delta = delta, Kr = Kr, T = "S",
    k_f = k_f, k_e = k_e, alpha_state = alpha_state,
    k_r = k_r, k_de = k_de,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = bias_alpha, bias_beta = bias_beta
  )
})
names(specs_v13b) <- paste0(
  "kf", grid_v13b$k_f,
  "_ke", grid_v13b$k_e,
  "_as", grid_v13b$alpha_state,
  "_kr", grid_v13b$k_r,
  "_ba", grid_v13b$bias_alpha,
  "_bb", grid_v13b$bias_beta
)

cat("Grid size:", length(specs_v13b), "specs\n\n")

# ---- 4. Evaluate ----
phase2_ckpt <- "data/nested_loso_v13b_phase2.rds"

if (file.exists(phase2_ckpt)) {
  cv_results <- readRDS(phase2_ckpt)
  todo       <- setdiff(names(specs_v13b), names(cv_results))
  cat("Resuming:", length(cv_results), "done,", length(todo), "remaining\n\n")
} else {
  cv_results <- list()
  todo       <- names(specs_v13b)
}

if (length(todo) > 0) {
  batch_size   <- n_cores
  todo_batches <- split(todo, ceiling(seq_along(todo) / batch_size))
  future::plan(future::multisession, workers = n_cores)

  for (bi in seq_along(todo_batches)) {
    batch <- todo_batches[[bi]]
    cat(sprintf("Batch %d/%d (%d specs)...", bi, length(todo_batches), length(batch)))
    t0 <- proc.time()[["elapsed"]]

    batch_results <- furrr::future_map(
      stats::setNames(batch, batch),
      function(spec_id) {
        spec        <- specs_v13b[[spec_id]]
        fold_scores <- vector("list", length(test_seasons))
        fold_preds  <- vector("list", length(test_seasons))
        names(fold_scores) <- names(fold_preds) <- test_seasons

        for (test_s in test_seasons) {
          fc <- m1_cache[[test_s]]
          m2_fit <- tryCatch(
            nested_loso_m2_train(
              fold           = fc$fold,
              m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
              spec           = spec, method = "REML", verbose = FALSE
            ), error = function(e) NULL
          )
          eval_out <- tryCatch(
            nested_loso_m2_eval_frozen_bias(
              allD          = allD, fold = fc$fold, m2_fit = m2_fit,
              m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
              spec          = spec, eval_window = 12L,
              manual_labels = manual_labels, flag_args = flag_args, verbose = FALSE
            ), error = function(e) NULL
          )
          if (is.null(eval_out)) {
            fold_scores[[test_s]] <- tibble::tibble(season = test_s, n = NA_integer_,
              mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_)
            fold_preds[[test_s]]  <- tibble::tibble()
          } else {
            fold_scores[[test_s]] <- eval_out$scores
            fold_preds[[test_s]]  <- eval_out$predictions
          }
        }
        list(scores = dplyr::bind_rows(fold_scores), predictions = dplyr::bind_rows(fold_preds))
      },
      .options = furrr::furrr_options(seed = TRUE)
    )

    cv_results <- c(cv_results, batch_results)
    saveRDS(cv_results, phase2_ckpt)
    elapsed    <- round(proc.time()[["elapsed"]] - t0)
    batch_nlls <- sapply(batch_results, function(r) round(mean(r$scores$mean_nll, na.rm = TRUE), 3))
    cat(sprintf(" %ds | nll range: %.3f–%.3f\n",
                elapsed, min(batch_nlls, na.rm=TRUE), max(batch_nlls, na.rm=TRUE)))
  }
  future::plan(future::sequential)
} else {
  cat("All specs already evaluated.\n\n")
}

# ---- 5. Results ----
cat("\n=== v13b Results ===\n")
all_scores <- purrr::imap_dfr(cv_results[names(specs_v13b)],
                               ~ dplyr::mutate(.x$scores, spec_id = .y))

summary_df <- all_scores |>
  dplyr::group_by(spec_id) |>
  dplyr::summarise(
    n_seasons = dplyr::n(),
    mean_nll  = mean(mean_nll, na.rm = TRUE),
    brier     = mean(brier,    na.rm = TRUE),
    rmse_p    = mean(rmse_p,   na.rm = TRUE),
    .groups   = "drop"
  ) |>
  dplyr::arrange(mean_nll)

print(summary_df, n = Inf)

best_id   <- summary_df$spec_id[1]
best_spec <- specs_v13b[[best_id]]
cat("\nBest spec:", best_id, "\n")

# NLL by alpha_state (min across bias_alpha)
cat("\n=== Best NLL by alpha_state ===\n")
summary_df$alpha_state <- as.numeric(sub("^kf\\d+_ke\\d+_as([0-9.]+)_.*$", "\\1", summary_df$spec_id))
ag <- aggregate(mean_nll ~ alpha_state, data = summary_df, FUN = min)
print(ag[order(ag$alpha_state), ])

results <- list(
  scores       = all_scores,
  summary      = summary_df,
  best_spec_id = best_id,
  best_spec    = best_spec,
  cv_results   = cv_results,
  grid         = grid_v13b
)
saveRDS(results, "data/nested_loso_v13b_production.rds")
cat("\nSaved to data/nested_loso_v13b_production.rds\n")
cat("End:", format(Sys.time()), "\n")
