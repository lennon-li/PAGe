#!/usr/bin/env Rscript
# Step 1 — M0 Ignition Detection (fresh run)
# Adapted from scripts/run_loso.R
# Key fix: setwd corrected to Linux path; output to data/fresh_m0_tuning.rds
#
# Output:  data/fresh_m0_tuning.rds
# Compare: data/stage1_tuning.rds

source("scripts/fresh_run/00_shared.R")
cat("=== Step 1: M0 Ignition Detection (fresh run) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# ---- Data ----
allD <- load_allD(exclude = EXCLUDE_PERM) |>
  dplyr::mutate(
    mmwr_year = ifelse(week >= 35L, start_year, start_year + 1L),
    weekS     = ((week - 35L) %% nW_true) + 1L
  )

cat("allD:", nrow(allD), "rows |", length(unique(allD$season)), "seasons\n")
stopifnot(length(unique(allD$season)) == 11L)

aligned_d <- build_aligned(allD)

# ---- Grid ----
grid_loso <- data.table::CJ(
  cls_thr   = 0.26,
  use_cls   = FALSE,
  p_thr     = c(0.002, 0.003, 0.004, 0.005),
  prev_thr  = c(0.001, 0.002, 0.003),
  n_consec  = 5L,
  L         = 2L,
  eps       = 0,
  K_sum     = 5L,
  p_sum_thr = c(0.050, 0.055, 0.060),
  N_req     = 4L,
  w_min     = 13L,
  w_max     = 26L,
  K_dp      = 3L,
  dp_thr    = 0.01,
  sorted    = FALSE
)
cat("Grid:", nrow(grid_loso), "specs x 10 LOSO folds =", nrow(grid_loso) * 10L, "evals\n\n")

# ---- LOSO tuning ----
tuned <- loso_M0v2(
  dat          = aligned_d,
  grid         = as.data.frame(grid_loso),
  score_col    = "p_cls_p",
  drop_seasons = "2015-16",
  exSeason_tune = NULL,
  fit_args = list(
    fit_base = TRUE, fit_slope = FALSE, fit_fs = FALSE,
    event_k = 1L, lead = 1L, A_pre = 6L, B_post = 6L,
    k_week = 6L, k_p = 8L, k_fs = 4L,
    select = FALSE, verbose = FALSE
  ),
  tune_args = list(
    miss_penalty = 0, lambda = 20, kappa = 0,
    gamma = 25, gamma_late = 0,
    iWeek = TRUE, ncores = n_cores,
    verbose = FALSE, progress_every = 50L
  ),
  verbose = TRUE
)

saveRDS(tuned, "data/fresh_m0_tuning.rds")
cat("\nSaved: data/fresh_m0_tuning.rds\n")

# ---- Comparison ----
cat("\n=== Comparison vs gold (data/stage1_tuning.rds) ===\n")
gold <- readRDS("data/stage1_tuning.rds")

cat("Gold best_params:\n"); print(gold$best_params)
cat("\nFresh best_params:\n"); print(tuned$best_params)

params_match <- all.equal(
  as.list(gold$best_params[order(names(gold$best_params))]),
  as.list(tuned$best_params[order(names(tuned$best_params))])
)
cat("\nParams match:", if (isTRUE(params_match)) "YES" else paste("NO —", params_match), "\n")

if (!is.null(tuned$compare) && !is.null(gold$compare)) {
  cmp <- dplyr::inner_join(
    as.data.frame(gold$compare)  |> dplyr::rename(iWeek_gold  = iWeek_hat),
    as.data.frame(tuned$compare) |> dplyr::rename(iWeek_fresh = iWeek_hat),
    by = "season"
  ) |> dplyr::mutate(delta = iWeek_fresh - iWeek_gold)
  cat("\nPer-season ignition week delta (fresh - gold):\n")
  print(cmp[, c("season", "iWeek_gold", "iWeek_fresh", "delta")])
  cat("Max |delta|:", max(abs(cmp$delta), na.rm = TRUE), "(expected 0)\n")
}

cat("\nEnd:", format(Sys.time()), "\n")
