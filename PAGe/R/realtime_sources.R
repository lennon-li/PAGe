# Real-time surveillance source resolution.
#
# Operational forecasting needs one entry point that accepts whatever the
# operator actually has on hand -- the live PHO ORVT feed by default, but also
# a downloaded ORVT CSV, the PAGe historical CSV layout, the daily
# age-stratified .RData extract, or an already-canonical data frame -- and
# returns the same canonical schema with the same provenance record in every
# case. Provenance is not optional here: a forecast is only interpretable
# alongside the exact source it was produced from.

.page_source_kind <- function(source) {
  if (is.null(source)) {
    return("orvt_feed")
  }
  if (is.data.frame(source)) {
    return("data_frame")
  }
  if (!is.character(source) || length(source) != 1L || is.na(source) || !nzchar(source)) {
    stop("`source` must be NULL, a data frame, or one file path.", call. = FALSE)
  }
  lower <- tolower(source)
  if (grepl("\\.(rdata|rda)$", lower)) {
    return("daily_rdata")
  }
  if (grepl("\\.csv$", lower)) {
    if (!file.exists(source)) {
      stop("Surveillance CSV not found: ", source, call. = FALSE)
    }
    header <- tolower(trimws(readLines(source, n = 1L, warn = FALSE)))
    # The PAGe historical layout names its count columns directly; the PHO
    # ORVT export does not, and getCurrentD() handles that layout itself.
    if (grepl("test_flu", header) && grepl("pos_flua", header)) {
      return("page_csv")
    }
    return("orvt_csv")
  }
  stop(
    "Unsupported `source`: expected NULL, a data frame, a .csv, or a .RData/.rda file, got `",
    source, "`.",
    call. = FALSE
  )
}

.page_file_sha256 <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    return(NA_character_)
  }
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

# The daily extract is a named list of per-pathogen tibbles, each one row per
# (date, age group). PAGe models provincial weekly counts, so the daily rows
# are summed across age groups and then across the MMWR week. Partial weeks are
# dropped by default: a 3-day week is not comparable with a 7-day training
# history and would depress positivity for that week.
.page_load_daily_rdata <- function(path, pathogen = "fluA", aggregate_ages = TRUE,
                                   complete_weeks_only = TRUE, start_week = 27L) {
  if (!file.exists(path)) stop("Daily RData file not found: ", path, call. = FALSE)
  if (!requireNamespace("MMWRweek", quietly = TRUE)) {
    stop("Reading the daily RData layout requires the MMWRweek package.", call. = FALSE)
  }
  env <- new.env(parent = emptyenv())
  loaded <- load(path, envir = env)
  holder <- NULL
  for (nm in loaded) {
    candidate <- get(nm, envir = env)
    if (is.list(candidate) && !is.data.frame(candidate) && pathogen %in% names(candidate)) {
      holder <- candidate
      break
    }
  }
  if (is.null(holder)) {
    stop(
      "No object in ", path, " holds a `", pathogen,
      "` element; available objects: ", paste(loaded, collapse = ", "), ".",
      call. = FALSE
    )
  }
  raw <- as.data.frame(holder[[pathogen]], stringsAsFactors = FALSE)
  required <- c("date", "pos", "tests")
  missing_cols <- setdiff(required, names(raw))
  if (length(missing_cols)) {
    stop(
      "Daily `", pathogen, "` table is missing column(s): ",
      paste(missing_cols, collapse = ", "), ".",
      call. = FALSE
    )
  }
  raw$date <- as.Date(raw$date)
  if (anyNA(raw$date)) stop("Daily table contains unparseable dates.", call. = FALSE)
  if (!aggregate_ages && "age." %in% names(raw)) {
    stop(
      "`aggregate_ages = FALSE` is not supported: PAGe models provincial totals, ",
      "so age strata must be summed.",
      call. = FALSE
    )
  }
  per_day <- stats::aggregate(
    cbind(pos, tests) ~ date,
    data = raw[, c("date", "pos", "tests")], FUN = sum
  )
  mw <- MMWRweek::MMWRweek(per_day$date)
  per_day$week_key <- sprintf("%04d-%02d", mw$MMWRyear, mw$MMWRweek)
  weekly <- stats::aggregate(
    cbind(pos, tests) ~ week_key,
    data = per_day, FUN = sum
  )
  counts <- stats::aggregate(date ~ week_key, data = per_day, FUN = length)
  names(counts)[2L] <- "n_days"
  starts <- stats::aggregate(date ~ week_key, data = per_day, FUN = min)
  names(starts)[2L] <- "week_start_date"
  weekly <- merge(merge(weekly, counts, by = "week_key"), starts, by = "week_key")
  weekly <- weekly[order(weekly$week_key), , drop = FALSE]
  dropped_partial <- character(0)
  if (isTRUE(complete_weeks_only)) {
    partial <- weekly$n_days < 7L
    dropped_partial <- weekly$week_key[partial]
    weekly <- weekly[!partial, , drop = FALSE]
  }
  if (!nrow(weekly)) stop("No complete weeks remain in ", path, ".", call. = FALSE)
  calendar <- page_season_calendar(dates = weekly$week_start_date, start_week = start_week)
  out <- data.frame(
    season = calendar$season,
    weekF = calendar$weekF,
    weekS = calendar$weekS,
    week = calendar$week,
    start_year = calendar$start_year,
    y = as.numeric(weekly$pos),
    N = as.numeric(weekly$tests),
    week_start_date = as.Date(weekly$week_start_date),
    week_end_date = as.Date(weekly$week_start_date) + 6L,
    n_days = as.integer(weekly$n_days),
    stringsAsFactors = FALSE
  )
  out$neg <- out$N - out$y
  out$p <- ifelse(out$N > 0, out$y / out$N, NA_real_)
  out$newWeek <- out$weekF
  out$date <- out$week_start_date
  attr(out, "dropped_partial_weeks") <- dropped_partial
  out
}

