#!/usr/bin/env Rscript
# Weekly operational runner for the frozen 2026-27 PAGe kit.
# Applies one frozen kit to current-season data; never refits or retunes.
# Launched detached by launch_weekly_forecast.sh or run directly with --dry-run.
args <- commandArgs(trailingOnly = TRUE)
if (any(!args %in% "--dry-run")) stop("Only --dry-run is supported.")
dry_run <- "--dry-run" %in% args

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) != 1L) stop("Invoke this runner with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), mustWork = TRUE)
repo_root <- normalizePath(Sys.getenv(
  "PAGE_REPO_ROOT", file.path(dirname(script_file), "..")
), mustWork = TRUE)
setwd(repo_root)

env_required <- function(name) {
  value <- trimws(Sys.getenv(name, ""))
  if (!nzchar(value)) stop("Set ", name, " before running the weekly forecast.", call. = FALSE)
  value
}
env_optional <- function(name, default) {
  value <- trimws(Sys.getenv(name, ""))
  if (!nzchar(value)) default else value
}
env_integer <- function(name, default) {
  text <- env_optional(name, as.character(default))
  value <- suppressWarnings(as.integer(text))
  if (is.na(value) || !grepl("^[0-9]+$", text)) {
    stop(name, " must be a non-negative integer.", call. = FALSE)
  }
  value
}
sha256_file <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}
`%||%` <- function(x, y) if (is.null(x)) y else x
write_tsv <- function(df, path) {
  utils::write.table(df, path,
    sep = "\t", row.names = FALSE, quote = FALSE, na = ""
  )
}

kit_path <- env_required("PAGE_KIT_PATH")
kit_expected_sha256 <- tolower(env_required("PAGE_KIT_SHA256"))
if (!grepl("^[0-9a-f]{64}$", kit_expected_sha256)) {
  stop("PAGE_KIT_SHA256 must be 64 lowercase hexadecimal characters.", call. = FALSE)
}
out_root <- env_required("PAGE_WEEKLY_OUT_ROOT")
run_id <- env_optional("PAGE_FORECAST_RUN_ID", "")
if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", run_id)) {
  stop("PAGE_FORECAST_RUN_ID must be a simple fresh identifier.", call. = FALSE)
}
run_dir <- env_optional("PAGE_WEEKLY_RUN_DIR", file.path(out_root, run_id))
forecast_source <- env_optional("PAGE_ORVT_URL", "")
forecast_week_text <- env_optional("PAGE_FORECAST_WEEK", "")
walk_start <- env_integer("PAGE_WALK_START", 5L)
timing_mode <- env_optional("PAGE_TIMING_MODE", "fractional")
if (!timing_mode %in% c("fractional", "legacy")) {
  stop("PAGE_TIMING_MODE must be `fractional` or `legacy`.", call. = FALSE)
}
staleness_text <- env_optional("PAGE_MAX_STALENESS_DAYS", "21")
staleness_days <- if (staleness_text %in% c("skip", "none")) {
  NA_integer_
} else {
  value <- suppressWarnings(as.integer(staleness_text))
  if (is.na(value) || value < 0L) {
    stop("PAGE_MAX_STALENESS_DAYS must be a non-negative integer, `skip`, or `none`.", call. = FALSE)
  }
  value
}
package_library <- env_optional("PAGE_PACKAGE_LIBRARY", "")
if (nzchar(package_library)) {
  if (!dir.exists(package_library)) {
    stop("PAGE_PACKAGE_LIBRARY does not exist: ", package_library, call. = FALSE)
  }
  .libPaths(unique(c(normalizePath(package_library, mustWork = TRUE), .libPaths())))
}
if (!requireNamespace("PAGe", quietly = TRUE)) stop("PAGe is not available on the library path.")
if (dry_run) {
  cat("PAGe weekly forecast dry run\n")
  cat("  repo_root           : ", repo_root, "\n", sep = "")
  cat("  kit_path            : ", kit_path, "\n", sep = "")
  cat("  kit_sha256_expected : ", kit_expected_sha256, "\n", sep = "")
  cat("  out_root            : ", out_root, "\n", sep = "")
  cat("  run_id              : ", run_id, "\n", sep = "")
  cat("  run_dir             : ", run_dir, "\n", sep = "")
  cat("  data source         : ",
    if (nzchar(forecast_source)) forecast_source else "<default PHO ORVT feed>",
    "\n", sep = ""
  )
  cat("  forecast week       : ",
    if (nzchar(forecast_week_text)) forecast_week_text else "<latest observed week>",
    "\n", sep = ""
  )
  cat("  timing_mode         : ", timing_mode, "\n", sep = "")
  cat("  walk_start          : ", walk_start, "\n", sep = "")
  cat("  max staleness days  : ",
    if (is.na(staleness_days)) "<disabled>" else staleness_days, "\n", sep = ""
  )
  cat("planned steps:\n")
  cat("  1. verify kit file exists and its sha256 equals PAGE_KIT_SHA256\n")
  cat("  2. load the kit and run PAGe::validate_page_kit(kit, mode = \"frozen\")\n")
  cat("  3. stop before fetching data or forecasting (dry run)\n")
}

