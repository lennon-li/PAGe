#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

if (!requireNamespace('digest', quietly=TRUE)) stop('Package `digest` is required.')

PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
ELIG_PATH <- 'artifacts/v3-joint-timing-contract-v2/modeling_eligibility_v3.csv'
M0_PATH <- 'artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds'
OUT <- 'artifacts/v3-m1-chronological-baselines-v2-pandemic-excluded'
MIN_TRAIN_SEASONS <- 4L
CANDIDATE_STEP <- 0.1
A_MAX_FUTURE <- 14
B_MAX_FUTURE <- 16
B_AMP_GRID <- seq(.005, .25, by=.005) # pre-existing B-specific grid from v2 research

dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

sha256_file <- function(path) digest::digest(file=path, algo='sha256', serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))

panel <- read.csv(PANEL_PATH, check.names=FALSE)
truth <- read.csv(TIMING_PATH, check.names=FALSE)
elig <- read.csv(ELIG_PATH, check.names=FALSE)
m0_fit <- readRDS(M0_PATH)

seasons <- unique(as.character(panel$season))
seasons <- seasons[order(season_start(seasons))]
truth <- truth[match(seasons,truth$season),]
if (anyNA(truth$season) || !identical(as.character(truth$season),seasons)) stop('Timing contract season order mismatch.')
elig <- elig[match(seasons,elig$season),]
if (anyNA(elig$season) || !identical(as.character(elig$season),seasons)) stop('Eligibility registry season order mismatch.')
B_ELIGIBLE <- as.character(elig$season[elig$M1_B_training_eligible])
B_SCORE_ELIGIBLE <- as.character(elig$season[elig$M1_B_peak_eligible])
if ('2019-20' %in% B_ELIGIBLE || '2019-20' %in% B_SCORE_ELIGIBLE) stop('Pandemic transition season must be excluded from M1-B.')

A <- data.frame(season=panel$season,weekF=panel$weekF,y=panel$y_A,N=panel$N_A,p=panel$p_A)
B <- data.frame(season=panel$season,weekF=panel$weekF,y=panel$y_B,N=panel$N_B,p=panel$p_B)
A <- A[order(season_start(A$season),A$weekF),]
B <- B[order(season_start(B$season),B$weekF),]

# Frozen M0-A policy is treated as an external fixed v2 component, not re-tuned
# inside v3 folds. Recompute causal activations on the canonical panel.
m0_params <- m0_fit$best_params
A_m0 <- detectIgnitionBySeason_M0v2_timing(A, params=m0_params, verbose=FALSE, iWeek=FALSE, keep_signals=TRUE)
A_activation <- A_m0$by_season[,c('season','iWeek_hat','iWeek_hatF','detection_failed')]
if (any(A_activation$detection_failed)) stop('Frozen M0-A failed on a historical canonical season.')
write.csv(A_activation,file.path(OUT,'A_frozen_m0_activation.csv'),row.names=FALSE)

# B activity markers come from the reproducible timing contract and are not truth.
B_activation <- truth[,c('season','B_activity_integer','B_activity_weekF','B_activity_detected','B_activity_status')]

fold_rows <- list()
for (test in seasons) {
  prior <- seasons[season_start(seasons) < season_start(test)]
  fold_rows[[length(fold_rows)+1L]] <- data.frame(
    test_season=test,
    n_prior=length(prior),
    training_seasons=paste(prior,collapse=';'),
    eligible_A=length(prior)>=MIN_TRAIN_SEASONS,
    eligible_B=sum(prior %in% B_ELIGIBLE)>=MIN_TRAIN_SEASONS &&
      test %in% B_SCORE_ELIGIBLE && isTRUE(truth$B_activity_detected[truth$season==test]) && is.finite(truth$B_peak_weekF[truth$season==test]),
    stringsAsFactors=FALSE
  )
}
folds <- do.call(rbind,fold_rows)
write.csv(folds,file.path(OUT,'fold_ledger.csv'),row.names=FALSE)

# Strong fold-isolation assertions.
for (i in seq_len(nrow(folds))) {
  tr <- if(nzchar(folds$training_seasons[i])) strsplit(folds$training_seasons[i],';',fixed=TRUE)[[1]] else character(0)
  if (length(tr) && any(season_start(tr) >= season_start(folds$test_season[i]))) stop('Chronological fold leakage detected.')
}

origin_max_prepeak <- function(T) floor(T - 1e-8) - 1L
metric_weight <- function(origin, activation) exp(-(0.1*(origin-ceiling(activation)))^2)

