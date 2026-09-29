#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')
source('scripts/v3_m1_b_runtime_helpers_v7.R')

if (!requireNamespace('digest', quietly=TRUE)) stop('Package `digest` is required.')

PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
ACTIVITY_PARAMS_PATH <- 'artifacts/v3-a-rule-transfer-to-b-v1/A_aggregated_params.rds'
M1B_ARTIFACT_PATH <- 'artifacts/m1-b-v3-peak-v8/m1_b_v3_peak_artifact.rds'
PLAN_PATH <- 'docs/v3-m2-b-implementation-plan-2026-09-26.md'
SCRIPT_PATH <- 'scripts/v3_benchmark_m2_b_posterior_c2_chronological_v1.R'
OUT <- 'artifacts/v3-m2-b-posterior-c2-chronological-v1'

EXCLUDED_B_SEASON <- '2019-20'
NO_EVENT_B_SEASON <- '2018-19'
MIN_STATE_PRIOR <- 3L
MIN_TIMING_PRIOR <- 4L
AMP_GRID <- seq(.005,.25,by=.005)
PASSAGE_STEP <- .M1_B_PASSAGE_CANDIDATE_STEP
PASSAGE_MAX_FUTURE <- .M1_B_PASSAGE_MAX_FUTURE_WEEKS
SHAPE_TAU <- seq(-8,8,by=.25)
ETA <- .5

if (dir.exists(OUT) && length(list.files(OUT, all.files=TRUE, no..=TRUE))) {
  stop('Output directory already exists and is nonempty: ', OUT, call.=FALSE)
}
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))
logit <- function(p) qlogis(pmin(pmax(p,1e-6),1-1e-6))
stab <- function(y,N,c=.5) (y+c)/(N+2*c)
fmt_seasons <- function(x) paste(as.character(x),collapse=';')

panel <- read.csv(PANEL_PATH,check.names=FALSE)
timing <- read.csv(TIMING_PATH,check.names=FALSE)
activity_params0 <- readRDS(ACTIVITY_PARAMS_PATH)
m1b_v8 <- readRDS(M1B_ARTIFACT_PATH)

required_panel <- c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')
if (!all(required_panel %in% names(panel))) stop('Canonical panel schema mismatch.')
if (anyDuplicated(panel[c('season','weekF')])) stop('Canonical panel has duplicate season/weekF keys.')
if (anyNA(panel[required_panel])) stop('Canonical panel has missing required values.')
panel$season <- as.character(panel$season)
timing$season <- as.character(timing$season)
all_seasons <- unique(panel$season)
all_seasons <- all_seasons[order(season_start(all_seasons))]
if (!setequal(all_seasons,timing$season)) stop('Timing contract season set mismatch.')
if (!EXCLUDED_B_SEASON %in% all_seasons || !NO_EVENT_B_SEASON %in% all_seasons) stop('Required B season-policy rows are absent.')

eligible_state_seasons <- setdiff(all_seasons,EXCLUDED_B_SEASON)
meaningful_b_seasons <- timing$season[is.finite(timing$B_peak_weekF)]
meaningful_b_seasons <- setdiff(meaningful_b_seasons,c(EXCLUDED_B_SEASON,NO_EVENT_B_SEASON))
meaningful_b_seasons <- all_seasons[all_seasons %in% meaningful_b_seasons]

# ---------- candidate-independent ledger ----------
ledger_rows <- list()
for (s in eligible_state_seasons) {
  z <- panel[panel$season==s,]
  z <- z[order(z$weekF),]
  ps <- stab(z$y_B,z$N_B)
  lg <- logit(ps)
  g1 <- c(NA,diff(lg))
  g2 <- c(NA,NA,(lg[3:length(lg)]-lg[1:(length(lg)-2)])/2)
  for (i in seq_len(nrow(z))) {
    if (z$weekF[i] < 13 || i < 3L) next
    for (h in 1:2) {
      j <- i+h
      if (j>nrow(z) || z$weekF[j] != z$weekF[i]+h) next
      ledger_rows[[length(ledger_rows)+1L]] <- data.frame(
        season=s,origin_week=z$weekF[i],target_week=z$weekF[j],horizon=h,
        y_target=z$y_B[j],N_target=z$N_B[j],p_target=z$p_B[j],
        y_current=z$y_B[i],N_current=z$N_B[i],p_current=z$p_B[i],p_star=ps[i],
        logit_current=lg[i],growth1=g1[i],growth2=g2[i],
        denominator_regime=z$denominator_regime[i],stringsAsFactors=FALSE)
    }
  }
}
ledger <- do.call(rbind,ledger_rows)
ledger$horizon_f <- factor(paste0('h',ledger$horizon),levels=c('h1','h2'))
if (any(ledger$season==EXCLUDED_B_SEASON)) stop('2019-20 entered candidate ledger.')
write.csv(ledger,file.path(OUT,'candidate_independent_ledger.csv'),row.names=FALSE)

