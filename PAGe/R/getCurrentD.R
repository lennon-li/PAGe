.pho_orvt_default_url <- function() {
  paste0(
    "https://ws1.publichealthontario.ca/appdata/powerbi/ORVT/",
    "ORVT_Lab_Testing_Data_2024-25_2025-26.csv"
  )
}

#' Fetch and tidy current-season PHO respiratory surveillance data
#'
#' Downloads (or reads a local copy of) the Public Health Ontario lab-testing
#' CSV, filters to one virus and the requested season plus its predecessor,
#' aggregates weekly totals across all PHUs, and returns a tidy data frame
#' ready for the M0/M1/M2 pipeline.
#'
#' @param data URL or local file path to the PHO lab-testing CSV. Defaults to
#'   the current PHO 2024-25 / 2025-26 ORVT feed.
#' @param startWeek Integer MMWR week used as the epidemic-year origin for
#'   computing \code{weekF} (default 27L, early July).
#' @param lastWeek Integer or \code{NA}. When non-\code{NA}, rows with MMWR
#'   \code{week > lastWeek} are dropped before returning.
#' @param virus Character string matching the \code{Virus} column of the CSV
#'   (default \code{"Influenza A"}).
#' @param season Character season identifier in \code{"YYYY-YY"} format
#'   (default \code{"2025-26"}).
#'
#' @return A data frame with one row per MMWR week containing: \code{season},
#'   \code{week}, \code{N} (total tests), \code{y} (positives), \code{neg},
#'   \code{p} (positivity), \code{weekS}, \code{weekF}, \code{cYear},
#'   \code{newWeek}, and \code{date}.
#' @export
getCurrentD <- function(data = NULL,
                        startWeek = 27L,
                        lastWeek = NA_integer_,
                        virus = "Influenza A",
                        season = "2025-26") {
  if (is.null(data)) data <- .pho_orvt_default_url()
  if (!is.character(data) || length(data) != 1L || is.na(data) ||
    !nzchar(trimws(data))) {
    stop("`data` must be one non-empty local path or URL.", call. = FALSE)
  }
  if (!is.character(season) || length(season) != 1L || is.na(season) ||
    !grepl("^[0-9]{4}-[0-9]{2}$", season)) {
    stop(
      "`season` must have the form `YYYY-YY` (for example, `2025-26`).",
      call. = FALSE
    )
  }
  if (!is.character(virus) || length(virus) != 1L || is.na(virus) ||
    !nzchar(trimws(virus))) {
    stop("`virus` must be one non-empty character value.", call. = FALSE)
  }
  if (!is.numeric(startWeek) || length(startWeek) != 1L ||
    !is.finite(startWeek) || startWeek != as.integer(startWeek) ||
    startWeek < 1L || startWeek > 53L) {
    stop("`startWeek` must be one integer in [1, 53].", call. = FALSE)
  }
  if (!is.numeric(lastWeek) || length(lastWeek) != 1L ||
    (!is.na(lastWeek) && (!is.finite(lastWeek) ||
      lastWeek != as.integer(lastWeek) || lastWeek < 1L || lastWeek > 53L))) {
    stop("`lastWeek` must be NA or one integer in [1, 53].", call. = FALSE)
  }

  raw <- tryCatch(
    utils::read.csv(data, check.names = TRUE),
    error = function(error) {
      stop(
        "Could not read PHO surveillance source `", data, "`: ",
        conditionMessage(error),
        call. = FALSE
      )
    }
  )
  required <- c(
    "Surveillance.week", "Surveillance.period", "Total...of.tests",
    "X..of.positive.tests", "Virus"
  )
  missing <- setdiff(required, names(raw))
  if (length(missing)) {
    stop(
      "PHO surveillance source is missing required column(s): ",
      paste(missing, collapse = ", "), ".",
      call. = FALSE
    )
  }

  currentD <- raw |>
    dplyr::transmute(
      week = suppressWarnings(as.numeric(.data$Surveillance.week)),
      season = as.character(.data$Surveillance.period),
      N = suppressWarnings(as.numeric(.data$Total...of.tests)),
      y = suppressWarnings(as.numeric(.data$X..of.positive.tests)),
      Virus = as.character(.data$Virus)
    )
  if (any(!is.finite(currentD$week)) ||
    any(currentD$week != round(currentD$week))) {
    stop(
      "PHO `Surveillance.week` must contain finite whole numbers.",
      call. = FALSE
    )
  }
  if (any(!is.finite(currentD$N)) || any(!is.finite(currentD$y)) ||
    any(currentD$N < 0) || any(currentD$y < 0) ||
    any(currentD$y > currentD$N)) {
    stop(
      "PHO test counts must be finite, non-negative, and satisfy y <= N.",
      call. = FALSE
    )
  }
  startWeek <- as.integer(startWeek)

  n_weeks_in_start_year <- function(start_year) {
    52L + as.integer(
      MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L
    )
  }

  years <- strsplit(season, "-", fixed = TRUE)[[1L]]
  start_year <- as.integer(years[1L]) - 1L
  end_year <- as.integer(paste0(substr(years[1L], 1L, 2L), years[2L])) - 1L
  prev_season <- paste0(start_year, "-", substr(end_year, 3L, 4L))
  date <- sprintf("%d-06-23", end_year)

  matched <- currentD |>
    dplyr::filter(
      .data$Virus == .env$virus,
      .data$season %in% c(.env$season, prev_season)
    )
  if (!nrow(matched)) {
    stop(
      "PHO source has no rows for virus `", virus, "` in season `", season,
      "` or its predecessor.",
      call. = FALSE
    )
  }

  currentD <- matched |>
    dplyr::group_by(.data$season, .data$week) |>
    dplyr::summarise(
      N = sum(.data$N), y = sum(.data$y), .groups = "drop"
    ) |>
    dplyr::group_by(.data$season) |>
    dplyr::mutate(
      neg = .data$N - .data$y,
      p = dplyr::if_else(.data$N > 0, .data$y / .data$N, NA_real_),
      start_year = as.integer(substr(.data$season, 1L, 4L)),
      mmwr_year = ifelse(
        .data$week >= 35L, .data$start_year, .data$start_year + 1L
      ),
      Rdate = MMWRweek2Date(.data$mmwr_year, .data$week, 1L),
      nW_true = n_weeks_in_start_year(.data$start_year),
      weekS = ((.data$week - 35L) %% .data$nW_true) + 1L,
      weekF = ((.data$week - startWeek) %% .data$nW_true) + 1L,
      cYear = as.factor(format(.data$Rdate, "%Y")),
      newWeek = .data$weekF
    ) |>
    dplyr::ungroup() |>
    dplyr::arrange(.data$season, .data$weekS, .data$Rdate) |>
    dplyr::filter(.data$Rdate > date) |>
    dplyr::rename(date = Rdate)

  if (!is.na(lastWeek)) {
    currentD <- currentD |> dplyr::filter(.data$week <= lastWeek)
  }

  currentD
}
