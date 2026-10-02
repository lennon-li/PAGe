# Governed runtime helpers for the v3 M2-B shadow-only candidate.
#
# Frozen routing:
#   +1 -> exact B1 state/growth forecast
#   +2 -> posterior-C2 when causal M1-B timing is available, else exact B1
#
# This helper is prospective shadow infrastructure only. It exposes no
# production-promotion or hard-passage route.

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('scripts/v3_m1_b_runtime_helpers_v7.R')

.M2_B_V3_VERSION <- 'm2-b-v3-shadow-v1'
.M2_B_V3_STATUS <- 'shadow_only_prospective_research'
.M2_B_V3_ARTIFACT_PATH <- 'artifacts/m2-b-v3-shadow-v1/m2_b_v3_shadow_artifact.rds'
.M2_B_V3_HELPER_PATH <- 'scripts/v3_m2_b_runtime_helpers_v1.R'
.M2_B_V3_CONTRACT_PATH <- 'docs/v3-m2-b-shadow-runtime-contract-2026-09-26.md'
.M2_B_V3_EXCLUDED_SEASON <- '2019-20'
.M2_B_V3_NO_EVENT_SEASON <- '2018-19'
.M2_B_V3_MIN_ORIGIN <- 13L
.M2_B_V3_HORIZONS <- c(1L,2L)
.M2_B_V3_TAU_GRID <- seq(-8,8,by=.25)
.M2_B_V3_POOLED_WEIGHT <- .5
.M2_B_V3_B_WEIGHT <- .5
.M2_B_V3_ETA <- .5
.M2_B_V3_LOWER_STEP <- .2
.M2_B_V3_LOWER_SATURATION <- .9
.M2_B_V3_STATE_TRAINING <- c(
  '2012-13','2013-14','2014-15','2016-17','2017-18','2018-19',
  '2022-23','2023-24','2024-25','2025-26'
)
.M2_B_V3_B_SHAPE_SEASONS <- c(
  '2012-13','2013-14','2014-15','2016-17','2017-18',
  '2022-23','2023-24','2024-25','2025-26'
)
.M2_B_V3_A_SHAPE_SEASONS <- c(
  '2012-13','2013-14','2014-15','2016-17','2017-18','2018-19','2019-20',
  '2022-23','2023-24','2024-25','2025-26'
)

.m2b_same <- function(x,y) identical(as.character(x),as.character(y))
.m2b_num1 <- function(x,y) is.numeric(x) && length(x)==1L && is.finite(x) && identical(as.numeric(x),as.numeric(y))
.m2b_sha256 <- function(path) {
  if (!requireNamespace('digest',quietly=TRUE)) stop('Package `digest` is required.',call.=FALSE)
  if (!file.exists(path)) stop('Required provenance file unavailable: ',path,call.=FALSE)
  digest::digest(file=path,algo='sha256',serialize=FALSE)
}
.m2b_season_start <- function(x) as.integer(substr(as.character(x),1,4))
.m2b_logit <- function(p) qlogis(pmin(pmax(p,1e-6),1-1e-6))
.m2b_stab <- function(y,N) (y+.5)/(N+1)

