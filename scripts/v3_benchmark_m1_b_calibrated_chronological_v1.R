#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')
source('PAGe/R/pipeline_training.R')

if (!requireNamespace('digest', quietly=TRUE)) stop('Package `digest` is required.')

PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
TIMING_META <- 'artifacts/v3-joint-timing-contract-v2/contract_metadata.csv'
B_DETECT_PATH <- 'artifacts/v3-a-rule-transfer-to-b-v1/B_window8_40_detection.rds'
B0_PATH <- 'artifacts/v3-m1-chronological-baselines-v1/per_origin_predictions.csv'
FOLD_PATH <- 'artifacts/v3-m1-chronological-baselines-v1/fold_ledger.csv'
OUT <- 'artifacts/v3-m1-b-calibrated-chronological-v1'

dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

B_AMP_GRID <- seq(.005,.25,by=.005)
SCORED_STEP <- .1
CAL_ORIGINS <- 4L
CAL_STEP <- .2
PASS_STEP <- .2
LOW_SUPPORT_SEASON <- '2017-18'

sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))

panel <- read.csv(PANEL_PATH,check.names=FALSE)
truth <- read.csv(TIMING_PATH,check.names=FALSE)
meta <- read.csv(TIMING_META,check.names=FALSE)
b0_all <- read.csv(B0_PATH,check.names=FALSE)
folds <- read.csv(FOLD_PATH,check.names=FALSE)

B <- data.frame(season=as.character(panel$season),weekF=panel$weekF,y=panel$y_B,N=panel$N_B,p=panel$p_B)
B <- B[order(season_start(B$season),B$weekF),]
b0 <- b0_all[b0_all$type=='B',]
meaningful <- as.character(truth$season[is.finite(truth$B_peak_weekF) & truth$B_activity_detected])

contract_sha <- sha256_file(TIMING_PATH)
detect_sha <- sha256_file(B_DETECT_PATH)

make_b_activation_adapter <- function(seasons) {
  z <- truth[match(seasons,truth$season),c('season','B_activity_integer','B_activity_weekF','B_activity_status')]
  if (anyNA(z$season) || any(!is.finite(z$B_activity_integer)) || any(!is.finite(z$B_activity_weekF))) stop('Missing B activation for training season.')
  out <- data.frame(
    season=as.character(z$season),
    activation_origin_week=as.numeric(z$B_activity_integer),
    activation_week_decimal=as.numeric(z$B_activity_weekF),
    stringsAsFactors=FALSE
  )
  payload_hash <- digest::digest(.m1_v2_activation_payload(out),algo='sha256')
  provenance_id <- digest::digest(list(
    semantics='v3-B-activity-research-adapter',
    marker_payload=.m1_v2_activation_payload(out),
    timing_contract_sha256=contract_sha,
    B_detection_rds_sha256=detect_sha,
    window='8-40'
  ),algo='sha256')
  attr(out,'m0_loso_context_id') <- paste0('v3-B-activity-A-rule-transfer-w8_40:',contract_sha)
  attr(out,'activation_provenance_id') <- provenance_id
  attr(out,'activation_payload_hash') <- payload_hash
  class(out) <- c('page_m1_v2_activation_table','data.frame')
  out
}

metric_weight <- function(origin,activation_origin) exp(-(0.1*(origin-activation_origin))^2)

# Predeclared fold universe exactly matches existing B0 scored test seasons.
test_seasons <- unique(as.character(b0$season))

stage_rows <- list(); inner_rows <- list(); pred_rows <- list(); passage_rows <- list(); leak_rows <- list(); sens_rows <- list(); leave22_rows <- list(); failure_rows <- list(); policy_eval_rows <- list()