run_path <- function(lib, held, activation, Ttruth, test_season, type, max_future) {
  first <- ceiling(activation)
  last <- origin_max_prepeak(Ttruth)
  if (!is.finite(first) || !is.finite(last) || first > last) return(NULL)
  rows <- list()
  for (o in seq.int(first,last)) {
    fit <- tryCatch(
      m1_v2_peak_posterior(lib,held,activation_week=activation,origin_week=o,
                           candidate_step=CANDIDATE_STEP,max_future_weeks=max_future),
      error=function(e) e
    )
    if (inherits(fit,'error')) next
    s <- fit$summary[1,]
    rows[[length(rows)+1L]] <- data.frame(
      type=type,model=paste0('M1-',type,'0_raw'),season=test_season,
      origin_weekF=o,activation_weekF=activation,truth_peak_weekF=Ttruth,
      pred_peak_mean=s$peak_mean,pred_peak_median=s$peak_median,pred_peak_map=s$peak_map,
      q05=s$peak_q05,q95=s$peak_q95,
      error=s$peak_mean-Ttruth,abs_error=abs(s$peak_mean-Ttruth),
      covered90=(s$peak_q05<=Ttruth && s$peak_q95>=Ttruth),
      weight_early=metric_weight(o,activation),
      stringsAsFactors=FALSE
    )
  }
  if (length(rows)) do.call(rbind,rows) else NULL
}

# Future-perturbation assertion: changing weeks after an origin must not change the posterior.
assert_future_invariance <- function(lib, held, activation, origin, max_future) {
  f1 <- m1_v2_peak_posterior(lib,held,activation,origin,candidate_step=CANDIDATE_STEP,max_future_weeks=max_future)
  h2 <- held
  future <- h2$weekF > origin
  if (any(future)) {
    h2$y[future] <- pmin(h2$N[future], h2$y[future] + 7L)
    h2$p[future] <- h2$y[future]/h2$N[future]
  }
  f2 <- m1_v2_peak_posterior(lib,h2,activation,origin,candidate_step=CANDIDATE_STEP,max_future_weeks=max_future)
  cols <- c('peak_mean','peak_median','peak_map','peak_q05','peak_q95')
  if (max(abs(as.numeric(f1$summary[1,cols])-as.numeric(f2$summary[1,cols]))) > 1e-12) {
    stop('Future perturbation changed a causal M1 prediction.')
  }
  TRUE
}

pred_rows <- list()
lib_rows <- list()
future_tests <- list()

for (test in seasons) {
  fold <- folds[folds$test_season==test,]
  prior <- if(nzchar(fold$training_seasons)) strsplit(fold$training_seasons,';',fixed=TRUE)[[1]] else character(0)

  if (isTRUE(fold$eligible_A)) {
    trainA <- A[A$season %in% prior,]
    truthA <- truth[truth$season %in% prior,c('season','A_peak_weekF')]
    names(truthA)[2] <- 'peak_week_decimal'
    libA <- fit_m1_v2_library(trainA,truthA,k=8L,grid_step=.01,tau_step=.1)
    heldA <- A[A$season==test,]
    actA <- A_activation$iWeek_hatF[A_activation$season==test]
    TA <- truth$A_peak_weekF[truth$season==test]
    pa <- run_path(libA,heldA,actA,TA,test,'A',A_MAX_FUTURE)
    if (!is.null(pa)) pred_rows[[length(pred_rows)+1L]] <- pa
    firstA <- ceiling(actA)
    if (firstA <= origin_max_prepeak(TA)) {
      assert_future_invariance(libA,heldA,actA,firstA,A_MAX_FUTURE)
      future_tests[[length(future_tests)+1L]] <- data.frame(type='A',season=test,origin=firstA,pass=TRUE)
    }
    lib_rows[[length(lib_rows)+1L]] <- data.frame(
      type='A',test_season=test,n_train=length(prior),training_seasons=paste(prior,collapse=';'),
      library_hash=libA$provenance$library_hash,amplitude_grid='0.08:0.02:0.44',stringsAsFactors=FALSE)
  }

  if (isTRUE(fold$eligible_B)) {
    trainB_seasons <- prior[prior %in% B_ELIGIBLE]
    trainB <- B[B$season %in% trainB_seasons,]
    truthB <- truth[truth$season %in% trainB_seasons,c('season','B_peak_weekF')]
    names(truthB)[2] <- 'peak_week_decimal'
    libB <- fit_m1_v2_library(trainB,truthB,k=8L,grid_step=.01,tau_step=.1,amplitude_grid=B_AMP_GRID)
    heldB <- B[B$season==test,]
    actB <- truth$B_activity_weekF[truth$season==test]
    TB <- truth$B_peak_weekF[truth$season==test]
    pb <- run_path(libB,heldB,actB,TB,test,'B',B_MAX_FUTURE)
    if (!is.null(pb)) pred_rows[[length(pred_rows)+1L]] <- pb
    firstB <- ceiling(actB)
    if (firstB <= origin_max_prepeak(TB)) {
      assert_future_invariance(libB,heldB,actB,firstB,B_MAX_FUTURE)
      future_tests[[length(future_tests)+1L]] <- data.frame(type='B',season=test,origin=firstB,pass=TRUE)
    }
    lib_rows[[length(lib_rows)+1L]] <- data.frame(
      type='B',test_season=test,n_train=length(trainB_seasons),training_seasons=paste(trainB_seasons,collapse=';'),
      library_hash=libB$provenance$library_hash,amplitude_grid='0.005:0.005:0.25',stringsAsFactors=FALSE)
  }
}

