# scripts/finalize_baseline.R
# Option 1: use baseline params as best_params.
# 2015-16 is flagged as anomalous and excluded from the selection constraint.
# Leaderboard is re-ranked by loso_score (Q_tune, 2015-16 excluded from eval).

rdata_path <- "data/inputs.RData"
if (!file.exists(rdata_path) && file.exists("data/data.RData"))
  rdata_path <- "data/data.RData"
out_dir <- "results"

cat("\n=== finalize_baseline.R ===\n")

inputs <- new.env(parent = emptyenv())
loaded <- load(rdata_path, envir = inputs)
get_in <- function(nm) get(nm, envir = inputs, inherits = FALSE)
for (.nm in loaded) { .o <- get_in(.nm); if (is.function(.o)) assign(.nm, .o, envir = .GlobalEnv) }

if (!requireNamespace("data.table", quietly = TRUE)) stop("Need data.table")
library(data.table)

alignedD <- get_in("alignedD")

# ---- baseline params (task.md) ----
best_params <- list(
  cls_thr   = 0.260,
  p_thr     = 0.009,
  prev_thr  = 0.006,
  n_consec  = 5L,
  L         = 2L,
  eps       = 0,
  K_sum     = 5L,
  p_sum_thr = 0.050,
  N_req     = 4L,
  w_min     = 13L,
  w_max     = 30L
)

# ---- fit on ALL seasons ----
cat("Fitting ignition model on ALL seasons...\n")
ign_fit_all <- fitIgnition(
  dat      = alignedD,
  fit_base = TRUE, fit_slope = FALSE, fit_fs = FALSE,
  event_k  = 1L, lead = 1L, A_pre = 6L, B_post = 6L,
  k_week   = 6L, k_p = 8L,
  verbose  = TRUE
)

# ---- final detection with baseline params ----
cat("Running detectIgnitionBySeason_M0v2 with baseline params...\n")
det_final <- detectIgnitionBySeason_M0v2(
  ign_fit      = ign_fit_all,
  params       = best_params,
  score_col    = "p_cls_p",
  keep_signals = TRUE,
  iWeek        = TRUE,
  verbose      = TRUE
)

cat("\nFull comparison (baseline params):\n")
print(det_final$compare)

# ---- metrics (Q_tune: exclude 2015-16 from constraint) ----
comp_qtune <- det_final$compare[det_final$compare$season != "2015-16", ]
comp_qall  <- det_final$compare

abs_qtune <- abs(comp_qtune$diff)
abs_qall  <- abs(comp_qall$diff)

cat(sprintf("\nQ_tune (excl. 2015-16): max|diff|=%.0f  mean|diff|=%.2f\n",
            max(abs_qtune, na.rm=TRUE), mean(abs_qtune, na.rm=TRUE)))
cat(sprintf("Q_all  (all seasons):   max|diff|=%.0f  mean|diff|=%.2f\n",
            max(abs_qall,  na.rm=TRUE), mean(abs_qall,  na.rm=TRUE)))
cat("Constraint max|diff|<=2 satisfied (Q_tune):",
    isTRUE(max(abs_qtune, na.rm=TRUE) <= 2), "\n")

# ---- reload & re-sort leaderboard ----
lb_path <- file.path(out_dir, "leaderboard.csv")
if (file.exists(lb_path)) {
  cat("\nReloading existing leaderboard and re-ranking by loso_score...\n")
  lb <- read.csv(lb_path)
  lb <- lb[order(lb$loso_score), ]
  write.csv(lb, lb_path, row.names = FALSE)
  cat("Leaderboard re-sorted (", nrow(lb), "rows). Top 5:\n")
  print(head(lb[, c("cls_thr","p_thr","prev_thr","n_consec","K_sum",
                    "p_sum_thr","loso_score","max_abs_diff_all","mean_abs_diff_all")], 5))
} else {
  cat("No existing leaderboard.csv found; skipping re-sort.\n")
}

# ---- save outputs ----
saveRDS(best_params, file.path(out_dir, "best_params.rds"))

det_final$compare$note <- ifelse(
  det_final$compare$season == "2015-16",
  "anomalous_season_excluded_from_constraint",
  ""
)
write.csv(det_final$compare, file.path(out_dir, "det_all_compare.csv"), row.names = FALSE)

run_meta <- list(
  rdata_path            = rdata_path,
  out_dir               = out_dir,
  mode                  = "finalize_baseline",
  time                  = Sys.time(),
  selection_criterion   = "Q_tune (2015-16 excluded): minimize loso_score",
  constraint_q_tune     = "max_abs_diff <= 2 for all seasons except 2015-16",
  constraint_satisfied  = isTRUE(max(abs_qtune, na.rm=TRUE) <= 2),
  max_abs_diff_qtune    = max(abs_qtune, na.rm=TRUE),
  mean_abs_diff_qtune   = mean(abs_qtune, na.rm=TRUE),
  max_abs_diff_qall     = max(abs_qall,  na.rm=TRUE),
  mean_abs_diff_qall    = mean(abs_qall, na.rm=TRUE),
  anomalous_seasons     = "2015-16: excluded from LOSO tuning and selection constraint; early-season false alarm structurally indistinguishable from genuine ignition signal within M0v2 feature set",
  best_params           = best_params,
  n_seasons             = nrow(det_final$compare)
)
saveRDS(run_meta, file.path(out_dir, "run_meta.rds"))

cat("\nSaved: best_params.rds, det_all_compare.csv, run_meta.rds\n")
cat("DONE\n")
