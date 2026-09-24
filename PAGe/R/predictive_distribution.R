#' Fit an out-of-sample residual calibrator for forecast distributions
#'
#' Fits a low-complexity empirical residual adapter from out-of-sample weekly
#' forecasts. Count outcomes use the Jeffreys empirical-logit correction
#' \code{(y + 0.5) / (N + 1)} before residuals are sampled on the logit scale.
#' Residuals are grouped by horizon.
#' Within each forecast draw, seasons are sampled uniformly before an origin is
#' sampled from that season, so seasons with more scored weeks do not dominate.
#' This function does not establish that calibration seasons precede a target
#' season; the caller must enforce chronological separation.
#'
#' This is an experimental distribution adapter, not evidence of calibration.
#' Use predictions generated strictly out of sample, and evaluate the resulting
#' distributions on untouched seasons before describing their probabilities as
#' calibrated.
#'
#' @param predictions Data frame of out-of-sample forecasts and observed weekly
#'   proportions. It must contain a season identifier, origin week, horizon,
#'   point forecast, positive count, and total count. The observed proportion
#'   column is optional and, when present, is checked against the counts.
#' @param forecast_col Name of the point-forecast column.
#' @param observed_col Optional observed-proportion column checked against the
#'   counts when present.
#' @param horizon_col Name of the forecast-horizon column. Values may be numeric
#'   (for example, \code{1}) or labels such as \code{"h1"}.
#' @param season_col Name of the season identifier column.
#' @param positive_col Name of the positive-count column.
#' @param total_col Name of the denominator column.
#' @param origin_col Name of the forecast-origin week column. It is required to
#'   reject duplicate origin/horizon rows.
#' @param out_of_sample Must be explicitly set to \code{TRUE} to attest that
#'   every supplied forecast was generated without using its target outcome.
#' @param predictor_id Stable identifier for the exact point-forecast protocol
#'   that generated these rows. It must match the identifier on the forecast
#'   passed to \code{predictive_distribution()}.
#' @param min_seasons Minimum distinct out-of-sample seasons required for each
#'   horizon.
#' @param eps Boundary threshold: training forecasts within \code{eps} of 0 or
#'   1 are excluded, and target forecasts must lie strictly between
#'   \code{eps} and \code{1 - eps} before the logit transform.
#'
#' @return An object of class \code{page_forecast_calibrator} containing
#'   horizon-specific logit residuals and season identifiers. Its status is
#'   always \code{"experimental"} until evaluated and validated externally.
#' @export
fit_forecast_calibrator <- function(predictions,
                                    predictor_id,
                                    forecast_col = "p_hat",
                                    observed_col = "p_obs",
                                    horizon_col = "lead",
                                    season_col = "season",
                                    origin_col = "eval_week",
                                    positive_col = "y_lead",
                                    total_col = "N_lead",
                                    out_of_sample = FALSE,
                                    min_seasons = 3L,
                                    eps = 1e-6) {
  if (!isTRUE(out_of_sample)) {
    stop(
      "Set `out_of_sample = TRUE` only when every row is a genuine ",
      "out-of-sample forecast.",
      call. = FALSE
    )
  }
  if (!is.character(predictor_id) || length(predictor_id) != 1L ||
    is.na(predictor_id) || !nzchar(predictor_id)) {
    stop("`predictor_id` must be one non-empty protocol identifier.", call. = FALSE)
  }
  if (!is.numeric(eps) || length(eps) != 1L || !is.finite(eps) || eps <= 0 || eps >= 0.5) {
    stop("`eps` must be one finite number strictly between 0 and 0.5.", call. = FALSE)
  }
  if (!is.numeric(min_seasons) || length(min_seasons) != 1L ||
    !is.finite(min_seasons) || min_seasons < 2 || min_seasons != as.integer(min_seasons)) {
    stop("`min_seasons` must be one integer of at least 2.", call. = FALSE)
  }
  predictions <- as.data.frame(predictions)
  needed <- c(forecast_col, horizon_col, season_col, origin_col, positive_col, total_col)
  missing <- setdiff(needed, names(predictions))
  if (length(missing)) {
    stop("`predictions` is missing: ", paste(missing, collapse = ", "), ".", call. = FALSE)
  }
  positive <- as.numeric(predictions[[positive_col]])
  total <- as.numeric(predictions[[total_col]])
  observed <- positive / total
  observed[!is.finite(total) | total <= 0] <- NA_real_
  if (observed_col %in% names(predictions)) {
    supplied_observed <- as.numeric(predictions[[observed_col]])
    comparable <- is.finite(observed) & is.finite(supplied_observed)
    inconsistent <- comparable & abs(observed - supplied_observed) > 1e-8
    if (any(inconsistent)) {
      stop("`observed_col` is inconsistent with positive/total counts.", call. = FALSE)
    }
  }
  # The count-aware empirical logit avoids treating a zero or all-positive
  # week as an infinite logit that is then controlled by `eps` alone.
  calibration_outcome <- (positive + 0.5) / (total + 1)
  calibration_outcome[!is.finite(total) | total <= 0] <- NA_real_
  forecast <- as.numeric(predictions[[forecast_col]])
  season <- .page_season_key(predictions[[season_col]])
  horizon <- .page_horizon_key(predictions[[horizon_col]])
  origin_week <- suppressWarnings(as.numeric(predictions[[origin_col]]))
  integer_origin <- is.finite(origin_week) & origin_week == floor(origin_week)
  valid <- is.finite(forecast) & is.finite(calibration_outcome) &
    forecast > eps & forecast < 1 - eps & calibration_outcome > 0 & calibration_outcome < 1 &
    is.finite(positive) & positive >= 0 & positive <= total &
    is.finite(total) & total > 0 & integer_origin & !is.na(season) & !is.na(horizon)
  if (!any(valid)) stop("No valid out-of-sample forecast rows were supplied.", call. = FALSE)
  n_dropped <- sum(!valid)
  drop_reason <- rep(NA_character_, length(valid))
  assign_reason <- function(condition, label) {
    idx <- which(!valid & is.na(drop_reason) & condition)
    drop_reason[idx] <<- label
  }
  assign_reason(!is.finite(forecast), "nonfinite_forecast")
  assign_reason(is.finite(forecast) & (forecast < 0 | forecast > 1), "forecast_outside_0_1")
  assign_reason(
    is.finite(forecast) & forecast >= 0 & forecast <= 1 &
      (forecast <= eps | forecast >= 1 - eps),
    "forecast_at_or_beyond_logit_clip"
  )
  assign_reason(!is.finite(total) | total <= 0, "nonpositive_or_nonfinite_total")
  assign_reason(!is.finite(calibration_outcome), "outcome_unavailable_or_nonfinite")
  assign_reason(!is.finite(positive) | positive < 0 | positive > total, "invalid_positive_count")
  assign_reason(!integer_origin, "invalid_origin_week")
  assign_reason(is.na(season) | !nzchar(season), "missing_season")
  assign_reason(is.na(horizon), "invalid_horizon")
  dropped_reasons <- as.list(table(factor(drop_reason[!valid], levels = unique(drop_reason[!valid]))))
  dropped_counts <- integer()
  if (n_dropped > 0L) {
    dropped_counts <- vapply(dropped_reasons, as.integer, integer(1))
  }
  target_col <- intersect(c("target_weekF", "target_week"), names(predictions))
  if (length(target_col)) {
    target_week <- suppressWarnings(as.numeric(predictions[[target_col[[1L]]]]))
    mismatch <- valid & (!is.finite(target_week) | target_week != origin_week + as.numeric(horizon))
    if (any(mismatch)) stop("Forecast origin, horizon, and target weeks are inconsistent.", call. = FALSE)
  } else {
    target_week <- rep(NA_real_, nrow(predictions))
  }
  key <- paste(season, horizon, origin_week, sep = "\r")
  if (anyDuplicated(key[valid])) {
    stop("Duplicate season/origin/horizon forecast rows were supplied.", call. = FALSE)
  }

  residuals <- data.frame(
    season = season[valid],
    horizon = horizon[valid],
    origin_week = origin_week[valid],
    target_week = target_week[valid],
    point_forecast = forecast[valid],
    calibrated_outcome = calibration_outcome[valid],
    residual = stats::qlogis(calibration_outcome[valid]) -
      stats::qlogis(pmin(1 - eps, pmax(eps, forecast[valid]))),
    stringsAsFactors = FALSE
  )
  if (any(!is.finite(residuals$residual))) {
    stop("Residual construction produced a non-finite value.", call. = FALSE)
  }
  residuals$training_positive <- positive[valid]
  residuals$training_total <- total[valid]
  n_seasons <- length(unique(residuals$season))
  seasons_per_horizon <- vapply(
    split(residuals$season, residuals$horizon),
    function(x) length(unique(x)), integer(1)
  )
  insufficient <- names(seasons_per_horizon)[seasons_per_horizon < min_seasons]
  if (length(insufficient)) {
    stop(
      "At least ", as.integer(min_seasons), " seasons are required for each horizon; ",
      "insufficient data for horizon(s): ", paste(insufficient, collapse = ", "), ".",
      call. = FALSE
    )
  }
  calibrator <- structure(
    list(
      residuals = residuals,
      eps = eps,
      n_seasons = n_seasons,
      training_seasons = sort(unique(residuals$season)),
      n_origins = nrow(residuals),
      seasons_per_horizon = seasons_per_horizon,
      n_dropped = n_dropped,
      dropped_reasons = dropped_counts,
      boundary_correction = "Jeffreys_empirical_logit",
      predictor_id = predictor_id,
      package_version = as.character(utils::packageVersion("PAGe")),
      horizons = sort(unique(residuals$horizon)),
      status = "experimental",
      method = "season_balanced_logit_residual_bootstrap"
    ),
    class = "page_forecast_calibrator"
  )
  calibrator$calibrator_id <- digest::digest(calibrator, algo = "sha256")
  if (n_dropped > 0L) {
    message(
      n_dropped, " invalid out-of-sample row(s) excluded from the residual pool (",
      paste(names(dropped_counts), dropped_counts, sep = "=", collapse = ", "), ")."
    )
  }
  calibrator
}