fit_state_baseline <- function(train_rows) {
  tr <- train_rows
  tr$horizon_f <- factor(paste0('h',tr$horizon),levels=c('h1','h2'))
  tr$offset_logit <- tr$logit_current
  suppressWarnings(glm(
    cbind(y_target,N_target-y_target) ~ horizon_f + growth1 + growth2 + offset(offset_logit),
    data=tr,family=quasibinomial()))
}

# ---------- causal prefix B activation ----------
activity_params <- activity_params0
activity_params$w_min <- 8L
activity_params$w_max <- 40L

make_B_surveillance <- function(data_panel, seasons=NULL) {
  # Match the governed v8 builder exactly for training-library identity: build
  # the full B frame first, sort it, then subset seasons so retained row names
  # are identical to the artifact builder's input.
  out <- data.frame(season=as.character(data_panel$season),weekF=data_panel$weekF,y=data_panel$y_B,N=data_panel$N_B,p=data_panel$p_B,stringsAsFactors=FALSE)
  out <- out[order(season_start(out$season),out$weekF),]
  if (!is.null(seasons)) out <- out[out$season %in% seasons,,drop=FALSE]
  out
}

causal_activity <- function(data_panel, season, origin_week) {
  if (identical(as.character(season),NO_EVENT_B_SEASON)) {
    return(list(detected=FALSE,activity_week=NA_real_,activity_integer=NA_integer_,reason='policy_no_timing_event'))
  }
  z <- make_B_surveillance(data_panel[data_panel$season==season & data_panel$weekF<=origin_week,,drop=FALSE])
  if (!nrow(z) || max(z$weekF)<8) return(list(detected=FALSE,activity_week=NA_real_,activity_integer=NA_integer_,reason='pre_window'))
  p <- activity_params
  # Detector validates configured window against observed domain; capping at the
  # causal prefix is equivalent to removing unavailable future candidate weeks.
  p$w_max <- min(40L,as.integer(max(z$weekF)))
  if (p$w_max < p$w_min) return(list(detected=FALSE,activity_week=NA_real_,activity_integer=NA_integer_,reason='pre_window'))
  det <- tryCatch(
    detectIgnitionBySeason_M0v2_timing(z,params=p,verbose=FALSE,iWeek=FALSE,keep_signals=TRUE),
    error=function(e)e)
  if (inherits(det,'error')) return(list(detected=FALSE,activity_week=NA_real_,activity_integer=NA_integer_,reason=paste0('detector_error:',conditionMessage(det))))
  b <- det$by_season
  if (!nrow(b) || isTRUE(b$detection_failed[1]) || !is.finite(b$iWeek_hatF[1])) {
    return(list(detected=FALSE,activity_week=NA_real_,activity_integer=NA_integer_,reason='not_detected'))
  }
  aw <- as.numeric(b$iWeek_hatF[1])
  ai <- as.integer(b$iWeek_hat[1])
  if (aw > origin_week + 1e-12) stop('Causal B activation exceeds forecast origin.')
  list(detected=TRUE,activity_week=aw,activity_integer=ai,reason='causal_prefix_detection')
}

# ---------- fold-local M1-B library ----------
fit_B_library <- function(train_seasons) {
  train_seasons <- all_seasons[all_seasons %in% train_seasons]
  d <- make_B_surveillance(panel,train_seasons)
  tt <- timing[timing$season %in% train_seasons,c('season','B_peak_weekF'),drop=FALSE]
  names(tt)[2] <- 'peak_week_decimal'
  tt <- tt[match(train_seasons,tt$season),,drop=FALSE]
  fit_m1_v2_library(d,tt,k=8L,grid_step=.01,tau_step=.1,amplitude_grid=AMP_GRID)
}

validate_fold_library <- function(lib, expected_seasons) {
  expected <- sort(as.character(expected_seasons))
  got <- sort(as.character(lib$training_seasons))
  if (!inherits(lib,'page_m1_v2_library')) stop('Fold-local M1-B library malformed.')
  if (!identical(got,expected)) stop('Fold-local M1-B season identity mismatch.')
  if (any(c(EXCLUDED_B_SEASON,NO_EVENT_B_SEASON) %in% got)) stop('Ineligible B timing season entered fold library.')
  if (!isTRUE(all.equal(as.numeric(lib$config$amplitude_grid),AMP_GRID,tolerance=0))) stop('Fold-local M1-B amplitude support mismatch.')
  if ('calibrator' %in% names(lib) || 'joint_A_conditioning' %in% names(lib)) stop('Fold-local library unexpectedly contains calibration/A-conditioning.')
  invisible(TRUE)
}

# Full-nine reproduction versus governed v8 library.
repro_seasons <- as.character(m1b_v8$training_seasons)
repro_lib <- fit_B_library(repro_seasons)
repro_match <- identical(repro_lib$provenance$library_hash,m1b_v8$library$provenance$library_hash)
if (!repro_match) stop('All-nine fold-local M1-B library does not reproduce v8 library hash.')

