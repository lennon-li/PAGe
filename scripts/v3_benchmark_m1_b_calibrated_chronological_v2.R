#!/usr/bin/env Rscript

# Audited corrected rerun of the calibrated B-only M1-B chronological benchmark.
# See docs/v3-m1-b-calibrated-audit-disposition-2026-09-25.md. The v1 artifacts
# are the first look and are hashed, never rewritten. Frozen PAGe/R code is
# sourced unchanged.

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
B0_CONFIG_PATH <- 'artifacts/v3-m1-chronological-baselines-v1/benchmark_config.csv'
FOLD_PATH <- 'artifacts/v3-m1-chronological-baselines-v1/fold_ledger.csv'
V1_DIR <- 'artifacts/v3-m1-b-calibrated-chronological-v1'
V1_SCRIPT <- 'scripts/v3_benchmark_m1_b_calibrated_chronological_v1.R'
OUT <- 'artifacts/v3-m1-b-calibrated-chronological-v2'

out_nonempty <- function() dir.exists(OUT) && length(list.files(OUT,all.files=TRUE,no..=TRUE))>0L
if (out_nonempty()) stop('Output directory already exists and is not empty: ',OUT)

B_AMP_GRID <- seq(.005,.25,by=.005)
SCORED_STEP <- .1
B_MAX_FUTURE <- 16
PASSAGE_MAX_FUTURE <- eval(formals(m1_v2_passage_posterior)$max_future_weeks)
CALIBRATOR_MAX_FUTURE <- eval(formals(m1_v2_peak_posterior)$max_future_weeks)
CAL_ORIGINS <- 4L
CAL_STEP <- .2
PASS_STEP <- .2
PASSAGE_LATE_WEEKS <- 6L
MIN_TRAIN <- 4L
LOW_SUPPORT_SEASON <- '2017-18'
INACTIVE_SEASON <- '2018-19'
ACTIVATION_SHIFTS <- c(-1L,1L)
N_CORES <- as.integer(Sys.getenv('PAGE_BENCH_CORES',unset='8'))

sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))
metric_weight <- function(origin,activation_origin) exp(-(0.1*(origin-activation_origin))^2)
origin_max_prepeak <- function(T) floor(T-1e-8)-1L
perturb_future <- function(d,o) {
  fut <- d$weekF>o
  if (any(fut)) { d$y[fut] <- pmin(d$N[fut],d$y[fut]+7); d$p[fut] <- d$y[fut]/d$N[fut] }
  d
}

# Preserve the first look: hash every v1 result file before and after the run.
v1_files <- sort(list.files(V1_DIR,full.names=TRUE))
if (!length(v1_files)) stop('v1 first-look artifacts are missing.')
v1_hash_start <- vapply(c(v1_files,V1_SCRIPT),sha256_file,character(1))

panel <- read.csv(PANEL_PATH,check.names=FALSE)
truth <- read.csv(TIMING_PATH,check.names=FALSE)
b0_all <- read.csv(B0_PATH,check.names=FALSE)
b0_cfg <- read.csv(B0_CONFIG_PATH,check.names=FALSE)
folds <- read.csv(FOLD_PATH,check.names=FALSE)

if (!identical(as.numeric(b0_cfg$value[b0_cfg$key=='B_max_future']),B_MAX_FUTURE)) stop('B0 max_future_weeks differs from benchmark configuration.')
if (!identical(as.numeric(b0_cfg$value[b0_cfg$key=='candidate_step']),SCORED_STEP)) stop('B0 candidate step differs from benchmark configuration.')

B <- data.frame(season=as.character(panel$season),weekF=panel$weekF,y=panel$y_B,N=panel$N_B,p=panel$p_B)
B <- B[order(season_start(B$season),B$weekF),]
b0 <- b0_all[b0_all$type=='B',]
meaningful <- as.character(truth$season[is.finite(truth$B_peak_weekF) & truth$B_activity_detected])

contract_sha <- sha256_file(TIMING_PATH)
detect_sha <- sha256_file(B_DETECT_PATH)

# Timing-contract semantic assertions.
tm <- truth[truth$season %in% meaningful,]
if (any(tm$B_peak_status!='retrospective_peak_truth')) stop('Meaningful B season lacks retrospective peak truth status.')
if (any(!is.finite(tm$B_activity_weekF)) || any(tm$B_activity_integer!=ceiling(tm$B_activity_weekF))) stop('B activity integer is not ceiling(B activity decimal).')
if (any(tm$B_activity_weekF>=tm$B_peak_weekF)) stop('B activation is not before B peak truth.')
ti <- truth[truth$season==INACTIVE_SEASON,]
if (nrow(ti)!=1L || isTRUE(ti$B_activity_detected) || is.finite(ti$B_peak_weekF) || ti$B_peak_status!='no_meaningful_peak') stop('Inactive-season timing semantics changed.')
if (INACTIVE_SEASON %in% meaningful) stop('Inactive season is marked meaningful.')

