#!/usr/bin/env Rscript
# Early-origin support audit variant: identical benchmark logic except scoring origins
# are admitted whenever the state model has >=3 observations; no weekF13 filter.
# V3 M2-A posterior-C2 chronological benchmark (audited plan
# docs/v3-m2-a-implementation-plan-2026-09-26.md).
#
# Usage (from repo root):
#   Rscript scripts/v3_benchmark_m2_a_early_origin_support_v1.R
# Optional environment:
#   PAGE_M2A_OUT              output directory override (determinism reference run)
#   PAGE_M2A_DETERMINISM_REF  earlier output directory to compare prediction-bearing files against

options(stringsAsFactors = FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

if (!requireNamespace('digest', quietly=TRUE)) stop('Package `digest` required.')

# Guard: the frozen scalar calibrator and hard passage decision must never run.
# Names are assembled so the static source scan below cannot self-match.
FORBIDDEN_FUNS <- c(paste0('m1_v2_apply_','bias_calibration'),paste0('m1_v2_passage_','decision'))
forbidden_calls <- setNames(integer(length(FORBIDDEN_FUNS)),FORBIDDEN_FUNS)
for (fn in FORBIDDEN_FUNS) local({
  nm <- fn
  assign(nm,function(...) {
    forbidden_calls[[nm]] <<- forbidden_calls[[nm]]+1L
    stop('Forbidden call in M2-A benchmark: ',nm)
  },envir=globalenv())
})

PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
M0_ARTIFACT_PATH <- 'artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds'
M1_STAGE_PATH <- 'artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/m1_v2_stage.rds'
PLAN_PATH <- 'docs/v3-m2-a-implementation-plan-2026-09-26.md'
SOURCE_CODE_PATHS <- c(
  'PAGe/R/data_contract.R','PAGe/R/stage_contracts.R','PAGe/R/m0_training.R',
  'PAGe/R/timing_pipeline_v2.R','PAGe/R/expert_timing_annotations.R',
  'PAGe/R/retrospective_peak_truth.R','PAGe/R/m1_v2.R'
)
SCRIPT_PATH <- 'scripts/v3_benchmark_m2_a_early_origin_support_v1.R'
OUT <- Sys.getenv('PAGE_M2A_OUT','artifacts/v3-m2-a-early-origin-support-v1')
DETERMINISM_REF <- Sys.getenv('PAGE_M2A_DETERMINISM_REF','')

EXPECTED_M0_SHA256 <- '9598486e78eedd8e322da77b0d990db60ca07224c3c6ea6ac61cea9cc6fb611d'
EXPECTED_M1_ARTIFACT_ID <- '90f06406dbe3a7d5f190070a5ec7a5c3605d28fe2e7f769609666f92d75d20a5'
EXPECTED_M1_FROZEN_LIBRARY_HASH <- '66152c96fac040ea94b21c6a45ebf6a7ec20c6960ece0ef3c955244fa3da52f8'
EXPECTED_V3_REFERENCE_LIBRARY_HASH <- 'ae539389e556fb342c6ea5e1a391fed027c46ff509326536647ff3d34fb79bfb'

B_EXCLUDED_SHAPE_SEASONS <- c('2018-19','2019-20')
MIN_STATE_PRIOR <- 3L
MIN_TIMING_PRIOR <- 5L
AMP_GRID <- seq(.08,.44,by=.02)
PASSAGE_STEP <- 0.2
PASSAGE_MAX_FUTURE <- 12
SHAPE_TAU <- seq(-8,8,by=.25)
C2_WEIGHTS <- c(pooled_AB=.5,A=.5)
ETA <- .5
LOWER_BOUND_MONITOR <- .9
NEAR_PEAK_HALF_WIDTH <- 1

if (dir.exists(OUT) && length(list.files(OUT,all.files=TRUE,no..=TRUE))) {
  stop('Refusing to overwrite non-empty output directory: ',OUT,call.=FALSE)
}
dir.create(OUT,recursive=TRUE,showWarnings=FALSE)

sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))
logit <- function(p) qlogis(pmin(pmax(p,1e-6),1-1e-6))
stab <- function(y,N,c=.5) (y+c)/(N+2*c)
fmt_seasons <- function(x) paste(as.character(x),collapse=';')
split_seasons <- function(x) if (nzchar(x)) strsplit(x,';',fixed=TRUE)[[1]] else character()

panel <- read.csv(PANEL_PATH,check.names=FALSE)
timing <- read.csv(TIMING_PATH,check.names=FALSE)
m0_art <- readRDS(M0_ARTIFACT_PATH)
m1_stage <- readRDS(M1_STAGE_PATH)

required_panel <- c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')
if (!all(required_panel %in% names(panel))) stop('Canonical panel missing required columns.')
if (anyNA(panel[required_panel])) stop('Canonical panel has missing required values.')
panel$season <- as.character(panel$season)
timing$season <- as.character(timing$season)
# The canonical panel is consumed in its native row order with native row
# names; the provenance hash is row-name-sensitive, so never reorder it.
if (is.unsorted(season_start(panel$season)*100+panel$weekF,strictly=TRUE)) {
  stop('Canonical panel is not in native chronological order; refusing to reorder.')
}
all_seasons <- unique(panel$season)
if (length(all_seasons)!=11L) stop('Expected 11 canonical seasons, found ',length(all_seasons))
if (!setequal(all_seasons,timing$season)) stop('Panel/timing season mismatch.')
if (any(!is.finite(timing$A_peak_weekF))) stop('Missing canonical v3 A peak truth.')
b_shape_seasons <- timing$season[is.finite(timing$B_peak_weekF) & !(timing$season %in% B_EXCLUDED_SHAPE_SEASONS)]
b_shape_seasons <- all_seasons[all_seasons %in% b_shape_seasons]

# ---------- frozen M0-A policy ----------
m0_sha <- sha256_file(M0_ARTIFACT_PATH)
if (!identical(m0_sha,EXPECTED_M0_SHA256)) stop('Frozen M0 artifact hash mismatch: ',m0_sha)
m0_params <- m0_art$best_params
if (!identical(m0_params$use_cls,FALSE) || !identical(m0_params$w_min,12L) ||
    !identical(m0_params$raw_nondec_n,3L) || !isTRUE(all.equal(m0_params$raw_drop_se_tol,1.0))) {
  stop('M0 artifact does not match frozen v2 policy (classifier off, w_min=12, raw3, 1-SE).')
}
m0_params_digest <- digest::digest(m0_params,algo='sha256')

# ---------- frozen M1-v2 specification identity ----------
if (!identical(m1_stage$artifact_id,EXPECTED_M1_ARTIFACT_ID)) stop('Frozen M1-v2 stage artifact ID mismatch.')
if (!identical(m1_stage$library$provenance$library_hash,EXPECTED_M1_FROZEN_LIBRARY_HASH)) stop('Frozen M1-v2 library hash mismatch.')
spec_identity <- data.frame(
  field=c('library_version','k','grid_step','tau_step','amplitude_grid','passage_candidate_step'),
  frozen=c(m1_stage$library$version,m1_stage$library$config$k,m1_stage$library$config$grid_step,
           m1_stage$library$config$tau_step,fmt_seasons(m1_stage$library$config$amplitude_grid),
           m1_stage$config$passage_candidate_step),
  benchmark=c(NA_character_,8L,.01,.1,fmt_seasons(AMP_GRID),PASSAGE_STEP),
  stringsAsFactors=FALSE)

