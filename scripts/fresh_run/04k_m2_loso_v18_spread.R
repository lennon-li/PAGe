#!/usr/bin/env Rscript
# Step 4k — M2 LOSO v18: logit_spread improvement (Phase 2)
#
# Tests whether the improved logit_spread (Phase 2: between + within GAM SE)
# shifts the optimal k_sp for the M2 GAM. Runs a focused ksp sweep at the
# v16 best spec (kf=4/ke=2/as=0.15/kr=0/kde=0/ba=0.05), varying ksp only.
#
# Phase A: Rebuild M1 fold cache with updated logit_spread
#          → data/fresh_nested_loso_v18_phase1.rds
# Phase B: M2 ksp sweep (6 specs x 10 folds)
#          → data/fresh_nested_loso_v18_ksp_sweep.rds

source("scripts/fresh_run/00_shared.R")
cat("=== Step 4k: M2 LOSO v18 — logit_spread ksp sweep ===\n")
cat("Start:", format(Sys.time()), "\n\n")

allD   <- load_allD(exclude = EXCLUDE_PERM)
params <- readRDS("data/fresh_m0_tuning.rds")$best_params

EXCLUDE_SEAS <- "2015-16"
test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("Test seasons (", length(test_seasons), "):", paste(test_seasons, collapse = ", "), "\n\n")

p1_cache_path <- "data/fresh_nested_loso_v18_phase1.rds"

# ============================================================
# PHASE A: Rebuild M1 fold cache with Phase 2 logit_spread
# ============================================================
if (file.exists(p1_cache_path)) {
  cat("=== PHASE A: Loading existing M1 cache ===\n")
  m1_cache <- readRDS(p1_cache_path)
  cat("Loaded", length(m1_cache), "folds.\n\n")
} else {
  cat("=== PHASE A: Building M1 fold cache (Phase 2 logit_spread) ===\n")
  future::plan(future::multisession, workers = n_cores)
  m1_cache <- list()

  for (test_s in test_seasons) {
    cat(sprintf("[%s] Building fold + M1...\n", test_s))
    t0 <- proc.time()[["elapsed"]]

    fold <- tryCatch(
      nested_loso_build_fold(
        allD = allD, test_season = test_s, exclude_seasons = EXCLUDE_SEAS,
        k_ref = M1_PARAMS$k_ref, ref_method = M1_PARAMS$ref_method,
        manual_labels = manual_labels, verbose = FALSE
      ),
      error = function(e) { message("  ERROR: ", conditionMessage(e)); NULL }
    )
    if (is.null(fold)) next

    m1_train <- tryCatch(
      m1_walkforward_multi(
        allD = allD, ref = fold$ref, hyper = fold$hyper, params = params,
        seasons = fold$train_seasons,
        temperature = M1_PARAMS$temperature, rise_weight = M1_PARAMS$rise_weight,
        trough_weight = M1_PARAMS$trough_weight, peak_decay = M1_PARAMS$peak_decay,
        slope_weight = M1_PARAMS$slope_weight, slope_window = M1_PARAMS$slope_window,
        dynamic_temp = M1_PARAMS$dynamic_temp,
        dynamic_temp_pivot = M1_PARAMS$dynamic_temp_pivot,
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
        dynamic_temp = M1_PARAMS$dynamic_temp,
        dynamic_temp_pivot = M1_PARAMS$dynamic_temp_pivot
      ),
      error = function(e) { message("  ERROR m1_test: ", conditionMessage(e)); NULL }
    )

    m1_cache[[test_s]] <- list(fold = fold, m1_train = m1_train, m1_test = m1_test)
    cat(sprintf("  Done in %ds | train rows: %d | test rows: %d\n\n",
                round(proc.time()[["elapsed"]] - t0),
                if (!is.null(m1_train)) nrow(m1_train) else 0L,
                if (!is.null(m1_test))  nrow(m1_test)  else 0L))
  }
  future::plan(future::sequential)

  saveRDS(m1_cache, p1_cache_path)
  cat("Saved Phase A cache:", p1_cache_path, "\n")
}
cat("Phase A complete:", length(m1_cache), "folds.\n\n")

# ============================================================
# PHASE B: ksp sweep at v16 best spec
# ============================================================
cat("=== PHASE B: ksp sweep (kf=4, ke=2, as=0.15, ba=0.05) ===\n")