make_b_activation_adapter <- function(seasons,shift=0L) {
  z <- truth[match(seasons,truth$season),c('season','B_activity_integer','B_activity_weekF','B_activity_status')]
  if (anyNA(z$season) || any(!is.finite(z$B_activity_integer)) || any(!is.finite(z$B_activity_weekF))) stop('Missing B activation for training season.')
  out <- data.frame(
    season=as.character(z$season),
    activation_origin_week=as.numeric(z$B_activity_integer)+shift,
    activation_week_decimal=as.numeric(z$B_activity_weekF)+shift,
    stringsAsFactors=FALSE
  )
  payload_hash <- digest::digest(.m1_v2_activation_payload(out),algo='sha256')
  provenance_id <- digest::digest(list(
    semantics='v3-B-activity-research-adapter',
    marker_payload=.m1_v2_activation_payload(out),
    timing_contract_sha256=contract_sha,
    B_detection_rds_sha256=detect_sha,
    window='8-40',
    activation_shift=shift
  ),algo='sha256')
  attr(out,'m0_loso_context_id') <- paste0('v3-B-activity-A-rule-transfer-w8_40:',contract_sha,':shift',shift)
  attr(out,'activation_provenance_id') <- provenance_id
  attr(out,'activation_payload_hash') <- payload_hash
  class(out) <- c('page_m1_v2_activation_table','data.frame')
  out
}

# Predeclared fold universe: exactly the B0 scored test seasons, which must equal
# the eligible-B fold ledger rows.
test_seasons <- unique(as.character(b0$season))
if (!setequal(test_seasons,folds$test_season[folds$eligible_B])) stop('B0 seasons differ from eligible-B fold ledger.')
if (INACTIVE_SEASON %in% test_seasons) stop('Inactive season is a scored test season.')

fold_train_seasons <- function(test) {
  fold <- folds[folds$test_season==test,]
  if (nrow(fold)!=1L) stop('Fold missing for ',test)
  prior <- strsplit(fold$training_seasons,';',fixed=TRUE)[[1]]
  prior[prior %in% meaningful]
}

fold_inputs <- function(test,Bdata,shift) {
  train_seasons <- fold_train_seasons(test)
  trainB <- Bdata[Bdata$season %in% train_seasons,]
  train_truth <- truth[truth$season %in% train_seasons,c('season','B_peak_weekF')]
  train_truth <- train_truth[match(train_seasons,train_truth$season),]
  names(train_truth)[2] <- 'peak_week_decimal'
  rownames(trainB) <- NULL; rownames(train_truth) <- NULL
  held <- Bdata[Bdata$season==test,]
  rownames(held) <- NULL
  list(train_seasons=train_seasons,trainB=trainB,train_truth=train_truth,
       act_train=make_b_activation_adapter(train_seasons,shift),held=held,
       digest=digest::digest(list(trainB,train_truth,held),algo='sha256'))
}

# Explicit fold-isolation semantic assertions; any violation stops the run.
assert_fold_isolation <- function(test,inp,stage) {
  tr <- inp$train_seasons
  if (length(tr)<MIN_TRAIN) stop('Insufficient meaningful-B training seasons for ',test)
  if (test %in% tr) stop('Test season in training set: ',test)
  if (any(season_start(tr)>=season_start(test))) stop('Chronological fold leakage at ',test)
  if (!all(tr %in% meaningful) || INACTIVE_SEASON %in% tr) stop('Non-meaningful B season in training at ',test)
  if (!setequal(unique(inp$trainB$season),tr)) stop('Training data seasons differ from fold training set at ',test)
  if (!identical(unique(inp$held$season),test)) stop('Held-out data contains other seasons at ',test)
  if (!setequal(stage$training_seasons,tr) || !setequal(stage$calibrator$training_seasons,tr)) stop('Stage training universe differs from fold at ',test)
  if (!all(stage$calibrator$inner_predictions$season %in% tr)) stop('Calibrator inner rows outside fold at ',test)
  if (!all(stage$passage_policy$evaluation$season %in% tr)) stop('Passage-policy evaluation outside fold at ',test)
  if (!identical(stage$calibrator$library_hash,stage$library$provenance$library_hash)) stop('Calibrator/library hash mismatch at ',test)
  if (!identical(stage$passage_policy$library_hash,stage$library$provenance$library_hash)) stop('Passage/library hash mismatch at ',test)
  TRUE
}

failure_row <- function(test,shift,o,stage,e) data.frame(season=test,activation_shift=shift,origin_weekF=o,stage=stage,message=conditionMessage(e),stringsAsFactors=FALSE)

