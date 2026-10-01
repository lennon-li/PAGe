#!/usr/bin/env Rscript

# Install the current PAGe source, then run this file again as a fresh worker.
# The worker only uses library(PAGe); it never sources package code or pkgload.
args <- commandArgs(trailingOnly = TRUE)
worker <- "--worker" %in% args
value_of <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
repo <- normalizePath(getwd(), mustWork = TRUE)
out_dir <- normalizePath(value_of("--out", file.path(repo, "output", "api-installed-smoke-20260910-r2")), mustWork = FALSE)
lib_dir <- file.path(out_dir, "library")
if (!worker && dir.exists(out_dir)) {
  stop("Refusing to reuse an existing smoke output directory: ", out_dir)
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(lib_dir, recursive = TRUE, showWarnings = FALSE)
source_files <- sort(list.files(file.path(repo, "PAGe"), recursive = TRUE, full.names = TRUE))
source_files <- source_files[file.info(source_files)$isdir %in% FALSE]
source_hashes <- data.frame(
  file = sub(paste0("^", normalizePath(repo), "/"), "", source_files),
  sha256 = vapply(source_files, digest::digest, character(1), file = TRUE, algo = "sha256"),
  stringsAsFactors = FALSE
)
write.csv(source_hashes, file.path(out_dir, "source-hashes.csv"), row.names = FALSE)
install_log <- file.path(out_dir, "install.log")
worker_log <- file.path(out_dir, "worker.log")
timing_file <- file.path(out_dir, "timings.csv")
evidence_file <- file.path(out_dir, "evidence.rds")
report_file <- file.path(out_dir, "evidence-report.md")

if (!worker) {
  r_bin <- Sys.which("R")
  rs_bin <- Sys.which("Rscript")
  install_start <- Sys.time()
  install_status <- system2(r_bin, c("CMD", "INSTALL", "--no-multiarch", "--with-keep.source", "-l", lib_dir, file.path(repo, "PAGe")), stdout = install_log, stderr = install_log, timeout = 180)
  install_seconds <- as.numeric(difftime(Sys.time(), install_start, units = "secs"))
  worker_status <- NA_integer_
  if (identical(install_status, 0L)) {
    script_path <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1L])
    worker_status <- system2(rs_bin, c("--vanilla", normalizePath(script_path), "--worker", "--out", out_dir, "--lib", lib_dir), stdout = worker_log, stderr = worker_log, timeout = 720)
  } else {
    writeLines("Worker was not launched because R CMD INSTALL failed.", worker_log)
  }
  evidence <- if (file.exists(evidence_file)) readRDS(evidence_file) else list()
  timings <- if (file.exists(timing_file)) read.csv(timing_file, stringsAsFactors = FALSE) else data.frame()
  `%||%` <- function(x, y) if (is.null(x)) y else x
  line <- function(x) paste0("- ", x)
  current_source_files <- sort(list.files(file.path(repo, "PAGe"), recursive = TRUE, full.names = TRUE))
  current_source_files <- current_source_files[file.info(current_source_files)$isdir %in% FALSE]
  current_source_hashes <- data.frame(
    file = sub(paste0("^", normalizePath(repo), "/"), "", current_source_files),
    sha256 = vapply(current_source_files, digest::digest, character(1), file = TRUE, algo = "sha256"),
    stringsAsFactors = FALSE
  )
  source_comparison <- merge(
    source_hashes,
    current_source_hashes,
    by = "file",
    all = TRUE,
    suffixes = c("_snapshot", "_current")
  )
  evidence$source_file_count <- nrow(source_hashes)
  evidence$source_missing_count <- sum(is.na(source_comparison$sha256_current))
  evidence$source_unexpected_count <- sum(is.na(source_comparison$sha256_snapshot))
  evidence$source_hash_mismatch_count <- sum(
    !is.na(source_comparison$sha256_snapshot) &
      !is.na(source_comparison$sha256_current) &
      source_comparison$sha256_snapshot != source_comparison$sha256_current
  )
  evidence$source_hash_match <- evidence$source_missing_count == 0L &&
    evidence$source_unexpected_count == 0L &&
    evidence$source_hash_mismatch_count == 0L
  saveRDS(evidence, evidence_file)
  warning_rows <- evidence$warnings %||% data.frame()
  warning_summary <- if (nrow(warning_rows)) {
    unique(warning_rows[c("stage", "message", "condition_call", "classification")])
  } else {
    data.frame()
  }
  markdown_cell <- function(x) {
    x <- gsub("[\r\n]+", " ", as.character(x))
    gsub("\\|", "\\\\|", x)
  }
  warning_table <- if (nrow(warning_summary)) {
    c(
      "| Stage | Count | Classification | Message | Condition call |",
      "|---|---:|---|---|---|",
      vapply(seq_len(nrow(warning_summary)), function(i) {
        key_match <- warning_rows$stage == warning_summary$stage[[i]] &
          warning_rows$message == warning_summary$message[[i]] &
          warning_rows$condition_call == warning_summary$condition_call[[i]] &
          warning_rows$classification == warning_summary$classification[[i]]
        paste0(
          "| ", markdown_cell(warning_summary$stage[[i]]),
          " | ", sum(key_match),
          " | ", markdown_cell(warning_summary$classification[[i]]),
          " | ", markdown_cell(warning_summary$message[[i]]),
          " | `", markdown_cell(warning_summary$condition_call[[i]]), "` |"
        )
      }, character(1))
    )
  } else {
    "- No worker warnings were recorded."
  }
  report <- c(
    "# Installed-package API smoke evidence", "",
    line(paste0("Date: `", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "`")),
    line(paste0("Repository: `", repo, "`")),
    line(paste0("Isolated library: `", normalizePath(lib_dir, mustWork = FALSE), "`")),
    line(paste0("Install exit status: `", install_status, "`; seconds: `", sprintf("%.2f", install_seconds), "`")),
    line(paste0("Fresh worker exit status: `", worker_status, "`")),
    line(paste0("Library path verified: `", isTRUE(evidence$library_path_verified), "`; exports verified: `", isTRUE(evidence$exports_verified), "`")), "",
    "## Process and exact calls", "",
    "The source was installed by `R CMD INSTALL` and the workflow ran in a fresh `Rscript --vanilla` process using `library(PAGe)`. No package source was sourced and `pkgload` was not used.", "",
    if (length(evidence$calls)) paste0("- `", evidence$calls, "`") else "- none recorded", "",
    "## Training, holdout, and results", "",
    line(paste0("Synthetic seasons: `", paste(evidence$seasons %||% character(), collapse = ", "), "`")),
    line(paste0("Training seasons: `", paste(evidence$training_seasons %||% character(), collapse = ", "), "`")),
    line(paste0("Holdout season: `", paste(evidence$holdout_seasons %||% character(), collapse = ", "), "`")),
    line(paste0("Rows: training `", evidence$training_rows %||% NA, "`; holdout `", evidence$holdout_rows %||% NA, "`")),
    line(paste0("M1 peak rows: `", evidence$m1_peak_rows %||% NA, "`; M2 rows: `", evidence$m2_rows %||% NA, "`; horizons: `", paste(evidence$m2_horizons %||% character(), collapse = ", "), "`")),
    line(paste0("M2 point forecasts with NA intervals: `", isTRUE(evidence$m2_intervals_na), "`")),
    line(paste0("Denominator-weighted comparison matched rows: `", evidence$comparison_rows %||% NA, "`")),
    line(paste0("Serialization/reload: `", isTRUE(evidence$serialization_verified), "`; unseen-prefix invariance: `", isTRUE(evidence$prefix_invariant), "`")), "",
    "## Warning evidence", "",
    line(paste0("Total worker warnings: `", evidence$warning_total %||% 0L, "`; unique stage/message/call warnings: `", evidence$warning_unique %||% 0L, "`")),
    warning_table, "",
    "Warnings classified as `expected numerical/model diagnostic` are emitted by numerical fitting or prediction routines on this small synthetic fixture. Any `possible API defect`, `possible integrity/data-leak problem`, or `requires manual review` row must be treated as unresolved until inspected.", "",
    "## Governed M2 subset", "",
    line(paste0("Grid IDs: `", paste(evidence$subset_grid_ids %||% character(), collapse = ", "), "`")),
    line(paste0("Selected terms: `", evidence$selected_terms %||% "not recorded", "`")),
    line(paste0("Tuning validation: `", isTRUE(evidence$subset_tuning_validated), "`; fit/freeze: `", evidence$subset_fit_status %||% "not recorded", "`")), "",
    "## Timings", "",
    if (nrow(timings)) paste0("- `", timings$stage, "`: ", sprintf("%.2f", timings$seconds), " s (", timings$status, ")") else "- none recorded", "",
    "## Source integrity", "",
    line(paste0("Package source files: `", evidence$source_file_count, "`; missing: `", evidence$source_missing_count, "`; unexpected: `", evidence$source_unexpected_count, "`; hash mismatches: `", evidence$source_hash_mismatch_count, "`; exact match: `", isTRUE(evidence$source_hash_match), "`")), "",
    "## Limitations", "",
    "One bounded synthetic workflow only: no historical retuning, BCC, comprehensive tuning, or publication claim. The governed grid includes all-off and horizon-intercept candidates; its selected terms document API execution, not promotion.", "",
    "## Failure detail", "",
    if (length(evidence$failure)) line(evidence$failure) else "- none recorded"
  )
  writeLines(unlist(report), report_file)
  quit(status = if (identical(install_status, 0L) && identical(worker_status, 0L)) 0L else 1L)
}

