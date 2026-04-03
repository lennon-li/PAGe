# scripts/tune_targeted.R
# Targeted search: starting from baseline params, find the smallest change that
# reduces 2015-16's |diff| while keeping ALL other seasons at |diff| <= 2.
#
# Usage:
#   Rscript scripts/tune_targeted.R

rdata_path <- "data/inputs.RData"
if (!file.exists(rdata_path) && file.exists("data/data.RData"))
  rdata_path <- "data/data.RData"
out_dir <- "results"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("\n=== tune_targeted.R ===\n")
cat("rdata:", rdata_path, "\n\n")

# ---- load ----
if (!file.exists(rdata_path)) stop("RData not found: ", rdata_path)
inputs <- new.env(parent = emptyenv())
loaded <- load(rdata_path, envir = inputs)
get_in <- function(nm) get(nm, envir = inputs, inherits = FALSE)

for (.nm in loaded) {
  .obj <- get_in(.nm)
  if (is.function(.obj)) assign(.nm, .obj, envir = .GlobalEnv)
}

if (!requireNamespace("data.table", quietly = TRUE)) stop("Need data.table")
library(data.table)

alignedD <- get_in("alignedD")

# ---- baseline params (task.md) ----
baseline <- list(
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

# ---- fit on all seasons ----
cat("Fitting ignition model on ALL seasons...\n")
ign_fit_all <- fitIgnition(
  dat      = alignedD,
  fit_base = TRUE, fit_slope = FALSE, fit_fs = FALSE,
  event_k  = 1L, lead = 1L, A_pre = 6L, B_post = 6L,
  k_week   = 6L, k_p = 8L,
  verbose  = TRUE
)

# ---- confirm baseline results ----
cat("\nBaseline results:\n")
det_base <- detectIgnitionBySeason_M0v2(
  ign_fit = ign_fit_all, params = baseline,
  score_col = "p_cls_p", keep_signals = FALSE,
  iWeek = TRUE, verbose = FALSE
)
print(det_base$compare)

# ---- targeted grid ----
# Hypothesis: at week 14 of 2015-16 (late-starting season), cumulative prevalence
# and K-week rolling sum are lower than at true ignition week for normal seasons.
# Raising prev_thr or p_sum_thr may block the early gate without delaying others.
# Also try N_req=5 (require all 5 gates) and higher cls_thr.

grid_targeted <- data.table::CJ(
  prev_thr  = c(0.006, 0.008, 0.010, 0.012, 0.015, 0.020),
  p_sum_thr = c(0.050, 0.060, 0.070, 0.080, 0.100),
  N_req     = c(4L, 5L),
  cls_thr   = c(0.26, 0.28, 0.30),
  n_consec  = c(5L, 6L, 7L, 8L),
  K_sum     = c(4L, 5L, 6L, 7L),
  w_min     = c(13L, 14L, 15L),
  sorted    = FALSE
)
cat("\nTargeted grid size:", nrow(grid_targeted), "\n")

# ---- evaluate per grid row, collect per-season diffs ----
param_names <- names(baseline)
int_params  <- c("n_consec","L","K_sum","N_req","w_min","w_max")

eval_row <- function(i) {
  row_params <- as.list(grid_targeted[i])
  row_params[["sorted"]] <- NULL
  p <- modifyList(baseline, row_params)
  for (nm in int_params) if (!is.null(p[[nm]])) p[[nm]] <- as.integer(p[[nm]])

  det <- detectIgnitionBySeason_M0v2(
    ign_fit = ign_fit_all, params = p,
    score_col = "p_cls_p", keep_signals = FALSE,
    iWeek = TRUE, verbose = FALSE
  )
  comp <- det$compare
  comp$row_i <- i
  comp
}

cat("Evaluating", nrow(grid_targeted), "param combinations...\n")
all_comp <- data.table::rbindlist(lapply(seq_len(nrow(grid_targeted)), eval_row))

# ---- filter: all non-2015-16 seasons must have |diff| <= 2 ----
others <- all_comp[season != "2015-16"]
bad_rows <- others[!is.na(diff) & abs(diff) > 2, unique(row_i)]
# also flag rows where a non-2015-16 season is newly missing (NA hat)
missing_rows <- others[is.na(iWeek_hat), unique(row_i)]
bad_rows <- unique(c(bad_rows, missing_rows))

good_rows <- setdiff(seq_len(nrow(grid_targeted)), bad_rows)
cat("Rows keeping all other seasons at |diff| <= 2:", length(good_rows), "/", nrow(grid_targeted), "\n\n")

if (length(good_rows) == 0L) {
  cat("No parameter set found that keeps all other seasons within |diff| <= 2.\n")
  quit(save = "no", status = 0)
}

# ---- for good rows, extract 2015-16 diff ----
s1516 <- all_comp[season == "2015-16" & row_i %in% good_rows]
s1516[, abs_diff_2015 := abs(diff)]

# join grid params
grid_cols <- setdiff(names(grid_targeted), "sorted")
grid_good <- cbind(
  grid_targeted[good_rows, ..grid_cols],
  s1516[match(good_rows, s1516$row_i), .(iWeek_hat_2015 = iWeek_hat,
                                          diff_2015 = diff,
                                          abs_diff_2015)]
)
data.table::setorder(grid_good, abs_diff_2015, -N_req, prev_thr)

cat("=== Candidates (all other seasons |diff| <= 2) ranked by |diff_2015| ===\n")
print(grid_good)

# ---- best candidate ----
best_candidate <- grid_good[1L]
cat("\n=== Best candidate ===\n")
cat(sprintf("  prev_thr=%.3f  p_sum_thr=%.3f  N_req=%d  cls_thr=%.2f  n_consec=%d  K_sum=%d  w_min=%d\n",
            best_candidate$prev_thr, best_candidate$p_sum_thr,
            best_candidate$N_req, best_candidate$cls_thr,
            best_candidate$n_consec, best_candidate$K_sum, best_candidate$w_min))
cat(sprintf("  2015-16: iWeek_hat=%d  diff=%+d  (baseline diff=-13)\n",
            best_candidate$iWeek_hat_2015, best_candidate$diff_2015))

# full comparison with best candidate
best_p <- modifyList(baseline, as.list(best_candidate[, .(prev_thr, p_sum_thr, N_req, cls_thr, n_consec, K_sum, w_min)]))
for (nm in int_params) if (!is.null(best_p[[nm]])) best_p[[nm]] <- as.integer(best_p[[nm]])

det_best <- detectIgnitionBySeason_M0v2(
  ign_fit = ign_fit_all, params = best_p,
  score_col = "p_cls_p", keep_signals = FALSE,
  iWeek = TRUE, verbose = FALSE
)
cat("\nFull season comparison with best candidate:\n")
print(det_best$compare)

# ---- save ----
write.csv(as.data.frame(grid_good),
          file.path(out_dir, "targeted_candidates.csv"), row.names = FALSE)
write.csv(det_best$compare,
          file.path(out_dir, "targeted_best_compare.csv"), row.names = FALSE)
cat("\nSaved: results/targeted_candidates.csv, results/targeted_best_compare.csv\n")
cat("DONE\n")
