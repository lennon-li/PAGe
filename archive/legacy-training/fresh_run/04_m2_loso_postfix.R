#!/usr/bin/env Rscript
# Step 4b — M2 Nested LOSO Grid Search v15-postfix (fresh run)
#
# Runs the full 7200-spec v15-postfix grid (B1-B4 corrected eval loop,
# bias_alpha and bias_beta in grid) and compares to the current gold standard.
#
# Reuses data/fresh_nested_loso_v15_phase1.rds for M1 fold cache
# (M1 walk-forward uses prospective ignition — not affected by B1-B4 fixes;
#  M1 logic changes since Apr 16 are pipe-only, no algorithm change).
#
# Reads:   data/fresh_m0_tuning.rds
#          data/fresh_nested_loso_v15_phase1.rds
# Output:  data/fresh_nested_loso_v15_postfix_phase2_ckpt.rds (resumable)
#          data/fresh_nested_loso_v15_postfix_production.rds
# Compare: data/nested_loso_v15_postfix_production.rds

source("scripts/fresh_run/00_shared.R")
cat("=== Step 4b: M2 Nested LOSO v15-postfix (fresh run) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# ---- Data ----
allD   <- load_allD(exclude = EXCLUDE_PERM)
params <- readRDS("data/fresh_m0_tuning.rds")$best_params
cat("Using fresh M0 best_params; allD:", nrow(allD), "rows\n\n")

EXCLUDE_SEAS <- "2015-16"
test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("Test seasons (", length(test_seasons), "):", paste(test_seasons, collapse = ", "), "\n\n")

# ---- Focused spec grid: centered on production best spec ----
# Fixed (clear winners from 7200-spec gold): delta=0, Kr=1, k_r=0, k_de=0, bias_beta=0
# Varied: k_f {4,5,6}, k_e {2,3}, alpha_state {0.35..0.50}, k_sp {0,2}, bias_alpha {0.3..0.6}
# 3 x 2 x 4 x 2 x 4 = 192 specs
grid_v15 <- tidyr::crossing(
  delta       = 0L,
  Kr          = 1L,
  k_f         = c(4L, 5L, 6L),
  k_e         = c(2L, 3L),
  alpha_state = c(0.35, 0.40, 0.45, 0.50),
  k_r         = 0L,
  k_de        = 0L,
  k_sp        = c(0L, 2L),
  bias_alpha  = c(0.3, 0.4, 0.5, 0.6),
  bias_beta   = 0.0
)
stopifnot(nrow(grid_v15) == 192L)

specs_v15 <- purrr::pmap(grid_v15, function(delta, Kr, k_f, k_e, alpha_state,
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
names(specs_v15) <- paste0(
  "d+", grid_v15$delta, "_Kr", grid_v15$Kr,
  "_kf", grid_v15$k_f, "_ke", grid_v15$k_e,
  "_as", grid_v15$alpha_state,
  "_kr", grid_v15$k_r, "_kde", grid_v15$k_de, "_ksp", grid_v15$k_sp,
  "_ba", grid_v15$bias_alpha, "_bb", grid_v15$bias_beta
)
cat("Grid size:", length(specs_v15), "specs\n\n")

# ============================================================
# PHASE 1: Load M1 fold cache
# (reused from Step 04 / run_nested_loso_v15_postfix — M1 logic unchanged)
# ============================================================
cat("=== PHASE 1: Loading M1 fold cache ===\n")
m1_cache_path <- "data/fresh_nested_loso_v15_phase1.rds"
if (!file.exists(m1_cache_path)) {
  stop("M1 phase-1 cache not found: ", m1_cache_path,
       "\nBuild it first by running scripts/fresh_run/04_m2_loso.R (Phase 1 only).")
}
m1_cache <- readRDS(m1_cache_path)
cat("Phase 1 cache loaded:", length(m1_cache), "folds.\n\n")

# ============================================================
# PHASE 2: Evaluate all 7200 specs (B1-B4 corrected frozen + Holt + online RE)
# ============================================================
cat("=== PHASE 2: M2 grid search (7200 specs, B1-B4 corrected) ===\n")

new_spec_ids <- names(specs_v15)
phase2_ckpt  <- "data/fresh_nested_loso_v15_postfix_phase2_ckpt.rds"

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
  future::plan(future::multicore, workers = n_cores)

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

          # B4 fix: per-fold training labels only (exclude held-out season)
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
    cat(sprintf(" %ds | bernoulli_nll range: %.4f-%.4f\n",
                elapsed, min(batch_nlls, na.rm = TRUE), max(batch_nlls, na.rm = TRUE)))
  }

  future::plan(future::sequential)
} else {
  cat("All specs already evaluated — skipping.\n\n")
}

# ---- Assemble results ----
cat("\n=== Assembling v15-postfix results ===\n")
cv_results_all <- cv_results_new[names(specs_v15)]
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

cat("\nTop 10 specs by Bernoulli NLL:\n")
print(utils::head(summary_df[, c("spec_id", "bernoulli_nll", "brier")], 10), n = 10)
cat("\nFresh best spec:", best_id, "\n")
cat("Best spec params:\n")
print(unlist(best_spec[c("k_f", "k_e", "alpha_state", "k_r", "k_de", "k_sp", "bias_alpha", "bias_beta")]))

# Boundary checks
cat("\n=== alpha_state boundary check ===\n")
print(summary_df |>
  dplyr::mutate(alpha_state = as.numeric(sub("^.*_as([0-9.]+)_.*$", "\\1", spec_id))) |>
  dplyr::group_by(alpha_state) |>
  dplyr::summarise(min_bern_nll = min(bernoulli_nll, na.rm = TRUE), .groups = "drop") |>
  dplyr::arrange(alpha_state))

cat("\n=== bias_alpha boundary check ===\n")
print(summary_df |>
  dplyr::mutate(bias_alpha = as.numeric(sub("^.*_ba([0-9.]+)_bb.*$", "\\1", spec_id))) |>
  dplyr::group_by(bias_alpha) |>
  dplyr::summarise(min_bern_nll = min(bernoulli_nll, na.rm = TRUE), .groups = "drop") |>
  dplyr::arrange(bias_alpha))

saveRDS(list(
  scores       = all_scores,
  summary      = summary_df,
  best_spec_id = best_id,
  best_spec    = best_spec,
  cv_results   = cv_results_all,
  grid         = grid_v15
), "data/fresh_nested_loso_v15_postfix_production.rds")
cat("\nSaved: data/fresh_nested_loso_v15_postfix_production.rds\n")

# ---- Comparison vs gold ----
cat("\n=== Comparison vs gold (data/nested_loso_v15_postfix_production.rds) ===\n")
gold <- readRDS("data/nested_loso_v15_postfix_production.rds")
gold_sum <- gold$summary |> dplyr::arrange(bernoulli_nll)

cat("Gold best spec:", gold_sum$spec_id[1],
    "| NLL:", round(gold_sum$bernoulli_nll[1], 4), "\n")
cat("Fresh best spec:", best_id,
    "| NLL:", round(summary_df$bernoulli_nll[1], 4), "\n")

spec_match <- gold_sum$spec_id[1] == best_id
cat("Best spec match:", if (spec_match) "YES" else "NO (document as finding)", "\n")

score_cmp <- dplyr::inner_join(
  gold_sum   |> dplyr::select(spec_id, nll_gold  = bernoulli_nll),
  summary_df |> dplyr::select(spec_id, nll_fresh = bernoulli_nll),
  by = "spec_id"
) |> dplyr::mutate(delta = nll_fresh - nll_gold)

cat("Matched specs:", nrow(score_cmp), "of", nrow(summary_df), "\n")
cat("Max |NLL delta| (fresh - gold):", round(max(abs(score_cmp$delta), na.rm = TRUE), 4),
    "(warn if > 0.002)\n")

merged_nll <- dplyr::inner_join(
  all_scores  |> dplyr::select(spec_id, season, nll_fresh = bernoulli_nll),
  gold$scores |> dplyr::select(spec_id, season, nll_gold  = bernoulli_nll),
  by = c("spec_id", "season")
)
if (nrow(merged_nll) > 1) {
  nll_cor <- cor(merged_nll$nll_gold, merged_nll$nll_fresh, use = "complete.obs")
  cat("cor(gold_nll, fresh_nll):", round(nll_cor, 5), "(expected > 0.999)\n")
}

cat("\nEnd:", format(Sys.time()), "\n")