.page_horizon_key <- function(x) {
  x <- trimws(as.character(x))
  x <- sub("^h", "", x)
  value <- suppressWarnings(as.numeric(x))
  out <- rep(NA_character_, length(value))
  valid <- is.finite(value) & value > 0 & value == as.integer(value)
  out[valid] <- as.character(as.integer(value[valid]))
  out
}

.page_season_key <- function(x) {
  out <- trimws(as.character(x))
  out[is.na(out) | !nzchar(out)] <- NA_character_
  season_parts <- regmatches(out, regexec("^([0-9]{4})[-/]([0-9]{2}|[0-9]{4})$", out))
  has_season_parts <- lengths(season_parts) == 3L
  if (any(has_season_parts)) {
    starts <- vapply(season_parts[has_season_parts], `[[`, character(1), 2L)
    ends <- vapply(season_parts[has_season_parts], `[[`, character(1), 3L)
    ends <- ifelse(nchar(ends) == 4L, substr(ends, 3L, 4L), ends)
    out[has_season_parts] <- paste0(starts, "-", ends)
  }
  out
}

.page_local_seed <- function(seed, code) {
  if (is.null(seed)) {
    return(force(code))
  }
  if (!is.numeric(seed) || length(seed) != 1L || !is.finite(seed)) {
    stop("`seed` must be NULL or one finite number.", call. = FALSE)
  }
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv)
  on.exit(
    {
      if (had_seed) {
        assign(".Random.seed", old_seed, envir = .GlobalEnv)
      } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    },
    add = TRUE
  )
  set.seed(as.integer(seed))
  force(code)
}