# Sequential passage replay from (shifted) activation through truth-confirm + 6.
# Every posterior/decision call is failure-captured.
replay_passage <- function(test,shift,stage,held,act_dec,T,check_future) {
  policy <- stage$passage_policy$selected[1,]
  act_int <- ceiling(act_dec)
  truth_confirm <- ceiling(T)-1
  last_origin <- min(max(held$weekF),truth_confirm+PASSAGE_LATE_WEEKS)
  hist <- NULL; first_confirm <- NA_real_; first_branch <- NA_character_
  future_ok <- TRUE; fails <- list(); n_origins <- 0L
  decide <- function(h,d) m1_v2_passage_decision(h,d,act_dec,high_threshold=policy$high_threshold,low_threshold=policy$low_threshold,drop_fraction=policy$drop_fraction,fast_drop_fraction=policy$fast_drop_fraction,min_post_activation=policy$min_post_activation)
  if (act_int<=last_origin) for (o in seq(act_int,last_origin)) {
    step <- tryCatch({
      pp <- m1_v2_passage_posterior(stage$library,held,act_dec,o,candidate_step=PASS_STEP,max_future_weeks=PASSAGE_MAX_FUTURE)
      h <- rbind(hist,pp)
      list(pp=pp,hist=h,dec=decide(h,held))
    },error=function(e)e)
    if (inherits(step,'error')) { fails[[length(fails)+1L]] <- failure_row(test,shift,o,'passage',step); break }
    n_origins <- n_origins+1L
    pp <- step$pp; hist <- step$hist; dec <- step$dec
    if (!is.finite(first_confirm) && isTRUE(dec$peak_reached_or_passed)) { first_confirm <- o; first_branch <- dec$confirmation_branch }
    if (check_future) {
      chk <- tryCatch({
        heldp <- perturb_future(held,o)
        pp2 <- m1_v2_passage_posterior(stage$library,heldp,act_dec,o,candidate_step=PASS_STEP,max_future_weeks=PASSAGE_MAX_FUTURE)
        hp <- rbind(if(nrow(hist)>1) hist[-nrow(hist),] else NULL,pp2)
        dec2 <- decide(hp,heldp)
        abs(pp2$prob_peak_passed-pp$prob_peak_passed)<1e-12 && identical(dec2$peak_reached_or_passed,dec$peak_reached_or_passed)
      },error=function(e)e)
      if (inherits(chk,'error')) { fails[[length(fails)+1L]] <- failure_row(test,shift,o,'passage_future_check',chk); future_ok <- FALSE }
      else future_ok <- future_ok && isTRUE(chk)
    }
  }
  completed <- !length(fails)
  list(row=data.frame(
    season=test,activation_shift=shift,activation_weekF=act_dec,truth_peak=T,truth_confirm=truth_confirm,
    first_origin=act_int,last_origin=last_origin,n_origins_replayed=n_origins,replay_completed=completed,
    confirm_origin=first_confirm,branch=first_branch,
    false_early=is.finite(first_confirm) && first_confirm<truth_confirm,
    early_weeks=if(is.finite(first_confirm)) max(truth_confirm-first_confirm,0) else 0,
    confirmed_by_peak2=is.finite(first_confirm) && first_confirm<=truth_confirm+2,
    delay=if(is.finite(first_confirm)) max(first_confirm-truth_confirm,0) else NA_real_,
    future_invariant=if(check_future) future_ok else NA,
    policy_high=policy$high_threshold,policy_low=policy$low_threshold,policy_drop=policy$drop_fraction,
    policy_fast_drop=policy$fast_drop_fraction,policy_min_post=policy$min_post_activation,
    stringsAsFactors=FALSE),failures=fails)
}

