#!/usr/bin/env Rscript
# ============================================================
# Nested LOSO M2 — v14b: alpha_state extension under Bernoulli NLL
#
# v14 confirmed alpha_state=0.30 is still at the boundary under Bernoulli NLL,
# and bias_alpha flipped from 0.4 (v13) to 0.2 (v14). v13b ran alpha_state
# up to 0.50 but only with bias_alpha in {0.3, 0.4, 0.5} — missing ba=0.2.
#
# This script runs the missing specs:
#   alpha_state in {0.30, 0.35, 0.40, 0.45, 0.50} x bias_alpha in {0.2, 0.3}
#   (ba=0.2 is new; ba=0.3 overlaps with v13b for cross-check)
#   k_f=4, k_e=2, k_r=2, k_de=0, bias_beta=0.0 (fixed at best)
#
# Then combines with v13 + v13b predictions and re-scores all with Bernoulli NLL.
#
# Output: data/nested_loso_v14b_production.rds
# ============================================================

cat("=== Nested LOSO M2 v14b — alpha_state boundary extension (Bernoulli NLL) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(PAGe); library(dplyr); library(tidyr); library(purrr)
  library(furrr); library(future); library(mgcv); library(MMWRweek)
  library(data.table)
})

for (f in c(
  "R/utils.R", "R/m0_retro.R", "R/flagIgnition.R",
  "R/m1_reference.R", "R/m1_reference_helpers.R", "R/m1_multi_template.R",
  "R/m2_spec_grid.R", "R/m2_training.R", "R/m2_nested_loso.R",
  "R/pipeline_bridge.R", "R/pipeline_runtime_helpers.R"
)) source(f)

n_cores <- max(1L, parallel::detectCores() - 1L)

# ---- Bernoulli NLL ----
bernoulli_nll_fn <- function(p_hat, p_obs, eps = 1e-12) {
  p_hat <- pmin(1 - eps, pmax(eps, p_hat))
  p_obs <- pmin(1 - eps, pmax(eps, p_obs))
  -mean(p_obs * log(p_hat) + (1 - p_obs) * log(1 - p_hat), na.rm = TRUE)
}

# ---- Data ----
n_weeks_in_start_year <- function(sy)
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(sy, "-12-31")))$MMWRweek == 53L)

allD <- read.csv("data/flu_testing_data.csv") |>
  dplyr::select(season, week, year, start_year = seasonstart,
                date = week_start_date, y = pos_flua, N = test_flu) |>
  dplyr::mutate(neg = N - y, date = as.Date(date),
                nW_true = n_weeks_in_start_year(start_year),
                weekF = ((week - 27L) %% nW_true) + 1L, p = y / N) |>
  dplyr::filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

params        <- readRDS("data/stage1_tuning.rds")$best_params
manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L, "2015-16" = 24L,
  "2016-17" = 19L, "2017-18" = 20L, "2018-19" = 19L, "2019-20" = 22L,
  "2022-23" = 15L, "2023-24" = 20L, "2024-25" = 23L
)
EXCLUDE_SEAS <- "2015-16"
flag_args    <- list(p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L,
                     min_window = 10L, w_min = 21L, w_max = 21L, d2_relax = -0.01)
test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))

# ---- M1 cache ----
m1_cache <- readRDS("data/nested_loso_v13_phase1.rds")
cat("M1 cache loaded:", length(m1_cache), "folds.\n\n")

# ---- New specs: alpha_state extension with ba=0.2 ----
grid_new <- tidyr::crossing(
  delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
  alpha_state = c(0.30, 0.35, 0.40, 0.45, 0.50),
  k_r = 2L, k_de = 0L,
  bias_alpha = c(0.2, 0.3),  # ba=0.3 overlaps v13b for cross-check
  bias_beta  = 0.0
)

specs_new <- purrr::pmap(grid_new, function(delta, Kr, k_f, k_e, alpha_state,
                                              k_r, k_de, bias_alpha, bias_beta) {
  stage2_make_spec(delta = delta, Kr = Kr, T = "S", k_f = k_f, k_e = k_e,
    alpha_state = alpha_state, k_r = k_r, k_de = k_de,
    k_n = 0L, k_w = 0L, k_s = 0L, lambda_w = 0, w_floor = 0.05,
    bias_alpha = bias_alpha, bias_beta = bias_beta)
})
names(specs_new) <- paste0("kf", grid_new$k_f, "_ke", grid_new$k_e,
  "_as", grid_new$alpha_state, "_kr", grid_new$k_r,
  "_ba", grid_new$bias_alpha, "_bb", grid_new$bias_beta)

