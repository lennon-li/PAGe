.pho_orvt_base_url <- function() {
  "https://ws1.publichealthontario.ca/appdata/powerbi/ORVT/"
}

.pho_orvt_default_url <- function() {
  paste0(.pho_orvt_base_url(), "ORVT_Lab_Testing_Data_2024-25_2025-26.csv")
}

.orvt_season_label <- function(start_year) {
  sprintf("%04d-%02d", as.integer(start_year), (as.integer(start_year) + 1L) %% 100L)
}

.orvt_season_start_year <- function(season) {
  pieces <- regmatches(season, regexec("^([0-9]{4})-([0-9]{2})$", season))[[1L]]
  if (length(pieces) != 3L) {
    stop("`season` must have the form `YYYY-YY` (for example, `2025-26`).", call. = FALSE)
  }
  start_year <- as.integer(pieces[2L])
  if (as.integer(pieces[3L]) != (start_year + 1L) %% 100L) {
    stop("`season` must identify consecutive calendar years (for example, `2025-26`).",
      call. = FALSE
    )
  }
  start_year
}

.orvt_previous_season <- function(season) {
  .orvt_season_label(.orvt_season_start_year(season) - 1L)
}

.orvt_next_season <- function(season) {
  .orvt_season_label(.orvt_season_start_year(season) + 1L)
}

.orvt_current_season <- function(start_week) {
  mmwr <- MMWRweek::MMWRweek(Sys.Date())
  start_year <- if (mmwr$MMWRweek >= start_week) mmwr$MMWRyear else mmwr$MMWRyear - 1L
  .orvt_season_label(start_year)
}

.orvt_n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(
    as.Date(paste0(as.integer(start_year), "-12-28"))
  )$MMWRweek == 53L)
}

.orvt_find_column <- function(data, candidates, required = TRUE) {
  normalize <- function(x) tolower(gsub("[^a-z0-9]", "", x))
  idx <- match(normalize(candidates), normalize(names(data)))
  idx <- idx[!is.na(idx)]
  if (!length(idx)) {
    if (required) {
      stop("PHO ORVT source is missing required column(s): ",
        paste(candidates, collapse = " / "), ".",
        call. = FALSE
      )
    }
    return(NULL)
  }
  names(data)[idx[1L]]
}

.orvt_parse_dates <- function(x, field) {
  if (inherits(x, "Date")) {
    return(x)
  }
  value <- trimws(as.character(x))
  out <- as.Date(rep(NA_character_, length(value)))
  formats <- list(
    "YYYY-MM-DD" = "^\\d{4}-\\d{2}-\\d{2}$",
    "DDMMMYYYY" = "^\\d{1,2}[A-Za-z]{3}\\d{4}$",
    "DD-MMM-YYYY" = "^\\d{1,2}-[A-Za-z]{3}-\\d{4}$",
    "MM/DD/YYYY" = "^\\d{1,2}/\\d{1,2}/\\d{4}$"
  )
  for (fmt in names(formats)) {
    pending <- is.na(out) & grepl(formats[[fmt]], value)
    if (!any(pending)) next
    parse_fmt <- switch(fmt,
      `YYYY-MM-DD` = "%Y-%m-%d",
      DDMMMYYYY = "%d%b%Y",
      `DD-MMM-YYYY` = "%d-%b-%Y",
      `MM/DD/YYYY` = "%m/%d/%Y"
    )
    out[pending] <- as.Date(toupper(value[pending]), format = parse_fmt)
  }
  if (anyNA(out)) {
    stop("PHO ORVT `", field, "` contains unsupported or invalid dates. Supported formats are ",
      "YYYY-MM-DD, DDMMMYYYY, DD-MMM-YYYY, and MM/DD/YYYY.",
      call. = FALSE
    )
  }
  out
}