`%||%` <- function(x, y) if (is.null(x)) y else x
.libPaths(c(normalizePath(value_of("--lib", lib_dir), mustWork = TRUE), .libPaths()))
evidence <- list(calls = character(), assertions = character(), failure = character(), library_path_verified = FALSE, exports_verified = FALSE, subset_tuning_validated = FALSE, serialization_verified = FALSE, prefix_invariant = FALSE, warnings = data.frame(stage = character(), message = character(), condition_call = character(), condition_class = character(), classification = character(), stringsAsFactors = FALSE), warning_total = 0L, warning_unique = 0L)
timings <- data.frame(stage = character(), seconds = numeric(), status = character(), stringsAsFactors = FALSE)
current_stage <- "worker setup"
record_call <- function(x) evidence$calls <<- c(evidence$calls, x)
assert <- function(ok, label) {
  if (!isTRUE(ok)) stop("ASSERTION FAILED: ", label, call. = FALSE)
  evidence$assertions <<- c(evidence$assertions, paste0(label, " (passed)"))
}
stage <- function(name, expr, elapsed_limit = 360) {
  previous_stage <- current_stage
  current_stage <<- name
  on.exit(current_stage <<- previous_stage, add = TRUE)
  started <- proc.time()[["elapsed"]]
  result <- tryCatch(
    {
      setTimeLimit(elapsed = elapsed_limit, transient = TRUE)
      on.exit(setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE), add = TRUE)
      force(expr)
    },
    error = function(e) stop(e)
  )
  timings <<- rbind(timings, data.frame(stage = name, seconds = proc.time()[["elapsed"]] - started, status = "passed", stringsAsFactors = FALSE))
  result
}
save_evidence <- function() {
  evidence$warning_total <- nrow(evidence$warnings)
  evidence$warning_unique <- if (nrow(evidence$warnings)) {
    nrow(unique(evidence$warnings[c("stage", "message", "condition_call")]))
  } else {
    0L
  }
  write.csv(timings, timing_file, row.names = FALSE)
  saveRDS(evidence, evidence_file)
}
classify_warning <- function(message) {
  if (identical(message, "collapsing to unique 'x' values")) {
    return("API defect: duplicate interpolation coordinates")
  }
  if (grepl("integrity|tamper|hash|data[ -]?leak|holdout.*train|train.*holdout", message, ignore.case = TRUE)) {
    return("possible integrity/data-leak problem")
  }
  if (grepl("deprecated|unknown|unused argument|missing|required|mismatch|contract|invalid|failed", message, ignore.case = TRUE)) {
    return("possible API defect")
  }
  if (grepl("converg|rank.deficien|singular|basis dimension|iteration|step fail|NaNs produced|fitted probabilit|not positive definite|numerical|model matrix", message, ignore.case = TRUE)) {
    return("expected numerical/model diagnostic")
  }
  "requires manual review"
}
record_warning <- function(w) {
  warning_call <- conditionCall(w)
  call_text <- if (is.null(warning_call)) {
    "<none>"
  } else {
    paste(deparse(warning_call, width.cutoff = 500L), collapse = " ")
  }
  message <- conditionMessage(w)
  evidence$warnings <<- rbind(
    evidence$warnings,
    data.frame(
      stage = current_stage,
      message = message,
      condition_call = call_text,
      condition_class = paste(class(w), collapse = "/"),
      classification = classify_warning(message),
      stringsAsFactors = FALSE
    )
  )
  invokeRestart("muffleWarning")
}
on.exit(save_evidence(), add = TRUE)

