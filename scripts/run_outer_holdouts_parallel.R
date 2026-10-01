#!/usr/bin/env Rscript

# Run independent outer holdouts in parallel on a Unix compute host.
# Each fold uses one inner worker; outer parallelism is the only active layer.

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
    stop(flag, " must be a finite number in [", lower, ", ", upper, ".",
      call. = FALSE
    )
  }
  out
}

`%||%` <- function(x, y) if (!is.null(x)) x else y
repo_root <- normalizePath(getwd(), mustWork = TRUE)
prepared_arg <- value_of("--prepared", Sys.getenv("PAGE_PREP_DIR", ""))
output_arg <- value_of("--output", Sys.getenv("PAGE_OUT_DIR", ""))
if (!nzchar(prepared_arg) || !nzchar(output_arg)) {
  stop("Both `--prepared`/PAGE_PREP_DIR and `--output`/PAGE_OUT_DIR are required.",
    call. = FALSE
  )
}
prepared_dir <- normalizePath(prepared_arg, mustWork = TRUE)
output_dir <- normalizePath(output_arg, mustWork = FALSE)
protocol_path <- value_of("--protocol", Sys.getenv("PAGE_PROTOCOL_RDS", ""))
if (nzchar(protocol_path)) protocol_path <- normalizePath(protocol_path, mustWork = TRUE)

outer_workers_default <- max(1L, min(4L, parallel::detectCores() - 1L))
outer_workers <- parse_integer(
  value_of("--outer-workers", Sys.getenv("PAGE_OUTER_WORKERS", outer_workers_default)),
  "--outer-workers"
)
inner_cores <- parse_integer(
  value_of("--inner-cores", Sys.getenv("PAGE_INNER_CORES", "1")),
  "--inner-cores"
)
if (.Platform$OS.type == "windows") {
  stop("This scheduler requires a Unix host such as Venkata.", call. = FALSE)
}

prepared_path <- file.path(prepared_dir, "prepared_data_all_seasons.rds")
labels_path <- file.path(prepared_dir, "timing_labels_v2_all_holdouts.rds")
manifest_path <- file.path(prepared_dir, "manifest.rds")
if (!file.exists(prepared_path) || !file.exists(labels_path)) {
  stop("Prepared directory must contain prepared data and timing labels: ",
    prepared_dir, call. = FALSE
  )
}
allD <- readRDS(prepared_path)
timing_labels_all <- readRDS(labels_path)
prep_manifest <- if (file.exists(manifest_path)) readRDS(manifest_path) else NULL
if (!is.data.frame(allD) || !nrow(allD)) stop("Prepared data are empty.", call. = FALSE)
if (!is.list(timing_labels_all) || is.null(names(timing_labels_all))) {
  stop("Timing-label input must be a named list.", call. = FALSE)
}

eligible <- prep_manifest$eligible_outer_holdouts %||%
  sort(unique(as.character(names(timing_labels_all))))
requested <- value_of("--holdouts", Sys.getenv("PAGE_HOLDOUTS", ""))
holdouts <- if (!nzchar(requested)) {
  as.character(eligible)
} else {
  trimws(strsplit(requested, ",", fixed = TRUE)[[1L]])
}
holdouts <- unique(holdouts[nzchar(holdouts)])
if (!length(holdouts) || any(!holdouts %in% eligible)) {
  stop("Requested holdouts must be eligible seasons: ",
    paste(eligible, collapse = ", "), call. = FALSE
  )
}

exclude_default <- c("2011-12", "2015-16", "2020-21", "2021-22")
exclude_text <- value_of("--exclude", Sys.getenv(
  "PAGE_EXCLUDE", paste(exclude_default, collapse = ",")
))
exclude <- trimws(strsplit(exclude_text, ",", fixed = TRUE)[[1L]])
exclude <- unique(exclude[nzchar(exclude)])

protocol <- if (nzchar(protocol_path)) readRDS(protocol_path) else list()
weighting <- protocol$weighting %||% list()
adoption <- protocol$adoption %||% list()
model <- protocol$model %||% list()
expansion <- protocol$expansion %||% list()

