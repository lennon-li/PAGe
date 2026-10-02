#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source('scripts/v3_shadow_ops_helpers_v1.R')
source('scripts/v3_shadow_release_helpers_v1.R')

`%||%` <- function(x, y) if (is.null(x)) y else x

.shadow_v2_repo_root <- function() {
  if (!file.exists("PAGe/DESCRIPTION")) {
    stop("Run this script from the PAGe repository root.", call. = FALSE)
  }
  normalizePath(".", winslash = "/", mustWork = TRUE)
}

.shadow_v2_source_package <- function() {
  files <- sort(list.files("PAGe/R", pattern = "[.]R$", full.names = TRUE))
  for (f in files) sys.source(f, envir = .GlobalEnv)
  invisible(files)
}

.shadow_v2_parse_args <- function(args) {
  out <- list(
    season = NULL,
    source = "auto",
    input = NULL,
    typed_panel = NULL,
    transaction_raw_sha256 = NULL,
    transaction_raw_path = NULL,
    release_dir = NULL,
    output_root = "results/weekly-shadow-v2",
    compare_panel = NULL,
    m0_artifact = "artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds",
    m1_artifact = "artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/m1_v2_stage.rds",
    m2_artifact = "artifacts/m2-v2-c2-governed-v1/m2_v2_c2_governed_fit.rds",
    olis_fallback = "../IRVRI/wf_output/olis_snapshot/hist_olis.RData"
  )
  for (arg in args) {
    if (arg %in% c("-h", "--help")) {
      cat(paste0(
        "Usage: Rscript 2026/run_weekly_shadow_v2.R --season=YYYY-YY [options]\n\n",
        "Options:\n",
        "  --source=auto|orvt|olis       Input source mode (default auto)\n",
        "  --input=PATH                  Explicit ORVT CSV or OLIS .RData snapshot\n",
        "  --typed-panel=PATH            Prebuilt typed A/B panel for exact replay/transaction use\n",
        "  --transaction-raw-sha256=SHA  Raw-source SHA supplied by authoritative transaction launcher\n",
        "  --transaction-raw-path=PATH   Archived raw-source path supplied by transaction launcher\n",
        "  --release-dir=PATH            Optional validated v3 release directory for comparison issuance\n",
        "  --output-root=PATH            Run output root\n",
        "  --compare-panel=PATH          Explicit previous typed_ab_weekly.csv\n",
        "  --m0-artifact=PATH            M0-v2 LOSO artifact\n",
        "  --m1-artifact=PATH            M1-v2 full-history stage\n",
        "  --m2-artifact=PATH            Governed M2-v2 artifact\n",
        "  --olis-fallback=PATH          Local OLIS fallback for --source=auto\n"
      ))
      quit(status = 0L)
    }
    if (!grepl("^--[^=]+=", arg)) stop("Unknown argument: ", arg, call. = FALSE)
    key <- sub("^--([^=]+)=.*$", "\\1", arg)
    value <- sub("^--[^=]+=", "", arg)
    key <- gsub("-", "_", key, fixed = TRUE)
    if (!key %in% names(out)) stop("Unknown option --", gsub("_", "-", key), call. = FALSE)
    out[[key]] <- value
  }
  if (is.null(out$season) || !grepl("^[0-9]{4}-[0-9]{2}$", out$season)) {
    stop("--season=YYYY-YY is required.", call. = FALSE)
  }
  if (!out$source %in% c("auto", "orvt", "olis")) {
    stop("--source must be auto, orvt, or olis.", call. = FALSE)
  }
  if (!is.null(out$typed_panel) && nzchar(out$typed_panel) && !is.null(out$input) && nzchar(out$input)) {
    stop("Use either --typed-panel or --input, not both.", call. = FALSE)
  }
  out
}

.shadow_v2_sha256 <- function(path) {
  digest::digest(file = path, algo = "sha256")
}

