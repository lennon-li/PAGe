#!/usr/bin/env Rscript

options(stringsAsFactors=FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

if(!requireNamespace('digest',quietly=TRUE)) stop('Package `digest` required.')

PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
DETECT_PATH <- 'artifacts/v3-a-rule-transfer-to-b-v1/B_window8_40_detection.rds'
B0_DIR <- 'artifacts/v3-m1-b0-excluding-pandemic-v1'
POLICY_DOC <- 'docs/v3-m1-b-season-policy-2026-09-26.md'
OUT <- 'artifacts/v3-m1-b-passage-excluding-pandemic-v1'
EXCLUDED <- '2019-20'
INACTIVE <- '2018-19'
AMP_GRID <- seq(.005,.25,by=.005)
PASS_STEP <- .2
PASS_MAX_FUTURE <- 12
SHIFTS <- c(-1L,0L,1L)

if(dir.exists(OUT) && length(list.files(OUT,all.files=TRUE,no..=TRUE))) stop('Output exists/nonempty: ',OUT)
dir.create(OUT,recursive=TRUE,showWarnings=FALSE)
sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))

panel <- read.csv(PANEL_PATH,check.names=FALSE)
truth <- read.csv(TIMING_PATH,check.names=FALSE)
folds <- read.csv(file.path(B0_DIR,'fold_ledger.csv'),check.names=FALSE)
B <- data.frame(season=as.character(panel$season),weekF=panel$weekF,y=panel$y_B,N=panel$N_B,p=panel$p_B)
B <- B[order(season_start(B$season),B$weekF),]

contract_sha <- sha256_file(TIMING_PATH)
detect_sha <- sha256_file(DETECT_PATH)
make_activation <- function(seasons){
  z <- truth[match(seasons,truth$season),c('season','B_activity_integer','B_activity_weekF')]
  if(anyNA(z$season)||any(!is.finite(z$B_activity_integer))||any(!is.finite(z$B_activity_weekF))) stop('Missing activation.')
  out <- data.frame(season=as.character(z$season),activation_origin_week=as.numeric(z$B_activity_integer),activation_week_decimal=as.numeric(z$B_activity_weekF),stringsAsFactors=FALSE)
  attr(out,'m0_loso_context_id') <- paste0('v3-B-activity-A-rule-transfer-w8_40:',contract_sha,':pandemic-excluded')
  attr(out,'activation_provenance_id') <- digest::digest(list(semantics='v3-B-activity-research-adapter-pandemic-excluded',payload=.m1_v2_activation_payload(out),timing_contract_sha256=contract_sha,detection_sha256=detect_sha,excluded=EXCLUDED),algo='sha256')
  attr(out,'activation_payload_hash') <- digest::digest(.m1_v2_activation_payload(out),algo='sha256')
  class(out) <- c('page_m1_v2_activation_table','data.frame')
  out
}

eligible <- as.character(folds$test_season[folds$eligible])
if(any(eligible %in% c(EXCLUDED,INACTIVE))) stop('Excluded/inactive season is eligible.')

replay <- function(lib,policy,held,act,T,shift){
  a <- act+shift
  first <- ceiling(a)
  last <- max(held$weekF)
  hist <- NULL; confirm <- NA_real_; branch <- NA_character_
  for(o in seq.int(first,last)){
    pp <- m1_v2_passage_posterior(lib,held,a,o,candidate_step=PASS_STEP,max_future_weeks=PASS_MAX_FUTURE)
    hist <- rbind(hist,pp)
    dec <- m1_v2_passage_decision(hist,held,a,
      high_threshold=policy$high_threshold,
      low_threshold=policy$low_threshold,
      drop_fraction=policy$drop_fraction,
      fast_drop_fraction=policy$fast_drop_fraction,
      min_post_activation=policy$min_post_activation)
    if(!is.finite(confirm) && isTRUE(dec$peak_reached_or_passed)) { confirm <- o; branch <- dec$confirmation_branch }
  }
  tc <- ceiling(T)-1
  delay_penalty <- if(is.finite(confirm)) max(confirm-tc,0) else 7
  data.frame(activation_shift=shift,activation_weekF=a,truth_peak=T,truth_confirm=tc,
             confirm_origin=confirm,branch=branch,false_early=is.finite(confirm)&&confirm<tc,
             early_weeks=if(is.finite(confirm)) max(tc-confirm,0) else 0,
             confirmed_by_peak2=is.finite(confirm)&&confirm<=tc+2,
             delay_penalty=delay_penalty,stringsAsFactors=FALSE)
}

