#!/usr/bin/env Rscript
# ============================================================
# L2-fix mini re-tune — top-20 pre-L2 specs rescored under L2
#
# Checks rank stability: does the production best spec remain best
# after L2 fix (walk-forward estimateDerivs)?
#
# Pre-L2 best NLL: 0.5959197 (v15-postfix)
# Output: data/nested_loso_v15_postfix_l2top20.rds
#         data/nested_loso_v15_postfix_l2top20_ckpt.rds
# ============================================================

cat("=== L2-fix mini re-tune — top-20 pre-L2 specs ===\n")
cat("Start:", format(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(PAGe); library(dplyr); library(tidyr); library(purrr)
  library(furrr); library(future); library(mgcv); library(MMWRweek)
})

for (f in c(
  "R/utils.R", "R/m0_retro.R", "R/flagIgnition.R",
  "R/m1_reference.R", "R/m1_reference_helpers.R", "R/m1_multi_template.R",
  "R/m2_spec_grid.R", "R/m2_training.R", "R/m2_nested_loso.R",
  "R/pipeline_bridge.R", "R/pipeline_runtime_helpers.R"
)) source(f)

n_cores <- max(1L, parallel::detectCores() - 1L)
cat("Cores:", n_cores, "\n\n")

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

manual_labels <- c("2012-13"=18L, "2013-14"=20L, "2014-15"=20L,
                   "2015-16"=24L, "2016-17"=19L, "2017-18"=20L,
                   "2018-19"=19L, "2019-20"=22L, "2022-23"=15L,
                   "2023-24"=20L, "2024-25"=23L)
EXCLUDE_SEAS <- "2015-16"
flag_args <- list(p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L,
                  min_window = 10L, w_min = 21L, w_max = 21L, d2_relax = -0.01)

# ---- Top 20 pre-L2 specs ----
prev <- readRDS("data/nested_loso_v15_postfix_production.rds")
top20_summary <- prev$summary[order(prev$summary$bernoulli_nll), ][1:20, ]
top20_ids <- top20_summary$spec_id
cat("Top 20 pre-L2 spec IDs:\n"); print(top20_ids)

# Reconstruct specs from grid — build spec_id column from grid params
grid_all <- prev$grid
grid_all$spec_id <- paste0(
  "d+", grid_all$delta, "_Kr", grid_all$Kr,
  "_kf", grid_all$k_f, "_ke", grid_all$k_e,
  "_as", grid_all$alpha_state,
  "_kr", grid_all$k_r, "_kde", grid_all$k_de, "_ksp", grid_all$k_sp,
  "_ba", grid_all$bias_alpha, "_bb", grid_all$bias_beta
)
grid_top20 <- grid_all[match(top20_ids, grid_all$spec_id), ]
stopifnot(nrow(grid_top20) == 20, !anyNA(grid_top20$spec_id))

specs_top20 <- purrr::pmap(grid_top20, function(delta, Kr, k_f, k_e,
                                                alpha_state, k_r, k_de, k_sp,
                                                bias_alpha, bias_beta, spec_id) {
  stage2_make_spec(
    delta = delta, Kr = Kr, T = "S",
    k_f = k_f, k_e = k_e, alpha_state = alpha_state,
    k_r = k_r, k_de = k_de, k_sp = k_sp,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = bias_alpha, bias_beta = bias_beta
  )
})
names(specs_top20) <- grid_top20$spec_id

test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("\nLOSO folds:", length(test_seasons), "\n\n")

# ---- Load M1 phase-1 cache ----
m1_cache <- readRDS("data/fresh_nested_loso_v15_phase1.rds")

# ---- Checkpoint / resume ----
ckpt_path <- "data/nested_loso_v15_postfix_l2top20_ckpt.rds"
cv_results <- if (file.exists(ckpt_path)) readRDS(ckpt_path) else list()
todo_ids <- setdiff(names(specs_top20), names(cv_results))
cat("To evaluate:", length(todo_ids), "/", length(specs_top20), "specs\n\n")