#' Construct a sample-based PAGe predictive distribution
#'
#' This constructor is the model-agnostic entry point for engines that already
#' provide predictive draws. Values must be on the declared outcome scale.
#'
#' @examples
#' d <- new_page_predictive_distribution(
#'   c(0.01, 0.02, 0.03),
#'   outcome = "positivity_observed"
#' )
#' probability_above(d, 0.02)
#' @seealso \code{\link[=predictive_distribution]{predictive_distribution()}},
#'   \code{\link[=fit_forecast_calibrator]{fit_forecast_calibrator()}},
#'   \code{\link[=probability_above]{probability_above()}},
#'   \code{\link[=probability_below]{probability_below()}}
#' @family predictive distributions
#'
#' @param draws Numeric predictive draws. An empty vector is allowed only when
#'   \code{status = "unavailable"}.
#' @param weights Optional finite, non-negative atom weights matching
#'   \code{draws}; positive weights are normalized to sum to one. Weighted
#'   summaries are exact and have no Monte Carlo error interval.
#' @param outcome One-word or short label describing the forecasted outcome.
#' @param scale Scale of the draws, for example \code{"proportion"}.
#' @param support Numeric length-two lower and upper bounds.
#' @param origin Optional origin metadata, typically a list with season and
#'   week.
#' @param target Optional target metadata, typically a list with season and
#'   week.
#' @param horizon Optional positive integer forecast horizon.
#' @param calibration Optional calibration metadata.
#' @param provenance Optional identity metadata for the forecasting and
#'   calibration artifacts.
#' @param status Either \code{"available"}, \code{"experimental"}, or
#'   \code{"unavailable"}.
#'
#' @return An object of class \code{page_predictive_distribution}.
#' @export
new_page_predictive_distribution <- function(draws,
                                             outcome,
                                             scale = "proportion",
                                             support = c(0, 1),
                                             origin = NULL,
                                             target = NULL,
                                             horizon = NULL,
                                             calibration = NULL,
                                             provenance = NULL,
                                             status = c("available", "experimental", "unavailable"),
                                             weights = NULL) {
  status <- match.arg(status)
  if (!is.numeric(draws) || !is.null(dim(draws)) || any(!is.finite(draws))) {
    stop("`draws` must be a numeric vector containing only finite values.", call. = FALSE)
  }
  if (!is.character(outcome) || length(outcome) != 1L || is.na(outcome) || !nzchar(outcome)) {
    stop("`outcome` must be one non-empty string.", call. = FALSE)
  }
  if (!is.character(scale) || length(scale) != 1L || is.na(scale) || !nzchar(scale)) {
    stop("`scale` must be one non-empty string.", call. = FALSE)
  }
  if (!is.numeric(support) || length(support) != 2L || any(!is.finite(support)) ||
    support[1L] >= support[2L]) {
    stop("`support` must be two finite values in increasing order.", call. = FALSE)
  }
  if (any(draws < support[1L] | draws > support[2L])) {
    stop("All `draws` must lie inside the declared `support`.", call. = FALSE)
  }
  if (!is.null(weights)) {
    weight_sum <- if (is.numeric(weights) && all(is.finite(weights))) sum(weights) else NA_real_
    if (!is.numeric(weights) || length(weights) != length(draws) ||
      any(!is.finite(weights)) || any(weights < 0) || !is.finite(weight_sum) || weight_sum <= 0) {
      stop("`weights` must be finite, non-negative, and match `draws` with positive sum.", call. = FALSE)
    }
    weights <- as.numeric(weights) / weight_sum
  }
  if (identical(status, "unavailable") && length(draws) > 0L) {
    stop("Unavailable distributions must not contain draws.", call. = FALSE)
  }
  if (!identical(status, "unavailable") && length(draws) < 2L) {
    stop("Available distributions require at least two draws.", call. = FALSE)
  }
  if (!is.null(horizon) && (!is.numeric(horizon) || length(horizon) != 1L ||
    !is.finite(horizon) || horizon < 1 || horizon != as.integer(horizon))) {
    stop("`horizon` must be NULL or one positive integer.", call. = FALSE)
  }
  structure(
    list(
      draws = as.numeric(draws), outcome = outcome, scale = scale,
      support = as.numeric(support), origin = origin, target = target,
      horizon = if (is.null(horizon)) NULL else as.integer(horizon),
      calibration = calibration, provenance = provenance, status = status,
      weights = weights
    ),
    class = "page_predictive_distribution"
  )
}