.page_load_page_csv <- function(path, start_week = 27L) {
  raw <- load_flu_hist(path)
  calendar <- page_season_calendar(
    dates = as.Date(raw$week_start_date), start_week = start_week
  )
  out <- raw
  out$pho_season <- as.character(out$season)
  out$season <- calendar$season
  out$week <- calendar$week
  out$start_year <- calendar$start_year
  out$weekS <- calendar$weekS
  out$weekF <- calendar$weekF
  out$y <- as.numeric(out$pos_flua)
  out$N <- as.numeric(out$test_flu)
  out$neg <- out$N - out$y
  out$p <- ifelse(out$N > 0, out$y / out$N, NA_real_)
  out$newWeek <- out$weekF
  out$date <- as.Date(out$week_start_date)
  out
}

#' Load current-season surveillance data from any supported source
#'
#' Resolves one operational data source into the canonical PAGe surveillance
#' schema and records where it came from. The default is the live PHO ORVT
#' feed; an operator who has a downloaded ORVT CSV, the PAGe historical CSV,
#' or the daily age-stratified \code{.RData} extract can pass that path
#' instead without changing anything downstream.
#'
#' @param source \code{NULL} (default) to read the live PHO ORVT feed, or a
#'   path to an ORVT CSV, a PAGe historical CSV, or an \code{.RData}/\code{.rda}
#'   daily extract, or a data frame already in the canonical schema.
#' @param season Optional PAGe season label (for example \code{"2026-27"}).
#'   Defaults to the current season implied by the calendar.
#' @param start_week Integer MMWR week that starts a PAGe season (default 27).
#' @param pathogen Element name to read from a daily \code{.RData} extract
#'   (default \code{"fluA"}). Ignored for other sources.
#' @param complete_weeks_only Drop trailing partial weeks from a daily extract
#'   (default \code{TRUE}). A partial week is not comparable with a full-week
#'   training history.
#' @param cache_dir Optional directory for archiving a fetched ORVT download.
#' @param include_predecessor Passed to \code{getCurrentD()} for ORVT sources.
#' @param ... Additional arguments passed to \code{getCurrentD()}.
#'
#' @return A prepared surveillance data frame carrying a \code{page_source}
#'   attribute: a list of \code{kind}, \code{path}, \code{sha256},
#'   \code{retrieved_utc}, \code{season}, \code{n_weeks},
#'   \code{latest_week_end} and \code{notes}.
#' @export
page_load_surveillance <- function(source = NULL,
                                   season = NULL,
                                   start_week = 27L,
                                   pathogen = "fluA",
                                   complete_weeks_only = TRUE,
                                   cache_dir = NULL,
                                   include_predecessor = FALSE,
                                   ...) {
  kind <- .page_source_kind(source)
  notes <- character(0)
  sha256 <- NA_character_
  path <- if (is.character(source)) source else NA_character_

  raw <- switch(kind,
    orvt_feed = getCurrentD(
      cache_dir = cache_dir, startWeek = start_week, season = season,
      include_predecessor = include_predecessor, ...
    ),
    orvt_csv = getCurrentD(
      data = source, cache_dir = cache_dir, startWeek = start_week,
      season = season, include_predecessor = include_predecessor, ...
    ),
    page_csv = .page_load_page_csv(source, start_week = start_week),
    daily_rdata = .page_load_daily_rdata(
      source,
      pathogen = pathogen, complete_weeks_only = complete_weeks_only,
      start_week = start_week
    ),
    data_frame = as.data.frame(source, stringsAsFactors = FALSE)
  )

  if (kind %in% c("orvt_feed", "orvt_csv")) {
    sha256 <- attr(raw, "sha256") %||% NA_character_
    path <- attr(raw, "source_url_or_path") %||% path
  } else if (kind %in% c("page_csv", "daily_rdata")) {
    sha256 <- .page_file_sha256(source)
  }
  dropped <- attr(raw, "dropped_partial_weeks")
  if (length(dropped)) {
    notes <- c(notes, paste0(
      "dropped ", length(dropped), " partial week(s): ", paste(dropped, collapse = ", ")
    ))
  }

  prepared <- prepare_surveillance_data(raw)
  if (!is.null(season)) {
    keep <- as.character(prepared$season) == as.character(season)
    if (!any(keep)) {
      stop("No rows for season `", season, "` in the resolved source.", call. = FALSE)
    }
    prepared <- prepared[keep, , drop = FALSE]
    rownames(prepared) <- NULL
  }
  resolved_season <- unique(as.character(prepared$season))
  latest_end <- if ("week_end_date" %in% names(prepared)) {
    as.character(max(as.Date(prepared$week_end_date), na.rm = TRUE))
  } else {
    NA_character_
  }
  attr(prepared, "page_source") <- list(
    kind = kind,
    path = path,
    sha256 = sha256,
    retrieved_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    season = resolved_season,
    n_weeks = nrow(prepared),
    latest_weekF = suppressWarnings(max(as.integer(prepared$weekF), na.rm = TRUE)),
    latest_week_end = latest_end,
    notes = notes
  )
  prepared
}