validate_m2_b_v3_shadow_artifact <- function(artifact) {
  if (!inherits(artifact,'page_m2_b_v3_shadow_artifact')) stop('Not a page_m2_b_v3_shadow_artifact.',call.=FALSE)
  if (!identical(artifact$version,.M2_B_V3_VERSION)) stop('Wrong M2-B v3 artifact version.',call.=FALSE)
  if (!identical(artifact$status,.M2_B_V3_STATUS)) stop('M2-B v3 artifact is not shadow-only.',call.=FALSE)
  if (!identical(artifact$production_eligible,FALSE)) stop('M2-B v3 artifact must be explicitly non-production.',call.=FALSE)

  sp <- artifact$season_policy
  if (!is.list(sp)) stop('M2-B v3 season policy missing.',call.=FALSE)
  if (!identical(sp$excluded_B_season,.M2_B_V3_EXCLUDED_SEASON)) stop('M2-B v3 2019-20 exclusion mismatch.',call.=FALSE)
  if (!identical(sp$no_event_B_season,.M2_B_V3_NO_EVENT_SEASON)) stop('M2-B v3 2018-19 no-event policy mismatch.',call.=FALSE)
  if (!.m2b_same(sp$state_training_seasons,.M2_B_V3_STATE_TRAINING)) stop('M2-B v3 state training seasons mismatch.',call.=FALSE)
  if (!.m2b_same(sp$B_shape_seasons,.M2_B_V3_B_SHAPE_SEASONS)) stop('M2-B v3 B shape seasons mismatch.',call.=FALSE)
  if (!.m2b_same(sp$A_shape_seasons,.M2_B_V3_A_SHAPE_SEASONS)) stop('M2-B v3 A shape seasons mismatch.',call.=FALSE)
  if (.M2_B_V3_EXCLUDED_SEASON %in% sp$state_training_seasons) stop('Excluded 2019-20 entered B state training.',call.=FALSE)
  if (any(c(.M2_B_V3_EXCLUDED_SEASON,.M2_B_V3_NO_EVENT_SEASON) %in% sp$B_shape_seasons)) stop('Ineligible season entered B shape training.',call.=FALSE)

  st <- artifact$state
  if (!is.list(st) || !inherits(st$model,'glm')) stop('M2-B v3 state GLM missing.',call.=FALSE)
  if (!identical(st$model$family$family,'quasibinomial')) stop('M2-B v3 state family mismatch.',call.=FALSE)
  if (!.m2b_same(st$training_seasons,.M2_B_V3_STATE_TRAINING)) stop('M2-B v3 fitted state seasons mismatch.',call.=FALSE)

  sh <- artifact$shape
  if (!is.list(sh) || !is.data.frame(sh$grid) || !nrow(sh$grid)) stop('M2-B v3 shape grid missing.',call.=FALSE)
  if (!identical(as.numeric(sh$tau_grid),as.numeric(.M2_B_V3_TAU_GRID))) stop('M2-B v3 tau grid mismatch.',call.=FALSE)
  if (!.m2b_num1(sh$pooled_weight,.M2_B_V3_POOLED_WEIGHT) || !.m2b_num1(sh$B_weight,.M2_B_V3_B_WEIGHT)) stop('M2-B v3 C2 weights mismatch.',call.=FALSE)
  if (!.m2b_num1(sh$eta,.M2_B_V3_ETA)) stop('M2-B v3 eta mismatch.',call.=FALSE)
  if (!.m2b_same(sh$A_seasons,.M2_B_V3_A_SHAPE_SEASONS) || !.m2b_same(sh$B_seasons,.M2_B_V3_B_SHAPE_SEASONS)) stop('M2-B v3 shape season metadata mismatch.',call.=FALSE)
  actual_B <- unique(as.character(sh$grid$season[sh$grid$type=='B']))
  actual_A <- unique(as.character(sh$grid$season[sh$grid$type=='A']))
  if (!setequal(actual_B,.M2_B_V3_B_SHAPE_SEASONS) || !setequal(actual_A,.M2_B_V3_A_SHAPE_SEASONS)) stop('M2-B v3 shape grid season content mismatch.',call.=FALSE)

  ac <- artifact$activity
  if (!is.list(ac) || !is.list(ac$params)) stop('M2-B v3 activity parameters missing.',call.=FALSE)
  if (!identical(as.integer(ac$params$w_min),8L) || !identical(as.integer(ac$params$w_max),40L)) stop('M2-B v3 activity window mismatch.',call.=FALSE)

  m1 <- artifact$m1_b
  if (!is.list(m1) || !identical(m1$version,'m1-b-v3-peak-v8')) stop('M2-B v3 M1-B reference version mismatch.',call.=FALSE)
  if (!file.exists(m1$path)) stop('Frozen M1-B artifact is unavailable.',call.=FALSE)
  if (!identical(m1$artifact_sha256,.m2b_sha256(m1$path))) stop('Frozen M1-B artifact hash mismatch.',call.=FALSE)
  m1_art <- readRDS(m1$path)
  validate_m1_b_v3_artifact(m1_art)
  if (!identical(m1$library_hash,m1_art$library$provenance$library_hash)) stop('Frozen M1-B library hash mismatch.',call.=FALSE)

  rc <- artifact$runtime_contract
  if (!is.list(rc)) stop('M2-B v3 runtime contract missing.',call.=FALSE)
  if (!identical(as.integer(rc$min_origin_week),.M2_B_V3_MIN_ORIGIN)) stop('M2-B v3 minimum origin mismatch.',call.=FALSE)
  if (!identical(as.integer(rc$horizons),.M2_B_V3_HORIZONS)) stop('M2-B v3 horizons mismatch.',call.=FALSE)
  if (!identical(rc$plus1_route,'exact_B1')) stop('M2-B v3 +1 route mismatch.',call.=FALSE)
  if (!identical(rc$plus2_route,'posterior_C2_if_timing_else_B1')) stop('M2-B v3 +2 route mismatch.',call.=FALSE)
  if (!identical(rc$allow_hard_passage,FALSE) || !identical(rc$allow_production,FALSE)) stop('M2-B v3 forbidden runtime route enabled.',call.=FALSE)
  if (!.m2b_num1(rc$lower_bound_step,.M2_B_V3_LOWER_STEP) || !.m2b_num1(rc$lower_bound_saturation_threshold,.M2_B_V3_LOWER_SATURATION)) stop('M2-B v3 lower-bound monitoring contract mismatch.',call.=FALSE)
  if (!identical(rc$lower_bound_definition,'sum(probability[peak_week_decimal <= min(peak_week_decimal)+0.2])')) stop('M2-B v3 lower-bound definition mismatch.',call.=FALSE)
  if (!identical(rc$required_helper,.M2_B_V3_HELPER_PATH)) stop('M2-B v3 runtime helper path mismatch.',call.=FALSE)
  if (!identical(rc$required_m1_helper,.M1_B_EXPECTED_HELPER)) stop('M2-B v3 M1 helper path mismatch.',call.=FALSE)

  pv <- artifact$provenance
  if (!is.list(pv)) stop('M2-B v3 provenance missing.',call.=FALSE)
  if (!identical(pv$runtime_helper_sha256,.m2b_sha256(.M2_B_V3_HELPER_PATH))) stop('M2-B v3 runtime helper provenance mismatch.',call.=FALSE)
  if (!identical(pv$runtime_contract_sha256,.m2b_sha256(.M2_B_V3_CONTRACT_PATH))) stop('M2-B v3 runtime contract provenance mismatch.',call.=FALSE)

  core <- list(
    version=artifact$version,
    status=artifact$status,
    state_coefficients=stats::coef(st$model),
    state_training=st$training_seasons,
    m1_library_hash=m1$library_hash,
    shape_grid=sh$grid,
    shape_A=sh$A_seasons,shape_B=sh$B_seasons,
    constants=c(sh$pooled_weight,sh$B_weight,sh$eta,rc$lower_bound_step,rc$lower_bound_saturation_threshold))
  core_hash <- digest::digest(core,algo='sha256')
  if (!identical(artifact$artifact_id,core_hash)) stop('M2-B v3 artifact core ID mismatch.',call.=FALSE)
  invisible(TRUE)
}

