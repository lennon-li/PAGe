#!/usr/bin/env Rscript

# Prepare the canonical data and timing-label inputs for every eligible outer
# holdout. This script does not fit models or launch workers.

args <- commandArgs(trailingOnly = TRUE)
value_of <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}

parse_integer <- function(value, flag, minimum = 1L) {
  out <- suppressWarnings(as.integer(value))
  if (length(out) != 1L || is.na(out) || out < minimum) {
    stop(flag, " must be an integer >= ", minimum, ".", call. = FALSE)
  }
  out
}
parse_number <- function(value, flag, lower = -Inf, upper = Inf) {
  out <- suppressWarnings(as.numeric(value))
  if (length(out) != 1L || is.na(out) || !is.finite(out) ||
    out < lower || out > upper) {
    stop(flag, " must be a finite number in [", lower, ", ", upper, "].",
      call. = FALSE
    )
  }
  out
}

repo_root <- normalizePath(getwd(), mustWork = TRUE)
input_path <- normalizePath(
  value_of("--input", Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv")),
  mustWork = TRUE
)
output_dir <- value_of(
  "--output",
  file.path(repo_root, "results", "manuscript", "all-season-holdout-prep-20260914")
)
output_dir <- normalizePath(output_dir, mustWork = FALSE)
if (dir.exists(output_dir)) {
  stop("Refusing to overwrite existing preparation directory: ", output_dir,
    call. = FALSE
  )
}

start_week <- parse_integer(value_of("--start-week", "27"), "--start-week")
smooth_window <- parse_integer(value_of("--smooth-window", "3"), "--smooth-window")
p_threshold <- parse_number(value_of("--p-threshold", "0.01"), "--p-threshold", 0, 1)
peak_tolerance <- parse_number(value_of("--peak-tolerance", "1e-12"), "--peak-tolerance", 0)
confidence <- parse_number(value_of("--confidence", "0.95"), "--confidence", 0, 1)
if (confidence <= 0 || confidence >= 1) {
  stop("--confidence must be strictly between 0 and 1.", call. = FALSE)
}
exclude <- strsplit(
  value_of("--exclude", "2011-12,2015-16,2020-21,2021-22"),
  ",", fixed = TRUE
)[[1L]]
exclude <- trimws(exclude[nzchar(trimws(exclude))])

package_library <- Sys.getenv("PAGE_PACKAGE_LIBRARY", "")
if (nzchar(package_library) && dir.exists(package_library)) {
  .libPaths(unique(c(package_library, .libPaths())))
}
if (!requireNamespace("PAGe", quietly = TRUE)) {
  stop("PAGe is unavailable; install the package or set PAGE_PACKAGE_LIBRARY.",
    call. = FALSE
  )
}
suppressPackageStartupMessages(library(PAGe))

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output_dir, "folds"), showWarnings = FALSE)

raw <- PAGe::load_flu_hist(input_path)
prepared <- PAGe::prepare_page_data(
  raw,
  outcome_col = "pos_flua",
  week_col = "week",
  season_col = "season",
  total_col = "test_flu",
  week_type = "mmwr",
  start_week = start_week,
  start_year_col = "seasonstart"
)

all_seasons <- sort(unique(as.character(prepared$season)))
eligible <- setdiff(all_seasons, exclude)
requested_holdouts <- value_of("--holdouts", NULL)
holdouts <- if (is.null(requested_holdouts)) {
  eligible
} else {
  requested <- strsplit(requested_holdouts, ",", fixed = TRUE)[[1L]]
  requested <- trimws(requested[nzchar(trimws(requested))])
  unique(requested)
}
if (!length(holdouts) || any(!holdouts %in% eligible)) {
  stop(
    "Every requested holdout must be one eligible season. Eligible seasons: ",
    paste(eligible, collapse = ", "),
    call. = FALSE
  )
}

manual_ignition <- PAGe::page_manual_ignition_labels()
missing_ignition <- setdiff(holdouts, names(manual_ignition))
if (length(missing_ignition)) {
  stop("Missing ignition labels for: ", paste(missing_ignition, collapse = ", "),
    call. = FALSE
  )
}

make_pair <- function(value, n_weeks) {
  value <- as.integer(value)
  if (value < n_weeks) c(value, value + 1L) else c(value - 1L, value)
}

