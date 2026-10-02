#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')

panel_path <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
labels_path <- 'artifacts/v3-joint-ab-ignition-review-v1/A_ignition_labels_v3.csv'
baseline_path <- 'artifacts/m0-v2-decimal-loso-baseline-r2/loso_result.rds'
out_dir <- 'artifacts/v3-a-rule-transfer-to-b-v1'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

panel <- read.csv(panel_path, check.names=FALSE)
lab <- read.csv(labels_path, check.names=FALSE)
old <- readRDS(baseline_path)

grid <- as.data.frame(old$folds[[1L]]$tuning_grid, stringsAsFactors=FALSE)
grid$use_cls <- FALSE
grid$w_min <- 12L
grid$raw_nondec_n <- 3L
grid$raw_drop_se_tol <- 1.0
grid$spec_id <- paste0(grid$spec_id, '_v3Atransfer')

truth <- data.frame(
  season=lab$season,
  ignition_target_weekF=as.numeric(lab$A_ignition_weekF),
  stringsAsFactors=FALSE
)

A <- data.frame(
  season=panel$season, weekF=panel$weekF,
  y=panel$y_A, N=panel$N_A, p=panel$p_A,
  stringsAsFactors=FALSE
)
A <- merge(A, truth, by='season', all.x=TRUE, sort=FALSE)
A$phase <- as.integer(A$weekF >= ceiling(A$ignition_target_weekF))

fit <- loso_M0v2(
  A, grid,
  timing_truth=truth,
  timing_mode='fractional',
  selection_policy='legacy',
  verbose=TRUE,
  tune_args=list(
    miss_penalty=0,
    lambda=20,
    kappa=0,
    gamma=25,
    gamma_late=0,
    iWeek=TRUE,
    ncores=4L,
    verbose=FALSE,
    progress_every=200L
  )
)

saveRDS(fit, file.path(out_dir,'A_loso_fit.rds'))
write.csv(fit$compare, file.path(out_dir,'A_loso_compare.csv'), row.names=FALSE)
write.csv(fit$best_params_by_fold, file.path(out_dir,'A_best_params_by_fold.csv'), row.names=FALSE)

params <- fit$best_params
saveRDS(params, file.path(out_dir,'A_aggregated_params.rds'))
write.csv(as.data.frame(params, stringsAsFactors=FALSE), file.path(out_dir,'A_aggregated_params.csv'), row.names=FALSE)

# Apply the A-derived parameter set unchanged to both A and B for comparison.
detA <- detectIgnitionBySeason_M0v2_timing(A, params=params, verbose=FALSE, iWeek=FALSE, keep_signals=TRUE)
B <- data.frame(
  season=panel$season, weekF=panel$weekF,
  y=panel$y_B, N=panel$N_B, p=panel$p_B,
  stringsAsFactors=FALSE
)
detB <- detectIgnitionBySeason_M0v2_timing(B, params=params, verbose=FALSE, iWeek=FALSE, keep_signals=TRUE)

Aout <- detA$by_season
names(Aout)[names(Aout)=='iWeek_hat'] <- 'A_ignition_hat_integer'
if ('iWeek_hatF' %in% names(Aout)) names(Aout)[names(Aout)=='iWeek_hatF'] <- 'A_ignition_hat_decimal'
Aout <- merge(Aout, truth, by='season', all.x=TRUE)

Bout <- detB$by_season
names(Bout)[names(Bout)=='iWeek_hat'] <- 'B_ignition_hat_integer'
if ('iWeek_hatF' %in% names(Bout)) names(Bout)[names(Bout)=='iWeek_hatF'] <- 'B_ignition_hat_decimal'

out <- merge(Aout, Bout, by='season', all=TRUE)
out <- out[match(truth$season,out$season),]
write.csv(out, file.path(out_dir,'A_label_and_B_transferred_ignition.csv'), row.names=FALSE)
write.csv(detA$data, file.path(out_dir,'A_detection_signals.csv'), row.names=FALSE)
write.csv(detB$data, file.path(out_dir,'B_detection_signals.csv'), row.names=FALSE)

cmp <- fit$compare
ae <- abs(cmp$iWeek_hatF-cmp$iWeek_true)
summary <- data.frame(
  n_seasons=nrow(cmp),
  mae_fractional=mean(ae,na.rm=TRUE),
  median_ae_fractional=median(ae,na.rm=TRUE),
  max_ae_fractional=max(ae,na.rm=TRUE),
  misses=sum(!is.finite(cmp$iWeek_hatF)),
  false_early_gt1=sum(cmp$iWeek_hatF < cmp$iWeek_true-1,na.rm=TRUE)
)
write.csv(summary, file.path(out_dir,'A_loso_summary.csv'), row.names=FALSE)

cat('\nA LOSO summary\n'); print(summary,row.names=FALSE,digits=6)
cat('\nAggregated A-derived params\n'); print(params)
cat('\nA labels / transferred B ignition\n'); print(out,row.names=FALSE,digits=6)