#' Build a next-horizon predictive distribution
#'
#' This is an S3 generic so forecast engines can implement distribution methods
#' without sharing model internals. The \code{page_forecast} method extracts
#' the latest origin at the requested horizon from a single-season forecast,
#' then samples season-balanced out-of-sample residuals
#' from a fitted calibrator. The resulting Jeffreys-smoothed positivity
#' distribution is
#' explicitly experimental until independently validated. Its residuals
#' pool forecast error with observation noise across historical denominators;
#' no realized future testing volume is read or assumed known. Residuals are
#' pooled by horizon across epidemic phases and historical test volumes, so the
#' result is marginal over those calibration conditions. The horizon-specific
#' residuals must come from the same forecast protocol, identified by
#' \code{predictor_id}. That identifier is an explicit caller attestation
#' unless the forecast object already carries it. Calibration seasons are
#' checked for overlap, but this method cannot establish chronology; the caller
#' must ensure all calibration seasons precede the forecast season. Common
#' \code{YYYY-YY} and \code{YYYY/YY} labels are canonicalized for overlap checks.
#'
#' @param forecast A model forecast object. The built-in method accepts a
#'   single-season \code{page_forecast} returned by
#'   \code{run_prospective_pipeline()}.
#' @param calibrator A \code{page_forecast_calibrator} from
#'   \code{fit_forecast_calibrator()}.
#' @param horizon Positive integer forecast horizon.
#' @param point_col Point forecast column in \code{forecast$m2_preds}.
#' @param outcome Outcome label recorded on the distribution. The built-in
#'   adapter defaults to \code{"positivity_jeffreys_smoothed"} because its
#'   count correction shifts residual targets slightly toward 0.5.
#' @param n_draws Number of predictive draws.
#' @param seed Optional seed. When supplied, the caller's random-number state is
#'   preserved.
#' @param predictor_id Optional protocol identifier. If absent, the method
#'   uses \code{forecast$predictor_id}. It must match the calibrator identifier.
#' @param ... Additional arguments passed to the selected method. The built-in
#'   \code{page_forecast} method rejects unused arguments.
#'
#' @return A \code{page_predictive_distribution}. If the requested target is
#'   unavailable, returns an explicit unavailable object with no draws.
#' @examples
#' # Synthetic out-of-sample rows demonstrate the interface only; they do not
#' # establish calibration for any real PAGe model.
#' oos <- data.frame(
#'   season = rep(c("s1", "s2", "s3"), each = 2),
#'   eval_week = rep(10:11, 3), lead = 1L,
#'   p_hat = rep(c(0.01, 0.02), 3),
#'   y_lead = c(1, 2, 2, 3, 1, 4), N_lead = 100
#' )
#' oos$p_obs <- oos$y_lead / oos$N_lead
#' cal <- fit_forecast_calibrator(
#'   oos,
#'   predictor_id = "example-protocol-v1", out_of_sample = TRUE
#' )
#' fc <- structure(list(
#'   season = "s4", predictor_id = "example-protocol-v1",
#'   m2_preds = data.frame(
#'     eval_week = 10L, h = 1L, target_weekF = 11L,
#'     forecast_available = TRUE, m2_p = 0.02
#'   )
#' ), class = c("page_forecast", "list"))
#' d <- predictive_distribution(fc, cal, seed = 1L)
#' probability_above(d, 0.02)
#' @seealso \code{\link[=fit_forecast_calibrator]{fit_forecast_calibrator()}},
#'   \code{\link[=new_page_predictive_distribution]{new_page_predictive_distribution()}},
#'   \code{\link[=probability_above]{probability_above()}},
#'   \code{\link[=probability_below]{probability_below()}}
#' @family predictive distributions
#' @export
predictive_distribution <- function(forecast, ...) {
  UseMethod("predictive_distribution")
}

