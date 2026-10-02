#!/usr/bin/env Rscript

# Pandemic-excluded, activation-robust M1-B passage benchmark (second-look
# historical robustness study; v3 shadow eligibility only). Implements
# docs/v3-m1-b-passage-robustness-plan-v2-2026-09-26.md under
# docs/v3-m1-b-season-policy-2026-09-26.md. Raw M1-B0 peak mechanics are frozen;
# only passage-policy selection changes. Frozen PAGe/R code is sourced
# unchanged; existing artifacts are read only. Set PAGE_BENCH_DRYRUN=1 to run a
# two-fold smoke test that writes nothing.

options(stringsAsFactors = FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

if (!requireNamespace('digest', quietly=TRUE)) stop('Package `digest` is required.')

PLAN_PATH <- 'docs/v3-m1-b-passage-robustness-plan-v2-2026-09-26.md'
POLICY_DOC <- 'docs/v3-m1-b-season-policy-2026-09-26.md'
SCRIPT_PATH <- 'scripts/v3_benchmark_m1_b_passage_robustness_v2.R'
PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
TIMING_META <- 'artifacts/v3-joint-timing-contract-v2/contract_metadata.csv'
B_DETECT_PATH <- 'artifacts/v3-a-rule-transfer-to-b-v1/B_window8_40_detection.rds'
M0_PARAMS_PATH <- 'artifacts/v3-a-rule-transfer-to-b-v1/A_aggregated_params.rds'
B0_DIR <- 'artifacts/v3-m1-b0-excluding-pandemic-v1'
B0_SCRIPT <- 'scripts/v3_benchmark_m1_b0_excluding_pandemic_v1.R'
EXISTING_DIR <- 'artifacts/v3-m1-b-passage-excluding-pandemic-v1'
EXISTING_SCRIPT <- 'scripts/v3_benchmark_m1_b_passage_excluding_pandemic_v1.R'
OUT <- 'artifacts/v3-m1-b-passage-robustness-v2'
DRYRUN <- identical(Sys.getenv('PAGE_BENCH_DRYRUN'),'1')

if (!DRYRUN && dir.exists(OUT) && length(list.files(OUT,all.files=TRUE,no..=TRUE))>0L) stop('Output directory already exists and is non-empty: ',OUT)

EXCLUDED_SEASON <- '2019-20'
EXCLUSION_REASON <- 'pandemic_transition'
INACTIVE_SEASON <- '2018-19'
PLAN_TEST_SEASONS <- c('2017-18','2022-23','2023-24','2024-25','2025-26')
B_AMP_GRID <- seq(.005,.25,by=.005)
PASS_STEP <- .2
PASSAGE_MAX_FUTURE <- 12
PASSAGE_LATE_WEEKS <- 6L
UNCONFIRMED_DELAY <- 7
B0_STEP <- .1
B0_MAX_FUTURE <- 16
B0_TOL <- 1e-8
MIN_TRAIN <- 4L
B_WINDOW <- c(8L,40L)
INNER_SHIFTS <- c(-1L,0L,1L)
OUTER_SHIFTS <- c(-1L,0L,1L)
TRUTH_PERTURB_WEEKS <- 3
TIMING_STATES <- c('inactive_no_timing_event','active_unconfirmed','confirmed')
N_CORES <- as.integer(Sys.getenv('PAGE_BENCH_CORES',unset='10'))

if (!identical(PASSAGE_MAX_FUTURE,eval(formals(m1_v2_passage_posterior)$max_future_weeks))) stop('Frozen passage max_future_weeks default changed.')

# Predeclared 1500-policy grid (plan v2, "Candidate grid").
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
# Frozen fit_m1_v2_passage_policy() defaults (the existing pandemic-excluded selector).
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

# Record plan, frozen-source and existing-artifact hashes before any computation.
plan_sha_start <- sha256_file(PLAN_PATH)
policy_doc_sha_start <- sha256_file(POLICY_DOC)
page_r_files <- sort(list.files('PAGe/R',full.names=TRUE,recursive=TRUE))
page_r_hash_start <- hash_dir(page_r_files)
page_r_git_clean_start <- identical(system2('git',c('diff','--quiet','HEAD','--','PAGe/R')),0L)
existing_files <- sort(setdiff(list.files('artifacts',full.names=TRUE,recursive=TRUE),list.files(OUT,full.names=TRUE,recursive=TRUE)))
existing_hash_start <- hash_dir(existing_files)
ref_inputs <- c(PANEL_PATH,TIMING_PATH,TIMING_META,B_DETECT_PATH,M0_PARAMS_PATH,B0_SCRIPT,EXISTING_SCRIPT)

panel <- read.csv(PANEL_PATH,check.names=FALSE)
truth0 <- read.csv(TIMING_PATH,check.names=FALSE)
folds <- read.csv(file.path(B0_DIR,'fold_ledger.csv'),check.names=FALSE)
b0_pred <- read.csv(file.path(B0_DIR,'per_origin_predictions.csv'),check.names=FALSE)
b0_libs <- read.csv(file.path(B0_DIR,'library_ledger.csv'),check.names=FALSE)
ex_pass <- read.csv(file.path(EXISTING_DIR,'passage_by_season_and_shift.csv'),check.names=FALSE)
ex_sel <- read.csv(file.path(EXISTING_DIR,'selected_policy_by_outer_fold.csv'),check.names=FALSE)

# B panel built exactly as the existing pandemic-excluded scripts (library hashes depend on it).
B <- data.frame(season=as.character(panel$season),weekF=panel$weekF,y=panel$y_B,N=panel$N_B,p=panel$p_B)
B <- B[order(season_start(B$season),B$weekF),]
meaningful <- as.character(truth0$season[is.finite(truth0$B_peak_weekF) & truth0$B_activity_detected & truth0$season!=EXCLUDED_SEASON])

contract_sha <- sha256_file(TIMING_PATH)
detect_sha <- sha256_file(B_DETECT_PATH)

tm <- truth0[truth0$season %in% meaningful,]
if (any(tm$B_peak_status!='retrospective_peak_truth')) stop('Meaningful B season lacks retrospective peak truth status.')
if (any(!is.finite(tm$B_activity_weekF)) || any(tm$B_activity_integer!=ceiling(tm$B_activity_weekF))) stop('B activity integer is not ceiling(B activity decimal).')
if (any(tm$B_activity_weekF>=tm$B_peak_weekF)) stop('B activation is not before B peak truth.')
ti <- truth0[truth0$season==INACTIVE_SEASON,]
if (nrow(ti)!=1L || isTRUE(ti$B_activity_detected) || is.finite(ti$B_peak_weekF) || ti$B_peak_status!='no_meaningful_peak') stop('Inactive-season timing semantics changed.')
if (any(c(INACTIVE_SEASON,EXCLUDED_SEASON) %in% meaningful)) stop('Inactive/excluded season is marked meaningful.')
if (!EXCLUDED_SEASON %in% B$season) stop('Canonical panel no longer retains the excluded season for audit.')

# Activation adapter identical to the existing pandemic-excluded passage script.
make_activation <- function(seasons,truth=truth0) {
  z <- truth[match(seasons,truth$season),c('season','B_activity_integer','B_activity_weekF')]
  if (anyNA(z$season) || any(!is.finite(z$B_activity_integer)) || any(!is.finite(z$B_activity_weekF))) stop('Missing activation.')
  out <- data.frame(season=as.character(z$season),activation_origin_week=as.numeric(z$B_activity_integer),activation_week_decimal=as.numeric(z$B_activity_weekF),stringsAsFactors=FALSE)
  attr(out,'m0_loso_context_id') <- paste0('v3-B-activity-A-rule-transfer-w8_40:',contract_sha,':pandemic-excluded')
  attr(out,'activation_provenance_id') <- digest::digest(list(semantics='v3-B-activity-research-adapter-pandemic-excluded',payload=.m1_v2_activation_payload(out),timing_contract_sha256=contract_sha,detection_sha256=detect_sha,excluded=EXCLUDED_SEASON),algo='sha256')
  attr(out,'activation_payload_hash') <- digest::digest(.m1_v2_activation_payload(out),algo='sha256')
  class(out) <- c('page_m1_v2_activation_table','data.frame')
  out
}

test_seasons <- as.character(folds$test_season[folds$eligible])
test_seasons <- test_seasons[order(season_start(test_seasons))]
if (!identical(test_seasons,PLAN_TEST_SEASONS)) stop('Eligible B timing seasons differ from plan: ',paste(test_seasons,collapse=';'))
if (any(c(EXCLUDED_SEASON,INACTIVE_SEASON) %in% test_seasons)) stop('Excluded/inactive season is a scored test season.')
if (!setequal(test_seasons,ex_sel$test_season) || !setequal(test_seasons,ex_pass$season)) stop('Existing selector artifact seasons differ.')
if (DRYRUN) test_seasons <- c('2017-18','2022-23')

fold_train_seasons <- function(test) {
  fold <- folds[folds$test_season==test,]
  if (nrow(fold)!=1L) stop('Fold missing for ',test)
  if (nzchar(fold$training_seasons)) strsplit(fold$training_seasons,';',fixed=TRUE)[[1]] else character(0)
}

fold_inputs <- function(test,Bdata,truth) {
  tr <- fold_train_seasons(test)
  trainB <- Bdata[Bdata$season %in% tr,]
  pt <- truth[match(tr,truth$season),c('season','B_peak_weekF')]
  names(pt)[2] <- 'peak_week_decimal'
  held <- Bdata[Bdata$season==test,]
  list(train_seasons=tr,trainB=trainB,train_truth=pt,act_train=make_activation(tr,truth),held=held,
       digest=digest::digest(list(trainB,pt,held),algo='sha256'))
}

assert_fold_isolation <- function(test,inp,lib) {
  tr <- inp$train_seasons
  if (length(tr)<MIN_TRAIN) stop('Insufficient meaningful-B training seasons for ',test)
  if (test %in% tr) stop('Test season in training set: ',test)
  if (any(season_start(tr)>=season_start(test))) stop('Chronological fold leakage at ',test)
  if (!all(tr %in% meaningful) || any(c(INACTIVE_SEASON,EXCLUDED_SEASON) %in% tr)) stop('Non-meaningful/excluded B season in training at ',test)
  if (!setequal(unique(inp$trainB$season),tr)) stop('Training data seasons differ from fold training set at ',test)
  if (any(c(INACTIVE_SEASON,EXCLUDED_SEASON) %in% inp$trainB$season)) stop('Excluded rows in training data at ',test)
  if (!identical(unique(inp$held$season),test)) stop('Held-out data contains other seasons at ',test)
  if (!setequal(lib$training_seasons,tr)) stop('Library training universe differs from fold at ',test)
  if (!isTRUE(all.equal(lib$config$amplitude_grid,B_AMP_GRID,tolerance=0))) stop('Library amplitude grid differs from 0.005:0.005:0.25 at ',test)
  TRUE
}

# Inner cross-fitted passage histories under activation shifts -1/0/+1. Inputs are
# normalised exactly as in fit_m1_v2_passage_policy(); shifted activations touch
# only causal activation coordinates, never peak truth.
build_inner_histories <- function(test,lib,inp,truth) {
  d <- prepare_surveillance_data(inp$trainB)
  if (digest::digest(d,algo='sha256')!=lib$provenance$data_hash) stop('Inner data differs from library training data at ',test)
  pt <- as.data.frame(inp$train_truth[,c('season','peak_week_decimal'),drop=FALSE])
  pt$season <- as.character(pt$season); pt$peak_week_decimal <- as.numeric(pt$peak_week_decimal)
  seasons <- lib$training_seasons
  pt <- pt[match(seasons,pt$season),,drop=FALSE]
  cfg <- lib$config
  rows <- list(); fails <- list(); iso <- list()
  for (heldout in seasons) {
    inner_seasons <- setdiff(seasons,heldout)
    il <- fit_m1_v2_library(d[d$season %in% inner_seasons,,drop=FALSE],pt[pt$season %in% inner_seasons,,drop=FALSE],
      k=cfg$k,grid_step=cfg$grid_step,tau_step=cfg$tau_step,amplitude_grid=cfg$amplitude_grid)
    if (heldout %in% il$training_seasons || !setequal(il$training_seasons,inner_seasons) || test %in% il$training_seasons ||
        any(c(INACTIVE_SEASON,EXCLUDED_SEASON) %in% il$training_seasons)) stop('Inner fold isolation violated at ',test,'/',heldout)
    if (!isTRUE(all.equal(il$config$amplitude_grid,B_AMP_GRID,tolerance=0))) stop('Inner amplitude grid changed at ',test,'/',heldout)
    iso[[length(iso)+1L]] <- data.frame(test_season=test,inner_heldout=heldout,inner_library_seasons=paste(il$training_seasons,collapse=';'),inner_isolated=TRUE,stringsAsFactors=FALSE)
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
        pp <- tryCatch(m1_v2_passage_posterior(il,prefix,activation_week=a_dec,origin_week=origin,candidate_step=PASS_STEP,max_future_weeks=PASSAGE_MAX_FUTURE),error=function(e)e)
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

# Per-season inner metrics exactly as defined in plan v2 "Exact policy evaluation".
evaluate_inner <- function(history,grid) {
  do.call(rbind,lapply(split(history,list(history$activation_shift,history$season),drop=TRUE),function(z) {
    r <- first_confirm(z,grid)
    tc <- unique(z$truth_confirm)
    r$season <- z$season[1]; r$activation_shift <- z$activation_shift[1]; r$truth_confirm <- tc
    r$FE <- as.integer(is.finite(r$confirm_origin) & r$confirm_origin<tc)
    r$EW <- ifelse(is.finite(r$confirm_origin),pmax(tc-r$confirm_origin,0),0)
    r$MISS <- as.integer(!is.finite(r$confirm_origin) | r$confirm_origin>tc+2)
    r$DP <- ifelse(is.finite(r$confirm_origin),pmax(r$confirm_origin-tc,0),UNCONFIRMED_DELAY)
    r
  }))
}

LEX_KEYS <- c('worst_shift_n_false_early','worst_shift_early_weeks_total','all_shift_n_false_early','all_shift_early_weeks_total',
  'worst_shift_n_miss_by_peak2','all_shift_n_miss_by_peak2','worst_shift_total_delay_penalty','all_shift_total_delay_penalty')

score_policies <- function(ev,grid) {
  agg <- aggregate(cbind(FE,EW,MISS,DP)~policy_id+activation_shift,data=ev,FUN=sum)
  out <- grid
  for (v in c('FE','EW','MISS','DP')) for (sh in INNER_SHIFTS) {
    a <- agg[agg$activation_shift==sh,]
    out[[paste0(v,'_shift',sh)]] <- a[[v]][match(out$policy_id,a$policy_id)]
  }
  s <- function(v) as.matrix(out[,paste0(v,'_shift',INNER_SHIFTS)])
  out$worst_shift_n_false_early <- apply(s('FE'),1,max)
  out$worst_shift_early_weeks_total <- apply(s('EW'),1,max)
  out$all_shift_n_false_early <- rowSums(s('FE'))
  out$all_shift_early_weeks_total <- rowSums(s('EW'))
  out$worst_shift_n_miss_by_peak2 <- apply(s('MISS'),1,max)
  out$all_shift_n_miss_by_peak2 <- rowSums(s('MISS'))
  out$worst_shift_total_delay_penalty <- apply(s('DP'),1,max)
  out$all_shift_total_delay_penalty <- rowSums(s('DP'))
  if (anyNA(out[,grep('_shift',names(out))])) stop('Incomplete inner policy scores.')
  out
}
# Exact lexicographic objective, then conservative deterministic tie-breaks.
select_policy <- function(sc) {
  ord <- do.call(order,c(unname(as.list(sc[,LEX_KEYS])),
    list(-sc$high_threshold,-sc$fast_drop_fraction,-sc$drop_fraction,-sc$min_post_activation,-sc$low_threshold)))
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
  decide <- function(h,d) m1_v2_passage_decision(h,d,act_dec,high_threshold=policy$high_threshold,low_threshold=policy$low_threshold,
    drop_fraction=policy$drop_fraction,fast_drop_fraction=policy$fast_drop_fraction,min_post_activation=policy$min_post_activation)
  hist <- NULL; rows <- list(); fails <- list(); fut <- list(); confirmed <- FALSE; n_calls <- 0L
  for (o in seq(ceiling(act_dec),max(held$weekF))) {
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

# Scoring after replay; truth enters only here. Delay penalty per plan v2:
# confirmed -> max(confirm-truth_confirm,0); unconfirmed -> 7.
score_path <- function(path,Tpk) {
  tc <- ceiling(Tpk)-1
  conf <- path$origin_week[path$confirmed_now]
  co <- if (length(conf)) min(conf) else NA_real_
  data.frame(truth_peak=Tpk,truth_confirm=tc,confirm_origin=co,
    branch=if (is.finite(co)) path$confirmation_branch[path$origin_week==co] else NA_character_,
    false_early=is.finite(co) && co<tc,early_weeks=if (is.finite(co)) max(tc-co,0) else 0,
    confirmed_by_peak2=is.finite(co) && co<=tc+2,miss_by_peak2=!is.finite(co) || co>tc+2,
    delay_penalty=if (is.finite(co)) max(co-tc,0) else UNCONFIRMED_DELAY,
    confirmed_after_late_horizon=is.finite(co) && co>tc+PASSAGE_LATE_WEEKS,stringsAsFactors=FALSE)
}

# One outer chronological fold.
run_fold <- function(test,Bdata=B,truth=truth0,mode='nominal') {
  full <- mode=='nominal'
  inp <- fold_inputs(test,Bdata,truth)
  lib <- fit_m1_v2_library(inp$trainB,inp$train_truth,k=8L,grid_step=.01,tau_step=.1,amplitude_grid=B_AMP_GRID)
  assert_fold_isolation(test,inp,lib)
  ih <- build_inner_histories(test,lib,inp,truth)
  fails <- ih$failures
  hist <- ih$history
  if (is.null(hist) || !nrow(hist)) stop('No inner passage histories at ',test)
  if (!all(hist$season %in% inp$train_seasons) || test %in% hist$season) stop('Shifted activations escaped inner training histories at ',test)

  ev <- evaluate_inner(hist,GRID)
  sc <- select_policy(score_policies(ev,GRID))
  sel <- sc[sc$rank==1L,,drop=FALSE]
  # Determinism: re-score on reversed grid/history order and compare.
  perm <- GRID[rev(seq_len(nrow(GRID))),]
  sc2 <- select_policy(score_policies(evaluate_inner(hist[rev(seq_len(nrow(hist))),],perm),perm))
  sel2 <- sc2[sc2$rank==1L,,drop=FALSE]
  deterministic <- identical(policy_sha(sel),policy_sha(sel2)) && sum(sc$rank==1L)==1L
  top <- sc[order(sc$rank),LEX_KEYS][1:2,]
  sel$tie_broken_by_parameters <- isTRUE(all(top[1,]==top[2,]))
  for (a in names(POLICY_AXES)) sel[[paste0('boundary_',a)]] <- sel[[a]] %in% range(POLICY_AXES[[a]])
  sel$high_threshold_hard_ceiling <- sel$high_threshold==max(POLICY_AXES$high_threshold)
  sel$inner_feasibility_veto_pass <- sel$worst_shift_n_false_early==0

  held <- inp$held
  act_nom <- truth$B_activity_weekF[truth$season==test]
  Tpk <- truth$B_peak_weekF[truth$season==test]
  outer_rows <- list(); fut <- list()
  for (sh in OUTER_SHIFTS) {
    r <- outer_path(test,sh,lib,held,act_nom+sh,sel,check_future=full)
    fails <- c(fails,r$failures)
    outer_rows[[length(outer_rows)+1L]] <- cbind(data.frame(season=test,activation_shift=sh,activation_weekF=act_nom+sh,
      first_origin=ceiling(act_nom+sh),last_origin=max(held$weekF),n_origins_replayed=nrow(r$path),replay_completed=!length(r$failures),
      final_timing_state=r$state,positive_timing_gate=identical(r$state,'confirmed'),path_sha256=path_hash(r$path),stringsAsFactors=FALSE),score_path(r$path,Tpk),
      data.frame(policy_id=sel$policy_id,policy_sha256=policy_sha(sel),policy_high=sel$high_threshold,policy_low=sel$low_threshold,
        policy_drop=sel$drop_fraction,policy_fast_drop=sel$fast_drop_fraction,policy_min_post=sel$min_post_activation,
        library_hash=lib$provenance$library_hash,stringsAsFactors=FALSE))
    if (!is.null(r$future)) fut[[length(fut)+1L]] <- r$future
  }
  base <- list(test=test,mode=mode,fold_digest=inp$digest,library_hash=lib$provenance$library_hash,policy_sha=policy_sha(sel),
    selected=sel,outer=do.call(rbind,outer_rows),history_hash=digest::digest(hist,algo='sha256'),
    failures=if (length(fails)) do.call(rbind,fails) else NULL)
  if (!full) return(base)

  # Existing pandemic-excluded selector (frozen fit_m1_v2_passage_policy defaults).
  pp <- fit_m1_v2_passage_policy(lib,inp$trainB,inp$train_truth,inp$act_train,candidate_step=PASS_STEP)
  if (!identical(pp$library_hash,lib$provenance$library_hash) || !all(pp$evaluation$season %in% inp$train_seasons)) stop('Existing selector outside fold at ',test)

  # Shift-0 inner evaluator equivalence with the frozen fitter on its sub-grid.
  hcols <- c('season','origin_week','activation_origin_week','activation_week_decimal','truth_confirm','prob_peak_passed','immediate_decline','sustained_two_week_decline','drop_from_post_activation_max')
  h0 <- hist[hist$activation_shift==0L,hcols]
  h0o <- h0[order(match(h0$season,ih$seasons),h0$origin_week),]; rownames(h0o) <- NULL
  ref_h <- pp$inner_history[,hcols]; rownames(ref_h) <- NULL
  history_equal <- isTRUE(all.equal(h0o,ref_h,tolerance=0,check.attributes=FALSE))
  sub <- GRID[GRID$high_threshold==FROZEN_SUB$high & GRID$fast_drop_fraction==FROZEN_SUB$fast & GRID$low_threshold %in% FROZEN_SUB$low &
    GRID$drop_fraction %in% FROZEN_SUB$drop & GRID$min_post_activation %in% FROZEN_SUB$min_post,]
  if (nrow(sub)!=32L) stop('Frozen sub-grid is not 32 policies.')
  ev0 <- merge(ev[ev$activation_shift==0L & ev$policy_id %in% sub$policy_id,],sub,by='policy_id')
  ref <- pp$evaluation
  key <- function(z) paste(z$season,z$high_threshold,z$low_threshold,z$drop_fraction,z$min_post_activation)
  m <- match(key(ev0),key(ref))
  if (anyNA(m) || nrow(ref)!=nrow(ev0)) stop('Frozen sub-grid rows do not align at ',test)
  ref <- ref[m,]
  sub_rows <- data.frame(test_season=test,season=ev0$season,policy_id=ev0$policy_id,high_threshold=ev0$high_threshold,low_threshold=ev0$low_threshold,
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
  dm <- merge(do.call(rbind,dec_rows),ev[ev$activation_shift==0L,c('season','policy_id','confirm_origin','branch')],by=c('season','policy_id'))
  decision_match <- nrow(dm)==length(ih$seasons)*nrow(sub) && all(identical_na(dm$decision_confirm,dm$confirm_origin) & identical_na(dm$decision_branch,dm$branch))

  # Existing selector replay under the same fixed-library/policy, test-only shift semantics,
  # checked against the frozen pandemic-excluded passage artifact.
  ex <- pp$selected[1,]
  ex_pol <- data.frame(high_threshold=ex$high_threshold,low_threshold=ex$low_threshold,drop_fraction=ex$drop_fraction,
    fast_drop_fraction=ex$fast_drop_fraction,min_post_activation=ex$min_post_activation)
  es <- ex_sel[ex_sel$test_season==test,]
  policy_repro <- nrow(es)==1L && isTRUE(all.equal(unlist(ex_pol[1,]),c(high_threshold=es$high,low_threshold=es$low,drop_fraction=es$drop,
    fast_drop_fraction=es$fast_drop,min_post_activation=es$min_post),tolerance=0,check.attributes=FALSE)) && identical(es$library_hash,lib$provenance$library_hash)
  cmp <- list()
  for (sh in OUTER_SHIFTS) {
    r <- outer_path(test,sh,lib,held,act_nom+sh,ex_pol)
    fails <- c(fails,r$failures)
    sp <- score_path(r$path,Tpk)
    a <- ex_pass[ex_pass$season==test & ex_pass$activation_shift==sh,]
    exact <- nrow(a)==1L && policy_repro && identical_na(sp$confirm_origin,a$confirm_origin) && identical_na(sp$branch,a$branch) &&
      isTRUE(all.equal(act_nom+sh,a$activation_weekF,tolerance=1e-12)) && identical(sp$false_early,as.logical(a$false_early)) &&
      identical(sp$confirmed_by_peak2,as.logical(a$confirmed_by_peak2)) && isTRUE(sp$delay_penalty==a$delay_penalty)
    cmp[[length(cmp)+1L]] <- cbind(data.frame(season=test,selector='existing_pandemic_excluded_fit_m1_v2_passage_policy',
      semantics='fixed_outer_library_policy_shift_test_only',activation_shift=sh,path_sha256=path_hash(r$path),stringsAsFactors=FALSE),sp,
      data.frame(policy_high=ex$high_threshold,policy_low=ex$low_threshold,policy_drop=ex$drop_fraction,policy_fast_drop=ex$fast_drop_fraction,
        policy_min_post=ex$min_post_activation,artifact_confirm_origin=if (nrow(a)) a$confirm_origin else NA_real_,
        artifact_branch=if (nrow(a)) a$branch else NA_character_,artifact_delay_penalty=if (nrow(a)) a$delay_penalty else NA_real_,
        reproduction_exact=exact,stringsAsFactors=FALSE))
  }

  # Sustained-only diagnostic: robust sustained parameters, fast branch disabled.
  so_pol <- data.frame(high_threshold=1,low_threshold=sel$low_threshold,drop_fraction=sel$drop_fraction,fast_drop_fraction=1,min_post_activation=sel$min_post_activation)
  so <- list()
  for (sh in OUTER_SHIFTS) {
    r <- outer_path(test,sh,lib,held,act_nom+sh,so_pol)
    fails <- c(fails,r$failures)
    sp <- score_path(r$path,Tpk)
    hb <- r$path$confirmation_branch %in% 'high_posterior_decline'
    through_first <- if (is.finite(sp$confirm_origin)) r$path$origin_week<=sp$confirm_origin else rep(TRUE,nrow(r$path))
    so[[length(so)+1L]] <- cbind(data.frame(season=test,activation_shift=sh,policy_high=1,policy_fast_drop=1,policy_low=so_pol$low_threshold,
      policy_drop=so_pol$drop_fraction,policy_min_post=so_pol$min_post_activation,n_origins_replayed=nrow(r$path),
      n_origins_high_posterior_branch_any=sum(hb),n_origins_high_posterior_branch_through_first_confirm=sum(hb & through_first),
      high_branch_origins_zero_positivity=all(held$p[match(r$path$origin_week[hb],held$weekF)]==0),path_sha256=path_hash(r$path),stringsAsFactors=FALSE),sp)
  }

  # Raw B0 peak-posterior reproduction against artifacts/v3-m1-b0-excluding-pandemic-v1.
  b0r <- list()
  first <- ceiling(act_nom); last <- floor(Tpk-1e-8)-1L
  for (o in seq.int(first,last)) {
    s <- m1_v2_peak_posterior(lib,held,act_nom,o,candidate_step=B0_STEP,max_future_weeks=B0_MAX_FUTURE)$summary[1,]
    rr <- b0_pred[b0_pred$season==test & b0_pred$origin_weekF==o,]
    got <- c(s$peak_mean,s$peak_median,s$peak_map,s$peak_q05,s$peak_q95)
    want <- if (nrow(rr)==1L) c(rr$pred_peak_mean,rr$pred_peak_median,rr$pred_peak_map,rr$q05,rr$q95) else rep(NA_real_,5)
    d <- max(abs(got-want))
    b0r[[length(b0r)+1L]] <- data.frame(season=test,origin_weekF=o,pred_peak_mean=s$peak_mean,artifact_pred_peak_mean=want[1],
      max_abs_diff_mean_median_map_q05_q95=d,library_hash=lib$provenance$library_hash,
      artifact_library_hash=b0_libs$library_hash[match(test,b0_libs$test_season)],pass=is.finite(d) && d<=B0_TOL &&
      identical(lib$provenance$library_hash,b0_libs$library_hash[match(test,b0_libs$test_season)]),stringsAsFactors=FALSE)
  }
  b0r <- do.call(rbind,b0r)
  b0_complete <- setequal(b0r$origin_weekF,b0_pred$origin_weekF[b0_pred$season==test])

  ise <- merge(ev[ev$policy_id==sel$policy_id,c('policy_id','activation_shift','season','truth_confirm','confirm_origin','branch','FE','EW','MISS','DP')],
    data.frame(test_season=test,policy_sha256=policy_sha(sel)),by=NULL)
  ise <- ise[order(ise$activation_shift,match(ise$season,ih$seasons)),c('test_season','policy_id','policy_sha256',setdiff(names(ise),c('test_season','policy_id','policy_sha256')))]
  names(ise)[names(ise) %in% c('FE','EW','MISS','DP')] <- c('false_early','early_weeks','miss_by_peak2','delay_penalty')

  ledger <- data.frame(test_season=test,n_train=length(inp$train_seasons),training_seasons=paste(inp$train_seasons,collapse=';'),
    excluded_season_in_training=EXCLUDED_SEASON %in% inp$train_seasons,inactive_season_in_training=INACTIVE_SEASON %in% inp$train_seasons,
    fold_input_digest=inp$digest,library_hash=lib$provenance$library_hash,existing_selector_library_hash=es$library_hash,
    amplitude_grid_ok=isTRUE(all.equal(lib$config$amplitude_grid,B_AMP_GRID,tolerance=0)),passage_candidate_step=PASS_STEP,
    passage_max_future_weeks=PASSAGE_MAX_FUTURE,outer_fold_isolation_asserted=TRUE,inner_fold_isolation_asserted=all(ih$isolation$inner_isolated),
    shifted_activation_confined_to_inner=TRUE,n_inner_seasons=length(ih$seasons),
    n_inner_rows_shift_m1=sum(hist$activation_shift==-1L),n_inner_rows_shift_0=sum(hist$activation_shift==0L),n_inner_rows_shift_p1=sum(hist$activation_shift==1L),
    inner_history_shift0_equals_fitter=history_equal,subgrid_evaluator_match=all(sub_rows$match),decision_fn_match=decision_match,
    selection_deterministic=deterministic,raw_B0_reproduced=all(b0r$pass) && b0_complete,inner_history_sha256=base$history_hash,stringsAsFactors=FALSE)
  sel_out <- cbind(data.frame(test_season=test,policy_sha256=policy_sha(sel),selection_deterministic=deterministic,
    inner_worst_shift_n_false_early=sel$worst_shift_n_false_early,inner_worst_shift_n_miss_by_peak2=sel$worst_shift_n_miss_by_peak2,
    inner_worst_shift_total_delay_penalty=sel$worst_shift_total_delay_penalty,stringsAsFactors=FALSE),sel)
  c(base,list(ledger=ledger,selected_out=sel_out,scores=cbind(test_season=test,sc[order(sc$rank),]),history=hist,inner_sel=ise,
    future=if (length(fut)) do.call(rbind,fut) else NULL,subgrid=sub_rows,comparison=do.call(rbind,cmp),sustained=do.call(rbind,so),b0=b0r,
    failures=if (length(fails)) do.call(rbind,fails) else NULL))
}

# Exclusion-perturbation data (2018-19 inactive; 2019-20 pandemic) and truth perturbation.
perturb_season <- function(Bdata,season) {
  i <- Bdata$season==season
  if (!any(i)) stop(season,' rows missing from B panel.')
  out <- Bdata
  out$y[i] <- pmin(out$N[i],round(out$y[i]*3)+25)
  storage.mode(out$y) <- storage.mode(Bdata$y)
  out$p[i] <- out$y[i]/out$N[i]
  if (identical(digest::digest(Bdata[i,],algo='sha256'),digest::digest(out[i,],algo='sha256'))) stop(season,' perturbation is a no-op.')
  if (!identical(Bdata[!i,],out[!i,])) stop('Perturbation touched rows outside ',season)
  out
}
B_pert <- list(inactive_perturbed=perturb_season(B,INACTIVE_SEASON),pandemic_perturbed=perturb_season(B,EXCLUDED_SEASON))
pert_season <- c(inactive_perturbed=INACTIVE_SEASON,pandemic_perturbed=EXCLUDED_SEASON)
post_of <- function(s) test_seasons[season_start(test_seasons)>season_start(s)]
truth_pert_for <- function(test) { z <- truth0; z$B_peak_weekF[z$season==test] <- z$B_peak_weekF[z$season==test]+TRUTH_PERTURB_WEEKS; z }

jobs <- c(lapply(test_seasons,function(s) list(test=s,mode='nominal')),
  lapply(test_seasons,function(s) list(test=s,mode='truth_perturbed')),
  lapply(post_of(INACTIVE_SEASON),function(s) list(test=s,mode='inactive_perturbed')),
  lapply(post_of(EXCLUDED_SEASON),function(s) list(test=s,mode='pandemic_perturbed')))
cat('Running',length(jobs),'fold jobs on',N_CORES,'cores\n')
res <- parallel::mclapply(jobs,function(j) tryCatch(
  run_fold(j$test,Bdata=if (j$mode %in% names(B_pert)) B_pert[[j$mode]] else B,truth=if (j$mode=='truth_perturbed') truth_pert_for(j$test) else truth0,mode=j$mode),
  error=function(e) structure(list(message=conditionMessage(e)),class='fold_error')),mc.cores=N_CORES,mc.preschedule=FALSE)
job_err <- vapply(res,function(r) inherits(r,'fold_error') || inherits(r,'try-error') || is.null(r),logical(1))
if (any(job_err)) {
  msg <- vapply(res[job_err],function(r) if (is.list(r) && !is.null(r$message)) r$message else paste(as.character(r),collapse=' '),character(1))
  stop('Fold job(s) failed:\n',paste(vapply(jobs[job_err],function(j) paste0(j$test,'/',j$mode),character(1)),msg,sep=': ',collapse='\n'))
}
mode_of <- vapply(jobs,`[[`,character(1),'mode')
bind <- function(rs,field) { z <- Filter(Negate(is.null),lapply(rs,`[[`,field)); if (length(z)) do.call(rbind,z) else data.frame() }
nom <- res[mode_of=='nominal']; tpr <- res[mode_of=='truth_perturbed']; xpr <- res[mode_of %in% names(B_pert)]; xmode <- mode_of[mode_of %in% names(B_pert)]
names(nom) <- vapply(nom,`[[`,character(1),'test')

ledger <- bind(nom,'ledger')
selected <- bind(nom,'selected_out')
scores <- bind(nom,'scores')
inner_hist <- bind(nom,'history')
inner_sel <- bind(nom,'inner_sel')
outer_all <- bind(nom,'outer')
outer_nom <- outer_all[outer_all$activation_shift==0L,]
outer_sens <- cbind(semantics='fixed_outer_library_policy_shift_test_only',outer_all)
future <- bind(nom,'future')
subgrid <- bind(nom,'subgrid')
comparison <- bind(nom,'comparison')
sustained <- bind(nom,'sustained')
b0_checks <- bind(nom,'b0')
failures <- bind(c(nom,tpr,xpr),'failures')
if (!nrow(failures)) failures <- data.frame(season=character(0),activation_shift=integer(0),origin_weekF=numeric(0),stage=character(0),message=character(0))

# Side-by-side comparison rows: existing selector (reproduced) and robust selector.
rob_cmp <- cbind(data.frame(season=outer_all$season,selector='activation_robust_v2',semantics='fixed_outer_library_policy_shift_test_only',
  activation_shift=outer_all$activation_shift,path_sha256=outer_all$path_sha256,stringsAsFactors=FALSE),
  outer_all[,names(score_path(data.frame(origin_week=numeric(0),confirmed_now=logical(0),confirmation_branch=character(0)),1))],
  data.frame(policy_high=outer_all$policy_high,policy_low=outer_all$policy_low,policy_drop=outer_all$policy_drop,policy_fast_drop=outer_all$policy_fast_drop,
    policy_min_post=outer_all$policy_min_post,artifact_confirm_origin=NA_real_,artifact_branch=NA_character_,artifact_delay_penalty=NA_real_,reproduction_exact=NA))
comparison_all <- rbind(comparison,rob_cmp)
summ_sel <- function(z) data.frame(selector=z$selector[1],activation_shift=z$activation_shift[1],n_seasons=nrow(z),n_false_early=sum(z$false_early),
  early_weeks_total=sum(z$early_weeks),n_confirmed_by_peak2=sum(z$confirmed_by_peak2),mean_delay_penalty=mean(z$delay_penalty),
  median_delay_penalty=median(z$delay_penalty),max_delay_penalty=max(z$delay_penalty),stringsAsFactors=FALSE)
comparison_summary <- do.call(rbind,lapply(split(comparison_all,list(comparison_all$selector,comparison_all$activation_shift),drop=TRUE),summ_sel))

# Outer truth perturbation: paths/policy/library identical, scoring changes.
truth_rows <- do.call(rbind,lapply(tpr,function(r) {
  n <- nom[[r$test]]
  a <- n$outer[order(n$outer$activation_shift),]; b <- r$outer[order(r$outer$activation_shift),]
  data.frame(season=r$test,activation_shift=a$activation_shift,truth_shift_weeks=TRUTH_PERTURB_WEEKS,
    nominal_path_sha256=a$path_sha256,perturbed_path_sha256=b$path_sha256,path_identical=a$path_sha256==b$path_sha256,
    policy_identical=identical(n$policy_sha,r$policy_sha),library_identical=identical(n$library_hash,r$library_hash),
    inner_history_identical=identical(n$history_hash,r$history_hash),
    nominal_truth_confirm=a$truth_confirm,perturbed_truth_confirm=b$truth_confirm,scoring_changed=a$truth_confirm!=b$truth_confirm,
    pass=a$path_sha256==b$path_sha256 & identical(n$policy_sha,r$policy_sha) & identical(n$library_hash,r$library_hash) &
      identical(n$history_hash,r$history_hash) & a$truth_confirm!=b$truth_confirm,stringsAsFactors=FALSE)
}))

# 2018-19 and 2019-20 exclusion-perturbation invariance for later folds.
pert_rows <- do.call(rbind,Map(function(r,md) {
  n <- nom[[r$test]]; s <- pert_season[[md]]
  same_paths <- identical(n$outer$path_sha256,r$outer$path_sha256)
  in_tr <- s %in% fold_train_seasons(r$test)
  data.frame(test_season=r$test,perturbed_season=s,mode=md,perturbed_season_in_training=in_tr,
    fold_input_digest_identical=identical(n$fold_digest,r$fold_digest),library_identical=identical(n$library_hash,r$library_hash),
    inner_history_identical=identical(n$history_hash,r$history_hash),policy_identical=identical(n$policy_sha,r$policy_sha),outer_paths_identical=same_paths,
    perturbation=paste0(s,' y_B -> min(N_B, round(3*y_B)+25)'),
    pass=!in_tr && identical(n$fold_digest,r$fold_digest) && identical(n$library_hash,r$library_hash) &&
      identical(n$history_hash,r$history_hash) && identical(n$policy_sha,r$policy_sha) && same_paths,stringsAsFactors=FALSE)
},xpr,xmode))

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
states_ok <- all(all_states %in% TIMING_STATES) && all(outer_all$final_timing_state %in% TIMING_STATES[2:3]) &&
  identical(outer_all$positive_timing_gate,outer_all$final_timing_state=='confirmed')
inact_pert <- pert_rows[pert_rows$perturbed_season==INACTIVE_SEASON,]
no_event <- rbind(prefix_rows,
  data.frame(check='prefix_window_coverage',season=INACTIVE_SEASON,prefix_week=NA,evaluated=TRUE,activated=NA,
    value=paste0(length(prefix_weeks),' prefixes weeks ',min(prefix_weeks),'-',max(prefix_weeks)),pass=length(prefix_weeks)>0L && all(B_WINDOW[1]:B_WINDOW[2] %in% prefix_weeks)),
  data.frame(check='full_season_detector_reproduces_B_window8_40_rds',season='all',prefix_week=NA,evaluated=TRUE,activated=NA,value=as.character(detector_reproduced),pass=isTRUE(detector_reproduced)),
  data.frame(check='no_passage_posterior_without_activation',season=INACTIVE_SEASON,prefix_week=NA,evaluated=TRUE,activated=FALSE,
    value=paste0('posterior_calls=',inactive_path$n_posterior_calls,';rows=',nrow(inactive_path$path)),pass=inactive_path$n_posterior_calls==0L && nrow(inactive_path$path)==0L),
  data.frame(check='m1_b_timing_state',season=INACTIVE_SEASON,prefix_week=NA,evaluated=TRUE,activated=FALSE,value=inactive_path$state,pass=identical(inactive_path$state,'inactive_no_timing_event')),
  data.frame(check='positive_timing_gate',season=INACTIVE_SEASON,prefix_week=NA,evaluated=TRUE,activated=FALSE,value='FALSE',pass=!identical(inactive_path$state,'confirmed')),
  data.frame(check='three_state_contract',season='all',prefix_week=NA,evaluated=TRUE,activated=NA,value=paste(sort(unique(all_states)),collapse=';'),pass=states_ok),
  data.frame(check='excluded_from_training_and_scoring',season=INACTIVE_SEASON,prefix_week=NA,evaluated=TRUE,activated=NA,
    value='not in test/training/inner seasons',pass=!(INACTIVE_SEASON %in% c(test_seasons,inner_hist$season,unlist(strsplit(ledger$training_seasons,';',fixed=TRUE))))),
  data.frame(check='exclusion_perturbation_invariance_later_folds',season=INACTIVE_SEASON,prefix_week=NA,evaluated=TRUE,activated=NA,
    value=paste0(sum(inact_pert$pass),'/',nrow(inact_pert),' later folds invariant'),pass=nrow(inact_pert)==length(post_of(INACTIVE_SEASON)) && all(inact_pert$pass)),
  data.frame(check='pseudo_activation_diagnostic',season=INACTIVE_SEASON,prefix_week=NA,evaluated=FALSE,activated=NA,value='optional non-decision diagnostic not run',pass=NA))

# Integrity tests (plan v2 items 1-11) and supporting checks.
nn <- outer_nom
fe_m1 <- sum(outer_all$false_early[outer_all$activation_shift==-1L]); fe_p1 <- sum(outer_all$false_early[outer_all$activation_shift==1L])
page_r_hash_end <- hash_dir(page_r_files)
existing_hash_end <- hash_dir(existing_files)
plan_sha_end <- sha256_file(PLAN_PATH)
page_r_unchanged <- identical(page_r_hash_start,page_r_hash_end) && identical(sort(list.files('PAGe/R',full.names=TRUE,recursive=TRUE)),page_r_files) &&
  page_r_git_clean_start && identical(system2('git',c('diff','--quiet','HEAD','--','PAGe/R')),0L)
pand_pert <- pert_rows[pert_rows$perturbed_season==EXCLUDED_SEASON,]
existing_repro <- comparison[comparison$reproduction_exact %in% c(TRUE,FALSE),]
integrity <- c(
  outer_fold_isolation=all(ledger$outer_fold_isolation_asserted),
  inner_fold_isolation=all(ledger$inner_fold_isolation_asserted) && all(ledger$shifted_activation_confined_to_inner),
  pandemic_2019_20_excluded=!any(ledger$excluded_season_in_training) && !(EXCLUDED_SEASON %in% c(test_seasons,inner_hist$season,outer_all$season,b0_checks$season)) &&
    nrow(pand_pert)==length(post_of(EXCLUDED_SEASON)) && all(pand_pert$pass),
  future_perturbation_invariance_all_shifts=nrow(future)>0L && all(future$invariant) && setequal(unique(future$activation_shift),OUTER_SHIFTS),
  truth_perturbation_scoring_only=nrow(truth_rows)==length(OUTER_SHIFTS)*length(test_seasons) && all(truth_rows$pass),
  raw_B0_reproduction=nrow(b0_checks)>0L && all(ledger$raw_B0_reproduced),
  shift0_inner_evaluator_matches_frozen_fitter=all(ledger$inner_history_shift0_equals_fitter) && all(ledger$subgrid_evaluator_match) && all(ledger$decision_fn_match),
  deterministic_policy_selection=all(ledger$selection_deterministic),
  prefix_2018_19_no_activation=all(prefix_rows$pass) && no_event$pass[no_event$check=='prefix_window_coverage'],
  source_plan_hashes_recorded_unchanged=identical(plan_sha_start,plan_sha_end) && identical(policy_doc_sha_start,sha256_file(POLICY_DOC)),
  frozen_page_r_unchanged=page_r_unchanged,
  existing_artifacts_unchanged=identical(existing_hash_start,existing_hash_end),
  existing_selector_reproduction_exact=nrow(existing_repro)==length(OUTER_SHIFTS)*length(test_seasons) && all(existing_repro$reproduction_exact),
  no_event_contract=all(no_event$pass,na.rm=TRUE),
  amplitude_grid_retained=all(ledger$amplitude_grid_ok),
  no_silent_inner_history_failures=!any(grepl('^inner_history',failures$stage))
)
so_operative_ok <- all(sustained$n_origins_high_posterior_branch_through_first_confirm==0L) && !any(sustained$branch %in% 'high_posterior_decline')
so_literal_ok <- all(sustained$n_origins_high_posterior_branch_any==0L)
criteria <- data.frame(
  group=c(rep('nominal_outer',5),rep('outer_activation_robustness',2),'inner_feasibility_veto',rep('integrity',length(integrity)),rep('diagnostic_non_veto',2)),
  criterion=c('n_false_early_eq_0','n_confirmed_by_peak2_ge_4','median_delay_penalty_le_2','mean_delay_penalty_le_2.5','no_unexpected_replay_failures',
    'shift_m1_n_false_early_eq_0','shift_p1_n_false_early_eq_0','all_folds_inner_worst_shift_n_false_early_eq_0',names(integrity),
    'sustained_only_no_high_posterior_branch_through_first_confirmation','sustained_only_no_high_posterior_branch_any_origin'),
  value=c(sum(nn$false_early),sum(nn$confirmed_by_peak2),median(nn$delay_penalty),mean(nn$delay_penalty),nrow(failures),fe_m1,fe_p1,
    max(selected$inner_worst_shift_n_false_early),as.numeric(integrity),
    sum(sustained$n_origins_high_posterior_branch_through_first_confirm),sum(sustained$n_origins_high_posterior_branch_any)),
  pass=c(sum(nn$false_early)==0,sum(nn$confirmed_by_peak2)>=4,median(nn$delay_penalty)<=2,mean(nn$delay_penalty)<=2.5,nrow(failures)==0L && all(outer_all$replay_completed),
    fe_m1==0,fe_p1==0,all(selected$inner_worst_shift_n_false_early==0),integrity,so_operative_ok,so_literal_ok),
  stringsAsFactors=FALSE)
criteria$n_eligible_seasons <- length(test_seasons)
decisive <- criteria$group!='diagnostic_non_veto'
promising <- all(criteria$pass[decisive])
ex_nom <- comparison[comparison$activation_shift==0L,]
verdict <- data.frame(
  historically_promising_second_look=promising,
  study_type='second_look_historical_robustness_not_clean_holdout',
  eligibility=if (promising) 'v3_shadow_use_only' else 'stop_hard_M1B_passage_gating',
  failure_decision=if (promising) 'NA' else 'retain raw M1-B0 peak location; passage state descriptive/shadow only; no hard M1-B passage gate in M2-B; future M2-B uses continuous posterior uncertainty',
  peak_location_model='raw_M1_B0_unchanged',
  excluded_B_season=EXCLUDED_SEASON,exclusion_reason=EXCLUSION_REASON,no_event_season=INACTIVE_SEASON,
  production_hard_gate_eligible=FALSE,governed=FALSE,prospective_2026_27_required=TRUE,
  n_eligible_seasons=length(test_seasons),
  n_false_early_nominal=sum(nn$false_early),n_false_early_shift_m1=fe_m1,n_false_early_shift_p1=fe_p1,
  n_confirmed_by_peak2_nominal=sum(nn$confirmed_by_peak2),median_delay_penalty_nominal=median(nn$delay_penalty),mean_delay_penalty_nominal=mean(nn$delay_penalty),
  existing_n_confirmed_by_peak2_nominal=sum(ex_nom$confirmed_by_peak2),existing_median_delay_penalty_nominal=median(ex_nom$delay_penalty),
  existing_mean_delay_penalty_nominal=mean(ex_nom$delay_penalty),
  n_unconfirmed_nominal=sum(!is.finite(nn$confirm_origin)),max_false_early_weeks_nominal=max(nn$early_weeks),
  n_failed_criteria=sum(!criteria$pass[decisive]),failed_criteria=paste(criteria$criterion[decisive & !criteria$pass],collapse=';'),
  stringsAsFactors=FALSE)

manifest <- rbind(
  data.frame(role='audited_plan_sha_before_run',path=PLAN_PATH,sha256=plan_sha_start),
  data.frame(role='B_season_policy',path=POLICY_DOC,sha256=policy_doc_sha_start),
  data.frame(role='benchmark_script',path=SCRIPT_PATH,sha256=sha256_file(SCRIPT_PATH)),
  data.frame(role=c('canonical_panel','timing_contract','timing_contract_metadata','B_activity_detector','M0_A_rule_params','raw_B0_script','existing_passage_script'),
    path=ref_inputs,sha256=unname(hash_dir(ref_inputs))),
  data.frame(role='raw_B0_reference_artifact',path=list.files(B0_DIR,full.names=TRUE),sha256=unname(hash_dir(list.files(B0_DIR,full.names=TRUE)))),
  data.frame(role='existing_passage_reference_artifact',path=list.files(EXISTING_DIR,full.names=TRUE),sha256=unname(hash_dir(list.files(EXISTING_DIR,full.names=TRUE)))),
  data.frame(role='all_existing_artifacts_aggregate',path=paste0('artifacts/** (',length(existing_files),' files, excluding ',OUT,')'),
    sha256=digest::digest(unname(existing_hash_end),algo='sha256')),
  data.frame(role='frozen_PAGe_R',path=page_r_files,sha256=unname(page_r_hash_end)))

config <- data.frame(
  key=c('benchmark','study_type','result_scope','plan_path','plan_sha256','season_policy_path','excluded_B_seasons','exclusion_reason','no_event_season',
    'eligible_test_seasons','fold_ledger','policy_grid_size','high_threshold','low_threshold','drop_fraction','fast_drop_fraction',
    'min_post_activation','inner_activation_shifts','outer_activation_shifts','outer_shift_semantics','selection_keys','tie_break','inner_feasibility_veto',
    'amplitude_grid','passage_candidate_step','passage_max_future_weeks','inner_history_last_origin','unconfirmed_delay_penalty','outer_replay_horizon',
    'truth_perturbation_weeks','exclusion_perturbation','B_activity_window','raw_B0_reproduction','sustained_only_policy','sustained_only_assertion',
    'pseudo_activation_diagnostic','dryrun'),
  value=c('v3-m1-b-passage-robustness-v2','second_look_historical_robustness_not_clean_holdout','v3_shadow_eligibility_only_not_production_gate',PLAN_PATH,plan_sha_start,
    POLICY_DOC,EXCLUDED_SEASON,EXCLUSION_REASON,INACTIVE_SEASON,paste(test_seasons,collapse=';'),file.path(B0_DIR,'fold_ledger.csv'),
    nrow(GRID),paste(POLICY_AXES$high_threshold,collapse=';'),paste(POLICY_AXES$low_threshold,collapse=';'),paste(POLICY_AXES$drop_fraction,collapse=';'),
    paste(POLICY_AXES$fast_drop_fraction,collapse=';'),paste(POLICY_AXES$min_post_activation,collapse=';'),paste(INNER_SHIFTS,collapse=';'),paste(OUTER_SHIFTS,collapse=';'),
    'library and policy fitted at nominal training activation; held-out activation shifted only',paste(LEX_KEYS,collapse='>'),
    'higher high_threshold>larger fast_drop_fraction>larger drop_fraction>larger min_post_activation>higher low_threshold',
    'outer fold fails passage eligibility if selected inner_worst_shift_n_false_early>0','0.005:0.005:0.25',
    PASS_STEP,PASSAGE_MAX_FUTURE,paste0('min(max(inner heldout weekF), truth_confirm+',PASSAGE_LATE_WEEKS,') as frozen fit_m1_v2_passage_policy (training truth only)'),
    UNCONFIRMED_DELAY,'ceiling(activation) .. max(held$weekF); held-out truth used only for scoring',TRUTH_PERTURB_WEEKS,
    paste0(INACTIVE_SEASON,' and ',EXCLUDED_SEASON,' y_B -> min(N_B, round(3*y_B)+25), later folds must be identical'),paste(B_WINDOW,collapse='-'),
    paste0('m1_v2_peak_posterior step ',B0_STEP,' max_future ',B0_MAX_FUTURE,' tol ',B0_TOL,' vs ',B0_DIR),
    'high_threshold=1; fast_drop_fraction=1; robust sustained parameters reused',
    'decisive-free diagnostic: no high_posterior_decline through first confirmation (operative); any-origin count reported separately',
    'not run (optional, no decision weight)',as.character(DRYRUN)),
  stringsAsFactors=FALSE)

cat('\nSelected policies:\n'); print(selected[,c('test_season','high_threshold','low_threshold','drop_fraction','fast_drop_fraction','min_post_activation','inner_worst_shift_n_false_early','inner_worst_shift_n_miss_by_peak2','inner_worst_shift_total_delay_penalty')],row.names=FALSE)
cat('\nOuter replay:\n'); print(outer_all[,c('season','activation_shift','confirm_origin','branch','truth_confirm','false_early','confirmed_by_peak2','delay_penalty')],row.names=FALSE)
cat('\nComparison summary:\n'); print(comparison_summary,row.names=FALSE)
cat('\nAcceptance:\n'); print(criteria[,c('group','criterion','value','pass')],row.names=FALSE)
cat('\nhistorically_promising_second_look =',promising,'\n')
if (nrow(failures)) { cat('\nFailures:\n'); print(failures,row.names=FALSE) }

if (DRYRUN) { cat('\nDRYRUN: nothing written.\n'); quit(save='no') }

# Write once; everything above is computed before the directory is created.
if (dir.exists(OUT) && length(list.files(OUT,all.files=TRUE,no..=TRUE))>0L) stop('Refusing to overwrite non-empty ',OUT)
dir.create(OUT,recursive=TRUE,showWarnings=FALSE)
wcsv <- function(x,f) write.csv(x,file.path(OUT,f),row.names=FALSE)
wcsv(ledger,'outer_fold_ledger.csv')
wcsv(selected,'selected_policy_by_outer_fold.csv')
wcsv(scores,'policy_scores_by_outer_fold.csv')
wcsv(inner_hist,'inner_passage_history.csv')
wcsv(inner_sel,'inner_selected_policy_evaluation.csv')
wcsv(outer_nom,'outer_passage_by_season.csv')
wcsv(outer_sens,'outer_activation_sensitivity.csv')
wcsv(comparison_all,'comparison_existing_policy.csv')
wcsv(comparison_summary,'comparison_summary.csv')
wcsv(subgrid,'frozen_subgrid_equivalence.csv')
wcsv(sustained,'sustained_only_diagnostic.csv')
wcsv(no_event,'no_event_prefix_check.csv')
wcsv(pert_rows,'exclusion_perturbation_checks.csv')
wcsv(future,'future_perturbation_checks.csv')
wcsv(truth_rows,'truth_perturbation_checks.csv')
wcsv(b0_checks,'raw_B0_reproduction_checks.csv')
wcsv(failures,'failures.csv')
wcsv(criteria,'acceptance_criteria.csv')
wcsv(verdict,'overall_verdict.csv')
wcsv(manifest,'source_manifest.csv')
wcsv(config,'benchmark_config.csv')
cat('\nWrote',length(list.files(OUT)),'files to',OUT,'\n')