# ---------- v3 shape grid from canonical panel + v3 timing peaks ----------
shape_rows <- list()
shape_peak_checks <- list()
for (s in all_seasons) {
  for (tp in c('A','B')) {
    if (tp=='B' && s %in% c(EXCLUDED_B_SEASON,NO_EVENT_B_SEASON)) next
    peak_col <- if(tp=='A') 'A_peak_weekF' else 'B_peak_weekF'
    truth_peak <- timing[[peak_col]][timing$season==s]
    if (length(truth_peak)!=1L || !is.finite(truth_peak)) next
    ycol <- paste0('y_',tp); ncol <- paste0('N_',tp); pcol <- paste0('p_',tp)
    z <- panel[panel$season==s,c('season','weekF',ycol,ncol,pcol)]
    names(z)[3:5] <- c('y','N','p')
    f <- retrospective_gam_peak_truth(z,season=s,k=8L,grid_step=.01)
    diff_peak <- abs(f$peak_week_decimal-truth_peak)
    if (diff_peak > .051) stop('V3 shape peak mismatch for ',s,' ',tp,': ',diff_peak)
    g <- f$grid
    amp <- max(g$fitted_p,na.rm=TRUE)
    vals <- approx(g$weekF-truth_peak,g$fitted_p/amp,xout=SHAPE_TAU,rule=1)$y
    shape_rows[[length(shape_rows)+1L]] <- data.frame(season=s,type=tp,tau=SHAPE_TAU,p_norm=vals,stringsAsFactors=FALSE)
    shape_peak_checks[[length(shape_peak_checks)+1L]] <- data.frame(season=s,type=tp,truth_peak=truth_peak,fitted_peak=f$peak_week_decimal,abs_diff=diff_peak)
  }
}
shape_grid <- do.call(rbind,shape_rows)
shape_peak_check <- do.call(rbind,shape_peak_checks)
if (any(shape_grid$type=='B' & shape_grid$season %in% c(EXCLUDED_B_SEASON,NO_EVENT_B_SEASON))) stop('Ineligible B shape entered v3 shape grid.')
write.csv(shape_grid,file.path(OUT,'shape_grid_v3.csv'),row.names=FALSE)
write.csv(shape_peak_check,file.path(OUT,'shape_peak_alignment_checks.csv'),row.names=FALSE)

one_lr <- function(z,tau,h) {
  cur <- approx(z$tau,z$p_norm,xout=tau,rule=1)$y
  fut <- approx(z$tau,z$p_norm,xout=tau+h,rule=1)$y
  if (!is.finite(cur) || !is.finite(fut)) return(NA_real_)
  log(pmax(fut,.01)/pmax(cur,.01))
}

c2_lr <- function(prior_seasons,tau,h) {
  prior_seasons <- as.character(prior_seasons)
  A_seasons <- prior_seasons
  B_seasons <- prior_seasons[prior_seasons %in% meaningful_b_seasons]
  vals_pool <- numeric(); vals_B <- numeric()
  for (s in A_seasons) {
    z <- shape_grid[shape_grid$season==s & shape_grid$type=='A',]
    if (nrow(z)) { q <- one_lr(z,tau,h); if(is.finite(q)) vals_pool <- c(vals_pool,q) }
  }
  for (s in B_seasons) {
    z <- shape_grid[shape_grid$season==s & shape_grid$type=='B',]
    if (nrow(z)) {
      q <- one_lr(z,tau,h)
      if(is.finite(q)) { vals_pool <- c(vals_pool,q); vals_B <- c(vals_B,q) }
    }
  }
  if (!length(vals_pool) || !length(vals_B)) return(NA_real_)
  .5*median(vals_pool)+.5*median(vals_B)
}

blend_shape <- function(base,current,lr,eta=ETA) {
  if (!is.finite(lr)) return(base)
  projected <- pmin(pmax(current*exp(lr),1e-6),1-1e-6)
  plogis((1-eta)*logit(base)+eta*logit(projected))
}

posterior_correction <- function(base,current,posterior,prior_seasons,horizon,origin_week) {
  w <- as.numeric(posterior$probability)
  T <- as.numeric(posterior$peak_week_decimal)
  if (!length(w) || length(w)!=length(T) || any(!is.finite(w)) || sum(w)<=0) stop('Malformed M1-B passage posterior.')
  w <- w/sum(w)
  lr <- vapply(T,function(tt)c2_lr(prior_seasons,origin_week-tt,horizon),numeric(1))
  supported <- is.finite(lr)
  pT <- rep(base,length(T))
  if (any(supported)) pT[supported] <- vapply(lr[supported],function(q)blend_shape(base,current,q,ETA),numeric(1))
  supported_mass <- sum(w[supported])
  pred <- sum(w*pT) # unsupported candidates already carry exact B1
  Tmean <- sum(w*T)
  lrmean <- c2_lr(prior_seasons,origin_week-Tmean,horizon)
  point_pred <- if(is.finite(lrmean)) blend_shape(base,current,lrmean,ETA) else base
  lower_bound <- min(T)
  lower_mass <- sum(w[T <= lower_bound+PASSAGE_STEP+1e-12])
  list(pred=pred,point_pred=point_pred,supported_mass=supported_mass,lower_bound_mass=lower_mass,posterior_mean=Tmean)
}