#' @rdname predictive_distribution
#' @export
predictive_distribution.page_forecast <- function(forecast,
                                                  calibrator,
                                                  horizon = 1L,
                                                  point_col = "m2_p",
                                                  outcome = "positivity_jeffreys_smoothed",
                                                  n_draws = 10000L,
                                                  seed = NULL,
                                                  predictor_id = NULL,
                                                  ...) {
  if (length(list(...))) stop("Unused arguments supplied to the page_forecast method.", call. = FALSE)
  if (!inherits(forecast, "page_forecast") || !is.data.frame(forecast$m2_preds)) {
    stop("`forecast` must be a `page_forecast` with a data-frame `m2_preds`.", call. = FALSE)
  }
  if (!inherits(calibrator, "page_forecast_calibrator")) {
    stop("`calibrator` must be fitted by `fit_forecast_calibrator()`.", call. = FALSE)
  }
  stored_calibrator_id <- calibrator$calibrator_id
  calibrator_copy <- calibrator
  calibrator_copy$calibrator_id <- NULL
  if (is.null(stored_calibrator_id) ||
    !identical(stored_calibrator_id, digest::digest(calibrator_copy, algo = "sha256"))) {
    stop("The forecast calibrator is missing its identity or was modified after fitting.", call. = FALSE)
  }
  predictor_id <- predictor_id %||% forecast$predictor_id
  if (is.null(predictor_id) || length(predictor_id) != 1L || is.na(predictor_id) ||
    !identical(as.character(predictor_id), calibrator$predictor_id)) {
    stop("Supply a `predictor_id` matching the calibrator's forecast protocol.", call. = FALSE)
  }
  if (!is.numeric(horizon) || length(horizon) != 1L || !is.finite(horizon) ||
    horizon < 1 || horizon != as.integer(horizon)) {
    stop("`horizon` must be one positive integer.", call. = FALSE)
  }
  if (!is.numeric(n_draws) || length(n_draws) != 1L || !is.finite(n_draws) ||
    n_draws < 2 || n_draws != as.integer(n_draws)) {
    stop("`n_draws` must be one integer of at least 2.", call. = FALSE)
  }
  pred <- as.data.frame(forecast$m2_preds)
  needed <- c("eval_week", "h", "target_weekF", "forecast_available", point_col)
  missing <- setdiff(needed, names(pred))
  if (length(missing)) {
    stop("`forecast$m2_preds` is missing: ", paste(missing, collapse = ", "), ".", call. = FALSE)
  }
  forecast_seasons <- if ("season" %in% names(pred)) {
    season_keys <- .page_season_key(pred$season)
    if (anyNA(season_keys)) stop("Forecast rows contain missing season identifiers.", call. = FALSE)
    unique(season_keys)
  } else {
    .page_season_key(forecast$season %||% character(0))
  }
  if (length(forecast_seasons) != 1L) {
    stop("`forecast` must describe exactly one season.", call. = FALSE)
  }
  if ("season" %in% names(pred) && !is.null(forecast$season)) {
    object_season <- unique(.page_season_key(forecast$season))
    if (length(object_season) != 1L || !identical(object_season, forecast_seasons)) {
      stop("`forecast$season` does not match the forecast-row season.", call. = FALSE)
    }
  }
  horizon_key <- as.character(as.integer(horizon))
  calibration_rows <- calibrator$residuals[calibrator$residuals$horizon == horizon_key, , drop = FALSE]
  if (!nrow(calibration_rows)) {
    stop("The calibrator has no residuals for horizon ", horizon_key, ".", call. = FALSE)
  }
  rows <- pred[.page_horizon_key(pred$h) == horizon_key, , drop = FALSE]
  if (!nrow(rows)) {
    stop("The forecast has no rows for horizon ", horizon_key, ".", call. = FALSE)
  }
  latest_origin <- suppressWarnings(max(as.numeric(rows$eval_week), na.rm = TRUE))
  if (!is.finite(latest_origin)) stop("The forecast origin week is unavailable.", call. = FALSE)
  row <- rows[as.numeric(rows$eval_week) == latest_origin, , drop = FALSE]
  if (nrow(row) != 1L) stop("The latest forecast row is not unique.", call. = FALSE)

  origin <- list(week = as.integer(latest_origin))
  if ("season" %in% names(row)) origin$season <- .page_season_key(row$season[[1L]])
  if (is.null(origin$season) && !is.null(forecast$season)) {
    origin$season <- .page_season_key(forecast$season[[1L]])
  }
  if (is.null(origin$season) || length(origin$season) != 1L || is.na(origin$season) ||
    !nzchar(origin$season)) {
    stop("A single forecast season is required to guard against calibrator leakage.", call. = FALSE)
  }
  if (origin$season %in% calibrator$training_seasons) {
    stop("The forecast season is present in the calibrator's training seasons.", call. = FALSE)
  }
  target_week <- suppressWarnings(as.numeric(row$target_weekF[[1L]]))
  if (!is.finite(target_week) || target_week != as.integer(target_week) ||
    target_week != latest_origin + as.integer(horizon)) {
    stop("The selected forecast row has an invalid target week.", call. = FALSE)
  }
  target <- list(week = as.integer(target_week))
  if (!is.null(origin$season)) target$season <- origin$season
  if (!isTRUE(row$forecast_available[[1L]]) || !is.finite(as.numeric(row[[point_col]][[1L]]))) {
    return(new_page_predictive_distribution(
      numeric(),
      outcome = outcome, origin = origin, target = target,
      horizon = as.integer(horizon),
      calibration = list(
        method = calibrator$method, status = calibrator$status,
        n_seasons = length(unique(calibration_rows$season)),
        n_origins = nrow(calibration_rows),
        training_seasons = sort(unique(calibration_rows$season)),
        predictor_id = predictor_id, calibrator_id = calibrator$calibrator_id
      ),
      provenance = list(predictor_id = predictor_id, calibrator_id = calibrator$calibrator_id),
      status = "unavailable"
    ))
  }
  p_hat <- as.numeric(row[[point_col]][[1L]])
  if (p_hat < 0 || p_hat > 1) stop("The point forecast must lie in [0, 1].", call. = FALSE)
  eps <- calibrator$eps
  if (p_hat <= eps || p_hat >= 1 - eps) {
    stop(
      "The point forecast lies at or beyond the calibrator's logit boundary; ",
      "the residual pool does not support extrapolation there.",
      call. = FALSE
    )
  }
  residual_seasons <- split(seq_len(nrow(calibration_rows)), calibration_rows$season)
  rng_kind <- RNGkind()
  r_version <- as.character(getRversion())
  samples <- .page_local_seed(seed, {
    sampled_seasons <- sample(names(residual_seasons), size = as.integer(n_draws), replace = TRUE)
    sampled_rows <- vapply(sampled_seasons, function(s) {
      idx <- residual_seasons[[s]]
      idx[sample.int(length(idx), size = 1L)]
    }, integer(1))
    sampled <- calibration_rows[sampled_rows, , drop = FALSE]
    stats::plogis(stats::qlogis(p_hat) + sampled$residual)
  })
  seasons_used <- sort(unique(calibration_rows$season))
  new_page_predictive_distribution(
    samples,
    outcome = outcome,
    origin = origin, target = target, horizon = as.integer(horizon),
    calibration = list(
      method = calibrator$method, status = calibrator$status,
      n_seasons = length(seasons_used), n_origins = nrow(calibration_rows),
      training_seasons = seasons_used,
      predictor_id = predictor_id,
      calibrator_id = calibrator$calibrator_id,
      point_forecast = p_hat,
      seed = seed, rng_kind = rng_kind, r_version = as.character(r_version),
      n_draws = as.integer(n_draws), eps = eps,
      denominator_handling = "Jeffreys_corrected_residuals_pooled_over_training_volumes"
    ),
    provenance = list(predictor_id = predictor_id, calibrator_id = calibrator$calibrator_id),
    status = "experimental"
  )
}