for (test in test_seasons) {
  fold <- folds[folds$test_season==test,]
  if (nrow(fold)!=1L) stop('Fold missing for ',test)
  prior <- strsplit(fold$training_seasons,';',fixed=TRUE)[[1]]
  train_seasons <- prior[prior %in% meaningful]
  if (length(train_seasons)<4L) stop('Insufficient meaningful-B training seasons for ',test)

  trainB <- B[B$season %in% train_seasons,]
  train_truth <- truth[truth$season %in% train_seasons,c('season','B_peak_weekF')]
  train_truth <- train_truth[match(train_seasons,train_truth$season),]
  names(train_truth)[2] <- 'peak_week_decimal'
  act_train <- make_b_activation_adapter(train_seasons)

  stage <- build_m1_v2_timing(
    allD=trainB,
    peak_truth=train_truth,
    activation_table=act_train,
    k=8L,grid_step=.01,tau_step=.1,
    amplitude_grid=B_AMP_GRID,
    calibration_origins=CAL_ORIGINS,
    calibration_candidate_step=CAL_STEP,
    passage_candidate_step=PASS_STEP
  )
  if (!inherits(stage,'page_m1_v2_stage')) stop('Stage construction failed.')
  if (!identical(stage$calibrator$library_hash,stage$library$provenance$library_hash)) stop('Calibrator/library hash mismatch.')
  if (!identical(stage$passage_policy$library_hash,stage$library$provenance$library_hash)) stop('Passage/library hash mismatch.')

  regimes <- unique(panel[panel$season %in% train_seasons,c('season','denominator_regime')])
  n_proxy <- sum(regimes$denominator_regime=='historical_shared_flu_test_proxy')
  n_type <- sum(regimes$denominator_regime!='historical_shared_flu_test_proxy')
  sel <- stage$passage_policy$selected[1,]
  pe <- stage$passage_policy$evaluation
  pe <- pe[pe$policy_id == sel$policy_id, , drop=FALSE]
  pe$test_season <- test
  pe$selection_note <- 'selected under frozen M1-v2 priority; sustained-branch settings may be tie-broken when all confirmations use fast branch'
  policy_eval_rows[[length(policy_eval_rows)+1L]] <- pe

  inner <- stage$calibrator$inner_predictions
  inner$test_season <- test
  inner$inner_asof_boundary <- inner$origin_week+1
  peak_map <- setNames(train_truth$peak_week_decimal,train_truth$season)
  inner$inner_truth_peak <- unname(peak_map[inner$season])
  inner$inner_post_peak_origin <- inner$inner_asof_boundary > inner$inner_truth_peak
  inner_rows[[length(inner_rows)+1L]] <- inner

  stage_rows[[length(stage_rows)+1L]] <- data.frame(
    test_season=test,n_train=length(train_seasons),training_seasons=paste(train_seasons,collapse=';'),
    low_support=(test==LOW_SUPPORT_SEASON),stage_artifact_id=stage$artifact_id,
    library_hash=stage$library$provenance$library_hash,calibration_offset_week=stage$calibrator$offset_week,
    calibration_mean_signed_bias=stage$calibrator$mean_signed_bias,
    calibration_post_peak_inner_rows=sum(inner$inner_post_peak_origin),
    passage_high=sel$high_threshold,passage_low=sel$low_threshold,
    passage_drop=sel$drop_fraction,passage_min_post=sel$min_post_activation,
    passage_fast_drop=sel$fast_drop_fraction,
    n_proxy_regime=n_proxy,n_type_specific_regime=n_type,
    activation_semantics='exploratory_transferred_A_rule_global_selection',
    stringsAsFactors=FALSE
  )

  # Diagnostic-only calibrator offset excluding 2022-23 from calibration rows.
  if ('2022-23' %in% inner$season) {
    di <- inner[inner$season!='2022-23',]
    di$wbal <- ave(di$weight_early,di$season,FUN=function(v)v/sum(v))
    alt_bias <- sum(di$wbal*di$signed_error)/sum(di$wbal)
    leave22_rows[[length(leave22_rows)+1L]] <- data.frame(test_season=test,primary_offset=stage$calibrator$offset_week,exclude_2022_offset=-alt_bias,delta_offset=(-alt_bias)-stage$calibrator$offset_week,stringsAsFactors=FALSE)
  }

  held <- B[B$season==test,]
  act_dec <- truth$B_activity_weekF[truth$season==test]
  act_int <- truth$B_activity_integer[truth$season==test]
  T <- truth$B_peak_weekF[truth$season==test]
  if (!all(is.finite(c(act_dec,act_int,T)))) stop('Test B timing missing for ',test)
  test_regime <- unique(panel$denominator_regime[panel$season==test])
  if (length(test_regime)!=1L) stop('Test season has multiple denominator regimes.')
  origins <- sort(b0$origin_weekF[b0$season==test])

  for (o in origins) {
    fit <- tryCatch(m1_v2_peak_posterior(stage$library,held,act_dec,o,candidate_step=SCORED_STEP),error=function(e)e)
    if (inherits(fit,'error')) {
      failure_rows[[length(failure_rows)+1L]] <- data.frame(season=test,origin_weekF=o,stage='peak_posterior',message=conditionMessage(fit),stringsAsFactors=FALSE)
      next
    }
    stored <- b0[b0$season==test & b0$origin_weekF==o,]
    if (nrow(stored)!=1L) stop('B0 stored origin mismatch.')
    if (abs(fit$summary$peak_mean-stored$pred_peak_mean)>1e-8) stop('Raw recomputation differs from B0 at ',test,'/',o)
    cal <- m1_v2_apply_bias_calibration(fit,stage$calibrator)

    pred_rows[[length(pred_rows)+1L]] <- data.frame(
      season=test,origin_weekF=o,denominator_regime=test_regime,low_support=(test==LOW_SUPPORT_SEASON),
      activation_weekF=act_dec,truth_peak_weekF=T,
      raw_mean=fit$summary$peak_mean,calibrated_mean=cal$peak_mean_calibrated,
      raw_median=fit$summary$peak_median,calibrated_median=cal$peak_median_calibrated,
      raw_map=fit$summary$peak_map,calibrated_map=cal$peak_map_calibrated,
      raw_q05=fit$summary$peak_q05,raw_q95=fit$summary$peak_q95,
      calibrated_q05=cal$peak_q05_calibrated,calibrated_q95=cal$peak_q95_calibrated,
      raw_error=fit$summary$peak_mean-T,calibrated_error=cal$peak_mean_calibrated-T,
      raw_abs_error=abs(fit$summary$peak_mean-T),calibrated_abs_error=abs(cal$peak_mean_calibrated-T),
      raw_covered90=fit$summary$peak_q05<=T && fit$summary$peak_q95>=T,
      calibrated_covered90=cal$peak_q05_calibrated<=T && cal$peak_q95_calibrated>=T,
      calibration_offset=stage$calibrator$offset_week,
      weight_early=metric_weight(o,act_int),stringsAsFactors=FALSE
    )

    # Future perturbation: prediction at o must be unchanged.
    held2 <- held; future <- held2$weekF>o
    if (any(future)) { held2$y[future] <- pmin(held2$N[future],held2$y[future]+7); held2$p[future] <- held2$y[future]/held2$N[future] }
    fit2 <- m1_v2_peak_posterior(stage$library,held2,act_dec,o,candidate_step=SCORED_STEP)
    cal2 <- m1_v2_apply_bias_calibration(fit2,stage$calibrator)
    pred_inv <- max(abs(c(fit2$summary$peak_mean-fit$summary$peak_mean,cal2$peak_mean_calibrated-cal$peak_mean_calibrated)))<1e-12
    if (!pred_inv) stop('Future prediction perturbation failed at ',test,'/',o)
    leak_rows[[length(leak_rows)+1L]] <- data.frame(season=test,origin_weekF=o,prediction_future_invariant=pred_inv,stringsAsFactors=FALSE)

    # Activation +/-1 sensitivity, same trained stage, diagnostic only.
    for (shift in c(-1,1)) {
      a2 <- act_dec+shift
      serr <- NA_character_
      sf <- tryCatch(m1_v2_peak_posterior(stage$library,held,a2,o,candidate_step=SCORED_STEP),error=function(e){ serr <<- conditionMessage(e); NULL })
      if (!is.null(sf)) {
        sc <- m1_v2_apply_bias_calibration(sf,stage$calibrator)
        sens_rows[[length(sens_rows)+1L]] <- data.frame(season=test,origin_weekF=o,activation_shift=shift,status='ok',message=NA_character_,pred_raw=sf$summary$peak_mean,pred_calibrated=sc$peak_mean_calibrated,truth=T,raw_abs_error=abs(sf$summary$peak_mean-T),cal_abs_error=abs(sc$peak_mean_calibrated-T),stringsAsFactors=FALSE)
      } else {
        sens_rows[[length(sens_rows)+1L]] <- data.frame(season=test,origin_weekF=o,activation_shift=shift,status='unsupported_at_origin',message=serr,pred_raw=NA_real_,pred_calibrated=NA_real_,truth=T,raw_abs_error=NA_real_,cal_abs_error=NA_real_,stringsAsFactors=FALSE)
      }
    }
  }

  # Passage replay through truth-confirm + 6 or season end.
  policy <- stage$passage_policy$selected[1,]
  truth_confirm <- ceiling(T)-1
  last_origin <- min(max(held$weekF),truth_confirm+6L)
  hist <- NULL; first_confirm <- NA_real_; first_branch <- NA_character_
  passage_future_ok <- TRUE
  if (act_int <= last_origin) {
    for (o in seq(act_int,last_origin)) {
      pp <- m1_v2_passage_posterior(stage$library,held,act_dec,o,candidate_step=PASS_STEP)
      hist <- rbind(hist,pp)
      dec <- m1_v2_passage_decision(
        hist,held,act_dec,
        high_threshold=policy$high_threshold,
        low_threshold=policy$low_threshold,
        drop_fraction=policy$drop_fraction,
        fast_drop_fraction=policy$fast_drop_fraction,
        min_post_activation=policy$min_post_activation
      )
      if (!is.finite(first_confirm) && isTRUE(dec$peak_reached_or_passed)) {
        first_confirm <- o; first_branch <- dec$confirmation_branch
      }
      # Future-B perturbation must leave current passage probability and decision unchanged.
      heldp <- held; fut <- heldp$weekF>o
      if (any(fut)) { heldp$y[fut] <- pmin(heldp$N[fut],heldp$y[fut]+7); heldp$p[fut] <- heldp$y[fut]/heldp$N[fut] }
      pp2 <- m1_v2_passage_posterior(stage$library,heldp,act_dec,o,candidate_step=PASS_STEP)
      hp <- rbind(if(nrow(hist)>1) hist[-nrow(hist),] else NULL,pp2)
      dec2 <- m1_v2_passage_decision(hp,heldp,act_dec,high_threshold=policy$high_threshold,low_threshold=policy$low_threshold,drop_fraction=policy$drop_fraction,fast_drop_fraction=policy$fast_drop_fraction,min_post_activation=policy$min_post_activation)
      ok <- abs(pp2$prob_peak_passed-pp$prob_peak_passed)<1e-12 && identical(dec2$peak_reached_or_passed,dec$peak_reached_or_passed)
      passage_future_ok <- passage_future_ok && ok
      if (!ok) stop('Future passage perturbation failed at ',test,'/',o)
    }
  }
  passage_rows[[length(passage_rows)+1L]] <- data.frame(
    season=test,truth_peak=T,truth_confirm=truth_confirm,confirm_origin=first_confirm,branch=first_branch,
    false_early=is.finite(first_confirm) && first_confirm<truth_confirm,
    early_weeks=if(is.finite(first_confirm)) max(truth_confirm-first_confirm,0) else 0,
    confirmed_by_peak2=is.finite(first_confirm) && first_confirm<=truth_confirm+2,
    delay=if(is.finite(first_confirm)) max(first_confirm-truth_confirm,0) else NA_real_,
    future_invariant=passage_future_ok,stringsAsFactors=FALSE)
}

