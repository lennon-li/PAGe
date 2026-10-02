# Package native runtime helpers copied from the frozen v3 runtime contracts.
.PAGE_V3_M1_TRAINING <- c('2012-13','2013-14','2014-15','2016-17','2017-18','2022-23','2023-24','2024-25','2025-26')
.PAGE_V3_M1_PEAK_STEP <- 0.1
.PAGE_V3_M1_PEAK_MAX <- 16
.PAGE_V3_M1_PASSAGE_STEP <- 0.2
.PAGE_V3_M1_PASSAGE_MAX <- 12
.PAGE_V3_M2_MIN_ORIGIN <- 12L
.PAGE_V3_M2_MIN_HISTORY <- 3L
.PAGE_V3_M2_MIN_HISTORY_OBSERVATIONS <- 3L
.PAGE_V3_M2_HORIZONS <- 1:2
.PAGE_V3_M2_NO_EVENT <- '2018-19'
.PAGE_V3_M2_POOLED_WEIGHT <- 0.5
.PAGE_V3_M2_B_WEIGHT <- 0.5
.PAGE_V3_M2_ETA <- 0.5
.PAGE_V3_M2_LOWER_STEP <- 0.2
.PAGE_V3_M2_LOWER_SATURATION <- 0.9
.PAGE_V3_M2_STATE_TRAINING <- c('2012-13','2013-14','2014-15','2016-17','2017-18','2018-19','2022-23','2023-24','2024-25','2025-26')
.PAGE_V3_M2_A_TRAINING <- c('2012-13','2013-14','2014-15','2016-17','2017-18','2018-19','2019-20','2022-23','2023-24','2024-25','2025-26')
.PAGE_V3_M2_B_SHAPE <- c('2012-13','2013-14','2014-15','2016-17','2017-18','2022-23','2023-24','2024-25','2025-26')
.PAGE_V3_M2_A_SHAPE <- c('2012-13','2013-14','2014-15','2016-17','2017-18','2018-19','2019-20','2022-23','2023-24','2024-25','2025-26')
.PAGE_V3_M2_TAU <- seq(-8,8,by=.25)

.m1_b_same_seasons <- function(x,y) identical(as.character(x),as.character(y))

.m1_b_same_number <- function(x,y) is.numeric(x) && length(x)==1L && is.finite(x) && identical(as.numeric(x),as.numeric(y))


.page_v3_compute_m1b_id <- function(artifact) {
  if (!requireNamespace('digest', quietly = TRUE)) stop('Package `digest` is required.')
  core <- list(
    version = as.character(artifact$version),
    status = as.character(artifact$status),
    library_hash = as.character(artifact$library$provenance$library_hash),
    training_seasons = as.character(artifact$training_seasons),
    amplitude_grid = as.numeric(artifact$amplitude_grid),
    activity_marker_window = as.numeric(artifact$activity_marker$window),
    activity_marker_params = artifact$activity_marker$params,
    timing_contract_sha256 = as.character(artifact$timing_contract_sha256),
    eligibility_sha256 = as.character(artifact$season_policy$eligibility_sha256),
    policy_source_sha256 = as.character(artifact$season_policy$source_sha256),
    runtime_contract = list(
      allow_peak_posterior = as.logical(artifact$runtime_contract$allow_peak_posterior),
      peak_candidate_step = as.numeric(artifact$runtime_contract$peak_candidate_step),
      peak_max_future_weeks = as.numeric(artifact$runtime_contract$peak_max_future_weeks),
      allow_continuous_passage_posterior = as.logical(artifact$runtime_contract$allow_continuous_passage_posterior),
      passage_candidate_step = as.numeric(artifact$runtime_contract$passage_candidate_step),
      passage_max_future_weeks = as.numeric(artifact$runtime_contract$passage_max_future_weeks),
      allow_passage_decision = as.logical(artifact$runtime_contract$allow_passage_decision),
      no_activity_state = as.character(artifact$runtime_contract$no_activity_state),
      required_helper = as.character(artifact$runtime_contract$required_helper),
      hard_passage_decision_scope = as.character(artifact$runtime_contract$hard_passage_decision_scope)
    ),
    calibration = list(
      enabled = as.logical(artifact$calibration$enabled),
      reason = as.character(artifact$calibration$reason)
    ),
    joint_A_conditioning = list(
      enabled = as.logical(artifact$joint_A_conditioning$enabled),
      reason = as.character(artifact$joint_A_conditioning$reason)
    ),
    passage = list(
      hard_gate_eligible = as.logical(artifact$passage$hard_gate_eligible),
      historical_threshold_search_closed = as.logical(artifact$passage$historical_threshold_search_closed),
      continuous_posterior_shadow_only = as.logical(artifact$passage$continuous_posterior_shadow_only)
    )
  )
  digest::digest(core, algo = 'sha256')
}


.page_v3_m1b_peak_posterior <- function(artifact,current_data,activity_week,origin_week,candidate_step=NULL,max_future_weeks=NULL) {
  .page_v3_validate_m1b(artifact)
  if (!is.null(candidate_step) && !identical(as.numeric(candidate_step),.PAGE_V3_M1_PEAK_STEP)) stop('M1-B peak candidate_step override violates frozen runtime contract.',call.=FALSE)
  if (!is.null(max_future_weeks) && !identical(as.numeric(max_future_weeks),as.numeric(.PAGE_V3_M1_PEAK_MAX))) stop('M1-B peak max_future_weeks override violates frozen runtime contract.',call.=FALSE)
  m1_v2_peak_posterior(artifact$library,current_data,activation_week=activity_week,origin_week=origin_week,
                       candidate_step=.PAGE_V3_M1_PEAK_STEP,max_future_weeks=.PAGE_V3_M1_PEAK_MAX)
}


.page_v3_m1b_passage_posterior <- function(artifact,current_data,activity_week,origin_week,candidate_step=NULL,max_future_weeks=NULL) {
  .page_v3_validate_m1b(artifact)
  if (!identical(artifact$passage$continuous_posterior_shadow_only,TRUE)) stop('Continuous passage posterior is not allowed by this artifact.',call.=FALSE)
  if (!is.null(candidate_step) && !identical(as.numeric(candidate_step),.PAGE_V3_M1_PASSAGE_STEP)) stop('M1-B passage candidate_step override violates frozen runtime contract.',call.=FALSE)
  if (!is.null(max_future_weeks) && !identical(as.numeric(max_future_weeks),as.numeric(.PAGE_V3_M1_PASSAGE_MAX))) stop('M1-B passage max_future_weeks override violates frozen runtime contract.',call.=FALSE)
  m1_v2_passage_posterior(artifact$library,current_data,activation_week=activity_week,origin_week=origin_week,
                          candidate_step=.PAGE_V3_M1_PASSAGE_STEP,max_future_weeks=.PAGE_V3_M1_PASSAGE_MAX)
}