#' @rdname predictive_distribution
#' @export
predictive_distribution.default <- function(forecast, ...) {
  stop(
    "No `predictive_distribution()` method is registered for class `",
    class(forecast)[[1L]], "`.",
    call. = FALSE
  )
}

#' Return predictive draws
#'
#' @param object A \code{page_predictive_distribution}.
#' @return Numeric vector of predictive draws.
#' @seealso \code{\link[=distribution_weights]{distribution_weights()}} for
#'   weighted atoms.
#' @export
distribution_draws <- function(object) {
  .check_page_predictive_distribution(object)
  if (!identical(object$status, "unavailable")) {
    return(object$draws)
  }
  numeric()
}

#' Return predictive atom weights
#'
#' @param object A \code{page_predictive_distribution}.
#' @return Normalized atom weights. Unweighted draws receive equal weights.
#' @export
distribution_weights <- function(object) {
  .check_page_predictive_distribution(object)
  if (identical(object$status, "unavailable")) {
    return(numeric())
  }
  if (!is.null(object$weights)) {
    return(object$weights)
  }
  rep(1 / length(object$draws), length(object$draws))
}

#' Compute predictive quantiles
#'
#' @param object A \code{page_predictive_distribution}.
#' @param probs Numeric probabilities in [0, 1].
#' @return Numeric quantiles on the declared outcome scale.
#' @export
distribution_quantile <- function(object, probs = c(0.05, 0.5, 0.95)) {
  .check_page_predictive_distribution(object)
  if (identical(object$status, "unavailable")) {
    stop("Quantiles are unavailable because the forecast is unavailable.", call. = FALSE)
  }
  if (!is.numeric(probs) || !length(probs) || any(!is.finite(probs)) ||
    any(probs < 0 | probs > 1)) {
    stop("`probs` must contain finite values in [0, 1].", call. = FALSE)
  }
  if (!is.null(object$weights)) {
    return(vapply(probs, function(prob) {
      ord <- order(object$draws)
      x <- object$draws[ord]
      w <- object$weights[ord]
      if (prob <= 0) {
        return(x[1L])
      }
      if (prob >= 1) {
        return(x[length(x)])
      }
      cumulative <- cumsum(w)
      cumulative[length(cumulative)] <- 1
      x[which(cumulative >= prob)[1L]]
    }, numeric(1)))
  }
  as.numeric(stats::quantile(object$draws, probs = probs, names = FALSE, type = 1L))
}