if (!file.exists(kit_path)) {
  stop("Frozen kit not found: ", kit_path, ". Refusing to continue (fail closed).", call. = FALSE)
}
kit_actual_sha256 <- tolower(sha256_file(kit_path))
if (!identical(kit_actual_sha256, kit_expected_sha256)) {
  stop(
    "Kit sha256 mismatch. expected=", kit_expected_sha256,
    " actual=", kit_actual_sha256, ". Refusing to continue (fail closed).",
    call. = FALSE
  )
}
kit <- readRDS(kit_path)
kit <- PAGe::validate_page_kit(kit, mode = "frozen")
cat(sprintf("kit verified: sha256=%s\n", kit_actual_sha256))

if (dry_run) {
  cat("dry run complete: kit verified; no data fetched and no forecast attempted\n")
  quit(save = "no", status = 0L)
}

dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
run_dir <- normalizePath(run_dir, mustWork = TRUE)
status_path <- file.path(run_dir, "status.tsv")
write_status <- function(status, detail = "") {
  row <- data.frame(
    timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    status = status, detail = gsub("[\t\r\n]", " ", detail), stringsAsFactors = FALSE
  )
  write.table(row, status_path,
    sep = "\t", row.names = FALSE,
    col.names = !file.exists(status_path), append = file.exists(status_path), quote = FALSE
  )
}
main_pid <- Sys.getpid()
options(error = function() {
  if (identical(Sys.getpid(), main_pid)) {
    write_status("failed", "unhandled R error; inspect weekly_forecast.log")
  }
  traceback(2)
  q(status = 1L, save = "no")
})
write_status("started", sprintf("run_id=%s kit_sha256=%s", run_id, kit_actual_sha256))

cache_dir <- file.path(run_dir, "data_cache")
current <- tryCatch(
  PAGe::getCurrentD(
    data = if (nzchar(forecast_source)) forecast_source else NULL,
    cache_dir = cache_dir
  ),
  error = function(e) stop("Surveillance fetch failed: ", conditionMessage(e), call. = FALSE)
)
if (!is.data.frame(current) || !nrow(current)) stop("Surveillance source returned no rows.", call. = FALSE)
provenance <- list(
  source_url_or_path = attr(current, "source_url_or_path"),
  retrieved_utc = attr(current, "retrieved_utc"),
  sha256 = attr(current, "sha256"),
  pho_layout = attr(current, "pho_layout"),
  n_weeks = attr(current, "n_weeks"),
  last_week_end_date = attr(current, "last_week_end_date")
)
if (!all(c("season", "weekF", "y", "N") %in% names(current))) {
  stop("Surveillance source is missing canonical columns.", call. = FALSE)
}
latest_row <- which.max(current$week_end_date)
season <- as.character(current$season[latest_row])
cur_season <- current[as.character(current$season) == season, , drop = FALSE]
latest_observed_week <- max(cur_season$weekF, na.rm = TRUE)
if (nzchar(forecast_week_text)) {
  forecast_week <- suppressWarnings(as.integer(forecast_week_text))
  if (is.na(forecast_week) || forecast_week < 1L || forecast_week > 53L) {
    stop("PAGE_FORECAST_WEEK must be an integer in [1, 53].", call. = FALSE)
  }
  if (forecast_week > latest_observed_week) {
    stop(
      "PAGE_FORECAST_WEEK=", forecast_week, " exceeds the latest observed week ",
      latest_observed_week, " for season ", season, ".",
      call. = FALSE
    )
  }
} else {
  forecast_week <- latest_observed_week
}
used <- cur_season[cur_season$weekF <= forecast_week, , drop = FALSE]
if (!nrow(used)) stop("No observed rows at or before forecast week ", forecast_week, ".", call. = FALSE)
end_date <- max(as.Date(used$week_end_date))
if (!is.na(staleness_days)) {
  age_days <- as.integer(Sys.Date() - end_date)
  if (age_days > staleness_days) {
    stop(
      "Latest observed week ends ", end_date, " (", age_days, " days old) which exceeds ",
      "PAGE_MAX_STALENESS_DAYS=", staleness_days, ". Refusing a stale forecast.",
      call. = FALSE
    )
  }
}
week_label <- sprintf("%s-weekF%02d", season, forecast_week)
week_dir <- file.path(run_dir, week_label)
if (file.exists(week_dir)) {
  stop("Refusing to overwrite an existing week directory: ", week_dir, call. = FALSE)
}