pred <- if(length(pred_rows)) do.call(rbind,pred_rows) else data.frame()
libs <- if(length(lib_rows)) do.call(rbind,lib_rows) else data.frame()
future_check <- if(length(future_tests)) do.call(rbind,future_tests) else data.frame()
write.csv(pred,file.path(OUT,'per_origin_predictions.csv'),row.names=FALSE)
write.csv(libs,file.path(OUT,'library_ledger.csv'),row.names=FALSE)
write.csv(future_check,file.path(OUT,'future_perturbation_checks.csv'),row.names=FALSE)

if (!nrow(pred)) stop('Chronological M1 benchmark produced no predictions.')

per_season <- do.call(rbind,lapply(split(pred,list(pred$type,pred$season),drop=TRUE),function(z){
  data.frame(
    type=z$type[1],season=z$season[1],n_origins=nrow(z),
    mae=mean(z$abs_error),rmse=sqrt(mean(z$error^2)),bias=mean(z$error),
    early_weighted_mae=sum(z$weight_early*z$abs_error)/sum(z$weight_early),
    coverage90=mean(z$covered90),
    stringsAsFactors=FALSE
  )
}))
per_season <- per_season[order(per_season$type,season_start(per_season$season)),]
write.csv(per_season,file.path(OUT,'per_season_metrics.csv'),row.names=FALSE)

summary <- do.call(rbind,lapply(split(per_season,per_season$type),function(z){
  data.frame(
    type=z$type[1],n_test_seasons=nrow(z),n_origins=sum(z$n_origins),
    season_balanced_mae=mean(z$mae),season_balanced_rmse=mean(z$rmse),
    season_balanced_bias=mean(z$bias),
    season_balanced_early_weighted_mae=mean(z$early_weighted_mae),
    mean_coverage90=mean(z$coverage90),
    worst_season_mae=max(z$mae),
    stringsAsFactors=FALSE
  )
}))
write.csv(summary,file.path(OUT,'summary_metrics.csv'),row.names=FALSE)

manifest_paths <- c(PANEL_PATH,TIMING_PATH,ELIG_PATH,M0_PATH)
manifest <- data.frame(
  role=c('canonical_panel','timing_contract','modeling_eligibility','frozen_m0_fit'),
  path=manifest_paths,
  sha256=vapply(manifest_paths,sha256_file,character(1)),
  stringsAsFactors=FALSE
)
write.csv(manifest,file.path(OUT,'source_manifest.csv'),row.names=FALSE)

config <- data.frame(
  key=c('benchmark_version','primary_validation','min_train_seasons','candidate_step','A_max_future','B_max_future','B_amplitude_grid','B_activity_semantics','B_excluded_seasons','calibration_status'),
  value=c('v3-m1-chronological-baselines-v2-pandemic-excluded','expanding_window_strict_prior_seasons',MIN_TRAIN_SEASONS,CANDIDATE_STEP,A_MAX_FUTURE,B_MAX_FUTURE,'0.005:0.005:0.25','exploratory_transferred_A_rule','2018-19:no_meaningful_B_activity;2019-20:pandemic_transition','raw_posterior_no_bias_calibration'),
  stringsAsFactors=FALSE
)
write.csv(config,file.path(OUT,'benchmark_config.csv'),row.names=FALSE)

cat('Chronological M1 raw baselines complete\n')
print(summary,row.names=FALSE,digits=5)
cat('\nTest seasons by type\n')
print(per_season[,c('type','season','n_origins','mae','early_weighted_mae')],row.names=FALSE,digits=4)
