#' Create a continuous season timing calendar
#'
#' The opt-in timing-v2 API represents week \code{w} by the half-open interval
#' \code{[w, w + 1)}. Thus, \code{19.2} means 20 percent of the way from the
#' start of observed week 19 to the start of observed week 20. Observed
#' \code{weekF} values remain integer week identifiers. Calendar dates are
#' optional, but must be supplied when converting between dates and timing
#' coordinates.
#'
#' @param season Optional season identifier.
#' @param n_weeks Number of weeks in the season. Both 52 and 53 week seasons
#'   are supported. When omitted, the length of \code{week_starts} is used;
#'   undated calendars default to 52 weeks.
#' @param week_starts Optional \code{Date} vector of week start dates.
#' @param week_ends Optional \code{Date} vector of exclusive week end dates.
#'   When omitted, each end is the next start date and the final end is seven
#'   days after the final start.
#'
#' @return An object of class \code{page_timing_calendar_v2} containing the
#'   season calendar and the documented continuous coordinate convention.
#' @keywords internal
new_timing_calendar <- function(season = NULL, n_weeks = NULL,
                                week_starts = NULL, week_ends = NULL) {
  if (is.null(n_weeks)) {
    n_weeks <- if (is.null(week_starts)) 52L else length(week_starts)
  }
  n_weeks <- .timing_check_n_weeks(n_weeks)

  if (!is.null(season)) {
    if (length(season) != 1L || is.na(season) || !nzchar(trimws(as.character(season)))) {
      stop("`season` must be one non-empty identifier.", call. = FALSE)
    }
    season <- trimws(as.character(season))
  }

  if (is.null(week_starts) && !is.null(week_ends)) {
    stop("`week_starts` is required when `week_ends` is supplied.", call. = FALSE)
  }
  if (!is.null(week_starts)) {
    week_starts <- .timing_as_date(week_starts, "week_starts")
    if (length(week_starts) != n_weeks) {
      stop("`week_starts` must contain one date per calendar week.", call. = FALSE)
    }
    if (any(diff(week_starts) <= 0)) {
      stop("`week_starts` must be strictly increasing.", call. = FALSE)
    }

    if (is.null(week_ends)) {
      week_ends <- c(week_starts[-1L], week_starts[n_weeks] + 7)
    } else {
      week_ends <- .timing_as_date(week_ends, "week_ends")
      if (length(week_ends) != n_weeks) {
        stop("`week_ends` must contain one date per calendar week.", call. = FALSE)
      }
    }
    if (any(week_ends <= week_starts)) {
      stop("Each `week_ends` date must be after its corresponding start.", call. = FALSE)
    }
    if (any(week_ends[-n_weeks] != week_starts[-1L])) {
      stop("Calendar week intervals must be contiguous.", call. = FALSE)
    }
  }

  week_table <- data.frame(
    weekF = seq_len(n_weeks),
    start_date = if (is.null(week_starts)) as.Date(rep(NA_character_, n_weeks)) else week_starts,
    end_date = if (is.null(week_starts)) as.Date(rep(NA_character_, n_weeks)) else week_ends,
    stringsAsFactors = FALSE
  )
  week_table$midpoint_date <- if (is.null(week_starts)) {
    as.Date(rep(NA_character_, n_weeks))
  } else {
    week_table$start_date + floor(as.numeric(week_table$end_date - week_table$start_date) / 2)
  }

  structure(
    list(
      season = season,
      n_weeks = n_weeks,
      week_table = week_table,
      coordinate_convention = "week w is [w, w + 1); dates use actual week boundaries",
      observed_week_type = "integer weekF",
      calendar_id = paste0("timing-v2-", n_weeks, "-week")
    ),
    class = "page_timing_calendar_v2"
  )
}

#' Validate a timing-v2 calendar
#'
#' @param calendar A \code{page_timing_calendar_v2} object.
#' @return The validated calendar, invisibly.
#' @keywords internal
validate_timing_calendar <- function(calendar) {
  if (!inherits(calendar, "page_timing_calendar_v2")) {
    stop("`calendar` must be created by `new_timing_calendar()`.", call. = FALSE)
  }
  .timing_check_n_weeks(calendar$n_weeks)
  required <- c("weekF", "start_date", "end_date", "midpoint_date")
  if (!is.data.frame(calendar$week_table) ||
    !all(required %in% names(calendar$week_table)) ||
    nrow(calendar$week_table) != calendar$n_weeks) {
    stop("`calendar$week_table` does not match `calendar$n_weeks`.", call. = FALSE)
  }
  if (!identical(as.integer(calendar$week_table$weekF), seq_len(calendar$n_weeks))) {
    stop("Calendar `weekF` values must be consecutive integers starting at 1.", call. = FALSE)
  }
  if (!inherits(calendar$week_table$start_date, "Date") ||
    !inherits(calendar$week_table$end_date, "Date") ||
    !inherits(calendar$week_table$midpoint_date, "Date")) {
    stop("Calendar date columns must be Date vectors.", call. = FALSE)
  }
  starts_missing <- is.na(calendar$week_table$start_date)
  ends_missing <- is.na(calendar$week_table$end_date)
  if (any(starts_missing != ends_missing) ||
    (any(starts_missing) && !all(starts_missing))) {
    stop("Calendar dates must be either complete or entirely missing.", call. = FALSE)
  }
  if (any(starts_missing)) {
    if (!all(is.na(calendar$week_table$midpoint_date))) {
      stop("Undated calendars must have missing midpoint dates.", call. = FALSE)
    }
  } else {
    starts <- calendar$week_table$start_date
    ends <- calendar$week_table$end_date
    if (any(diff(starts) <= 0) || any(ends <= starts) ||
      any(ends[-calendar$n_weeks] != starts[-1L])) {
      stop("Calendar date intervals must be increasing, valid, and contiguous.", call. = FALSE)
    }
    if (anyNA(calendar$week_table$midpoint_date)) {
      stop("Dated calendars must have complete midpoint dates.", call. = FALSE)
    }
    expected_midpoints <- starts + floor(as.numeric(ends - starts) / 2)
    if (any(calendar$week_table$midpoint_date != expected_midpoints)) {
      stop("Calendar midpoint dates do not match the supplied intervals.", call. = FALSE)
    }
  }
  invisible(calendar)
}