# One chronological fold under one activation shift. shift = 0 is the primary
# benchmark; shifted runs move training and test activation together, rebuild the
# whole stage, regenerate the scored origin path and replay passage.
run_fold <- function(test,shift=0L,Bdata=B,primary=TRUE) {
  inp <- fold_inputs(test,Bdata,shift)
  stage <- build_m1_v2_timing(
    allD=inp$trainB,
    peak_truth=inp$train_truth,
    activation_table=inp$act_train,
    k=8L,grid_step=.01,tau_step=.1,
    amplitude_grid=B_AMP_GRID,
    calibration_origins=CAL_ORIGINS,
    calibration_candidate_step=CAL_STEP,
    passage_candidate_step=PASS_STEP
  )
  if (!inherits(stage,'page_m1_v2_stage')) stop('Stage construction failed.')
  assert_fold_isolation(test,inp,stage)
  train_seasons <- inp$train_seasons; train_truth <- inp$train_truth; held <- inp$held

  regimes <- unique(panel[panel$season %in% train_seasons,c('season','denominator_regime')])
  sel <- stage$passage_policy$selected[1,]
  pe <- stage$passage_policy$evaluation
  pe <- pe[pe$policy_id==sel$policy_id,,drop=FALSE]
  pe$test_season <- test; pe$activation_shift <- shift

  inner <- stage$calibrator$inner_predictions
  inner$test_season <- test
  inner$activation_shift <- shift
  inner$inner_asof_boundary <- inner$origin_week+1
  peak_map <- setNames(train_truth$peak_week_decimal,train_truth$season)
  inner$inner_truth_peak <- unname(peak_map[inner$season])
  inner$inner_post_peak_origin <- inner$inner_asof_boundary>inner$inner_truth_peak

  stage_row <- data.frame(
    test_season=test,activation_shift=shift,n_train=length(train_seasons),training_seasons=paste(train_seasons,collapse=';'),
    low_support=(test==LOW_SUPPORT_SEASON),stage_artifact_id=stage$artifact_id,
    library_hash=stage$library$provenance$library_hash,calibration_offset_week=stage$calibrator$offset_week,
    calibration_mean_signed_bias=stage$calibrator$mean_signed_bias,
    calibration_inner_rows=nrow(inner),calibration_post_peak_inner_rows=sum(inner$inner_post_peak_origin),
    passage_high=sel$high_threshold,passage_low=sel$low_threshold,
    passage_drop=sel$drop_fraction,passage_min_post=sel$min_post_activation,
    passage_fast_drop=sel$fast_drop_fraction,
    n_proxy_regime=sum(regimes$denominator_regime=='historical_shared_flu_test_proxy'),
    n_type_specific_regime=sum(regimes$denominator_regime!='historical_shared_flu_test_proxy'),
    fold_isolation_asserted=TRUE,fold_input_digest=inp$digest,
    activation_semantics='exploratory_transferred_A_rule_global_selection',
    stringsAsFactors=FALSE
  )

  leave22 <- NULL
  if (primary && shift==0L && '2022-23' %in% inner$season) {
    di <- inner[inner$season!='2022-23',]
    di$wbal <- ave(di$weight_early,di$season,FUN=function(v)v/sum(v))
    alt_bias <- sum(di$wbal*di$signed_error)/sum(di$wbal)
    leave22 <- data.frame(test_season=test,primary_offset=stage$calibrator$offset_week,exclude_2022_offset=-alt_bias,delta_offset=(-alt_bias)-stage$calibrator$offset_week,diagnostic_only=TRUE,stringsAsFactors=FALSE)
  }

  act_dec <- truth$B_activity_weekF[truth$season==test]+shift
  act_int <- ceiling(act_dec)
  T <- truth$B_peak_weekF[truth$season==test]
  if (!all(is.finite(c(act_dec,act_int,T)))) stop('Test B timing missing for ',test)
  if (act_int!=truth$B_activity_integer[truth$season==test]+shift) stop('Shifted activation integer mismatch at ',test)
  test_regime <- unique(panel$denominator_regime[panel$season==test])
  if (length(test_regime)!=1L) stop('Test season has multiple denominator regimes.')

  # Regenerate the scored origin path from (shifted) activation to the last pre-peak origin.
  origins <- if (act_int<=origin_max_prepeak(T)) seq.int(act_int,origin_max_prepeak(T)) else integer(0)
  if (shift==0L && !identical(as.numeric(origins),as.numeric(sort(b0$origin_weekF[b0$season==test])))) stop('Primary origin path differs from stored B0 origins at ',test)

  pred_rows <- list(); leak_rows <- list(); b0_rows <- list(); fails <- list()
  for (o in origins) {
    fit <- tryCatch(m1_v2_peak_posterior(stage$library,held,act_dec,o,candidate_step=SCORED_STEP,max_future_weeks=B_MAX_FUTURE),error=function(e)e)
    if (inherits(fit,'error')) { fails[[length(fails)+1L]] <- failure_row(test,shift,o,'peak_posterior',fit); next }
    cal <- tryCatch(m1_v2_apply_bias_calibration(fit,stage$calibrator),error=function(e)e)
    if (inherits(cal,'error')) { fails[[length(fails)+1L]] <- failure_row(test,shift,o,'calibration',cal); next }
    w <- metric_weight(o,act_int)
    if (shift==0L) {
      stored <- b0[b0$season==test & b0$origin_weekF==o,]
      if (nrow(stored)!=1L) stop('B0 stored origin mismatch.')
      b0_rows[[length(b0_rows)+1L]] <- data.frame(season=test,origin_weekF=o,
        max_abs_diff_summary=max(abs(c(fit$summary$peak_mean-stored$pred_peak_mean,fit$summary$peak_median-stored$pred_peak_median,
                                       fit$summary$peak_map-stored$pred_peak_map,fit$summary$peak_q05-stored$q05,fit$summary$peak_q95-stored$q95))),
        abs_diff_weight_early=abs(w-stored$weight_early),stringsAsFactors=FALSE)
    }
    pred_rows[[length(pred_rows)+1L]] <- data.frame(
      season=test,activation_shift=shift,origin_weekF=o,denominator_regime=test_regime,low_support=(test==LOW_SUPPORT_SEASON),
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
      weight_early=w,stringsAsFactors=FALSE
    )
    if (primary && shift==0L) {
      chk <- tryCatch({
        held2 <- perturb_future(held,o)
        fit2 <- m1_v2_peak_posterior(stage$library,held2,act_dec,o,candidate_step=SCORED_STEP,max_future_weeks=B_MAX_FUTURE)
        cal2 <- m1_v2_apply_bias_calibration(fit2,stage$calibrator)
        max(abs(c(fit2$summary$peak_mean-fit$summary$peak_mean,cal2$peak_mean_calibrated-cal$peak_mean_calibrated)))<1e-12
      },error=function(e)e)
      if (inherits(chk,'error')) { fails[[length(fails)+1L]] <- failure_row(test,shift,o,'prediction_future_check',chk); chk <- FALSE }
      leak_rows[[length(leak_rows)+1L]] <- data.frame(season=test,origin_weekF=o,prediction_future_invariant=isTRUE(chk),stringsAsFactors=FALSE)
    }
  }

  pr <- tryCatch(replay_passage(test,shift,stage,held,act_dec,T,check_future=(primary && shift==0L)),error=function(e)e)
  if (inherits(pr,'error')) {
    fails[[length(fails)+1L]] <- failure_row(test,shift,NA_real_,'passage_replay',pr)
    pr <- list(row=NULL,failures=list())
  }
  fails <- c(fails,pr$failures)

  list(test=test,shift=shift,stage_row=stage_row,inner=inner,policy_eval=pe,leave22=leave22,
       pred=if(length(pred_rows)) do.call(rbind,pred_rows) else NULL,
       leak=if(length(leak_rows)) do.call(rbind,leak_rows) else NULL,
       b0_check=if(length(b0_rows)) do.call(rbind,b0_rows) else NULL,
       passage=pr$row,failures=if(length(fails)) do.call(rbind,fails) else NULL,
       n_expected_origins=length(origins))
}

