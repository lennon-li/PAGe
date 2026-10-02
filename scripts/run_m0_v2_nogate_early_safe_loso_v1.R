#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')

campaign <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
ignition <- read.csv(
  'artifacts/expert-ignition-annotation-v2-pass1/expert_ignition_labels_v2_pass1.csv',
  stringsAsFactors = FALSE
)
legacy_loso <- readRDS('artifacts/m0-v2-decimal-loso-baseline-r2/loso_result.rds')

base_grid <- as.data.frame(legacy_loso$folds[[1L]]$tuning_grid, stringsAsFactors = FALSE)
base_grid <- unique(base_grid[, setdiff(names(base_grid), c('p_sum_thr', 'spec_id')), drop = FALSE])

p_sum_grid <- c(0.075, 0.080, 0.085, 0.090, 0.095, 0.100)
grid <- do.call(rbind, lapply(p_sum_grid, function(threshold) {
  x <- base_grid
  x$p_sum_thr <- threshold
  x
}))
grid$w_min <- 1L
grid$use_cls <- FALSE
grid$spec_id <- vapply(seq_len(nrow(grid)), function(i) {
  paste0('m0_nogate_', digest::digest(as.list(grid[i, , drop = FALSE]), algo = 'xxhash64'))
}, character(1L))

truth <- data.frame(
  season = as.character(ignition$season),
  ignition_target_weekF = as.numeric(ignition$ignition_week_decimal),
  stringsAsFactors = FALSE
)

dat <- merge(campaign, truth, by = 'season', all.x = TRUE, sort = FALSE)
dat$phase <- as.integer(dat$weekF >= ceiling(dat$ignition_target_weekF))

loso <- loso_M0v2(
  dat,
  grid = grid,
  timing_truth = truth,
  timing_mode = 'fractional',
  selection_policy = 'legacy',
  verbose = TRUE,
  tune_args = list(
    miss_penalty = 0,
    lambda = 20,
    kappa = 0,
    gamma = 25,
    gamma_late = 0,
    gamma_early = 100,
    iWeek = TRUE,
    ncores = 4L,
    verbose = FALSE,
    progress_every = 200L
  )
)

out_dir <- 'artifacts/m0-v2-nogate-early-safe-loso-v1'
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(loso, file.path(out_dir, 'loso_result.rds'))
write.csv(loso$compare, file.path(out_dir, 'compare.csv'), row.names = FALSE)
write.csv(loso$best_params_by_fold, file.path(out_dir, 'best_params_by_fold.csv'), row.names = FALSE)
write.csv(grid, file.path(out_dir, 'tuning_grid.csv'), row.names = FALSE)

cmp <- loso$compare
cmp$abs_error_fractional <- abs(cmp$iWeek_hatF - cmp$iWeek_true)
summary <- data.frame(
  n_seasons = nrow(cmp),
  mae_fractional = mean(cmp$abs_error_fractional),
  median_ae_fractional = median(cmp$abs_error_fractional),
  bias_fractional = mean(cmp$iWeek_hatF - cmp$iWeek_true),
  max_ae_fractional = max(cmp$abs_error_fractional),
  early_more_than_1w = sum(cmp$iWeek_hatF < cmp$iWeek_true - 1),
  early_more_than_2w = sum(cmp$iWeek_hatF < cmp$iWeek_true - 2),
  use_cls = FALSE,
  w_min = 1L,
  gamma_early = 100,
  stringsAsFactors = FALSE
)
write.csv(summary, file.path(out_dir, 'summary.csv'), row.names = FALSE)

cat('M0-v2 no-gate early-safe LOSO\n')
print(summary, row.names = FALSE, digits = 6)
cat('\nAggregate LOSO params\n')
print(loso$best_params)
cat('\nPer-season\n')
print(cmp[, c('season', 'iWeek_true', 'iWeek_hat', 'iWeek_hatF', 'diff')], row.names = FALSE, digits = 6)