withCallingHandlers(tryCatch(
  {
    record_call(".libPaths(isolated_library); library(PAGe)")
    suppressPackageStartupMessages(library(PAGe))
    expected_package_path <- normalizePath(
      file.path(value_of("--lib", lib_dir), "PAGe"),
      mustWork = TRUE
    )
    loaded_package_path <- normalizePath(find.package("PAGe"), mustWork = TRUE)
    evidence$library_path_verified <- identical(loaded_package_path, expected_package_path)
    evidence$loaded_package_path <- loaded_package_path
    evidence$expected_package_path <- expected_package_path
    assert(evidence$library_path_verified, "PAGe was loaded from the isolated install")
    required_exports <- c("prepare_page_data", "simulate_flu_seasons", "train_pipeline", "validate_season_selection", "fit_m0", "freeze_m0", "fit_m1", "freeze_m1", "tune_m2", "validate_m2_tuning", "fit_m2", "freeze_m2", "assemble_kit", "run_pipeline", "compare_m1_m2")
    evidence$exports_verified <- all(required_exports %in% getNamespaceExports("PAGe"))
    assert(evidence$exports_verified, "required exports are present")
    record_call("set.seed(20260909); simulate_flu_seasons(S=4L, weeks=1:52, seed=20260909)")
    raw <- stage("synthetic data generation", {
      set.seed(20260909)
      sim <- simulate_flu_seasons(S = 4L, weeks = 1:52, seed = 20260909)
      data.frame(source_season = paste0("syn-", as.character(sim$season)), source_week = sim$newWeek, source_positive = sim$y, source_total = sim$y + sim$neg, stringsAsFactors = FALSE)
    })
    record_call("prepare_page_data(raw, outcome_col='source_positive', week_col='source_week', season_col='source_season', total_col='source_total', week_type='within_season')")
    dat <- stage("public data preparation", prepare_page_data(raw, outcome_col = "source_positive", week_col = "source_week", season_col = "source_season", total_col = "source_total", week_type = "within_season"))
    evidence$seasons <- sort(unique(as.character(dat$season)))
    evidence$holdout_seasons <- tail(evidence$seasons, 1L)
    evidence$training_seasons <- head(evidence$seasons, -1L)
    evidence$training_rows <- sum(dat$season %in% evidence$training_seasons)
    evidence$holdout_rows <- sum(dat$season %in% evidence$holdout_seasons)
    assert(nrow(dat) == 208L, "prepared synthetic data has 208 unique weekly rows")
    assert(all(c("season", "weekF", "y", "N", "p", "neg") %in% names(dat)), "canonical data contract is present")
    m0_params <- list(cls_thr = 0.26, p_thr = 0.005, prev_thr = 0.001, p_sum_thr = 0.06, eps = 0, n_consec = 5L, L = 2L, K_sum = 5L, N_req = 4L, w_min = 13L, w_max = 26L)
    flag_args <- list(p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L, min_window = 10L, w_min = 21L, w_max = 21L, d2_relax = -0.01)
    m1_params <- m1_make_params(k_ref = 10L, ref_method = "fs", temperature = 0.25, rise_weight = 1, trough_weight = 0.1, peak_decay = 0.3, slope_weight = 8, slope_window = 6L, dynamic_temp = FALSE, spread_method = "between")
    record_call("validate_season_selection(dat, training_seasons, holdout_seasons)")
    selection <- stage("explicit season selection", validate_season_selection(dat, training_seasons = evidence$training_seasons, holdout_seasons = evidence$holdout_seasons))
    record_call("freeze_m0(fit_m0(dat, selection, config=m0_params, flag_args=flag_args))")
    m0 <- stage("governed M0 fit/freeze", freeze_m0(fit_m0(dat, selection, config = m0_params, flag_args = flag_args)))
    record_call("freeze_m1(fit_m1(dat, selection, m0=m0, config=m1_params))")
    m1 <- stage("governed M1 fit/freeze", freeze_m1(fit_m1(dat, selection, m0 = m0, config = m1_params)), elapsed_limit = 360)
    assert(identical(m0$status, "frozen") && identical(m1$status, "frozen"), "M0 and M1 are frozen before governed M2")
    subset_grid <- data.frame(intercept = c(FALSE, TRUE), z = c(FALSE, FALSE), u = c(FALSE, FALSE), d = c(FALSE, FALSE), stringsAsFactors = FALSE)
    record_call("tune_m2(dat, selection, m0, m1, grid=subset_grid, family='offset_subset_v1', n_cores=1L)")
    tuning <- stage("governed M2 subset tuning", tune_m2(dat, selection = selection, m0 = m0, m1 = m1, grid = subset_grid, family = "offset_subset_v1", n_cores = 1L, verbose = FALSE))
    evidence$subset_grid_ids <- as.character(tuning$grid$id)
    record_call("validate_m2_tuning(tuning)")
    tuning_validated <- stage("governed M2 tuning validation", validate_m2_tuning(tuning))
    evidence$subset_tuning_validated <- TRUE
    evidence$selected_terms <- paste0("h1=", tuning_validated$selected_config$h1$id, ",h2=", tuning_validated$selected_config$h2$id)
    record_call("freeze_m2(fit_m2(dat, selection, m0, m1, config=tuning$selected_config, family='offset_subset_v1', m1_train_preds=tuning$m1_train_preds))")
    m2 <- stage("governed M2 fit/freeze", freeze_m2(fit_m2(dat, selection = selection, m0 = m0, m1 = m1, config = tuning_validated$selected_config, family = "offset_subset_v1", m1_train_preds = tuning_validated$m1_train_preds, n_cores = 1L, verbose = FALSE), tuning = tuning_validated))
    evidence$subset_fit_status <- m2$status
    assert(identical(m2$status, "frozen"), "governed M2 fit is frozen")
    record_call("assemble_kit(m0, m1, m2); saveRDS(); readRDS(); validate_page_kit(reloaded)")
    kit <- stage("governed kit assembly", assemble_kit(m0, m1, m2))
    assert(identical(kit$m2_production$family, "offset_subset_v1"), "assembled kit records offset_subset_v1")
    serialized_path <- file.path(out_dir, "kit-serialized.rds")
    saveRDS(kit, serialized_path)
    reloaded <- readRDS(serialized_path)
    validate_page_kit(reloaded)
    evidence$serialization_verified <- TRUE
    holdout <- dat[dat$season %in% evidence$holdout_seasons, , drop = FALSE]
    record_call("run_pipeline(reloaded, holdout, walk_start=5L, mode='frozen', season=holdout)")
    forecast <- stage("held-out frozen run_pipeline", run_pipeline(reloaded, holdout, walk_start = 5L, mode = "frozen", season = evidence$holdout_seasons, verbose = FALSE))
    evidence$m1_peak_rows <- sum(is.finite(forecast$params_df$peak_weekF))
    evidence$m2_rows <- nrow(forecast$m2_preds)
    evidence$m2_horizons <- sort(unique(as.character(forecast$m2_preds$h)))
    evidence$m2_intervals_na <- nrow(forecast$m2_preds) > 0L && all(is.na(forecast$m2_preds$m2_lo)) && all(is.na(forecast$m2_preds$m2_hi))
    assert(evidence$m1_peak_rows > 0L, "M1 supplies a peak estimate")
    assert(evidence$m2_rows > 0L, "M2 supplies runtime forecasts")
    assert(setequal(evidence$m2_horizons, c("1", "2")), "M2 emits only h1 and h2")
    assert(evidence$m2_intervals_na, "M2 subset runtime records NA intervals")
    compare_frame <- forecast$m2_preds
    compare_frame$season <- evidence$holdout_seasons
    compare_frame$origin <- compare_frame$eval_week
    compare_frame$target <- compare_frame$target_weekF
    compare_frame$horizon <- compare_frame$h
    compare_frame$outcome <- holdout$p[match(compare_frame$target, holdout$weekF)]
    compare_frame$N <- holdout$N[match(compare_frame$target, holdout$weekF)]
    record_call("compare_m1_m2(compare_frame, denominator_col='N')")
    comparison <- stage("denominator-weighted M1/M2 comparison", compare_m1_m2(compare_frame, outcome_col = "outcome", m1_col = "m1_p", m2_col = "m2_p", season_col = "season", origin_col = "origin", target_col = "target", horizon_col = "horizon", denominator_col = "N"))
    evidence$comparison_rows <- comparison$forecast$matched_rows
    assert(evidence$comparison_rows > 0L, "comparison has denominator-weighted matched rows")
    prefix_week <- 30L
    record_call("run_pipeline(reloaded, holdout[weekF<=30], ...); compare earlier origins")
    prefix_forecast <- stage("unseen-prefix run_pipeline", run_pipeline(reloaded, holdout[holdout$weekF <= prefix_week, , drop = FALSE], walk_start = 5L, mode = "frozen", season = evidence$holdout_seasons, verbose = FALSE))
    a <- forecast$m2_preds[forecast$m2_preds$eval_week <= prefix_week, c("eval_week", "h", "m1_p", "m2_p")]
    b <- prefix_forecast$m2_preds[, c("eval_week", "h", "m1_p", "m2_p")]
    evidence$prefix_invariant <- isTRUE(all.equal(a[order(a$eval_week, a$h), ], b[order(b$eval_week, b$h), ], check.attributes = FALSE, tolerance = 1e-12))
    assert(evidence$prefix_invariant, "future holdout rows do not change earlier prefix forecasts")
  },
  error = function(e) {
    evidence$failure <<- conditionMessage(e)
    save_evidence()
    quit(status = 1L)
  }
), warning = record_warning)
save_evidence()
quit(status = 0L)