# 2018-19 exclusion perturbation: a materially different 2018-19 B series.
B_pert <- B
i1819 <- B_pert$season==INACTIVE_SEASON
if (!any(i1819)) stop('2018-19 rows missing from B panel.')
B_pert$y[i1819] <- pmin(B_pert$N[i1819],round(B_pert$y[i1819]*3)+25)
storage.mode(B_pert$y) <- storage.mode(B$y)
B_pert$p[i1819] <- B_pert$y[i1819]/B_pert$N[i1819]
if (identical(digest::digest(B[i1819,],algo='sha256'),digest::digest(B_pert[i1819,],algo='sha256'))) stop('2018-19 perturbation is a no-op.')
if (!identical(B[!i1819,],B_pert[!i1819,])) stop('Perturbation touched non-2018-19 rows.')
post1819 <- test_seasons[season_start(test_seasons)>season_start(INACTIVE_SEASON)]

jobs <- c(
  lapply(test_seasons,function(s) list(test=s,shift=0L,perturbed=FALSE)),
  unlist(lapply(ACTIVATION_SHIFTS,function(sh) lapply(test_seasons,function(s) list(test=s,shift=sh,perturbed=FALSE))),recursive=FALSE),
  lapply(post1819,function(s) list(test=s,shift=0L,perturbed=TRUE))
)
cat('Running',length(jobs),'fold jobs on',N_CORES,'cores\n')
res <- parallel::mclapply(jobs,function(j) tryCatch(
  run_fold(j$test,j$shift,if(j$perturbed) B_pert else B,primary=!j$perturbed),
  error=function(e) structure(list(message=conditionMessage(e)),class='fold_error')),
  mc.cores=N_CORES,mc.preschedule=FALSE)
job_err <- vapply(seq_along(res),function(i) inherits(res[[i]],'fold_error') || inherits(res[[i]],'try-error') || is.null(res[[i]]),logical(1))
if (any(job_err)) {
  msg <- vapply(res[job_err],function(r) if(is.list(r) && !is.null(r$message)) r$message else paste(as.character(r),collapse=' '),character(1))
  stop('Fold job(s) failed (assertion or stage construction):\n',paste(vapply(jobs[job_err],function(j) paste0(j$test,'/shift',j$shift,if(j$perturbed)'/perturbed'),character(1)),msg,sep=': ',collapse='\n'))
}
is_primary <- vapply(jobs,function(j) j$shift==0L && !j$perturbed,logical(1))
is_shift <- vapply(jobs,function(j) j$shift!=0L,logical(1))
is_pert <- vapply(jobs,function(j) j$perturbed,logical(1))
bind <- function(rs,field) { z <- Filter(Negate(is.null),lapply(rs,`[[`,field)); if(length(z)) do.call(rbind,z) else data.frame() }

prim <- res[is_primary]; shf <- res[is_shift]; prt <- res[is_pert]
pred <- bind(prim,'pred')
stages <- bind(c(prim,shf),'stage_row')
inner_all <- bind(c(prim,shf),'inner')
passage <- bind(prim,'passage')
leak <- bind(prim,'leak')
b0_check <- bind(prim,'b0_check')
leave22 <- bind(prim,'leave22')
policy_eval <- bind(c(prim,shf),'policy_eval')
sens_pred <- bind(shf,'pred')
sens_passage <- bind(shf,'passage')
failures <- bind(c(prim,shf,prt),'failures')
if (!nrow(failures)) failures <- data.frame(season=character(0),activation_shift=integer(0),origin_weekF=numeric(0),stage=character(0),message=character(0))

# Library is activation-independent; shifted stages must reuse the primary library.
lib_by <- tapply(stages$library_hash,stages$test_season,function(v) length(unique(v))==1L)
if (!all(lib_by)) stop('Activation shift changed the fitted library.')

inner_post_peak <- inner_all[inner_all$inner_post_peak_origin,]