if (length(failure_rows)) {
  failures <- do.call(rbind,failure_rows)
  write.csv(failures,file.path(OUT,'failures.csv'),row.names=FALSE)
  stop('Peak-posterior failures occurred; see failures.csv')
}

pred <- do.call(rbind,pred_rows)
stages <- do.call(rbind,stage_rows)
inner_all <- do.call(rbind,inner_rows)
passage <- do.call(rbind,passage_rows)
leak <- do.call(rbind,leak_rows)
sens <- if(length(sens_rows)) do.call(rbind,sens_rows) else data.frame()
leave22 <- if(length(leave22_rows)) do.call(rbind,leave22_rows) else data.frame()
policy_eval <- if(length(policy_eval_rows)) do.call(rbind,policy_eval_rows) else data.frame()

per_season <- do.call(rbind,lapply(split(pred,pred$season),function(z){
  data.frame(
    season=z$season[1],denominator_regime=z$denominator_regime[1],low_support=z$low_support[1],n_origins=nrow(z),
    raw_mae=mean(z$raw_abs_error),calibrated_mae=mean(z$calibrated_abs_error),
    raw_rmse=sqrt(mean(z$raw_error^2)),calibrated_rmse=sqrt(mean(z$calibrated_error^2)),
    raw_bias=mean(z$raw_error),calibrated_bias=mean(z$calibrated_error),
    raw_early_weighted_mae=sum(z$weight_early*z$raw_abs_error)/sum(z$weight_early),
    calibrated_early_weighted_mae=sum(z$weight_early*z$calibrated_abs_error)/sum(z$weight_early),
    raw_coverage90=mean(z$raw_covered90),calibrated_coverage90=mean(z$calibrated_covered90),
    stringsAsFactors=FALSE)
}))
per_season <- per_season[order(season_start(per_season$season)),]

