#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

if (!requireNamespace('digest', quietly = TRUE)) stop('Package `digest` is required.')

PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
POLICY_DOC <- 'docs/v3-m1-b-season-policy-2026-09-26.md'
OUT <- 'artifacts/v3-m1-b0-excluding-pandemic-v1'
EXCLUDED_B_SEASONS <- c('2019-20')
MIN_TRAIN_SEASONS <- 4L
CANDIDATE_STEP <- 0.1
MAX_FUTURE <- 16
AMP_GRID <- seq(.005, .25, by=.005)

if (dir.exists(OUT) && length(list.files(OUT, all.files=TRUE, no..=TRUE))) stop('Output directory already exists and is non-empty: ', OUT)
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

sha256_file <- function(path) digest::digest(file=path, algo='sha256', serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))

panel <- read.csv(PANEL_PATH, check.names=FALSE)
truth <- read.csv(TIMING_PATH, check.names=FALSE)
seasons <- unique(as.character(panel$season))
seasons <- seasons[order(season_start(seasons))]
truth$season <- as.character(truth$season)
truth <- truth[match(seasons, truth$season),]
if (anyNA(truth$season)) stop('Timing contract season mismatch.')

B <- data.frame(season=as.character(panel$season), weekF=panel$weekF,
                y=panel$y_B, N=panel$N_B, p=panel$p_B,
                stringsAsFactors=FALSE)
B <- B[order(season_start(B$season),B$weekF),]

policy <- data.frame(
  season=seasons,
  B_model_role=ifelse(seasons %in% EXCLUDED_B_SEASONS, 'excluded',
                      ifelse(truth$B_activity_detected, 'eligible_timing', 'no_event')),
  exclusion_reason=ifelse(seasons %in% EXCLUDED_B_SEASONS, 'pandemic_transition',
                          ifelse(truth$B_activity_detected, '', 'no_meaningful_B_activity')),
  stringsAsFactors=FALSE
)
write.csv(policy,file.path(OUT,'season_policy.csv'),row.names=FALSE)

meaningful <- truth$season[is.finite(truth$B_peak_weekF) & truth$B_activity_detected & !(truth$season %in% EXCLUDED_B_SEASONS)]

folds <- do.call(rbind,lapply(seasons,function(test){
  prior <- seasons[season_start(seasons) < season_start(test)]
  train <- prior[prior %in% meaningful]
  data.frame(
    test_season=test,
    excluded_test=test %in% EXCLUDED_B_SEASONS,
    test_has_meaningful_B=test %in% meaningful,
    n_train=length(train),
    training_seasons=paste(train,collapse=';'),
    eligible=(!(test %in% EXCLUDED_B_SEASONS)) && (test %in% meaningful) && length(train)>=MIN_TRAIN_SEASONS,
    stringsAsFactors=FALSE
  )
}))
write.csv(folds,file.path(OUT,'fold_ledger.csv'),row.names=FALSE)

for(i in seq_len(nrow(folds))){
  tr <- if(nzchar(folds$training_seasons[i])) strsplit(folds$training_seasons[i],';',fixed=TRUE)[[1]] else character(0)
  if(length(tr) && any(season_start(tr)>=season_start(folds$test_season[i]))) stop('Chronological leakage.')
  if(any(tr %in% EXCLUDED_B_SEASONS)) stop('Excluded pandemic season entered B training.')
}

origin_max_prepeak <- function(T) floor(T-1e-8)-1L
metric_weight <- function(origin,activation) exp(-(0.1*(origin-ceiling(activation)))^2)

future_invariance <- function(lib,held,activation,origin){
  f1 <- m1_v2_peak_posterior(lib,held,activation,origin,candidate_step=CANDIDATE_STEP,max_future_weeks=MAX_FUTURE)
  h2 <- held
  idx <- h2$weekF>origin
  if(any(idx)){
    h2$y[idx] <- pmin(h2$N[idx],h2$y[idx]+7L)
    h2$p[idx] <- h2$y[idx]/h2$N[idx]
  }
  f2 <- m1_v2_peak_posterior(lib,h2,activation,origin,candidate_step=CANDIDATE_STEP,max_future_weeks=MAX_FUTURE)
  cols <- c('peak_mean','peak_median','peak_map','peak_q05','peak_q95')
  d <- max(abs(as.numeric(f1$summary[1,cols])-as.numeric(f2$summary[1,cols])))
  if(!is.finite(d) || d>1e-12) stop('Future perturbation changed prediction.')
  d
}

