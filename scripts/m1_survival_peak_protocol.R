sp_protocol <- function(run_id = "m1-survival-peak-v1-smoke") {
  list(
    protocol_id = "research_m1_survival_peak_v1",
    run_id = run_id,
    route = "research_m1_survival_peak_v1",
    production_eligible = FALSE,
    principal_seasons = c("2012-13", "2013-14", "2014-15", "2016-17", "2017-18",
      "2018-19", "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"),
    excluded_seasons = c("2011-12", "2015-16", "2020-21", "2021-22"),
    min_origin = 13L, lambda = c(0.1, 1, 10), links = c("logit", "cloglog"),
    tie_link = "logit", feature_names = c("level", "slope3", "weeks_since_max", "drawdown"),
    gate_df = 3L, hazard_df = 3L, spline_knots = c(18, 35), spline_bounds = c(1, 53),
    ridge_scale = "normalized_loss", probability_clip = 1e-12, normalization_tolerance = 1e-10,
    seed = 20260930L, interval_level = 0.8, interval_type = "central_discrete_predictive",
    interval_fields = c(point = "peak_weekF_origin", lo = "peak_weekF_lo", hi = "peak_weekF_hi", width = "peak_ci_width")
  )
}

sp_validate_calendar <- function(calendar) {
  if (is.null(names(calendar)) || any(!nzchar(names(calendar))) || anyDuplicated(names(calendar)))
    stop("Calendar must be a uniquely named season-to-week vector.", call. = FALSE)
  if (any(!is.finite(calendar)) || any(calendar != as.integer(calendar)))
    stop("Calendar lengths must be finite integer values.", call. = FALSE)
  if (any(!calendar %in% c(52L, 53L))) stop("Only 52/53-week calendars are supported.", call. = FALSE)
  invisible(as.integer(calendar))
}

sp_calendar_from_metadata <- function(metadata, seasons = NULL) {
  x <- as.data.frame(metadata, stringsAsFactors = FALSE)
  if (!all(c("season", "W", "source", "source_hash", "authoritative") %in% names(x)))
    stop("Calendar metadata must identify season, W, authority, source, and source hash.", call. = FALSE)
  if (anyDuplicated(x$season) || anyNA(x$authoritative) || any(!x$authoritative) ||
      anyNA(x$source) || any(!nzchar(x$source)) || anyNA(x$source_hash) || any(!nzchar(x$source_hash)))
    stop("Calendar metadata is ambiguous or unauthoritative.", call. = FALSE)
  out <- setNames(as.integer(x$W), as.character(x$season))
  sp_validate_calendar(out)
  if (!is.null(seasons) && !setequal(names(out), as.character(seasons)))
    stop("Calendar metadata does not cover the required seasons exactly.", call. = FALSE)
  out
}

sp_calendar_hash <- function(calendar_metadata) {
  x <- as.data.frame(calendar_metadata, stringsAsFactors = FALSE)
  x <- x[order(x$season), c("season", "W", "source", "source_hash", "authoritative"), drop = FALSE]
  tf <- tempfile(); on.exit(unlink(tf), add = TRUE)
  write.csv(x, tf, row.names = FALSE, na = "")
  unname(tools::md5sum(tf))
}

sp_round_peak <- function(P) {
  if (!is.numeric(P) || any(!is.finite(P))) stop("P must contain finite numeric labels.", call. = FALSE)
  as.integer(floor(P + 0.5))
}

sp_validate_labels <- function(labels, calendar, require_mature = TRUE) {
  sp_validate_calendar(calendar)
  need <- c("season", "P", "mature")
  if (!is.data.frame(labels) || !all(need %in% names(labels))) stop("Labels require season, P, mature.", call. = FALSE)
  if (anyDuplicated(labels$season)) stop("Duplicate season labels.", call. = FALSE)
  if (!setequal(as.character(labels$season), names(calendar))) stop("Label/calendar season mappings must be exact.", call. = FALSE)
  W <- unname(calendar[as.character(labels$season)])
  K <- sp_round_peak(labels$P)
  if (any(labels$P < 1 | labels$P > W | K < 1 | K > W)) stop("Peak label outside calendar support.", call. = FALSE)
  if (anyNA(labels$mature) || (require_mature && any(!labels$mature))) stop("All primary-study labels must be present and mature.", call. = FALSE)
  data.frame(season = as.character(labels$season), P = as.numeric(labels$P), K = K,
    W = as.integer(W), mature = as.logical(labels$mature), stringsAsFactors = FALSE)
}

sp_preflight_panel <- function(observations, labels, calendar_metadata, protocol = sp_protocol(), expected_isolation = TRUE) {
  if (!isTRUE(expected_isolation)) stop("Source/data isolation expectation failed.", call. = FALSE)
  cal <- sp_calendar_from_metadata(calendar_metadata, protocol$principal_seasons)
  lab <- sp_validate_labels(labels, cal, require_mature = TRUE)
  obs <- as.data.frame(observations, stringsAsFactors = FALSE)
  if (!all(c("season", "weekF", "y", "N") %in% names(obs))) stop("Observation schema is incomplete.", call. = FALSE)
  if (anyDuplicated(obs[c("season", "weekF")])) stop("Duplicate observation keys.", call. = FALSE)
  if (any(!obs$season %in% names(cal))) stop("Observations contain a season without authoritative calendar metadata.", call. = FALSE)
  if (any(!is.finite(obs$weekF) | obs$weekF != as.integer(obs$weekF) | obs$weekF < 1L |
          obs$weekF > unname(cal[as.character(obs$season)]))) stop("Observed weekF/calendar mismatch.", call. = FALSE)
  hashes <- attr(observations, "source_hashes")
  list(calendar = cal, labels = lab, calendar_hash = sp_calendar_hash(calendar_metadata),
       source_hashes = hashes, mature_seasons = sort(lab$season))
}

sp_require_isolated_source <- function(root = ".", allow_smoke = FALSE) {
  git <- suppressWarnings(system2("git", c("-C", shQuote(root), "rev-parse", "--show-toplevel"), stdout = TRUE, stderr = FALSE))
  if (!length(git) || !nzchar(git[[1L]])) {
    if (isTRUE(allow_smoke)) return(invisible(list(git = NA_character_, smoke_only = TRUE)))
    stop("Git source identity unavailable; historical run is blocked.", call. = FALSE)
  }
  branch <- system2("git", c("-C", shQuote(root), "branch", "--show-current"), stdout = TRUE, stderr = FALSE)
  commit <- system2("git", c("-C", shQuote(root), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)
  if (!length(branch) || !nzchar(branch[[1L]]) || !length(commit) || !nzchar(commit[[1L]]))
    stop("Git branch/commit identity unavailable.", call. = FALSE)
  invisible(list(root = git[[1L]], branch = branch[[1L]], commit = commit[[1L]], smoke_only = FALSE))
}