#' Evaluate the empirical predictive cumulative distribution function
#'
#' @param object A \code{page_predictive_distribution}.
#' @param q Numeric thresholds on the distribution's outcome scale.
#' @return Numeric probabilities \eqn{P(Y \le q)}{P(Y <= q)}.
#' @export
distribution_cdf <- function(object, q) {
  .check_page_predictive_distribution(object)
  if (identical(object$status, "unavailable")) {
    stop("The CDF is unavailable because the forecast is unavailable.", call. = FALSE)
  }
  if (!is.numeric(q) || any(!is.finite(q))) {
    stop("`q` must contain only finite numeric values.", call. = FALSE)
  }
  if (!is.null(object$weights)) {
    return(vapply(q, function(value) sum(object$weights[object$draws <= value]), numeric(1)))
  }
  vapply(q, function(value) mean(object$draws <= value), numeric(1))
}

#' Compute a threshold exceedance probability
#'
#' @param object A \code{page_predictive_distribution}.
#' @param threshold One finite threshold on the distribution's outcome scale.
#' @param inclusive If FALSE, compute P(Y > threshold); if TRUE, compute
#'   P(Y >= threshold).
#' @return One probability in [0, 1]. Attributes \code{mc_se} and
#'   \code{mc_interval} describe only finite-draw simulation error;
#'   they do not include uncertainty in the residual calibrator.
#' @export
probability_above <- function(object, threshold, inclusive = FALSE) {
  .page_probability(object, threshold, inclusive, direction = "above")
}