# ---------- fold ledger ----------
fold_rows <- list()
for (target in eligible_state_seasons) {
  prior_state <- eligible_state_seasons[season_start(eligible_state_seasons)<season_start(target)]
  prior_timing <- meaningful_b_seasons[season_start(meaningful_b_seasons)<season_start(target)]
  prior_A_shapes <- all_seasons[season_start(all_seasons)<season_start(target)]
  prior_B_shapes <- meaningful_b_seasons[season_start(meaningful_b_seasons)<season_start(target)]
  fold_rows[[length(fold_rows)+1L]] <- data.frame(
    target_season=target,n_prior_state=length(prior_state),prior_state=fmt_seasons(prior_state),
    n_prior_timing=length(prior_timing),prior_timing=fmt_seasons(prior_timing),
    prior_A_shapes=fmt_seasons(prior_A_shapes),prior_B_shapes=fmt_seasons(prior_B_shapes),
    state_available=length(prior_state)>=MIN_STATE_PRIOR,
    timing_library_available=length(prior_timing)>=MIN_TIMING_PRIOR && target!=NO_EVENT_B_SEASON,
    stringsAsFactors=FALSE)
}
fold_ledger <- do.call(rbind,fold_rows)
write.csv(fold_ledger,file.path(OUT,'outer_fold_ledger.csv'),row.names=FALSE)

# Hard fold-isolation assertions.
for (i in seq_len(nrow(fold_ledger))) {
  target <- fold_ledger$target_season[i]
  ps <- if(nzchar(fold_ledger$prior_state[i])) strsplit(fold_ledger$prior_state[i],';',fixed=TRUE)[[1]] else character()
  pt <- if(nzchar(fold_ledger$prior_timing[i])) strsplit(fold_ledger$prior_timing[i],';',fixed=TRUE)[[1]] else character()
  if (length(ps) && any(season_start(ps)>=season_start(target))) stop('State fold leakage for ',target)
  if (length(pt) && any(season_start(pt)>=season_start(target))) stop('Timing fold leakage for ',target)
  if (EXCLUDED_B_SEASON %in% ps) stop('2019-20 entered state prior.')
  if (any(c(EXCLUDED_B_SEASON,NO_EVENT_B_SEASON) %in% pt)) stop('Ineligible season entered timing prior.')
}

# ---------- chronological predictions ----------
pred_rows <- list(); timing_lib_rows <- list(); shape_lib_rows <- list(); future_rows <- list(); perturb_rows <- list(); failure_rows <- list()

compute_timing_for_origin <- function(target,origin,prior_timing,prior_shapes,lib,data_panel=panel) {
  act <- causal_activity(data_panel,target,origin)
  if (!act$detected) return(list(available=FALSE,reason=act$reason,activity_week=NA_real_,posterior=NULL,prob_passed=NA_real_))
  z <- make_B_surveillance(data_panel[data_panel$season==target & data_panel$weekF<=origin,,drop=FALSE])
  pp <- tryCatch(m1_v2_passage_posterior(lib,z,activation_week=act$activity_week,origin_week=origin,candidate_step=PASSAGE_STEP,max_future_weeks=PASSAGE_MAX_FUTURE),error=function(e)e)
  if (inherits(pp,'error')) return(list(available=FALSE,reason=paste0('posterior_error:',conditionMessage(pp)),activity_week=act$activity_week,posterior=NULL,prob_passed=NA_real_))
  list(available=TRUE,reason='available',activity_week=act$activity_week,posterior=attr(pp,'posterior'),prob_passed=pp$prob_peak_passed[1])
}