# ---------- candidate-independent A ledger ----------
ledger_rows <- list()
for (s in all_seasons) {
  z <- panel[panel$season==s,,drop=FALSE]
  ps <- stab(z$y_A,z$N_A)
  lg <- logit(ps)
  for (i in seq_len(nrow(z))) {
    if (i < 3L) next
    for (h in 1:2) {
      j <- i+h
      if (j > nrow(z) || z$weekF[j]!=z$weekF[i]+h) next
      ledger_rows[[length(ledger_rows)+1L]] <- data.frame(
        season=s,origin_week=z$weekF[i],target_week=z$weekF[j],horizon=h,
        y_target=z$y_A[j],N_target=z$N_A[j],p_target=z$p_A[j],
        y_current=z$y_A[i],N_current=z$N_A[i],p_current=z$p_A[i],p_star=ps[i],
        logit_current=lg[i],growth1=lg[i]-lg[i-1L],growth2=(lg[i]-lg[i-2L])/2,
        denominator_regime=z$denominator_regime[i],stringsAsFactors=FALSE)
    }
  }
}
ledger <- do.call(rbind,ledger_rows)
write.csv(ledger,file.path(OUT,'candidate_independent_ledger.csv'),row.names=FALSE)

fit_state_baseline <- function(train_rows) {
  tr <- train_rows
  tr$horizon_f <- factor(paste0('h',tr$horizon),levels=c('h1','h2'))
  tr$offset_logit <- tr$logit_current
  suppressWarnings(glm(
    cbind(y_target,N_target-y_target) ~ horizon_f + growth1 + growth2 + offset(offset_logit),
    data=tr,family=quasibinomial()))
}

state_features_at_origin <- function(data_panel, season, origin_week) {
  z <- data_panel[data_panel$season==season & data_panel$weekF<=origin_week,,drop=FALSE]
  i <- which(z$weekF==origin_week)
  if (length(i)!=1L || i<3L) stop('Insufficient prefix state features for ',season,' origin ',origin_week)
  ps <- stab(z$y_A,z$N_A)
  lg <- logit(ps)
  data.frame(
    p_star=ps[i],logit_current=lg[i],
    growth1=lg[i]-lg[i-1L],growth2=(lg[i]-lg[i-2L])/2,
    denominator_regime=z$denominator_regime[i],stringsAsFactors=FALSE)
}

predict_state_one <- function(fit_state, features, horizon) {
  nd <- features
  nd$horizon <- horizon
  nd$horizon_f <- factor(paste0('h',horizon),levels=c('h1','h2'))
  nd$offset_logit <- nd$logit_current
  as.numeric(predict(fit_state,newdata=nd,type='response'))
}

# ---------- causal prefix A activation (frozen M0, unmodified w_max) ----------
make_A_surveillance <- function(data_panel, seasons=NULL) {
  # Native row order, freshly constructed so row names are the compact default:
  # the library provenance hash is row-name-sensitive. Never sort/subset a
  # frame that would carry non-canonical row names into fit_m1_v2_library().
  keep <- if (is.null(seasons)) rep(TRUE,nrow(data_panel)) else as.character(data_panel$season) %in% seasons
  data.frame(season=as.character(data_panel$season[keep]),weekF=data_panel$weekF[keep],
             y=data_panel$y_A[keep],N=data_panel$N_A[keep],p=data_panel$p_A[keep],stringsAsFactors=FALSE)
}

inactive <- function(reason) list(detected=FALSE,activity_week=NA_real_,activity_integer=NA_integer_,reason=reason)

causal_activity <- function(data_panel, season, origin_week) {
  z <- make_A_surveillance(data_panel[data_panel$season==season & data_panel$weekF<=origin_week,,drop=FALSE])
  if (!nrow(z)) return(inactive('empty_prefix'))
  det <- tryCatch(
    detectIgnitionBySeason_M0v2_timing(z,m0_params,verbose=FALSE,iWeek=FALSE,validate_support=FALSE),
    error=function(e)e)
  if (inherits(det,'error')) return(inactive(paste0('detector_error:',conditionMessage(det))))
  b <- det$by_season
  if (!nrow(b)) return(inactive('detector_empty'))
  if (isTRUE(b$detection_failed[1])) return(inactive('detection_failed'))
  if (!is.finite(b$iWeek_hat[1]) || !is.finite(b$iWeek_hatF[1])) return(inactive('activation_missing'))
  aw <- as.numeric(b$iWeek_hatF[1])
  ai <- as.integer(b$iWeek_hat[1])
  if (aw > origin_week + 1e-12) return(inactive('activation_after_origin'))
  list(detected=TRUE,activity_week=aw,activity_integer=ai,reason='causal_prefix_detection')
}

activation_rows <- list()
for (s in all_seasons) {
  for (o in sort(unique(ledger$origin_week[ledger$season==s]))) {
    a <- causal_activity(panel,s,o)
    activation_rows[[length(activation_rows)+1L]] <- data.frame(
      season=s,origin_week=o,detected=a$detected,activity_integer=a$activity_integer,
      activity_week=a$activity_week,reason=a$reason,stringsAsFactors=FALSE)
  }
}
activation_table <- do.call(rbind,activation_rows)
act_key <- function(s,o) paste(s,o,sep='|')
activation_cache <- split(activation_table,act_key(activation_table$season,activation_table$origin_week))

# Activation latch audit: once active, later prefixes keep the same coordinate.
latch_rows <- lapply(all_seasons,function(s) {
  z <- activation_table[activation_table$season==s,,drop=FALSE]
  first <- which(z$detected)[1]
  if (is.na(first)) {
    return(data.frame(season=s,first_active_origin=NA_real_,latched_integer=NA_integer_,latched_week=NA_real_,
                      n_later_origins=0L,n_mismatch=0L,mismatch_origins='',pass=TRUE))
  }
  later <- z[seq(first,nrow(z)),,drop=FALSE]
  bad <- !later$detected | later$activity_integer!=z$activity_integer[first] |
    abs(later$activity_week-z$activity_week[first])>0
  bad[is.na(bad)] <- TRUE
  data.frame(season=s,first_active_origin=z$origin_week[first],latched_integer=z$activity_integer[first],
             latched_week=z$activity_week[first],n_later_origins=nrow(later),n_mismatch=sum(bad),
             mismatch_origins=fmt_seasons(later$origin_week[bad]),pass=!any(bad))
})
latch_audit <- do.call(rbind,latch_rows)
write.csv(activation_table,file.path(OUT,'causal_activation_by_origin.csv'),row.names=FALSE)
write.csv(latch_audit,file.path(OUT,'activation_latch_audit.csv'),row.names=FALSE)

# End-of-season audit only: final prefix versus a whole-panel frozen-M0 table.
whole_det <- detectIgnitionBySeason_M0v2_timing(make_A_surveillance(panel),m0_params,verbose=FALSE,iWeek=FALSE,validate_support=FALSE)$by_season
whole_det$season <- as.character(whole_det$season)
m0_compare <- m0_art$compare
eos_rows <- lapply(all_seasons,function(s) {
  last_week <- max(panel$weekF[panel$season==s])
  a <- causal_activity(panel,s,last_week)
  w <- whole_det[whole_det$season==s,,drop=FALSE]
  w_active <- nrow(w)==1L && !isTRUE(w$detection_failed) && is.finite(w$iWeek_hatF)
  same <- (a$detected==w_active) && (!a$detected ||
    (identical(a$activity_integer,as.integer(w$iWeek_hat)) && isTRUE(all.equal(a$activity_week,as.numeric(w$iWeek_hatF),tolerance=0))))
  mc <- m0_compare[as.character(m0_compare$season)==s,,drop=FALSE]
  data.frame(season=s,end_of_season_week=last_week,prefix_detected=a$detected,prefix_integer=a$activity_integer,
             prefix_week=a$activity_week,frozen_table_detected=w_active,
             frozen_table_integer=if (w_active) as.integer(w$iWeek_hat) else NA_integer_,
             frozen_table_week=if (w_active) as.numeric(w$iWeek_hatF) else NA_real_,
             m0_loso_iWeek_hatF=if (nrow(mc)) as.numeric(mc$iWeek_hatF) else NA_real_,
             reviewed_A_ignition_weekF=timing$A_ignition_weekF[timing$season==s],pass=same)
})
eos_parity <- do.call(rbind,eos_rows)
write.csv(eos_parity,file.path(OUT,'end_of_season_activation_parity.csv'),row.names=FALSE)

