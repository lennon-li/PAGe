source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')
source('PAGe/R/pipeline_training.R')
source('PAGe/R/pipeline_runtime.R')

campaign <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
ignition <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/expert_ignition_labels_v2_pass1.csv', stringsAsFactors=FALSE)
peak_truth <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
global_m0 <- readRDS('artifacts/m0-v2-wmin12-raw3-decimal-loso-v1/loso_result.rds')
m0_grid <- as.data.frame(global_m0$folds[[1]]$tuning_grid, stringsAsFactors=FALSE)
seasons <- as.character(peak_truth$season)

out_dir <- 'artifacts/m1-v2-governed-nested-m0-wmin12-raw3-replay'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(out_dir,'m0_outer_training_loso'), recursive=TRUE, showWarnings=FALSE)

make_m0_data <- function(season_set) {
  d <- campaign[campaign$season %in% season_set, , drop=FALSE]
  tt <- data.frame(
    season=season_set,
    ignition_target_weekF=ignition$ignition_week_decimal[match(season_set, ignition$season)],
    stringsAsFactors=FALSE
  )
  d <- merge(d, tt, by='season', all.x=TRUE, sort=FALSE)
  d$phase <- as.integer(d$weekF >= ceiling(d$ignition_target_weekF))
  list(data=d, truth=tt)
}

fit_outer_training_m0 <- function(holdout) {
  cache <- file.path(out_dir,'m0_outer_training_loso',paste0(gsub('[^A-Za-z0-9]+','_',holdout),'.rds'))
  if (file.exists(cache)) {
    x <- readRDS(cache)
    if (inherits(x,'page_m0_loso_result')) return(x)
  }
  train <- setdiff(seasons, holdout)
  md <- make_m0_data(train)
  x <- loso_M0v2(
    md$data,
    grid=m0_grid,
    timing_truth=md$truth,
    timing_mode='fractional',
    selection_policy='legacy',
    verbose=FALSE,
    tune_args=list(
      miss_penalty=0, lambda=20, kappa=0, gamma=25, gamma_late=0,
      iWeek=TRUE, ncores=4L, verbose=FALSE, progress_every=200L
    )
  )
  saveRDS(x,cache)
  x
}

rows <- list(); stages <- list(); m0_audit <- list()
for (holdout in seasons) {
  message('outer holdout: ', holdout)
  train <- setdiff(seasons, holdout)
  m0_train_loso <- fit_outer_training_m0(holdout)
  activations <- m1_v2_activation_table_from_m0_loso(m0_train_loso)
  stage <- build_m1_v2_timing(
    campaign[campaign$season %in% train, , drop=FALSE],
    peak_truth[peak_truth$season %in% train, c('season','peak_week_decimal'), drop=FALSE],
    activations,
    k=8L, grid_step=.01, tau_step=.1,
    calibration_origins=4L, calibration_candidate_step=.2,
    passage_candidate_step=.2
  )
  stages[[holdout]] <- data.frame(
    season=holdout,
    artifact_id=stage$artifact_id,
    calibration_offset=stage$calibrator$offset_week,
    m0_context_id=attr(activations,'m0_loso_context_id'),
    passage_high=stage$passage_policy$selected$high_threshold,
    passage_low=stage$passage_policy$selected$low_threshold,
    passage_drop=stage$passage_policy$selected$drop_fraction,
    passage_fast_drop=stage$passage_policy$selected$fast_drop_fraction,
    passage_min_post=stage$passage_policy$selected$min_post_activation,
    stringsAsFactors=FALSE
  )
  m0_audit[[holdout]] <- cbind(
    data.frame(outer_holdout=holdout, stringsAsFactors=FALSE),
    as.data.frame(activations)
  )

  # Outer runtime M0 is the held-out detection from the full 11-season M0 LOSO;
  # that fold excludes the current outer season and is therefore prospective-safe.
  mr <- global_m0$compare[global_m0$compare$season == holdout, , drop=FALSE]
  if (nrow(mr) != 1L || !is.finite(mr$iWeek_hat) || !is.finite(mr$iWeek_hatF)) {
    stop('Missing outer M0 held-out detection for ', holdout)
  }
  tr <- peak_truth[peak_truth$season == holdout, , drop=FALSE]
  truth_confirm <- ceiling(tr$peak_week_decimal)-1L
  primary_last <- round(tr$peak_week_decimal)
  runtime_last <- truth_confirm+2L
  current <- campaign[campaign$season==holdout & campaign$weekF<=runtime_last, , drop=FALSE]
  rt <- run_m1_v2_timing(
    list(m1_v2=stage), current,
    list(iWeek_locked=as.integer(mr$iWeek_hat), iWeek_lockedF=mr$iWeek_hatF),
    verbose=FALSE
  )
  z <- rt$timing_df
  z$truth_peak_decimal <- tr$peak_week_decimal
  z$truth_peak_integer <- round(tr$peak_week_decimal)
  z$truth_confirm <- truth_confirm
  z$in_primary_metric <- z$origin_week >= as.integer(mr$iWeek_hat) & z$origin_week <= primary_last
  z$prediction_integer <- round(z$calibrated_peak_mean)
  z$weight_early <- exp(-(0.1*(z$origin_week-as.integer(mr$iWeek_hat)))^2)
  rows[[holdout]] <- z
}