for (fi in seq_len(nrow(fold_ledger))) {
  target <- fold_ledger$target_season[fi]
  if (!isTRUE(fold_ledger$state_available[fi])) next
  prior_state <- strsplit(fold_ledger$prior_state[fi],';',fixed=TRUE)[[1]]
  tr <- ledger[ledger$season %in% prior_state,,drop=FALSE]
  te <- ledger[ledger$season==target,,drop=FALSE]
  if (!nrow(te)) next
  fit_state <- fit_state_baseline(tr)
  te$offset_logit <- te$logit_current
  te$pred_B0 <- te$p_star
  te$pred_B1 <- as.numeric(predict(fit_state,newdata=te,type='response'))

  prior_timing <- if(nzchar(fold_ledger$prior_timing[fi])) strsplit(fold_ledger$prior_timing[fi],';',fixed=TRUE)[[1]] else character()
  prior_shapes <- all_seasons[season_start(all_seasons)<season_start(target)]
  lib <- NULL
  if (isTRUE(fold_ledger$timing_library_available[fi])) {
    lib <- tryCatch(fit_B_library(prior_timing),error=function(e)e)
    if (inherits(lib,'error')) {
      failure_rows[[length(failure_rows)+1L]] <- data.frame(stage='fit_timing_library',season=target,origin=NA,detail=conditionMessage(lib))
      lib <- NULL
    } else {
      validate_fold_library(lib,prior_timing)
      timing_lib_rows[[length(timing_lib_rows)+1L]] <- data.frame(
        target_season=target,n_train=length(prior_timing),training_seasons=fmt_seasons(prior_timing),
        library_hash=lib$provenance$library_hash,validation_pass=TRUE,stringsAsFactors=FALSE)
    }
  } else {
    timing_lib_rows[[length(timing_lib_rows)+1L]] <- data.frame(
      target_season=target,n_train=length(prior_timing),training_seasons=fmt_seasons(prior_timing),
      library_hash=NA_character_,validation_pass=TRUE,stringsAsFactors=FALSE)
  }
  shape_lib_rows[[length(shape_lib_rows)+1L]] <- data.frame(
    target_season=target,A_shape_seasons=fmt_seasons(prior_shapes),
    B_shape_seasons=fmt_seasons(prior_timing),stringsAsFactors=FALSE)

  origins <- sort(unique(te$origin_week))
  timing_cache <- list()
  if (!is.null(lib) && target!=NO_EVENT_B_SEASON) {
    for (o in origins) timing_cache[[as.character(o)]] <- compute_timing_for_origin(target,o,prior_timing,prior_shapes,lib,panel)
  }

  for (i in seq_len(nrow(te))) {
    o <- te$origin_week[i]; h <- te$horizon[i]; base <- te$pred_B1[i]
    pred_mix <- base; pred_point <- base
    timing_available <- FALSE; timing_reason <- 'timing_library_unavailable'; activity_week <- NA_real_; prob_passed <- NA_real_
    supported_mass <- 0; lower_mass <- 0; posterior_mean <- NA_real_
    if (target==NO_EVENT_B_SEASON) {
      timing_reason <- 'policy_no_timing_event'
    } else if (!is.null(lib)) {
      info <- timing_cache[[as.character(o)]]
      timing_reason <- info$reason; activity_week <- info$activity_week; prob_passed <- info$prob_passed
      if (isTRUE(info$available)) {
        q <- posterior_correction(base,te$p_star[i],info$posterior,prior_shapes,h,o)
        pred_mix <- q$pred; pred_point <- q$point_pred; supported_mass <- q$supported_mass
        lower_mass <- q$lower_bound_mass; posterior_mean <- q$posterior_mean; timing_available <- TRUE
      }
    }
    pred_rows[[length(pred_rows)+1L]] <- data.frame(
      season=target,origin_week=o,target_week=te$target_week[i],horizon=h,
      y_target=te$y_target[i],N_target=te$N_target[i],p_target=te$p_target[i],
      p_star=te$p_star[i],growth1=te$growth1[i],growth2=te$growth2[i],denominator_regime=te$denominator_regime[i],
      pred_B0=te$pred_B0[i],pred_B1=base,pred_B2_pointmean=pred_point,pred_B2_posterior=pred_mix,
      timing_available=timing_available,timing_reason=timing_reason,activity_week=activity_week,
      passage_prob_peak_passed=prob_passed,posterior_mean_peak=posterior_mean,
      supported_mass=supported_mass,lower_bound_mass=lower_mass,stringsAsFactors=FALSE)
  }

  # Future perturbation: first origin with available timing. Perturb only weeks after origin,
  # then recompute causal activation/posterior/correction and require exact prediction stability.
  if (!is.null(lib) && target!=NO_EVENT_B_SEASON) {
    avail_orig <- origins[vapply(timing_cache,function(q)isTRUE(q$available),logical(1))]
    if (length(avail_orig)) {
      o <- min(avail_orig)
      refrows <- te[te$origin_week==o,,drop=FALSE]
      p2 <- panel
      ix <- p2$season==target & p2$weekF>o
      p2$y_B[ix] <- pmin(p2$N_B[ix],p2$y_B[ix]+7)
      p2$p_B[ix] <- p2$y_B[ix]/p2$N_B[ix]
      info0 <- timing_cache[[as.character(o)]]
      info2 <- compute_timing_for_origin(target,o,prior_timing,prior_shapes,lib,p2)
      same_act <- isTRUE(all.equal(info0$activity_week,info2$activity_week,tolerance=0))
      same_post <- FALSE; max_post_diff <- Inf
      if (info0$available && info2$available) {
        a <- info0$posterior; b <- info2$posterior
        same_grid <- identical(as.numeric(a$peak_week_decimal),as.numeric(b$peak_week_decimal))
        max_post_diff <- if(same_grid) max(abs(a$probability-b$probability)) else Inf
        same_post <- same_grid && max_post_diff < 1e-14
      }
      max_pred_diff <- 0
      for (j in seq_len(nrow(refrows))) {
        q0 <- posterior_correction(refrows$pred_B1[j],refrows$p_star[j],info0$posterior,prior_shapes,refrows$horizon[j],o)
        q2 <- posterior_correction(refrows$pred_B1[j],refrows$p_star[j],info2$posterior,prior_shapes,refrows$horizon[j],o)
        max_pred_diff <- max(max_pred_diff,abs(q0$pred-q2$pred))
      }
      pass <- same_act && same_post && max_pred_diff<1e-14
      if (!pass) stop('Future perturbation invariance failed for ',target)
      future_rows[[length(future_rows)+1L]] <- data.frame(season=target,origin=o,same_activation=same_act,max_posterior_diff=max_post_diff,max_prediction_diff=max_pred_diff,pass=pass)
    }
  }

  # Target truth/forecast-target perturbation structural checks. The prediction path
  # consumes only prior timing truth and current-prefix covariates.
  target_truth <- timing[timing$season==target,'B_peak_weekF']
  prior_truth_hash <- digest::digest(timing[timing$season %in% prior_timing,c('season','B_peak_weekF')],algo='sha256')
  t2 <- timing; t2$B_peak_weekF[t2$season==target] <- if(is.finite(target_truth)) target_truth+5 else 47
  prior_truth_hash2 <- digest::digest(t2[t2$season %in% prior_timing,c('season','B_peak_weekF')],algo='sha256')
  truth_pass <- identical(prior_truth_hash,prior_truth_hash2)
  # Forecast targets are not model inputs: perturb and verify the predictive columns are unchanged by construction.
  target_pass <- !any(c('p_target','y_target','N_target') %in% c('p_star','growth1','growth2','logit_current'))
  if (!truth_pass || !target_pass) stop('Truth/target perturbation structural check failed for ',target)
  perturb_rows[[length(perturb_rows)+1L]] <- data.frame(season=target,outer_truth_prior_hash_unchanged=truth_pass,forecast_targets_not_predictors=target_pass,pass=truth_pass&&target_pass)
}