# ---------- fold-local M1-A library ----------
fit_A_library <- function(train_seasons, data_panel=panel, timing_data=timing) {
  train_seasons <- all_seasons[all_seasons %in% train_seasons]
  d <- make_A_surveillance(data_panel,train_seasons)
  tt <- data.frame(season=train_seasons,
                   peak_week_decimal=timing_data$A_peak_weekF[match(train_seasons,timing_data$season)],
                   stringsAsFactors=FALSE)
  fit_m1_v2_library(d,tt,k=8L,grid_step=.01,tau_step=.1,amplitude_grid=AMP_GRID)
}

validate_fold_library <- function(lib, expected_seasons) {
  if (!inherits(lib,'page_m1_v2_library')) stop('Fold-local M1-A library malformed.')
  if (!identical(sort(as.character(lib$training_seasons)),sort(as.character(expected_seasons)))) stop('Fold-local M1-A season identity mismatch.')
  if (!isTRUE(all.equal(as.numeric(lib$config$amplitude_grid),AMP_GRID,tolerance=0))) stop('Fold-local M1-A amplitude support mismatch.')
  if (!identical(lib$version,m1_stage$library$version)) stop('Fold-local M1-A version mismatch.')
  invisible(TRUE)
}

# Full-history canonical-v3 reproduction (all 11 A seasons).
repro_lib <- fit_A_library(all_seasons)
repro_match <- identical(repro_lib$provenance$library_hash,EXPECTED_V3_REFERENCE_LIBRARY_HASH)
if (!repro_match) stop('Full-history canonical-v3 M1-A library does not reproduce reference hash: ',repro_lib$provenance$library_hash)
spec_identity$benchmark[1] <- repro_lib$version
spec_identity$benchmark[2:4] <- c(repro_lib$config$k,repro_lib$config$grid_step,repro_lib$config$tau_step)
spec_identity$benchmark[5] <- fmt_seasons(repro_lib$config$amplitude_grid)
spec_identity$match <- spec_identity$frozen==spec_identity$benchmark
write.csv(spec_identity,file.path(OUT,'m1_spec_identity.csv'),row.names=FALSE)

frozen_truth <- m1_stage$library$peak_truth
peak_parity <- data.frame(season=all_seasons,
  v3_A_peak_weekF=timing$A_peak_weekF[match(all_seasons,timing$season)],
  frozen_m1_peak_weekF=frozen_truth$peak_week_decimal[match(all_seasons,as.character(frozen_truth$season))])
peak_parity$diff_weeks <- peak_parity$v3_A_peak_weekF-peak_parity$frozen_m1_peak_weekF
peak_parity$vintage_difference <- is.na(peak_parity$diff_weeks) | abs(peak_parity$diff_weeks)>1e-9
write.csv(peak_parity,file.path(OUT,'peak_truth_parity.csv'),row.names=FALSE)

# ---------- v3 shape grid from canonical panel + v3 timing peaks ----------
build_one_shape <- function(data_panel, timing_data, season, type, check_alignment=TRUE) {
  if (type=='B' && !(season %in% b_shape_seasons)) return(NULL)
  peak_col <- if (type=='A') 'A_peak_weekF' else 'B_peak_weekF'
  truth_peak <- timing_data[[peak_col]][timing_data$season==season]
  if (length(truth_peak)!=1L || !is.finite(truth_peak)) return(NULL)
  ycol <- paste0('y_',type); ncol <- paste0('N_',type); pcol <- paste0('p_',type)
  z <- data_panel[data_panel$season==season,c('season','weekF',ycol,ncol,pcol)]
  names(z)[3:5] <- c('y','N','p')
  f <- retrospective_gam_peak_truth(z,season=season,k=8L,grid_step=.01)
  diff_peak <- abs(f$peak_week_decimal-truth_peak)
  if (check_alignment && diff_peak>.051) stop('V3 shape peak mismatch for ',season,' ',type,': ',diff_peak)
  g <- f$grid
  amp <- max(g$fitted_p,na.rm=TRUE)
  vals <- approx(g$weekF-truth_peak,g$fitted_p/amp,xout=SHAPE_TAU,rule=1)$y
  list(
    grid=data.frame(season=season,type=type,tau=SHAPE_TAU,p_norm=vals,stringsAsFactors=FALSE),
    check=data.frame(season=season,type=type,truth_peak=truth_peak,fitted_peak=f$peak_week_decimal,abs_diff=diff_peak,stringsAsFactors=FALSE))
}

build_shape_grid <- function(data_panel=panel, timing_data=timing, check_alignment=TRUE) {
  rows <- list(); checks <- list()
  for (ss in all_seasons) for (tp in c('A','B')) {
    q <- build_one_shape(data_panel,timing_data,ss,tp,check_alignment=check_alignment)
    if (is.null(q)) next
    rows[[length(rows)+1L]] <- q$grid
    checks[[length(checks)+1L]] <- q$check
  }
  list(grid=do.call(rbind,rows),checks=do.call(rbind,checks))
}

shape_obj <- build_shape_grid()
shape_grid <- shape_obj$grid
if (any(shape_grid$type=='B' & shape_grid$season %in% B_EXCLUDED_SHAPE_SEASONS)) stop('Excluded B shape entered v3 shape grid.')
write.csv(shape_grid,file.path(OUT,'shape_grid_v3.csv'),row.names=FALSE)
write.csv(shape_obj$checks,file.path(OUT,'shape_peak_alignment_checks.csv'),row.names=FALSE)

one_lr <- function(z,tau,h) {
  cur <- approx(z$tau,z$p_norm,xout=tau,rule=1)$y
  fut <- approx(z$tau,z$p_norm,xout=tau+h,rule=1)$y
  if (!is.finite(cur) || !is.finite(fut)) return(NA_real_)
  log(pmax(fut,.01)/pmax(cur,.01))
}

# LR_C2_A = 0.5*median_pooled_AB + 0.5*median_A; supported only if both finite.
c2_lr <- function(prior_A,prior_B,tau,h,shape_data=shape_grid) {
  vals_A <- numeric(); vals_B <- numeric()
  for (s in prior_A) {
    z <- shape_data[shape_data$season==s & shape_data$type=='A',]
    if (nrow(z)) { q <- one_lr(z,tau,h); if (is.finite(q)) vals_A <- c(vals_A,q) }
  }
  for (s in prior_B) {
    z <- shape_data[shape_data$season==s & shape_data$type=='B',]
    if (nrow(z)) { q <- one_lr(z,tau,h); if (is.finite(q)) vals_B <- c(vals_B,q) }
  }
  if (!length(vals_A) || !length(vals_B)) return(NA_real_)
  C2_WEIGHTS[['pooled_AB']]*median(c(vals_A,vals_B))+C2_WEIGHTS[['A']]*median(vals_A)
}

