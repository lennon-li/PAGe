source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

campaign <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
truth <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0 <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
seasons <- as.character(truth$season)
rows <- list(); calrows <- list()

for (holdout in seasons) {
  train <- setdiff(seasons, holdout)
  train_data <- campaign[campaign$season %in% train, , drop = FALSE]
  train_truth <- truth[truth$season %in% train, c('season','peak_week_decimal'), drop = FALSE]
  lib <- fit_m1_v2_library(train_data, train_truth, k=8L, grid_step=.01, tau_step=.1)
  act <- m0[m0$season %in% train, c('season','iWeek_hat','iWeek_hatF'), drop = FALSE]
  names(act) <- c('season','activation_origin_week','activation_week_decimal')
  cal <- fit_m1_v2_bias_calibrator(lib, train_data, train_truth, act, n_origins=4L, candidate_step=.2)
  calrows[[holdout]] <- data.frame(season=holdout,offset_week=cal$offset_week,mean_signed_bias=cal$mean_signed_bias)

  held <- campaign[campaign$season==holdout, , drop = FALSE]
  mr <- m0[m0$season==holdout, , drop = FALSE]
  tr <- truth[truth$season==holdout, , drop = FALSE]
  origins <- seq(as.integer(mr$iWeek_hat), round(tr$peak_week_decimal), by=1L)
  for (o in origins) {
    fc <- m1_v2_peak_posterior(lib, held, activation_week=mr$iWeek_hatF, origin_week=o, candidate_step=.1)
    adj <- m1_v2_apply_bias_calibration(fc, cal)
    rows[[length(rows)+1L]] <- data.frame(
      season=holdout, origin_weekF=o,
      m0_integer=as.integer(mr$iWeek_hat), m0_decimal=mr$iWeek_hatF,
      truth_peak_decimal=tr$peak_week_decimal, truth_peak_integer=round(tr$peak_week_decimal),
      raw_peak_mean=adj$peak_mean_raw, calibrated_peak_mean=adj$peak_mean_calibrated,
      raw_peak_integer=round(adj$peak_mean_raw), calibrated_peak_integer=round(adj$peak_mean_calibrated),
      calibration_offset=adj$calibration_offset_week,
      calibrated_mean_is_future=adj$calibrated_mean_is_future,
      weight_early=exp(-(0.1*(o-as.integer(mr$iWeek_hat)))^2),
      stringsAsFactors=FALSE
    )
  }
}
x <- do.call(rbind,rows); caltab <- do.call(rbind,calrows); rownames(caltab)<-NULL
score <- function(pred_col, truth_col) {
  ss <- sort(unique(x$season))
  mean(vapply(ss,function(s){
    z <- x[x$season==s,]
    sum(z$weight_early*abs(z[[pred_col]]-z[[truth_col]]))/sum(z$weight_early)
  },numeric(1)))
}
summary <- data.frame(
  method=c('raw','calibrated'),
  active_integer_metric=c(score('raw_peak_integer','truth_peak_integer'),score('calibrated_peak_integer','truth_peak_integer')),
  native_decimal_metric=c(score('raw_peak_mean','truth_peak_decimal'),score('calibrated_peak_mean','truth_peak_decimal'))
)
per <- do.call(rbind,lapply(split(x,x$season),function(z)data.frame(
  season=z$season[1], n=nrow(z), offset=z$calibration_offset[1],
  raw_int=sum(z$weight_early*abs(z$raw_peak_integer-z$truth_peak_integer))/sum(z$weight_early),
  cal_int=sum(z$weight_early*abs(z$calibrated_peak_integer-z$truth_peak_integer))/sum(z$weight_early),
  raw_dec=sum(z$weight_early*abs(z$raw_peak_mean-z$truth_peak_decimal))/sum(z$weight_early),
  cal_dec=sum(z$weight_early*abs(z$calibrated_peak_mean-z$truth_peak_decimal))/sum(z$weight_early),
  n_calibrated_mean_not_future=sum(!z$calibrated_mean_is_future)
)))

dir.create('artifacts/m1-v2-calibrated-package-api-replay',recursive=TRUE,showWarnings=FALSE)
write.csv(x,'artifacts/m1-v2-calibrated-package-api-replay/per_origin.csv',row.names=FALSE)
write.csv(caltab,'artifacts/m1-v2-calibrated-package-api-replay/calibrators.csv',row.names=FALSE)
write.csv(summary,'artifacts/m1-v2-calibrated-package-api-replay/summary.csv',row.names=FALSE)
write.csv(per,'artifacts/m1-v2-calibrated-package-api-replay/per_season.csv',row.names=FALSE)
cat('CALIBRATORS\n');print(caltab,row.names=FALSE,digits=5)
cat('\nSUMMARY\n');print(summary,row.names=FALSE,digits=6)
cat('\nPER SEASON\n');print(per,row.names=FALSE,digits=5)