.shadow_v2_copy_source <- function(path, data_cache, label = NULL) {
  if (!file.exists(path)) stop("Input file does not exist: ", path, call. = FALSE)
  dir.create(data_cache, recursive = TRUE, showWarnings = FALSE)
  hash <- .shadow_v2_sha256(path)
  ext <- tools::file_ext(path)
  stem <- label %||% tools::file_path_sans_ext(basename(path))
  dest <- file.path(data_cache, paste0(stem, "_", hash, if (nzchar(ext)) paste0(".", ext) else ""))
  if (!file.exists(dest) && !file.copy(path, dest, overwrite = FALSE)) {
    stop("Could not archive input vintage `", path, "`.", call. = FALSE)
  }
  normalizePath(dest, winslash = "/", mustWork = TRUE)
}

.shadow_v2_fetch_orvt <- function(season, data_cache) {
  candidates <- c(
    paste0("ORVT_Lab_Testing_Data_", .orvt_previous_season(season), "_", season, ".csv"),
    paste0("ORVT_Lab_Testing_Data_", season, "_", .orvt_next_season(season), ".csv")
  )
  base <- sub("/+$", "", .pho_orvt_base_url())
  errors <- character()
  for (candidate in candidates) {
    url <- paste0(base, "/", candidate)
    got <- tryCatch(.orvt_read_source(url, cache_dir = NULL), error = identity)
    if (inherits(got, "error")) {
      errors <- c(errors, paste0(url, ": ", conditionMessage(got)))
      next
    }
    dir.create(data_cache, recursive = TRUE, showWarnings = FALSE)
    dest <- file.path(data_cache, paste0("orvt_live_", got$hash, ".csv"))
    if (!file.exists(dest)) writeBin(got$bytes, dest)
    return(list(
      mode = "orvt",
      path = normalizePath(dest, winslash = "/", mustWork = TRUE),
      original = url,
      sha256 = got$hash,
      fallback_reason = NA_character_
    ))
  }
  stop("No readable live PHO ORVT feed. ", paste(errors, collapse = " | "), call. = FALSE)
}

.shadow_v2_resolve_source <- function(opts, data_cache) {
  if (!is.null(opts$input) && nzchar(opts$input)) {
    path <- normalizePath(opts$input, winslash = "/", mustWork = TRUE)
    mode <- if (tolower(tools::file_ext(path)) %in% c("rdata", "rda")) "olis" else "orvt"
    if (opts$source != "auto" && !identical(opts$source, mode)) {
      stop("--source=", opts$source, " conflicts with input extension for `", path, "`.", call. = FALSE)
    }
    archived <- .shadow_v2_copy_source(path, data_cache, label = paste0(mode, "_input"))
    return(list(
      mode = mode, path = archived, original = path,
      sha256 = .shadow_v2_sha256(archived), fallback_reason = NA_character_
    ))
  }

  if (opts$source %in% c("auto", "orvt")) {
    live <- tryCatch(.shadow_v2_fetch_orvt(opts$season, data_cache), error = identity)
    if (!inherits(live, "error")) return(live)
    if (opts$source == "orvt") stop(conditionMessage(live), call. = FALSE)
    live_error <- conditionMessage(live)
  } else {
    live_error <- NA_character_
  }

  if (!file.exists(opts$olis_fallback)) {
    stop(
      "Live ORVT unavailable and OLIS fallback missing. ORVT error: ", live_error,
      "; fallback: ", opts$olis_fallback,
      call. = FALSE
    )
  }
  original <- normalizePath(opts$olis_fallback, winslash = "/", mustWork = TRUE)
  archived <- .shadow_v2_copy_source(original, data_cache, label = "olis_input")
  list(
    mode = "olis", path = archived, original = original,
    sha256 = .shadow_v2_sha256(archived), fallback_reason = live_error
  )
}

.shadow_v2_panel_from_orvt <- function(path, season) {
  a <- getCurrentD(
    data = path, virus = "Influenza A", season = season,
    include_predecessor = FALSE
  )
  b <- getCurrentD(
    data = path, virus = "Influenza B", season = season,
    include_predecessor = FALSE
  )
  a <- a[a$season == season, , drop = FALSE]
  b <- b[b$season == season, , drop = FALSE]
  if (!identical(a$weekF, b$weekF)) {
    stop("ORVT A/B weekF coverage differs; refusing a misaligned typed panel.", call. = FALSE)
  }
  if (!all(a$week_start_date == b$week_start_date)) {
    stop("ORVT A/B week-start dates differ; refusing a misaligned typed panel.", call. = FALSE)
  }
  data.frame(
    season = season,
    weekF = a$weekF,
    week_start_date = as.character(a$week_start_date),
    week_end_date = as.character(a$week_end_date),
    y_A = a$y,
    N_A = a$N,
    p_A = a$p,
    y_B = b$y,
    N_B = b$N,
    p_B = b$p,
    denominator_regime = "orvt_type_specific",
    stringsAsFactors = FALSE
  )
}