#' Produce a real-time forecast from a frozen kit and any supported source
#'
#' Thin operational wrapper: resolve the source, confirm the kit is frozen,
#' run the frozen walk-forward, and return the pipeline result together with
#' the resolved provenance and a tidy latest-origin summary. Pre-ignition
#' seasons legitimately return zero forecast rows; that is a valid result and
#' not an error.
#'
#' @param kit A frozen PAGe kit.
#' @param source Passed to \code{page_load_surveillance()}; \code{NULL}
#'   (default) reads the live PHO ORVT feed.
#' @param season Optional PAGe season label.
#' @param walk_start Minimum M1 evaluation week (default 5). The effective
#'   start is \code{max(walk_start, locked ignition week)}.
#' @param manual_ign_week Optional integer week overriding M0 detection.
#' @param timing_mode \code{"fractional"} (default) or \code{"legacy"}.
#' @param verbose Print stage progress.
#' @param ... Passed to \code{page_load_surveillance()}.
#'
#' @return A list with \code{forecast} (latest-origin h1/h2 rows, possibly
#'   zero-row), \code{ignition} (status scalars), \code{result} (the full
#'   \code{run_prospective_pipeline()} object) and \code{source} (provenance).
#' @export
page_forecast_now <- function(kit,
                              source = NULL,
                              season = NULL,
                              walk_start = 5L,
                              manual_ign_week = NA_integer_,
                              timing_mode = c("fractional", "legacy"),
                              verbose = TRUE,
                              ...) {
  timing_mode <- match.arg(timing_mode)
  kit <- validate_page_kit(kit, mode = "frozen")
  current <- page_load_surveillance(source = source, season = season, ...)
  provenance <- attr(current, "page_source")
  if (length(provenance$season) != 1L) {
    stop(
      "Resolved source spans ", length(provenance$season),
      " seasons; supply `season` to choose one.",
      call. = FALSE
    )
  }
  if (isTRUE(verbose)) {
    message(
      "[page_forecast_now] source=", provenance$kind,
      " season=", provenance$season,
      " weeks=", provenance$n_weeks,
      " latest_weekF=", provenance$latest_weekF,
      " latest_week_end=", provenance$latest_week_end
    )
  }
  result <- run_prospective_pipeline(
    kit, current,
    walk_start = walk_start, manual_ign_week = manual_ign_week,
    mode = "frozen", season = provenance$season, verbose = verbose,
    timing_mode = timing_mode
  )
  preds <- as.data.frame(result$m2_preds, stringsAsFactors = FALSE)
  latest <- if (nrow(preds)) {
    preds[as.integer(preds$eval_week) == max(as.integer(preds$eval_week)), , drop = FALSE]
  } else {
    preds
  }
  ignition <- list(
    detection_failed = isTRUE(result$ign_out$detection_failed),
    ign_week_locked = result$ign_out$ign_week_locked,
    iWeek_hat_locked = result$ign_out$iWeek_hat_locked,
    timing_mode = result$ign_out$timing_mode
  )
  if (isTRUE(verbose)) {
    message(
      "[page_forecast_now] ignition locked=",
      if (is.na(ignition$ign_week_locked)) "none (pre-ignition)" else ignition$ign_week_locked,
      "; forecast rows=", nrow(latest)
    )
  }
  list(
    forecast = latest,
    ignition = ignition,
    result = result,
    source = provenance
  )
}