blend_shape <- function(base,current,lr,eta=ETA) {
  if (!is.finite(lr)) return(base)
  projected <- pmin(pmax(current*exp(lr),1e-6),1-1e-6)
  plogis((1-eta)*logit(base)+eta*logit(projected))
}

posterior_correction <- function(base,current,posterior,prior_A,prior_B,horizon,origin_week,shape_data=shape_grid) {
  w <- as.numeric(posterior$probability)
  T <- as.numeric(posterior$peak_week_decimal)
  if (!length(w) || length(w)!=length(T) || any(!is.finite(w)) || sum(w)<=0) stop('Malformed M1-A passage posterior.')
  w <- w/sum(w)
  lr <- vapply(T,function(tt)c2_lr(prior_A,prior_B,origin_week-tt,horizon,shape_data=shape_data),numeric(1))
  supported <- is.finite(lr)
  pT <- rep(base,length(T))
  if (any(supported)) pT[supported] <- vapply(lr[supported],function(q)blend_shape(base,current,q,ETA),numeric(1))
  Tmean <- sum(w*T)
  lrmean <- c2_lr(prior_A,prior_B,origin_week-Tmean,horizon,shape_data=shape_data)
  list(pred=sum(w*pT), # unsupported candidates already carry exact A1
       point_pred=if (is.finite(lrmean)) blend_shape(base,current,lrmean,ETA) else base,
       supported_mass=sum(w[supported]),
       lower_bound_mass=sum(w[T <= min(T)+PASSAGE_STEP+1e-12]),
       posterior_mean=Tmean)
}

# ---------- fold ledger ----------
state_seasons <- all_seasons[all_seasons %in% ledger$season]
fold_rows <- lapply(all_seasons,function(target) {
  prior <- function(x) x[season_start(x)<season_start(target)]
  prior_state <- prior(state_seasons)
  prior_timing <- prior(all_seasons)
  data.frame(
    target_season=target,n_prior_state=length(prior_state),prior_state=fmt_seasons(prior_state),
    n_prior_timing=length(prior_timing),prior_timing=fmt_seasons(prior_timing),
    prior_A_shapes=fmt_seasons(prior(all_seasons)),prior_B_shapes=fmt_seasons(prior(b_shape_seasons)),
    state_available=length(prior_state)>=MIN_STATE_PRIOR,
    timing_library_available=length(prior_timing)>=MIN_TIMING_PRIOR,
    stringsAsFactors=FALSE)
})
fold_ledger <- do.call(rbind,fold_rows)
write.csv(fold_ledger,file.path(OUT,'outer_fold_ledger.csv'),row.names=FALSE)

fold_leakage <- vapply(seq_len(nrow(fold_ledger)),function(i) {
  tgt <- season_start(fold_ledger$target_season[i])
  all_prior <- unlist(lapply(fold_ledger[i,c('prior_state','prior_timing','prior_A_shapes','prior_B_shapes')],split_seasons))
  length(all_prior) && any(season_start(all_prior)>=tgt)
},logical(1))
if (any(fold_leakage)) stop('Fold leakage detected.')
if (any(vapply(fold_ledger$prior_B_shapes,function(x)any(split_seasons(x) %in% B_EXCLUDED_SHAPE_SEASONS),logical(1)))) stop('Excluded B shape entered fold.')

# ---------- chronological predictions ----------
pred_rows <- list(); timing_lib_rows <- list(); shape_lib_rows <- list()
future_rows <- list(); perturb_rows <- list(); failure_rows <- list()

log_failure <- function(stage,season,origin,detail) {
  failure_rows[[length(failure_rows)+1L]] <<- data.frame(stage=stage,season=season,origin=origin,detail=detail,stringsAsFactors=FALSE)
}

compute_timing_for_origin <- function(target,origin,lib,data_panel=panel,act=NULL) {
  if (is.null(act)) act <- causal_activity(data_panel,target,origin)
  if (!isTRUE(act$detected)) return(list(available=FALSE,reason=act$reason,activity_week=NA_real_,posterior=NULL,prob_passed=NA_real_))
  z <- make_A_surveillance(data_panel[data_panel$season==target & data_panel$weekF<=origin,,drop=FALSE])
  pp <- tryCatch(m1_v2_passage_posterior(lib,z,activation_week=act$activity_week,origin_week=origin,
                                         candidate_step=PASSAGE_STEP,max_future_weeks=PASSAGE_MAX_FUTURE),error=function(e)e)
  if (inherits(pp,'error')) return(list(available=FALSE,reason=paste0('posterior_error:',conditionMessage(pp)),activity_week=act$activity_week,posterior=NULL,prob_passed=NA_real_))
  post <- attr(pp,'posterior')
  if (is.null(post) || !nrow(post) || sum(post$probability)<=0) return(list(available=FALSE,reason='empty_admissible_posterior',activity_week=act$activity_week,posterior=NULL,prob_passed=NA_real_))
  list(available=TRUE,reason='available',activity_week=act$activity_week,posterior=post,prob_passed=pp$prob_peak_passed[1])
}

cached_activity <- function(target,origin) {
  a <- activation_cache[[act_key(target,origin)]]
  list(detected=a$detected,activity_week=a$activity_week,activity_integer=a$activity_integer,reason=a$reason)
}

posterior_equal <- function(a,b,tol=1e-14) {
  if (is.null(a) || is.null(b)) return(is.null(a) && is.null(b))
  if (!identical(as.numeric(a$peak_week_decimal),as.numeric(b$peak_week_decimal))) return(FALSE)
  max(abs(as.numeric(a$probability)-as.numeric(b$probability))) <= tol
}

predict_one_context <- function(target,origin,horizon,fit_state,prior_A,prior_B,lib,data_panel=panel,shape_data=shape_grid) {
  f <- state_features_at_origin(data_panel,target,origin)
  base <- predict_state_one(fit_state,f,horizon)
  if (is.null(lib)) return(list(base=base,pred=base,features=f,available=FALSE,activity_week=NA_real_,posterior=NULL))
  info <- compute_timing_for_origin(target,origin,lib,data_panel)
  if (!isTRUE(info$available)) return(list(base=base,pred=base,features=f,available=FALSE,activity_week=info$activity_week,posterior=info$posterior))
  q <- posterior_correction(base,f$p_star,info$posterior,prior_A,prior_B,horizon,origin,shape_data)
  list(base=base,pred=q$pred,features=f,available=TRUE,activity_week=info$activity_week,posterior=info$posterior)
}