timing_labels <- setNames(vector("list", length(holdouts)), holdouts)
season_rows <- lapply(all_seasons, function(season) {
  season_data <- prepared[as.character(prepared$season) == season, , drop = FALSE]
  review <- PAGe::review_season_timing_v2(
    prepared,
    season = season,
    smooth_window = smooth_window,
    p_threshold = p_threshold,
    peak_tolerance = peak_tolerance,
    confidence = confidence
  )
  n_weeks <- max(52L, max(season_data$weekF, na.rm = TRUE))
  peak <- as.integer(review$peak_summary$peak_weekF[[1L]])
  if (season %in% holdouts && !is.finite(peak)) {
    stop("No finite observed peak label for holdout season: ", season,
      call. = FALSE
    )
  }
  if (season %in% holdouts) {
    timing_labels[[season]] <- PAGe::finalize_season_timing_v2(
      review,
      ignition = make_pair(manual_ignition[[season]], n_weeks),
      peak = make_pair(peak, n_weeks),
      n_weeks = n_weeks,
      annotator = "all-season holdout preparation",
      note = "Historical ignition label paired with the following week; observed peak paired with its adjacent week."
    )
  }
  data.frame(
    season = season,
    n_rows = nrow(season_data),
    first_weekF = min(season_data$weekF),
    last_weekF = max(season_data$weekF),
    n_weeks = n_weeks,
    eligible_outer_holdout = season %in% eligible,
    requested_holdout = season %in% holdouts,
    excluded = season %in% exclude,
    ignition_label = if (season %in% names(manual_ignition)) manual_ignition[[season]] else NA_integer_,
    observed_peak_weekF = peak,
    stringsAsFactors = FALSE
  )
})
season_manifest <- do.call(rbind, season_rows)

holdout_rows <- lapply(holdouts, function(holdout) {
  training <- setdiff(eligible, holdout)
  fold_dir <- file.path(output_dir, "folds", gsub("[^A-Za-z0-9]+", "_", holdout))
  dir.create(fold_dir, recursive = TRUE, showWarnings = FALSE)
  training_data <- prepared[as.character(prepared$season) %in% training, , drop = FALSE]
  holdout_data <- prepared[as.character(prepared$season) == holdout, , drop = FALSE]
  fold_labels <- timing_labels[training]
  saveRDS(training_data, file.path(fold_dir, "training_data.rds"))
  saveRDS(holdout_data, file.path(fold_dir, "holdout_data.rds"))
  saveRDS(fold_labels, file.path(fold_dir, "timing_labels_training.rds"))
  writeLines(training, file.path(fold_dir, "training_seasons.txt"))
  data.frame(
    holdout = holdout,
    training_seasons = paste(training, collapse = ";"),
    n_training_seasons = length(training),
    n_training_rows = nrow(training_data),
    n_holdout_rows = nrow(holdout_data),
    timing_label_available = holdout %in% names(timing_labels),
    stringsAsFactors = FALSE
  )
})
holdout_manifest <- do.call(rbind, holdout_rows)

saveRDS(prepared, file.path(output_dir, "prepared_data_all_seasons.rds"))
saveRDS(timing_labels, file.path(output_dir, "timing_labels_v2_all_holdouts.rds"))
utils::write.csv(season_manifest, file.path(output_dir, "season_manifest.csv"), row.names = FALSE)
utils::write.csv(holdout_manifest, file.path(output_dir, "outer_holdout_manifest.csv"), row.names = FALSE)

hash_file <- function(path) unname(tools::md5sum(path))
manifest <- list(
  schema = "page_all_season_holdout_preparation",
  prepared_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  repository = repo_root,
  input_path = input_path,
  input_md5 = hash_file(input_path),
  output_dir = output_dir,
  start_week = start_week,
  review = list(
    smooth_window = smooth_window,
    p_threshold = p_threshold,
    peak_tolerance = peak_tolerance,
    confidence = confidence
  ),
  all_seasons = all_seasons,
  excluded_seasons = exclude,
  eligible_outer_holdouts = eligible,
  requested_holdouts = holdouts,
  n_all_seasons = length(all_seasons),
  n_eligible_holdouts = length(eligible),
  prepared_rows = nrow(prepared),
  timing_label_policy = "Ignition uses the established manual label plus its following week; peak uses the observed peak and its adjacent week; each fold removes its holdout labels before training.",
  fitting_started = FALSE
)
saveRDS(manifest, file.path(output_dir, "manifest.rds"))

readme <- c(
  "# All-season outer-holdout preparation",
  "",
  "This directory contains canonical data snapshots and timing-label inputs for the requested outer holdouts. It was produced without fitting models or launching workers.",
  "",
  paste0("- Input: `", input_path, "`"),
  paste0("- Input MD5: `", manifest$input_md5, "`"),
  paste0("- Eligible holdouts: `", paste(holdouts, collapse = ", "), "`"),
  paste0("- Fixed exclusions: `", paste(exclude, collapse = ", "), "`"),
  paste0("- Prepared rows: `", nrow(prepared), "`"),
  "",
  "Each `folds/<holdout>/` directory contains `training_data.rds`, `holdout_data.rds`, `timing_labels_training.rds`, and `training_seasons.txt`.",
  "The fold label file excludes the corresponding holdout and is ready for `PAGe::nested_season_evaluation()`.",
  "",
  "Reproduce with:",
  "",
  "```bash",
  paste(
    "PAGE_FLU_HIST_FILE=/home/yeli/FLU/flu_testing_data.csv",
    "R_LIBS_USER=/home/yeli/repos/PAGe/r-lib",
    "Rscript scripts/prepare_all_season_holdouts.R",
    sep = " "
  ),
  "```"
)
writeLines(readme, file.path(output_dir, "README.md"))

cat(
  "prepared ", length(holdouts), " outer holdouts; ", nrow(prepared),
  " rows; output=", output_dir, "\n", sep = ""
)
