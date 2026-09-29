#!/usr/bin/env Rscript

# Activation-robust M1-B passage hardening benchmark (second-look historical
# robustness study). Implements docs/v3-m1-b-passage-robustness-plan-2026-09-25.md.
# Raw M1-B0 peak mechanics are frozen; only passage-policy selection changes.
# Frozen PAGe/R code is sourced unchanged; existing artifacts are read only.

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

PLAN_PATH <- 'docs/v3-m1-b-passage-robustness-plan-2026-09-25.md'
SCRIPT_PATH <- 'scripts/v3_benchmark_m1_b_passage_robustness_v1.R'
PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
TIMING_META <- 'artifacts/v3-joint-timing-contract-v2/contract_metadata.csv'
B_DETECT_PATH <- 'artifacts/v3-a-rule-transfer-to-b-v1/B_window8_40_detection.rds'
M0_PARAMS_PATH <- 'artifacts/v3-a-rule-transfer-to-b-v1/A_aggregated_params.rds'
B0_PATH <- 'artifacts/v3-m1-chronological-baselines-v1/per_origin_predictions.csv'
FOLD_PATH <- 'artifacts/v3-m1-chronological-baselines-v1/fold_ledger.csv'
V2_DIR <- 'artifacts/v3-m1-b-calibrated-chronological-v2'
V2_SCRIPT <- 'scripts/v3_benchmark_m1_b_calibrated_chronological_v2.R'
V2_PASSAGE <- file.path(V2_DIR,'passage_by_season.csv')
V2_SENS <- file.path(V2_DIR,'activation_sensitivity_passage.csv')
OUT <- 'artifacts/v3-m1-b-passage-robustness-v1'

if (dir.exists(OUT) && length(list.files(OUT,all.files=TRUE,no..=TRUE))>0L) stop('Output directory already exists and is non-empty: ',OUT)

B_AMP_GRID <- seq(.005,.25,by=.005)
CAL_ORIGINS <- 4L
CAL_STEP <- .2
PASS_STEP <- .2
PASSAGE_MAX_FUTURE <- 12
PASSAGE_LATE_WEEKS <- 6L
UNCONFIRMED_DELAY <- 7
MIN_TRAIN <- 4L
INACTIVE_SEASON <- '2018-19'
B_WINDOW <- c(8L,40L)
INNER_SHIFTS <- c(-1L,0L,1L)
OUTER_SHIFTS <- c(-1L,0L,1L)
TRUTH_PERTURB_WEEKS <- 3
TIMING_STATES <- c('inactive_no_timing_event','active_unconfirmed','confirmed')
N_CORES <- as.integer(Sys.getenv('PAGE_BENCH_CORES',unset='8'))

if (!identical(PASSAGE_MAX_FUTURE,eval(formals(m1_v2_passage_posterior)$max_future_weeks))) stop('Frozen passage max_future_weeks default changed.')

# Predeclared 1500-policy grid.
POLICY_AXES <- list(
  high_threshold=c(.95,.975,.99),
  low_threshold=c(.10,.20,.30,.40,.50),
  drop_fraction=c(.03,.05,.08,.10,.12),
  fast_drop_fraction=c(0,.03,.05,.08,.10),
  min_post_activation=3:6
)
GRID <- do.call(expand.grid,c(POLICY_AXES,list(KEEP.OUT.ATTRS=FALSE,stringsAsFactors=FALSE)))
GRID$policy_id <- seq_len(nrow(GRID))
if (nrow(GRID)!=1500L) stop('Policy grid is not 1500 candidates.')
# Frozen fit_m1_v2_passage_policy() defaults used by build_m1_v2_timing().
FROZEN_SUB <- list(high=.95,low=c(.10,.20,.30,.40),drop=c(.03,.05,.08,.10),fast=0,min_post=3:4)

sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))
perturb_future <- function(d,o) {
  fut <- d$weekF>o
  if (any(fut)) { d$y[fut] <- pmin(d$N[fut],d$y[fut]+7); d$p[fut] <- d$y[fut]/d$N[fut] }
  d
}
identical_na <- function(a,b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a==b)
hash_dir <- function(paths) vapply(paths,sha256_file,character(1))
failure_row <- function(test,shift,o,stage,msg) data.frame(season=test,activation_shift=shift,origin_weekF=o,stage=stage,message=msg,stringsAsFactors=FALSE)

# Record plan and frozen-source hashes before any benchmark computation.
plan_sha_start <- sha256_file(PLAN_PATH)
page_r_files <- sort(list.files('PAGe/R',full.names=TRUE,recursive=TRUE))
page_r_hash_start <- hash_dir(page_r_files)
existing_files <- sort(c(list.files(V2_DIR,full.names=TRUE,recursive=TRUE),V2_SCRIPT,PANEL_PATH,TIMING_PATH,TIMING_META,B_DETECT_PATH,M0_PARAMS_PATH,B0_PATH,FOLD_PATH))
existing_hash_start <- hash_dir(existing_files)
page_r_git_clean_start <- identical(system2('git',c('diff','--quiet','HEAD','--','PAGe/R')),0L)

panel <- read.csv(PANEL_PATH,check.names=FALSE)
truth0 <- read.csv(TIMING_PATH,check.names=FALSE)
b0_all <- read.csv(B0_PATH,check.names=FALSE)
folds <- read.csv(FOLD_PATH,check.names=FALSE)
v2_pass <- read.csv(V2_PASSAGE,check.names=FALSE)
v2_sens <- read.csv(V2_SENS,check.names=FALSE)

B <- data.frame(season=as.character(panel$season),weekF=panel$weekF,y=panel$y_B,N=panel$N_B,p=panel$p_B)
B <- B[order(season_start(B$season),B$weekF),]
rownames(B) <- NULL
b0 <- b0_all[b0_all$type=='B',]
meaningful <- as.character(truth0$season[is.finite(truth0$B_peak_weekF) & truth0$B_activity_detected])

contract_sha <- sha256_file(TIMING_PATH)
detect_sha <- sha256_file(B_DETECT_PATH)

tm <- truth0[truth0$season %in% meaningful,]
if (any(tm$B_peak_status!='retrospective_peak_truth')) stop('Meaningful B season lacks retrospective peak truth status.')
if (any(!is.finite(tm$B_activity_weekF)) || any(tm$B_activity_integer!=ceiling(tm$B_activity_weekF))) stop('B activity integer is not ceiling(B activity decimal).')
if (any(tm$B_activity_weekF>=tm$B_peak_weekF)) stop('B activation is not before B peak truth.')
ti <- truth0[truth0$season==INACTIVE_SEASON,]
if (nrow(ti)!=1L || isTRUE(ti$B_activity_detected) || is.finite(ti$B_peak_weekF) || ti$B_peak_status!='no_meaningful_peak') stop('Inactive-season timing semantics changed.')
if (INACTIVE_SEASON %in% meaningful) stop('Inactive season is marked meaningful.')