env_number <- function(name, fallback, lower = -Inf, upper = Inf) {
  parse_number(Sys.getenv(name, as.character(fallback)), name, lower, upper)
}
env_integer <- function(name, fallback, minimum = 1L) {
  parse_integer(Sys.getenv(name, as.character(fallback)), name, minimum)
}

protocol_args <- list(
  timing_mode = Sys.getenv("PAGE_TIMING_MODE", model$timing_mode %||% "fractional"),
  pre_ignition_weight = env_number(
    "PAGE_PRE_IGNITION_WEIGHT", weighting$pre_ignition %||% 0, 0
  ),
  early_weight = env_number("PAGE_EARLY_WEIGHT", weighting$early %||% 2, 0),
  early_max_t_since = env_integer(
    "PAGE_EARLY_MAX_T_SINCE", weighting$early_max_t_since %||% 12, 0L
  ),
  late_weight = env_number("PAGE_LATE_WEIGHT", weighting$late %||% 1, 0),
  score_scale = Sys.getenv("PAGE_SCORE_SCALE", weighting$score_scale %||% "equal_week"),
  min_gain = env_number("PAGE_MIN_GAIN", adoption$min_gain %||% 0.0012, 0),
  min_gain_by_horizon = c(
    "2" = env_number("PAGE_MIN_GAIN_H2", adoption$min_gain_by_horizon[["2"]] %||% 0.002, 0)
  ),
  confidence = env_number("PAGE_CONFIDENCE", adoption$confidence %||% 0.95, 0, 1),
  max_season_degradation = env_number(
    "PAGE_MAX_SEASON_DEGRADATION", adoption$max_season_degradation %||% 0, 0
  ),
  m1_min_gain = env_number("PAGE_M1_MIN_GAIN", 0.05, 0),
  max_boundary_rounds = expansion$max_boundary_rounds %||%
    c(M0 = 10L, M1 = 4L, M2 = 6L),
  m0_expansion_steps = expansion$m0_steps %||%
    c(p_thr = 0.001, prev_thr = 0.001, p_sum_thr = 0.01),
  m1_expansion_steps = expansion$m1_steps %||% c(k_ref = 5, slope_weight = 4),
  m2_expansion_increment = env_integer(
    "PAGE_M2_EXPANSION_INCREMENT", expansion$m2_increment %||% 12L
  ),
  n_cores = inner_cores
)
protocol_args$score_scale <- match.arg(
  protocol_args$score_scale, c("equal_week", "test_count")
)
protocol_args$timing_mode <- match.arg(
  protocol_args$timing_mode, c("legacy", "fractional")
)
if (!is.null(protocol$max_boundary_rounds)) {
  protocol_args$max_boundary_rounds <- protocol$max_boundary_rounds
}

if (dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
} else {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
}
fold_root <- file.path(output_dir, "folds")
dir.create(fold_root, showWarnings = FALSE)

slug <- function(x) gsub("[^A-Za-z0-9]+", "_", x)
write_status <- function(path, status, detail = "") {
  row <- paste(
    format(Sys.time(), tz = "UTC", usetz = TRUE), status, detail,
    sep = "\t"
  )
  cat(row, "\n", file = path, append = file.exists(path))
}

# Construct the governed call explicitly so the protocol list remains
# auditable and named.
run_one <- local({
  call_args <- protocol_args
  function(holdout) {
    fold_dir <- file.path(fold_root, slug(holdout))
    artifact_dir <- file.path(fold_dir, "artifacts")
    checkpoint_dir <- file.path(fold_dir, "checkpoints")
    status_path <- file.path(fold_dir, "status.tsv")
    result_path <- file.path(artifact_dir, "outer_fold_result.rds")
    log_path <- file.path(fold_dir, "run.log")
    dir.create(fold_dir, recursive = TRUE, showWarnings = FALSE)
    if (file.exists(result_path) && identical(Sys.getenv("PAGE_RESUME", "1"), "1")) {
      write_status(status_path, "skipped", "existing outer_fold_result.rds")
      return(list(holdout = holdout, status = "skipped", error = NA_character_))
    }
    write_status(status_path, "started", paste0("inner_cores=", inner_cores))
    log_con <- file(log_path, open = "at")
    sink(log_con, type = "output")
    sink(log_con, type = "message")
    on.exit({
      sink(type = "message")
      sink(type = "output")
      close(log_con)
    }, add = TRUE)
    tryCatch({
      result <- do.call(
        PAGe::run_outer_fold,
        c(list(
          data = allD, holdout = holdout, timing_labels = timing_labels_all,
          artifact_dir = artifact_dir, checkpoint_dir = checkpoint_dir,
          exclude = exclude, verbose = TRUE
        ), call_args)
      )
      write_status(status_path, "complete", "outer replay complete")
      list(holdout = holdout, status = "complete", error = NA_character_)
    }, error = function(e) {
      message("ERROR: ", conditionMessage(e))
      write_status(status_path, "failed", conditionMessage(e))
      list(holdout = holdout, status = "failed", error = conditionMessage(e))
    })
  }
})

