#' Compare M1 and M2 forecasts
#'
#' Computes descriptive, matched-row comparisons for two forecast columns. The
#' primary summaries give every season equal weight: rows are first averaged
#' within season and those season summaries are then averaged. Pooled row
#' summaries are retained for reference. All deltas are M2 minus M1, so a
#' negative delta is better for these loss metrics. This function is forecast
#' only; M1 peak performance must be evaluated separately because M2 cannot
#' estimate peaks.
#'
#' The recommendation is descriptive rather than inferential. `use_m2` is
#' returned only when both forecast losses are no worse than `tolerance` and at
#' least one is strictly lower. No significance test or automatic promotion is
#' performed.
#'
#' When `denominator_col` is supplied, forecast MAE and Bernoulli NLL use the
#' test-volume-weighted form `sum(N * loss) / sum(N)` within each reported
#' group. Equal-season aggregates then average those season-level weighted
#' losses. The NLL is the cross-entropy loss for the supplied proportion and
#' prediction; no binomial-coefficient constant is included.
#'
#' @param forecasts Data frame with one row per season, origin, target, and
#'   horizon, and columns for the observed proportion and both predictions.
#' @param denominator_col Optional character scalar column name in `forecasts`
#'   containing positive test volumes. When supplied, matched forecast rows
#'   are weighted by this denominator; missing denominators are excluded.
#'   `outcome_col` remains a proportion in [0, 1], not a success count.
#' @param outcome_col,m1_col,m2_col Character scalar column names in
#'   `forecasts` for the observed proportion and M1 and M2 predictions.
#' @param season_col,origin_col,target_col,horizon_col Character scalar column
#'   names in `forecasts` defining the unique forecast key.
#' @param tolerance Non-negative finite scalar maximum tolerated increase in
#'   any loss, on the same scale as the corresponding loss.
#'
#' @return A named list with `forecast` and `recommendation` entries.
#'   Forecast entries contain matched counts, exclusions, transparent loss
#'   rows, equal-season and pooled summaries, and per-season summaries.
#'   The recommendation contains `decision`, machine-readable `reasons`, and
#'   the applied tolerance.
#' @export
compare_m1_m2 <- function(
  forecasts,
  outcome_col,
  m1_col,
  m2_col,
  season_col,
  origin_col,
  target_col,
  horizon_col,
  tolerance = 0,
  denominator_col = NULL
) {
  tolerance <- .compare_m1_m2_validate_tolerance(tolerance)
  forecasts <- .compare_m1_m2_as_data_frame(forecasts, "forecasts")

  forecast_cols <- c(
    outcome = outcome_col, m1 = m1_col, m2 = m2_col,
    season = season_col, origin = origin_col, target = target_col,
    horizon = horizon_col
  )
  forecast_cols <- .compare_m1_m2_validate_mappings(
    forecast_cols, forecasts, "forecasts"
  )
  .compare_m1_m2_validate_key(forecasts, forecast_cols)
  .compare_m1_m2_validate_horizon(forecasts[[forecast_cols[["horizon"]]]])
  .compare_m1_m2_validate_probability(
    forecasts[[forecast_cols[["outcome"]]]], "outcome"
  )
  .compare_m1_m2_validate_probability(
    forecasts[[forecast_cols[["m1"]]]], "M1 prediction"
  )
  .compare_m1_m2_validate_probability(
    forecasts[[forecast_cols[["m2"]]]], "M2 prediction"
  )
  denominator <- .compare_m1_m2_validate_denominator(
    denominator_col, forecasts
  )

  forecast_frame <- data.frame(
    season = forecasts[[forecast_cols[["season"]]]],
    origin = forecasts[[forecast_cols[["origin"]]]],
    target = forecasts[[forecast_cols[["target"]]]],
    horizon = as.numeric(forecasts[[forecast_cols[["horizon"]]]]),
    outcome = as.numeric(forecasts[[forecast_cols[["outcome"]]]]),
    m1_prediction = as.numeric(forecasts[[forecast_cols[["m1"]]]]),
    m2_prediction = as.numeric(forecasts[[forecast_cols[["m2"]]]]),
    denominator = denominator,
    stringsAsFactors = FALSE
  )
  forecast_matched <- with(
    forecast_frame,
    !is.na(outcome) & !is.na(m1_prediction) & !is.na(m2_prediction) &
      !is.na(denominator)
  )
  if (!any(forecast_matched)) {
    stop("No matched forecast rows remain after excluding missing values.")
  }
  forecast_losses <- forecast_frame[forecast_matched, , drop = FALSE]
  forecast_losses$m1_mae <- abs(
    forecast_losses$m1_prediction - forecast_losses$outcome
  )
  forecast_losses$m2_mae <- abs(
    forecast_losses$m2_prediction - forecast_losses$outcome
  )
  forecast_losses$m1_nll <- .compare_m1_m2_nll(
    forecast_losses$outcome, forecast_losses$m1_prediction
  )
  forecast_losses$m2_nll <- .compare_m1_m2_nll(
    forecast_losses$outcome, forecast_losses$m2_prediction
  )
  forecast_losses$delta_mae <- .compare_m1_m2_delta(
    forecast_losses$m1_mae, forecast_losses$m2_mae
  )
  forecast_losses$delta_nll <- .compare_m1_m2_delta(
    forecast_losses$m1_nll, forecast_losses$m2_nll
  )
  forecast_summary <- .compare_m1_m2_summaries(
    forecast_losses,
    group_col = "horizon", tolerance = tolerance,
    weighting = if (is.null(denominator_col)) "row" else "denominator"
  )
  forecast_by_season <- .compare_m1_m2_summary_table(
    forecast_losses,
    group_col = "season", tolerance = tolerance,
    weighting = if (is.null(denominator_col)) "row" else "denominator"
  )
  forecast_accounting <- .compare_m1_m2_accounting(
    forecast_frame, forecast_matched,
    c("outcome", "m1_prediction", "m2_prediction", "denominator")
  )
  forecast <- list(
    input_rows = nrow(forecast_frame),
    matched_rows = nrow(forecast_losses),
    excluded_rows = sum(!forecast_matched),
    exclusions = forecast_accounting$exclusions,
    row_accounting = forecast_accounting,
    matched = forecast_losses,
    weighting = if (is.null(denominator_col)) "row" else "denominator",
    total_denominator = sum(forecast_losses$denominator),
    overall = forecast_summary$overall,
    by_horizon = forecast_summary$by_group_equal_season,
    by_horizon_pooled = forecast_summary$by_group,
    by_season = forecast_by_season
  )

  recommendation <- .compare_m1_m2_recommendation(forecast, tolerance)
  structure(
    list(forecast = forecast, recommendation = recommendation),
    class = c("page_m1_m2_comparison", "list")
  )
}

