#!/usr/bin/env Rscript
# Step 4e — M2 Nested LOSO v16 (RE-fix, fresh run)
#
# RE-fix: estimate_season_re_online() now uses only post-ignition observations
# (weekF >= iWeek_hat / iWeek_used) instead of all current-season obs.
# This prevents pre-ignition low-positivity weeks from creating a spuriously
# negative season RE that tanks early-season predictions.
#
# Grid: same 192-spec focused grid as v15-postfix, centered on kf6/as0.35.
# bias_alpha range extended to 0.1–0.7 since the RE fix may shift optimal alpha.
#
# Reuses: data/fresh_nested_loso_v15_phase1.rds  (M1 fold cache, unchanged)
# Output: data/fresh_nested_loso_v16_ckpt.rds         (resumable)
#         data/fresh_nested_loso_v16_production.rds
# Expand: data/fresh_nested_loso_v16_expand_production.rds (post-expansion)

source("scripts/fresh_run/00_shared.R")
cat("=== Step 4e: M2 Nested LOSO v16 (RE-fix) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# ---- Data ----
allD   <- load_allD(exclude = EXCLUDE_PERM)
params <- readRDS("data/fresh_m0_tuning.rds")$best_params
cat("allD:", nrow(allD), "rows\n")

EXCLUDE_SEAS <- "2015-16"
test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("Test seasons (", length(test_seasons), "):", paste(test_seasons, collapse = ", "), "\n\n")

# ---- Load M1 fold cache (reused from v15-postfix) ----
cat("Loading M1 fold cache...\n")
m1_cache_path <- "data/fresh_nested_loso_v15_phase1.rds"
if (!file.exists(m1_cache_path))
  stop("M1 cache not found: ", m1_cache_path, "\nRun 04_m2_loso.R first.")
m1_cache <- readRDS(m1_cache_path)
cat("M1 cache loaded:", length(m1_cache), "folds.\n\n")

# ---- Focused grid: same structure as v15-postfix; bias_alpha extended ----
# bias_alpha range now 0.1–0.7 (RE fix reduces need for high alpha)
# 3 x 2 x 4 x 2 x 5 = 240 specs
grid_v16 <- tidyr::crossing(
  delta       = 0L,
  Kr          = 1L,
  k_f         = c(4L, 5L, 6L),
  k_e         = c(2L, 3L),
  alpha_state = c(0.30, 0.35, 0.40, 0.45),
  k_r         = 0L,
  k_de        = 0L,
  k_sp        = c(0L, 2L),
  bias_alpha  = c(0.1, 0.3, 0.5, 0.7, 1.0),
  bias_beta   = 0.0
)
cat("Grid size:", nrow(grid_v16), "specs\n\n")

specs_v16 <- purrr::pmap(grid_v16, function(delta, Kr, k_f, k_e, alpha_state,
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
names(specs_v16) <- paste0(
  "d+", grid_v16$delta, "_Kr", grid_v16$Kr,
  "_kf", grid_v16$k_f, "_ke", grid_v16$k_e,
  "_as", grid_v16$alpha_state,
  "_kr", grid_v16$k_r, "_kde", grid_v16$k_de, "_ksp", grid_v16$k_sp,
  "_ba", grid_v16$bias_alpha, "_bb", grid_v16$bias_beta
)

# ---- Phase 2: Evaluate all specs ----
cat("=== PHASE 2: M2 grid search (", length(specs_v16), "specs) ===\n")
ckpt_path <- "data/fresh_nested_loso_v16_ckpt.rds"

if (file.exists(ckpt_path)) {
  cv_results <- readRDS(ckpt_path)
  todo_ids   <- setdiff(names(specs_v16), names(cv_results))
  cat("Resuming:", length(cv_results), "done,", length(todo_ids), "remaining\n\n")
} else {
  cv_results <- list()
  todo_ids   <- names(specs_v16)
}

if (length(todo_ids) > 0) {
  batch_size   <- n_cores
  todo_batches <- split(todo_ids, ceiling(seq_along(todo_ids) / batch_size))
  future::plan(future::multicore, workers = n_cores)

  for (bi in seq_along(todo_batches)) {
    batch <- todo_batches[[bi]]
    cat(sprintf("Batch %d/%d (%d specs)...", bi, length(todo_batches), length(batch)))
    t0 <- proc.time()[["elapsed"]]

    batch_res <- furrr::future_map(
      stats::setNames(batch, batch),
      function(spec_id) {
        spec        <- specs_v16[[spec_id]]
        fold_scores <- vector("list", length(test_seasons))
        fold_preds  <- vector("list", length(test_seasons))
        names(fold_scores) <- names(fold_preds) <- test_seasons

        for (test_s in test_seasons) {
          fc <- m1_cache[[test_s]]

          m2_fit <- tryCatch(
            nested_loso_m2_train(
              fold = fc$fold, m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0)
                fc$m1_train else NULL,
              spec = spec, method = "REML", verbose = FALSE
            ), error = function(e) NULL)

          manual_labels_train_fold <- manual_labels[setdiff(names(manual_labels), test_s)]
          eval_out <- tryCatch(
            nested_loso_m2_eval_frozen_bias(
              allD = allD, fold = fc$fold, m2_fit = m2_fit,
              m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0)
                fc$m1_test else NULL,
              spec = spec, eval_window = 12L,
              bias_alpha = spec$bias_alpha,
              manual_labels_train = manual_labels_train_fold,
              manual_labels_test  = NULL,
              flag_args = flag_args, verbose = FALSE
            ), error = function(e) NULL)

          fold_scores[[test_s]] <- if (is.null(eval_out))
            tibble::tibble(season = test_s, n = NA_integer_,
                           mean_nll = NA_real_, bernoulli_nll = NA_real_,
                           brier = NA_real_, rmse_p = NA_real_)
          else eval_out$scores
          fold_preds[[test_s]] <- if (is.null(eval_out)) tibble::tibble() else eval_out$predictions
        }
        list(scores = dplyr::bind_rows(fold_scores),
             predictions = dplyr::bind_rows(fold_preds))
      },
      .options = furrr::furrr_options(seed = TRUE)
    )

    cv_results <- c(cv_results, batch_res)
    saveRDS(cv_results, ckpt_path)

    elapsed    <- round(proc.time()[["elapsed"]] - t0)
    batch_nlls <- sapply(batch_res, function(r) round(mean(r$scores$bernoulli_nll, na.rm = TRUE), 4))
    cat(sprintf(" %ds | nll range: %.4f-%.4f\n",
                elapsed, min(batch_nlls, na.rm = TRUE), max(batch_nlls, na.rm = TRUE)))
  }
  future::plan(future::sequential)
} else {
  cat("All specs already evaluated — skipping.\n\n")
}

# ---- Assemble results ----
cat("\n=== Assembling v16 results ===\n")
cv_results_all <- cv_results[names(specs_v16)]
all_scores <- purrr::imap_dfr(cv_results_all, ~ dplyr::mutate(.x$scores, spec_id = .y))

summary_df <- all_scores |>
  dplyr::group_by(spec_id) |>
  dplyr::summarise(
    n_seasons     = dplyr::n(),
    bernoulli_nll = mean(bernoulli_nll, na.rm = TRUE),
    mean_nll      = mean(mean_nll,      na.rm = TRUE),
    brier         = mean(brier,         na.rm = TRUE),
    rmse_p        = mean(rmse_p,        na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::arrange(bernoulli_nll)

best_id   <- summary_df$spec_id[1]
best_spec <- specs_v16[[best_id]]

cat("\nTop 10 specs:\n")
print(utils::head(summary_df[, c("spec_id", "bernoulli_nll", "brier")], 10), n = 10)
cat("\nBest spec:", best_id, "| NLL:", round(summary_df$bernoulli_nll[1], 5), "\n")

# Boundary diagnostics
for (dim_nm in c("kf", "ke", "as", "ksp", "ba")) {
  pat     <- paste0("_", dim_nm, "([0-9.]+)")
  vals    <- as.numeric(sub(paste0(".*", pat, ".*"), "\\1", summary_df$spec_id))
  best_v  <- vals[1]
  rng     <- range(unique(vals))
  at_lo   <- best_v == rng[1]
  at_hi   <- best_v == rng[2]
  flag    <- if (at_lo || at_hi) " *** BOUNDARY ***" else ""
  cat(sprintf("  %-12s best=%-6g grid=[%g, %g]%s\n", dim_nm, best_v, rng[1], rng[2], flag))
}

saveRDS(list(
  scores       = all_scores,
  summary      = summary_df,
  best_spec_id = best_id,
  best_spec    = best_spec,
  cv_results   = cv_results_all,
  grid         = grid_v16
), "data/fresh_nested_loso_v16_production.rds")
cat("\nSaved: data/fresh_nested_loso_v16_production.rds\n")

# ---- Comparison vs v15-postfix ----
cat("\n=== Comparison vs v15-postfix (pre-RE-fix) ===\n")
v15 <- readRDS("data/fresh_nested_loso_v15_postfix_production.rds")
v15_sum <- v15$summary |> dplyr::arrange(bernoulli_nll)
cat("v15-postfix best:", v15_sum$spec_id[1], "| NLL:", round(v15_sum$bernoulli_nll[1], 5), "\n")
cat("v16 (RE-fix) best:", best_id,           "| NLL:", round(summary_df$bernoulli_nll[1], 5), "\n")
cat("NLL delta (v16-v15):", round(summary_df$bernoulli_nll[1] - v15_sum$bernoulli_nll[1], 5), "\n")

cat("\nEnd:", format(Sys.time()), "\n")
