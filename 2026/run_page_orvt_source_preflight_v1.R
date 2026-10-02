#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

.parse_args <- function(args) {
  out <- list(
    season = "2026-27",
    min_weekF = "1",
    input = NULL,
    result_path = NULL
  )
  for (arg in args) {
    if (!grepl("^--[^=]+=", arg)) stop("Arguments must use --key=value.", call. = FALSE)
    key <- gsub("-", "_", sub("^--([^=]+)=.*$", "\\1", arg))
    value <- sub("^--[^=]+=", "", arg)
    if (!key %in% names(out)) stop("Unknown preflight argument: ", key, call. = FALSE)
    out[[key]] <- value
  }
  if (is.null(out$result_path) || !nzchar(out$result_path)) {
    stop("--result-path is required.", call. = FALSE)
  }
  if (!grepl("^[0-9]{4}-[0-9]{2}$", out$season)) {
    stop("--season must have form YYYY-YY.", call. = FALSE)
  }
  min_weekF <- suppressWarnings(as.integer(out$min_weekF))
  if (is.na(min_weekF) || !grepl("^[0-9]+$", out$min_weekF) || min_weekF < 1L || min_weekF > 53L) {
    stop("--min-weekF must be one integer in [1, 53].", call. = FALSE)
  }
  out$min_weekF <- min_weekF
  out
}

.atomic_json <- function(x, path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite missing.", call. = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile("orvt-preflight-", tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  writeLines(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", pretty = FALSE), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) stop("Could not publish ORVT preflight result.", call. = FALSE)
}

.main <- function(args = commandArgs(trailingOnly = TRUE)) {
  opt <- .parse_args(args)
  if (!file.exists("PAGe/DESCRIPTION")) stop("Run from the PAGe repository root.", call. = FALSE)

  ok <- FALSE
  code <- "orvt_preflight_failed"
  detail <- NULL
  result <- list()
  tryCatch({
    source("2026/run_weekly_shadow_v2.R")
    .shadow_v2_source_package()
    cache <- tempfile("page-orvt-preflight-cache-")
    dir.create(cache, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(cache, recursive = TRUE, force = TRUE), add = TRUE)

    if (is.null(opt$input) || !nzchar(opt$input)) {
      raw <- .shadow_v2_fetch_orvt(opt$season, cache)
    } else {
      src <- normalizePath(opt$input, winslash = "/", mustWork = TRUE)
      archived <- .shadow_v2_copy_source(src, cache, label = "orvt_preflight_input")
      raw <- list(
        mode = "orvt",
        path = archived,
        original = src,
        sha256 = .shadow_v2_sha256(archived),
        fallback_reason = NA_character_
      )
    }

    if (!identical(raw$mode, "orvt")) stop("Preflight did not resolve ORVT.", call. = FALSE)
    panel <- .shadow_v2_panel_from_orvt(raw$path, opt$season)
    panel <- panel[order(as.integer(panel$weekF)), , drop = FALSE]
    .shadow_ops_validate_panel(panel, opt$season, require_forecast_support = FALSE)
    origin <- max(as.integer(panel$weekF))
    if (origin < opt$min_weekF) {
      stop(
        "Live ORVT latest weekF is ", origin,
        ", below required minimum ", opt$min_weekF, ".",
        call. = FALSE
      )
    }
    last <- panel[which.max(as.integer(panel$weekF)), , drop = FALSE]
    result <- list(
      source_mode = "orvt",
      source_original = as.character(raw$original),
      raw_source_sha256 = as.character(raw$sha256),
      season = opt$season,
      origin_weekF = as.integer(origin),
      week_end_date = as.character(last$week_end_date[[1L]]),
      A = list(
        y = as.numeric(last$y_A[[1L]]), N = as.numeric(last$N_A[[1L]]),
        p = as.numeric(last$p_A[[1L]])
      ),
      B = list(
        y = as.numeric(last$y_B[[1L]]), N = as.numeric(last$N_B[[1L]]),
        p = as.numeric(last$p_B[[1L]])
      )
    )
    ok <- TRUE
    code <- "ok"
  }, error = function(e) {
    detail <<- conditionMessage(e)
  })

  payload <- c(
    list(
      ok = ok,
      code = code,
      checked_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      required_min_weekF = as.integer(opt$min_weekF)
    ),
    result,
    if (is.null(detail)) list() else list(detail = detail)
  )
  .atomic_json(payload, opt$result_path)
  if (!ok) quit(save = "no", status = 1L)
  invisible(payload)
}

if (sys.nframe() == 0L) .main()