status_detail <- sprintf(
  "season=%s forecast_week=%d latest_observed=%d source=%s data_sha256=%s",
  season, forecast_week, latest_observed_week,
  provenance$source_url_or_path %||% "unknown", provenance$sha256 %||% "unknown"
)
write_status("forecasting", status_detail)
dir.create(week_dir, recursive = FALSE, showWarnings = FALSE)

t0 <- Sys.time()
result <- PAGe::run_prospective_pipeline(
  kit,
  current_data = used,
  walk_start = walk_start,
  manual_ign_week = NA_integer_,
  mode = "frozen",
  season = season,
  verbose = TRUE,
  timing_mode = timing_mode
)
elapsed_s <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
saveRDS(result, file.path(week_dir, "weekly_result.rds"))

ign <- result$ign_out %||% list()
ign_weekF <- suppressWarnings(as.integer(ign$ign_week_locked %||% NA_integer_))
ign_decimal <- suppressWarnings(as.numeric(ign$iWeek_hat_lockedF %||% NA_real_))
ignition_status <- if (is.finite(ign_weekF) || is.finite(ign_decimal)) "locked" else "not_detected"
if (is.finite(ign_decimal)) {
  bracket_lo <- max(1, floor(ign_decimal))
  bracket_hi <- min(52, bracket_lo + 1L)
} else if (is.finite(ign_weekF)) {
  bracket_lo <- max(1, ign_weekF)
  bracket_hi <- min(52, ign_weekF + 1L)
} else {
  bracket_lo <- NA_integer_
  bracket_hi <- NA_integer_
}
params_df <- result$params_df
peak_week <- NA_integer_
peak_lo <- NA_real_
peak_hi <- NA_real_
t_peak <- NA_real_
peak_passed <- NA
if (is.data.frame(params_df) && nrow(params_df)) {
  peak_idx <- which.max(params_df$eval_week)
  if (length(peak_idx)) {
    peak_row <- params_df[peak_idx, , drop = FALSE]
    peak_week <- suppressWarnings(as.integer(peak_row$peak_weekF[[1L]]))
    peak_lo <- suppressWarnings(as.numeric(peak_row$peak_weekF_lo[[1L]]))
    peak_hi <- suppressWarnings(as.numeric(peak_row$peak_weekF_hi[[1L]]))
    t_peak <- suppressWarnings(as.numeric(peak_row$t_peak[[1L]]))
    peak_passed <- isTRUE(peak_row$peak_passed[[1L]])
  }
}
ignition_row <- data.frame(
  season = season, forecast_weekF = forecast_week, latest_observed_weekF = latest_observed_week,
  ignition_status = ignition_status, ignition_weekF = ign_weekF,
  ignition_iWeek_hatF = ign_decimal,
  ignition_bracket_lo = bracket_lo, ignition_bracket_hi = bracket_hi,
  peak_passed = peak_passed, peak_weekF = peak_week, peak_weekF_lo = peak_lo,
  peak_weekF_hi = peak_hi, t_peak = t_peak, timing_mode = timing_mode,
  stringsAsFactors = FALSE
)
write_tsv(ignition_row, file.path(week_dir, "ignition.tsv"))