.compare_m1_m2_as_data_frame <- function(x, label) {
  if (!is.data.frame(x)) stop("`", label, "` must be a data frame.")
  if (!nrow(x)) stop("`", label, "` must contain at least one row.")
  x
}

.compare_m1_m2_validate_tolerance <- function(x) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) || x < 0) {
    stop("`tolerance` must be one finite non-negative number.")
  }
  as.numeric(x)
}

.compare_m1_m2_validate_mappings <- function(mappings, data, label) {
  for (mapping in mappings) {
    if (!is.character(mapping) || length(mapping) != 1L ||
      is.na(mapping) || !nzchar(mapping)) {
      stop("Every column mapping for `", label, "` must be a non-empty character scalar.")
    }
  }
  missing <- unname(mappings)[!unname(mappings) %in% names(data)]
  if (length(missing)) {
    stop("Column `", missing[[1L]], "` is absent from `", label, "`.")
  }
  mappings
}

.compare_m1_m2_validate_key <- function(data, cols) {
  key <- unname(cols[c("season", "origin", "target", "horizon")])
  if (any(vapply(data[key], anyNA, logical(1)))) {
    stop("Forecast key columns must not contain missing values.")
  }
  if (any(duplicated(data[key]))) {
    stop("`forecasts` contains duplicate forecast keys.")
  }
  if (anyNA(data[[cols[["season"]]]]) || anyNA(data[[cols[["origin"]]]])) {
    stop("Forecast grouping columns must not contain missing values.")
  }
}

.compare_m1_m2_validate_horizon <- function(x) {
  if (!is.numeric(x) || any(!is.finite(x)) || any(x <= 0) || any(x != floor(x))) {
    stop("`horizon` must contain finite positive integer values.")
  }
}

.compare_m1_m2_validate_probability <- function(x, label) {
  if (!is.numeric(x)) stop("The `", label, "` column must be numeric.")
  bad_finite <- !is.na(x) & !is.finite(x)
  if (any(bad_finite)) stop("The `", label, "` column must contain finite values.")
  bad_probability <- !is.na(x) & (x < 0 | x > 1)
  if (any(bad_probability)) {
    stop("The `", label, "` column contains probabilities outside [0, 1].")
  }
}