# Activation adapter identical to v2 (shift 0 only reaches the stage builder).
make_b_activation_adapter <- function(seasons,shift=0L,truth=truth0) {
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

test_seasons <- unique(as.character(b0$season))
test_seasons <- test_seasons[order(season_start(test_seasons))]
if (!setequal(test_seasons,folds$test_season[folds$eligible_B])) stop('B0 seasons differ from eligible-B fold ledger.')
if (INACTIVE_SEASON %in% test_seasons) stop('Inactive season is a scored test season.')
if (!setequal(test_seasons,v2_pass$season)) stop('v2 passage rows differ from test seasons.')

fold_train_seasons <- function(test) {
  fold <- folds[folds$test_season==test,]
  if (nrow(fold)!=1L) stop('Fold missing for ',test)
  prior <- strsplit(fold$training_seasons,';',fixed=TRUE)[[1]]
  prior[prior %in% meaningful]
}

fold_inputs <- function(test,Bdata,truth) {
  train_seasons <- fold_train_seasons(test)
  trainB <- Bdata[Bdata$season %in% train_seasons,]
  train_truth <- truth[truth$season %in% train_seasons,c('season','B_peak_weekF')]
  train_truth <- train_truth[match(train_seasons,train_truth$season),]
  names(train_truth)[2] <- 'peak_week_decimal'
  rownames(trainB) <- NULL; rownames(train_truth) <- NULL
  held <- Bdata[Bdata$season==test,]
  rownames(held) <- NULL
  list(train_seasons=train_seasons,trainB=trainB,train_truth=train_truth,
       act_train=make_b_activation_adapter(train_seasons,0L,truth),held=held,
       digest=digest::digest(list(trainB,train_truth,held),algo='sha256'))
}

assert_fold_isolation <- function(test,inp,stage) {
  tr <- inp$train_seasons
  if (length(tr)<MIN_TRAIN) stop('Insufficient meaningful-B training seasons for ',test)
  if (test %in% tr) stop('Test season in training set: ',test)
  if (any(season_start(tr)>=season_start(test))) stop('Chronological fold leakage at ',test)
  if (!all(tr %in% meaningful) || INACTIVE_SEASON %in% tr) stop('Non-meaningful B season in training at ',test)
  if (!setequal(unique(inp$trainB$season),tr)) stop('Training data seasons differ from fold training set at ',test)
  if (!identical(unique(inp$held$season),test)) stop('Held-out data contains other seasons at ',test)
  if (!setequal(stage$training_seasons,tr) || !setequal(stage$calibrator$training_seasons,tr)) stop('Stage training universe differs from fold at ',test)
  if (!all(stage$passage_policy$evaluation$season %in% tr)) stop('Passage-policy evaluation outside fold at ',test)
  if (!identical(stage$passage_policy$library_hash,stage$library$provenance$library_hash)) stop('Passage/library hash mismatch at ',test)
  if (!isTRUE(all.equal(stage$library$config$amplitude_grid,B_AMP_GRID,tolerance=0))) stop('Stage amplitude grid differs from 0.005:0.005:0.25 at ',test)
  TRUE
}

# Inner cross-fitted passage histories under activation shifts -1/0/+1. Feature
# construction mirrors fit_m1_v2_passage_policy(); shifted activations are
# confined to these inner training histories.
build_inner_histories <- function(test,stage,inp,truth) {
  d <- prepare_surveillance_data(prepare_surveillance_data(inp$trainB))
  if (digest::digest(d,algo='sha256')!=stage$library$provenance$data_hash) stop('Inner data differs from library training data at ',test)
  seasons <- stage$library$training_seasons
  cfg <- stage$library$config
  pt <- inp$train_truth[match(seasons,inp$train_truth$season),]
  rows <- list(); fails <- list(); iso <- list()
  for (heldout in seasons) {
    inner_seasons <- setdiff(seasons,heldout)
    lib <- fit_m1_v2_library(d[d$season %in% inner_seasons,,drop=FALSE],pt[pt$season %in% inner_seasons,,drop=FALSE],
      k=cfg$k,grid_step=cfg$grid_step,tau_step=cfg$tau_step,amplitude_grid=cfg$amplitude_grid)
    if (heldout %in% lib$training_seasons || !setequal(lib$training_seasons,inner_seasons) || test %in% lib$training_seasons) stop('Inner fold isolation violated at ',test,'/',heldout)
    if (!isTRUE(all.equal(lib$config$amplitude_grid,B_AMP_GRID,tolerance=0))) stop('Inner amplitude grid changed at ',test,'/',heldout)
    iso[[length(iso)+1L]] <- data.frame(test_season=test,inner_heldout=heldout,inner_library_seasons=paste(lib$training_seasons,collapse=';'),inner_isolated=TRUE,stringsAsFactors=FALSE)
    Tpk <- pt$peak_week_decimal[pt$season==heldout]
    tc <- ceiling(Tpk)-1
    held <- d[d$season==heldout,,drop=FALSE]
    last_origin <- min(max(held$weekF),tc+PASSAGE_LATE_WEEKS)
    for (sh in INNER_SHIFTS) {
      a_int <- truth$B_activity_integer[truth$season==heldout]+sh
      a_dec <- truth$B_activity_weekF[truth$season==heldout]+sh
      n0 <- length(rows)
      if (a_int<=last_origin) for (origin in seq(a_int,last_origin,by=1)) {
        prefix <- held[held$weekF<=origin,,drop=FALSE]
        pp <- tryCatch(m1_v2_passage_posterior(lib,prefix,activation_week=a_dec,origin_week=origin,candidate_step=PASS_STEP,max_future_weeks=PASSAGE_MAX_FUTURE),error=function(e)e)
        if (inherits(pp,'error')) { fails[[length(fails)+1L]] <- failure_row(test,sh,origin,paste0('inner_history:',heldout),conditionMessage(pp)); next }
        post_act <- prefix[prefix$weekF>=ceiling(a_dec),,drop=FALSE]
        post_act <- post_act[order(post_act$weekF),,drop=FALSE]
        immediate <- nrow(post_act)>=2L && diff(tail(post_act$weekF,2L))==1 && tail(post_act$p,1L)<post_act$p[nrow(post_act)-1L]
        two_down <- nrow(post_act)>=3L && all(diff(tail(post_act$weekF,3L))==1) && all(diff(tail(post_act$p,3L))<0)
        drop <- if (nrow(post_act)) 1-tail(post_act$p,1L)/max(post_act$p) else NA_real_
        rows[[length(rows)+1L]] <- data.frame(test_season=test,activation_shift=sh,season=heldout,origin_week=origin,
          activation_origin_week=a_int,activation_week_decimal=a_dec,truth_confirm=tc,prob_peak_passed=pp$prob_peak_passed,
          immediate_decline=immediate,sustained_two_week_decline=two_down,drop_from_post_activation_max=drop,stringsAsFactors=FALSE)
      }
      if (length(rows)==n0) fails[[length(fails)+1L]] <- failure_row(test,sh,NA_real_,paste0('inner_history_empty:',heldout),'No inner passage history generated.')
    }
  }
  list(history=do.call(rbind,rows),failures=fails,isolation=do.call(rbind,iso),seasons=seasons)
}

# Vectorised evaluator: first confirmation of every policy on one ordered history.
# Non-finite posterior/drop values never confirm (m1_v2_passage_decision semantics).
first_confirm <- function(z,grid) {
  z <- z[order(z$origin_week),,drop=FALSE]
  el <- outer(z$origin_week-ceiling(z$activation_week_decimal),grid$min_post_activation,'>=')
  p <- ifelse(is.finite(z$prob_peak_passed),z$prob_peak_passed,-Inf)
  dr <- ifelse(is.finite(z$drop_from_post_activation_max),z$drop_from_post_activation_max,-Inf)
  fast <- el & outer(p,grid$high_threshold,'>=') & (z$immediate_decline %in% TRUE) & outer(dr,grid$fast_drop_fraction,'>=')
  sus <- el & outer(p,grid$low_threshold,'>=') & (z$sustained_two_week_decline %in% TRUE) & outer(dr,grid$drop_fraction,'>=')
  idx <- apply(fast|sus,2,function(v) match(TRUE,v))
  fb <- fast[cbind(ifelse(is.na(idx),1L,idx),seq_along(idx))]
  data.frame(policy_id=grid$policy_id,confirm_origin=ifelse(is.na(idx),NA_real_,z$origin_week[ifelse(is.na(idx),1L,idx)]),
    branch=ifelse(is.na(idx),NA_character_,ifelse(fb,'high_posterior_decline','sustained_decline')),stringsAsFactors=FALSE)
}

evaluate_inner <- function(history,grid) {
  do.call(rbind,lapply(split(history,list(history$activation_shift,history$season),drop=TRUE),function(z) {
    r <- first_confirm(z,grid)
    tc <- unique(z$truth_confirm)
    r$season <- z$season[1]; r$activation_shift <- z$activation_shift[1]; r$truth_confirm <- tc
    r$FE <- as.integer(is.finite(r$confirm_origin) & r$confirm_origin<tc)
    r$EW <- ifelse(is.finite(r$confirm_origin),pmax(tc-r$confirm_origin,0),0)
    r$MISS <- as.integer(!is.finite(r$confirm_origin) | r$confirm_origin>tc+2)
    r$D7 <- ifelse(is.finite(r$confirm_origin),pmax(r$confirm_origin-tc,0),UNCONFIRMED_DELAY)
    r
  }))
}

# Exact lexicographic robust objective with deterministic parameter tie-breaks.
score_policies <- function(ev,grid,n_inner_seasons) {
  agg <- aggregate(cbind(FE,EW,MISS,D7)~policy_id+activation_shift,data=ev,FUN=sum)
  w <- function(v) { m <- reshape(agg[,c('policy_id','activation_shift',v)],idvar='policy_id',timevar='activation_shift',direction='wide'); m[order(m$policy_id),] }
  out <- grid
  for (v in c('FE','EW','MISS','D7')) {
    m <- w(v); m <- m[match(out$policy_id,m$policy_id),]
    for (sh in INNER_SHIFTS) {
      col <- paste0(v,'.',sh)
      out[[paste0(v,'_shift',sh)]] <- if (col %in% names(m)) m[[col]] else NA_real_
    }
  }
  s <- function(v) as.matrix(out[,paste0(v,'_shift',INNER_SHIFTS)])
  out$worst_shift_n_false_early <- apply(s('FE'),1,max)
  out$worst_shift_early_weeks_total <- apply(s('EW'),1,max)
  out$all_shift_n_false_early <- rowSums(s('FE'))
  out$all_shift_early_weeks_total <- rowSums(s('EW'))
  out$worst_shift_n_miss_by_peak2 <- apply(s('MISS'),1,max)
  out$all_shift_n_miss_by_peak2 <- rowSums(s('MISS'))
  out$worst_shift_delay7_total <- apply(s('D7'),1,max)
  out$all_shift_delay7_total <- rowSums(s('D7'))
  out$all_shift_miss_rate <- out$all_shift_n_miss_by_peak2/(length(INNER_SHIFTS)*n_inner_seasons)
  if (anyNA(out[,grep('_shift',names(out))])) stop('Incomplete inner policy scores.')
  out
}
LEX_KEYS <- c('worst_shift_n_false_early','worst_shift_early_weeks_total','all_shift_n_false_early','all_shift_early_weeks_total',
  'worst_shift_n_miss_by_peak2','all_shift_n_miss_by_peak2','worst_shift_delay7_total','all_shift_delay7_total')
select_policy <- function(sc) {
  ord <- order(sc$worst_shift_n_false_early,sc$worst_shift_early_weeks_total,sc$all_shift_n_false_early,sc$all_shift_early_weeks_total,
    sc$worst_shift_n_miss_by_peak2,sc$all_shift_n_miss_by_peak2,sc$worst_shift_delay7_total,sc$all_shift_delay7_total,
    -sc$high_threshold,-sc$fast_drop_fraction,-sc$drop_fraction,-sc$min_post_activation,-sc$low_threshold)
  sc$rank <- NA_integer_; sc$rank[ord] <- seq_along(ord)
  sc
}
policy_sha <- function(p) digest::digest(as.list(p[1,names(POLICY_AXES)]),algo='sha256')

# Truth-independent outer replay: sequential causal posteriors and frozen
# m1_v2_passage_decision() through max(held$weekF). No peak truth enters here.
outer_path <- function(test,shift,library,held,act_dec,policy,check_future=FALSE) {
  empty <- data.frame(season=character(0),activation_shift=integer(0),origin_week=numeric(0),prob_peak_passed=numeric(0),
    immediate_decline=logical(0),sustained_two_week_decline=logical(0),drop_from_post_activation_max=numeric(0),
    confirmed_now=logical(0),confirmation_branch=character(0),timing_state=character(0))
  if (!is.finite(act_dec)) return(list(path=empty,state='inactive_no_timing_event',failures=list(),future=NULL,n_posterior_calls=0L))
  act_int <- ceiling(act_dec)
  decide <- function(h,d) m1_v2_passage_decision(h,d,act_dec,high_threshold=policy$high_threshold,low_threshold=policy$low_threshold,
    drop_fraction=policy$drop_fraction,fast_drop_fraction=policy$fast_drop_fraction,min_post_activation=policy$min_post_activation)
  hist <- NULL; rows <- list(); fails <- list(); fut <- list(); confirmed <- FALSE; n_calls <- 0L
  for (o in seq(act_int,max(held$weekF))) {
    step <- tryCatch({
      pp <- m1_v2_passage_posterior(library,held,act_dec,o,candidate_step=PASS_STEP,max_future_weeks=PASSAGE_MAX_FUTURE)
      h <- rbind(hist,pp)
      list(pp=pp,hist=h,dec=decide(h,held))
    },error=function(e)e)
    n_calls <- n_calls+1L
    if (inherits(step,'error')) { fails[[length(fails)+1L]] <- failure_row(test,shift,o,'outer_passage',conditionMessage(step)); break }
    hist <- step$hist; dec <- step$dec
    confirmed <- confirmed || isTRUE(dec$peak_reached_or_passed)
    rows[[length(rows)+1L]] <- data.frame(season=test,activation_shift=shift,origin_week=o,prob_peak_passed=step$pp$prob_peak_passed,
      immediate_decline=dec$immediate_decline,sustained_two_week_decline=dec$sustained_two_week_decline,
      drop_from_post_activation_max=dec$drop_from_post_activation_max,confirmed_now=isTRUE(dec$peak_reached_or_passed),
      confirmation_branch=dec$confirmation_branch,timing_state=if (confirmed) 'confirmed' else 'active_unconfirmed',stringsAsFactors=FALSE)
    if (check_future) {
      chk <- tryCatch({
        heldp <- perturb_future(held,o)
        pp2 <- m1_v2_passage_posterior(library,heldp,act_dec,o,candidate_step=PASS_STEP,max_future_weeks=PASSAGE_MAX_FUTURE)
        hp <- rbind(if (nrow(hist)>1) hist[-nrow(hist),] else NULL,pp2)
        dec2 <- decide(hp,heldp)
        c(prob=abs(pp2$prob_peak_passed-step$pp$prob_peak_passed),
          same=identical(dec2$peak_reached_or_passed,dec$peak_reached_or_passed) && identical(dec2$confirmation_branch,dec$confirmation_branch))
      },error=function(e)e)
      if (inherits(chk,'error')) { fails[[length(fails)+1L]] <- failure_row(test,shift,o,'outer_future_check',conditionMessage(chk)); chk <- c(prob=NA,same=0) }
      fut[[length(fut)+1L]] <- data.frame(season=test,activation_shift=shift,origin_week=o,max_abs_prob_diff=chk[['prob']],
        decision_identical=isTRUE(chk[['same']]==1),invariant=isTRUE(chk[['prob']]<1e-12) && isTRUE(chk[['same']]==1),stringsAsFactors=FALSE)
    }
  }
  path <- if (length(rows)) do.call(rbind,rows) else empty
  list(path=path,state=if (confirmed) 'confirmed' else 'active_unconfirmed',failures=fails,
       future=if (length(fut)) do.call(rbind,fut) else NULL,n_posterior_calls=n_calls)
}
path_hash <- function(path) digest::digest(path,algo='sha256')

# Scoring after replay; truth enters only here.
score_path <- function(path,Tpk,horizon_cap=Inf) {
  tc <- ceiling(Tpk)-1
  p <- path[path$origin_week<=horizon_cap,,drop=FALSE]
  conf <- p$origin_week[p$confirmed_now]
  full <- if (length(conf)) min(conf) else NA_real_
  br <- if (length(conf)) p$confirmation_branch[p$origin_week==full] else NA_character_
  scored <- if (is.finite(full) && full<=tc+PASSAGE_LATE_WEEKS) full else NA_real_
  data.frame(truth_peak=Tpk,truth_confirm=tc,first_confirm_origin_any=full,confirm_origin=scored,branch=if (is.finite(scored)) br else NA_character_,
    first_confirm_branch_any=br,censored_after_late_horizon=is.finite(full) && !is.finite(scored),
    false_early=is.finite(full) && full<tc,early_weeks=if (is.finite(full)) max(tc-full,0) else 0,
    confirmed_by_peak2=is.finite(full) && full<=tc+2,delay=if (is.finite(scored)) max(scored-tc,0) else NA_real_,
    delay7=if (is.finite(scored)) max(scored-tc,0) else UNCONFIRMED_DELAY,stringsAsFactors=FALSE)
}

# One outer chronological fold.
run_fold <- function(test,Bdata=B,truth=truth0,mode='nominal') {
  full <- mode=='nominal'
  inp <- fold_inputs(test,Bdata,truth)
  stage <- build_m1_v2_timing(allD=inp$trainB,peak_truth=inp$train_truth,activation_table=inp$act_train,
    k=8L,grid_step=.01,tau_step=.1,amplitude_grid=B_AMP_GRID,calibration_origins=CAL_ORIGINS,
    calibration_candidate_step=CAL_STEP,passage_candidate_step=PASS_STEP)
  if (!inherits(stage,'page_m1_v2_stage')) stop('Stage construction failed.')
  assert_fold_isolation(test,inp,stage)
  ih <- build_inner_histories(test,stage,inp,truth)
  fails <- ih$failures
  hist <- ih$history
  if (is.null(hist) || !nrow(hist)) stop('No inner passage histories at ',test)
  if (!all(hist$season %in% inp$train_seasons) || test %in% hist$season) stop('Shifted activations escaped inner training histories at ',test)

  ev <- evaluate_inner(hist,GRID)
  sc <- select_policy(score_policies(ev,GRID,length(ih$seasons)))
  sel <- sc[sc$rank==1L,,drop=FALSE]
  # Determinism: re-evaluate on a permuted grid/history order and compare.
  perm <- GRID[rev(seq_len(nrow(GRID))),]
  sc2 <- select_policy(score_policies(evaluate_inner(hist[rev(seq_len(nrow(hist))),],perm),perm,length(ih$seasons)))
  sel2 <- sc2[sc2$rank==1L,,drop=FALSE]
  deterministic <- identical(policy_sha(sel),policy_sha(sel2)) && sum(sc$rank==1L)==1L
  top <- sc[order(sc$rank),LEX_KEYS][1:2,]
  sel$tie_broken_by_parameters <- isTRUE(all(top[1,]==top[2,]))
  for (a in names(POLICY_AXES)) sel[[paste0('boundary_',a)]] <- sel[[a]] %in% range(POLICY_AXES[[a]])
  sel$high_threshold_hard_ceiling <- sel$high_threshold==max(POLICY_AXES$high_threshold)

  lib <- stage$library; held <- inp$held
  act_nom <- truth$B_activity_weekF[truth$season==test]
  Tpk <- truth$B_peak_weekF[truth$season==test]
  paths <- list(); outer_rows <- list(); fut <- list()
  for (sh in OUTER_SHIFTS) {
    r <- outer_path(test,sh,lib,held,act_nom+sh,sel,check_future=full)
    fails <- c(fails,r$failures)
    paths[[as.character(sh)]] <- r
    outer_rows[[length(outer_rows)+1L]] <- cbind(data.frame(season=test,activation_shift=sh,activation_weekF=act_nom+sh,
      first_origin=ceiling(act_nom+sh),last_origin=max(held$weekF),n_origins_replayed=nrow(r$path),replay_completed=!length(r$failures),
      final_timing_state=r$state,path_sha256=path_hash(r$path),stringsAsFactors=FALSE),score_path(r$path,Tpk),
      data.frame(policy_id=sel$policy_id,policy_sha256=policy_sha(sel),policy_high=sel$high_threshold,policy_low=sel$low_threshold,
        policy_drop=sel$drop_fraction,policy_fast_drop=sel$fast_drop_fraction,policy_min_post=sel$min_post_activation,stringsAsFactors=FALSE))
    if (!is.null(r$future)) fut[[length(fut)+1L]] <- r$future
  }
  base <- list(test=test,mode=mode,fold_digest=inp$digest,library_hash=lib$provenance$library_hash,policy_sha=policy_sha(sel),
    selected=sel,outer=do.call(rbind,outer_rows),history_hash=digest::digest(hist,algo='sha256'),
    failures=if (length(fails)) do.call(rbind,fails) else NULL)
  if (!full) return(base)

  # Frozen sub-grid evaluator equivalence at shift 0 against fit_m1_v2_passage_policy().
  pp <- stage$passage_policy
  h0 <- hist[hist$activation_shift==0L,c('season','origin_week','activation_origin_week','activation_week_decimal','truth_confirm','prob_peak_passed','immediate_decline','sustained_two_week_decline','drop_from_post_activation_max')]
  ref_h <- pp$inner_history[,names(h0)]
  h0o <- h0[order(match(h0$season,ih$seasons),h0$origin_week),]; rownames(h0o) <- NULL; rownames(ref_h) <- NULL
  history_equal <- isTRUE(all.equal(h0o,ref_h,tolerance=0,check.attributes=FALSE))
  sub <- GRID[GRID$high_threshold==FROZEN_SUB$high & GRID$fast_drop_fraction==FROZEN_SUB$fast & GRID$low_threshold %in% FROZEN_SUB$low &
    GRID$drop_fraction %in% FROZEN_SUB$drop & GRID$min_post_activation %in% FROZEN_SUB$min_post,]
  if (nrow(sub)!=32L) stop('Frozen sub-grid is not 32 policies.')
  ev0 <- ev[ev$activation_shift==0L & ev$policy_id %in% sub$policy_id,]
  ev0 <- merge(ev0,sub,by='policy_id')
  ref <- pp$evaluation
  key <- function(z) paste(z$season,z$high_threshold,z$low_threshold,z$drop_fraction,z$min_post_activation)
  m <- match(key(ev0),key(ref))
  if (anyNA(m) || nrow(ref)!=nrow(ev0)) stop('Frozen sub-grid rows do not align at ',test)
  ref <- ref[m,]
  sub_rows <- data.frame(test_season=test,season=ev0$season,high_threshold=ev0$high_threshold,low_threshold=ev0$low_threshold,
    drop_fraction=ev0$drop_fraction,fast_drop_fraction=ev0$fast_drop_fraction,min_post_activation=ev0$min_post_activation,
    custom_confirm=ev0$confirm_origin,fitter_confirm=ref$confirm_origin,custom_branch=ev0$branch,fitter_branch=ref$branch,
    match=identical_na(ev0$confirm_origin,ref$confirm_origin) & identical_na(ev0$branch,ref$branch) &
      (ev0$FE==as.integer(ref$false_early)) & (ev0$EW==ref$early_weeks) & (ev0$MISS==as.integer(ref$miss_by_peak2)),stringsAsFactors=FALSE)
  # m1_v2_passage_decision() agreement on the same shift-0 sub-grid histories.
  d_tr <- prepare_surveillance_data(inp$trainB)
  dec_rows <- list()
  for (s in ih$seasons) {
    z <- h0o[h0o$season==s,]; heldz <- d_tr[d_tr$season==s,]
    for (i in seq_len(nrow(sub))) {
      pol <- sub[i,]; conf <- NA_real_; br <- NA_character_
      for (j in seq_len(nrow(z))) {
        dd <- m1_v2_passage_decision(z[seq_len(j),c('origin_week','prob_peak_passed')],heldz[heldz$weekF<=z$origin_week[j],],z$activation_week_decimal[1],
          high_threshold=pol$high_threshold,low_threshold=pol$low_threshold,drop_fraction=pol$drop_fraction,
          fast_drop_fraction=pol$fast_drop_fraction,min_post_activation=pol$min_post_activation)
        if (isTRUE(dd$peak_reached_or_passed)) { conf <- z$origin_week[j]; br <- dd$confirmation_branch; break }
      }
      dec_rows[[length(dec_rows)+1L]] <- data.frame(season=s,policy_id=pol$policy_id,decision_confirm=conf,decision_branch=br)
    }
  }
  dr <- do.call(rbind,dec_rows)
  dm <- merge(dr,ev[ev$activation_shift==0L,c('season','policy_id','confirm_origin','branch')],by=c('season','policy_id'))
  sub_rows$decision_fn_match <- all(identical_na(dm$decision_confirm,dm$confirm_origin) & identical_na(dm$decision_branch,dm$branch)) && nrow(dm)==nrow(dr)

  # Existing v2 selector reproduction (nominal) plus fixed-library shift replay.
  ex <- pp$selected[1,]
  ex_pol <- data.frame(high_threshold=ex$high_threshold,low_threshold=ex$low_threshold,drop_fraction=ex$drop_fraction,
    fast_drop_fraction=ex$fast_drop_fraction,min_post_activation=ex$min_post_activation)
  v2r <- v2_pass[v2_pass$season==test,]
  cmp <- list()
  for (sh in OUTER_SHIFTS) {
    r <- outer_path(test,sh,lib,held,act_nom+sh,ex_pol)
    fails <- c(fails,r$failures)
    sp <- score_path(r$path,Tpk)
    row <- data.frame(season=test,semantics='fixed_outer_library_policy_shift_test_only',selector='existing_v2_fit_m1_v2_passage_policy',activation_shift=sh,
      confirm_origin=sp$confirm_origin,branch=sp$branch,false_early=sp$false_early,early_weeks=sp$early_weeks,confirmed_by_peak2=sp$confirmed_by_peak2,delay7=sp$delay7,
      policy_high=ex$high_threshold,policy_low=ex$low_threshold,policy_drop=ex$drop_fraction,policy_fast_drop=ex$fast_drop_fraction,policy_min_post=ex$min_post_activation,
      v2_confirm_origin=NA_real_,v2_branch=NA_character_,reproduction_exact=NA,stringsAsFactors=FALSE)
    if (sh==0L) {
      v2cap <- score_path(r$path,Tpk,horizon_cap=v2r$last_origin)
      row$v2_confirm_origin <- v2r$confirm_origin; row$v2_branch <- v2r$branch
      row$reproduction_exact <- identical_na(v2cap$first_confirm_origin_any,v2r$confirm_origin) && identical_na(v2cap$first_confirm_branch_any,v2r$branch) &&
        isTRUE(all.equal(c(ex$high_threshold,ex$low_threshold,ex$drop_fraction,ex$fast_drop_fraction,ex$min_post_activation),
          c(v2r$policy_high,v2r$policy_low,v2r$policy_drop,v2r$policy_fast_drop,v2r$policy_min_post),tolerance=0))
    }
    cmp[[length(cmp)+1L]] <- row
  }
  # Sustained-only diagnostic: fast branch disabled, robust sustained parameters reused.
  so_pol <- data.frame(high_threshold=1,low_threshold=sel$low_threshold,drop_fraction=sel$drop_fraction,fast_drop_fraction=1,min_post_activation=sel$min_post_activation)
  so <- list()
  for (sh in OUTER_SHIFTS) {
    r <- outer_path(test,sh,lib,held,act_nom+sh,so_pol)
    fails <- c(fails,r$failures)
    so[[length(so)+1L]] <- cbind(data.frame(season=test,activation_shift=sh,policy_high=1,policy_fast_drop=1,policy_low=so_pol$low_threshold,
      policy_drop=so_pol$drop_fraction,policy_min_post=so_pol$min_post_activation,n_origins_replayed=nrow(r$path),
      any_origin_high_posterior_branch=any(r$path$confirmation_branch %in% 'high_posterior_decline'),
      n_origins_high_posterior_branch=sum(r$path$confirmation_branch %in% 'high_posterior_decline'),
      high_branch_origins_zero_positivity=all(held$p[match(r$path$origin_week[r$path$confirmation_branch %in% 'high_posterior_decline'],held$weekF)]==0),
      stringsAsFactors=FALSE),score_path(r$path,Tpk))
    so[[length(so)]]$first_confirmation_high_posterior_branch <- so[[length(so)]]$first_confirm_branch_any %in% 'high_posterior_decline'
  }

  ledger <- data.frame(test_season=test,n_train=length(inp$train_seasons),training_seasons=paste(inp$train_seasons,collapse=';'),
    fold_input_digest=inp$digest,library_hash=lib$provenance$library_hash,stage_artifact_id=stage$artifact_id,
    amplitude_grid_ok=isTRUE(all.equal(lib$config$amplitude_grid,B_AMP_GRID,tolerance=0)),passage_candidate_step=PASS_STEP,
    passage_max_future_weeks=PASSAGE_MAX_FUTURE,outer_fold_isolation_asserted=TRUE,inner_fold_isolation_asserted=all(ih$isolation$inner_isolated),
    shifted_activation_confined_to_inner=TRUE,n_inner_seasons=length(ih$seasons),
    n_inner_rows_shift_m1=sum(hist$activation_shift==-1L),n_inner_rows_shift_0=sum(hist$activation_shift==0L),n_inner_rows_shift_p1=sum(hist$activation_shift==1L),
    inner_history_shift0_equals_fitter=history_equal,subgrid_evaluator_match=all(sub_rows$match),decision_fn_match=all(sub_rows$decision_fn_match),
    selection_deterministic=deterministic,inner_history_sha256=base$history_hash,stringsAsFactors=FALSE)
  sel_out <- cbind(data.frame(test_season=test,policy_sha256=policy_sha(sel),selection_deterministic=deterministic,
    inner_worst_shift_n_false_early=sel$worst_shift_n_false_early,inner_worst_shift_n_miss_by_peak2=sel$worst_shift_n_miss_by_peak2,
    inner_all_shift_miss_rate=sel$all_shift_miss_rate,stringsAsFactors=FALSE),sel)
  c(base,list(ledger=ledger,selected_out=sel_out,scores=cbind(test_season=test,sc[order(sc$rank),]),history=hist,
    future=if (length(fut)) do.call(rbind,fut) else NULL,subgrid=sub_rows,comparison=do.call(rbind,cmp),sustained=do.call(rbind,so),
    failures=if (length(fails)) do.call(rbind,fails) else NULL))
}
# 2018-19 exclusion perturbation data and outer truth perturbation table.
B_pert <- B
i1819 <- B_pert$season==INACTIVE_SEASON
if (!any(i1819)) stop('2018-19 rows missing from B panel.')
B_pert$y[i1819] <- pmin(B_pert$N[i1819],round(B_pert$y[i1819]*3)+25)
storage.mode(B_pert$y) <- storage.mode(B$y)
B_pert$p[i1819] <- B_pert$y[i1819]/B_pert$N[i1819]
if (identical(digest::digest(B[i1819,],algo='sha256'),digest::digest(B_pert[i1819,],algo='sha256'))) stop('2018-19 perturbation is a no-op.')
if (!identical(B[!i1819,],B_pert[!i1819,])) stop('Perturbation touched non-2018-19 rows.')
post1819 <- test_seasons[season_start(test_seasons)>season_start(INACTIVE_SEASON)]
truth_pert_for <- function(test) { z <- truth0; z$B_peak_weekF[z$season==test] <- z$B_peak_weekF[z$season==test]+TRUTH_PERTURB_WEEKS; z }

jobs <- c(lapply(test_seasons,function(s) list(test=s,mode='nominal')),
  lapply(test_seasons,function(s) list(test=s,mode='truth_perturbed')),
  lapply(post1819,function(s) list(test=s,mode='inactive_perturbed')))
cat('Running',length(jobs),'fold jobs on',N_CORES,'cores\n')
res <- parallel::mclapply(jobs,function(j) tryCatch(
  run_fold(j$test,Bdata=if (j$mode=='inactive_perturbed') B_pert else B,truth=if (j$mode=='truth_perturbed') truth_pert_for(j$test) else truth0,mode=j$mode),
  error=function(e) structure(list(message=conditionMessage(e)),class='fold_error')),mc.cores=N_CORES,mc.preschedule=FALSE)
job_err <- vapply(res,function(r) inherits(r,'fold_error') || inherits(r,'try-error') || is.null(r),logical(1))
if (any(job_err)) {
  msg <- vapply(res[job_err],function(r) if (is.list(r) && !is.null(r$message)) r$message else paste(as.character(r),collapse=' '),character(1))
  stop('Fold job(s) failed:\n',paste(vapply(jobs[job_err],function(j) paste0(j$test,'/',j$mode),character(1)),msg,sep=': ',collapse='\n'))
}
mode_of <- vapply(jobs,`[[`,character(1),'mode')
bind <- function(rs,field) { z <- Filter(Negate(is.null),lapply(rs,`[[`,field)); if (length(z)) do.call(rbind,z) else data.frame() }
nom <- res[mode_of=='nominal']; tpr <- res[mode_of=='truth_perturbed']; ipr <- res[mode_of=='inactive_perturbed']
names(nom) <- vapply(nom,`[[`,character(1),'test')

ledger <- bind(nom,'ledger')
selected <- bind(nom,'selected_out')
scores <- bind(nom,'scores')
inner_hist <- bind(nom,'history')
outer_all <- bind(nom,'outer')
outer_nom <- outer_all[outer_all$activation_shift==0L,]
outer_sens <- outer_all
outer_sens$semantics <- 'fixed_outer_library_policy_shift_test_only'
future <- bind(nom,'future')
subgrid <- bind(nom,'subgrid')
comparison <- bind(nom,'comparison')
sustained <- bind(nom,'sustained')
failures <- bind(c(nom,tpr,ipr),'failures')
if (!nrow(failures)) failures <- data.frame(season=character(0),activation_shift=integer(0),origin_weekF=numeric(0),stage=character(0),message=character(0))

# Robust-selector rows and v2 joint-shift rows (earlier semantics, labelled separately).
rob_cmp <- data.frame(season=outer_all$season,semantics='fixed_outer_library_policy_shift_test_only',selector='activation_robust_v1',
  activation_shift=outer_all$activation_shift,confirm_origin=outer_all$confirm_origin,branch=outer_all$branch,false_early=outer_all$false_early,
  early_weeks=outer_all$early_weeks,confirmed_by_peak2=outer_all$confirmed_by_peak2,delay7=outer_all$delay7,policy_high=outer_all$policy_high,
  policy_low=outer_all$policy_low,policy_drop=outer_all$policy_drop,policy_fast_drop=outer_all$policy_fast_drop,policy_min_post=outer_all$policy_min_post,
  v2_confirm_origin=NA_real_,v2_branch=NA_character_,reproduction_exact=NA,stringsAsFactors=FALSE)
v2j <- rbind(v2_pass,v2_sens[,names(v2_pass)])
v2_cmp <- data.frame(season=v2j$season,semantics=ifelse(v2j$activation_shift==0,'v2_nominal_truth_horizon','v2_joint_train_test_shift_semantics'),
  selector='existing_v2_artifact',activation_shift=v2j$activation_shift,confirm_origin=v2j$confirm_origin,branch=v2j$branch,false_early=v2j$false_early,
  early_weeks=v2j$early_weeks,confirmed_by_peak2=v2j$confirmed_by_peak2,delay7=ifelse(is.finite(v2j$delay),v2j$delay,UNCONFIRMED_DELAY),
  policy_high=v2j$policy_high,policy_low=v2j$policy_low,policy_drop=v2j$policy_drop,policy_fast_drop=v2j$policy_fast_drop,policy_min_post=v2j$policy_min_post,
  v2_confirm_origin=NA_real_,v2_branch=NA_character_,reproduction_exact=NA,stringsAsFactors=FALSE)
comparison_all <- rbind(comparison,rob_cmp,v2_cmp)
existing_repro <- comparison[comparison$activation_shift==0L,]

# Outer truth perturbation: generated paths/policy identical, scoring changes.
truth_rows <- do.call(rbind,lapply(tpr,function(r) {
  n <- nom[[r$test]]
  a <- n$outer[order(n$outer$activation_shift),]; b <- r$outer[order(r$outer$activation_shift),]
  data.frame(season=r$test,activation_shift=a$activation_shift,truth_shift_weeks=TRUTH_PERTURB_WEEKS,
    nominal_path_sha256=a$path_sha256,perturbed_path_sha256=b$path_sha256,path_identical=a$path_sha256==b$path_sha256,
    policy_identical=identical(n$policy_sha,r$policy_sha),library_identical=identical(n$library_hash,r$library_hash),
    inner_history_identical=identical(n$history_hash,r$history_hash),
    nominal_truth_confirm=a$truth_confirm,perturbed_truth_confirm=b$truth_confirm,scoring_changed=a$truth_confirm!=b$truth_confirm,
    pass=a$path_sha256==b$path_sha256 & identical(n$policy_sha,r$policy_sha) & a$truth_confirm!=b$truth_confirm,stringsAsFactors=FALSE)
}))

# 2018-19 exclusion perturbation invariance for later folds.
pert_rows <- do.call(rbind,lapply(ipr,function(r) {
  n <- nom[[r$test]]
  same_paths <- identical(n$outer$path_sha256,r$outer$path_sha256)
  data.frame(test_season=r$test,inactive_in_training=INACTIVE_SEASON %in% fold_train_seasons(r$test),
    fold_input_digest_identical=identical(n$fold_digest,r$fold_digest),library_identical=identical(n$library_hash,r$library_hash),
    inner_history_identical=identical(n$history_hash,r$history_hash),policy_identical=identical(n$policy_sha,r$policy_sha),outer_paths_identical=same_paths,
    perturbation=sprintf('2018-19 y_B -> min(N_B, round(3*y_B)+25)'),
    pass=!(INACTIVE_SEASON %in% fold_train_seasons(r$test)) && identical(n$fold_digest,r$fold_digest) && identical(n$library_hash,r$library_hash) &&
      identical(n$history_hash,r$history_hash) && identical(n$policy_sha,r$policy_sha) && same_paths,stringsAsFactors=FALSE)
}))

# No-event contract: causal prefix replay of the B activity detector for 2018-19.
m0_params <- readRDS(M0_PARAMS_PATH)
m0_params$w_min <- B_WINDOW[1]; m0_params$w_max <- B_WINDOW[2]
det_ref <- readRDS(B_DETECT_PATH)$by_season
det_full <- tryCatch(detectIgnitionBySeason_M0v2_timing(B,params=m0_params,verbose=FALSE,iWeek=FALSE)$by_season,error=function(e)e)
detector_reproduced <- FALSE
if (!inherits(det_full,'error')) {
  mm <- match(det_ref$season,det_full$season)
  detector_reproduced <- !anyNA(mm) && all(identical_na(det_full$iWeek_hat[mm],det_ref$iWeek_hat)) &&
    all(identical_na(det_full$detection_failed[mm],det_ref$detection_failed)) &&
    isTRUE(all.equal(as.numeric(det_full$iWeek_hatF[mm]),as.numeric(det_ref$iWeek_hatF),tolerance=1e-10))
}
B1819 <- B[B$season==INACTIVE_SEASON,]
prefix_weeks <- B1819$weekF[B1819$weekF>=B_WINDOW[1] & B1819$weekF<=B_WINDOW[2]]
prefix_rows <- do.call(rbind,lapply(prefix_weeks,function(k) {
  dk <- tryCatch(detectIgnitionBySeason_M0v2_timing(B1819[B1819$weekF<=k,],params=m0_params,verbose=FALSE,iWeek=FALSE,validate_support=FALSE)$by_season,error=function(e)e)
  if (inherits(dk,'error')) return(data.frame(check='prefix_activation',season=INACTIVE_SEASON,prefix_week=k,evaluated=FALSE,activated=NA,value=conditionMessage(dk),pass=FALSE))
  act <- nrow(dk)>0L && !isTRUE(dk$detection_failed[1]) && is.finite(dk$iWeek_hat[1])
  data.frame(check='prefix_activation',season=INACTIVE_SEASON,prefix_week=k,evaluated=TRUE,activated=act,value=as.character(dk$iWeek_hat[1]),pass=!act)
}))
inactive_path <- outer_path(INACTIVE_SEASON,0L,NULL,B1819,NA_real_,NULL)
all_states <- c(inactive_path$state,outer_all$final_timing_state)
states_ok <- all(all_states %in% TIMING_STATES) && all(outer_all$final_timing_state %in% TIMING_STATES[2:3])
no_event <- rbind(prefix_rows,
  data.frame(check='prefix_window_coverage',season=INACTIVE_SEASON,prefix_week=NA,evaluated=TRUE,activated=NA,
    value=paste0(length(prefix_weeks),' prefixes weeks ',min(prefix_weeks),'-',max(prefix_weeks)),pass=length(prefix_weeks)>0L && all(B_WINDOW[1]:B_WINDOW[2] %in% prefix_weeks)),
  data.frame(check='full_season_detector_reproduces_B_window8_40_rds',season='all',prefix_week=NA,evaluated=TRUE,activated=NA,value=as.character(detector_reproduced),pass=isTRUE(detector_reproduced)),
  data.frame(check='no_passage_posterior_without_activation',season=INACTIVE_SEASON,prefix_week=NA,evaluated=TRUE,activated=FALSE,
    value=paste0('posterior_calls=',inactive_path$n_posterior_calls,';rows=',nrow(inactive_path$path)),pass=inactive_path$n_posterior_calls==0L && nrow(inactive_path$path)==0L),
  data.frame(check='m1_b_timing_state',season=INACTIVE_SEASON,prefix_week=NA,evaluated=TRUE,activated=FALSE,value=inactive_path$state,pass=identical(inactive_path$state,'inactive_no_timing_event')),
  data.frame(check='three_state_contract',season='all',prefix_week=NA,evaluated=TRUE,activated=NA,value=paste(sort(unique(all_states)),collapse=';'),pass=states_ok),
  data.frame(check='excluded_from_training_and_scoring',season=INACTIVE_SEASON,prefix_week=NA,evaluated=TRUE,activated=NA,
    value='not in meaningful/test/inner seasons',pass=!(INACTIVE_SEASON %in% c(test_seasons,inner_hist$season,unlist(strsplit(ledger$training_seasons,';',fixed=TRUE))))),
  data.frame(check='pseudo_activation_diagnostic',season=INACTIVE_SEASON,prefix_week=NA,evaluated=FALSE,activated=NA,value='optional non-veto diagnostic not run',pass=NA))

# Acceptance criteria.
nn <- outer_nom
fe_m1 <- sum(outer_all$false_early[outer_all$activation_shift==-1L]); fe_p1 <- sum(outer_all$false_early[outer_all$activation_shift==1L])
page_r_hash_end <- hash_dir(page_r_files)
existing_hash_end <- hash_dir(existing_files)
plan_sha_end <- sha256_file(PLAN_PATH)
page_r_unchanged <- identical(page_r_hash_start,page_r_hash_end) && identical(sort(list.files('PAGe/R',full.names=TRUE,recursive=TRUE)),page_r_files) &&
  page_r_git_clean_start && identical(system2('git',c('diff','--quiet','HEAD','--','PAGe/R')),0L)
existing_unchanged <- identical(existing_hash_start,existing_hash_end)
integrity <- c(
  outer_fold_isolation=all(ledger$outer_fold_isolation_asserted),
  inner_fold_isolation=all(ledger$inner_fold_isolation_asserted),
  future_perturbation_invariance_all_shifts=nrow(future)>0L && all(future$invariant) && setequal(unique(future$activation_shift),OUTER_SHIFTS),
  truth_perturbation_scoring_only=nrow(truth_rows)==length(OUTER_SHIFTS)*length(test_seasons) && all(truth_rows$pass),
  shifted_activation_confined_inner=all(ledger$shifted_activation_confined_to_inner),
  existing_selector_reproduction_exact=nrow(existing_repro)==length(test_seasons) && all(existing_repro$reproduction_exact %in% TRUE),
  subgrid_evaluator_equivalence=all(ledger$subgrid_evaluator_match) && all(ledger$inner_history_shift0_equals_fitter),
  decision_function_agreement=all(ledger$decision_fn_match),
  prefix_2018_19_no_activation=all(prefix_rows$pass),
  inactive_exclusion_perturbation_invariant=nrow(pert_rows)==length(post1819) && all(pert_rows$pass),
  deterministic_policy_selection=all(ledger$selection_deterministic),
  amplitude_grid_retained=all(ledger$amplitude_grid_ok),
  passage_step_and_max_future_explicit=all(ledger$passage_candidate_step==.2 & ledger$passage_max_future_weeks==12),
  no_silent_inner_history_failures=!any(grepl('^inner_history',failures$stage)),
  sustained_only_confirmation_never_fast_branch=all(!sustained$first_confirmation_high_posterior_branch),
  plan_sha_recorded_unchanged=identical(plan_sha_start,plan_sha_end),
  frozen_page_r_unchanged=page_r_unchanged,
  existing_artifacts_unchanged=existing_unchanged
)
no_event_ok <- all(no_event$pass[!is.na(no_event$pass)])
criteria <- data.frame(
  group=c(rep('nominal_outer',5),rep('outer_activation_robustness',2),rep('inner_feasibility_integrity',4),rep('integrity_detail',length(integrity))),
  criterion=c('n_false_early_eq_0','n_confirmed_by_peak2_ge_4','median_delay7_le_2','mean_delay7_le_2.5','no_unhandled_replay_failures',
    'shift_m1_n_false_early_eq_0','shift_p1_n_false_early_eq_0',
    'all_folds_inner_worst_shift_n_false_early_eq_0','all_causal_integrity_checks_pass','deterministic_policy_selection','no_event_contract_pass',
    names(integrity)),
  value=c(sum(nn$false_early),sum(nn$confirmed_by_peak2),median(nn$delay7),mean(nn$delay7),nrow(failures),fe_m1,fe_p1,
    max(selected$inner_worst_shift_n_false_early),sum(!integrity),sum(!ledger$selection_deterministic),sum(!no_event$pass,na.rm=TRUE),as.numeric(integrity)),
  pass=c(sum(nn$false_early)==0,sum(nn$confirmed_by_peak2)>=4,median(nn$delay7)<=2,mean(nn$delay7)<=2.5,nrow(failures)==0L && all(outer_all$replay_completed),
    fe_m1==0,fe_p1==0,all(selected$inner_worst_shift_n_false_early==0),all(integrity),all(ledger$selection_deterministic),no_event_ok,integrity),
  stringsAsFactors=FALSE)
criteria$n_eligible_seasons <- length(test_seasons)
promising <- all(criteria$pass)
verdict <- data.frame(
  historically_promising_second_look=promising,
  study_type='second_look_historical_robustness_not_clean_holdout',
  eligibility=if (promising) 'M2-B_shadow_integration_only' else 'stop_hard_M1B_passage_gating',
  peak_location_model='raw_M1_B0_unchanged',
  production_hard_gate_eligible=FALSE,governed=FALSE,
  prospective_2026_27_required=TRUE,
  n_false_early_nominal=sum(nn$false_early),n_false_early_shift_m1=fe_m1,n_false_early_shift_p1=fe_p1,
  n_confirmed_by_peak2_nominal=sum(nn$confirmed_by_peak2),median_delay7_nominal=median(nn$delay7),mean_delay7_nominal=mean(nn$delay7),
  n_unconfirmed_nominal=sum(!is.finite(nn$confirm_origin)),max_false_early_weeks_nominal=max(nn$early_weeks),
  zero_failure_upper95_note='0/6 false-early leaves approximate 95% upper bound near 39% per season',
  n_failed_criteria=sum(!criteria$pass),failed_criteria=paste(criteria$criterion[!criteria$pass],collapse=';'),
  stringsAsFactors=FALSE)

# Write once.
if (dir.exists(OUT) && length(list.files(OUT,all.files=TRUE,no..=TRUE))>0L) stop('Refusing to overwrite non-empty ',OUT)
dir.create(OUT,recursive=TRUE,showWarnings=FALSE)
wcsv <- function(x,f) write.csv(x,file.path(OUT,f),row.names=FALSE)
wcsv(ledger,'outer_fold_ledger.csv')
wcsv(selected,'selected_policy_by_outer_fold.csv')
wcsv(scores,'policy_scores_by_outer_fold.csv')
wcsv(inner_hist,'inner_passage_history.csv')
wcsv(outer_nom,'outer_passage_by_season.csv')
wcsv(outer_sens,'outer_activation_sensitivity.csv')
wcsv(comparison_all,'comparison_existing_policy.csv')
wcsv(subgrid,'frozen_subgrid_equivalence.csv')
wcsv(sustained,'sustained_only_diagnostic.csv')
wcsv(no_event,'no_event_check.csv')
wcsv(future,'future_perturbation_checks.csv')
wcsv(truth_rows,'truth_perturbation_checks.csv')
wcsv(pert_rows,'inactive_exclusion_perturbation_check.csv')
wcsv(failures,'failures.csv')
wcsv(criteria,'acceptance_criteria.csv')
wcsv(verdict,'overall_verdict.csv')

manifest <- rbind(
  data.frame(role='audited_plan_sha_before_run',path=PLAN_PATH,sha256=plan_sha_start),
  data.frame(role='benchmark_script',path=SCRIPT_PATH,sha256=sha256_file(SCRIPT_PATH)),
  data.frame(role=c('canonical_panel','timing_contract','timing_contract_metadata','B_activity_detector','M0_A_rule_params','raw_B0_baseline','fold_ledger','v2_reference_script'),
    path=c(PANEL_PATH,TIMING_PATH,TIMING_META,B_DETECT_PATH,M0_PARAMS_PATH,B0_PATH,FOLD_PATH,V2_SCRIPT),
    sha256=unname(hash_dir(c(PANEL_PATH,TIMING_PATH,TIMING_META,B_DETECT_PATH,M0_PARAMS_PATH,B0_PATH,FOLD_PATH,V2_SCRIPT)))),
  data.frame(role='v2_reference_artifact',path=list.files(V2_DIR,full.names=TRUE,recursive=TRUE),sha256=unname(hash_dir(list.files(V2_DIR,full.names=TRUE,recursive=TRUE)))),
  data.frame(role='frozen_PAGe_R',path=page_r_files,sha256=unname(page_r_hash_end)))
wcsv(manifest,'source_manifest.csv')

config <- data.frame(
  key=c('benchmark','study_type','result_scope','plan_path','plan_sha256','policy_grid_size','high_threshold','low_threshold','drop_fraction','fast_drop_fraction',
    'min_post_activation','inner_activation_shifts','outer_activation_shifts','outer_shift_semantics','selection_keys','tie_break','amplitude_grid',
    'passage_candidate_step','passage_max_future_weeks','late_scoring_weeks','unconfirmed_delay','outer_replay_horizon','truth_perturbation_weeks',
    'inactive_season','B_activity_window','sustained_only_policy','sustained_only_assertion','pseudo_activation_diagnostic'),
  value=c('v3-m1-b-passage-robustness-v1','second_look_historical_robustness_not_clean_holdout','shadow_only_M2-B_eligibility_not_governed',PLAN_PATH,plan_sha_start,
    nrow(GRID),paste(POLICY_AXES$high_threshold,collapse=';'),paste(POLICY_AXES$low_threshold,collapse=';'),paste(POLICY_AXES$drop_fraction,collapse=';'),
    paste(POLICY_AXES$fast_drop_fraction,collapse=';'),paste(POLICY_AXES$min_post_activation,collapse=';'),paste(INNER_SHIFTS,collapse=';'),paste(OUTER_SHIFTS,collapse=';'),
    'library and policy fitted at nominal training activation; test activation shifted only',paste(LEX_KEYS,collapse='>'),
    'higher high_threshold>larger fast_drop_fraction>larger drop_fraction>larger min_post_activation>higher low_threshold','0.005:0.005:0.25',
    PASS_STEP,PASSAGE_MAX_FUTURE,PASSAGE_LATE_WEEKS,UNCONFIRMED_DELAY,'max(held$weekF); truth used only for scoring',TRUTH_PERTURB_WEEKS,
    INACTIVE_SEASON,paste(B_WINDOW,collapse='-'),'high_threshold=1; fast_drop_fraction=1; robust sustained parameters reused','first confirmation branch never high_posterior_decline; later-origin fast firings at p=0 weeks (drop=1, posterior=1) reported, not vetoed','not run (optional, non-veto)'),
  stringsAsFactors=FALSE)
wcsv(config,'benchmark_config.csv')

cat('\nSelected policies:\n'); print(selected[,c('test_season','high_threshold','low_threshold','drop_fraction','fast_drop_fraction','min_post_activation','inner_worst_shift_n_false_early','inner_all_shift_miss_rate')],row.names=FALSE)
cat('\nOuter replay:\n'); print(outer_all[,c('season','activation_shift','confirm_origin','branch','truth_confirm','false_early','confirmed_by_peak2','delay7')],row.names=FALSE)
cat('\nAcceptance:\n'); print(criteria[,c('group','criterion','value','pass')],row.names=FALSE)
cat('\nhistorically_promising_second_look =',promising,'\n')