load_m2_b_v3_shadow_artifact <- function(path=.M2_B_V3_ARTIFACT_PATH) {
  if (!file.exists(path)) stop('M2-B v3 shadow artifact not found: ',path,call.=FALSE)
  a <- readRDS(path)
  validate_m2_b_v3_shadow_artifact(a)
  a
}

.m2b_normalize_current <- function(current_B) {
  d <- as.data.frame(current_B,stringsAsFactors=FALSE)
  if (!all(c('season','weekF') %in% names(d))) stop('current_B requires season and weekF.',call.=FALSE)
  if (!all(c('y','N','p') %in% names(d))) {
    if (all(c('y_B','N_B','p_B') %in% names(d))) {
      d$y <- d$y_B; d$N <- d$N_B; d$p <- d$p_B
    } else stop('current_B requires y/N/p or y_B/N_B/p_B.',call.=FALSE)
  }
  d <- d[,c('season','weekF','y','N','p')]
  d$season <- as.character(d$season)
  if (length(unique(d$season))!=1L) stop('current_B must contain exactly one season.',call.=FALSE)
  d <- d[order(d$weekF),]
  if (anyDuplicated(d$weekF)) stop('current_B has duplicate weekF rows.',call.=FALSE)
  if (any(!is.finite(d$weekF)) || any(!is.finite(d$y)) || any(!is.finite(d$N)) || any(d$N<=0) || any(d$y<0) || any(d$y>d$N)) stop('current_B has invalid counts/weekF.',call.=FALSE)
  d$p <- d$y/d$N
  d
}