summarize_set <- function(ps,label) data.frame(
  subset=label,n_seasons=nrow(ps),n_origins=sum(ps$n_origins),
  raw_season_balanced_mae=mean(ps$raw_mae),calibrated_season_balanced_mae=mean(ps$calibrated_mae),
  raw_early_weighted_mae=mean(ps$raw_early_weighted_mae),calibrated_early_weighted_mae=mean(ps$calibrated_early_weighted_mae),
  raw_rmse=mean(ps$raw_rmse),calibrated_rmse=mean(ps$calibrated_rmse),
  raw_bias=mean(ps$raw_bias),calibrated_bias=mean(ps$calibrated_bias),
  raw_coverage90=mean(ps$raw_coverage90),calibrated_coverage90=mean(ps$calibrated_coverage90),
  raw_worst_season_mae=max(ps$raw_mae),calibrated_worst_season_mae=max(ps$calibrated_mae),
  n_seasons_worse=sum(ps$calibrated_mae>ps$raw_mae),stringsAsFactors=FALSE)
summary_all <- summarize_set(per_season,'all')
summary_no_low <- summarize_set(per_season[!per_season$low_support,],'exclude_2017-18_low_support')
summary <- rbind(summary_all,summary_no_low)

by_regime <- do.call(rbind,lapply(split(per_season,per_season$denominator_regime),function(z) summarize_set(z,z$denominator_regime[1])))

