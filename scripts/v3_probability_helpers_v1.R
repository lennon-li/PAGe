# Experimental probability helpers for the v3 weekly API.
#
# IMPORTANT: This file intentionally lives outside PAGe/R. Canonical v3 binds
# the complete PAGe/R/*.R source closure into its release identity. Probability
# diagnostics must not mutate that frozen runtime just to expose read-only API
# projections.

.page_prob_new <- function(atoms, outcome, scale, support, weights = NULL,
                           status = c('experimental', 'unavailable'),
                           calibration = NULL, provenance = NULL) {
  status <- match.arg(status)
  if (!is.numeric(atoms) || !is.null(dim(atoms)) || any(!is.finite(atoms)))
    stop('Probability atoms must be a finite numeric vector.', call.=FALSE)
  if (!is.numeric(support) || length(support)!=2L || any(!is.finite(support)) || support[[1L]]>=support[[2L]])
    stop('Probability support must contain two increasing finite numbers.', call.=FALSE)
  if (identical(status,'unavailable')) {
    if (length(atoms)) stop('Unavailable probability distribution cannot contain atoms.', call.=FALSE)
    weights <- numeric()
  } else {
    if (!length(atoms)) stop('Experimental probability distribution requires atoms.', call.=FALSE)
    if (any(atoms < support[[1L]] | atoms > support[[2L]])) stop('Probability atoms lie outside support.', call.=FALSE)
    if (is.null(weights)) weights <- rep(1/length(atoms), length(atoms))
    if (!is.numeric(weights) || length(weights)!=length(atoms) || any(!is.finite(weights)) || any(weights<0) || sum(weights)<=0)
      stop('Probability weights are invalid.', call.=FALSE)
    weights <- as.numeric(weights)/sum(weights)
  }
  list(atoms=as.numeric(atoms), weights=as.numeric(weights), outcome=as.character(outcome),
       scale=as.character(scale), support=as.numeric(support), status=status,
       calibration=calibration, provenance=provenance)
}

.page_prob_above <- function(d, threshold, inclusive=FALSE) {
  if (!is.list(d) || identical(d$status,'unavailable')) stop('Probability distribution is unavailable.',call.=FALSE)
  if (!is.numeric(threshold) || length(threshold)!=1L || !is.finite(threshold)) stop('Threshold must be finite.',call.=FALSE)
  hit <- if (isTRUE(inclusive)) d$atoms >= threshold else d$atoms > threshold
  as.numeric(sum(d$weights[hit]))
}

.page_prob_below <- function(d, threshold, inclusive=FALSE) {
  if (!is.list(d) || identical(d$status,'unavailable')) stop('Probability distribution is unavailable.',call.=FALSE)
  if (!is.numeric(threshold) || length(threshold)!=1L || !is.finite(threshold)) stop('Threshold must be finite.',call.=FALSE)
  hit <- if (isTRUE(inclusive)) d$atoms <= threshold else d$atoms < threshold
  as.numeric(sum(d$weights[hit]))
}

.page_prob_calibrator <- local({
  cache <- NULL
  function(path='governance/v3_probability_calibrator_v1.rds') {
    if (!is.null(cache)) return(cache)
    if (!file.exists(path)) stop('Frozen v3 probability calibrator is unavailable.',call.=FALSE)
    x <- readRDS(path)
    stored <- x$calibrator_id
    x$calibrator_id <- NULL
    if (!is.character(stored) || length(stored)!=1L ||
        !identical(stored,digest::digest(x,algo='sha256')))
      stop('Frozen v3 probability calibrator identity check failed.',call.=FALSE)
    x$calibrator_id <- stored
    if (!exists('.PAGE_V3_RELEASE_ID',inherits=TRUE) || !identical(x$release_id,.PAGE_V3_RELEASE_ID) || !identical(x$status,'experimental'))
      stop('Frozen v3 probability calibrator release/status mismatch.',call.=FALSE)
    cache <<- x
    cache
  }
})

.page_prob_pool <- function(calibrator,type,horizon) {
  key <- paste0(type,'_h',as.integer(horizon))
  pool <- calibrator$pools[[key]]
  if (is.null(pool) || !is.data.frame(pool) || !all(c('season','residual','weight') %in% names(pool)))
    stop('Probability calibrator pool missing: ',key,call.=FALSE)
  if (any(!is.finite(pool$residual)) || any(!is.finite(pool$weight)) || any(pool$weight<0) || abs(sum(pool$weight)-1)>1e-10)
    stop('Probability calibrator pool malformed: ',key,call.=FALSE)
  pool
}