for (fi in seq_len(nrow(fold_ledger))) {
  target <- fold_ledger$target_season[fi]
  if (!isTRUE(fold_ledger$state_available[fi])) next
  prior_state <- split_seasons(fold_ledger$prior_state[fi])
  tr <- ledger[ledger$season %in% prior_state,,drop=FALSE]
  te <- ledger[ledger$season==target,,drop=FALSE]
  if (!nrow(te)) next
  fit_state <- fit_state_baseline(tr)
  te$horizon_f <- factor(paste0('h',te$horizon),levels=c('h1','h2'))
  te$offset_logit <- te$logit_current
  te$pred_A0 <- te$p_star
  te$pred_A1 <- as.numeric(predict(fit_state,newdata=te,type='response'))

  prior_timing <- split_seasons(fold_ledger$prior_timing[fi])
  prior_A <- split_seasons(fold_ledger$prior_A_shapes[fi])
  prior_B <- split_seasons(fold_ledger$prior_B_shapes[fi])
  lib <- NULL
  if (isTRUE(fold_ledger$timing_library_available[fi])) {
    lib <- tryCatch(fit_A_library(prior_timing),error=function(e)e)
    if (inherits(lib,'error')) { log_failure('fit_timing_library',target,NA_real_,conditionMessage(lib)); lib <- NULL }
  }
  if (!is.null(lib)) validate_fold_library(lib,prior_timing)
  timing_lib_rows[[length(timing_lib_rows)+1L]] <- data.frame(
    target_season=target,training_seasons=fmt_seasons(prior_timing),n_training=length(prior_timing),
    library_fitted=!is.null(lib),library_hash=if (!is.null(lib)) lib$provenance$library_hash else NA_character_,
    library_version=if (!is.null(lib)) lib$version else NA_character_,stringsAsFactors=FALSE)
  shape_lib_rows[[length(shape_lib_rows)+1L]] <- data.frame(
    target_season=target,A_shape_seasons=fmt_seasons(prior_A),n_A_shapes=length(prior_A),
    B_shape_seasons=fmt_seasons(prior_B),n_B_shapes=length(prior_B),stringsAsFactors=FALSE)

  origins <- sort(unique(te$origin_week))
  timing_cache <- if (!is.null(lib)) setNames(lapply(origins,function(o)compute_timing_for_origin(target,o,lib,panel,cached_activity(target,o))),as.character(origins)) else list()
  for (q in timing_cache) if (!isTRUE(q$available) && grepl('^(posterior_error|detector_error)',q$reason)) log_failure('timing',target,NA_real_,q$reason)

  for (i in seq_len(nrow(te))) {
    o <- te$origin_week[i]; h <- te$horizon[i]; base <- te$pred_A1[i]
    pred_mix <- base; pred_point <- base
    timing_available <- FALSE; prob_passed <- NA_real_; posterior_mean <- NA_real_
    supported_mass <- 0; lower_mass <- NA_real_
    act <- cached_activity(target,o)
    activity_week <- act$activity_week
    timing_reason <- if (is.null(lib)) 'insufficient_timing_prior' else timing_cache[[as.character(o)]]$reason
    if (!is.null(lib)) {
      info <- timing_cache[[as.character(o)]]
      if (isTRUE(info$available)) {
        q <- posterior_correction(base,te$p_star[i],info$posterior,prior_A,prior_B,h,o)
        pred_mix <- q$pred; pred_point <- q$point_pred; supported_mass <- q$supported_mass
        lower_mass <- q$lower_bound_mass; posterior_mean <- q$posterior_mean
        prob_passed <- info$prob_passed; timing_available <- TRUE
      }
    }
    pred_rows[[length(pred_rows)+1L]] <- data.frame(
      season=target,origin_week=o,target_week=te$target_week[i],horizon=h,
      y_target=te$y_target[i],N_target=te$N_target[i],p_target=te$p_target[i],
      p_star=te$p_star[i],growth1=te$growth1[i],growth2=te$growth2[i],denominator_regime=te$denominator_regime[i],
      pred_A0=te$pred_A0[i],pred_A1=base,pred_A2_pointmean=pred_point,pred_A2_posterior=pred_mix,
      activation_detected=act$detected,activation_integer=act$activity_integer,activity_week=activity_week,
      timing_available=timing_available,timing_reason=timing_reason,
      passage_prob_peak_passed=prob_passed,posterior_mean_peak=posterior_mean,
      supported_mass=supported_mass,lower_bound_mass=lower_mass,stringsAsFactors=FALSE)
  }

  # Future-data perturbation: first scored origin plus first/last timing-active origins.
  avail_orig <- origins[vapply(as.character(origins),function(k)isTRUE(timing_cache[[k]]$available),logical(1))]
  check_orig <- unique(c(min(origins),if (length(avail_orig)) c(min(avail_orig),max(avail_orig))))
  for (o in check_orig) {
    p2 <- panel
    ix <- which(p2$season==target & p2$weekF>o)
    if (!length(ix)) next
    delta <- pmax(7L,as.integer(round(.2*p2$N_A[ix])))
    p2$y_A[ix] <- ifelse(p2$y_A[ix] < p2$N_A[ix]/2,pmin(p2$N_A[ix],p2$y_A[ix]+delta),pmax(0,p2$y_A[ix]-delta))
    p2$p_A[ix] <- p2$y_A[ix]/p2$N_A[ix]
    a0 <- causal_activity(panel,target,o); a2 <- causal_activity(p2,target,o)
    same_act <- identical(a0$detected,a2$detected) && identical(a0$activity_integer,a2$activity_integer) &&
      isTRUE(all.equal(a0$activity_week,a2$activity_week,tolerance=0))
    same_post <- TRUE; max_a1 <- 0; max_pred <- 0
    for (h in 1:2) {
      q0 <- predict_one_context(target,o,h,fit_state,prior_A,prior_B,lib,panel,shape_grid)
      q2 <- predict_one_context(target,o,h,fit_state,prior_A,prior_B,lib,p2,shape_grid)
      same_post <- same_post && posterior_equal(q0$posterior,q2$posterior)
      max_a1 <- max(max_a1,abs(q0$base-q2$base)); max_pred <- max(max_pred,abs(q0$pred-q2$pred))
    }
    future_rows[[length(future_rows)+1L]] <- data.frame(
      season=target,origin_week=o,n_future_weeks_perturbed=length(ix),same_activation=same_act,
      same_posterior=same_post,max_A1_diff=max_a1,max_prediction_diff=max_pred,
      pass=same_act && same_post && max_a1<1e-14 && max_pred<1e-14,stringsAsFactors=FALSE)
  }

  # Held-out peak-truth and forecast-target perturbations at the first timing-active +2 origin
  # (or the first scored origin when timing is unavailable for the fold).
  o <- if (length(avail_orig)) min(avail_orig) else min(origins)
  row0 <- te[te$origin_week==o & te$horizon==2,,drop=FALSE]
  if (nrow(row0)) {
    ref <- predict_one_context(target,o,2,fit_state,prior_A,prior_B,lib,panel,shape_grid)
    t2 <- timing
    old_truth <- t2$A_peak_weekF[t2$season==target]
    t2$A_peak_weekF[t2$season==target] <- if (old_truth+5<=47) old_truth+5 else old_truth-5
    lib_truth <- if (!is.null(lib)) fit_A_library(prior_timing,data_panel=panel,timing_data=t2) else NULL
    lib_truth_same <- is.null(lib) || identical(lib$provenance$library_hash,lib_truth$provenance$library_hash)
    shape_truth <- shape_grid
    qshape <- build_one_shape(panel,t2,target,'A',check_alignment=FALSE)
    shape_truth <- rbind(shape_truth[!(shape_truth$season==target & shape_truth$type=='A'),,drop=FALSE],qshape$grid)
    pred_truth <- predict_one_context(target,o,2,fit_state,prior_A,prior_B,lib_truth,panel,shape_truth)
    truth_pass <- lib_truth_same && isTRUE(all.equal(ref$activity_week,pred_truth$activity_week,tolerance=0)) &&
      posterior_equal(ref$posterior,pred_truth$posterior) && abs(ref$pred-pred_truth$pred)<1e-14

    p3 <- panel
    ix3 <- which(p3$season==target & p3$weekF==row0$target_week[1])
    if (length(ix3)!=1L) stop('Could not identify held-out forecast target for perturbation.')
    delta <- max(7L,as.integer(round(.2*p3$N_A[ix3])))
    p3$y_A[ix3] <- if (p3$y_A[ix3] < p3$N_A[ix3]/2) min(p3$N_A[ix3],p3$y_A[ix3]+delta) else max(0,p3$y_A[ix3]-delta)
    p3$p_A[ix3] <- p3$y_A[ix3]/p3$N_A[ix3]
    lib_target <- if (!is.null(lib)) fit_A_library(prior_timing,data_panel=p3,timing_data=timing) else NULL
    lib_target_same <- is.null(lib) || identical(lib$provenance$library_hash,lib_target$provenance$library_hash)
    qshape3 <- build_one_shape(p3,timing,target,'A',check_alignment=FALSE)
    shape_target <- rbind(shape_grid[!(shape_grid$season==target & shape_grid$type=='A'),,drop=FALSE],qshape3$grid)
    pred_target <- predict_one_context(target,o,2,fit_state,prior_A,prior_B,lib_target,p3,shape_target)
    target_pass <- lib_target_same && isTRUE(all.equal(ref$features,pred_target$features,tolerance=0)) &&
      isTRUE(all.equal(ref$activity_week,pred_target$activity_week,tolerance=0)) &&
      posterior_equal(ref$posterior,pred_target$posterior) &&
      abs(ref$base-pred_target$base)<1e-14 && abs(ref$pred-pred_target$pred)<1e-14
    old_abs <- abs(ref$pred-panel$p_A[ix3]); new_abs <- abs(pred_target$pred-p3$p_A[ix3])
    perturb_rows[[length(perturb_rows)+1L]] <- data.frame(
      season=target,origin_week=o,target_week=row0$target_week[1],timing_available=ref$available,
      truth_old=old_truth,truth_new=t2$A_peak_weekF[t2$season==target],truth_library_same=lib_truth_same,
      truth_prediction_diff=abs(ref$pred-pred_truth$pred),truth_pass=truth_pass,
      target_p_old=panel$p_A[ix3],target_p_new=p3$p_A[ix3],target_library_same=lib_target_same,
      target_prediction_diff=abs(ref$pred-pred_target$pred),target_score_changed=abs(old_abs-new_abs)>1e-12,
      target_pass=target_pass,pass=truth_pass && target_pass && abs(old_abs-new_abs)>1e-12,stringsAsFactors=FALSE)
  }
}