pass_summary <- data.frame(
  n_seasons=nrow(passage),n_false_early=sum(passage$false_early),early_weeks_total=sum(passage$early_weeks),
  max_early_weeks=max(passage$early_weeks),confirmed_by_peak2=sum(passage$confirmed_by_peak2),
  mean_delay=mean(ifelse(is.finite(passage$delay),passage$delay,7)),median_delay=median(passage$delay,na.rm=TRUE),
  all_future_invariant=all(passage$future_invariant),stringsAsFactors=FALSE)

# Explicit inactive no-event season row.
inactive <- truth[!truth$B_activity_detected | !is.finite(truth$B_peak_weekF),c('season','B_activity_status','B_peak_status')]
inactive$M1_B_state <- 'inactive_no_meaningful_activity'
inactive$timing_scored <- FALSE

# Check 2018-19 is absent from every fitted stage universe.
if ('2018-19' %in% unlist(strsplit(stages$training_seasons,';',fixed=TRUE))) stop('2018-19 leaked into meaningful-B training stage.')

# Predeclared interpretation checks, separated so calibration and raw-passage
# conclusions cannot be conflated. Evaluate calibration on both declared sets.
cal_threshold_rows <- do.call(rbind,lapply(seq_len(nrow(summary)),function(i){
  ss <- summary[i,]
  data.frame(
    scope='calibration',subset=ss$subset,
    criterion=c('calibrated_mae_le_raw','calibrated_early_weighted_le_raw','worst_mae_delta_le_0.5','n_seasons_worse_le_2','calibrated_coverage_ge_0.70','prediction_integrity_all_pass'),
    pass=c(
      ss$calibrated_season_balanced_mae<=ss$raw_season_balanced_mae,
      ss$calibrated_early_weighted_mae<=ss$raw_early_weighted_mae,
      ss$calibrated_worst_season_mae<=ss$raw_worst_season_mae+.5,
      ss$n_seasons_worse<=2,
      ss$calibrated_coverage90>=.70,
      all(leak$prediction_future_invariant)
    ),stringsAsFactors=FALSE)
}))
pass_threshold_rows <- data.frame(
  scope='raw_B0_passage',subset='all',
  criterion=c('passage_false_early_zero','passage_future_integrity_all_pass'),
  pass=c(pass_summary$n_false_early==0,all(passage$future_invariant)),
  stringsAsFactors=FALSE)
