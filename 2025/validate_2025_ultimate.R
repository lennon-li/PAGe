#!/usr/bin/env Rscript

# Independent, read-only audit for the governed 2025-26 outer-fold run.
# This script must be run after the runner has reached terminal completion.
# It never trains, tunes, promotes, or modifies a model artifact.

args <- commandArgs(trailingOnly = TRUE)
run_dir <- "/home/yeli/repos/PAGe/results/manuscript/nested-outer-2025-26-ultimate-20260911/20260912T025500Z-ultimate-2025-26-r3"
for (arg in args) {
  if (!grepl("^--run_dir=", arg)) stop("Unknown argument: ", arg)
  run_dir <- sub("^--run_dir=", "", arg)
}
run_dir <- normalizePath(run_dir, mustWork = TRUE)
artifact_dir <- file.path(run_dir, "artifacts")

fail <- function(...) stop(paste0(...), call. = FALSE)
need <- function(path) {
  if (!file.exists(path)) fail("Missing required file: ", path)
  path
}
same_set <- function(x, y) identical(sort(as.character(x)), sort(as.character(y)))
check_metric_bundle <- function(bundle, path) {
  if (!is.list(bundle) || !is.character(bundle$decision) ||
    !bundle$decision %in% c("use_m2", "keep_m1", "insufficient_evidence")) {
    fail("Invalid decision bundle in ", path, ".")
  }
  for (section in c("overall", "by_horizon", "by_season", "matched")) {
    if (!is.data.frame(bundle[[section]]) || !nrow(bundle[[section]])) {
      fail("Missing metric section ", section, " in ", path, ".")
    }
  }
  point_columns <- c(
    "m1_nll", "m2_nll", "delta_nll", "gain_nll",
    "m1_mae", "m2_mae", "delta_mae"
  )
  for (section in c("overall", "by_horizon", "by_season", "matched")) {
    df <- bundle[[section]]
    columns <- intersect(point_columns, names(df))
    for (column in columns) {
      if (any(!is.finite(as.numeric(df[[column]])))) {
        fail("Non-finite point estimate in ", path, "$", section, "$", column, ".")
      }
    }
  }
  matched <- bundle$matched
  for (column in intersect(c("weight", "horizon", "valid"), names(matched))) {
    if (column == "valid") next
    if (any(!is.finite(as.numeric(matched[[column]])))) {
      fail("Non-finite accounting value in ", path, "$matched$", column, ".")
    }
  }
  # Standard errors and gate thresholds are undefined or infinite when only
  # one season is available; point estimates above remain mandatory.
  invisible(TRUE)
}

status <- read.delim(need(file.path(run_dir, "status.tsv")), sep = "\t",
  stringsAsFactors = FALSE
)
if (!nrow(status) || !identical(tail(status$status, 1L), "complete")) {
  fail("Runner status is not terminal complete.")
}
need(file.path(run_dir, "watch_terminal.txt"))

summary <- readRDS(need(file.path(run_dir, "run_summary.rds")))
outer <- readRDS(need(file.path(artifact_dir, "outer_fold_result.rds")))
training <- outer$training
replay <- outer$replay
provenance <- readRDS(need(file.path(run_dir, "provenance.rds")))
protocol <- readRDS(need(file.path(artifact_dir, "protocol.rds")))
predictions <- utils::read.csv(
  need(file.path(artifact_dir, "outer_predictions.csv")),
  stringsAsFactors = FALSE
)
inner_gate_rows <- utils::read.csv(
  need(file.path(artifact_dir, "inner_gate_matched_rows.csv")),
  stringsAsFactors = FALSE
)

holdout <- "2025-26"
excluded <- c("2011-12", "2015-16", "2020-21", "2021-22")
training_seasons <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18",
  "2018-19", "2019-20", "2022-23", "2023-24", "2024-25"
)

if (!identical(as.character(outer$holdout), holdout)) fail("Outer holdout mismatch.")
if (!identical(as.character(replay$season), holdout) ||
  !identical(as.character(replay$status), "unseen_replay_complete")) {
  fail("Replay is not a complete strict unseen-season replay.")
}
if (!same_set(training$selection$training_seasons, training_seasons) ||
  holdout %in% as.character(training$selection$training_seasons)) {
  fail("Training season selection does not match the declared outer split.")
}
if (!same_set(training$selection$exclude_seasons, excluded)) {
  fail("Excluded season selection does not match the declared protocol.")
}
if (!same_set(provenance$training_seasons, training_seasons) ||
  !identical(as.character(provenance$holdout), holdout)) {
  fail("Provenance season contract mismatch.")
}

w <- protocol$weighting
a <- protocol$adoption
if (!identical(as.numeric(w$pre_ignition), 0) ||
  !identical(as.numeric(w$early), 2) ||
  !identical(as.integer(w$early_max_t_since), 12L) ||
  !identical(as.numeric(w$late), 1) ||
  !identical(as.character(w$score_scale), "equal_week") ||
  !identical(as.character(w$season_aggregation), "equal")) {
  fail("Recorded primary weighting protocol does not match the declaration.")
}
if (!identical(as.numeric(a$min_gain), 0.0012) ||
  !identical(names(a$min_gain_by_horizon), "2") ||
  length(a$min_gain_by_horizon) != 1L ||
  !isTRUE(all.equal(as.numeric(a$min_gain_by_horizon), 0.002)) ||
  !identical(as.numeric(a$confidence), 0.95) ||
  !identical(as.numeric(a$max_season_degradation), 0)) {
  fail("Recorded adoption protocol does not match the declaration.")
}