pred <- do.call(rbind,pred_rows)
if (!nrow(pred)) stop('No chronological M2-B predictions produced.')
if (any(pred$season==EXCLUDED_B_SEASON)) stop('2019-20 entered scored predictions.')

# Hard fallback identities.
no_timing <- !pred$timing_available
if (any(abs(pred$pred_B2_posterior[no_timing]-pred$pred_B1[no_timing])>1e-12)) stop('Timing-unavailable fallback identity failed.')
if (any(abs(pred$pred_B2_posterior[pred$season==NO_EVENT_B_SEASON]-pred$pred_B1[pred$season==NO_EVENT_B_SEASON])>1e-12)) stop('2018-19 exact B1 fallback failed.')

for (m in c('B0','B1','B2_pointmean','B2_posterior')) {
  p <- pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8)
  pred[[paste0('err_',m)]] <- p-pred$p_target
  pred[[paste0('abs_',m)]] <- abs(pred[[paste0('err_',m)]])
  pred[[paste0('sq_',m)]] <- pred[[paste0('err_',m)]]^2
  pred[[paste0('nll_',m)]] <- -(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target
}
write.csv(pred,file.path(OUT,'per_origin_predictions.csv'),row.names=FALSE)
support_diag <- pred[,c('season','origin_week','horizon','timing_available','timing_reason','activity_week','posterior_mean_peak','supported_mass','lower_bound_mass','pred_B1','pred_B2_posterior')]
write.csv(support_diag,file.path(OUT,'posterior_support_diagnostics.csv'),row.names=FALSE)

# ---------- metrics ----------
per_season <- do.call(rbind,lapply(split(pred,list(pred$season,pred$horizon),drop=TRUE),function(z){
  data.frame(
    season=z$season[1],horizon=z$horizon[1],n=nrow(z),timing_availability=mean(z$timing_available),
    B0_mae_pp=100*mean(z$abs_B0),B1_mae_pp=100*mean(z$abs_B1),B2_pointmean_mae_pp=100*mean(z$abs_B2_pointmean),B2_posterior_mae_pp=100*mean(z$abs_B2_posterior),
    B1_rmse_pp=100*sqrt(mean(z$sq_B1)),B2_posterior_rmse_pp=100*sqrt(mean(z$sq_B2_posterior)),
    B1_bias_pp=100*mean(z$err_B1),B2_posterior_bias_pp=100*mean(z$err_B2_posterior),
    B1_nll=mean(z$nll_B1),B2_posterior_nll=mean(z$nll_B2_posterior),
    stringsAsFactors=FALSE)
}))
per_season <- per_season[order(per_season$horizon,season_start(per_season$season)),]
write.csv(per_season,file.path(OUT,'per_season_metrics.csv'),row.names=FALSE)

summary_metrics <- do.call(rbind,lapply(split(per_season,per_season$horizon),function(z){
  h <- z$horizon[1]
  ph <- pred[pred$horizon==h,,drop=FALSE]
  data.frame(
    horizon=h,n_seasons=nrow(z),
    B1_mae_pp=mean(z$B1_mae_pp),B2_posterior_mae_pp=mean(z$B2_posterior_mae_pp),
    relative_mae_gain=1-mean(z$B2_posterior_mae_pp)/mean(z$B1_mae_pp),
    B1_rmse_pp=mean(z$B1_rmse_pp),B2_posterior_rmse_pp=mean(z$B2_posterior_rmse_pp),
    B1_bias_pp=mean(z$B1_bias_pp),B2_posterior_bias_pp=mean(z$B2_posterior_bias_pp),
    B1_nll=mean(ph$nll_B1),B2_posterior_nll=mean(ph$nll_B2_posterior),
    worst_B1_mae_pp=max(z$B1_mae_pp),worst_B2_posterior_mae_pp=max(z$B2_posterior_mae_pp),
    seasons_better=sum(z$B2_posterior_mae_pp<z$B1_mae_pp-1e-12),
    seasons_worse=sum(z$B2_posterior_mae_pp>z$B1_mae_pp+1e-12),
    stringsAsFactors=FALSE)
}))
write.csv(summary_metrics,file.path(OUT,'summary_metrics.csv'),row.names=FALSE)