.orvt_source_calendar_dates <- function(source_calendar, pho_season, week) {
  calendar <- if (is.function(source_calendar)) {
    tryCatch(
      source_calendar(pho_season = pho_season, week = week),
      error = function(e) source_calendar(pho_season, week)
    )
  } else {
    source_calendar
  }
  if (inherits(calendar, "Date")) {
    if (length(calendar) != length(week)) {
      stop("`source_calendar` must return one date per source row.", call. = FALSE)
    }
    week_start <- calendar
    return(list(week_start = week_start, week_end = week_start + 6L))
  }
  if (!is.data.frame(calendar) && is.list(calendar)) calendar <- as.data.frame(calendar)
  if (!is.data.frame(calendar)) {
    stop("`source_calendar` must be a data frame, Date vector, or function.", call. = FALSE)
  }
  date_col <- intersect(c("week_start_date", "week_start", "date"), names(calendar))[1L]
  end_col <- intersect(c("week_end_date", "week_end"), names(calendar))[1L]
  week_col <- intersect(c("week", "mmwr_week", "MMWRweek"), names(calendar))[1L]
  season_col <- intersect(c("pho_season", "season", "source_season"), names(calendar))[1L]
  year_col <- intersect(c("mmwr_year", "MMWRyear", "year"), names(calendar))[1L]
  if (is.na(date_col) && is.na(year_col)) {
    stop("`source_calendar` must supply week-start dates or MMWR years.", call. = FALSE)
  }
  if (!is.na(week_col)) {
    if (!is.na(season_col)) {
      key <- paste(as.character(pho_season), as.integer(week), sep = "\r")
      cal_key <- paste(as.character(calendar[[season_col]]),
        as.integer(calendar[[week_col]]),
        sep = "\r"
      )
      idx <- match(key, cal_key)
    } else if (nrow(calendar) == length(week)) {
      idx <- seq_along(week)
    } else {
      idx <- match(as.integer(week), as.integer(calendar[[week_col]]))
    }
  } else if (nrow(calendar) == length(week)) {
    idx <- seq_along(week)
  } else {
    stop("`source_calendar` must identify rows by week (and season when needed).", call. = FALSE)
  }
  if (anyNA(idx)) stop("`source_calendar` has no mapping for every source row.", call. = FALSE)
  mmwr_week <- as.integer(week)
  week_start <- if (!is.na(date_col)) {
    .orvt_parse_dates(calendar[[date_col]][idx], "source calendar week start")
  } else {
    mmwr_year <- suppressWarnings(as.integer(as.character(calendar[[year_col]][idx])))
    if (anyNA(mmwr_year)) stop("`source_calendar` MMWR years must be finite integers.", call. = FALSE)
    as.Date(MMWRweek::MMWRweek2Date(mmwr_year, mmwr_week, 1L), origin = "1970-01-01")
  }
  week_end <- if (!is.na(end_col)) {
    .orvt_parse_dates(calendar[[end_col]][idx], "source calendar week end")
  } else {
    week_start + 6L
  }
  list(week_start = week_start, week_end = week_end)
}

.orvt_fetch_bytes <- function(source) {
  reader <- getOption("PAGe.orvt_reader", NULL)
  if (!is.null(reader)) {
    bytes <- reader(source)
    if (is.character(bytes) && length(bytes) == 1L && file.exists(bytes)) {
      bytes <- readBin(bytes, what = "raw", n = file.info(bytes)$size)
    }
    if (!is.raw(bytes)) stop("PAGe.orvt_reader must return raw bytes or a file path.", call. = FALSE)
    return(bytes)
  }
  if (grepl("^https?://", source, ignore.case = TRUE)) {
    target <- tempfile(fileext = ".csv")
    on.exit(unlink(target), add = TRUE)
    utils::download.file(source, target, mode = "wb", quiet = TRUE)
    return(readBin(target, what = "raw", n = file.info(target)$size))
  }
  if (!file.exists(source)) stop("File does not exist: `", source, "`.", call. = FALSE)
  readBin(source, what = "raw", n = file.info(source)$size)
}