.page_v3_m1b_inactive_state <- function() {
  list(state='inactive_no_timing_event',positive_timing_gate=FALSE,peak_posterior=NULL,passage_posterior=NULL)
}


.page_v3_same <- function(x,y) identical(as.character(x),as.character(y))

.page_v3_num1 <- function(x,y) is.numeric(x) && length(x)==1L && is.finite(x) && identical(as.numeric(x),as.numeric(y))

.page_v3_season_start <- function(x) as.integer(substr(as.character(x),1,4))

.page_v3_logit <- function(p) qlogis(pmin(pmax(p,1e-6),1-1e-6))

.page_v3_stab <- function(y,N) (y+.5)/(N+1)


.page_v3_projection_id <- function(x) {
  y <- x
  y$runtime_projection_id <- NULL
  digest::digest(y, algo = "sha256")
}


.page_v3_normalize_current <- function(current_B) {
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


.page_v3_state_features <- function(d,origin_week) {
  z <- d[d$weekF<=origin_week,,drop=FALSE]
  i <- which(z$weekF==origin_week)
  if (length(i)!=1L || i<3L) stop('At least three observations through the exact origin are required.',call.=FALSE)
  ps <- .page_v3_stab(z$y,z$N)
  lg <- .page_v3_logit(ps)
  data.frame(
    p_star=ps[i],logit_current=lg[i],
    growth1=lg[i]-lg[i-1L],growth2=(lg[i]-lg[i-2L])/2,
    stringsAsFactors=FALSE)
}


.page_v3_predict_from_coefficients <- function(coefficients, features, horizon) {
  b <- as.numeric(coefficients)
  names(b) <- names(coefficients)
  required <- c("(Intercept)", "horizon_fh2", "growth1", "growth2")
  if (!identical(names(b), required) || any(!is.finite(b))) {
    stop("Frozen state coefficient payload is invalid.", call. = FALSE)
  }
  eta <- as.numeric(features$logit_current) + b[["(Intercept)"]] +
    (if (as.integer(horizon) == 2L) b[["horizon_fh2"]] else 0) +
    b[["growth1"]] * as.numeric(features$growth1) +
    b[["growth2"]] * as.numeric(features$growth2)
  as.numeric(stats::plogis(eta))
}

.page_v3_state_predict <- function(artifact, features, horizon) {
  .page_v3_predict_from_coefficients(artifact$state$coefficients, features, horizon)
}

.page_v3_m2a_forecast <- function(artifact, current_A, origin_week, horizon) {
  .page_v3_validate_m2a(artifact)
  d <- as.data.frame(current_A, stringsAsFactors = FALSE)
  if (!all(c("season", "weekF", "y", "N") %in% names(d))) {
    stop("M2-A runtime requires season/weekF/y/N.", call. = FALSE)
  }
  d <- d[order(d$weekF), , drop = FALSE]
  if (length(unique(d$season)) != 1L || anyDuplicated(d$weekF)) {
    stop("M2-A runtime requires one season with unique weekF rows.", call. = FALSE)
  }
  s <- unique(as.character(d$season))
  if (s %in% artifact$training_seasons) {
    stop("M2-A runtime is prospective-only; current season is in training data.", call. = FALSE)
  }
  f <- .page_v3_state_features(d, as.integer(origin_week))
  pred <- .page_v3_predict_from_coefficients(artifact$baseline_coefficients_A, f, horizon)
  list(
    forecast = pred,
    baseline = pred,
    route = "exact_A1_state",
    model_version = artifact$source_version,
    artifact_id = artifact$source_artifact_id
  )
}


.page_v3_causal_activity <- function(artifact,d,origin_week) {
  s <- unique(d$season)
  if (identical(s,.PAGE_V3_M2_NO_EVENT)) return(list(detected=FALSE,activity_week=NA_real_,reason='policy_no_timing_event'))
  z <- d[d$weekF<=origin_week,,drop=FALSE]
  p <- artifact$activity$params
  p$w_min <- 12L
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


.page_v3_one_lr <- function(z,tau,h) {
  cur <- stats::approx(z$tau,z$p_norm,xout=tau,rule=1)$y
  fut <- stats::approx(z$tau,z$p_norm,xout=tau+h,rule=1)$y
  if (!is.finite(cur) || !is.finite(fut)) return(NA_real_)
  log(pmax(fut,.01)/pmax(cur,.01))
}


.page_v3_c2_lr <- function(artifact,tau,h) {
  g <- artifact$shape$grid
  pool <- numeric(); bvals <- numeric()
  for (s in artifact$shape$A_seasons) {
    z <- g[g$season==s & g$type=='A',,drop=FALSE]
    if (nrow(z)) { q <- .page_v3_one_lr(z,tau,h); if (is.finite(q)) pool <- c(pool,q) }
  }
  for (s in artifact$shape$B_seasons) {
    z <- g[g$season==s & g$type=='B',,drop=FALSE]
    if (nrow(z)) {
      q <- .page_v3_one_lr(z,tau,h)
      if (is.finite(q)) { pool <- c(pool,q); bvals <- c(bvals,q) }
    }
  }
  if (!length(pool) || !length(bvals)) return(NA_real_)
  artifact$shape$pooled_weight*stats::median(pool) + artifact$shape$B_weight*stats::median(bvals)
}


.page_v3_blend <- function(base,current,lr,eta) {
  if (!is.finite(lr)) return(base)
  projected <- pmin(pmax(current*exp(lr),1e-6),1-1e-6)
  plogis((1-eta)*.page_v3_logit(base)+eta*.page_v3_logit(projected))
}


.page_v3_posterior_c2 <- function(artifact,base,current,posterior,origin_week,horizon) {
  w <- as.numeric(posterior$probability)
  T <- as.numeric(posterior$peak_week_decimal)
  if (!length(w) || length(w)!=length(T) || any(!is.finite(w)) || sum(w)<=0) stop('Malformed M1-B posterior.',call.=FALSE)
  w <- w/sum(w)
  lr <- vapply(T,function(tt).page_v3_c2_lr(artifact,origin_week-tt,horizon),numeric(1))
  supported <- is.finite(lr)
  pT <- rep(base,length(T))
  if (any(supported)) pT[supported] <- vapply(lr[supported],function(q).page_v3_blend(base,current,q,artifact$shape$eta),numeric(1))
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


.page_v3_m2b_forecast <- function(artifact,m1_b_artifact,current_B,origin_week,horizon) {
  .page_v3_validate_m2b(artifact)
  .page_v3_validate_m1b(m1_b_artifact)
  if (!identical(m1_b_artifact$version,artifact$m1_b$version) || !identical(m1_b_artifact$library$provenance$library_hash,artifact$m1_b$library_hash)) stop('Runtime M1-B artifact does not match M2-B contract.',call.=FALSE)
  horizon <- as.integer(horizon)
  origin_week <- as.integer(origin_week)
  if (!horizon %in% .PAGE_V3_M2_HORIZONS) stop('M2-B v4 supports horizons 1 and 2 only.',call.=FALSE)
  if (origin_week<.PAGE_V3_M2_MIN_ORIGIN) stop('M2-B v5 origin week is outside the supported weekF domain.',call.=FALSE)

  d <- .page_v3_normalize_current(current_B)
  s <- unique(d$season)
  if (s %in% artifact$state$training_seasons) stop('M2-B v3 runtime is prospective-only; current season is in the training archive.',call.=FALSE)
  if (max(.page_v3_season_start(artifact$state$training_seasons))>=.page_v3_season_start(s)) stop('M2-B v3 runtime season must be later than all training seasons.',call.=FALSE)
  if (!origin_week %in% d$weekF) stop('Requested origin_week is absent from current_B.',call.=FALSE)
  z_support <- d[d$weekF<=origin_week,,drop=FALSE]
  need <- as.integer(origin_week - (.PAGE_V3_M2_MIN_HISTORY_OBSERVATIONS-1L)):as.integer(origin_week)
  have <- tail(as.integer(z_support$weekF),.PAGE_V3_M2_MIN_HISTORY_OBSERVATIONS)
  if (length(have)!=.PAGE_V3_M2_MIN_HISTORY_OBSERVATIONS || !identical(have,need)) {
    stop('M2-B v4 requires three consecutive observations through the exact origin.',call.=FALSE)
  }

  f <- .page_v3_state_features(d,origin_week)
  B1 <- .page_v3_state_predict(artifact,f,horizon)
  base_out <- list(
    season=s,origin_week=origin_week,horizon=horizon,
    forecast=B1,B1_forecast=B1,
    timing_available=FALSE,timing_reason=if(horizon==1L)'plus1_state_only' else 'not_evaluated',
    route=if(horizon==1L)'exact_B1_state' else 'exact_B1_fallback',
    activity_week=NA_real_,prob_peak_passed=NA_real_,posterior_mean_peak=NA_real_,
    supported_mass=0,lower_bound_mass=0,lower_bound_saturated=FALSE,
    m1_b_version=m1_b_artifact$version,m1_b_library_hash=m1_b_artifact$library$provenance$library_hash,
    m2_b_version=artifact$source_version,m2_b_artifact_id=artifact$source_artifact_id)

  if (horizon==1L) return(as.data.frame(base_out,stringsAsFactors=FALSE))

  act <- .page_v3_causal_activity(artifact,d,origin_week)
  if (!isTRUE(act$detected)) {
    base_out$timing_reason <- act$reason
    return(as.data.frame(base_out,stringsAsFactors=FALSE))
  }

  pp <- tryCatch(
    .page_v3_m1b_passage_posterior(m1_b_artifact,d,activity_week=act$activity_week,origin_week=origin_week),
    error=function(e)e)
  if (inherits(pp,'error')) {
    base_out$timing_reason <- paste0('m1_posterior_error:',conditionMessage(pp))
    base_out$activity_week <- act$activity_week
    return(as.data.frame(base_out,stringsAsFactors=FALSE))
  }
  post <- attr(pp,'posterior')
  q <- .page_v3_posterior_c2(artifact,B1,f$p_star,post,origin_week,horizon)
  base_out$forecast <- q$prediction
  base_out$timing_available <- TRUE
  base_out$timing_reason <- 'posterior_C2'
  base_out$route <- 'posterior_C2'
  base_out$activity_week <- act$activity_week
  base_out$prob_peak_passed <- pp$prob_peak_passed[[1]]
  base_out$posterior_mean_peak <- q$posterior_mean_peak
  base_out$supported_mass <- q$supported_mass
  base_out$lower_bound_mass <- q$lower_bound_mass
  base_out$lower_bound_saturated <- q$lower_bound_saturated
  as.data.frame(base_out,stringsAsFactors=FALSE)
}

.PAGE_V3_RELEASE_ID <- "5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b"
.PAGE_V3_SOURCE_SHA <- c(
  m0_a = "9598486e78eedd8e322da77b0d990db60ca07224c3c6ea6ac61cea9cc6fb611d",
  m1_a = "cfeb370305c5b81d66d7eafd7e45ee7e946836ba9f841854f2ec068cf3d43b09",
  m2_a = "1efe590c5222f6061af7bef46b0ea19657ec37e070549898569a62ccd4ac65bb",
  m1_b = "a98629fc313388487e9b3471ae9934cfae8cbc35cdb707ba371f680162691694",
  m2_b = "cae89144c461636662380c19880bf6c5780ce76347edf6b3e30617a614af7226"
)
.PAGE_V3_RUNTIME_SHA <- c(
  m0_a = "9598486e78eedd8e322da77b0d990db60ca07224c3c6ea6ac61cea9cc6fb611d",
  m1_a = "cfeb370305c5b81d66d7eafd7e45ee7e946836ba9f841854f2ec068cf3d43b09",
  m2_a = "718a7b67f0c264ff5cdad5989cfe198052bcf997af06b5acabf83b35c299aa4a",
  m1_b = "a98629fc313388487e9b3471ae9934cfae8cbc35cdb707ba371f680162691694",
  m2_b = "a56333f64dcf30bffcfbfe3c03dc66a5c3507b10d7b404114308a301d977d4e6"
)
.page_v3_cache <- new.env(parent=emptyenv())

.page_v3_hash <- function(path) {
  if (!requireNamespace("digest", quietly=TRUE)) stop("Package 'digest' is required.", call.=FALSE)
  digest::digest(file=path, algo="sha256", serialize=FALSE)
}

.page_v3_model_dir <- function() {
  path <- system.file("models", "v3-week12", package="PAGe")
  if (nzchar(path) && dir.exists(path)) return(path)
  candidates <- c(
    file.path("inst", "models", "v3-week12"),
    file.path("PAGe", "inst", "models", "v3-week12"),
    file.path("..", "..", "inst", "models", "v3-week12")
  )
  hit <- candidates[dir.exists(candidates)]
  if (length(hit)) return(normalizePath(hit[[1L]], winslash = "/", mustWork = TRUE))
  stop("Installed PAGe v3-week12 model bundle is unavailable.", call.=FALSE)
}

.page_v3_validate_m0 <- function(x) {
  p <- x$best_params
  expected <- list(w_min=12, raw_nondec_n=3, raw_drop_se_tol=1)
  if (!inherits(x,"page_m0_loso_result") || !all(vapply(names(expected), function(nm)
    isTRUE(all.equal(as.numeric(p[[nm]]), expected[[nm]], tolerance=0)), logical(1))))
    stop("M0-A frozen parameters do not match the v3 contract.", call.=FALSE)
  invisible(TRUE)
}

.page_v3_validate_m1a <- function(x) {
  if (!inherits(x,"page_m1_v2_stage") || !identical(x$version,"page-m1-v2-stage-v1") ||
      !identical(x$artifact_id,"90f06406dbe3a7d5f190070a5ec7a5c3605d28fe2e7f769609666f92d75d20a5") ||
      !identical(x$library$provenance$library_hash,"66152c96fac040ea94b21c6a45ebf6a7ec20c6960ece0ef3c955244fa3da52f8"))
    stop("M1-A frozen identity mismatch.", call.=FALSE)
  invisible(TRUE)
}

.page_v3_validate_m1b <- function(x) {
  if (!inherits(x,"page_m1_b_v3_peak_artifact") || !identical(x$version,"m1-b-v3-peak-v10") ||
      !identical(x$status,"shadow_research_peak_location_only") ||
      !identical(x$season_policy$excluded_B_season,"2019-20") ||
      !identical(x$season_policy$no_event_season,"2018-19") ||
      !.m1_b_same_seasons(x$training_seasons,.PAGE_V3_M1_TRAINING) ||
      !.m1_b_same_seasons(x$library$training_seasons,.PAGE_V3_M1_TRAINING) ||
      !identical(x$runtime_contract$allow_peak_posterior,TRUE) ||
      !identical(x$runtime_contract$allow_continuous_passage_posterior,TRUE) ||
      !identical(x$runtime_contract$allow_passage_decision,FALSE) ||
      !.m1_b_same_number(x$runtime_contract$peak_candidate_step,.PAGE_V3_M1_PEAK_STEP) ||
      !.m1_b_same_number(x$runtime_contract$peak_max_future_weeks,.PAGE_V3_M1_PEAK_MAX) ||
      !.m1_b_same_number(x$runtime_contract$passage_candidate_step,.PAGE_V3_M1_PASSAGE_STEP) ||
      !.m1_b_same_number(x$runtime_contract$passage_max_future_weeks,.PAGE_V3_M1_PASSAGE_MAX) ||
      !identical(x$artifact_id,.page_v3_compute_m1b_id(x)))
    stop("M1-B frozen runtime contract or canonical artifact ID mismatch.", call.=FALSE)
  invisible(TRUE)
}

.page_v3_validate_m2a <- function(x) {
  expected_coef <- c(
    "(Intercept)" = -0.130280518271989,
    "horizon_fh2" = -0.00572369172317978,
    "growth1" = 0.272361466725941,
    "growth2" = 0.740452823664156
  )
  if (!inherits(x, "page_v3_m2a_runtime") ||
      !identical(x$version, "page-v3-m2a-runtime-v1") ||
      !identical(x$source_version, "m2-v2-c2-governed-v1") ||
      !identical(x$source_artifact_id, "m2v2g_e61427c696b16f7f23c6287bf684c0ff6e5fb9db11e379687d8a57fe9d13dd29") ||
      !identical(x$source_sha256, .PAGE_V3_SOURCE_SHA[["m2_a"]]) ||
      !identical(as.character(x$training_seasons), .PAGE_V3_M2_A_TRAINING) ||
      !isTRUE(all.equal(x$baseline_coefficients_A, expected_coef, tolerance = 1e-14, check.attributes = TRUE)) ||
      !identical(as.integer(x$runtime_contract$min_origin_week), 12L) ||
      !identical(as.integer(x$runtime_contract$horizons), 1:2) ||
      !identical(x$runtime_contract$route, "exact_A1_state") ||
      !identical(x$runtime_projection_id, .page_v3_projection_id(x))) {
    stop("M2-A package runtime projection identity mismatch.", call. = FALSE)
  }
  invisible(TRUE)
}

.page_v3_validate_m2b <- function(x) {
  rc <- x$runtime_contract
  expected_coef <- c(
    "(Intercept)" = -0.0505161664266541,
    "horizon_fh2" = 0.039465131384689,
    "growth1" = 0.0147459866205844,
    "growth2" = 0.71473944194588
  )
  if (!inherits(x,"page_v3_m2b_runtime") || !identical(x$version,"page-v3-m2b-runtime-v1") ||
      !identical(x$source_version,"m2-b-v3-shadow-v5") ||
      !identical(x$source_artifact_id,"7dca48a3c52f6b2a7ee4b92eb1acdf206c8e66f4a332ad5b7d5266311d07cd2f") ||
      !identical(x$source_sha256,.PAGE_V3_SOURCE_SHA[["m2_b"]]) ||
      !identical(x$status,"shadow_only_prospective_research") || !identical(x$production_eligible,FALSE) ||
      !identical(x$season_policy$excluded_B_season,"2019-20") ||
      !identical(x$season_policy$no_event_B_season,"2018-19") ||
      !.page_v3_same(x$state$training_seasons,.PAGE_V3_M2_STATE_TRAINING) ||
      !isTRUE(all.equal(x$state$coefficients, expected_coef, tolerance = 1e-14, check.attributes = TRUE)) ||
      !.page_v3_same(x$shape$A_seasons,.PAGE_V3_M2_A_SHAPE) ||
      !.page_v3_same(x$shape$B_seasons,.PAGE_V3_M2_B_SHAPE) ||
      !identical(names(x$shape$grid),c("season","type","tau","p_norm")) ||
      !identical(as.integer(x$activity$params$w_min),12L) || !identical(as.integer(x$activity$params$w_max),40L) ||
      !identical(as.integer(rc$min_origin_week),12L) || !identical(as.integer(rc$horizons),1:2) ||
      !identical(rc$plus1_route,"exact_B1") ||
      !identical(rc$plus2_route,"posterior_C2_if_timing_else_B1") ||
      !identical(rc$allow_hard_passage,FALSE) || !identical(rc$allow_production,FALSE) ||
      !identical(x$runtime_projection_id,.page_v3_projection_id(x)))
    stop("M2-B package runtime projection identity mismatch.", call.=FALSE)
  invisible(TRUE)
}


.page_v3_validate_bundle <- function(dir) {
  manifest_path <- file.path(dir,"manifest.csv")
  if (!file.exists(manifest_path)) stop("v3 model manifest is missing.",call.=FALSE)
  manifest <- utils::read.csv(manifest_path,stringsAsFactors=FALSE,check.names=FALSE)
  required <- c("release_id","model","file","runtime_sha256","source_sha256","projection",
                "source_version","source_artifact_id","runtime_projection_id","library_hash")
  if (!identical(names(manifest), required) || nrow(manifest)!=5L ||
      !identical(unique(manifest$release_id),.PAGE_V3_RELEASE_ID) ||
      !setequal(manifest$model,names(.PAGE_V3_RUNTIME_SHA))) {
    stop("Malformed or wrong-release v3 model manifest.",call.=FALSE)
  }
  for (nm in names(.PAGE_V3_RUNTIME_SHA)) {
    row <- manifest[manifest$model==nm,,drop=FALSE]
    path <- file.path(dir,row$file[[1]])
    if (!file.exists(path) ||
        !identical(row$runtime_sha256[[1]],.PAGE_V3_RUNTIME_SHA[[nm]]) ||
        !identical(row$source_sha256[[1]],.PAGE_V3_SOURCE_SHA[[nm]]) ||
        !identical(.page_v3_hash(path),.PAGE_V3_RUNTIME_SHA[[nm]])) {
      stop("Frozen v3 runtime model hash mismatch: ",nm,call.=FALSE)
    }
  }
  models <- setNames(lapply(names(.PAGE_V3_RUNTIME_SHA),function(nm)
    readRDS(file.path(dir,manifest$file[match(nm,manifest$model)]))),names(.PAGE_V3_RUNTIME_SHA))
  .page_v3_validate_m0(models$m0_a)
  .page_v3_validate_m1a(models$m1_a)
  .page_v3_validate_m2a(models$m2_a)
  .page_v3_validate_m1b(models$m1_b)
  .page_v3_validate_m2b(models$m2_b)
  attr(models,"manifest_sha256") <- .page_v3_hash(manifest_path)
  attr(models,"manifest") <- manifest
  attr(models,"release_id") <- .PAGE_V3_RELEASE_ID
  models
}


#' Load and validate the frozen PAGe v3 weekF12 model bundle
#' @return Named list containing M0-A, M1-A, M2-A, M1-B and M2-B artifacts,
#'   plus `release_id`, `manifest`, and `manifest_sha256` metadata.
#' @export
page_v3_models <- function() {
  if (exists("models", envir = .page_v3_cache, inherits = FALSE)) {
    return(get("models", envir = .page_v3_cache))
  }
  models <- .page_v3_validate_bundle(.page_v3_model_dir())
  models$release_id <- attr(models, "release_id")
  models$manifest <- attr(models, "manifest")
  models$manifest_sha256 <- attr(models, "manifest_sha256")
  assign("models", models, envir = .page_v3_cache)
  models
}

.page_v3_aggregate_olis_type <- function(x) {
  required <- c("date", "pos", "tests")
  if (!is.data.frame(x) || !all(required %in% names(x))) {
    stop("OLIS pathogen data must contain date, pos, and tests.", call. = FALSE)
  }
  x <- x[, required, drop = FALSE]
  x$date <- as.Date(x$date)
  if (anyNA(x$date)) {
    stop("OLIS pathogen data contain invalid dates.", call. = FALSE)
  }
  if (!is.numeric(x$pos) || !is.numeric(x$tests) || any(!is.finite(x$pos)) ||
      any(!is.finite(x$tests)) || any(x$tests <= 0) || any(x$pos < 0) ||
      any(x$pos > x$tests)) {
    stop("OLIS pathogen data contain invalid positive/test counts.", call. = FALSE)
  }
  daily <- stats::aggregate(cbind(pos, tests) ~ date, data = x, FUN = sum)
  cal <- page_season_calendar(dates = daily$date)
  daily$season <- as.character(cal$season)
  daily$weekF <- as.integer(cal$weekF)
  counts <- stats::aggregate(cbind(pos, tests) ~ season + weekF, data = daily, FUN = sum)
  starts <- stats::aggregate(date ~ season + weekF, data = daily, FUN = min)
  out <- merge(counts, starts, by = c("season", "weekF"), sort = TRUE)
  out$p <- out$pos / out$tests
  out
}

.page_v3_panel <- function(data, season = NULL, strict = TRUE) {
  if (!is.logical(strict) || length(strict) != 1L || is.na(strict)) {
    stop("`strict` must be TRUE or FALSE.", call. = FALSE)
  }
  kind <- "typed_panel"
  source_path <- NA_character_
  source_sha <- NA_character_
  if (is.character(data) && length(data) == 1L && !is.na(data)) {
    source_path <- normalizePath(data, winslash = "/", mustWork = TRUE)
    source_sha <- .page_v3_hash(source_path)
    ext <- tolower(tools::file_ext(source_path))
    if (ext %in% c("rdata", "rda")) {
      kind <- "olis_rdata"
      env <- new.env(parent = emptyenv())
      loaded <- load(source_path, envir = env)
      if (!"r" %in% loaded || !is.list(env$r) || !all(c("fluA", "fluB") %in% names(env$r))) {
        stop("OLIS snapshot must contain `r$fluA` and `r$fluB`.", call. = FALSE)
      }
      a <- .page_v3_aggregate_olis_type(env$r$fluA)
      b <- .page_v3_aggregate_olis_type(env$r$fluB)
      if (is.null(season)) {
        common_seasons <- intersect(unique(a$season), unique(b$season))
        if (length(common_seasons) != 1L) {
          stop("`season` is required when an OLIS snapshot spans multiple seasons.", call. = FALSE)
        }
        season <- common_seasons[[1L]]
      }
      a <- a[a$season == season, , drop = FALSE]
      b <- b[b$season == season, , drop = FALSE]
      m <- merge(a, b, by = c("season", "weekF"), suffixes = c("_A", "_B"), sort = TRUE)
      if (!nrow(m) || nrow(m) != nrow(a) || nrow(m) != nrow(b) || any(m$date_A != m$date_B)) {
        stop("OLIS A/B weekly coverage is misaligned.", call. = FALSE)
      }
      data <- data.frame(
        season = m$season,
        weekF = m$weekF,
        week_start_date = as.character(m$date_A),
        week_end_date = as.character(m$date_A + 6L),
        y_A = m$pos_A, N_A = m$tests_A, p_A = m$p_A,
        y_B = m$pos_B, N_B = m$tests_B, p_B = m$p_B,
        denominator_regime = "orvt_type_specific",
        stringsAsFactors = FALSE
      )
    } else if (ext == "csv") {
      kind <- "orvt_csv"
      if (is.null(season)) stop("`season` is required for an ORVT CSV path.", call. = FALSE)
      a <- getCurrentD(data = source_path, virus = "Influenza A", season = season, include_predecessor = FALSE)
      b <- getCurrentD(data = source_path, virus = "Influenza B", season = season, include_predecessor = FALSE)
      a <- a[a$season == season, , drop = FALSE]
      b <- b[b$season == season, , drop = FALSE]
      if (!nrow(a) || !nrow(b) || !identical(as.integer(a$weekF), as.integer(b$weekF)) ||
          !all(as.Date(a$week_start_date) == as.Date(b$week_start_date))) {
        stop("ORVT A/B weekly coverage is misaligned.", call. = FALSE)
      }
      data <- data.frame(
        season = season,
        weekF = a$weekF,
        week_start_date = as.character(a$week_start_date),
        week_end_date = as.character(a$week_end_date),
        y_A = a$y, N_A = a$N, p_A = a$p,
        y_B = b$y, N_B = b$N, p_B = b$p,
        denominator_regime = "orvt_type_specific",
        stringsAsFactors = FALSE
      )
    } else {
      stop("Path input must be an OLIS .RData/.rda snapshot or ORVT .csv file.", call. = FALSE)
    }
  }

  d <- as.data.frame(data, stringsAsFactors = FALSE)
  required <- c("weekF", "y_A", "N_A", "y_B", "N_B")
  if (!all(required %in% names(d))) {
    stop("Typed panel requires weekF, y_A, N_A, y_B, and N_B.", call. = FALSE)
  }
  if (!"season" %in% names(d)) {
    if (is.null(season)) stop("Typed panel requires `season` or an explicit `season` argument.", call. = FALSE)
    d$season <- as.character(season)
  }
  d$season <- as.character(d$season)
  if (!is.null(season)) d <- d[d$season == as.character(season), , drop = FALSE]
  if (!nrow(d) || length(unique(d$season)) != 1L) {
    stop("Forecast input must resolve to exactly one non-empty season.", call. = FALSE)
  }
  if (is.null(season)) season <- unique(d$season)[[1L]]
  if (anyDuplicated(d$weekF) || any(!is.finite(d$weekF)) ||
      any(!is.finite(d$y_A)) || any(!is.finite(d$N_A)) ||
      any(!is.finite(d$y_B)) || any(!is.finite(d$N_B)) ||
      any(d$N_A <= 0 | d$N_B <= 0 | d$y_A < 0 | d$y_B < 0 | d$y_A > d$N_A | d$y_B > d$N_B)) {
    stop("Invalid or duplicate weekly panel counts/weekF.", call. = FALSE)
  }
  pA <- d$y_A / d$N_A
  pB <- d$y_B / d$N_B
  if (isTRUE(strict) && "p_A" %in% names(d) && any(abs(as.numeric(d$p_A) - pA) > 1e-12, na.rm = TRUE)) {
    stop("Typed panel p_A disagrees with y_A/N_A.", call. = FALSE)
  }
  if (isTRUE(strict) && "p_B" %in% names(d) && any(abs(as.numeric(d$p_B) - pB) > 1e-12, na.rm = TRUE)) {
    stop("Typed panel p_B disagrees with y_B/N_B.", call. = FALSE)
  }
  d$p_A <- pA
  d$p_B <- pB
  d$weekF <- as.integer(d$weekF)
  d <- d[order(d$weekF), , drop = FALSE]
  rownames(d) <- NULL
  list(data = d, kind = kind, path = source_path, sha256 = source_sha, season = season)
}

#' Generate a shadow-only PAGe v3 two-pathogen forecast
#'
#' Runs the canonical weekF12 PAGe v3 model bundle shipped with the package.
#' The runtime is self-contained after package installation: no repository
#' scripts, external model directories, or shell services are required.
#'
#' @param data Canonical typed A/B panel, OLIS `.RData` path containing
#'   `r$fluA`/`r$fluB`, or a local ORVT CSV path.
#' @param season Optional season label. Required for ORVT CSV paths and when an
#'   OLIS snapshot spans more than one season.
#' @param origin_weekF Optional forecast origin. Defaults to the latest week.
#' @param strict When `TRUE`, supplied positivity columns must agree exactly
#'   (within numerical tolerance) with the supplied positive/test counts.
#' @return An object of class `page_v3_forecast`.
#' @export
page_v3_forecast <- function(data, season = NULL, origin_weekF = NULL, strict = TRUE) {
  panel_info <- .page_v3_panel(data, season = season, strict = strict)
  panel <- panel_info$data
  season <- panel_info$season
  if (is.null(origin_weekF)) origin_weekF <- max(panel$weekF)
  if (!is.numeric(origin_weekF) || length(origin_weekF) != 1L || !is.finite(origin_weekF) ||
      origin_weekF != as.integer(origin_weekF)) {
    stop("`origin_weekF` must be one finite integer week.", call. = FALSE)
  }
  origin_weekF <- as.integer(origin_weekF)
  panel <- panel[panel$weekF <= origin_weekF, , drop = FALSE]
  if (!nrow(panel) || !origin_weekF %in% panel$weekF) stop("Exact origin week is absent.", call. = FALSE)

  forecasts <- data.frame(
    season = season,
    origin_weekF = origin_weekF,
    type = c("A", "A", "B", "B"),
    horizon = c(1L, 2L, 1L, 2L),
    forecast = NA_real_, forecast_pct = NA_real_,
    state_baseline = NA_real_, state_baseline_pct = NA_real_,
    route = "not_issued",
    timing_available = FALSE,
    timing_reason = "not_in_validated_window_before_weekF12",
    activity_week = NA_real_, prob_peak_passed = NA_real_, posterior_mean_peak = NA_real_,
    supported_mass = 0, lower_bound_mass = 0, lower_bound_saturated = FALSE,
    model_version = NA_character_, artifact_id = NA_character_, production_eligible = FALSE,
    stringsAsFactors = FALSE
  )
  pre_monitoring <- list(
    A = list(
      m0 = list(eligible = FALSE, eligible_from_weekF = 12L, ignited = FALSE, ignition_weekF = NULL,
                ignition_week = NULL, bracket_lo = NULL, bracket_hi = NULL, fraction_method = NULL),
      m1 = list(available = FALSE, state = "not_eligible_before_weekF12",
                weeks_elapsed_since_activation = NULL, weeks_to_peak = NULL,
                raw_peak_mean_weekF = NULL, peak_mean_weekF = NULL, peak_q05_weekF = NULL, peak_q95_weekF = NULL,
                interval_width_90 = NULL, prob_peak_passed = NULL,
                prob_peak_within_1w = NULL, prob_peak_within_2w = NULL,
                prob_peak_within_3w = NULL, locked_peak_weekF = NULL)
    ),
    B = list(m1 = list(available = FALSE, timing_reason = "not_eligible_before_weekF12",
                       activity_weekF = NULL, peak_mean_weekF = NULL,
                       prob_peak_passed = NULL, supported_mass = 0,
                       lower_bound_mass = 0, lower_bound_saturated = FALSE,
                       route = "not_issued", model_version = NULL))
  )
  pre_monitoring$origin_weekF <- origin_weekF
  pre_monitoring$release_id <- .PAGE_V3_RELEASE_ID
  result <- list(
    release_id = .PAGE_V3_RELEASE_ID,
    package_version = as.character(utils::packageVersion("PAGe")),
    season = season,
    origin_weekF = origin_weekF,
    issued = FALSE,
    status = "shadow_only",
    production_eligible = FALSE,
    monitoring = pre_monitoring,
    forecasts = forecasts,
    provenance = list(
      input_kind = panel_info$kind,
      input_path = panel_info$path,
      input_sha256 = panel_info$sha256
    ),
    panel = panel
  )
  class(result) <- "page_v3_forecast"
  if (origin_weekF < .PAGE_V3_M2_MIN_ORIGIN) return(result)

  need <- as.integer(origin_weekF - 2L):as.integer(origin_weekF)
  have <- tail(as.integer(panel$weekF), 3L)
  if (length(have) != 3L || !identical(have, need)) {
    stop("WeekF12+ forecasts require exact origin-minus-two through origin support.", call. = FALSE)
  }

  models <- page_v3_models()
  a <- data.frame(
    season = season, weekF = panel$weekF,
    y = panel$y_A, N = panel$N_A, p = panel$p_A,
    stringsAsFactors = FALSE
  )
  current_b <- data.frame(
    season = season, weekF = panel$weekF,
    y_B = panel$y_B, N_B = panel$N_B, p_B = panel$p_B,
    stringsAsFactors = FALSE
  )

  m0 <- detectIgnitionBySeason_M0v2_timing(
    a, models$m0_a$best_params,
    verbose = FALSE, iWeek = FALSE, validate_support = FALSE
  )
  det <- m0$by_season[1L, , drop = FALSE]
  ignited <- !isTRUE(det$detection_failed[[1L]])
  m0_result <- list(
    ign_out = m0,
    iWeek_locked = if (ignited) as.numeric(det$iWeek_hat[[1L]]) else NA_real_,
    iWeek_lockedF = if (ignited) as.numeric(det$iWeek_hatF[[1L]]) else NA_real_,
    overridden = FALSE
  )
  m1 <- run_m1_v2_timing(list(m1_v2 = models$m1_a), a, m0_result, verbose = FALSE)

  ar <- lapply(1:2, function(h) {
    .page_v3_m2a_forecast(models$m2_a, a, origin_weekF, h)
  })
  forecasts$forecast[1:2] <- vapply(ar, `[[`, numeric(1L), "forecast")
  forecasts$forecast_pct[1:2] <- 100 * forecasts$forecast[1:2]
  forecasts$state_baseline[1:2] <- vapply(ar, `[[`, numeric(1L), "baseline")
  forecasts$state_baseline_pct[1:2] <- 100 * forecasts$state_baseline[1:2]
  forecasts$route[1:2] <- vapply(ar, `[[`, character(1L), "route")
  forecasts$timing_reason[1:2] <- "policy_A_state_only"
  forecasts$model_version[1:2] <- vapply(ar, `[[`, character(1L), "model_version")
  forecasts$artifact_id[1:2] <- vapply(ar, `[[`, character(1L), "artifact_id")

  br <- do.call(rbind, lapply(1:2, function(h) {
    .page_v3_m2b_forecast(models$m2_b, models$m1_b, current_b, origin_weekF, h)
  }))
  br <- br[order(br$horizon), , drop = FALSE]
  if (nrow(br) != 2L || !identical(as.integer(br$horizon), 1:2) ||
      abs(br$forecast[[1L]] - br$B1_forecast[[1L]]) > 1e-15 ||
      isTRUE(br$timing_available[[1L]]) || !identical(br$route[[1L]], "exact_B1_state")) {
    stop("M2-B +1 route invariant failed.", call. = FALSE)
  }
  if (isTRUE(br$timing_available[[2L]])) {
    if (!identical(br$route[[2L]], "posterior_C2") ||
        !is.finite(br$prob_peak_passed[[2L]]) || !is.finite(br$posterior_mean_peak[[2L]])) {
      stop("M2-B +2 active timing invariant failed.", call. = FALSE)
    }
  } else if (!identical(br$route[[2L]], "exact_B1_fallback") ||
             abs(br$forecast[[2L]] - br$B1_forecast[[2L]]) > 1e-15) {
    stop("M2-B +2 fallback invariant failed.", call. = FALSE)
  }
  forecasts$forecast[3:4] <- as.numeric(br$forecast)
  forecasts$forecast_pct[3:4] <- 100 * forecasts$forecast[3:4]
  forecasts$state_baseline[3:4] <- as.numeric(br$B1_forecast)
  forecasts$state_baseline_pct[3:4] <- 100 * forecasts$state_baseline[3:4]
  forecasts$route[3:4] <- as.character(br$route)
  forecasts$timing_available[3:4] <- as.logical(br$timing_available)
  forecasts$timing_reason[3:4] <- as.character(br$timing_reason)
  forecasts$activity_week[3:4] <- as.numeric(br$activity_week)
  forecasts$prob_peak_passed[3:4] <- as.numeric(br$prob_peak_passed)
  forecasts$posterior_mean_peak[3:4] <- as.numeric(br$posterior_mean_peak)
  forecasts$supported_mass[3:4] <- as.numeric(br$supported_mass)
  forecasts$lower_bound_mass[3:4] <- as.numeric(br$lower_bound_mass)
  forecasts$lower_bound_saturated[3:4] <- as.logical(br$lower_bound_saturated)
  forecasts$model_version[3:4] <- as.character(br$m2_b_version)
  forecasts$artifact_id[3:4] <- as.character(br$m2_b_artifact_id)

  m0_monitor <- list(
    eligible = TRUE,
    eligible_from_weekF = 12L,
    ignited = ignited,
    ignition_weekF = if (ignited) as.numeric(det$iWeek_hatF[[1L]]) else NULL,
    ignition_week = if (ignited) as.integer(det$iWeek_hat[[1L]]) else NULL,
    bracket_lo = if (ignited && "iWeek_bracket_lo" %in% names(det)) as.integer(det$iWeek_bracket_lo[[1L]]) else NULL,
    bracket_hi = if (ignited && "iWeek_bracket_hi" %in% names(det)) as.integer(det$iWeek_bracket_hi[[1L]]) else NULL,
    fraction_method = if (ignited && "iWeek_fraction_method" %in% names(det)) as.character(det$iWeek_fraction_method[[1L]]) else NULL
  )
  m1_monitor <- list(
    available = FALSE, state = "inactive_pre_ignition",
    weeks_elapsed_since_activation = NULL, weeks_to_peak = NULL,
    raw_peak_mean_weekF = NULL, peak_mean_weekF = NULL, peak_q05_weekF = NULL, peak_q95_weekF = NULL,
    interval_width_90 = NULL, prob_peak_passed = NULL,
    prob_peak_within_1w = NULL, prob_peak_within_2w = NULL,
    prob_peak_within_3w = NULL, peak_passed = NULL, locked_peak_weekF = NULL
  )
  if (is.data.frame(m1$timing_df) && nrow(m1$timing_df)) {
    tr <- m1$timing_df[nrow(m1$timing_df), , drop = FALSE]
    state <- as.character(tr$state[[1L]])
    active <- identical(state, "active")
    scalar <- function(nm) {
      if (!nm %in% names(tr)) return(NULL)
      value <- suppressWarnings(as.numeric(tr[[nm]][[1L]]))
      if (length(value) != 1L || !is.finite(value)) NULL else value
    }
    logical_scalar <- function(nm) {
      if (!nm %in% names(tr) || is.na(tr[[nm]][[1L]])) NULL else isTRUE(tr[[nm]][[1L]])
    }
    m1_monitor <- list(
      available = active,
      state = state,
      weeks_elapsed_since_activation = scalar("weeks_elapsed_since_activation"),
      weeks_to_peak = scalar("weeks_to_calibrated_peak"),
      raw_peak_mean_weekF = scalar("raw_peak_mean"),
      peak_mean_weekF = scalar("calibrated_peak_mean"),
      peak_q05_weekF = scalar("calibrated_peak_q05"),
      peak_q95_weekF = scalar("calibrated_peak_q95"),
      interval_width_90 = scalar("interval_width_90"),
      prob_peak_passed = scalar("prob_peak_passed"),
      prob_peak_within_1w = scalar("prob_peak_within_1w"),
      prob_peak_within_2w = scalar("prob_peak_within_2w"),
      prob_peak_within_3w = scalar("prob_peak_within_3w"),
      peak_passed = logical_scalar("peak_passed"),
      locked_peak_weekF = scalar("locked_peak_week")
    )
  }
  b2 <- br[br$horizon == 2L, , drop = FALSE]
  b_monitor <- list(
    available = isTRUE(b2$timing_available[[1L]]),
    timing_reason = as.character(b2$timing_reason[[1L]]),
    activity_weekF = if (is.finite(b2$activity_week[[1L]])) as.numeric(b2$activity_week[[1L]]) else NULL,
    peak_mean_weekF = if (is.finite(b2$posterior_mean_peak[[1L]])) as.numeric(b2$posterior_mean_peak[[1L]]) else NULL,
    prob_peak_passed = if (is.finite(b2$prob_peak_passed[[1L]])) as.numeric(b2$prob_peak_passed[[1L]]) else NULL,
    supported_mass = as.numeric(b2$supported_mass[[1L]]),
    lower_bound_mass = as.numeric(b2$lower_bound_mass[[1L]]),
    lower_bound_saturated = isTRUE(b2$lower_bound_saturated[[1L]]),
    route = as.character(b2$route[[1L]]),
    model_version = as.character(b2$m2_b_version[[1L]])
  )

  result$issued <- TRUE
  result$forecasts <- forecasts
  result$monitoring <- list(origin_weekF = origin_weekF, release_id = .PAGE_V3_RELEASE_ID,
                            A = list(m0 = m0_monitor, m1 = m1_monitor), B = list(m1 = b_monitor))
  result$provenance <- list(
    release_id = .PAGE_V3_RELEASE_ID,
    manifest_sha256 = attr(models, "manifest_sha256"),
    runtime_model_sha256 = .PAGE_V3_RUNTIME_SHA,
    source_model_sha256 = .PAGE_V3_SOURCE_SHA,
    artifact_ids = list(
      m1_a = models$m1_a$artifact_id,
      m2_a = models$m2_a$source_artifact_id,
      m1_b = models$m1_b$artifact_id,
      m2_b = models$m2_b$source_artifact_id
    ),
    runtime_projection_ids = list(
      m2_a = models$m2_a$runtime_projection_id,
      m2_b = models$m2_b$runtime_projection_id
    ),
    input_kind = panel_info$kind,
    input_path = panel_info$path,
    input_sha256 = panel_info$sha256
  )
  result
}

#' @method print page_v3_forecast
#' @export
print.page_v3_forecast <- function(x, ...) {
  cat("<PAGe v3 forecast>\n")
  cat("  season/origin: ", x$season, " / weekF", x$origin_weekF, "\n", sep = "")
  cat("  status: ", x$status, "; ", if (x$issued) "issued" else "not issued", "\n", sep = "")
  if (isTRUE(x$issued)) {
    m0 <- x$monitoring$A$m0
    cat("  A ignition: ", if (isTRUE(m0$ignited)) paste0("yes @ weekF", format(m0$ignition_weekF, digits = 4)) else "no", "\n", sep = "")
    m1 <- x$monitoring$A$m1
    if (isTRUE(m1$available)) {
      cat("  A peak: weekF", format(m1$peak_mean_weekF, digits = 4),
          " (90% ", format(m1$peak_q05_weekF, digits = 4), "-", format(m1$peak_q95_weekF, digits = 4), ")\n", sep = "")
    } else {
      cat("  A peak: unavailable (", m1$state, ")\n", sep = "")
    }
    cat("  B timing: ", if (isTRUE(x$monitoring$B$m1$available)) "available" else x$monitoring$B$m1$timing_reason, "\n", sep = "")
    show <- x$forecasts[, c("type", "horizon", "forecast_pct", "route"), drop = FALSE]
    print(show, row.names = FALSE, digits = 5)
  }
  cat("  production eligible: FALSE\n")
  invisible(x)
}