.shadow_v2_aggregate_olis_type <- function(x, season) {
  required <- c("date", "pos", "tests")
  if (!is.data.frame(x) || !all(required %in% names(x))) {
    stop("OLIS snapshot type data must contain date, pos, tests.", call. = FALSE)
  }
  x$date <- as.Date(x$date)
  if (anyNA(x$date)) stop("OLIS snapshot contains invalid dates.", call. = FALSE)
  daily <- stats::aggregate(cbind(pos, tests) ~ date, data = x, FUN = sum)
  cal <- page_season_calendar(dates = daily$date)
  daily$season <- cal$season
  daily$weekF <- cal$weekF
  daily <- daily[daily$season == season, , drop = FALSE]
  if (!nrow(daily)) stop("OLIS snapshot contains no rows for season `", season, "`.", call. = FALSE)
  counts <- stats::aggregate(cbind(pos, tests) ~ season + weekF, data = daily, FUN = sum)
  dates <- stats::aggregate(date ~ season + weekF, data = daily, FUN = min)
  out <- merge(counts, dates, by = c("season", "weekF"), sort = TRUE)
  out$p <- out$pos / out$tests
  out
}

.shadow_v2_panel_from_olis <- function(path, season) {
  env <- new.env(parent = emptyenv())
  loaded <- load(path, envir = env)
  if (!"r" %in% loaded || !is.list(env$r) ||
      !all(c("fluA", "fluB") %in% names(env$r))) {
    stop("OLIS snapshot must contain `r$fluA` and `r$fluB`.", call. = FALSE)
  }
  a <- .shadow_v2_aggregate_olis_type(env$r$fluA, season)
  b <- .shadow_v2_aggregate_olis_type(env$r$fluB, season)
  m <- merge(a, b, by = c("season", "weekF"), suffixes = c("_A", "_B"), sort = TRUE)
  if (!nrow(m)) stop("No overlapping A/B OLIS weeks for season `", season, "`.", call. = FALSE)
  if (nrow(m) != nrow(a) || nrow(m) != nrow(b)) {
    stop("OLIS A/B week coverage differs; refusing a misaligned typed panel.", call. = FALSE)
  }
  if (!all(m$date_A == m$date_B)) {
    stop("OLIS A/B weekly dates differ; refusing a misaligned typed panel.", call. = FALSE)
  }
  data.frame(
    season = m$season,
    weekF = m$weekF,
    week_start_date = as.character(m$date_A),
    week_end_date = as.character(m$date_A + 6),
    y_A = m$pos_A,
    N_A = m$tests_A,
    p_A = m$p_A,
    y_B = m$pos_B,
    N_B = m$tests_B,
    p_B = m$p_B,
    # Modern OLIS is the same type-specific testing regime represented by ORVT.
    denominator_regime = "orvt_type_specific",
    stringsAsFactors = FALSE
  )
}

.shadow_v2_resolve_panel <- function(opts, data_cache) {
  if (!is.null(opts$typed_panel) && nzchar(opts$typed_panel)) {
    original <- normalizePath(opts$typed_panel,winslash='/',mustWork=TRUE)
    archived <- .shadow_v2_copy_source(original,data_cache,label='typed_panel_input')
    panel <- utils::read.csv(archived,stringsAsFactors=FALSE,check.names=FALSE)
    .shadow_ops_validate_panel(panel,opts$season,require_forecast_support=FALSE)
    return(list(
      panel=panel,
      source=list(mode='typed_panel',path=archived,original=original,sha256=.shadow_v2_sha256(archived),fallback_reason=NA_character_)
    ))
  }
  src <- .shadow_v2_resolve_source(opts,data_cache)
  panel <- if (src$mode=='olis') .shadow_v2_panel_from_olis(src$path,opts$season) else .shadow_v2_panel_from_orvt(src$path,opts$season)
  panel <- panel[order(panel$weekF),,drop=FALSE]
  .shadow_ops_validate_panel(panel,opts$season,require_forecast_support=FALSE)
  list(panel=panel,source=src)
}

