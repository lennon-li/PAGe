setwd("C:/Users/lennon.li/Documents/claude/PAGe")
suppressPackageStartupMessages({ library(dplyr); library(mgcv) })
source("R/m0_training.R")
source("R/m2_spec_grid.R")
source("R/m2_training.R")
load("data/data.RData")

tuned2 <- readRDS("data/stage2_tuning.rds")

cat("=== Best spec ===\n")
bsg <- as.data.frame(tuned2$by_spec_grid)
best_row <- bsg[bsg$spec_id == tuned2$best$spec_id, ]
print(t(best_row[, c("delta","Kr","k_f","alpha_state","Kb","k_w","k_s","k_e","k_n","k_1","k_2","mean_nll")]))

spec <- stage2_spec_from_tuning(tuned2)
cat("\nFormula:\n"); print(spec$formula)
cat("\nexclude_newseason:", paste(spec$exclude_newseason, collapse=", "), "\n")
cat("pre_buffer:", spec$pre_buffer, "\n")

cat("\n=== Template endpoints ===\n")
cat("nw range:", min(template_df$newWeek), "-", max(template_df$newWeek), "\n")
print(tail(template_df[order(template_df$newWeek), c("newWeek","fit")], 10))

cat("\n=== Calibration ===\n")
if (file.exists("data/stage2_calib_loso.rds")) {
  d_cal <- readRDS("data/stage2_calib_loso.rds")
  cat("Cols:", paste(names(d_cal), collapse=", "), "\n")
  cat("Rows:", nrow(d_cal), "| Seasons:", paste(sort(unique(d_cal$season)), collapse=", "), "\n")
  if ("p_hat" %in% names(d_cal) && "p_obs" %in% names(d_cal)) {
    for (h in sort(unique(d_cal$lead))) {
      dh <- d_cal[d_cal$lead == h, ]
      cat(sprintf("  lead=%s: n=%d, mean(p_hat)=%.4f, mean(p_obs)=%.4f\n",
                  h, nrow(dh), mean(dh$p_hat, na.rm=TRUE), mean(dh$p_obs, na.rm=TRUE)))
    }
  }
} else { cat("No stage2_calib_loso.rds found\n") }

# Inspect trained model if exists
if (file.exists("data/joint_out.rds")) {
  joint_out <- readRDS("data/joint_out.rds")
  fit <- joint_out$fit
  cat("\n=== GAM fit summary (key smooth terms) ===\n")
  sm <- summary(fit)
  cat("Smooth terms edf:\n")
  print(sm$s.table[, c("edf","Ref.df","F","p-value")])
  # range of newWeek in training data
  cat("\n=== newWeek range in training ===\n")
  if ("newWeek" %in% names(fit$model)) {
    cat("newWeek range:", min(fit$model$newWeek), "-", max(fit$model$newWeek), "\n")
    cat("z_ema range:", round(range(fit$model$z_ema, na.rm=TRUE), 3), "\n")
    cat("logit_f_eff range:", round(range(fit$model$logit_f_eff, na.rm=TRUE), 3), "\n")
  }
}
