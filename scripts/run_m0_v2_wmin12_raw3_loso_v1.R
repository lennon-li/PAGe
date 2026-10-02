#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source("PAGe/R/data_contract.R")
source("PAGe/R/stage_contracts.R")
source("PAGe/R/m0_training.R")
source("PAGe/R/timing_pipeline_v2.R")

campaign_path <- "artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds"
labels_path <- "artifacts/expert-ignition-annotation-v2-pass1/expert_ignition_labels_v2_pass1.csv"
baseline_path <- "artifacts/m0-v2-decimal-loso-baseline-r2/loso_result.rds"
out_dir <- "artifacts/m0-v2-wmin12-raw3-decimal-loso-v1"

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

camp <- readRDS(campaign_path)
ign <- read.csv(labels_path, stringsAsFactors = FALSE)
old <- readRDS(baseline_path)

grid <- as.data.frame(old$folds[[1L]]$tuning_grid, stringsAsFactors = FALSE)
grid$use_cls <- FALSE
grid$w_min <- 12L
grid$raw_nondec_n <- 3L
grid$spec_id <- paste0(grid$spec_id, "_w12raw3")

truth <- data.frame(
  season = as.character(ign$season),
  ignition_target_weekF = as.numeric(ign$ignition_week_decimal),
  stringsAsFactors = FALSE
)

d <- merge(camp, truth, by = "season", all.x = TRUE, sort = FALSE)
d$phase <- as.integer(d$weekF >= ceiling(d$ignition_target_weekF))

res <- loso_M0v2(
  d,
  grid,
  timing_truth = truth,
  timing_mode = "fractional",
  selection_policy = "legacy",
  verbose = TRUE,
  tune_args = list(
    miss_penalty = 0,
    lambda = 20,
    kappa = 0,
    gamma = 25,
    gamma_late = 0,
    iWeek = TRUE,
    ncores = 4L,
    verbose = FALSE,
    progress_every = 200L
  )
)

saveRDS(res, file.path(out_dir, "loso_result.rds"))
write.csv(res$compare, file.path(out_dir, "compare.csv"), row.names = FALSE)
write.csv(res$best_params_by_fold, file.path(out_dir, "best_params_by_fold.csv"), row.names = FALSE)

cmp <- res$compare
ae <- abs(cmp$iWeek_hatF - cmp$iWeek_true)
summary <- data.frame(
  n_seasons = nrow(cmp),
  mae_fractional = mean(ae, na.rm = TRUE),
  median_ae_fractional = median(ae, na.rm = TRUE),
  bias_fractional = mean(cmp$iWeek_hatF - cmp$iWeek_true, na.rm = TRUE),
  max_ae_fractional = max(ae, na.rm = TRUE),
  n_miss = sum(!is.finite(cmp$iWeek_hatF)),
  n_early_gt1 = sum(cmp$iWeek_hatF < cmp$iWeek_true - 1, na.rm = TRUE),
  stringsAsFactors = FALSE
)
write.csv(summary, file.path(out_dir, "summary.csv"), row.names = FALSE)

stopifnot(
  identical(res$best_params$use_cls, FALSE),
  identical(res$best_params$w_min, 12L),
  identical(res$best_params$raw_nondec_n, 3L)
)

cat("\nM0-v2 w_min=12 + raw-3 LOSO\n")
print(cmp[, c("season", "iWeek_true", "iWeek_hat", "iWeek_hatF")], row.names = FALSE)
print(summary, row.names = FALSE, digits = 6)
cat("\nAggregated params\n")
print(res$best_params)
