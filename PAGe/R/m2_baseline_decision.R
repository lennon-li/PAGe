# Data-agnostic M2 versus M1 adoption decision.

#' Decide whether an M2 candidate earns adoption over M1
#'
#' Applies a prospective, equal-season baseline decision to matched forecasts.
#' M1 is the incumbent and M2 is adopted only when its Bernoulli NLL gain is
#' larger than both the requested practical floor and a one-sided
#' season-level uncertainty allowance. The all-off M2 configuration can use
#' this decision as an exact M1 fallback.
#'
#' Rows may be weighted by a supplied denominator and/or phase weights. The
#' primary aggregation is always equal across seasons: rows are summarized
#' within season and horizon first, then seasons are averaged. No pathogen,
#' source column, or influenza-specific season label is assumed.
#'
#' @param forecasts Data frame with one row per season, origin, target, and
#'   horizon, containing the observed proportion and M1/M2 predictions.
#' @param outcome_col,m1_col,m2_col Character scalar column names for the
#'   observed proportion and the two predictions.
#' @param season_col,origin_col,target_col,horizon_col Character scalar column
#'   names defining the unique forecast key.
#' @param phase_col Optional phase-label column. When supplied with
#'   \code{phase_weights}, every observed non-missing phase must have a named
#'   weight.
#' @param t_since_col Optional numeric column used to derive
#'   \code{pre_ignition}, \code{early}, and \code{late} labels. Values from
#'   zero through \code{phase_break} are early; larger values are late.
#' @param phase_break Non-negative numeric boundary used with
#'   \code{t_since_col}. It must be supplied when \code{t_since_col} is used;
#'   there is no pathogen-specific default.
#' @param phase_weights Optional named non-negative weights. With no phase
#'   source, all rows have weight one. A zero weight excludes a phase from the
#'   score while retaining it in the input accounting.
#' @param denominator_col Optional positive numeric column, such as test
#'   volume. It is multiplied by the phase weight when supplied.
#' @param horizon_weights Optional named non-negative weights by horizon.
#'   Unspecified horizons receive equal weight when this is \code{NULL}.
#' @param min_gain Non-negative practical NLL gain floor on the equal-season
#'   overall score.
#' @param min_gain_by_horizon Optional named practical NLL gain floors for
#'   selected horizons. These are additional horizon-specific adoption gates.
#' @param confidence One-sided confidence level used for the season-level
#'   uncertainty allowance.
#' @param max_season_degradation Maximum tolerated equal-season NLL increase
#'   for any season after combining horizons. The default zero is a strict
#'   historical non-degradation rule.
#' @param eps Probability clipping value used in the NLL calculation.
#'
#' @return A \code{page_m2_baseline_decision} list with \code{decision},
#'   \code{reasons}, \code{rule}, \code{overall}, \code{by_horizon},
#'   \code{by_season}, and row-accounting entries.
#' @export
decide_m2_vs_m1 <- function(
  forecasts,
  outcome_col,
  m1_col,
  m2_col,
  season_col,
  origin_col,
  target_col,
  horizon_col,
  phase_col = NULL,
  t_since_col = NULL,
  phase_break = NULL,
  phase_weights = NULL,
  denominator_col = NULL,
  horizon_weights = NULL,
  min_gain = 0,
  min_gain_by_horizon = NULL,
  confidence = 0.95,
  max_season_degradation = 0,
  eps = 1e-12
) {
  forecasts <- .m2_decision_validate_frame(forecasts)
  mappings <- c(
    outcome = outcome_col, m1 = m1_col, m2 = m2_col,
    season = season_col, origin = origin_col, target = target_col,
    horizon = horizon_col
  )
  .m2_decision_validate_mappings(mappings, forecasts)
  if (!is.null(phase_col) && !is.null(t_since_col)) {
    stop("Supply only one of `phase_col` or `t_since_col`.", call. = FALSE)
  }
  .m2_decision_validate_probability(forecasts[[outcome_col]], "outcome")
  .m2_decision_validate_probability(forecasts[[m1_col]], "M1 prediction")
  .m2_decision_validate_probability(forecasts[[m2_col]], "M2 prediction")
  .m2_decision_validate_key(forecasts, mappings)
  horizon <- suppressWarnings(as.numeric(forecasts[[horizon_col]]))
  if (any(!is.finite(horizon)) || any(horizon <= 0) || any(horizon != floor(horizon))) {
    stop("`horizon` must contain finite positive integer values.", call. = FALSE)
  }
  .m2_decision_validate_nonnegative(min_gain, "`min_gain`")
  .m2_decision_validate_nonnegative(max_season_degradation, "`max_season_degradation`")
  if (!is.numeric(confidence) || length(confidence) != 1L ||
    !is.finite(confidence) || confidence <= 0 || confidence >= 1) {
    stop("`confidence` must be one finite number strictly between 0 and 1.", call. = FALSE)
  }
  if (!is.numeric(eps) || length(eps) != 1L || !is.finite(eps) ||
    eps <= 0 || eps >= 0.5) {
    stop("`eps` must be one finite number in (0, 0.5).", call. = FALSE)
  }
  if (!is.null(t_since_col)) {
    .m2_decision_validate_mappings(c(t_since = t_since_col), forecasts)
    t_since <- suppressWarnings(as.numeric(forecasts[[t_since_col]]))
    if (any(!is.na(t_since) & !is.finite(t_since))) {
      stop("`t_since_col` must contain finite values or missing values.", call. = FALSE)
    }
    if (is.null(phase_break) || !is.numeric(phase_break) || length(phase_break) != 1L ||
      !is.finite(phase_break) || phase_break < 0) {
      stop("`phase_break` must be one finite non-negative number.", call. = FALSE)
    }
    phase <- ifelse(
      is.na(t_since), NA_character_,
      ifelse(t_since < 0, "pre_ignition",
        ifelse(t_since <= phase_break, "early", "late")
      )
    )
  } else if (!is.null(phase_col)) {
    .m2_decision_validate_mappings(c(phase = phase_col), forecasts)
    phase <- as.character(forecasts[[phase_col]])
  } else {
    phase <- rep("all", nrow(forecasts))
  }
  phase_weight <- .m2_decision_resolve_weights(
    phase, phase_weights, "phase",
    default = 1
  )
  denominator <- .m2_decision_resolve_denominator(denominator_col, forecasts)
  horizon_labels <- sort(unique(as.character(horizon)))
  horizon_weight <- .m2_decision_validate_horizon_weights(
    horizon_weights, horizon_labels
  )

  p_obs <- as.numeric(forecasts[[outcome_col]])
  p_m1 <- as.numeric(forecasts[[m1_col]])
  p_m2 <- as.numeric(forecasts[[m2_col]])
  score_weight <- phase_weight * denominator
  valid <- is.finite(p_obs) & is.finite(p_m1) & is.finite(p_m2) &
    is.finite(score_weight) & score_weight > 0 &
    horizon_weight[match(as.character(horizon), names(horizon_weight))] > 0
  if (!any(valid)) {
    stop("No matched forecast rows remain with positive decision weight.", call. = FALSE)
  }
  clip <- function(x) pmin(1 - eps, pmax(eps, x))
  nll <- function(y, p) {
    p <- clip(p)
    -(y * log(p) + (1 - y) * log1p(-p))
  }
  frame <- data.frame(
    season = as.character(forecasts[[season_col]]),
    horizon = horizon,
    phase = phase,
    m1_nll = nll(p_obs, p_m1), m2_nll = nll(p_obs, p_m2),
    m1_mae = abs(p_m1 - p_obs), m2_mae = abs(p_m2 - p_obs),
    weight = score_weight, valid = valid,
    stringsAsFactors = FALSE
  )
  frame <- frame[frame$valid, , drop = FALSE]
  result <- .m2_decision_summarize(
    frame, horizon_weight, min_gain, min_gain_by_horizon,
    confidence, max_season_degradation, phase_weights, denominator_col
  )
  phase_labels <- unique(phase[!is.na(phase)])
  result$rule$phase_source <- if (!is.null(phase_col)) {
    "phase_col"
  } else if (!is.null(t_since_col)) {
    "t_since_col"
  } else {
    "none"
  }
  result$rule$phase_break <- if (is.null(t_since_col)) NA_real_ else phase_break
  result$rule$phase_weights <- if (is.null(phase_weights)) {
    stats::setNames(rep(1, length(phase_labels)), phase_labels)
  } else {
    phase_weights
  }
  result$rule$horizon_weights <- horizon_weight
  result
}