cat("Starting ", length(holdouts), " outer holdouts with ", outer_workers,
  " outer workers and ", inner_cores, " inner cores per fold\n", sep = "")
worker_status <- parallel::mclapply(
  holdouts, run_one, mc.cores = outer_workers, mc.preschedule = FALSE
)
worker_status <- do.call(rbind, lapply(worker_status, as.data.frame,
  stringsAsFactors = FALSE
))
utils::write.csv(worker_status, file.path(output_dir, "fold_status.csv"), row.names = FALSE)

complete_holdouts <- worker_status$holdout[worker_status$status %in% c("complete", "skipped")]
result_paths <- file.path(fold_root, slug(complete_holdouts), "artifacts", "outer_fold_result.rds")
result_paths <- result_paths[file.exists(result_paths)]
predictions <- lapply(result_paths, function(path) readRDS(path)$predictions)
predictions <- if (length(predictions)) do.call(rbind, predictions) else NULL
decision <- NULL
if (is.data.frame(predictions) && nrow(predictions)) {
  decision <- PAGe::decide_m2_vs_m1(
    predictions,
    outcome_col = "outcome", m1_col = "m1_prediction",
    m2_col = "m2_prediction", season_col = "season",
    origin_col = "origin", target_col = "target", horizon_col = "horizon",
    t_since_col = "t_since_target", phase_break = protocol_args$early_max_t_since,
    phase_weights = c(pre_ignition = protocol_args$pre_ignition_weight,
      early = protocol_args$early_weight, late = protocol_args$late_weight),
    min_gain = protocol_args$min_gain,
    min_gain_by_horizon = protocol_args$min_gain_by_horizon,
    confidence = protocol_args$confidence,
    max_season_degradation = protocol_args$max_season_degradation
  )
  saveRDS(predictions, file.path(output_dir, "outer_predictions_all_seasons.rds"))
  utils::write.csv(predictions,
    file.path(output_dir, "outer_predictions_all_seasons.csv"), row.names = FALSE
  )
  saveRDS(decision, file.path(output_dir, "aggregate_m2_vs_m1.rds"))
  writeLines(capture.output(print(decision)),
    file.path(output_dir, "aggregate_m2_vs_m1.txt")
  )
}

final_status <- if (all(worker_status$status %in% c("complete", "skipped"))) {
  "complete"
} else {
  "failed"
}
saveRDS(list(
  schema = "page_outer_holdouts_parallel_run",
  completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  prepared_dir = prepared_dir,
  output_dir = output_dir,
  holdouts = holdouts,
  outer_workers = outer_workers,
  inner_cores = inner_cores,
  exclude = exclude,
  protocol = protocol_args,
  worker_status = worker_status,
  decision = decision,
  status = final_status
), file.path(output_dir, "parallel_run_summary.rds"))
writeLines(capture.output(str(list(
  status = final_status, holdouts = holdouts, worker_status = worker_status,
  decision = decision
), max.level = 2)), file.path(output_dir, "parallel_run_summary.txt"))
if (final_status != "complete") {
  stop("One or more outer holdouts failed; inspect fold_status.csv and fold logs.",
    call. = FALSE
  )
}
cat("parallel outer-holdout run complete\n")