#' Compute a threshold shortfall probability
#'
#' @param object A \code{page_predictive_distribution}.
#' @param threshold One finite threshold on the distribution's outcome scale.
#' @param inclusive If FALSE, compute P(Y < threshold); if TRUE, compute
#'   P(Y <= threshold).
#' @return One probability in [0, 1]. Attributes \code{mc_se} and
#'   \code{mc_interval} describe only finite-draw simulation error;
#'   they do not include uncertainty in the residual calibrator.
#' @export
probability_below <- function(object, threshold, inclusive = FALSE) {
  .page_probability(object, threshold, inclusive, direction = "below")
}

.check_page_predictive_distribution <- function(object) {
  if (!inherits(object, "page_predictive_distribution") || !is.list(object)) {
    stop("`object` must be a `page_predictive_distribution`.", call. = FALSE)
  }
  invisible(object)
}

.page_probability <- function(object, threshold, inclusive, direction) {
  .check_page_predictive_distribution(object)
  if (!is.numeric(threshold) || length(threshold) != 1L || !is.finite(threshold)) {
    stop("`threshold` must be one finite number.", call. = FALSE)
  }
  if (!is.logical(inclusive) || length(inclusive) != 1L || is.na(inclusive)) {
    stop("`inclusive` must be TRUE or FALSE.", call. = FALSE)
  }
  if (identical(object$status, "unavailable")) {
    stop("A probability cannot be calculated because the forecast is unavailable.", call. = FALSE)
  }
  x <- object$draws
  hit <- if (direction == "above") {
    if (inclusive) x >= threshold else x > threshold
  } else if (inclusive) {
    x <= threshold
  } else {
    x < threshold
  }
  count <- sum(hit)
  p <- if (is.null(object$weights)) count / length(x) else sum(object$weights[hit])
  if (is.null(object$weights)) {
    attr(p, "mc_se") <- if (p %in% c(0, 1)) NA_real_ else sqrt(p * (1 - p) / length(x))
    attr(p, "mc_interval") <- stats::binom.test(count, length(x))$conf.int
  } else {
    attr(p, "mc_se") <- NA_real_
    attr(p, "mc_interval") <- c(NA_real_, NA_real_)
  }
  attr(p, "n_seasons") <- object$calibration$n_seasons %||% NA_integer_
  attr(p, "n_origins") <- object$calibration$n_origins %||% NA_integer_
  p
}

#' @export
print.page_predictive_distribution <- function(x, ...) {
  .check_page_predictive_distribution(x)
  cat("<PAGe predictive distribution>\n")
  cat("  outcome: ", x$outcome, " (", x$scale, ")\n", sep = "")
  cat("  horizon: ", x$horizon %||% "unspecified", " | status: ", x$status, "\n", sep = "")
  if (identical(x$status, "unavailable")) {
    cat("  draws: unavailable\n")
  } else if (!is.null(x$weights)) {
    cat("  atoms: ", length(x$draws), " | effective_n: ",
      round(1 / sum(x$weights^2), 2), "\n",
      sep = ""
    )
  } else {
    cat("  draws: ", length(x$draws), "\n", sep = "")
    if (identical(x$status, "experimental")) cat("  calibration: experimental\n")
  }
  invisible(x)
}
