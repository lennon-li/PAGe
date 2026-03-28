setwd("C:/Users/lennon.li/Documents/claude/PAGe")
suppressPackageStartupMessages({ library(dplyr); library(data.table) })
source("R/ignitionTraining.R")
source("R/module_training.R")
source("R/prospective_training.R")

tuned2 <- readRDS("data/stage2_tuning.rds")

cat("=== METADATA ===\n")
cat("eval_window :", tuned2$scoring$eval_window, "\n")
cat("refit_loso  :", isTRUE(tuned2$parallel$refit_loso), "\n")
cat("w_early     :", tuned2$scoring$w_early, "\n")
cat("Total specs :", nrow(tuned2$by_spec), "\n")
cat("Elapsed (s) :", round(tuned2$timing$elapsed_sec, 0), "\n")

cat("\n=== BEST SPEC ===\n")
best <- as.data.frame(tuned2$best)
print(best)

cat("\n=== TOP 10 SPECS ===\n")
bsg <- as.data.frame(tuned2$by_spec_grid)
bsg <- bsg[order(bsg$mean_nll, na.last=TRUE), ]
top10 <- head(bsg, 10)
keep <- intersect(c("delta","Kr","k_f","alpha_state","Kb","lambda_w","w_floor",
                    "k_w","k_s","k_e","k_1","mean_nll","brier"), names(top10))
print(top10[, keep], row.names=FALSE)

cat("\n=== TOP-20% FREQUENCY ANALYSIS ===\n")
bsg2 <- bsg[!is.na(bsg$mean_nll), ]
thresh <- quantile(bsg2$mean_nll, 0.20, na.rm=TRUE)
top20  <- bsg2[bsg2$mean_nll <= thresh, ]
cat("Top-20% threshold:", round(thresh,3), "| n:", nrow(top20), "\n\n")

params <- c("delta","Kr","k_f","alpha_state","Kb","lambda_w","w_floor","k_w","k_s","k_e","k_1")
for (p in params) {
  if (!p %in% names(bsg2)) next
  all_tab <- prop.table(table(bsg2[[p]])) * 100
  top_tab <- prop.table(table(top20[[p]])) * 100
  cat(sprintf("%-14s | all: %s | top-20%%: %s\n", p,
    paste(sprintf("%s=%.0f%%", names(all_tab), all_tab), collapse=" "),
    paste(sprintf("%s=%.0f%%", names(top_tab), top_tab), collapse=" ")))
}