.compare_m1_m2_validate_denominator <- function(column, data) {
  if (is.null(column)) {
    return(rep(1, nrow(data)))
  }
  if (!is.character(column) || length(column) != 1L || is.na(column) || !nzchar(column)) {
    stop("`denominator_col` must be NULL or a non-empty character scalar.")
  }
  if (!column %in% names(data)) {
    stop("Column `", column, "` is absent from `forecasts`.")
  }
  value <- data[[column]]
  if (!is.numeric(value)) stop("The `denominator_col` column must be numeric.")
  invalid <- !is.na(value) & (!is.finite(value) | value <= 0)
  if (any(invalid)) {
    stop("The `denominator_col` column must contain finite positive values.")
  }
  as.numeric(value)
}

.compare_m1_m2_nll <- function(outcome, prediction) {
  result <- numeric(length(outcome))
  zero <- prediction == 0
  one <- prediction == 1
  interior <- !(zero | one)
  result[zero] <- ifelse(outcome[zero] == 0, 0, Inf)
  result[one] <- ifelse(outcome[one] == 1, 0, Inf)
  result[interior] <- -(
    outcome[interior] * log(prediction[interior]) +
      (1 - outcome[interior]) * log1p(-prediction[interior])
  )
  result
}

.compare_m1_m2_delta <- function(m1, m2) {
  result <- rep(NA_real_, length(m1))
  both_inf <- is.infinite(m1) & is.infinite(m2) & sign(m1) == sign(m2)
  result[both_inf] <- 0
  finite_difference <- is.finite(m1) & is.finite(m2)
  result[finite_difference] <- m2[finite_difference] - m1[finite_difference]
  result[is.finite(m1) & is.infinite(m2)] <- sign(m2[is.finite(m1) & is.infinite(m2)]) * Inf
  result[is.infinite(m1) & is.finite(m2)] <- -sign(m1[is.infinite(m1) & is.finite(m2)]) * Inf
  result
}

.compare_m1_m2_summary_row <- function(data, group_value = NULL, weighting = "row") {
  weights <- if (weighting == "denominator") data$denominator else rep(1, nrow(data))
  weighted_mean <- function(x) sum(weights * x) / sum(weights)
  m1_mae <- weighted_mean(data$m1_mae)
  m2_mae <- weighted_mean(data$m2_mae)
  m1_nll <- weighted_mean(data$m1_nll)
  m2_nll <- weighted_mean(data$m2_nll)
  delta_mae <- .compare_m1_m2_delta(m1_mae, m2_mae)
  delta_nll <- .compare_m1_m2_delta(m1_nll, m2_nll)
  result <- data.frame(
    n_rows = as.integer(nrow(data)),
    n_seasons = as.integer(length(unique(data$season))),
    total_denominator = sum(weights),
    m1_mae = m1_mae, m2_mae = m2_mae, delta_mae = delta_mae,
    m1_nll = m1_nll, m2_nll = m2_nll, delta_nll = delta_nll,
    stringsAsFactors = FALSE
  )
  if (!is.null(group_value)) {
    result <- cbind(
      data.frame(group = group_value, stringsAsFactors = FALSE), result
    )
  }
  result
}

.compare_m1_m2_summary_table <- function(data, group_col, tolerance, weighting = "row") {
  values <- unique(data[[group_col]])
  values <- values[order(values)]
  rows <- lapply(values, function(value) {
    .compare_m1_m2_summary_row(
      data[data[[group_col]] == value, , drop = FALSE], value, weighting
    )
  })
  result <- do.call(rbind, rows)
  names(result)[[1L]] <- group_col
  result$m2_loses_mae <- result$delta_mae > tolerance
  result$m2_loses_nll <- result$delta_nll > tolerance
  result$m2_loses_any <- result$m2_loses_mae | result$m2_loses_nll
  rownames(result) <- NULL
  result
}

