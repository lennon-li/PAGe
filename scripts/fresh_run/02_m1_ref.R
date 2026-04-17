#!/usr/bin/env Rscript
# Step 2 — M1 Reference Curve (fresh run)
# No existing script — new. Fits estimateRef + learn_alignment_hyperparams
# on all 11 production seasons (excl. 2011-12, 2015-16, 2020-21, 2021-22).
# Note: does NOT include 2025-26 in EXCLUDE_PERM so production includes it.
#
# Output:  data/fresh_ref_production.rds (partial; m2 components added in Step 5)
# Compare: data/ref_production.rds

source("scripts/fresh_run/00_shared.R")
cat("=== Step 2: M1 Reference Curve (fresh run) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# Production training set: all seasons except permanent exclusions (keeps 2025-26)
allD_prod <- load_allD(exclude = c("2011-12", "2015-16", "2020-21", "2021-22"))
train_seas <- sort(unique(allD_prod$season))
cat("Production seasons:", paste(train_seas, collapse = ", "), "\n")
cat("Total:", length(train_seas), "seasons\n\n")

# ---- Align ----
cat("Building aligned training data...\n")
aligned_train <- build_aligned(allD_prod)
cat("aligned_train:", nrow(aligned_train), "rows\n\n")

# ---- Reference curve ----
cat("estimateRef (k_ref =", M1_PARAMS$k_ref, ", method =", M1_PARAMS$ref_method, ")...\n")
ref <- estimateRef(
  alignedD = aligned_train,
  exSeason = character(0),
  k        = M1_PARAMS$k_ref,
  n_weeks  = 52L,
  method   = M1_PARAMS$ref_method
)
cat("eta_mat:", nrow(ref$eta_mat), "weeks x", ncol(ref$eta_mat), "seasons\n")
cat("anchorWeek:", ref$anchorWeek, "\n\n")

# ---- Hyperparameters ----
cat("learn_alignment_hyperparams...\n")
hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
cat("hyper built\n\n")

# ---- Save (partial — m2 components added in Step 5) ----
saveRDS(list(
  ref           = ref,
  hyper         = hyper,
  hist_data     = aligned_train,
  M1_PARAMS     = M1_PARAMS,
  flag_args     = flag_args,
  manual_labels = manual_labels
), "data/fresh_ref_production.rds")
cat("Saved: data/fresh_ref_production.rds\n")

# ---- Comparison ----
cat("\n=== Comparison vs gold (data/ref_production.rds) ===\n")
gold_ref <- readRDS("data/ref_production.rds")

cat("Gold anchorWeek:", gold_ref$ref$anchorWeek,
    "| Fresh anchorWeek:", ref$anchorWeek, "\n")
if (ref$anchorWeek != gold_ref$ref$anchorWeek) {
  stop("CRITICAL: anchorWeek mismatch — all downstream newWeek coordinates are wrong!")
}
cat("anchorWeek: MATCH\n\n")

gold_pred  <- gold_ref$ref$pred_df
fresh_pred <- ref$pred_df
pred_cmp   <- dplyr::inner_join(gold_pred, fresh_pred, by = "newWeek", suffix = c(".gold", ".fresh"))
pred_cmp$delta <- pred_cmp$fit.fresh - pred_cmp$fit.gold
cat("Reference curve (logit scale) fit delta:\n")
cat("  Max |delta|:", round(max(abs(pred_cmp$delta), na.rm = TRUE), 5), "(warn if > 0.01)\n")
cat("  Mean |delta|:", round(mean(abs(pred_cmp$delta), na.rm = TRUE), 5), "\n")

if (max(abs(pred_cmp$delta), na.rm = TRUE) > 0.01)
  warning("Reference curve delta > 0.01 — possible REML optimizer divergence. Consider re-running.")

cat("\nEnd:", format(Sys.time()), "\n")
