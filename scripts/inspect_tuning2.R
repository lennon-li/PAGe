setwd("C:/Users/lennon.li/Documents/claude/PAGe")
load("data/data.RData")
source("R/ignitionTraining.R")

tuned <- readRDS("data/stage1_tuning.rds")
cat("Names in tuned:\n"); print(names(tuned))

cat("\nbest_params:\n"); print(tuned$best_params)

cat("\nClass of folds:", class(tuned$folds), "\n")
cat("Length of folds:", length(tuned$folds), "\n")
if (is.list(tuned$folds)) {
  cat("Names of folds:\n"); print(names(tuned$folds))
  cat("\nFirst fold names:\n"); print(names(tuned$folds[[1]]))
  cat("\nFirst fold best_params:\n"); print(tuned$folds[[1]]$best_params)
  cat("\nFirst fold iWeek_true/hat:\n")
  cat("  iWeek_true:", tuned$folds[[1]]$iWeek_true, "\n")
  cat("  iWeek_hat: ", tuned$folds[[1]]$iWeek_hat, "\n")
}

cat("\nsummary:\n"); print(tuned$summary)
cat("\ncompare (first rows):\n"); print(head(tuned$compare))

cat("\nbest_params_by_fold:\n"); print(tuned$best_params_by_fold)