.page_prob_predictive_distribution <- function(forecast,type=c('A','B'),horizon=1L) {
  if (!inherits(forecast,'page_v3_forecast')) stop('Expected page_v3_forecast.',call.=FALSE)
  type <- match.arg(type); horizon <- as.integer(horizon)
  if (!horizon %in% c(1L,2L)) stop('Horizon must be 1 or 2.',call.=FALSE)
  if (!isTRUE(forecast$issued)) return(.page_prob_new(numeric(),'positivity_jeffreys_smoothed','proportion',c(0,1),status='unavailable',provenance=list(reason='forecast_not_issued')))
  row <- forecast$forecasts[forecast$forecasts$type==type & forecast$forecasts$horizon==horizon,,drop=FALSE]
  if (nrow(row)!=1L || !is.finite(row$forecast[[1L]])) stop('Canonical v3 point forecast unavailable.',call.=FALSE)
  cal <- .page_prob_calibrator(); pool <- .page_prob_pool(cal,type,horizon)
  if (as.character(forecast$season) %in% unique(pool$season)) stop('Forecast season overlaps probability calibration seasons.',call.=FALSE)
  if (.page_v3_season_start(forecast$season) <= max(.page_v3_season_start(unique(pool$season))))
    stop('Probability calibration seasons are not strictly historical to forecast season.',call.=FALSE)
  p <- as.numeric(row$forecast[[1L]])
  if (p<=cal$eps || p>=1-cal$eps) stop('Point forecast outside probability calibrator logit domain.',call.=FALSE)
  atoms <- stats::plogis(stats::qlogis(p)+pool$residual)
  .page_prob_new(atoms,'positivity_jeffreys_smoothed','proportion',c(0,1),weights=pool$weight,
    calibration=list(status='experimental',method=cal$method,n_seasons=length(unique(pool$season)),n_origins=nrow(pool),calibrator_id=cal$calibrator_id,target_semantics='Jeffreys-smoothed observed positivity (y+0.5)/(N+1)'),
    provenance=list(release_id=forecast$release_id,type=type,horizon=horizon,route=as.character(row$route[[1L]]),calibrator_id=cal$calibrator_id,point_forecast=p))
}

.page_prob_peak_posterior <- function(forecast,type) {
  models <- page_v3_models(); origin <- as.integer(forecast$origin_weekF)
  panel <- forecast$panel[forecast$panel$weekF<=origin,,drop=FALSE]
  if (identical(type,'A')) {
    m0 <- forecast$monitoring$A$m0
    if (!isTRUE(m0$ignited) || is.null(m0$ignition_weekF)) return(NULL)
    d <- data.frame(season=forecast$season,weekF=panel$weekF,y=panel$y_A,N=panel$N_A,p=panel$p_A)
    pp <- m1_v2_passage_posterior(models$m1_a$library,d,activation_week=as.numeric(m0$ignition_weekF),origin_week=origin,candidate_step=0.1,max_future_weeks=12)
    return(list(summary=pp,posterior=attr(pp,'posterior'),source='M1_A_passage_posterior'))
  }
  d <- data.frame(season=forecast$season,weekF=panel$weekF,y=panel$y_B,N=panel$N_B,p=panel$p_B)
  act <- .page_v3_causal_activity(models$m2_b,.page_v3_normalize_current(d),origin)
  if (!isTRUE(act$detected)) return(NULL)
  pp <- .page_v3_m1b_passage_posterior(models$m1_b,d,activity_week=act$activity_week,origin_week=origin)
  list(summary=pp,posterior=attr(pp,'posterior'),source='M1_B_passage_posterior')
}

.page_prob_peak_distribution <- function(forecast,type=c('A','B')) {
  if (!inherits(forecast,'page_v3_forecast')) stop('Expected page_v3_forecast.',call.=FALSE)
  type <- match.arg(type)
  if (!isTRUE(forecast$issued)) return(.page_prob_new(numeric(),'season_peak_week','weekF',c(0,60),status='unavailable',provenance=list(reason='forecast_not_issued',type=type)))
  x <- .page_prob_peak_posterior(forecast,type)
  if (is.null(x)) return(.page_prob_new(numeric(),'season_peak_week','weekF',c(0,60),status='unavailable',provenance=list(reason='timing_inactive',type=type)))
  post <- x$posterior; T <- as.numeric(post$peak_week_decimal); w <- as.numeric(post$probability)
  if (!length(T) || length(T)!=length(w) || any(!is.finite(T)) || any(!is.finite(w)) || any(w<0) || sum(w)<=0)
    stop('Peak posterior atoms are malformed.',call.=FALSE)
  .page_prob_new(T,'season_peak_week','weekF',c(0,max(60,ceiling(max(T))+1)),weights=w,
    calibration=list(status='experimental',method=x$source,uncertainty='model-conditional passage posterior; not prospectively calibrated'),
    provenance=list(release_id=forecast$release_id,type=type,asof_boundary=as.numeric(x$summary$asof_boundary[[1L]])))
}

.page_prob_snapshot_distribution <- function(d,type,horizon=NULL) {
  list(type=type,horizon=if(is.null(horizon)) NULL else as.integer(horizon),status=d$status,
       outcome=d$outcome,scale=d$scale,support=as.list(as.numeric(d$support)),
       atoms=as.list(as.numeric(d$atoms)),weights=as.list(as.numeric(d$weights)),
       calibration=d$calibration,provenance=d$provenance)
}

.page_v3_probability_snapshot <- function(forecast) {
  if (!inherits(forecast,'page_v3_forecast')) stop('Expected page_v3_forecast.',call.=FALSE)
  positivity <- list()
  for (type in c('A','B')) for (h in 1:2) {
    d <- .page_prob_predictive_distribution(forecast,type,h)
    positivity[[paste0(type,'_h',h)]] <- .page_prob_snapshot_distribution(d,type,h)
  }
  peak <- list()
  for (type in c('A','B')) {
    d <- .page_prob_peak_distribution(forecast,type)
    peak[[type]] <- .page_prob_snapshot_distribution(d,type)
  }
  list(schema_version='page-v3-probability-snapshot-v1',status='experimental',
       season=as.character(forecast$season),origin_weekF=as.integer(forecast$origin_weekF),
       release_id=as.character(forecast$release_id),issued=isTRUE(forecast$issued),
       semantics=list(positivity='experimental season-balanced OOS logit-residual predictive atoms for Jeffreys-smoothed observed positivity',peak='experimental current M1 passage-posterior peak-week atoms'),
       positivity=positivity,peak=peak)
}