cat("New specs:", length(specs_new), "\n\n")

# ---- Evaluate new specs ----
ckpt <- "data/nested_loso_v14b_phase2.rds"
if (file.exists(ckpt)) {
  cv_new <- readRDS(ckpt)
  todo   <- setdiff(names(specs_new), names(cv_new))
  cat("Resuming:", length(cv_new), "done,", length(todo), "remaining\n\n")
} else {
  cv_new <- list(); todo <- names(specs_new)
}

if (length(todo) > 0) {
  future::plan(future::multisession, workers = n_cores)
  batch_size   <- n_cores
  todo_batches <- split(todo, ceiling(seq_along(todo) / batch_size))

  for (bi in seq_along(todo_batches)) {
    batch <- todo_batches[[bi]]
    cat(sprintf("Batch %d/%d (%d specs)...", bi, length(todo_batches), length(batch)))
    t0 <- proc.time()[["elapsed"]]

    batch_results <- furrr::future_map(
      stats::setNames(batch, batch),
      function(spec_id) {
        spec <- specs_new[[spec_id]]
        fold_scores <- vector("list", length(test_seasons))
        fold_preds  <- vector("list", length(test_seasons))
        names(fold_scores) <- names(fold_preds) <- test_seasons
        for (test_s in test_seasons) {
          fc <- m1_cache[[test_s]]
          m2_fit <- tryCatch(nested_loso_m2_train(
            fold = fc$fold,
            m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
            spec = spec, method = "REML", verbose = FALSE), error = function(e) NULL)
          eval_out <- tryCatch(nested_loso_m2_eval_frozen_bias(
            allD = allD, fold = fc$fold, m2_fit = m2_fit,
            m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
            spec = spec, eval_window = 12L,
            manual_labels = manual_labels, flag_args = flag_args, verbose = FALSE),
            error = function(e) NULL)
          if (is.null(eval_out)) {
            fold_scores[[test_s]] <- tibble::tibble(season = test_s, n = NA_integer_,
              mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_)
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
    cv_new <- c(cv_new, batch_results)
    saveRDS(cv_new, ckpt)
    elapsed <- round(proc.time()[["elapsed"]] - t0)
    cat(sprintf(" %ds\n", elapsed))
  }
  future::plan(future::sequential)
}

# ---- Score new specs with Bernoulli NLL ----
score_bern <- function(cv_results) {
  purrr::imap_dfr(cv_results, function(res, spec_id) {
    purrr::map_dfr(unique(res$scores$season), function(seas) {
      pr <- res$predictions |> dplyr::filter(season == seas)
      sc <- res$scores      |> dplyr::filter(season == seas)
      if (nrow(pr) == 0) return(tibble::tibble(spec_id = spec_id, season = seas,
        n = NA_integer_, bernoulli_nll = NA_real_, brier = NA_real_, mean_nll_raw = NA_real_))
      tibble::tibble(spec_id = spec_id, season = seas, n = nrow(pr),
        bernoulli_nll = bernoulli_nll_fn(pr$p_hat, pr$p_obs),
        brier         = mean((pr$p_hat - pr$p_obs)^2, na.rm = TRUE),
        mean_nll_raw  = sc$mean_nll)
    })
  })
}

scores_new <- score_bern(cv_new[names(specs_new)])

summary_new <- scores_new |>
  dplyr::group_by(spec_id) |>
  dplyr::summarise(bernoulli_nll = mean(bernoulli_nll, na.rm = TRUE),
                   brier = mean(brier, na.rm = TRUE),
                   mean_nll_raw = mean(mean_nll_raw, na.rm = TRUE),
                   .groups = "drop") |>
  dplyr::arrange(bernoulli_nll)

cat("\n=== v14b Results (Bernoulli NLL) ===\n")
print(summary_new)

cat("\n=== Best Bernoulli NLL by alpha_state ===\n")
summary_new$alpha_state <- as.numeric(sub("^.*_as([0-9.]+)_.*$", "\\1", summary_new$spec_id))
ag <- aggregate(bernoulli_nll ~ alpha_state, data = summary_new, FUN = min)
print(ag[order(ag$alpha_state), ])

best_id <- summary_new$spec_id[1]
cat("\nBest spec:", best_id, "\n")

saveRDS(list(scores = scores_new, summary = summary_new,
             best_spec_id = best_id, cv_results = cv_new[names(specs_new)],
             grid = grid_new),
        "data/nested_loso_v14b_production.rds")
cat("Saved data/nested_loso_v14b_production.rds\n")
cat("End:", format(Sys.time()), "\n")