.m2_decision_validate_frame <- function(x) {
  if (!is.data.frame(x) || !nrow(x)) {
    stop("`forecasts` must be a non-empty data frame.", call. = FALSE)
  }
  x
}

.m2_decision_validate_mappings <- function(mappings, data) {
  for (mapping in mappings) {
    if (!is.character(mapping) || length(mapping) != 1L || is.na(mapping) ||
      !nzchar(mapping)) {
      stop("Every column mapping must be a non-empty character scalar.", call. = FALSE)
    }
  }
  missing <- unname(mappings)[!unname(mappings) %in% names(data)]
  if (length(missing)) {
    stop("Mapped column `", missing[[1L]], "` is absent from `forecasts`.", call. = FALSE)
  }
}

.m2_decision_validate_key <- function(data, mappings) {
  key <- unname(mappings[c("season", "origin", "target", "horizon")])
  if (any(vapply(data[key], anyNA, logical(1))) || any(duplicated(data[key]))) {
    stop("Forecast key columns must be complete and unique.", call. = FALSE)
  }
}

.m2_decision_validate_probability <- function(x, label) {
  if (!is.numeric(x)) stop("The `", label, "` column must be numeric.", call. = FALSE)
  bad <- !is.na(x) & (!is.finite(x) | x < 0 | x > 1)
  if (any(bad)) stop("The `", label, "` column must contain values in [0, 1] or NA.", call. = FALSE)
}