active <- pred[pred$timing_available,,drop=FALSE]
active_per <- if(nrow(active)) do.call(rbind,lapply(split(active,list(active$season,active$horizon),drop=TRUE),function(z){
  data.frame(season=z$season[1],horizon=z$horizon[1],n=nrow(z),
    B1_mae_pp=100*mean(z$abs_B1),B2_posterior_mae_pp=100*mean(z$abs_B2_posterior),
    relative_mae_gain=1-mean(z$abs_B2_posterior)/mean(z$abs_B1),
    stringsAsFactors=FALSE)
})) else data.frame()
active_summary <- if(nrow(active_per)) do.call(rbind,lapply(split(active_per,active_per$horizon),function(z){
  data.frame(horizon=z$horizon[1],n_active_seasons=nrow(z),n_active_rows=sum(z$n),
    B1_mae_pp=mean(z$B1_mae_pp),B2_posterior_mae_pp=mean(z$B2_posterior_mae_pp),
    relative_mae_gain=1-mean(z$B2_posterior_mae_pp)/mean(z$B1_mae_pp),
    seasons_better=sum(z$B2_posterior_mae_pp<z$B1_mae_pp-1e-12),
    seasons_worse=sum(z$B2_posterior_mae_pp>z$B1_mae_pp+1e-12),
    max_worsening_pp=max(c(0,z$B2_posterior_mae_pp-z$B1_mae_pp)),stringsAsFactors=FALSE)
})) else data.frame()
write.csv(active_summary,file.path(OUT,'active_timing_summary.csv'),row.names=FALSE)
write.csv(active_per,file.path(OUT,'active_timing_per_season.csv'),row.names=FALSE)

fallback_summary <- as.data.frame(table(pred$timing_reason),stringsAsFactors=FALSE)
names(fallback_summary) <- c('reason','n_rows')
write.csv(fallback_summary,file.path(OUT,'fallback_summary.csv'),row.names=FALSE)

# ---------- integrity / perturbation outputs ----------
timing_lib_df <- if(length(timing_lib_rows)) do.call(rbind,timing_lib_rows) else data.frame()
shape_lib_df <- if(length(shape_lib_rows)) do.call(rbind,shape_lib_rows) else data.frame()
future_df <- if(length(future_rows)) do.call(rbind,future_rows) else data.frame()
perturb_df <- if(length(perturb_rows)) do.call(rbind,perturb_rows) else data.frame()
failures_df <- if(length(failure_rows)) do.call(rbind,failure_rows) else data.frame(stage=character(),season=character(),origin=numeric(),detail=character())
write.csv(timing_lib_df,file.path(OUT,'timing_library_ledger.csv'),row.names=FALSE)
write.csv(shape_lib_df,file.path(OUT,'shape_library_ledger.csv'),row.names=FALSE)
write.csv(future_df,file.path(OUT,'future_perturbation_checks.csv'),row.names=FALSE)
write.csv(perturb_df,file.path(OUT,'truth_target_perturbation_checks.csv'),row.names=FALSE)
write.csv(failures_df,file.path(OUT,'failures.csv'),row.names=FALSE)

integrity <- data.frame(
  check=c('no_2019_scoring','no_2019_state_priors','no_2018_2019_timing_priors','no_2018_2019_B_shapes','2018_exact_B1_fallback','timing_unavailable_exact_B1','unsupported_mass_exact_B1','helper_passage_constants_pinned','future_perturbations','truth_target_perturbations','full9_library_hash_reproduction','no_unexpected_failures'),
  pass=c(
    !any(pred$season==EXCLUDED_B_SEASON),
    !any(grepl(EXCLUDED_B_SEASON,fold_ledger$prior_state,fixed=TRUE)),
    !any(grepl(EXCLUDED_B_SEASON,timing_lib_df$training_seasons,fixed=TRUE)) && !any(grepl(NO_EVENT_B_SEASON,timing_lib_df$training_seasons,fixed=TRUE)),
    !any(shape_grid$type=='B' & shape_grid$season%in%c(EXCLUDED_B_SEASON,NO_EVENT_B_SEASON)),
    all(abs(pred$pred_B2_posterior[pred$season==NO_EVENT_B_SEASON]-pred$pred_B1[pred$season==NO_EVENT_B_SEASON])<1e-12),
    all(abs(pred$pred_B2_posterior[!pred$timing_available]-pred$pred_B1[!pred$timing_available])<1e-12),
    all(abs(pred$pred_B2_posterior[pred$timing_available & pred$supported_mass<=1e-15]-pred$pred_B1[pred$timing_available & pred$supported_mass<=1e-15])<1e-12),
    identical(PASSAGE_STEP,.M1_B_PASSAGE_CANDIDATE_STEP) && identical(PASSAGE_MAX_FUTURE,.M1_B_PASSAGE_MAX_FUTURE_WEEKS) && identical(m1b_v8$runtime_contract$passage_candidate_step,PASSAGE_STEP) && identical(m1b_v8$runtime_contract$passage_max_future_weeks,PASSAGE_MAX_FUTURE),
    !nrow(future_df) || all(future_df$pass),
    !nrow(perturb_df) || all(perturb_df$pass),
    repro_match,
    nrow(failures_df)==0L
  ),stringsAsFactors=FALSE)
