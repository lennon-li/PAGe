#' Derive the PAGe July-start season calendar from surveillance dates
#'
#' The modelling season starts at MMWR week `start_week` (27 by default).
#' The input CSV season label is never consulted when dates or explicit MMWR
#' years are supplied. `weekS` is retained only as the historical PHO-style
#' interpretation coordinate; `weekF` is the chronological July-season index.
#'
#' @param dates Optional vector of week-start dates. Supply this or both
#'   `mmwr_year` and `week`.
#' @param mmwr_year Optional MMWR calendar year for each `week`.
#' @param week Optional MMWR week number for each observation.
#' @param start_week MMWR week at which the PAGe season starts (default 27).
#'
#' @return A data frame with `season`, `start_year`, `week`, `nW_true`,
#'   `weekF`, and `weekS`.
#' @export
page_season_calendar <- function(dates = NULL, mmwr_year = NULL, week = NULL,
                                 start_week = 27L) {
  if (!is.numeric(start_week) || length(start_week) != 1L ||
    !is.finite(start_week) || start_week != as.integer(start_week) ||
    start_week < 1L || start_week > 53L) {
    stop("`start_week` must be one integer in [1, 53].", call. = FALSE)
  }
  start_week <- as.integer(start_week)
  has_dates <- !is.null(dates)
  has_mmwryw <- !is.null(mmwr_year) || !is.null(week)
  if (has_dates && has_mmwryw) {
    stop("Supply `dates` or `mmwr_year`/`week`, not both.", call. = FALSE)
  }
  if (!has_dates && (!has_mmwryw || is.null(mmwr_year) || is.null(week))) {
    stop("Supply `dates` or both `mmwr_year` and `week`.", call. = FALSE)
  }

  if (has_dates) {
    dates <- as.Date(dates)
    if (anyNA(dates)) stop("`dates` must contain valid dates.", call. = FALSE)
    mmwr <- MMWRweek::MMWRweek(dates)
    mmwr_year <- as.integer(mmwr$MMWRyear)
    week <- as.integer(mmwr$MMWRweek)
  } else {
    mmwr_year <- suppressWarnings(as.integer(as.character(mmwr_year)))
    week <- suppressWarnings(as.integer(as.character(week)))
    if (anyNA(mmwr_year) || anyNA(week)) {
      stop("`mmwr_year` and `week` must contain finite whole numbers.", call. = FALSE)
    }
    if (any(mmwr_year < 1L | mmwr_year > 9999L) || any(week < 1L | week > 53L)) {
      stop("MMWR years or weeks are outside their valid ranges.", call. = FALSE)
    }
    check_dates <- as.Date(MMWRweek::MMWRweek2Date(mmwr_year, week, 1L),
      origin = "1970-01-01"
    )
    check <- MMWRweek::MMWRweek(check_dates)
    if (any(as.integer(check$MMWRyear) != mmwr_year |
      as.integer(check$MMWRweek) != week)) {
      stop("`mmwr_year` and `week` contain an invalid MMWR year/week pair.", call. = FALSE)
    }
  }

  start_year <- ifelse(week >= start_week, mmwr_year, mmwr_year - 1L)
  nW_true <- vapply(start_year, function(year) {
    52L + as.integer(MMWRweek::MMWRweek(
      as.Date(paste0(as.integer(year), "-12-31"))
    )$MMWRweek == 53L)
  }, integer(1))
  weekF <- ifelse(
    week >= start_week,
    week - start_week + 1L,
    nW_true - start_week + week + 1L
  )
  weekS <- ((week - 35L) %% nW_true) + 1L
  data.frame(
    season = sprintf("%04d-%02d", start_year, (start_year + 1L) %% 100L),
    start_year = as.integer(start_year), week = as.integer(week),
    nW_true = as.integer(nW_true), weekF = as.integer(weekF),
    weekS = as.integer(weekS), stringsAsFactors = FALSE
  )
}

# Plain alignment shift. This deliberately does not wrap or clamp. Callers
# must exclude/flag values outside their template domain explicitly.
.page_shift_week <- function(weekF, iWeek, anchorWeek) {
  as.numeric(weekF) - as.numeric(iWeek) + as.numeric(anchorWeek)
}

# The declared width of the shared aligned template coordinate used by every
# M1 reference fit. This is NOT a season's calendar length (that is nW_true /
# .season_calendar_weeks()) - it is one fixed constant for the whole package.
.page_template_weeks <- function() {
  52L
}

.page_alignment_domain <- function(newWeek, n_weeks = .page_template_weeks()) {
  in_domain <- is.finite(newWeek) & newWeek >= 1 & newWeek <= as.numeric(n_weeks)
  list(newWeek = newWeek, in_domain = in_domain, out_of_domain = !in_domain)
}

.page_assert_prefix <- function(data, origin, season_col = "season",
                                week_col = "weekF", label = "walk-forward input") {
  if (!is.data.frame(data) || !week_col %in% names(data)) {
    stop(label, " must contain `", week_col, "`.", call. = FALSE)
  }
  origin <- suppressWarnings(as.numeric(origin))
  weeks <- suppressWarnings(as.numeric(data[[week_col]]))
  if (length(origin) != 1L || !is.finite(origin)) {
    stop(label, " origin must be one finite weekF value.", call. = FALSE)
  }
  if (any(is.finite(weeks) & weeks > origin)) {
    stop(label, " contains rows with weekF > origin t=", origin, ".", call. = FALSE)
  }
  invisible(data)
}