#' Convert dates to continuous season timing coordinates
#'
#' @param calendar A \code{page_timing_calendar_v2} object with dates.
#' @param dates Dates to convert.
#' @param allow_na Whether missing dates should return missing coordinates.
#' @return Numeric timing coordinates.
#' @keywords internal
date_to_timing <- function(calendar, dates, allow_na = TRUE) {
  validate_timing_calendar(calendar)
  dates <- .timing_as_date(dates, "dates", allow_na = allow_na)
  if (all(is.na(calendar$week_table$start_date))) {
    stop("This calendar has no dates; supply `week_starts` for date mapping.", call. = FALSE)
  }

  result <- rep(NA_real_, length(dates))
  observed <- !is.na(dates)
  starts <- calendar$week_table$start_date
  ends <- calendar$week_table$end_date
  candidate <- findInterval(dates[observed], starts)
  candidate <- pmin(candidate, calendar$n_weeks)
  valid <- candidate >= 1L & dates[observed] < ends[pmax(candidate, 1L)]
  if (any(!valid)) {
    bad <- dates[observed][which(!valid)[1L]]
    stop("Date ", format(bad), " is outside the supplied season calendar.", call. = FALSE)
  }
  observed_indices <- which(observed)
  weeks <- candidate[valid]
  valid_indices <- observed_indices[valid]
  spans <- as.numeric(ends[weeks] - starts[weeks])
  result[valid_indices] <- weeks +
    as.numeric(dates[valid_indices] - starts[weeks]) / spans
  result
}

#' Convert continuous timing coordinates to observed integer weeks
#'
#' @param calendar A \code{page_timing_calendar_v2} object.
#' @param timing Numeric coordinates in the season.
#' @param allow_na Whether missing coordinates should return missing weeks.
#' @return Integer observed \code{weekF} values.
#' @keywords internal
timing_to_week <- function(calendar, timing, allow_na = TRUE) {
  validate_timing_calendar(calendar)
  timing <- .timing_as_numeric(timing, "timing", allow_na = allow_na)
  invalid <- !is.na(timing) & (timing < 1 | timing >= calendar$n_weeks + 1)
  if (any(invalid)) {
    stop("`timing` must lie in [1, n_weeks + 1).", call. = FALSE)
  }
  as.integer(floor(timing))
}

#' Convert continuous timing coordinates to dates
#'
#' @param calendar A dated \code{page_timing_calendar_v2} object.
#' @param timing Numeric coordinates in the season.
#' @param allow_na Whether missing coordinates should return missing dates.
#' @return Dates obtained by linear interpolation within the calendar week.
#' @keywords internal
timing_to_date <- function(calendar, timing, allow_na = TRUE) {
  validate_timing_calendar(calendar)
  timing <- .timing_as_numeric(timing, "timing", allow_na = allow_na)
  if (all(is.na(calendar$week_table$start_date))) {
    stop("This calendar has no dates; supply `week_starts` for date mapping.", call. = FALSE)
  }
  weeks <- timing_to_week(calendar, timing, allow_na = allow_na)
  result <- as.Date(rep(NA_character_, length(timing)))
  observed <- !is.na(timing)
  if (any(observed)) {
    starts <- calendar$week_table$start_date[weeks[observed]]
    ends <- calendar$week_table$end_date[weeks[observed]]
    result[observed] <- starts +
      (timing[observed] - weeks[observed]) * as.numeric(ends - starts)
  }
  result
}

.timing_check_n_weeks <- function(n_weeks) {
  if (length(n_weeks) != 1L || is.logical(n_weeks) || !is.numeric(n_weeks) ||
    !is.finite(n_weeks) || n_weeks != floor(n_weeks) ||
    n_weeks < 2L || n_weeks > .Machine$integer.max) {
    stop("`n_weeks` must be one integer of at least 2.", call. = FALSE)
  }
  as.integer(n_weeks)
}

.timing_as_date <- function(x, name, allow_na = FALSE) {
  if (inherits(x, "POSIXt")) x <- as.Date(x)
  if (!inherits(x, "Date")) {
    stop("`", name, "` must be a Date vector.", call. = FALSE)
  }
  if (!allow_na && anyNA(x)) stop("`", name, "` cannot contain missing dates.", call. = FALSE)
  x
}

.timing_as_numeric <- function(x, name, allow_na = FALSE) {
  if (is.logical(x) || !is.numeric(x)) {
    stop("`", name, "` must be numeric.", call. = FALSE)
  }
  if (!allow_na && anyNA(x)) stop("`", name, "` cannot contain missing values.", call. = FALSE)
  if (any(!is.na(x) & !is.finite(x))) stop("`", name, "` must contain finite values.", call. = FALSE)
  as.numeric(x)
}
