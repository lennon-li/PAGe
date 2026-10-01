#!/usr/bin/env Rscript

# M0-only nested outer holdouts for a Unix compute host.
# Each outer fold tunes M0 by inner LOSO, expands unresolved boundaries, fits
# the final training classifier, and evaluates ignition on its unseen season.

args <- commandArgs(trailingOnly = TRUE)
value_of <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
as_integer <- function(value, flag, minimum = 1L) {
  out <- suppressWarnings(as.integer(value))
  if (length(out) != 1L || is.na(out) || out < minimum) {
    stop(flag, " must be an integer >= ", minimum, ".", call. = FALSE)
  }
  out
}
slug <- function(x) gsub("[^A-Za-z0-9]+", "_", x)
write_status <- function(path, status, detail = "") {
  row <- paste(format(Sys.time(), tz = "UTC", usetz = TRUE), status, detail, sep = "\t")
  cat(row, "\n", file = path, append = file.exists(path))
}

data_path <- value_of("--data", Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv"))
output_dir <- value_of("--output", Sys.getenv("PAGE_M0_OUT_DIR", ""))
if (!nzchar(output_dir)) stop("--output or PAGE_M0_OUT_DIR is required.", call. = FALSE)
output_dir <- normalizePath(output_dir, mustWork = FALSE)
holdout_text <- value_of(
  "--holdouts",
  Sys.getenv(
    "PAGE_M0_HOLDOUTS",
    paste(c("2012-13", "2013-14", "2014-15", "2016-17", "2017-18",
            "2018-19", "2019-20", "2022-23", "2023-24", "2024-25"), collapse = ",")
  )
)
holdouts <- unique(trimws(strsplit(holdout_text, ",", fixed = TRUE)[[1L]]))
holdouts <- holdouts[nzchar(holdouts)]
outer_workers <- as_integer(
  value_of("--outer-workers", Sys.getenv("PAGE_M0_OUTER_WORKERS", "4")),
  "--outer-workers"
)
inner_cores <- as_integer(
  value_of("--inner-cores", Sys.getenv("PAGE_M0_INNER_CORES", "1")),
  "--inner-cores"
)
max_boundary_rounds <- as_integer(
  value_of("--max-boundary-rounds", Sys.getenv("PAGE_M0_MAX_BOUNDARY_ROUNDS", "10")),
  "--max-boundary-rounds"
)
timing_mode <- match.arg(
  value_of("--timing-mode", Sys.getenv("PAGE_M0_TIMING_MODE", "fractional")),
  c("legacy", "fractional")
)
exclude <- unique(trimws(strsplit(
  value_of("--exclude", Sys.getenv("PAGE_M0_EXCLUDE", "2011-12,2015-16,2020-21,2021-22")),
  ",", fixed = TRUE
)[[1L]]))
exclude <- exclude[nzchar(exclude)]

if (.Platform$OS.type == "windows") stop("This runner requires a Unix host.", call. = FALSE)
if (!file.exists(data_path)) stop("Authorized historical CSV not found: ", data_path, call. = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
fold_root <- file.path(output_dir, "folds")
dir.create(fold_root, recursive = TRUE, showWarnings = FALSE)
parent_status <- file.path(output_dir, "status.tsv")
write_status(parent_status, "started", paste0("holdouts=", length(holdouts), "; outer_workers=", outer_workers))

package_library <- Sys.getenv("PAGE_PACKAGE_LIBRARY", "")
if (nzchar(package_library) && dir.exists(package_library)) {
  .libPaths(unique(c(package_library, .libPaths())))
}
suppressPackageStartupMessages(library(PAGe))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(MMWRweek))

n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(as.integer(start_year), "-12-31")))$MMWRweek == 53L)
}
raw <- PAGe::load_flu_hist(data_path)
allD <- raw |>
  dplyr::mutate(
    season = as.character(season), week = as.integer(week),
    start_year = as.integer(seasonstart), y = as.numeric(pos_flua),
    N = as.numeric(test_flu),
    weekF = ((week - 27L) %% n_weeks_in_start_year(start_year)) + 1L
  ) |>
  dplyr::select(season, weekF, y, N, dplyr::everything()) |>
  PAGe::prepare_surveillance_data()