pred_rows <- list(); lib_rows <- list(); future_rows <- list()
for(test in folds$test_season[folds$eligible]){
  fold <- folds[folds$test_season==test,]
  train_seasons <- if(nzchar(fold$training_seasons)) strsplit(fold$training_seasons,';',fixed=TRUE)[[1]] else character(0)
  train <- B[B$season %in% train_seasons,]
  peak <- truth[truth$season %in% train_seasons,c('season','B_peak_weekF')]
  names(peak)[2] <- 'peak_week_decimal'
  lib <- fit_m1_v2_library(train,peak,k=8L,grid_step=.01,tau_step=.1,amplitude_grid=AMP_GRID)
  held <- B[B$season==test,]
  act <- truth$B_activity_weekF[truth$season==test]
  T <- truth$B_peak_weekF[truth$season==test]
  first <- ceiling(act); last <- origin_max_prepeak(T)
  if(first>last) stop('No prepeak origin for ',test)
  d0 <- future_invariance(lib,held,act,first)
  future_rows[[length(future_rows)+1L]] <- data.frame(season=test,origin=first,max_abs_diff=d0,pass=TRUE)
  for(o in seq.int(first,last)){
    fit <- m1_v2_peak_posterior(lib,held,act,o,candidate_step=CANDIDATE_STEP,max_future_weeks=MAX_FUTURE)
    s <- fit$summary[1,]
    pred_rows[[length(pred_rows)+1L]] <- data.frame(
      season=test,origin_weekF=o,activation_weekF=act,truth_peak_weekF=T,
      pred_peak_mean=s$peak_mean,pred_peak_median=s$peak_median,pred_peak_map=s$peak_map,
      q05=s$peak_q05,q95=s$peak_q95,error=s$peak_mean-T,abs_error=abs(s$peak_mean-T),
      covered90=(s$peak_q05<=T && s$peak_q95>=T),weight_early=metric_weight(o,act),
      stringsAsFactors=FALSE
    )
  }
  lib_rows[[length(lib_rows)+1L]] <- data.frame(test_season=test,n_train=length(train_seasons),
    training_seasons=paste(train_seasons,collapse=';'),library_hash=lib$provenance$library_hash,stringsAsFactors=FALSE)
}

pred <- do.call(rbind,pred_rows)
libs <- do.call(rbind,lib_rows)
future <- do.call(rbind,future_rows)
write.csv(pred,file.path(OUT,'per_origin_predictions.csv'),row.names=FALSE)
write.csv(libs,file.path(OUT,'library_ledger.csv'),row.names=FALSE)
write.csv(future,file.path(OUT,'future_perturbation_checks.csv'),row.names=FALSE)

per_season <- do.call(rbind,lapply(split(pred,pred$season),function(z)data.frame(
  season=z$season[1],n_origins=nrow(z),mae=mean(z$abs_error),rmse=sqrt(mean(z$error^2)),bias=mean(z$error),
  early_weighted_mae=sum(z$weight_early*z$abs_error)/sum(z$weight_early),coverage90=mean(z$covered90),stringsAsFactors=FALSE)))
per_season <- per_season[order(season_start(per_season$season)),]
write.csv(per_season,file.path(OUT,'per_season_metrics.csv'),row.names=FALSE)

summary <- data.frame(
  n_test_seasons=nrow(per_season),n_origins=sum(per_season$n_origins),
  season_balanced_mae=mean(per_season$mae),season_balanced_rmse=mean(per_season$rmse),
  season_balanced_bias=mean(per_season$bias),season_balanced_early_weighted_mae=mean(per_season$early_weighted_mae),
  mean_coverage90=mean(per_season$coverage90),worst_season_mae=max(per_season$mae),stringsAsFactors=FALSE)
write.csv(summary,file.path(OUT,'summary_metrics.csv'),row.names=FALSE)

manifest_paths <- c(PANEL_PATH,TIMING_PATH,POLICY_DOC)
manifest <- data.frame(role=c('canonical_panel','timing_contract','B_season_policy'),path=manifest_paths,
                       sha256=vapply(manifest_paths,sha256_file,character(1)),stringsAsFactors=FALSE)
write.csv(manifest,file.path(OUT,'source_manifest.csv'),row.names=FALSE)
config <- data.frame(key=c('benchmark_version','primary_validation','excluded_B_seasons','exclusion_reason','min_train_seasons','candidate_step','max_future_weeks','amplitude_grid','calibration_status'),
 value=c('v3-m1-b0-excluding-pandemic-v1','expanding_window_strict_prior_seasons',paste(EXCLUDED_B_SEASONS,collapse=';'),'pandemic_transition',MIN_TRAIN_SEASONS,CANDIDATE_STEP,MAX_FUTURE,'0.005:0.005:0.25','raw_posterior_no_bias_calibration'),stringsAsFactors=FALSE)
write.csv(config,file.path(OUT,'benchmark_config.csv'),row.names=FALSE)

cat('M1-B0 pandemic-excluded benchmark complete\n')
print(summary,row.names=FALSE,digits=5)
print(per_season,row.names=FALSE,digits=4)