per_season_metrics <- function(pr) {
  out <- do.call(rbind,lapply(split(pr,pr$season),function(z) data.frame(
    season=z$season[1],denominator_regime=z$denominator_regime[1],low_support=z$low_support[1],n_origins=nrow(z),
    raw_mae=mean(z$raw_abs_error),calibrated_mae=mean(z$calibrated_abs_error),
    raw_rmse=sqrt(mean(z$raw_error^2)),calibrated_rmse=sqrt(mean(z$calibrated_error^2)),
    raw_bias=mean(z$raw_error),calibrated_bias=mean(z$calibrated_error),
    raw_early_weighted_mae=sum(z$weight_early*z$raw_abs_error)/sum(z$weight_early),
    calibrated_early_weighted_mae=sum(z$weight_early*z$calibrated_abs_error)/sum(z$weight_early),
    raw_coverage90=mean(z$raw_covered90),calibrated_coverage90=mean(z$calibrated_covered90),
    stringsAsFactors=FALSE)))
  out[order(season_start(out$season)),]
}
summarize_set <- function(ps,label) data.frame(
  subset=label,n_seasons=nrow(ps),n_origins=sum(ps$n_origins),
  raw_season_balanced_mae=mean(ps$raw_mae),calibrated_season_balanced_mae=mean(ps$calibrated_mae),
  raw_early_weighted_mae=mean(ps$raw_early_weighted_mae),calibrated_early_weighted_mae=mean(ps$calibrated_early_weighted_mae),
  raw_rmse=mean(ps$raw_rmse),calibrated_rmse=mean(ps$calibrated_rmse),
  raw_bias=mean(ps$raw_bias),calibrated_bias=mean(ps$calibrated_bias),
  raw_coverage90=mean(ps$raw_coverage90),calibrated_coverage90=mean(ps$calibrated_coverage90),
  raw_worst_season_mae=max(ps$raw_mae),calibrated_worst_season_mae=max(ps$calibrated_mae),
  n_seasons_worse=sum(ps$calibrated_mae>ps$raw_mae),stringsAsFactors=FALSE)
passage_summary <- function(ps,label) data.frame(
  subset=label,n_seasons=nrow(ps),n_replay_completed=sum(ps$replay_completed),n_false_early=sum(ps$false_early),
  early_weeks_total=sum(ps$early_weeks),max_early_weeks=max(ps$early_weeks),confirmed_by_peak2=sum(ps$confirmed_by_peak2),
  mean_delay=mean(ifelse(is.finite(ps$delay),ps$delay,PASSAGE_LATE_WEEKS+1)),median_delay=median(ps$delay,na.rm=TRUE),
  stringsAsFactors=FALSE)

per_season <- per_season_metrics(pred)
if (!setequal(per_season$season,test_seasons)) stop('Primary per-season metrics missing a scored season.')
summary_primary <- summarize_set(per_season,'primary_all_six_eligible')
summary_no_low <- summarize_set(per_season[!per_season$low_support,],'descriptive_only_exclude_2017-18_low_support')
summary <- rbind(summary_primary,summary_no_low)
summary$decision_role <- c('primary_decision','descriptive_only_no_decision_weight')
by_regime <- do.call(rbind,lapply(split(per_season,per_season$denominator_regime),function(z) summarize_set(z,z$denominator_regime[1])))

pass_summary <- passage_summary(passage,'primary_all_six_eligible')
pass_summary$all_future_invariant <- all(passage$future_invariant)

sens_per_season <- do.call(rbind,lapply(split(sens_pred,sens_pred$activation_shift),function(z) cbind(activation_shift=z$activation_shift[1],per_season_metrics(z))))
sens_summary <- do.call(rbind,lapply(ACTIVATION_SHIFTS,function(sh) {
  ps <- sens_per_season[sens_per_season$activation_shift==sh,]
  pz <- sens_passage[sens_passage$activation_shift==sh,]
  cbind(activation_shift=sh,summarize_set(ps,'all_six_eligible'),
        passage_summary(pz,'all_six_eligible')[,c('n_replay_completed','n_false_early','early_weeks_total','max_early_weeks','confirmed_by_peak2','mean_delay')])
}))
sens_complete <- nrow(sens_passage)==length(ACTIVATION_SHIFTS)*length(test_seasons) && all(sens_passage$replay_completed) &&
  all(vapply(ACTIVATION_SHIFTS,function(sh) setequal(sens_per_season$season[sens_per_season$activation_shift==sh],test_seasons),logical(1)))