rows <- list(); policies <- list(); failures <- list()
for(test in eligible){
  fr <- folds[folds$test_season==test,]
  tr <- if(nzchar(fr$training_seasons)) strsplit(fr$training_seasons,';',fixed=TRUE)[[1]] else character(0)
  if(any(tr %in% c(EXCLUDED,INACTIVE))) stop('Excluded/inactive season entered training for ',test)
  if(any(season_start(tr)>=season_start(test))) stop('Chronological leakage.')
  train <- B[B$season %in% tr,]
  pt <- truth[match(tr,truth$season),c('season','B_peak_weekF')]
  names(pt)[2] <- 'peak_week_decimal'
  act_table <- make_activation(tr)
  lib <- fit_m1_v2_library(train,pt,k=8L,grid_step=.01,tau_step=.1,amplitude_grid=AMP_GRID)
  pol <- tryCatch(fit_m1_v2_passage_policy(lib,train,pt,act_table,candidate_step=PASS_STEP),error=function(e)e)
  if(inherits(pol,'error')) { failures[[length(failures)+1L]] <- data.frame(season=test,stage='fit_passage_policy',message=conditionMessage(pol)); next }
  sel <- pol$selected[1,]
  policies[[length(policies)+1L]] <- data.frame(test_season=test,n_train=length(tr),training_seasons=paste(tr,collapse=';'),
    high=sel$high_threshold,low=sel$low_threshold,drop=sel$drop_fraction,fast_drop=sel$fast_drop_fraction,min_post=sel$min_post_activation,
    library_hash=lib$provenance$library_hash,stringsAsFactors=FALSE)
  held <- B[B$season==test,]
  act <- truth$B_activity_weekF[truth$season==test]
  T <- truth$B_peak_weekF[truth$season==test]
  for(sh in SHIFTS){
    rr <- tryCatch(replay(lib,sel,held,act,T,sh),error=function(e)e)
    if(inherits(rr,'error')) failures[[length(failures)+1L]] <- data.frame(season=test,stage=paste0('replay_shift_',sh),message=conditionMessage(rr))
    else { rr$season <- test; rows[[length(rows)+1L]] <- rr }
  }
}

pass <- do.call(rbind,rows); pass <- pass[,c('season',setdiff(names(pass),'season'))]
policies <- do.call(rbind,policies)
failures_df <- if(length(failures)) do.call(rbind,failures) else data.frame(season=character(),stage=character(),message=character())
write.csv(pass,file.path(OUT,'passage_by_season_and_shift.csv'),row.names=FALSE)
write.csv(policies,file.path(OUT,'selected_policy_by_outer_fold.csv'),row.names=FALSE)
write.csv(failures_df,file.path(OUT,'failures.csv'),row.names=FALSE)

summ <- do.call(rbind,lapply(split(pass,pass$activation_shift),function(z)data.frame(
  activation_shift=z$activation_shift[1],n_seasons=nrow(z),n_false_early=sum(z$false_early),early_weeks_total=sum(z$early_weeks),
  n_confirmed_by_peak2=sum(z$confirmed_by_peak2),mean_delay_penalty=mean(z$delay_penalty),median_delay_penalty=median(z$delay_penalty),
  max_delay_penalty=max(z$delay_penalty),stringsAsFactors=FALSE)))
summ <- summ[order(summ$activation_shift),]
write.csv(summ,file.path(OUT,'passage_summary_by_shift.csv'),row.names=FALSE)

nom <- summ[summ$activation_shift==0,]; minus <- summ[summ$activation_shift==-1,]; plus <- summ[summ$activation_shift==1,]
criteria <- data.frame(
  criterion=c('nominal_zero_false_early','shift_minus1_zero_false_early','shift_plus1_zero_false_early','nominal_at_least_4_of_5_by_peak2','nominal_median_delay_le_2','nominal_mean_delay_le_2_5','no_failures'),
  pass=c(nom$n_false_early==0,minus$n_false_early==0,plus$n_false_early==0,nom$n_confirmed_by_peak2>=4,nom$median_delay_penalty<=2,nom$mean_delay_penalty<=2.5,nrow(failures_df)==0),
  stringsAsFactors=FALSE)
write.csv(criteria,file.path(OUT,'acceptance_criteria.csv'),row.names=FALSE)
verdict <- data.frame(historically_promising=all(criteria$pass),decision=if(all(criteria$pass)) 'existing_passage_policy_eligible_for_shadow' else 'existing_passage_policy_not_sufficient',stringsAsFactors=FALSE)
write.csv(verdict,file.path(OUT,'overall_verdict.csv'),row.names=FALSE)

# Explicit no-event operational state.
noevent <- data.frame(season=INACTIVE,activity_detected=FALSE,m1_b_state='inactive_no_timing_event',positive_timing_gate=FALSE,stringsAsFactors=FALSE)
write.csv(noevent,file.path(OUT,'no_event_contract.csv'),row.names=FALSE)

manifest_paths <- c(PANEL_PATH,TIMING_PATH,DETECT_PATH,file.path(B0_DIR,'fold_ledger.csv'),POLICY_DOC)
manifest <- data.frame(path=manifest_paths,sha256=vapply(manifest_paths,sha256_file,character(1)),stringsAsFactors=FALSE)
write.csv(manifest,file.path(OUT,'source_manifest.csv'),row.names=FALSE)

cat('Pandemic-excluded existing passage policy benchmark complete\n')
print(summ,row.names=FALSE)
print(criteria,row.names=FALSE)
print(verdict,row.names=FALSE)