.orvt_read_source <- function(source, cache_dir = NULL) {
  bytes <- .orvt_fetch_bytes(source)
  if (!length(bytes)) stop("PHO ORVT source is empty: `", source, "`.", call. = FALSE)
  hash <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  if (!is.null(cache_dir) && grepl("^https?://", source, ignore.case = TRUE)) {
    if (length(cache_dir) != 1L || is.na(cache_dir) || !nzchar(cache_dir)) {
      stop("`cache_dir` must be NULL or one non-empty directory path.", call. = FALSE)
    }
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
    writeBin(bytes, file.path(cache_dir, paste0("orvt_", stamp, "_", hash, ".csv")))
  }
  list(
    bytes = bytes, hash = hash,
    data = utils::read.csv(
      text = rawToChar(bytes), check.names = FALSE,
      stringsAsFactors = FALSE
    )
  )
}

#' Fetch and tidy current-season PHO respiratory surveillance data
#'
#' Reads a Public Health Ontario ORVT lab-testing CSV from a URL or local path,
#' maps seasons from dated MMWR weeks rather than the PHO label, aggregates the
#' selected virus across public health units, and returns data ready for PAGe.
#' With no code{data}, the previous/current and current/next feed names are
#' tried in that order. PHO labels and source dates are retained for audit.
#'
#' @param data URL or local file path to an ORVT CSV, or code{NULL} for default
#'   feed resolution.
#' @param base_url Base ORVT URL for default feed resolution. The
#'   code{PAGe.orvt_base_url} option overrides the package default.
#' @param file_name Optional ORVT filename replacing the two default candidates;
#'   code{PAGe.orvt_file_name} is also supported.
#' @param cache_dir Optional directory for timestamped downloaded raw CSV files.
#' @param startWeek Integer MMWR week used as the PAGe season origin (default 27).
#' @param lastWeek Integer or code{NA}; drop rows with MMWR week greater than it.
#' @param virus Character string matching the PHO code{Virus} column.
#' @param season Character season in code{"YYYY-YY"}; defaults to the season
#'   containing code{Sys.Date()} under the PAGe origin.
#' @param include_predecessor Logical; also return the derived predecessor
#'   season. Defaults to code{TRUE} for backward compatibility.
#' @param source_calendar Optional explicit calendar for undated sources. It
#'   must be a data frame, Date vector, or function mapping source season/week
#'   rows to week-start dates (or MMWR years); labels alone are never used to
#'   guess dates.
#'
#' @return A data frame with code{season}, code{week}, code{N}, code{y},
#'   code{neg}, code{p}, code{weekS}, code{weekF}, code{cYear},
#'   code{newWeek}, and code{date}, plus PHO audit columns. The PHU-only
#'   totals and the exact-Ontario-row provenance are retained in
#'   code{phu_N}, code{phu_y}, code{source_has_ontario},
#'   code{source_ontario_consistent}, and code{provincial_value_source}.
#'   Attributes record
#'   code{source_url_or_path}, code{retrieved_utc}, code{sha256},
#'   code{pho_layout}, code{n_weeks}, and code{last_week_end_date}.
#' @export
getCurrentD <- function(data = NULL, base_url = NULL, file_name = NULL,
                        cache_dir = NULL, startWeek = 27L,
                        lastWeek = NA_integer_, virus = "Influenza A",
                        season = NULL, include_predecessor = TRUE,
                        source_calendar = NULL) {
  if (!is.numeric(startWeek) || length(startWeek) != 1L || !is.finite(startWeek) ||
    startWeek != as.integer(startWeek) || startWeek < 1L || startWeek > 53L) {
    stop("`startWeek` must be one integer in [1, 53].", call. = FALSE)
  }
  startWeek <- as.integer(startWeek)
  if (!is.numeric(lastWeek) || length(lastWeek) != 1L ||
    (!is.na(lastWeek) && (!is.finite(lastWeek) || lastWeek != as.integer(lastWeek) ||
      lastWeek < 1L || lastWeek > 53L))) {
    stop("`lastWeek` must be NA or one integer in [1, 53].", call. = FALSE)
  }
  if (!is.logical(include_predecessor) || length(include_predecessor) != 1L ||
    is.na(include_predecessor)) {
    stop("`include_predecessor` must be one non-missing logical value.",
      call. = FALSE
    )
  }
  if (!is.character(virus) || length(virus) != 1L || is.na(virus) || !nzchar(trimws(virus))) {
    stop("`virus` must be one non-empty character value.", call. = FALSE)
  }
  if (is.null(season)) season <- .orvt_current_season(startWeek)
  if (!is.character(season) || length(season) != 1L || is.na(season) ||
    !grepl("^[0-9]{4}-[0-9]{2}$", season)) {
    stop("`season` must have the form `YYYY-YY` (for example, `2025-26`).", call. = FALSE)
  }
  season <- trimws(season)
  .orvt_season_start_year(season)
  if (!is.null(data) && (!is.character(data) || length(data) != 1L || is.na(data) ||
    !nzchar(trimws(data)))) {
    stop("`data` must be NULL or one non-empty local path or URL.", call. = FALSE)
  }

  requested_seasons <- c(season, if (isTRUE(include_predecessor)) .orvt_previous_season(season))
  source <- data
  if (is.null(source)) {
    base_url <- if (is.null(base_url)) getOption("PAGe.orvt_base_url", .pho_orvt_base_url()) else base_url
    file_name <- if (is.null(file_name)) getOption("PAGe.orvt_file_name", NULL) else file_name
    if (!is.character(base_url) || length(base_url) != 1L || is.na(base_url) || !nzchar(base_url)) {
      stop("`base_url` must be one non-empty URL when `data` is NULL.", call. = FALSE)
    }
    candidates <- if (is.null(file_name)) {
      c(
        paste0("ORVT_Lab_Testing_Data_", .orvt_previous_season(season), "_", season, ".csv"),
        paste0("ORVT_Lab_Testing_Data_", season, "_", .orvt_next_season(season), ".csv")
      )
    } else {
      if (!is.character(file_name) || length(file_name) != 1L || is.na(file_name) ||
        !nzchar(trimws(file_name))) {
        stop("`file_name` must be NULL or one non-empty filename.", call. = FALSE)
      }
      file_name
    }
    tried <- character()
    source <- character()
    for (candidate in candidates) {
      candidate_url <- paste0(sub("/+$", "", base_url), "/", candidate)
      tried <- c(tried, candidate_url)
      attempt <- tryCatch(.orvt_read_source(candidate_url, cache_dir), error = function(e) NULL)
      if (!is.null(attempt)) {
        source <- candidate_url
        raw_source <- attempt
        break
      }
    }
    if (!length(source)) {
      stop("No readable PHO ORVT feed found. Tried: ",
        paste(tried, collapse = "; "),
        call. = FALSE
      )
    }
  } else {
    raw_source <- tryCatch(.orvt_read_source(source, cache_dir), error = function(e) {
      stop("Could not read PHO surveillance source `", source, "`: ", conditionMessage(e), call. = FALSE)
    })
  }
  raw <- raw_source$data
  virus_col <- .orvt_find_column(raw, "Virus")
  week_col <- .orvt_find_column(raw, "Surveillance week")
  pos_col <- .orvt_find_column(raw, c("# of positive tests", "Number of positive tests"))
  total_col <- .orvt_find_column(raw, c("Total # of tests", "Total number of tests"))
  phu_col <- .orvt_find_column(raw, c("Public health unit", "Public health unit name"), FALSE)
  pho_season_col <- .orvt_find_column(raw, c("Surveillance period", "Respiratory season"))
  layout <- if (identical(.orvt_find_column(raw, "Surveillance period", FALSE), pho_season_col)) {
    "surveillance_period"
  } else {
    "respiratory_season"
  }
  start_col <- .orvt_find_column(raw, "Week start date", FALSE)
  end_col <- .orvt_find_column(raw, "Week end date", FALSE)
  if (xor(is.null(start_col), is.null(end_col))) {
    stop("PHO ORVT source must contain both `Week start date` and `Week end date`.", call. = FALSE)
  }
  keep <- trimws(as.character(raw[[virus_col]])) == trimws(virus)
  if (!any(keep)) stop("PHO source has no rows for virus `", virus, ".", call. = FALSE)
  raw <- raw[keep, , drop = FALSE]
  week <- suppressWarnings(as.numeric(as.character(raw[[week_col]])))
  positive <- suppressWarnings(as.numeric(as.character(raw[[pos_col]])))
  total <- suppressWarnings(as.numeric(as.character(raw[[total_col]])))
  if (any(!is.finite(week)) || any(week != round(week)) || any(week < 1L | week > 53L)) {
    stop("PHO `Surveillance.week` must contain finite whole numbers in [1, 53].", call. = FALSE)
  }
  if (any(!is.finite(total)) || any(!is.finite(positive)) || any(total < 0) ||
    any(positive < 0) || any(positive > total)) {
    stop("PHO test counts must be finite, non-negative, and satisfy y <= N.", call. = FALSE)
  }
  pho_season <- trimws(as.character(raw[[pho_season_col]]))
  phu <- if (is.null(phu_col)) {
    rep("<unknown>", nrow(raw))
  } else {
    trimws(as.character(raw[[phu_col]]))
  }
  if (anyNA(pho_season) || any(!nzchar(pho_season)) || anyNA(phu) || any(!nzchar(phu))) {
    stop("PHO season labels and public health units must be non-empty.", call. = FALSE)
  }
  if (!is.null(start_col)) {
    week_start <- .orvt_parse_dates(raw[[start_col]], "Week start date")
    week_end <- .orvt_parse_dates(raw[[end_col]], "Week end date")
    if (any(week_end < week_start)) stop("PHO week-end dates precede week-start dates.", call. = FALSE)
    mmwr <- MMWRweek::MMWRweek(week_start)
    if (any(as.integer(mmwr$MMWRweek) != as.integer(week))) {
      stop("PHO `Surveillance week` disagrees with the supplied week-start date.", call. = FALSE)
    }
  } else {
    if (is.null(source_calendar)) {
      stop(
        "PHO source has no week-start dates; supply `source_calendar` explicitly. ",
        "The PHO season label is not a calendar source.",
        call. = FALSE
      )
    }
    source_dates <- .orvt_source_calendar_dates(source_calendar, pho_season, week)
    week_start <- source_dates$week_start
    week_end <- source_dates$week_end
    mmwr_year <- as.integer(MMWRweek::MMWRweek(week_start)$MMWRyear)
    mmwr <- list(MMWRyear = mmwr_year, MMWRweek = week)
  }
  mmwr_year <- as.integer(mmwr$MMWRyear)
  mmwr_week <- as.integer(mmwr$MMWRweek)
  calendar <- page_season_calendar(dates = week_start, start_week = startWeek)
  derived_start <- calendar$start_year
  derived_season <- calendar$season
  n_weeks <- calendar$nW_true
  weekF <- calendar$weekF

  phu_key <- paste(phu, as.character(week_start), mmwr_week, sep = "\r")
  groups <- split(seq_along(phu_key), phu_key)
  retained <- integer(length(groups))
  group_i <- 0L
  for (indices in groups) {
    group_i <- group_i + 1L
    relevant <- data.frame(
      phu = phu[indices], pho_season = pho_season[indices],
      week_start = week_start[indices], week_end = week_end[indices],
      week = mmwr_week[indices], N = total[indices], y = positive[indices],
      stringsAsFactors = FALSE
    )
    if (nrow(unique(relevant)) > 1L) {
      stop("Conflicting duplicate PHO rows for public health unit/week.", call. = FALSE)
    }
    retained[group_i] <- indices[1L]
  }
  if (length(retained) < length(phu_key)) {
    phu <- phu[retained]
    pho_season <- pho_season[retained]
    week_start <- week_start[retained]
    week_end <- week_end[retained]
    mmwr_year <- mmwr_year[retained]
    mmwr_week <- mmwr_week[retained]
    derived_start <- derived_start[retained]
    derived_season <- derived_season[retained]
    n_weeks <- n_weeks[retained]
    weekF <- weekF[retained]
    total <- total[retained]
    positive <- positive[retained]
  }
  selected <- derived_season %in% requested_seasons
  if (!any(selected)) {
    stop("PHO source has no dated rows for requested season `", season,
      if (isTRUE(include_predecessor)) " or its predecessor." else ".",
      call. = FALSE
    )
  }
  aggregate_groups <- split(which(selected), paste(derived_season[selected], mmwr_week[selected], sep = "\r"))
  out <- vector("list", length(aggregate_groups))
  group_i <- 0L
  provincial_tolerance <- 0
  missing_ontario <- character()
  for (indices in aggregate_groups) {
    group_i <- group_i + 1L
    ontario <- phu[indices] == "Ontario"
    if (sum(ontario) > 1L) {
      stop("Multiple exact `Ontario` rows for season/week.", call. = FALSE)
    }
    phu_indices <- indices[!ontario]
    phu_N <- sum(total[phu_indices])
    phu_y <- sum(positive[phu_indices])
    has_ontario <- any(ontario)
    if (has_ontario) {
      provincial_N <- total[indices[ontario]]
      provincial_y <- positive[indices[ontario]]
      consistent <- abs(provincial_N - phu_N) <= provincial_tolerance &&
        abs(provincial_y - phu_y) <= provincial_tolerance
      if (!consistent) {
        stop("Exact `Ontario` totals disagree with the PHU sum for season/week.", call. = FALSE)
      }
      value_N <- provincial_N
      value_y <- provincial_y
      value_source <- "Ontario"
    } else {
      provincial_N <- NA_real_
      provincial_y <- NA_real_
      consistent <- NA
      value_N <- phu_N
      value_y <- phu_y
      value_source <- "PHU sum"
      missing_ontario <- c(
        missing_ontario,
        paste(derived_season[indices[1L]], mmwr_week[indices[1L]], sep = "/")
      )
    }
    out[[group_i]] <- data.frame(
      season = derived_season[indices[1L]], week = mmwr_week[indices[1L]],
      N = value_N, y = value_y,
      pho_season = paste(sort(unique(pho_season[indices])), collapse = ";"),
      week_start_date = min(week_start[indices]), week_end_date = max(week_end[indices]),
      mmwr_year = mmwr_year[indices[1L]], source_n_phu = length(unique(phu[phu_indices])),
      phu_N = phu_N, phu_y = phu_y,
      provincial_N = provincial_N, provincial_y = provincial_y,
      source_has_ontario = has_ontario,
      source_ontario_consistent = consistent,
      provincial_value_source = value_source,
      stringsAsFactors = FALSE
    )
  }
  out <- do.call(rbind, out)
  if (length(missing_ontario)) {
    warning(
      "PHO source has no exact `Ontario` row for ", length(missing_ontario),
      " season/week group(s); using the PHU sum. Provenance is recorded in `provincial_value_source`.",
      call. = FALSE
    )
  }
  out$neg <- out$N - out$y
  out$p <- ifelse(out$N > 0, out$y / out$N, NA_real_)
  out_calendar <- page_season_calendar(dates = out$week_start_date, start_week = startWeek)
  out$season <- out_calendar$season
  out$weekF <- out_calendar$weekF
  out$weekS <- out_calendar$weekS
  out$cYear <- as.factor(format(out$week_start_date, "%Y"))
  out$newWeek <- out$weekF
  out$date <- out$week_start_date
  out$season_rank <- match(out$season, requested_seasons)
  out <- out[order(out$season_rank, out$weekF), , drop = FALSE]
  out$season_rank <- NULL
  if (!is.na(lastWeek)) out <- out[out$week <= lastWeek, , drop = FALSE]
  if (!nrow(out) || !(season %in% out$season)) {
    stop("No rows remain for requested season `", season, ".",
      call. = FALSE
    )
  }
  rownames(out) <- NULL
  attr(out, "source_url_or_path") <- source
  attr(out, "retrieved_utc") <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  attr(out, "sha256") <- raw_source$hash
  attr(out, "pho_layout") <- layout
  attr(out, "n_weeks") <- sum(out$season == season)
  attr(out, "last_week_end_date") <- as.character(max(out$week_end_date[out$season == season]))
  out
}

`%||%` <- function(x, y) if (is.null(x)) y else x