manual_labels <- PAGe:::.default_manual_labels()
if (!("2025-26" %in% names(manual_labels))) manual_labels["2025-26"] <- 19L
all_seasons <- sort(unique(as.character(allD$season)))
eligible <- setdiff(all_seasons, exclude)
if (!length(holdouts) || any(!holdouts %in% eligible)) {
  stop("Requested M0 holdouts must be eligible seasons: ", paste(eligible, collapse = ", "), call. = FALSE)
}
if (timing_mode == "fractional") {
  missing_labels <- setdiff(eligible, names(manual_labels))
  if (length(missing_labels)) stop("Missing ignition labels: ", paste(missing_labels, collapse = ", "), call. = FALSE)
}
timing_truth <- data.frame(
  season = eligible,
  ignition_target_weekF = as.numeric(manual_labels[eligible]) + 0.5,
  stringsAsFactors = FALSE
)
saveRDS(list(
  input_path = normalizePath(data_path),
  data_seasons = all_seasons, eligible_seasons = eligible,
  holdouts = holdouts, exclude = exclude, manual_labels = manual_labels,
  timing_mode = timing_mode, timing_truth = timing_truth,
  outer_workers = outer_workers, inner_cores = inner_cores,
  max_boundary_rounds = max_boundary_rounds
), file.path(output_dir, "run_manifest.rds"))

