#!/usr/bin/env Rscript
# Step 4 — M2 Nested LOSO Grid Search (fresh run)
# Adapted from scripts/run_nested_loso_v15.R
# Key change: all output paths prefixed with "fresh_"; reads fresh M0 params.
#
# Reads:   data/fresh_m0_tuning.rds
# Output:  data/fresh_nested_loso_v15_phase1.rds
#          data/fresh_nested_loso_v15_phase2.rds (resumable checkpoint)
#          data/fresh_nested_loso_v15_production.rds
# Compare: data/nested_loso_v15_production.rds

source("scripts/fresh_run/00_shared.R")
cat("=== Step 4: M2 Nested LOSO Grid Search v15 (fresh run) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# ---- Data ----
allD   <- load_allD(exclude = EXCLUDE_PERM)
params <- readRDS("data/fresh_m0_tuning.rds")$best_params
cat("Using fresh M0 best_params; allD:", nrow(allD), "rows\n\n")

EXCLUDE_SEAS <- "2015-16"
test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("Test seasons (", length(test_seasons), "):", paste(test_seasons, collapse = ", "), "\n\n")

# ---- M2 grid ----
BIAS_ALPHA <- 0.4
grid_v15 <- tidyr::crossing(
  delta       = 0L,
  Kr          = 1L,
  k_f         = c(2L, 3L, 4L, 5L),
  k_e         = c(2L, 3L),
  alpha_state = c(0.30, 0.35, 0.40, 0.45, 0.50),
  k_r         = c(0L, 2L, 3L),
  k_de        = c(0L, 2L),
  k_sp        = c(0L, 2L)
)
specs_v15 <- purrr::pmap(grid_v15, function(delta, Kr, k_f, k_e, alpha_state, k_r, k_de, k_sp) {
  stage2_make_spec(
    delta = delta, Kr = Kr, T = "S",
    k_f = k_f, k_e = k_e, alpha_state = alpha_state,
    k_r = k_r, k_de = k_de, k_sp = k_sp,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = BIAS_ALPHA
  )
})
names(specs_v15) <- paste0(
  "d+", grid_v15$delta, "_Kr", grid_v15$Kr,
  "_kf", grid_v15$k_f, "_ke", grid_v15$k_e,
  "_as", grid_v15$alpha_state, "_kr", grid_v15$k_r,
  "_kde", grid_v15$k_de, "_ksp", grid_v15$k_sp
)
cat("Grid size:", length(specs_v15), "specs\n\n")

# ============================================================
# PHASE 1: Build M1 cache (forced rebuild — no prior cache loaded)
# ============================================================
cat("=== PHASE 1: Building M1 cache ===\n")
cat("  NOT loading any prior cache — full rebuild required.\n\n")

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
      k_ref = M1_PARAMS$k_ref, ref_method = M1_PARAMS$ref_method,
      manual_labels = manual_labels, verbose = FALSE
    ),
    error = function(e) { message("  ERROR building fold: ", conditionMessage(e)); NULL }
  )
  if (is.null(fold)) next

  m1_train <- tryCatch(
    m1_walkforward_multi(
      allD = allD, ref = fold$ref, hyper = fold$hyper, params = params,
      seasons = fold$train_seasons,
      temperature = M1_PARAMS$temperature, rise_weight = M1_PARAMS$rise_weight,
      trough_weight = M1_PARAMS$trough_weight, peak_decay = M1_PARAMS$peak_decay,
      slope_weight = M1_PARAMS$slope_weight, slope_window = M1_PARAMS$slope_window,
      dynamic_temp = M1_PARAMS$dynamic_temp, dynamic_temp_pivot = M1_PARAMS$dynamic_temp_pivot,
      parallel = TRUE, verbose = FALSE
    ),
    error = function(e) { message("  ERROR m1_train: ", conditionMessage(e)); NULL }
  )

  m1_test <- tryCatch(
    m1_walkforward_predictions(
      seasonD = allD[allD$season == test_s, ], ref = fold$ref, hyper = fold$hyper,
      params = params,
      temperature = M1_PARAMS$temperature, rise_weight = M1_PARAMS$rise_weight,
      trough_weight = M1_PARAMS$trough_weight, peak_decay = M1_PARAMS$peak_decay,
      slope_weight = M1_PARAMS$slope_weight, slope_window = M1_PARAMS$slope_window,
      dynamic_temp = M1_PARAMS$dynamic_temp, dynamic_temp_pivot = M1_PARAMS$dynamic_temp_pivot
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
  saveRDS(m1_cache, "data/fresh_nested_loso_v15_phase1.rds")
  cat("Saved Phase 1 cache to data/fresh_nested_loso_v15_phase1.rds\n")
}
cat("Phase 1 complete:", length(m1_cache), "folds.\n\n")

if (Sys.getenv("SMOKE_TEST", unset = "0") == "1") {
  cat("=== SMOKE TEST: 1 fold x 1 spec ===\n")
  test_s   <- test_seasons[1]
  fc       <- m1_cache[[test_s]]
  smoke_id <- names(specs_v15)[which(
    grid_v15$k_f == 4L & grid_v15$k_e == 2L & grid_v15$alpha_state == 0.40 &
    grid_v15$k_r == 2L & grid_v15$k_de == 0L & grid_v15$k_sp == 0L
  )[1]]
  smoke_spec <- specs_v15[[smoke_id]]
  m2_fit <- nested_loso_m2_train(
    fold = fc$fold,
    m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
    spec = smoke_spec, method = "REML", verbose = TRUE
  )
  eval_out <- nested_loso_m2_eval_frozen_bias(
    allD = allD, fold = fc$fold, m2_fit = m2_fit,
    m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
    spec = smoke_spec, eval_window = 12L, bias_alpha = BIAS_ALPHA,
    manual_labels = manual_labels, flag_args = flag_args, verbose = FALSE
  )
  cat("Smoke test scores:\n"); print(eval_out$scores)
  stopifnot("bernoulli_nll" %in% names(eval_out$scores))
  cat("=== SMOKE TEST PASSED ===\n")
  quit(save = "no")
}

# ============================================================
# PHASE 2: Evaluate all 480 specs (resumable checkpoint)
# ============================================================
cat("=== PHASE 2: M2 grid search (480 specs, frozen + Holt + online RE) ===\n")

new_spec_ids <- names(specs_v15)
phase2_ckpt  <- "data/fresh_nested_loso_v15_phase2.rds"

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
              fold = fc$fold,
              m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
              spec = spec, method = "REML", verbose = FALSE
            ),
            error = function(e) NULL
          )
          eval_out <- tryCatch(
            nested_loso_m2_eval_frozen_bias(
              allD = allD, fold = fc$fold, m2_fit = m2_fit,
              m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
              spec = spec, eval_window = 12L, bias_alpha = BIAS_ALPHA,
              manual_labels = manual_labels, flag_args = flag_args, verbose = FALSE
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

# ---- Assemble results ----
cat("\n=== Assembling v15 results ===\n")
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
cat("Fresh best spec params:\n")
print(unlist(best_spec[c("k_f", "k_e", "alpha_state", "k_r", "k_de", "k_sp")]))

results <- list(
  scores       = all_scores,
  summary      = summary_df,
  best_spec_id = best_id,
  best_spec    = best_spec,
  cv_results   = cv_results_all,
  grid         = grid_v15
)
saveRDS(results, "data/fresh_nested_loso_v15_production.rds")
cat("\nSaved: data/fresh_nested_loso_v15_production.rds\n")

# ---- Comparison ----
cat("\n=== Comparison vs gold (data/nested_loso_v15_production.rds) ===\n")
gold_v15 <- readRDS("data/nested_loso_v15_production.rds")
gold_sum  <- gold_v15$summary |> dplyr::arrange(bernoulli_nll)
cat("Gold best spec:", gold_sum$spec_id[1], "NLL:", round(gold_sum$bernoulli_nll[1], 4), "\n")
cat("Fresh best spec:", best_id, "NLL:", round(summary_df$bernoulli_nll[1], 4), "\n")
if (gold_sum$spec_id[1] != best_id)
  warning("Best spec_id differs between gold and fresh — document as genuine finding.")

score_cmp <- dplyr::inner_join(
  gold_sum  |> dplyr::select(spec_id, nll_gold  = bernoulli_nll),
  summary_df |> dplyr::select(spec_id, nll_fresh = bernoulli_nll),
  by = "spec_id"
) |> dplyr::mutate(delta = nll_fresh - nll_gold)
cat("Max |NLL delta| (fresh - gold):", round(max(abs(score_cmp$delta), na.rm = TRUE), 4),
    "(warn if > 0.002)\n")
merged_nll <- dplyr::inner_join(
  all_scores    |> dplyr::select(spec_id, season, nll_fresh = bernoulli_nll),
  gold_v15$scores |> dplyr::select(spec_id, season, nll_gold  = bernoulli_nll),
  by = c("spec_id", "season")
)
cat("cor(gold_nll, fresh_nll):", round(cor(merged_nll$nll_gold, merged_nll$nll_fresh,
                                            use = "complete.obs"), 5),
    "(expected > 0.999)\n")

cat("\nEnd:", format(Sys.time()), "\n")