pred <- do.call(rbind,pred_rows)
pred$correction_nonzero <- abs(pred$pred_A2_posterior-pred$pred_A1)>1e-12
for (m in c('A0','A1','A2_pointmean','A2_posterior')) {
  p <- pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8)
  pred[[paste0('err_',m)]] <- p-pred$p_target
  pred[[paste0('abs_',m)]] <- abs(pred[[paste0('err_',m)]])
  pred[[paste0('sq_',m)]] <- pred[[paste0('err_',m)]]^2
  pred[[paste0('nll_',m)]] <- -(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target
}
peak_lookup <- setNames(timing$A_peak_weekF,timing$season)
pred$target_minus_peak <- pred$target_week-peak_lookup[pred$season]
pred$retrospective_phase <- ifelse(pred$target_minus_peak < -NEAR_PEAK_HALF_WIDTH,'pre_peak',
                                   ifelse(pred$target_minus_peak > NEAR_PEAK_HALF_WIDTH,'post_peak','near_peak'))
write.csv(pred,file.path(OUT,'per_origin_predictions.csv'),row.names=FALSE)

support_diag <- pred[,c('season','origin_week','horizon','activation_detected','activity_week','timing_available','timing_reason',
                        'passage_prob_peak_passed','posterior_mean_peak','supported_mass','lower_bound_mass','pred_A1','pred_A2_posterior')]
write.csv(support_diag,file.path(OUT,'posterior_support_diagnostics.csv'),row.names=FALSE)

season_metrics <- function(z) data.frame(
  season=z$season[1],horizon=z$horizon[1],n=nrow(z),timing_availability=mean(z$timing_available),
  n_nonzero_correction=sum(z$correction_nonzero),
  A0_mae_pp=100*mean(z$abs_A0),A1_mae_pp=100*mean(z$abs_A1),
  A2_pointmean_mae_pp=100*mean(z$abs_A2_pointmean),A2_posterior_mae_pp=100*mean(z$abs_A2_posterior),
  A1_rmse_pp=100*sqrt(mean(z$sq_A1)),A2_posterior_rmse_pp=100*sqrt(mean(z$sq_A2_posterior)),
  A1_bias_pp=100*mean(z$err_A1),A2_posterior_bias_pp=100*mean(z$err_A2_posterior),
  A1_nll=mean(z$nll_A1),A2_posterior_nll=mean(z$nll_A2_posterior),stringsAsFactors=FALSE)
per_season <- do.call(rbind,lapply(split(pred,list(pred$season,pred$horizon),drop=TRUE),season_metrics))
per_season <- per_season[order(per_season$horizon,season_start(per_season$season)),]
per_season$delta_mae_vs_A1_pp <- per_season$A2_posterior_mae_pp-per_season$A1_mae_pp
per_season$timing_active_season <- per_season$n_nonzero_correction>0
write.csv(per_season,file.path(OUT,'per_season_metrics.csv'),row.names=FALSE)

summary_metrics <- do.call(rbind,lapply(split(per_season,per_season$horizon),function(z) {
  ph <- pred[pred$horizon==z$horizon[1],,drop=FALSE]
  data.frame(
    horizon=z$horizon[1],n_seasons=nrow(z),n_rows=nrow(ph),
    A0_mae_pp=mean(z$A0_mae_pp),A1_mae_pp=mean(z$A1_mae_pp),
    A2_pointmean_mae_pp=mean(z$A2_pointmean_mae_pp),A2_posterior_mae_pp=mean(z$A2_posterior_mae_pp),
    relative_mae_gain=1-mean(z$A2_posterior_mae_pp)/mean(z$A1_mae_pp),
    A1_rmse_pp=mean(z$A1_rmse_pp),A2_posterior_rmse_pp=mean(z$A2_posterior_rmse_pp),
    A1_bias_pp=mean(z$A1_bias_pp),A2_posterior_bias_pp=mean(z$A2_posterior_bias_pp),
    A1_nll=mean(ph$nll_A1),A2_posterior_nll=mean(ph$nll_A2_posterior),
    worst_A1_mae_pp=max(z$A1_mae_pp),worst_A2_posterior_mae_pp=max(z$A2_posterior_mae_pp),
    seasons_better=sum(z$A2_posterior_mae_pp<z$A1_mae_pp-1e-12),
    seasons_worse=sum(z$A2_posterior_mae_pp>z$A1_mae_pp+1e-12),
    timing_availability=mean(ph$timing_available),stringsAsFactors=FALSE)
}))
write.csv(summary_metrics,file.path(OUT,'summary_metrics.csv'),row.names=FALSE)

# Timing-active seasons: season-level metrics over all rows of seasons with a non-zero correction.
active_per <- per_season[per_season$timing_active_season,,drop=FALSE]
active_rows_only <- pred[pred$timing_available,,drop=FALSE]
active_summary <- do.call(rbind,lapply(1:2,function(h) {
  z <- active_per[active_per$horizon==h,,drop=FALSE]
  r <- active_rows_only[active_rows_only$horizon==h,,drop=FALSE]
  data.frame(horizon=h,n_active_seasons=nrow(z),active_seasons=fmt_seasons(z$season),
    A1_mae_pp=if (nrow(z)) mean(z$A1_mae_pp) else NA_real_,
    A2_posterior_mae_pp=if (nrow(z)) mean(z$A2_posterior_mae_pp) else NA_real_,
    relative_mae_gain=if (nrow(z)) 1-mean(z$A2_posterior_mae_pp)/mean(z$A1_mae_pp) else NA_real_,
    seasons_better=sum(z$A2_posterior_mae_pp<z$A1_mae_pp-1e-12),
    seasons_worse=sum(z$A2_posterior_mae_pp>z$A1_mae_pp+1e-12),
    max_worsening_pp=max(c(0,z$A2_posterior_mae_pp-z$A1_mae_pp)),
    n_timing_active_rows=nrow(r),
    timing_active_rows_A1_mae_pp=if (nrow(r)) 100*mean(r$abs_A1) else NA_real_,
    timing_active_rows_A2_posterior_mae_pp=if (nrow(r)) 100*mean(r$abs_A2_posterior) else NA_real_,
    stringsAsFactors=FALSE)
}))
write.csv(active_summary,file.path(OUT,'active_timing_summary.csv'),row.names=FALSE)
write.csv(active_per,file.path(OUT,'active_timing_per_season.csv'),row.names=FALSE)