.compare_m1_m2_equal_season <- function(data, tolerance, weighting = "row") {
  seasons <- .compare_m1_m2_summary_table(data, "season", tolerance, weighting)
  result <- data.frame(
    n_rows = as.integer(nrow(data)), n_seasons = as.integer(nrow(seasons)),
    total_denominator = sum(seasons$total_denominator),
    m1_mae = mean(seasons$m1_mae), m2_mae = mean(seasons$m2_mae),
    delta_mae = .compare_m1_m2_delta(mean(seasons$m1_mae), mean(seasons$m2_mae)),
    m1_nll = mean(seasons$m1_nll), m2_nll = mean(seasons$m2_nll),
    delta_nll = .compare_m1_m2_delta(mean(seasons$m1_nll), mean(seasons$m2_nll)),
    n_seasons_lost_mae = sum(seasons$m2_loses_mae),
    n_seasons_lost_nll = sum(seasons$m2_loses_nll),
    stringsAsFactors = FALSE
  )
  result
}

.compare_m1_m2_summaries <- function(data, group_col, tolerance, weighting = "row") {
  pooled <- .compare_m1_m2_summary_row(data, weighting = weighting)
  pooled$n_seasons_lost_mae <- sum(
    .compare_m1_m2_summary_table(data, "season", tolerance, weighting)$m2_loses_mae
  )
  pooled$n_seasons_lost_nll <- sum(
    .compare_m1_m2_summary_table(data, "season", tolerance, weighting)$m2_loses_nll
  )
  by_group <- .compare_m1_m2_summary_table(data, group_col, tolerance, weighting)
  by_group_equal <- lapply(split(data, data[[group_col]], drop = TRUE), function(x) {
    .compare_m1_m2_equal_season(x, tolerance, weighting)
  })
  equal_group <- do.call(rbind, by_group_equal)
  equal_group[[group_col]] <- rownames(equal_group)
  equal_group <- equal_group[, c(group_col, setdiff(names(equal_group), group_col)), drop = FALSE]
  rownames(equal_group) <- NULL
  list(
    overall = list(
      equal_season = .compare_m1_m2_equal_season(data, tolerance, weighting),
      pooled = pooled
    ),
    by_group = by_group,
    by_group_equal_season = equal_group
  )
}

.compare_m1_m2_accounting <- function(data, matched, fields) {
  excluded <- !matched
  reasons <- rep("matched", nrow(data))
  for (i in seq_len(nrow(data))) {
    missing <- fields[is.na(data[i, fields, drop = TRUE])]
    if (length(missing)) reasons[[i]] <- paste(missing, collapse = "+")
  }
  counts <- table(reasons[excluded])
  exclusions <- data.frame(
    reason = names(counts), rows = as.integer(counts), stringsAsFactors = FALSE
  )
  list(
    input_rows = as.integer(nrow(data)), matched_rows = as.integer(sum(matched)),
    excluded_rows = as.integer(sum(excluded)), exclusions = exclusions,
    total_denominator = sum(data$denominator[matched])
  )
}

.compare_m1_m2_recommendation <- function(forecast, tolerance) {
  deltas <- c(
    forecast_mae = forecast$overall$equal_season$delta_mae,
    forecast_nll = forecast$overall$equal_season$delta_nll
  )
  reasons <- character()
  unknown <- character()
  forecast_failures <- names(deltas)[
    (is.finite(deltas) & deltas > tolerance) |
      (is.infinite(deltas) & deltas > 0)
  ]
  if (is.na(deltas[["forecast_mae"]])) unknown <- c(unknown, "forecast_mae")
  if (is.na(deltas[["forecast_nll"]])) unknown <- c(unknown, "forecast_nll")
  if (length(forecast_failures)) {
    reasons <- c(
      reasons,
      paste0(
        "forecast_m2_exceeds_tolerance_",
        sub("^forecast_", "", forecast_failures)
      )
    )
  }
  if (length(unknown)) reasons <- c(reasons, "incomplete_requested_metrics")
  strict_improvement <- any(deltas < 0, na.rm = TRUE)
  if (!length(reasons) && !length(unknown) && strict_improvement) {
    decision <- "use_m2"
    reasons <- "forecast_within_tolerance"
  } else if (length(forecast_failures) ||
    any(grepl("exceeds_tolerance", reasons, fixed = TRUE))) {
    decision <- "keep_m1"
  } else {
    decision <- "insufficient_evidence"
    if (!length(reasons)) reasons <- "no_strict_improvement"
  }
  list(
    decision = decision, reasons = unique(reasons), tolerance = tolerance,
    deltas = deltas, rule = paste(
      "use_m2 requires forecast MAE and NLL deltas <= tolerance and one strict improvement"
    )
  )
}