run_one <- function(holdout) {
  fold_dir <- file.path(fold_root, slug(holdout))
  artifact_dir <- file.path(fold_dir, "artifacts")
  checkpoint_dir <- file.path(fold_dir, "checkpoints", "m0")
  status_path <- file.path(fold_dir, "status.tsv")
  dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
  write_status(status_path, "started", paste0("holdout=", holdout, "; inner_cores=", inner_cores))
  tryCatch({
    training_seasons <- setdiff(eligible, holdout)
    selection <- PAGe::validate_season_selection(
      allD, training_seasons = training_seasons,
      exclude_seasons = exclude, holdout_seasons = holdout,
      application_seasons = character(0)
    )
    saveRDS(selection, file.path(artifact_dir, "season_selection.rds"))
    grid <- PAGe:::.default_m0_grid()
    tuning <- NULL
    boundary_history <- list()
    for (attempt in seq_len(max_boundary_rounds)) {
      write_status(status_path, "m0_running", paste0("attempt=", attempt, "; specs=", nrow(grid)))
      tuning <- PAGe::tune_m0(
        allD, grid = grid, manual_labels = manual_labels,
        n_cores = inner_cores, verbose = TRUE, selection = selection,
        checkpoint_dir = checkpoint_dir,
        previous_results = if (attempt == 1L) NULL else tuning$tuning,
        timing_truth = timing_truth, timing_mode = timing_mode
      )
      report <- PAGe::inspect_tuning_boundaries(tuning, stage = "M0", warn = TRUE)
      boundary_history[[attempt]] <- report
      write.csv(grid, file.path(artifact_dir, paste0("m0_grid_round", attempt, ".csv")), row.names = FALSE)
      write.csv(report, file.path(artifact_dir, paste0("m0_boundary_report_round", attempt, ".csv")), row.names = FALSE)
      if (!any(report$decision == "expand_required")) break
      grid <- PAGe::expand_tuning_grid(tuning, stage = "M0")
    }
    if (is.null(tuning) || any(tail(boundary_history, 1L)[[1L]]$decision == "expand_required")) {
      stop("M0 boundary unresolved after configured expansion rounds.", call. = FALSE)
    }
    tuning <- PAGe::validate_m0_tuning(tuning, grid = grid, check_boundaries = TRUE)
    saveRDS(tuning, file.path(artifact_dir, "m0_tuning.rds"))
    saveRDS(boundary_history, file.path(artifact_dir, "m0_boundary_history.rds"))

    fit_args <- list(
      dat = as.data.frame(tuning$aligned), fit_base = TRUE, fit_slope = FALSE,
      fit_fs = FALSE, event_k = 1L, lead = 1L, A_pre = 6L, B_post = 6L,
      k_week = 6L, k_p = 8L, k_fs = 4L, select = FALSE, verbose = FALSE
    )
    if (timing_mode == "fractional") fit_args$timing_truth <- timing_truth[timing_truth$season %in% training_seasons, , drop = FALSE]
    classifier <- do.call(PAGe:::fitIgnition, fit_args)
    saveRDS(classifier, file.path(artifact_dir, "m0_classifier.rds"))

    test <- as.data.frame(allD[allD$season == holdout, , drop = FALSE])
    test$p_cls_p <- as.numeric(stats::predict(classifier$fits$base$gam, newdata = test, type = "response"))
    det <- if (timing_mode == "fractional") {
      PAGe::detectIgnitionBySeason_M0v2_timing(
        test, params = tuning$best_params, score_col = "p_cls_p",
        week_col = "weekF", season_col = "season", phase_col = "phase",
        keep_signals = TRUE, verbose = FALSE, iWeek = FALSE, copy_data = TRUE
      )
    } else {
      PAGe:::detectIgnitionBySeason_M0v2(
        test, params = tuning$best_params, score_col = "p_cls_p",
        week_col = "weekF", season_col = "season", phase_col = "phase",
        keep_signals = TRUE, verbose = FALSE, iWeek = FALSE, copy_data = TRUE
      )
    }
    by_season <- as.data.frame(det$by_season)
    row_id <- match(holdout, by_season$season)
    estimate_integer <- by_season$iWeek_hat[row_id]
    estimate <- if (timing_mode == "fractional" && "iWeek_hatF" %in% names(by_season)) {
      by_season$iWeek_hatF[row_id]
    } else {
      estimate_integer
    }
    truth_current <- as.numeric(manual_labels[[holdout]])
    truth_target <- as.numeric(timing_truth$ignition_target_weekF[timing_truth$season == holdout])
    comparison <- data.frame(
      season = holdout, iWeek_true_current = truth_current,
      iWeek_true_training_target = truth_target, iWeek_hat = estimate,
      iWeek_hatF = if (timing_mode == "fractional") estimate else NA_real_,
      iWeek_hat_integer = estimate_integer,
      error_vs_current = estimate - truth_current,
      error_vs_training_target = estimate - truth_target,
      stringsAsFactors = FALSE
    )
    write.csv(comparison, file.path(artifact_dir, "m0_outer_comparison.csv"), row.names = FALSE)
    saveRDS(det, file.path(artifact_dir, "m0_outer_detection.rds"))
    saveRDS(list(
      schema = "page_m0_outer_holdout_v1", holdout = holdout,
      training_seasons = training_seasons, selection = selection,
      tuning = tuning, classifier = classifier, detection = det,
      comparison = comparison, timing_mode = timing_mode,
      boundary_history = boundary_history
    ), file.path(artifact_dir, "m0_outer_result.rds"))
    write_status(status_path, "complete", paste0("iWeek_hat=", estimate))
    list(holdout = holdout, status = "complete", estimate = estimate, error = NA_character_)
  }, error = function(e) {
    writeLines(capture.output(conditionCall(e), conditionMessage(e)), file.path(fold_dir, "error.txt"))
    write_status(status_path, "failed", conditionMessage(e))
    list(holdout = holdout, status = "failed", estimate = NA_real_, error = conditionMessage(e))
  })
}

results <- parallel::mclapply(holdouts, run_one, mc.cores = outer_workers, mc.preschedule = FALSE)
summary <- do.call(rbind, lapply(results, as.data.frame, stringsAsFactors = FALSE))
write.csv(summary, file.path(output_dir, "fold_status.csv"), row.names = FALSE)
final_status <- if (all(summary$status == "complete")) "complete" else "failed"
write_status(parent_status, final_status, paste0("complete=", sum(summary$status == "complete"), "; failed=", sum(summary$status == "failed")))
saveRDS(list(schema = "page_m0_outer_holdouts_v1", status = final_status,
             holdouts = holdouts, fold_status = summary,
             output_dir = output_dir), file.path(output_dir, "m0_outer_summary.rds"))
if (final_status != "complete") stop("One or more M0 outer holdouts failed; inspect fold_status.csv.", call. = FALSE)
cat("M0 outer holdout run complete\n")