strat_summary <- function(z,key) do.call(rbind,lapply(split(z,z[[key]]),function(q)data.frame(
  stratum=q[[key]][1],n_rows=nrow(q),n_seasons=length(unique(q$season)),
  A1_mae_pp=100*mean(q$abs_A1),A2_posterior_mae_pp=100*mean(q$abs_A2_posterior),
  relative_mae_gain=1-mean(q$abs_A2_posterior)/mean(q$abs_A1),stringsAsFactors=FALSE)))
p2rows <- pred[pred$horizon==2,,drop=FALSE]
write.csv(strat_summary(p2rows,'retrospective_phase'),file.path(OUT,'phase_stratified_h2_summary.csv'),row.names=FALSE)
lb2 <- p2rows[p2rows$timing_available,,drop=FALSE]
lb2$lower_bound_stratum <- ifelse(lb2$lower_bound_mass>=LOWER_BOUND_MONITOR,'mass_ge_0.9','mass_lt_0.9')
lb_summary <- if (nrow(lb2)) strat_summary(lb2,'lower_bound_stratum') else data.frame()
write.csv(lb_summary,file.path(OUT,'lower_bound_stratified_summary.csv'),row.names=FALSE)
lb_manifest <- if (nrow(lb2)) do.call(rbind,lapply(split(lb2,lb2$season),function(z)data.frame(
  season=z$season[1],n_timing_active_h2=nrow(z),n_lower_bound_ge_0.9=sum(z$lower_bound_mass>=LOWER_BOUND_MONITOR),
  first_active_origin=min(z$origin_week),last_active_origin=max(z$origin_week),
  mean_lower_bound_mass=mean(z$lower_bound_mass),stringsAsFactors=FALSE))) else data.frame()
write.csv(lb_manifest,file.path(OUT,'lower_bound_active_season_manifest.csv'),row.names=FALSE)

fallback_summary <- as.data.frame(table(horizon=pred$horizon,timing_reason=pred$timing_reason),stringsAsFactors=FALSE)
fallback_summary <- fallback_summary[fallback_summary$Freq>0,,drop=FALSE]
write.csv(fallback_summary,file.path(OUT,'fallback_summary.csv'),row.names=FALSE)

timing_lib_df <- do.call(rbind,timing_lib_rows)
shape_lib_df <- do.call(rbind,shape_lib_rows)
future_df <- if (length(future_rows)) do.call(rbind,future_rows) else data.frame()
perturb_df <- if (length(perturb_rows)) do.call(rbind,perturb_rows) else data.frame()
failures_df <- if (length(failure_rows)) do.call(rbind,failure_rows) else data.frame(stage=character(),season=character(),origin=numeric(),detail=character())
write.csv(timing_lib_df,file.path(OUT,'timing_library_ledger.csv'),row.names=FALSE)
write.csv(shape_lib_df,file.path(OUT,'shape_library_ledger.csv'),row.names=FALSE)
write.csv(future_df,file.path(OUT,'future_perturbation_checks.csv'),row.names=FALSE)
write.csv(perturb_df,file.path(OUT,'truth_target_perturbation_checks.csv'),row.names=FALSE)
write.csv(failures_df,file.path(OUT,'failures.csv'),row.names=FALSE)

# ---------- determinism (compare with an earlier run when supplied) ----------
DETERMINISM_FILES <- c('candidate_independent_ledger.csv','outer_fold_ledger.csv','causal_activation_by_origin.csv',
  'timing_library_ledger.csv','shape_library_ledger.csv','shape_grid_v3.csv','per_origin_predictions.csv',
  'future_perturbation_checks.csv','truth_target_perturbation_checks.csv')
determinism_df <- data.frame(file=DETERMINISM_FILES,sha256=vapply(file.path(OUT,DETERMINISM_FILES),sha256_file,character(1)),
                             reference_sha256=NA_character_,stringsAsFactors=FALSE)
if (nzchar(DETERMINISM_REF)) {
  ref_paths <- file.path(DETERMINISM_REF,DETERMINISM_FILES)
  determinism_df$reference_sha256 <- ifelse(file.exists(ref_paths),vapply(ref_paths,function(p)if (file.exists(p)) sha256_file(p) else NA_character_,character(1)),NA_character_)
}
determinism_df$match <- determinism_df$sha256==determinism_df$reference_sha256
write.csv(determinism_df,file.path(OUT,'determinism_check.csv'),row.names=FALSE)
determinism_pass <- nzchar(DETERMINISM_REF) && all(determinism_df$match %in% TRUE)

# ---------- integrity ----------
script_lines <- readLines(SCRIPT_PATH,warn=FALSE)
static_no_forbidden <- !any(vapply(FORBIDDEN_FUNS,function(fn)any(grepl(paste0('\\b',fn,'[[:space:]]*\\('),script_lines)),logical(1)))
unsupported <- pred$timing_available & pred$supported_mass<=1e-15
fold_prior_ok <- all(vapply(seq_len(nrow(timing_lib_df)),function(i)
  all(season_start(split_seasons(timing_lib_df$training_seasons[i]))<season_start(timing_lib_df$target_season[i])),logical(1)))
integrity <- data.frame(
  check=c('01_strictly_prior_training','02_causal_activation_future_invariant','03_future_obs_do_not_change_A1_posterior_M2A',
          '04_heldout_peak_truth_does_not_change_predictions','05_heldout_target_changes_scoring_only',
          '06_timing_unavailable_exact_A1','07_unsupported_mass_exact_A1','08a_full_history_v3_reference_hash',
          '08b_m1_spec_identity','08c_peak_truth_parity_emitted','09_no_calibration_or_hard_passage_call',
          '10_fixed_c2_weights_eta','11_B_pool_excludes_2018_19_2019_20','12_repeated_execution_deterministic',
          '13_m0_and_panel_hashes_emitted','14a_activation_latch','14b_end_of_season_activation_parity',
          '15_source_hashes_and_fold_ledgers_emitted','all_11_seasons_modeled','no_unexpected_failures'),
  pass=c(
    !any(fold_leakage) && fold_prior_ok,
    nrow(future_df)>0 && all(future_df$same_activation),
    nrow(future_df)>0 && all(future_df$pass),
    nrow(perturb_df)>0 && all(perturb_df$truth_pass),
    nrow(perturb_df)>0 && all(perturb_df$target_pass & perturb_df$target_score_changed),
    all(abs(pred$pred_A2_posterior[!pred$timing_available]-pred$pred_A1[!pred$timing_available])<1e-12) &&
      all(abs(pred$pred_A2_pointmean[!pred$timing_available]-pred$pred_A1[!pred$timing_available])<1e-12),
    all(abs(pred$pred_A2_posterior[unsupported]-pred$pred_A1[unsupported])<1e-12),
    repro_match,
    all(spec_identity$match),
    nrow(peak_parity)==11L && file.exists(file.path(OUT,'peak_truth_parity.csv')),
    static_no_forbidden && all(forbidden_calls==0L),
    identical(unname(C2_WEIGHTS),c(.5,.5)) && identical(ETA,.5),
    !any(shape_grid$type=='B' & shape_grid$season %in% B_EXCLUDED_SHAPE_SEASONS) &&
      !any(grepl(paste(B_EXCLUDED_SHAPE_SEASONS,collapse='|'),shape_lib_df$B_shape_seasons)),
    determinism_pass,
    TRUE,
    all(latch_audit$pass),
    all(eos_parity$pass),
    TRUE,
    setequal(fold_ledger$target_season,all_seasons) && length(all_seasons)==11L,
    nrow(failures_df)==0L),
  stringsAsFactors=FALSE)
