#!/usr/bin/env Rscript
# Step 4f — M2 Boundary Expansion for v16 (RE-fix)
#
# v16 initial grid (240 specs) had ALL 5 dimensions at their lower boundaries.
# ke (lower=2) and ksp (lower=0) are hard-floor; no expansion there.
# Expands: kf (can go to 3, 2), as (can go to 0.25, 0.20), ba (can go to 0.05).
#
# Reads:   data/fresh_nested_loso_v16_production.rds
#          data/fresh_nested_loso_v15_phase1.rds
# Updates: data/fresh_nested_loso_v16_production.rds  (merged)
#          data/fresh_nested_loso_v16_ckpt.rds         (merged)

source("scripts/fresh_run/00_shared.R")
cat("=== Step 4f: M2 Boundary Expansion v16 (RE-fix) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# ---- Load current results ----
results_path <- "data/fresh_nested_loso_v16_production.rds"
ckpt_path    <- "data/fresh_nested_loso_v16_ckpt.rds"

if (!file.exists(results_path)) stop("Run 04e_m2_loso_v16.R first.")
res          <- readRDS(results_path)
cv_results   <- res$cv_results
summary_df   <- res$summary
grid_current <- res$grid

allD         <- load_allD(exclude = EXCLUDE_PERM)
m1_cache     <- readRDS("data/fresh_nested_loso_v15_phase1.rds")
test_seasons <- sort(setdiff(unique(allD$season), "2015-16"))

cat("Loaded:", nrow(grid_current), "specs in current grid\n")
cat("Current best:", summary_df$spec_id[1], "| NLL:", round(summary_df$bernoulli_nll[1], 5), "\n\n")

# ---- Boundary check helpers ----
check_boundary <- function(df, dim_name, grid_vals) {
  best_val <- as.numeric(sub(
    paste0(".*_", dim_name, "([0-9.]+).*"), "\\1",
    df$spec_id[which.min(df$bernoulli_nll)]))
  list(
    best_val  = best_val,
    at_lower  = best_val == min(grid_vals),
    at_upper  = best_val == max(grid_vals),
    grid_vals = grid_vals
  )
}

# Dimension definitions: id in spec_id, col in grid, step, hard lo/hi
# ke lower=2 and ksp lower=0 are hard floors — no expansion below those.
DIMS <- list(
  list(id = "kf",  col = "k_f",         step = 1L,     lo = 2L,    hi = 12L,
       to_int = TRUE),
  list(id = "ke",  col = "k_e",         step = 1L,     lo = 2L,    hi = 6L,
       to_int = TRUE),
  list(id = "as",  col = "alpha_state",  step = 0.05,   lo = 0.10,  hi = 0.70,
       to_int = FALSE),
  list(id = "ksp", col = "k_sp",        step = 2L,     lo = 0L,    hi = 8L,
       to_int = TRUE),
  list(id = "ba",  col = "bias_alpha",   step = 0.05,   lo = 0.01,  hi = 1.0,
       to_int = FALSE)
)

make_spec_from_row <- function(r) {
  stage2_make_spec(
    delta = r$delta, Kr = r$Kr, T = "S",
    k_f   = r$k_f,   k_e = r$k_e, alpha_state = r$alpha_state,
    k_r   = r$k_r,   k_de = r$k_de, k_sp = r$k_sp,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = r$bias_alpha, bias_beta = r$bias_beta
  )
}

spec_id_from_row <- function(r) {
  paste0("d+", r$delta, "_Kr", r$Kr,
         "_kf", r$k_f, "_ke", r$k_e, "_as", r$alpha_state,
         "_kr", r$k_r, "_kde", r$k_de, "_ksp", r$k_sp,
         "_ba", r$bias_alpha, "_bb", r$bias_beta)
}

eval_specs <- function(specs_new, spec_ids_new) {
  future::plan(future::multicore, workers = n_cores)
  batch_size   <- n_cores
  todo_batches <- split(spec_ids_new, ceiling(seq_along(spec_ids_new) / batch_size))
  new_cv <- list()

  for (bi in seq_along(todo_batches)) {
    batch <- todo_batches[[bi]]
    cat(sprintf("  Batch %d/%d (%d specs)...", bi, length(todo_batches), length(batch)))
    t0 <- proc.time()[["elapsed"]]

    batch_results <- furrr::future_map(
      stats::setNames(batch, batch),
      function(spec_id) {
        spec        <- specs_new[[spec_id]]
        fold_scores <- vector("list", length(test_seasons))
        fold_preds  <- vector("list", length(test_seasons))
        names(fold_scores) <- names(fold_preds) <- test_seasons

        for (test_s in test_seasons) {
          fc <- m1_cache[[test_s]]
          m2_fit <- tryCatch(
            nested_loso_m2_train(
              fold = fc$fold,
              m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0)
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
    new_cv     <- c(new_cv, batch_results)
    elapsed    <- round(proc.time()[["elapsed"]] - t0)
    batch_nlls <- sapply(batch_results, function(r)
      round(mean(r$scores$bernoulli_nll, na.rm = TRUE), 4))
    cat(sprintf(" %ds | nll range: %.4f-%.4f\n",
                elapsed, min(batch_nlls, na.rm = TRUE), max(batch_nlls, na.rm = TRUE)))
  }
  future::plan(future::sequential)
  new_cv
}

rebuild_summary <- function(cv_all) {
  all_sc <- purrr::imap_dfr(cv_all, ~ dplyr::mutate(.x$scores, spec_id = .y))
  all_sc |>
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
}

# ---- Expansion loop ----
MAX_ROUNDS <- 8L
for (round_i in seq_len(MAX_ROUNDS)) {
  cat(sprintf("\n=== Boundary check round %d ===\n", round_i))

  best_id      <- summary_df$spec_id[1]
  best_nll_val <- summary_df$bernoulli_nll[1]
  cat(sprintf("Current best: %s  NLL=%.5f\n\n", best_id, best_nll_val))

  new_grid_rows <- list()

  for (d in DIMS) {
    col_vals <- sort(unique(grid_current[[d$col]]))
    bc <- check_boundary(summary_df, d$id, col_vals)
    cat(sprintf("  %-12s best=%-6s grid=[%s]", d$col, bc$best_val,
                paste(col_vals, collapse = ",")))

    extend_vals <- numeric(0)
    if (bc$at_lower && bc$best_val - d$step >= d$lo) {
      new_val <- if (d$to_int) as.integer(bc$best_val - d$step)
                 else round(bc$best_val - d$step, 6)
      extend_vals <- new_val
      cat(sprintf("  LOWER → adding %s", new_val))
    }
    if (bc$at_upper && bc$best_val + d$step <= d$hi) {
      new_val <- if (d$to_int) as.integer(bc$best_val + d$step)
                 else round(bc$best_val + d$step, 6)
      extend_vals <- c(extend_vals, new_val)
      cat(sprintf("  UPPER → adding %s", new_val))
    }
    cat("\n")

    if (length(extend_vals) > 0) {
      for (ev in extend_vals) {
        tmp_grid          <- grid_current
        tmp_grid[[d$col]] <- ev
        new_grid_rows[[length(new_grid_rows) + 1]] <- tmp_grid
      }
    }
  }

  if (length(new_grid_rows) == 0) {
    cat("\nNo boundary hits — expansion complete.\n")
    break
  }

  new_grid <- dplyr::distinct(dplyr::bind_rows(new_grid_rows))
  new_grid$spec_id_tmp <- purrr::pmap_chr(new_grid, function(...) spec_id_from_row(list(...)))
  new_grid <- new_grid[!new_grid$spec_id_tmp %in% names(cv_results), ]
  new_grid$spec_id_tmp <- NULL

  if (nrow(new_grid) == 0) {
    cat("All expansion specs already evaluated — expansion complete.\n")
    break
  }

  cat(sprintf("\nEvaluating %d new specs...\n", nrow(new_grid)))

  specs_new    <- purrr::pmap(new_grid, function(...) make_spec_from_row(list(...)))
  spec_ids_new <- purrr::pmap_chr(new_grid, function(...) spec_id_from_row(list(...)))
  names(specs_new) <- spec_ids_new

  new_cv      <- eval_specs(specs_new, spec_ids_new)
  cv_results  <- c(cv_results, new_cv)

  grid_current <- dplyr::distinct(dplyr::bind_rows(
    grid_current,
    new_grid[, names(grid_current)]
  ))

  summary_df <- rebuild_summary(cv_results)

  # Boundary diagnostics after round
  cat(sprintf("\nAfter round %d: best=%s  NLL=%.5f\n", round_i,
              summary_df$spec_id[1], summary_df$bernoulli_nll[1]))
  for (d in DIMS) {
    col_vals <- sort(unique(grid_current[[d$col]]))
    bc <- check_boundary(summary_df, d$id, col_vals)
    flag <- if (bc$at_lower || bc$at_upper) " *** BOUNDARY ***" else ""
    cat(sprintf("  %-12s best=%-6g grid=[%g, %g]%s\n",
                d$id, bc$best_val, min(col_vals), max(col_vals), flag))
  }

  # Save checkpoint after each round
  saveRDS(list(
    scores       = purrr::imap_dfr(cv_results, ~ dplyr::mutate(.x$scores, spec_id = .y)),
    summary      = summary_df,
    best_spec_id = summary_df$spec_id[1],
    best_spec    = NULL,
    cv_results   = cv_results,
    grid         = grid_current
  ), ckpt_path)
  cat(sprintf("Checkpoint saved: %s\n", ckpt_path))
}

# ---- Save final results ----
cat("\n=== Top 10 specs (final) ===\n")
print(head(summary_df[, c("spec_id", "bernoulli_nll", "brier")], 10))

best_id <- summary_df$spec_id[1]
best_spec <- {
  r <- grid_current[purrr::pmap_chr(grid_current, function(...) spec_id_from_row(list(...))) == best_id, ]
  if (nrow(r) == 1L) make_spec_from_row(as.list(r[1, ])) else NULL
}

saveRDS(list(
  scores       = purrr::imap_dfr(cv_results, ~ dplyr::mutate(.x$scores, spec_id = .y)),
  summary      = summary_df,
  best_spec_id = best_id,
  best_spec    = best_spec,
  cv_results   = cv_results,
  grid         = grid_current
), results_path)
cat("\nSaved:", results_path, "\n")

# ---- Boundary diagnostics (final) ----
cat("\n=== Final boundary diagnostics ===\n")
for (d in DIMS) {
  col_vals <- sort(unique(grid_current[[d$col]]))
  bc <- check_boundary(summary_df, d$id, col_vals)
  flag <- if (bc$at_lower || bc$at_upper) " *** BOUNDARY ***" else ""
  cat(sprintf("  %-12s best=%-6g grid=[%g, %g]%s\n",
              d$id, bc$best_val, min(col_vals), max(col_vals), flag))
}

# ---- Comparison vs v15-postfix ----
cat("\n=== Comparison vs v15-postfix (pre-RE-fix) ===\n")
v15 <- readRDS("data/fresh_nested_loso_v15_postfix_production.rds")
v15_sum <- v15$summary |> dplyr::arrange(bernoulli_nll)
cat("v15-postfix best:", v15_sum$spec_id[1], "| NLL:", round(v15_sum$bernoulli_nll[1], 5), "\n")
cat("v16 (RE-fix) best:", best_id,           "| NLL:", round(summary_df$bernoulli_nll[1], 5), "\n")
cat("NLL delta (v16-v15):", round(summary_df$bernoulli_nll[1] - v15_sum$bernoulli_nll[1], 5), "\n")
cat("Total specs evaluated:", length(cv_results), "\n")

cat("\nEnd:", format(Sys.time()), "\n")