x <- do.call(rbind,rows); rownames(x)<-NULL
stage_df <- do.call(rbind,stages); rownames(stage_df)<-NULL
m0_df <- do.call(rbind,m0_audit); rownames(m0_df)<-NULL
primary_mask <- x$in_primary_metric
if (any(!is.finite(x$calibrated_peak_mean[primary_mask])) ||
    any(!is.finite(x$raw_peak_mean[primary_mask]))) {
  bad <- x[primary_mask & (!is.finite(x$calibrated_peak_mean) | !is.finite(x$raw_peak_mean)),
           c("season","origin_week","state","error"), drop=FALSE]
  print(bad)
  stop("Authoritative M1-v2 replay has unavailable primary-origin timing predictions.")
}

score <- function(pred,truth_col) {
  ss <- sort(unique(x$season))
  mean(vapply(ss,function(s){
    z <- x[x$season==s & x$in_primary_metric,]
    sum(z$weight_early*abs(z[[pred]]-z[[truth_col]]))/sum(z$weight_early)
  },numeric(1)))
}
summary <- data.frame(
  active_integer_metric=score('prediction_integer','truth_peak_integer'),
  native_decimal_metric=score('calibrated_peak_mean','truth_peak_decimal'),
  raw_native_decimal_metric=score('raw_peak_mean','truth_peak_decimal'),
  n_primary_origins=sum(x$in_primary_metric),
  stringsAsFactors=FALSE
)
per <- do.call(rbind,lapply(split(x,x$season),function(z){
  primary <- z[z$in_primary_metric,]
  confirm_rows <- z[z$peak_passed,]
  confirm_origin <- if(nrow(confirm_rows)) min(confirm_rows$origin_week) else NA_real_
  tc <- unique(z$truth_confirm)
  data.frame(
    season=z$season[1], n_primary=nrow(primary),
    active_integer=sum(primary$weight_early*abs(primary$prediction_integer-primary$truth_peak_integer),na.rm=TRUE)/sum(primary$weight_early[is.finite(primary$prediction_integer)]),
    native_decimal=sum(primary$weight_early*abs(primary$calibrated_peak_mean-primary$truth_peak_decimal),na.rm=TRUE)/sum(primary$weight_early[is.finite(primary$calibrated_peak_mean)]),
    raw_decimal=sum(primary$weight_early*abs(primary$raw_peak_mean-primary$truth_peak_decimal),na.rm=TRUE)/sum(primary$weight_early[is.finite(primary$raw_peak_mean)]),
    final_state=tail(z$state,1), confirm_origin=confirm_origin, truth_confirm=tc,
    false_early=is.finite(confirm_origin) && confirm_origin<tc,
    delay=if(is.finite(confirm_origin)) max(confirm_origin-tc,0) else NA_real_,
    miss_by_peak2=!is.finite(confirm_origin) || confirm_origin>tc+2,
    locked_peak=tail(z$locked_peak_week,1), locked_at=tail(z$locked_at_origin,1),
    stringsAsFactors=FALSE
  )
}))

write.csv(x,file.path(out_dir,'per_origin.csv'),row.names=FALSE)
write.csv(stage_df,file.path(out_dir,'stage_artifacts.csv'),row.names=FALSE)
write.csv(m0_df,file.path(out_dir,'nested_m0_activations.csv'),row.names=FALSE)
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
write.csv(per,file.path(out_dir,'per_season.csv'),row.names=FALSE)
cat('SUMMARY\n');print(summary,row.names=FALSE,digits=6)
cat('\nPASSAGE\n');cat('false early=',sum(per$false_early),'/',nrow(per),' by+2=',sum(!per$miss_by_peak2),'/',nrow(per),' mean delay=',mean(per$delay[is.finite(per$delay)]),' median delay=',median(per$delay[is.finite(per$delay)]),'\n',sep='')
cat('\nSTAGES\n');print(stage_df,row.names=FALSE,digits=5)
cat('\nPER SEASON\n');print(per,row.names=FALSE,digits=5)