integrity$detail <- c(
  '', paste0(nrow(future_df),' origins'), paste0(nrow(future_df),' origins'), paste0(nrow(perturb_df),' folds'),
  paste0(nrow(perturb_df),' folds'), paste0(sum(!pred$timing_available),' rows'), paste0(sum(unsupported),' rows'),
  repro_lib$provenance$library_hash, '', paste0(sum(peak_parity$vintage_difference),' vintage differences'),
  paste0('runtime_calls=',sum(forbidden_calls)), 'C2 0.5/0.5, eta 0.5', fmt_seasons(b_shape_seasons),
  if (nzchar(DETERMINISM_REF)) DETERMINISM_REF else 'no_reference_run', paste0('m0=',m0_sha,';panel=',sha256_file(PANEL_PATH)),
  paste0(sum(!latch_audit$pass),' seasons failing'), paste0(sum(!eos_parity$pass),' seasons failing'),
  'source_manifest.csv', fmt_seasons(all_seasons), paste0(nrow(failures_df),' failures'))
write.csv(integrity,file.path(OUT,'integrity_checks.csv'),row.names=FALSE)

# ---------- predeclared A +2 decision rule ----------
s2 <- summary_metrics[summary_metrics$horizon==2,,drop=FALSE]
a2 <- active_summary[active_summary$horizon==2,,drop=FALSE]
if (nrow(s2)!=1L || nrow(a2)!=1L) stop('Missing +2 summaries.')
strict_majority <- a2$seasons_better>=3L && a2$seasons_better>a2$n_active_seasons/2
active_gain <- if (is.finite(a2$relative_mae_gain)) a2$relative_mae_gain else -Inf
criteria <- data.frame(
  criterion=c('service_mae_gain_ge_5pct','active_season_mae_gain_ge_5pct','strict_majority_active_seasons_improve_min3',
              'no_active_season_worsens_gt_0_15pp','worst_service_mae_not_worse_gt_0_20pp','nll_not_worse_gt_0_001',
              'all_integrity_checks_pass'),
  value=c(s2$relative_mae_gain,a2$relative_mae_gain,a2$seasons_better,a2$max_worsening_pp,
          s2$worst_A2_posterior_mae_pp-s2$worst_A1_mae_pp,s2$A2_posterior_nll-s2$A1_nll,mean(integrity$pass)),
  threshold=c(.05,.05,max(3L,floor(a2$n_active_seasons/2)+1L),.15,.20,.001,1),
  direction=c('>=','>=','>=','<=','<=','<=','=='),
  pass=c(s2$relative_mae_gain>=.05,active_gain>=.05,strict_majority,a2$max_worsening_pp<=.15+1e-12,
         (s2$worst_A2_posterior_mae_pp-s2$worst_A1_mae_pp)<=.20+1e-12,(s2$A2_posterior_nll-s2$A1_nll)<=.001+1e-12,
         all(integrity$pass)),
  stringsAsFactors=FALSE)
write.csv(criteria,file.path(OUT,'acceptance_criteria.csv'),row.names=FALSE)

promising <- all(criteria$pass)
verdict <- data.frame(
  historically_promising=promising,
  plus1_route='exact_A1_diagnostic_only',
  plus2_route=if (promising) 'posterior_C2_when_causal_M1A_timing_available_else_A1' else 'exact_A1',
  next_action=if (promising) 'shadow_eligibility_only_package_separately_from_B' else 'retain_A1_stop_retrospective_M2A_timing_search',
  interpretation_limits='final_vintage_replay_not_as_issued; conditional_on_globally_selected_frozen_M0A',
  stringsAsFactors=FALSE)
write.csv(verdict,file.path(OUT,'overall_verdict.csv'),row.names=FALSE)

manifest_paths <- c(PANEL_PATH,TIMING_PATH,M0_ARTIFACT_PATH,M1_STAGE_PATH,PLAN_PATH,SOURCE_CODE_PATHS,SCRIPT_PATH)
manifest <- data.frame(
  role=c('canonical_panel','timing_contract','frozen_m0_artifact','frozen_m1_stage','plan',
         paste0('source_code_',basename(SOURCE_CODE_PATHS)),'script'),
  path=manifest_paths,
  sha256=vapply(manifest_paths,sha256_file,character(1)),stringsAsFactors=FALSE)
write.csv(manifest,file.path(OUT,'source_manifest.csv'),row.names=FALSE)

config <- data.frame(
  key=c('benchmark_version','seasons','min_state_prior','min_timing_prior','m0_artifact_sha256','m0_params_digest',
        'm0_detector_call','m0_w_max_unmodified','amplitude_grid','k','grid_step','tau_step','passage_candidate_step',
        'passage_max_future_weeks','shape_tau_grid','C2_formula','C2_weights','eta','B_shape_exclusions',
        'plus1_policy','lower_bound_monitor_threshold_diagnostic_only','near_peak_half_width_scoring_only',
        'canonical_panel_sha256','v3_reference_library_hash','v3_reproduced_library_hash','m1_frozen_library_hash',
        'm1_artifact_id','comparators','determinism_reference'),
  value=c('v3-m2-a-posterior-c2-chronological-v1',fmt_seasons(all_seasons),MIN_STATE_PRIOR,MIN_TIMING_PRIOR,m0_sha,m0_params_digest,
          'detectIgnitionBySeason_M0v2_timing(prefix,params,iWeek=FALSE,validate_support=FALSE)',m0_params$w_max,
          '0.08:0.02:0.44',8,.01,.1,PASSAGE_STEP,PASSAGE_MAX_FUTURE,'-8:0.25:8',
          '0.5*median_pooled_AB(LR)+0.5*median_A(LR)','0.5 0.5',ETA,fmt_seasons(B_EXCLUDED_SHAPE_SEASONS),
          'diagnostic_only_exact_A1_route',LOWER_BOUND_MONITOR,NEAR_PEAK_HALF_WIDTH,sha256_file(PANEL_PATH),
          EXPECTED_V3_REFERENCE_LIBRARY_HASH,repro_lib$provenance$library_hash,EXPECTED_M1_FROZEN_LIBRARY_HASH,
          m1_stage$artifact_id,'A0_persistence;A1_state;A2_pointmean_C2;A2_posterior_C2',
          if (nzchar(DETERMINISM_REF)) DETERMINISM_REF else ''),
  stringsAsFactors=FALSE)
write.csv(config,file.path(OUT,'benchmark_config.csv'),row.names=FALSE)

cat('\nSummary metrics\n'); print(summary_metrics,row.names=FALSE,digits=6)
cat('\nActive timing summary\n'); print(active_summary,row.names=FALSE,digits=6)
cat('\nIntegrity\n'); print(integrity[,c('check','pass')],row.names=FALSE)
cat('\nAcceptance criteria\n'); print(criteria,row.names=FALSE,digits=6)
cat('\nVerdict\n'); print(verdict,row.names=FALSE)