.m2_decision_validate_nonnegative <- function(x, label) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x < 0) {
    stop(label, " must be one finite non-negative number.", call. = FALSE)
  }
}

.m2_decision_resolve_weights <- function(labels, weights, label, default = 1) {
  labels <- as.character(labels)
  if (is.null(weights)) {
    return(rep(default, length(labels)))
  }
  if (!is.numeric(weights) || !length(weights) || any(!is.finite(weights)) ||
    any(weights < 0) || is.null(names(weights)) || any(!nzchar(names(weights))) ||
    anyDuplicated(names(weights))) {
    stop("`", label, "_weights` must be a named finite non-negative numeric vector.", call. = FALSE)
  }
  observed <- unique(labels[!is.na(labels)])
  if (any(!observed %in% names(weights))) {
    stop("`", label, "_weights` is missing observed label(s): ",
      paste(setdiff(observed, names(weights)), collapse = ", "),
      call. = FALSE
    )
  }
  out <- unname(weights[match(labels, names(weights))])
  if (!any(out > 0, na.rm = TRUE)) {
    stop("`", label, "_weights` must assign positive weight to at least one observed label.", call. = FALSE)
  }
  out
}

.m2_decision_resolve_denominator <- function(column, data) {
  if (is.null(column)) {
    return(rep(1, nrow(data)))
  }
  .m2_decision_validate_mappings(c(denominator = column), data)
  value <- data[[column]]
  if (!is.numeric(value) || any(!is.na(value) & (!is.finite(value) | value <= 0))) {
    stop("`denominator_col` must contain positive numeric values or NA.", call. = FALSE)
  }
  as.numeric(value)
}

.m2_decision_validate_horizon_weights <- function(weights, horizons) {
  if (is.null(weights)) {
    return(setNames(rep(1, length(horizons)), horizons))
  }
  if (!is.numeric(weights) || !length(weights) || any(!is.finite(weights)) ||
    any(weights < 0) || is.null(names(weights)) || anyDuplicated(names(weights))) {
    stop("`horizon_weights` must be a named finite non-negative numeric vector.", call. = FALSE)
  }
  if (any(!horizons %in% names(weights))) {
    stop("`horizon_weights` is missing observed horizon(s).", call. = FALSE)
  }
  out <- weights[match(horizons, names(weights))]
  if (!any(out > 0)) stop("`horizon_weights` must assign positive weight to a horizon.", call. = FALSE)
  setNames(as.numeric(out), horizons)
}