# 2018-19 exclusion perturbation evaluation.
pert_rows <- do.call(rbind,lapply(test_seasons,function(s) {
  d0 <- fold_inputs(s,B,0L)$digest; d1 <- fold_inputs(s,B_pert,0L)$digest
  r0 <- prim[[which(vapply(prim,`[[`,character(1),'test')==s)]]
  j <- which(vapply(prt,`[[`,character(1),'test')==s)
  rebuilt <- length(j)==1L
  same_stage <- same_pred <- same_passage <- NA
  if (rebuilt) {
    r1 <- prt[[j]]
    cols <- c('origin_weekF','raw_mean','calibrated_mean','raw_q05','raw_q95','calibrated_q05','calibrated_q95','raw_abs_error','calibrated_abs_error')
    pcols <- c('confirm_origin','branch','false_early','early_weeks','delay')
    same_stage <- identical(r0$stage_row$stage_artifact_id,r1$stage_row$stage_artifact_id)
    same_pred <- !is.null(r1$pred) && nrow(r0$pred)==nrow(r1$pred) && isTRUE(all.equal(r0$pred[,cols],r1$pred[,cols],tolerance=0,check.attributes=FALSE))
    same_passage <- !is.null(r1$passage) && identical(r0$passage[,pcols],r1$passage[,pcols])
  }
  data.frame(test_season=s,inactive_in_training=INACTIVE_SEASON %in% fold_train_seasons(s),
             fold_input_digest_unchanged=identical(d0,d1),full_rebuild=rebuilt,
             stage_artifact_id_unchanged=same_stage,predictions_errors_unchanged=same_pred,passage_unchanged=same_passage,
             pass=identical(d0,d1) && !(INACTIVE_SEASON %in% fold_train_seasons(s)) && (!rebuilt || (isTRUE(same_stage) && isTRUE(same_pred) && isTRUE(same_passage))),
             stringsAsFactors=FALSE)
}))
pert_rows$perturbation <- sprintf('2018-19 y_B -> min(N_B, round(3*y_B)+25) across %d weeks',sum(i1819))

# Explicit inactive/no-event runtime rows.
inactive <- truth[!truth$B_activity_detected | !is.finite(truth$B_peak_weekF),c('season','B_activity_status','B_peak_status')]
inactive$activity_detected <- FALSE
inactive$M1_B_state <- 'inactive_no_meaningful_activity'
inactive$timing_scored <- FALSE
inactive$in_any_training_stage <- inactive$season %in% unlist(strsplit(stages$training_seasons,';',fixed=TRUE))
inactive$exclusion_perturbation_pass <- all(pert_rows$pass)
if (any(inactive$in_any_training_stage)) stop('Inactive season leaked into a meaningful-B training stage.')

b0_exact <- nrow(b0_check)==nrow(b0) && all(b0_check$max_abs_diff_summary<=1e-8)
b0_weights <- nrow(b0_check)==nrow(b0) && all(b0_check$abs_diff_weight_early<=1e-12)
primary_complete <- nrow(pred)==nrow(b0) && nrow(passage)==length(test_seasons) && all(passage$replay_completed)

ss <- summary_primary
criteria <- data.frame(
  criterion=c('calibrated_mae_le_raw','calibrated_early_weighted_mae_le_raw','worst_season_mae_delta_le_0.5',
              'n_seasons_worse_le_2','calibrated_coverage90_ge_0.70','primary_passage_false_early_zero',
              'activation_minus1_passage_false_early_zero','activation_plus1_passage_false_early_zero',
              'activation_sensitivity_complete','prediction_future_integrity_all_pass','passage_future_integrity_all_pass',
              'inactive_2018_19_exclusion_perturbation_pass','raw_B0_exact_recomputation','raw_B0_early_weights_match',
              'primary_scoring_complete','no_unexpected_failures'),
  value=c(ss$calibrated_season_balanced_mae-ss$raw_season_balanced_mae,ss$calibrated_early_weighted_mae-ss$raw_early_weighted_mae,
          ss$calibrated_worst_season_mae-ss$raw_worst_season_mae,ss$n_seasons_worse,ss$calibrated_coverage90,pass_summary$n_false_early,
          sum(sens_passage$false_early[sens_passage$activation_shift==-1]),sum(sens_passage$false_early[sens_passage$activation_shift==1]),
          sens_complete,mean(leak$prediction_future_invariant),mean(passage$future_invariant),
          mean(pert_rows$pass),max(b0_check$max_abs_diff_summary),max(b0_check$abs_diff_weight_early),primary_complete,nrow(failures)),
  pass=c(ss$calibrated_season_balanced_mae<=ss$raw_season_balanced_mae,
         ss$calibrated_early_weighted_mae<=ss$raw_early_weighted_mae,
         ss$calibrated_worst_season_mae<=ss$raw_worst_season_mae+.5,
         ss$n_seasons_worse<=2,
         ss$calibrated_coverage90>=.70,
         pass_summary$n_false_early==0,
         !any(sens_passage$false_early[sens_passage$activation_shift==-1]),
         !any(sens_passage$false_early[sens_passage$activation_shift==1]),
         sens_complete,
         nrow(leak)==nrow(b0) && all(leak$prediction_future_invariant),
         all(passage$future_invariant %in% TRUE),
         all(pert_rows$pass),
         b0_exact,b0_weights,primary_complete,
         nrow(failures)==0L),
  stringsAsFactors=FALSE)
criteria$subset <- 'primary_all_six_eligible'
historically_promising <- all(criteria$pass)
verdict <- data.frame(
  historically_promising=historically_promising,
  n_criteria=nrow(criteria),n_failed=sum(!criteria$pass),
  failed_criteria=paste(criteria$criterion[!criteria$pass],collapse=';'),
  decision=if(historically_promising) 'conditional_research_pass_requires_activation_governance' else 'retain_raw_M1_B0_stop_scalar_calibration',
  governed=FALSE,
  note='Primary decision uses all six eligible seasons; exclude-2017-18 subset is descriptive only. Not governed: B activation rule/window and amplitude support selected with full archive.',
  stringsAsFactors=FALSE)