# Eval one spec across all folds.
eval_one_spec <- function(sid, spec) {
  fold_scores <- vector("list", length(test_seasons))
  names(fold_scores) <- test_seasons
  for (ts in test_seasons) {
    fc <- m1_cache[[ts]]
    m2_fit <- tryCatch(nested_loso_m2_train(
      fold = fc$fold,
      m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
      spec = spec, method = "REML", verbose = FALSE
    ), error = function(e) NULL)
    if (is.null(m2_fit)) { fold_scores[[ts]] <- NA_real_; next }
    lbl_train <- manual_labels[setdiff(names(manual_labels), ts)]
    eo <- tryCatch(nested_loso_m2_eval_frozen_bias(
      allD = allD, fold = fc$fold, m2_fit = m2_fit,
      m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
      spec = spec, eval_window = 12L,
      bias_alpha = spec$bias_alpha,
      manual_labels_train = lbl_train,
      manual_labels_test = NULL,
      flag_args = flag_args, verbose = FALSE
    ), error = function(e) NULL)
    fold_scores[[ts]] <- if (is.null(eo)) NA_real_ else eo$scores$bernoulli_nll
  }
  unlist(fold_scores)
}

# ---- Run in parallel across specs ----
future::plan(future::multisession, workers = min(n_cores, length(todo_ids)))

if (length(todo_ids) > 0) {
  t0 <- Sys.time()
  cat("Evaluating", length(todo_ids), "specs in parallel...\n")
  results <- furrr::future_map(todo_ids, function(sid) {
    eval_one_spec(sid, specs_top20[[sid]])
  }, .progress = TRUE, .options = furrr::furrr_options(seed = TRUE))
  names(results) <- todo_ids
  for (sid in todo_ids) cv_results[[sid]] <- list(per_fold = results[[sid]])
  saveRDS(cv_results, ckpt_path)
  cat(sprintf("\nElapsed: %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

# ---- Build comparison table ----
pre_l2 <- setNames(top20_summary$bernoulli_nll, top20_summary$spec_id)
post_l2 <- sapply(names(specs_top20), function(sid)
  mean(cv_results[[sid]]$per_fold, na.rm = TRUE))

cmp <- data.frame(
  spec_id = names(specs_top20),
  pre_l2  = pre_l2[names(specs_top20)],
  post_l2 = post_l2,
  delta   = post_l2 - pre_l2[names(specs_top20)],
  row.names = NULL
)
cmp$pre_rank  <- rank(cmp$pre_l2,  ties.method = "min")
cmp$post_rank <- rank(cmp$post_l2, ties.method = "min")
cmp$rank_shift <- cmp$post_rank - cmp$pre_rank
cmp <- cmp[order(cmp$post_l2), ]

cat("\n==============================\n")
cat("Top-20 L2 rescore comparison\n")
cat("==============================\n")
cat(sprintf("%-52s %8s %8s %8s %5s %5s %5s\n",
            "spec_id", "pre_L2", "post_L2", "delta", "r_pre", "r_post", "shift"))
cat(strrep("-", 100), "\n")
for (i in seq_len(nrow(cmp))) {
  r <- cmp[i, ]
  cat(sprintf("%-52s %.5f %.5f %+7.5f %5d %5d %+5d\n",
              r$spec_id, r$pre_l2, r$post_l2, r$delta,
              r$pre_rank, r$post_rank, r$rank_shift))
}

best_post_id  <- cmp$spec_id[which.min(cmp$post_l2)]
best_post_nll <- min(cmp$post_l2, na.rm = TRUE)
prod_kit_id   <- "d+0_Kr1_kf5_ke2_as0.4_kr0_kde0_ksp2_ba0.5_bb0"
prod_post_nll <- cmp$post_l2[cmp$spec_id == prod_kit_id]

cat("\n--- Summary ---\n")
cat(sprintf("Pre-L2 best:  %s (NLL=%.5f)\n",
            cmp$spec_id[which.min(cmp$pre_l2)], min(cmp$pre_l2)))
cat(sprintf("Post-L2 best: %s (NLL=%.5f)\n", best_post_id, best_post_nll))
cat(sprintf("Production kit: %s (post-L2 NLL=%.5f)\n", prod_kit_id, prod_post_nll))
cat(sprintf("Gap (prod - post_best): %+.5f\n", prod_post_nll - best_post_nll))

saveRDS(list(comparison = cmp, cv_results = cv_results,
             best_post_id = best_post_id, best_post_nll = best_post_nll,
             prod_post_nll = prod_post_nll),
        "data/nested_loso_v15_postfix_l2top20.rds")
cat("\nSaved data/nested_loso_v15_postfix_l2top20.rds\n")
cat("End:", format(Sys.time()), "\n")