.m2b_state_features <- function(d,origin_week) {
  z <- d[d$weekF<=origin_week,,drop=FALSE]
  i <- which(z$weekF==origin_week)
  if (length(i)!=1L || i<3L) stop('At least three observations through the exact origin are required.',call.=FALSE)
  ps <- .m2b_stab(z$y,z$N)
  lg <- .m2b_logit(ps)
  data.frame(
    p_star=ps[i],logit_current=lg[i],
    growth1=lg[i]-lg[i-1L],growth2=(lg[i]-lg[i-2L])/2,
    stringsAsFactors=FALSE)
}

.m2b_state_predict <- function(artifact,features,horizon) {
  nd <- features
  nd$horizon_f <- factor(paste0('h',horizon),levels=c('h1','h2'))
  nd$offset_logit <- nd$logit_current
  as.numeric(stats::predict(artifact$state$model,newdata=nd,type='response'))
}

.m2b_causal_activity <- function(artifact,d,origin_week) {
  s <- unique(d$season)
  if (identical(s,.M2_B_V3_NO_EVENT_SEASON)) return(list(detected=FALSE,activity_week=NA_real_,reason='policy_no_timing_event'))
  z <- d[d$weekF<=origin_week,,drop=FALSE]
  p <- artifact$activity$params
  p$w_min <- 8L
  p$w_max <- min(40L,as.integer(origin_week),as.integer(max(z$weekF)))
  if (p$w_max<p$w_min) return(list(detected=FALSE,activity_week=NA_real_,reason='pre_window'))
  det <- tryCatch(detectIgnitionBySeason_M0v2_timing(z,params=p,verbose=FALSE,iWeek=FALSE,keep_signals=TRUE),error=function(e)e)
  if (inherits(det,'error')) return(list(detected=FALSE,activity_week=NA_real_,reason=paste0('detector_error:',conditionMessage(det))))
  b <- det$by_season
  if (!nrow(b) || isTRUE(b$detection_failed[1]) || !is.finite(b$iWeek_hatF[1])) return(list(detected=FALSE,activity_week=NA_real_,reason='not_detected'))
  aw <- as.numeric(b$iWeek_hatF[1])
  if (aw>origin_week+1e-12) stop('Causal M2-B activity week exceeds origin.',call.=FALSE)
  list(detected=TRUE,activity_week=aw,reason='causal_prefix_detection')
}

.m2b_one_lr <- function(z,tau,h) {
  cur <- approx(z$tau,z$p_norm,xout=tau,rule=1)$y
  fut <- approx(z$tau,z$p_norm,xout=tau+h,rule=1)$y
  if (!is.finite(cur) || !is.finite(fut)) return(NA_real_)
  log(pmax(fut,.01)/pmax(cur,.01))
}

.m2b_c2_lr <- function(artifact,tau,h) {
  g <- artifact$shape$grid
  pool <- numeric(); bvals <- numeric()
  for (s in artifact$shape$A_seasons) {
    z <- g[g$season==s & g$type=='A',,drop=FALSE]
    if (nrow(z)) { q <- .m2b_one_lr(z,tau,h); if (is.finite(q)) pool <- c(pool,q) }
  }
  for (s in artifact$shape$B_seasons) {
    z <- g[g$season==s & g$type=='B',,drop=FALSE]
    if (nrow(z)) {
      q <- .m2b_one_lr(z,tau,h)
      if (is.finite(q)) { pool <- c(pool,q); bvals <- c(bvals,q) }
    }
  }
  if (!length(pool) || !length(bvals)) return(NA_real_)
  artifact$shape$pooled_weight*stats::median(pool) + artifact$shape$B_weight*stats::median(bvals)
}

.m2b_blend <- function(base,current,lr,eta) {
  if (!is.finite(lr)) return(base)
  projected <- pmin(pmax(current*exp(lr),1e-6),1-1e-6)
  plogis((1-eta)*.m2b_logit(base)+eta*.m2b_logit(projected))
}

.m2b_posterior_c2 <- function(artifact,base,current,posterior,origin_week,horizon) {
  w <- as.numeric(posterior$probability)
  T <- as.numeric(posterior$peak_week_decimal)
  if (!length(w) || length(w)!=length(T) || any(!is.finite(w)) || sum(w)<=0) stop('Malformed M1-B posterior.',call.=FALSE)
  w <- w/sum(w)
  lr <- vapply(T,function(tt).m2b_c2_lr(artifact,origin_week-tt,horizon),numeric(1))
  supported <- is.finite(lr)
  pT <- rep(base,length(T))
  if (any(supported)) pT[supported] <- vapply(lr[supported],function(q).m2b_blend(base,current,q,artifact$shape$eta),numeric(1))
  pred <- sum(w*pT)
  lower <- min(T)
  lower_mass <- sum(w[T<=lower+artifact$runtime_contract$lower_bound_step+1e-12])
  list(
    prediction=pred,
    supported_mass=sum(w[supported]),
    lower_bound=lower,
    lower_bound_mass=lower_mass,
    lower_bound_saturated=lower_mass>=artifact$runtime_contract$lower_bound_saturation_threshold,
    posterior_mean_peak=sum(w*T))
}