required_artifacts <- c(
  "m0_tuning.rds", "m0_frozen.rds", "m1_tuning.rds", "m1_selection.rds",
  "m1_frozen.rds", "m2_tuning.rds", "m2_frozen.rds",
  "candidate_pre_holdout.rds", "outer_training_result.rds", "outer_replay.rds",
  "outer_predictions.csv", "outer_fold_result.rds", "inner_gate_matched_rows.csv",
  "inner_gate_decision.rds", "gate_decision_applied.rds",
  "m0_boundary_plan_round1.rds", "m0_boundary_report_round1.csv",
  "m1_boundary_plan_round1.rds", "m1_boundary_report_round1.csv",
  "m2_boundary_plan_round1.rds", "m2_boundary_report_round1.csv"
)
missing <- required_artifacts[!file.exists(file.path(artifact_dir, required_artifacts))]
if (length(missing)) fail("Missing required artifacts: ", paste(missing, collapse = ", "))

for (stage in c("m0", "m1", "m2")) {
  history <- training$boundaries[[stage]]
  if (!length(history) || !isTRUE(tail(history, 1L)[[1L]]$settled)) {
    fail("Boundary expansion is unresolved for ", stage, ".")
  }
}

required_prediction_columns <- c(
  "outcome", "m1_prediction", "m2_prediction", "t_since_target"
)
if (!all(required_prediction_columns %in% names(predictions)) || !nrow(predictions)) {
  fail("Outer prediction table is incomplete.")
}
if (any(!is.finite(as.matrix(predictions[required_prediction_columns]))) ||
  any(predictions$t_since_target < 0) ||
  any(predictions$m1_prediction < 0 | predictions$m1_prediction > 1) ||
  any(predictions$m2_prediction < 0 | predictions$m2_prediction > 1)) {
  fail("Outer prediction table contains invalid values.")
}
if ("season" %in% names(predictions) &&
  any(as.character(predictions$season) != holdout)) {
  fail("Outer predictions contain a non-holdout season.")
}
if ("season" %in% names(inner_gate_rows) &&
  any(as.character(inner_gate_rows$season) == holdout)) {
  fail("Inner gate rows contain the outer holdout season.")
}
object_predictions <- outer$predictions
if (!is.data.frame(object_predictions) ||
  nrow(object_predictions) != nrow(predictions) ||
  !all(required_prediction_columns %in% names(object_predictions))) {
  fail("Saved outer prediction object is inconsistent with its CSV.")
}
for (column in required_prediction_columns) {
  if (!isTRUE(all.equal(
    as.numeric(object_predictions[[column]]),
    as.numeric(predictions[[column]])
  ))) {
    fail("Prediction object/CSV mismatch in column ", column, ".")
  }
}
check_metric_bundle(outer$metrics, "outer$metrics")
check_metric_bundle(outer$sensitivity, "outer$sensitivity")
check_metric_bundle(summary$metrics, "run_summary$metrics")
check_metric_bundle(summary$sensitivity, "run_summary$sensitivity")

gate_applied <- readRDS(need(file.path(artifact_dir, "gate_decision_applied.rds")))
if (!identical(gate_applied, training$gate$applied) ||
  !gate_applied$action %in% c("use_m2", "keep_m1")) {
  fail("Recorded gate application does not match the training result.")
}

manifest <- utils::read.csv(need(file.path(run_dir, "package_source_manifest.csv")),
  stringsAsFactors = FALSE
)
hash_mismatch <- vapply(seq_len(nrow(manifest)), function(i) {
  snapshot <- file.path(run_dir, "source_snapshot", manifest$path[[i]])
  !file.exists(snapshot) ||
    !identical(unname(tools::md5sum(snapshot)), manifest$md5[[i]])
}, logical(1))
if (any(hash_mismatch)) fail("Source snapshot hash mismatch detected.")

audit <- list(
  validated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  run_dir = run_dir,
  status = "independent_validation_passed",
  holdout = holdout,
  training_seasons = training_seasons,
  excluded_seasons = excluded,
  replay_status = replay$status,
  prediction_rows = nrow(predictions),
  primary_metrics = outer$metrics,
  sensitivity_metrics = outer$sensitivity,
  gate_applied = gate_applied,
  boundary_stages_settled = setNames(rep(TRUE, 3L), c("M0", "M1", "M2")),
  source_manifest_rows = nrow(manifest)
)
saveRDS(audit, file.path(run_dir, "independent_validation.rds"))
writeLines(c(
  "status: independent_validation_passed",
  paste0("validated_utc: ", audit$validated_utc),
  paste0("holdout: ", holdout),
  paste0("prediction_rows: ", nrow(predictions)),
  paste0("gate_action: ", gate_applied$action),
  paste0("source_manifest_rows: ", nrow(manifest))
), file.path(run_dir, "independent_validation.txt"))
cat("independent validation passed\n")