.shadow_v2_revision_audit <- function(current, previous) {
  cols <- c("weekF", "y_A", "N_A", "p_A", "y_B", "N_B", "p_B")
  if (!all(cols %in% names(previous))) {
    stop("Previous panel lacks required A/B columns for revision audit.", call. = FALSE)
  }
  m <- merge(
    previous[, cols], current[, cols], by = "weekF",
    suffixes = c("_previous", "_current"), sort = TRUE
  )
  if (!nrow(m)) return(m)
  for (nm in c("y_A", "N_A", "p_A", "y_B", "N_B", "p_B")) {
    m[[paste0("delta_", nm)]] <- m[[paste0(nm, "_current")]] - m[[paste0(nm, "_previous")]]
  }
  m$revised_A <- m$delta_y_A != 0 | m$delta_N_A != 0
  m$revised_B <- m$delta_y_B != 0 | m$delta_N_B != 0
  m
}

.shadow_v2_find_previous_panel <- function(output_root, season, current_run_dir) {
  season_root <- file.path(output_root, season)
  if (!dir.exists(season_root)) return(NULL)
  candidates <- list.files(season_root, pattern = "typed_ab_weekly[.]csv$", recursive = TRUE, full.names = TRUE)
  candidates <- candidates[!startsWith(normalizePath(candidates, winslash = "/", mustWork = FALSE),
                                        normalizePath(current_run_dir, winslash = "/", mustWork = FALSE))]
  if (!length(candidates)) return(NULL)
  info <- file.info(candidates)
  candidates[order(info$mtime, decreasing = TRUE)][1L]
}

.shadow_v2_write_kv <- function(path, x) {
  df <- data.frame(
    key = names(x),
    value = vapply(x, function(v) paste(v, collapse = ";"), character(1L)),
    stringsAsFactors = FALSE
  )
  utils::write.table(df, path, sep = "\t", quote = FALSE, row.names = FALSE)
}