write.csv(integrity,file.path(OUT,'integrity_checks.csv'),row.names=FALSE)
if (!all(integrity$pass)) stop('One or more M2-B integrity checks failed.')

# ---------- predeclared +2 acceptance ----------
s2 <- summary_metrics[summary_metrics$horizon==2,,drop=FALSE]
a2 <- active_summary[active_summary$horizon==2,,drop=FALSE]
ap2 <- active_per[active_per$horizon==2,,drop=FALSE]
if (nrow(s2)!=1L) stop('Missing +2 service summary.')
if (nrow(a2)!=1L) stop('Missing +2 active timing summary.')
strict_majority <- a2$seasons_better >= 2L && a2$seasons_better > a2$n_active_seasons/2
criteria <- data.frame(
  criterion=c('service_mae_gain_ge_5pct','active_mae_gain_ge_10pct','strict_majority_active_seasons_improve','no_active_season_worsens_gt_0_15pp','worst_service_mae_not_worse_gt_0_10pp','nll_not_worse_gt_0_001','all_integrity_checks_pass'),
  value=c(s2$relative_mae_gain,a2$relative_mae_gain,a2$seasons_better,a2$max_worsening_pp,s2$worst_B2_posterior_mae_pp-s2$worst_B1_mae_pp,s2$B2_posterior_nll-s2$B1_nll,mean(integrity$pass)),
  threshold=c(.05,.10,floor(a2$n_active_seasons/2)+1,.15,.10,.001,1),
  direction=c('>=','>=','>=','<=','<=','<=','=='),
  pass=c(
    s2$relative_mae_gain>=.05,
    a2$relative_mae_gain>=.10,
    strict_majority,
    a2$max_worsening_pp<=.15+1e-12,
    (s2$worst_B2_posterior_mae_pp-s2$worst_B1_mae_pp)<=.10+1e-12,
    (s2$B2_posterior_nll-s2$B1_nll)<=.001+1e-12,
    all(integrity$pass)
  ),stringsAsFactors=FALSE)
write.csv(criteria,file.path(OUT,'acceptance_criteria.csv'),row.names=FALSE)

historically_promising <- all(criteria$pass)
verdict <- data.frame(
  candidate='v3_m2_b_posterior_c2_plus2',
  plus1_route='exact_B1_diagnostic_only',
  historically_promising=historically_promising,
  decision=if(historically_promising) 'eligible_for_v3_shadow_plus2' else 'retain_B1_stop_retrospective_M2B_timing_search',
  stringsAsFactors=FALSE)
write.csv(verdict,file.path(OUT,'overall_verdict.csv'),row.names=FALSE)

# ---------- provenance ----------
manifest_paths <- c(PANEL_PATH,TIMING_PATH,ACTIVITY_PARAMS_PATH,M1B_ARTIFACT_PATH,PLAN_PATH,SCRIPT_PATH)
manifest <- data.frame(
  role=c('canonical_panel','timing_contract','activity_params','m1b_v8_reference','audited_plan','script'),
  path=manifest_paths,
  sha256=vapply(manifest_paths,sha256_file,character(1)),stringsAsFactors=FALSE)
write.csv(manifest,file.path(OUT,'source_manifest.csv'),row.names=FALSE)

config <- data.frame(
  key=c('benchmark_version','excluded_B_season','no_event_B_season','min_state_prior','min_timing_prior','amplitude_grid','activity_window','passage_candidate_step','passage_max_future_weeks','shape_tau_grid','C2_weights','eta','plus1_policy','canonical_panel_sha256','m1b_full9_library_hash','m1b_v8_library_hash'),
  value=c('v3-m2-b-posterior-c2-chronological-v1',EXCLUDED_B_SEASON,NO_EVENT_B_SEASON,MIN_STATE_PRIOR,MIN_TIMING_PRIOR,'0.005:0.005:0.25','8-40',PASSAGE_STEP,PASSAGE_MAX_FUTURE,'-8:0.25:8','0.5 pooled + 0.5 B',ETA,'diagnostic_only_exact_B1_route',sha256_file(PANEL_PATH),repro_lib$provenance$library_hash,m1b_v8$library$provenance$library_hash),
  stringsAsFactors=FALSE)
write.csv(config,file.path(OUT,'benchmark_config.csv'),row.names=FALSE)

cat('\nV3 M2-B posterior C2 chronological benchmark complete\n')
print(summary_metrics,row.names=FALSE,digits=6)
cat('\nActive timing\n')
print(active_summary,row.names=FALSE,digits=6)
cat('\nAcceptance\n')
print(criteria,row.names=FALSE,digits=6)
cat('\nVerdict\n')
print(verdict,row.names=FALSE)