m2_preds <- result$m2_preds
latest <- NULL
if (is.data.frame(m2_preds) && nrow(m2_preds)) {
  ledger <- m2_preds
  ledger$season <- season
  ledger$ignition_status <- ignition_status
  ledger$ignition_iWeek_hatF <- ign_decimal
  ledger$peak_passed <- peak_passed
  ledger$peak_weekF <- peak_week
  write_tsv(ledger, file.path(week_dir, "forecast_ledger.tsv"))
  origin <- max(m2_preds$eval_week, na.rm = TRUE)
  latest <- m2_preds[m2_preds$eval_week == origin, , drop = FALSE]
  latest <- latest[order(latest$h), , drop = FALSE]
} else {
  write_tsv(
    data.frame(eval_week = integer(0), h = integer(0), target_weekF = integer(0)),
    file.path(week_dir, "forecast_ledger.tsv")
  )
}
common <- data.frame(
  ignition_status = ignition_status, ignition_weekF = ign_weekF,
  ignition_iWeek_hatF = ign_decimal,
  ignition_bracket_lo = bracket_lo, ignition_bracket_hi = bracket_hi,
  peak_passed = peak_passed, peak_weekF = peak_week,
  peak_weekF_lo = peak_lo, peak_weekF_hi = peak_hi, t_peak = t_peak,
  stringsAsFactors = FALSE
)
if (!is.null(latest) && nrow(latest)) {
  h1h2 <- data.frame(
    season = season, forecast_weekF = forecast_week, origin_weekF = latest$eval_week,
    target_weekF = latest$target_weekF, h = latest$h,
    m1_p = latest$m1_p, m1_lo = latest$m1_lo, m1_hi = latest$m1_hi,
    m2_p = latest$m2_p, m2_lo = latest$m2_lo, m2_hi = latest$m2_hi,
    forecast_action = latest$forecast_action %||% NA_character_,
    common, stringsAsFactors = FALSE
  )
} else {
  h1h2 <- data.frame(
    season = season, forecast_weekF = forecast_week, origin_weekF = NA_integer_,
    target_weekF = NA_integer_, h = c(1L, 2L),
    m1_p = NA_real_, m1_lo = NA_real_, m1_hi = NA_real_,
    m2_p = NA_real_, m2_lo = NA_real_, m2_hi = NA_real_,
    forecast_action = NA_character_, common,
    stringsAsFactors = FALSE
  )
}
write_tsv(h1h2, file.path(week_dir, "forecast_h1h2.tsv"))

platform <- list(
  captured_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  R_version = R.version.string,
  session_info = utils::sessionInfo(),
  extSoftVersion = extSoftVersion(),
  La_version = La_version(),
  OS = Sys.info(),
  nproc = tryCatch(system2("nproc", stdout = TRUE, stderr = FALSE), error = function(e) NA_character_),
  package_library = package_library,
  environment = Sys.getenv(c("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS")),
  repo_root = repo_root
)
data_files <- if (dir.exists(cache_dir)) {
  list.files(cache_dir, full.names = TRUE)
} else {
  character(0)
}
manifest <- list(
  run_id = run_id,
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  kit_path = kit_path, kit_sha256 = kit_actual_sha256,
  kit_expected_sha256 = kit_expected_sha256,
  season = season, forecast_weekF = forecast_week,
  latest_observed_weekF = latest_observed_week,
  walk_start = walk_start, timing_mode = timing_mode,
  max_staleness_days = staleness_days, observed_week_end_date = as.character(end_date),
  data_source = provenance$source_url_or_path, data_sha256 = provenance$sha256,
  data_retrieved_utc = provenance$retrieved_utc, data_cache_files = data_files,
  package_version = as.character(utils::packageVersion("PAGe")),
  package_path = find.package("PAGe"),
  n_rows_used = nrow(used), elapsed_seconds = elapsed_s,
  ignition = ignition_row, platform = platform
)
saveRDS(manifest, file.path(week_dir, "manifest.rds"))
writeLines(capture.output(print(manifest)), file.path(week_dir, "manifest.txt"))
write_tsv(
  data.frame(
    field = c(
      "source_url_or_path", "retrieved_utc", "data_sha256", "pho_layout",
      "n_weeks", "last_week_end_date"
    ),
    value = c(
      provenance$source_url_or_path %||% NA_character_,
      provenance$retrieved_utc %||% NA_character_,
      provenance$sha256 %||% NA_character_,
      provenance$pho_layout %||% NA_character_,
      as.character(provenance$n_weeks %||% NA_integer_),
      provenance$last_week_end_date %||% NA_character_
    ),
    stringsAsFactors = FALSE
  ),
  file.path(week_dir, "data_provenance.tsv")
)
write_status("complete", sprintf(
  "week_dir=%s elapsed_s=%.0f kit_sha256=%s", week_dir, elapsed_s, kit_actual_sha256
))
cat(sprintf("weekly forecast complete: %s (%.1f s)\n", week_dir, elapsed_s))
q(save = "no", status = 0L)