.shadow_v2_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  .shadow_v2_repo_root()
  opts <- .shadow_v2_parse_args(args)
  .shadow_v2_source_package()

  release_info <- if (!is.null(opts$release_dir) && nzchar(opts$release_dir)) .v3_release_validate(opts$release_dir) else NULL

  required_artifacts <- c(opts$m0_artifact, opts$m1_artifact, opts$m2_artifact)
  missing <- required_artifacts[!file.exists(required_artifacts)]
  if (length(missing)) stop("Missing governed shadow artifact(s): ", paste(missing, collapse = ", "), call. = FALSE)

  stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  provisional_dir <- file.path(opts$output_root, opts$season, paste0(stamp, "-pending"))
  dir.create(file.path(provisional_dir, "data_cache"), recursive = TRUE, showWarnings = FALSE)

  got <- .shadow_v2_resolve_panel(opts,file.path(provisional_dir,"data_cache"))
  panel <- got$panel
  source_info <- got$source
  origin <- max(as.integer(panel$weekF))
  .shadow_ops_validate_panel(panel,opts$season,require_forecast_support=origin>=13L)
  effective_panel_sha256 <- .shadow_ops_effective_panel_sha256(panel,opts$season)
  supplied_typed_panel_sha256 <- if (identical(source_info$mode,'typed_panel')) source_info$sha256 else NA_character_
  raw_source_sha256 <- if (identical(source_info$mode,'typed_panel')) opts$transaction_raw_sha256 else source_info$sha256
  raw_source_path <- if (identical(source_info$mode,'typed_panel')) opts$transaction_raw_path else source_info$path
  final_dir <- file.path(opts$output_root, opts$season, paste0(stamp, "-weekF", sprintf("%02d", origin)))
  if (dir.exists(final_dir)) stop("Shadow run directory already exists: ", final_dir, call. = FALSE)
  if (!file.rename(provisional_dir, final_dir)) stop("Could not finalize shadow run directory.", call. = FALSE)
  source_info$path <- file.path(final_dir, "data_cache", basename(source_info$path))

  utils::write.csv(panel, file.path(final_dir, "typed_ab_weekly.csv"), row.names = FALSE)

  previous_path <- opts$compare_panel
  if (is.null(previous_path) || !nzchar(previous_path)) {
    previous_path <- .shadow_v2_find_previous_panel(opts$output_root, opts$season, final_dir)
  }
  revision_summary <- list(
    previous_panel = NA_character_, overlap_weeks = 0L,
    revised_A_weeks = 0L, revised_B_weeks = 0L,
    max_abs_A_revision_pp = 0, max_abs_B_revision_pp = 0
  )
  if (!is.null(previous_path) && file.exists(previous_path)) {
    previous <- utils::read.csv(previous_path, stringsAsFactors = FALSE)
    audit <- .shadow_v2_revision_audit(panel, previous)
    utils::write.csv(audit, file.path(final_dir, "revision_audit.csv"), row.names = FALSE)
    revision_summary <- list(
      previous_panel = normalizePath(previous_path, winslash = "/", mustWork = TRUE),
      overlap_weeks = nrow(audit),
      revised_A_weeks = if (nrow(audit)) sum(audit$revised_A) else 0L,
      revised_B_weeks = if (nrow(audit)) sum(audit$revised_B) else 0L,
      max_abs_A_revision_pp = if (nrow(audit)) 100 * max(abs(audit$delta_p_A)) else 0,
      max_abs_B_revision_pp = if (nrow(audit)) 100 * max(abs(audit$delta_p_B)) else 0
    )
  }
  .shadow_v2_write_kv(file.path(final_dir, "revision_summary.tsv"), revision_summary)

  m0_art <- readRDS(opts$m0_artifact)
  params <- m0_art$best_params
  if (!identical(params$use_cls, FALSE) || !identical(params$w_min, 12L) ||
      !identical(params$raw_nondec_n, 3L) || !isTRUE(all.equal(params$raw_drop_se_tol, 1.0))) {
    stop("M0 artifact does not match frozen v2 policy (classifier off, w_min=12, raw3, 1-SE).", call. = FALSE)
  }
  a_current <- data.frame(
    season = panel$season, weekF = panel$weekF,
    y = panel$y_A, N = panel$N_A, p = panel$p_A,
    stringsAsFactors = FALSE
  )
  m0_det <- detectIgnitionBySeason_M0v2_timing(
    a_current, params, verbose = FALSE, iWeek = FALSE, validate_support = FALSE
  )
  by <- m0_det$by_season[1L, , drop = FALSE]
  ignited <- !isTRUE(by$detection_failed)
  m0_result <- list(
    ign_out = m0_det,
    iWeek_locked = if (ignited) as.numeric(by$iWeek_hat) else NA_real_,
    iWeek_lockedF = if (ignited) as.numeric(by$iWeek_hatF) else NA_real_,
    overridden = FALSE
  )
  utils::write.csv(m0_det$data, file.path(final_dir, "m0_signals.csv"), row.names = FALSE)
  utils::write.csv(by, file.path(final_dir, "m0_detection.csv"), row.names = FALSE)

  m1_stage <- readRDS(opts$m1_artifact)
  m1_out <- run_m1_v2_timing(
    list(m1_v2 = m1_stage), a_current, m0_result, verbose = FALSE
  )
  saveRDS(m1_out, file.path(final_dir, "m1_v2_runtime.rds"))
  if (is.data.frame(m1_out$timing_df) && nrow(m1_out$timing_df)) {
    utils::write.csv(m1_out$timing_df, file.path(final_dir, "m1_v2_timing.csv"), row.names = FALSE)
  }

  m2_art <- readRDS(opts$m2_artifact)
  m2_out <- run_m2_v2_c2_governed_runtime(
    m2_art, panel, origin,
    a_handoff = m1_out$m2_handoff,
    b_handoff = NULL,
    b_gate_review = NULL
  )
  saveRDS(m2_out, file.path(final_dir, "m2_v2_runtime.rds"))
  utils::write.csv(m2_out$predictions, file.path(final_dir, "m2_v2_predictions.csv"), row.names = FALSE)

  forecast <- m2_out$predictions
  forecast$forecast_pct <- 100 * forecast$pred_selected
  forecast$current_stabilized_pct <- 100 * forecast$p_star
  keep <- c(
    "type", "horizon", "current_stabilized_pct", "forecast_pct",
    "c2_applied", "timing_used", "fallback_reason", "model_artifact_id"
  )
  utils::write.table(
    forecast[, keep, drop = FALSE], file.path(final_dir, "forecast_summary.tsv"),
    sep = "\t", quote = FALSE, row.names = FALSE
  )

  m0_sha <- .shadow_v2_sha256(opts$m0_artifact)
  m1_sha <- .shadow_v2_sha256(opts$m1_artifact)
  m2_sha <- .shadow_v2_sha256(opts$m2_artifact)
  provenance <- list(
    run_utc = stamp,
    season = opts$season,
    origin_weekF = origin,
    latest_week_start = tail(panel$week_start_date, 1L),
    latest_week_end = tail(panel$week_end_date, 1L),
    source_mode = source_info$mode,
    source_original = source_info$original,
    source_archived = source_info$path,
    source_sha256 = source_info$sha256,
    raw_source_path = raw_source_path %||% NA_character_,
    raw_source_sha256 = raw_source_sha256 %||% NA_character_,
    supplied_typed_panel_sha256 = supplied_typed_panel_sha256,
    effective_panel_sha256 = effective_panel_sha256,
    release_dir = opts$release_dir %||% NA_character_,
    release_id = if (is.null(release_info)) NA_character_ else release_info$release_id,
    source_fallback_reason = source_info$fallback_reason %||% NA_character_,
    m0_artifact_path = opts$m0_artifact,
    m0_artifact_sha256 = m0_sha,
    m0_policy = "w_min12_raw3_1se_classifier_off",
    m1_artifact_path = opts$m1_artifact,
    m1_artifact_id = m1_stage$artifact_id,
    m1_artifact_sha256 = m1_sha,
    m2_artifact_path = opts$m2_artifact,
    m2_artifact_id = m2_art$artifact_id,
    m2_artifact_sha256 = m2_sha,
    b_gate_review = "closed_pending_review"
  )
  .shadow_v2_write_kv(file.path(final_dir, "provenance.tsv"), provenance)

  status <- list(
    season = opts$season,
    origin_weekF = origin,
    m0_ignited = ignited,
    m0_iWeek = if (ignited) by$iWeek_hat else NA,
    m0_iWeekF = if (ignited) by$iWeek_hatF else NA,
    m1_status = m1_out$status,
    m2_status = m2_out$status,
    A_h1_pct = 100 * forecast$pred_selected[forecast$type == "A" & forecast$horizon == 1L],
    A_h2_pct = 100 * forecast$pred_selected[forecast$type == "A" & forecast$horizon == 2L],
    B_h1_pct = 100 * forecast$pred_selected[forecast$type == "B" & forecast$horizon == 1L],
    B_h2_pct = 100 * forecast$pred_selected[forecast$type == "B" & forecast$horizon == 2L]
  )
  .shadow_v2_write_kv(file.path(final_dir, "status.tsv"), status)

  cat("PAGe v2 weekly shadow complete\n")
  cat("run_dir:", normalizePath(final_dir, winslash = "/", mustWork = TRUE), "\n")
  cat("season:", opts$season, " origin weekF:", origin, "\n")
  cat("M0 ignited:", ignited, " M1:", m1_out$status, "\n")
  print(forecast[, c("type", "horizon", "forecast_pct", "c2_applied", "timing_used", "fallback_reason")], row.names = FALSE, digits = 7)

  invisible(list(
    run_dir = final_dir, panel = panel, m0 = m0_det,
    m1 = m1_out, m2 = m2_out, provenance = provenance
  ))
}

if (sys.nframe() == 0L) {
  .shadow_v2_main(commandArgs(trailingOnly = TRUE))
}