# v1 first look must be byte-identical after the run.
v1_hash_end <- vapply(c(v1_files,V1_SCRIPT),sha256_file,character(1))
if (!identical(v1_hash_start,v1_hash_end) || !setequal(v1_files,list.files(V1_DIR,full.names=TRUE))) stop('v1 first-look artifacts changed during the run.')

if (out_nonempty()) stop('Output directory became non-empty during the run: ',OUT)
dir.create(OUT,recursive=TRUE,showWarnings=FALSE)
wcsv <- function(x,f) write.csv(x,file.path(OUT,f),row.names=FALSE)
wcsv(folds,'fold_ledger.csv')
wcsv(stages,'stage_ledger.csv')
wcsv(inner_all,'calibrator_inner_predictions.csv')
wcsv(inner_post_peak,'calibrator_inner_post_peak_rows.csv')
wcsv(pred,'per_origin_predictions.csv')
wcsv(per_season,'per_season_metrics.csv')
wcsv(summary,'summary_metrics.csv')
wcsv(summary_no_low,'summary_excluding_low_support_descriptive.csv')
wcsv(by_regime,'metrics_by_denominator_regime.csv')
wcsv(passage,'passage_by_season.csv')
wcsv(pass_summary,'passage_summary.csv')
wcsv(policy_eval,'selected_passage_policy_inner_evaluation.csv')
wcsv(leak,'future_perturbation_checks.csv')
wcsv(b0_check,'raw_B0_recomputation_checks.csv')
wcsv(sens_pred,'activation_sensitivity_per_origin.csv')
wcsv(sens_per_season,'activation_sensitivity_per_season.csv')
wcsv(sens_passage,'activation_sensitivity_passage.csv')
wcsv(sens_summary,'activation_sensitivity_summary.csv')
wcsv(leave22,'calibrator_leave_2022_diagnostic.csv')
wcsv(inactive,'inactive_no_event_seasons.csv')
wcsv(pert_rows,'inactive_exclusion_perturbation_check.csv')
wcsv(failures,'failures.csv')
wcsv(criteria,'predeclared_threshold_evaluation.csv')
wcsv(verdict,'overall_verdict.csv')

manifest_paths <- c(PANEL_PATH,TIMING_PATH,TIMING_META,B_DETECT_PATH,B0_PATH,B0_CONFIG_PATH,FOLD_PATH)
manifest <- rbind(
  data.frame(role=c('canonical_panel','timing_contract','timing_contract_metadata','B_activity_detector','raw_B0_baseline','raw_B0_config','fold_ledger'),
             path=manifest_paths,sha256=vapply(manifest_paths,sha256_file,character(1)),stringsAsFactors=FALSE),
  data.frame(role=c(rep('v1_first_look_result',length(v1_files)),'v1_first_look_script'),path=names(v1_hash_end),sha256=unname(v1_hash_end),stringsAsFactors=FALSE),
  data.frame(role='v2_script',path='scripts/v3_benchmark_m1_b_calibrated_chronological_v2.R',sha256=sha256_file('scripts/v3_benchmark_m1_b_calibrated_chronological_v2.R'),stringsAsFactors=FALSE))
wcsv(manifest,'source_manifest.csv')

config <- data.frame(
  key=c('version','status','supersedes','primary_decision_set','descriptive_subset','activation_limitation','amplitude_grid',
        'calibration_origins','calibration_step','passage_step','scored_step','scored_max_future_weeks','passage_max_future_weeks',
        'calibrator_inner_max_future_weeks_frozen_default','passage_late_weeks','min_train_seasons','low_support_season','inactive_season',
        'activation_shifts','activation_shift_semantics'),
  value=c('v3-m1-b-calibrated-chronological-v2','conditional_research_not_governed','v3-m1-b-calibrated-chronological-v1 (first look, preserved)',
          'all six eligible B seasons','exclude 2017-18 low support (descriptive only)','global B activity rule selected with full archive','0.005:0.005:0.25',
          CAL_ORIGINS,CAL_STEP,PASS_STEP,SCORED_STEP,B_MAX_FUTURE,PASSAGE_MAX_FUTURE,CALIBRATOR_MAX_FUTURE,PASSAGE_LATE_WEEKS,MIN_TRAIN,LOW_SUPPORT_SEASON,INACTIVE_SEASON,
          paste(ACTIVATION_SHIFTS,collapse=';'),'training and test activation shifted together; stage, calibrator, passage policy, scored path and passage replay rebuilt'),
  stringsAsFactors=FALSE)
wcsv(config,'benchmark_config.csv')

cat('Calibrated chronological M1-B benchmark v2 complete\n')
print(summary,row.names=FALSE,digits=5)
cat('\nPassage summary\n'); print(pass_summary,row.names=FALSE,digits=5)
cat('\nActivation sensitivity\n'); print(sens_summary[,c('activation_shift','calibrated_season_balanced_mae','raw_season_balanced_mae','n_replay_completed','n_false_early')],row.names=FALSE,digits=5)
cat('\nPredeclared criteria\n'); print(criteria,row.names=FALSE,digits=5)
cat('\nhistorically_promising =',historically_promising,'\n')