.m2_decision_validate_min_gain_by_horizon <- function(x, horizons) {
  if (is.null(x)) {
    return(setNames(rep(0, length(horizons)), horizons))
  }
  if (!is.numeric(x) || any(!is.finite(x)) || any(x < 0) ||
    is.null(names(x)) || anyDuplicated(names(x)) || any(!nzchar(names(x)))) {
    stop("`min_gain_by_horizon` must be a named finite non-negative numeric vector.", call. = FALSE)
  }
  if (any(!names(x) %in% horizons)) stop("`min_gain_by_horizon` contains unknown horizon(s).", call. = FALSE)
  out <- setNames(rep(0, length(horizons)), horizons)
  out[names(x)] <- as.numeric(x)
  out
}

.m2_decision_weighted_mean <- function(x, weight) {
  sum(x * weight) / sum(weight)
}

.m2_decision_summarize <- function(
  frame, horizon_weight, min_gain, min_gain_by_horizon, confidence,
  max_season_degradation, phase_weights, denominator_col
) {
  horizons <- sort(unique(as.character(frame$horizon)))
  horizon_weight <- .m2_decision_validate_horizon_weights(
    horizon_weight, horizons
  )
  min_gain_by_horizon <- .m2_decision_validate_min_gain_by_horizon(
    min_gain_by_horizon, horizons
  )
  frame$horizon_label <- as.character(frame$horizon)
  groups <- split(frame, interaction(frame$season, frame$horizon_label, drop = TRUE), drop = TRUE)
  sh <- do.call(rbind, lapply(groups, function(x) {
    data.frame(
      season = x$season[[1L]], horizon = x$horizon_label[[1L]],
      m1_nll = .m2_decision_weighted_mean(x$m1_nll, x$weight),
      m2_nll = .m2_decision_weighted_mean(x$m2_nll, x$weight),
      m1_mae = .m2_decision_weighted_mean(x$m1_mae, x$weight),
      m2_mae = .m2_decision_weighted_mean(x$m2_mae, x$weight),
      n_predictions = nrow(x), total_weight = sum(x$weight),
      stringsAsFactors = FALSE
    )
  }))
  sh$delta_nll <- sh$m2_nll - sh$m1_nll
  sh$gain_nll <- -sh$delta_nll
  sh$delta_mae <- sh$m2_mae - sh$m1_mae
  by_horizon <- do.call(rbind, lapply(split(sh, sh$horizon), function(x) {
    data.frame(
      horizon = x$horizon[[1L]],
      m1_nll = mean(x$m1_nll), m2_nll = mean(x$m2_nll),
      delta_nll = mean(x$delta_nll), gain_nll = -mean(x$delta_nll),
      m1_mae = mean(x$m1_mae), m2_mae = mean(x$m2_mae),
      delta_mae = mean(x$delta_mae), n_seasons = nrow(x),
      stringsAsFactors = FALSE
    )
  }))
  by_horizon$season_se_nll <- NA_real_
  by_horizon$uncertainty_gain <- NA_real_
  by_horizon$required_gain <- NA_real_
  for (i in seq_len(nrow(by_horizon))) {
    v <- sh$delta_nll[sh$horizon == by_horizon$horizon[[i]]]
    if (length(v) >= 2L) {
      uncertainty <- stats::qt(confidence, length(v) - 1L) * stats::sd(v) /
        sqrt(length(v))
      by_horizon$season_se_nll[[i]] <- stats::sd(v) / sqrt(length(v))
      by_horizon$uncertainty_gain[[i]] <- uncertainty
      by_horizon$required_gain[[i]] <- max(
        min_gain_by_horizon[[by_horizon$horizon[[i]]]], uncertainty
      )
    }
  }
  season_groups <- split(sh, sh$season, drop = TRUE)
  by_season <- do.call(rbind, lapply(season_groups, function(x) {
    hw <- unname(horizon_weight[x$horizon])
    data.frame(
      season = x$season[[1L]],
      m1_nll = .m2_decision_weighted_mean(x$m1_nll, hw),
      m2_nll = .m2_decision_weighted_mean(x$m2_nll, hw),
      delta_nll = .m2_decision_weighted_mean(x$delta_nll, hw),
      gain_nll = -.m2_decision_weighted_mean(x$delta_nll, hw),
      m1_mae = .m2_decision_weighted_mean(x$m1_mae, hw),
      m2_mae = .m2_decision_weighted_mean(x$m2_mae, hw),
      delta_mae = .m2_decision_weighted_mean(x$delta_mae, hw),
      n_horizons = nrow(x), stringsAsFactors = FALSE
    )
  }))
  n_seasons <- nrow(by_season)
  overall_gain <- mean(by_season$gain_nll)
  season_se <- if (n_seasons >= 2L) stats::sd(by_season$delta_nll) / sqrt(n_seasons) else NA_real_
  uncertainty_gain <- if (n_seasons >= 2L) {
    stats::qt(confidence, n_seasons - 1L) * season_se
  } else {
    Inf
  }
  required_gain <- max(min_gain, uncertainty_gain)
  lower_confidence_gain <- overall_gain - uncertainty_gain
  worst_season_delta <- max(by_season$delta_nll)
  horizon_pass <- by_horizon$gain_nll >= by_horizon$required_gain
  horizon_pass[is.na(horizon_pass)] <- FALSE
  enough <- n_seasons >= 2L && is.finite(overall_gain)
  reasons <- character(0)
  if (!enough) reasons <- c(reasons, "insufficient_season_evidence")
  if (enough && overall_gain <= 0) reasons <- c(reasons, "m2_not_strictly_better_than_m1")
  if (enough && overall_gain < required_gain) reasons <- c(reasons, "overall_minimum_gain_failed")
  if (enough && any(!horizon_pass)) reasons <- c(reasons, "horizon_minimum_gain_failed")
  if (enough && worst_season_delta > max_season_degradation) {
    reasons <- c(reasons, "season_degradation_limit_failed")
  }
  decision <- if (!enough) {
    "insufficient_evidence"
  } else if (length(reasons)) {
    "keep_m1"
  } else {
    "use_m2"
  }
  overall <- data.frame(
    m1_nll = mean(by_season$m1_nll), m2_nll = mean(by_season$m2_nll),
    delta_nll = mean(by_season$delta_nll), gain_nll = overall_gain,
    season_se_nll = season_se, uncertainty_gain = uncertainty_gain,
    required_gain = required_gain,
    lower_confidence_gain = lower_confidence_gain,
    worst_season_delta_nll = worst_season_delta,
    n_seasons = n_seasons, stringsAsFactors = FALSE
  )
  rule <- list(
    primary_metric = "equal-season Bernoulli NLL",
    practical_min_gain = min_gain,
    horizon_min_gain = min_gain_by_horizon,
    confidence = confidence,
    max_season_degradation = max_season_degradation,
    phase_weights = phase_weights,
    denominator_weighting = !is.null(denominator_col),
    fallback = "keep_m1; the all-off M2 candidate is exactly M1"
  )
  structure(
    list(
      decision = decision, reasons = unique(reasons), rule = rule,
      overall = overall, by_horizon = by_horizon, by_season = by_season,
      matched = frame,
      accounting = list(matched_rows = nrow(frame), n_seasons = n_seasons)
    ),
    class = c("page_m2_baseline_decision", "list")
  )
}

#' @export
print.page_m2_baseline_decision <- function(x, ...) {
  cat("M2 versus M1 decision: ", x$decision, "\n", sep = "")
  cat("Overall NLL gain: ", format(x$overall$gain_nll, digits = 6),
    " (required ", format(x$overall$required_gain, digits = 6), ")\n",
    sep = ""
  )
  if (length(x$reasons)) cat("Reasons: ", paste(x$reasons, collapse = "; "), "\n", sep = "")
  invisible(x)
}
