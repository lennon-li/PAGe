setwd("C:/Users/lennon.li/Documents/claude/PAGe")
load("data/data.RData")
source("R/m0_training.R")

tuned <- readRDS("data/stage1_tuning.rds")
cat("Names in tuned:\n"); print(names(tuned))
cat("\nbest_params_loso:\n"); print(tuned$best_params_loso)
cat("\nClass of loso_results:", class(tuned$loso_results), "\n")
cat("Length of loso_results:", length(tuned$loso_results), "\n")
if (is.data.frame(tuned$loso_results)) {
  cat("Columns:\n"); print(names(tuned$loso_results))
  print(head(tuned$loso_results))
} else if (is.list(tuned$loso_results)) {
  cat("Names:\n"); print(names(tuned$loso_results))
  cat("\nFirst element names:\n"); print(names(tuned$loso_results[[1]]))
}
cat("\nloso_perf:\n"); print(tuned$loso_perf)