grid <- expand.grid(
  delta       = 0L,
  Kr          = 1L,
  k_f         = 4L,
  k_e         = 2L,
  alpha_state = 0.15,
  k_r         = 0L,
  k_de        = 0L,
  k_sp        = c(0L, 2L, 4L, 6L, 8L, 10L),
  bias_alpha  = 0.05,
  bias_beta   = 0.0,
  stringsAsFactors = FALSE
)
cat("Grid:", nrow(grid), "specs (ksp sweep only)\n\n")

make_spec <- function(r) {
  stage2_make_spec(
    delta = r$delta, Kr = r$Kr, T = "S",
    k_f = r$k_f, k_e = r$k_e, alpha_state = r$alpha_state,
    k_r = r$k_r, k_de = r$k_de, k_sp = r$k_sp,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = r$bias_alpha, bias_beta = r$bias_beta
  )
}

spec_id <- function(r) {
  paste0("d+", r$delta, "_Kr", r$Kr,
         "_kf", r$k_f, "_ke", r$k_e, "_as", r$alpha_state,
         "_kr", r$k_r, "_kde", r$k_de, "_ksp", r$k_sp,
         "_ba", r$bias_alpha, "_v18")
}

specs     <- purrr::pmap(grid, function(...) make_spec(list(...)))
spec_ids  <- purrr::pmap_chr(grid, function(...) spec_id(list(...)))
names(specs) <- spec_ids

future::plan(future::multicore, workers = n_cores)

cv_results <- furrr::future_map(
  stats::setNames(spec_ids, spec_ids),
  function(sid) {
    spec <- specs[[sid]]
    fold_scores <- vector("list", length(test_seasons))
    fold_preds  <- vector("list", length(test_seasons))
    names(fold_scores) <- names(fold_preds) <- test_seasons

    for (test_s in test_seasons) {
      fc <- m1_cache[[test_s]]
      m2_fit <- tryCatch(
        nested_loso_m2_train(
          fold           = fc$fold,
          m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
          spec = spec, method = "REML", verbose = FALSE
        ), error = function(e) NULL)

      manual_labels_fold <- manual_labels[setdiff(names(manual_labels), test_s)]
      eval_out <- tryCatch(
        nested_loso_m2_eval_frozen_bias(
          allD = allD, fold = fc$fold, m2_fit = m2_fit,
          m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
          spec = spec, eval_window = 12L, bias_alpha = spec$bias_alpha,
          manual_labels_train = manual_labels_fold,
          manual_labels_test  = NULL,
          flag_args = flag_args, verbose = FALSE
        ), error = function(e) NULL)

      if (is.null(eval_out)) {
        fold_scores[[test_s]] <- tibble::tibble(
          season = test_s, n = NA_integer_,
          mean_nll = NA_real_, bernoulli_nll = NA_real_,
          brier = NA_real_, rmse_p = NA_real_)
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

future::plan(future::sequential)

# Summarise
summary_df <- purrr::imap_dfr(cv_results, ~ dplyr::mutate(.x$scores, spec_id = .y)) |>
  dplyr::group_by(spec_id) |>
  dplyr::summarise(
    n_seasons     = dplyr::n(),
    bernoulli_nll = mean(bernoulli_nll, na.rm = TRUE),
    brier         = mean(brier, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::arrange(bernoulli_nll)

cat("\n=== Phase B results ===\n")
print(dplyr::left_join(
  summary_df,
  cbind(spec_id = spec_ids, grid),
  by = "spec_id"
) |> dplyr::select(k_sp, bernoulli_nll, brier, n_seasons))

# Compare to v16 baseline
v16 <- readRDS("data/fresh_nested_loso_v16_production.rds")
v16_best <- v16$summary$bernoulli_nll[1]
cat(sprintf("\nv16 best NLL: %.5f\n", v16_best))
cat(sprintf("v18 best NLL: %.5f  (Δ = %+.5f)\n",
            summary_df$bernoulli_nll[1],
            summary_df$bernoulli_nll[1] - v16_best))

saveRDS(list(
  summary    = summary_df,
  cv_results = cv_results,
  grid       = grid
), "data/fresh_nested_loso_v18_ksp_sweep.rds")
cat("\nSaved: data/fresh_nested_loso_v18_ksp_sweep.rds\n")
cat("End:", format(Sys.time()), "\n")
