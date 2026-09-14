#' Prepare arbitrary surveillance data for the PAGe pipeline
#'
#' Converts a user-supplied weekly data frame with source-specific column names
#' to the canonical surveillance contract used by PAGe. This function does not
#' fetch, filter, or aggregate observations; the input must already contain
#' exactly one row per season and week.
#'
#' The outcome is the positive-count column, not a percentage. Supply either a
#' total-count column, a negative-count column, or both. When calendar/MMWR
#' weeks are supplied, \code{weekF} is computed from \code{start_week} and a
#' season start year. The start year is read from \code{start_year_col}, or is
#' inferred from season labels of the form \code{YYYY-YY}.
#'
#' @param data A data frame containing weekly observations.
#' @param outcome_col Character scalar naming the positive-count column.
#' @param week_col Character scalar naming the week column. With
#'   \code{week_type = "within_season"}, values are already PAGe week indices.
#' @param season_col Character scalar naming the season identifier column.
#' @param total_col Optional character scalar naming the total-observation
#'   column. At least one of \code{total_col} and \code{negative_col} is
#'   required.
#' @param negative_col Optional character scalar naming the negative-count
#'   column. At least one of \code{total_col} and \code{negative_col} is
#'   required.
#' @param positivity_col Optional character scalar naming a supplied positivity
#'   column. If supplied, it is checked against the counts.
#' @param week_type Week representation: \code{"within_season"} for an
#'   existing PAGe-style week index, or \code{"mmwr"} for calendar/MMWR week
#'   numbers that must be converted using \code{start_week}.
#' @param start_week Integer MMWR week used as the season origin when
#'   \code{week_type = "mmwr"}; defaults to 27.
#' @param start_year_col Optional character scalar naming the season start-year
#'   column. Required for non-YYYY-YY season labels when \code{week_type =
#'   "mmwr"}.
#' @param tolerance Numeric tolerance passed to
#'   \code{\link{prepare_surveillance_data}} for consistency checks.
#'
#' @return A data frame with canonical columns \code{season}, \code{weekF},
#'   \code{y}, \code{N}, \code{p}, and \code{neg}, followed by unmapped source
#'   columns. The result can be passed directly to \code{train_pipeline()} or
#'   the stage APIs.
#' @export
prepare_page_data <- function(data,
                              outcome_col,
                              week_col,
                              season_col,
                              total_col = NULL,
                              negative_col = NULL,
                              positivity_col = NULL,
                              week_type = c("within_season", "mmwr"),
                              start_week = 27L,
                              start_year_col = NULL,
                              tolerance = 1e-8) {
  if (!is.data.frame(data)) {
    stop("`data` must be a data frame.", call. = FALSE)
  }
  week_type <- match.arg(week_type)

  column_args <- list(
    outcome_col = outcome_col,
    week_col = week_col,
    season_col = season_col,
    total_col = total_col,
    negative_col = negative_col,
    positivity_col = positivity_col,
    start_year_col = start_year_col
  )
  for (arg in names(column_args)) {
    value <- column_args[[arg]]
    if (is.null(value)) next
    if (length(value) != 1L || is.na(value) || !is.character(value) ||
      !nzchar(trimws(value))) {
      stop("`", arg, "` must be NULL or one non-empty column name.", call. = FALSE)
    }
  }

  required_args <- c("outcome_col", "week_col", "season_col")
  if (any(vapply(column_args[required_args], is.null, logical(1)))) {
    stop("`outcome_col`, `week_col`, and `season_col` are required.", call. = FALSE)
  }
  if (is.null(total_col) && is.null(negative_col)) {
    stop("Supply at least one of `total_col` or `negative_col`.", call. = FALSE)
  }

  mapped <- unlist(column_args, use.names = FALSE)
  if (anyDuplicated(mapped)) {
    stop("Source column mappings must name distinct columns.", call. = FALSE)
  }
  missing <- setdiff(mapped, names(data))
  if (length(missing)) {
    stop(
      "Mapped source column(s) are absent from `data`: ",
      paste(missing, collapse = ", "), ".",
      call. = FALSE
    )
  }

  if (length(start_week) != 1L || !is.numeric(start_week) ||
    is.na(start_week) || !is.finite(start_week) ||
    start_week != as.integer(start_week) || start_week < 1L || start_week > 53L) {
    stop("`start_week` must be one integer in [1, 53].", call. = FALSE)
  }
  start_week <- as.integer(start_week)

  source_values <- function(column, label, allow_na = FALSE) {
    value <- suppressWarnings(as.numeric(as.character(data[[column]])))
    invalid <- if (allow_na) {
      !is.na(data[[column]]) & (!is.finite(value))
    } else {
      !is.finite(value)
    }
    if (any(invalid)) {
      stop(
        "Source column `", column, "` mapped to `", label,
        "` must contain finite numeric values",
        if (allow_na) " or missing values." else ".",
        call. = FALSE
      )
    }
    value
  }

  week <- source_values(week_col, "week")
  if (any(week != round(week))) {
    stop("Mapped `week_col` must contain whole-number week values.", call. = FALSE)
  }
  if (week_type == "mmwr" && any(week < 1 | week > 53)) {
    stop("MMWR weeks mapped by `week_col` must be in [1, 53].", call. = FALSE)
  }

  season <- as.character(data[[season_col]])
  if (anyNA(season) || any(!nzchar(trimws(season)))) {
    stop("Mapped `season_col` must contain non-empty identifiers.", call. = FALSE)
  }

  weekF <- week
  if (week_type == "mmwr") {
    start_year <- NULL
    if (!is.null(start_year_col)) {
      start_year <- source_values(start_year_col, "start_year")
      if (any(start_year != round(start_year))) {
        stop("Mapped `start_year_col` must contain whole-number years.", call. = FALSE)
      }
    } else {
      match_year <- regexec("^([0-9]{4})-[0-9]{2}$", trimws(season))
      pieces <- regmatches(trimws(season), match_year)
      can_infer <- lengths(pieces) == 2L
      if (!all(can_infer)) {
        stop(
          "`week_type = \"mmwr\"` needs `start_year_col` unless every `season_col` ",
          "value has the form `YYYY-YY`.",
          call. = FALSE
        )
      }
      start_year <- vapply(pieces, function(piece) as.numeric(piece[2L]), numeric(1))
    }
    if (any(start_year < 1 | start_year > 9999)) {
      stop("Mapped season start years must be in [1, 9999].", call. = FALSE)
    }
    mmwr_year <- ifelse(week >= start_week, start_year, start_year + 1)
    mmwr_date <- MMWRweek::MMWRweek2Date(mmwr_year, week, 1L)
    mmwr_check <- MMWRweek::MMWRweek(mmwr_date)
    valid_week <- mmwr_check$MMWRyear == mmwr_year &
      mmwr_check$MMWRweek == week
    if (any(!valid_week)) {
      stop(
        "Mapped `week_col` contains an MMWR week that is invalid for the ",
        "calendar year implied by `start_week` and the season start year.",
        call. = FALSE
      )
    }
    n_weeks <- vapply(start_year, n_weeks_in_start_year, integer(1))
    weekF <- ((week - start_week) %% n_weeks) + 1L
  }

  canonical <- data.frame(
    season = season,
    weekF = weekF,
    y = source_values(outcome_col, "y"),
    stringsAsFactors = FALSE
  )
  if (!is.null(total_col)) canonical$N <- source_values(total_col, "N")
  if (!is.null(negative_col)) canonical$neg <- source_values(negative_col, "neg")
  if (!is.null(positivity_col)) canonical$p <- source_values(positivity_col, "p", allow_na = TRUE)

  canonical_names <- c("season", "weekF", "y", "N", "p", "neg")
  extras <- data[, setdiff(names(data), c(mapped, canonical_names)), drop = FALSE]
  out <- cbind(canonical, extras)
  prepare_surveillance_data(out, tolerance = tolerance)
}