threshold_eval <- rbind(cal_threshold_rows,pass_threshold_rows)

write.csv(folds,file.path(OUT,'fold_ledger.csv'),row.names=FALSE)
write.csv(stages,file.path(OUT,'stage_ledger.csv'),row.names=FALSE)
write.csv(inner_all,file.path(OUT,'calibrator_inner_predictions.csv'),row.names=FALSE)
write.csv(pred,file.path(OUT,'per_origin_predictions.csv'),row.names=FALSE)
write.csv(per_season,file.path(OUT,'per_season_metrics.csv'),row.names=FALSE)
write.csv(summary,file.path(OUT,'summary_metrics.csv'),row.names=FALSE)
write.csv(summary_no_low,file.path(OUT,'summary_excluding_low_support.csv'),row.names=FALSE)
write.csv(by_regime,file.path(OUT,'metrics_by_denominator_regime.csv'),row.names=FALSE)
write.csv(passage,file.path(OUT,'passage_by_season.csv'),row.names=FALSE)
write.csv(pass_summary,file.path(OUT,'passage_summary.csv'),row.names=FALSE)
write.csv(passage,file.path(OUT,'raw_B0_passage_by_season.csv'),row.names=FALSE)
write.csv(pass_summary,file.path(OUT,'raw_B0_passage_summary.csv'),row.names=FALSE)
write.csv(policy_eval,file.path(OUT,'selected_passage_policy_inner_evaluation.csv'),row.names=FALSE)
write.csv(leak,file.path(OUT,'future_perturbation_checks.csv'),row.names=FALSE)
write.csv(sens,file.path(OUT,'activation_sensitivity.csv'),row.names=FALSE)
write.csv(leave22,file.path(OUT,'calibrator_leave_2022_diagnostic.csv'),row.names=FALSE)
write.csv(inactive,file.path(OUT,'inactive_no_event_seasons.csv'),row.names=FALSE)
write.csv(threshold_eval,file.path(OUT,'predeclared_threshold_evaluation.csv'),row.names=FALSE)

manifest_paths <- c(PANEL_PATH,TIMING_PATH,TIMING_META,B_DETECT_PATH,B0_PATH,FOLD_PATH)
manifest <- data.frame(role=c('canonical_panel','timing_contract','timing_contract_metadata','B_activity_detector','raw_B0_baseline','fold_ledger'),path=manifest_paths,sha256=vapply(manifest_paths,sha256_file,character(1)),stringsAsFactors=FALSE)
write.csv(manifest,file.path(OUT,'source_manifest.csv'),row.names=FALSE)

config <- data.frame(key=c('version','status','activation_limitation','amplitude_grid','calibration_origins','calibration_step','passage_step','scored_step','low_support_season'),value=c('v3-m1-b-calibrated-chronological-v1','conditional_research_not_governed','global B activity rule selected with full archive','0.005:0.005:0.25',CAL_ORIGINS,CAL_STEP,PASS_STEP,SCORED_STEP,LOW_SUPPORT_SEASON),stringsAsFactors=FALSE)
write.csv(config,file.path(OUT,'benchmark_config.csv'),row.names=FALSE)

cat('Calibrated chronological M1-B benchmark complete\n')
print(summary,row.names=FALSE,digits=5)
cat('\nPassage summary\n'); print(pass_summary,row.names=FALSE,digits=5)
cat('\nPredeclared thresholds\n'); print(threshold_eval,row.names=FALSE)
cat('\nStage offsets\n'); print(stages[,c('test_season','n_train','calibration_offset_week','calibration_post_peak_inner_rows','n_proxy_regime','n_type_specific_regime')],row.names=FALSE,digits=5)