m2_b_v3_shadow_forecast <- function(artifact,m1_b_artifact,current_B,origin_week,horizon) {
  validate_m2_b_v3_shadow_artifact(artifact)
  validate_m1_b_v3_artifact(m1_b_artifact)
  if (!identical(m1_b_artifact$version,artifact$m1_b$version) || !identical(m1_b_artifact$library$provenance$library_hash,artifact$m1_b$library_hash)) stop('Runtime M1-B artifact does not match M2-B contract.',call.=FALSE)
  horizon <- as.integer(horizon)
  origin_week <- as.integer(origin_week)
  if (!horizon %in% .M2_B_V3_HORIZONS) stop('M2-B v3 supports horizons 1 and 2 only.',call.=FALSE)
  if (origin_week<.M2_B_V3_MIN_ORIGIN) stop('M2-B v3 shadow is not validated before weekF 13.',call.=FALSE)

  d <- .m2b_normalize_current(current_B)
  s <- unique(d$season)
  if (s %in% artifact$state$training_seasons) stop('M2-B v3 runtime is prospective-only; current season is in the training archive.',call.=FALSE)
  if (max(.m2b_season_start(artifact$state$training_seasons))>=.m2b_season_start(s)) stop('M2-B v3 runtime season must be later than all training seasons.',call.=FALSE)
  if (!origin_week %in% d$weekF) stop('Requested origin_week is absent from current_B.',call.=FALSE)

  f <- .m2b_state_features(d,origin_week)
  B1 <- .m2b_state_predict(artifact,f,horizon)
  base_out <- list(
    season=s,origin_week=origin_week,horizon=horizon,
    forecast=B1,B1_forecast=B1,
    timing_available=FALSE,timing_reason=if(horizon==1L)'plus1_state_only' else 'not_evaluated',
    activity_week=NA_real_,prob_peak_passed=NA_real_,posterior_mean_peak=NA_real_,
    supported_mass=0,lower_bound_mass=0,lower_bound_saturated=FALSE,
    m1_b_version=m1_b_artifact$version,m1_b_library_hash=m1_b_artifact$library$provenance$library_hash,
    m2_b_version=artifact$version,m2_b_artifact_id=artifact$artifact_id)

  if (horizon==1L) return(as.data.frame(base_out,stringsAsFactors=FALSE))

  act <- .m2b_causal_activity(artifact,d,origin_week)
  if (!isTRUE(act$detected)) {
    base_out$timing_reason <- act$reason
    return(as.data.frame(base_out,stringsAsFactors=FALSE))
  }

  pp <- tryCatch(
    m1_b_v3_passage_posterior(m1_b_artifact,d,activity_week=act$activity_week,origin_week=origin_week),
    error=function(e)e)
  if (inherits(pp,'error')) {
    base_out$timing_reason <- paste0('m1_posterior_error:',conditionMessage(pp))
    base_out$activity_week <- act$activity_week
    return(as.data.frame(base_out,stringsAsFactors=FALSE))
  }
  post <- attr(pp,'posterior')
  q <- .m2b_posterior_c2(artifact,B1,f$p_star,post,origin_week,horizon)
  base_out$forecast <- q$prediction
  base_out$timing_available <- TRUE
  base_out$timing_reason <- 'posterior_C2'
  base_out$activity_week <- act$activity_week
  base_out$prob_peak_passed <- pp$prob_peak_passed[[1]]
  base_out$posterior_mean_peak <- q$posterior_mean_peak
  base_out$supported_mass <- q$supported_mass
  base_out$lower_bound_mass <- q$lower_bound_mass
  base_out$lower_bound_saturated <- q$lower_bound_saturated
  as.data.frame(base_out,stringsAsFactors=FALSE)
}

m2_b_v3_production_forecast <- function(...) {
  stop('M2-B v3 is shadow-only and has no production forecast route.',call.=FALSE)
}
