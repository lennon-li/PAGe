#!/usr/bin/env Rscript

# Compare the governed Asgard 2018-19 cycle with the archived BCC cycle.
# This is an audit/reporting script; it never changes either fitted artifact.

artifact_root <- Sys.getenv(
  "PAGE_ARTIFACT_ROOT",
  "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812"
)
run_id <- Sys.getenv("PAGE_RUN_ID", "2018-final2")
run_dir <- file.path(artifact_root, run_id)
artifact_dir <- file.path(run_dir, "artifacts")
bcc_dir <- Sys.getenv(
  "PAGE_BCC_RUN_DIR",
  file.path(artifact_root, "bcc-2018-19")
)

required <- c(
  asgard_replay = file.path(artifact_dir, "holdout_2018_19_replay.rds"),
  asgard_result = file.path(artifact_dir, "training_result.rds"),
  asgard_manifest = file.path(artifact_dir, "run_manifest.rds"),
  asgard_m2_grid = file.path(artifact_dir, "m2_grid.csv"),
  bcc_replay = file.path(bcc_dir, "page-m2-holdout-replay.rds"),
  bcc_audit = file.path(bcc_dir, "audit_summary.txt")
)
missing <- required[!file.exists(required)]
if (length(missing)) stop("Missing comparison artifacts: ", paste(missing, collapse = ", "))

asgard_replay <- readRDS(required[["asgard_replay"]])
asgard_result <- readRDS(required[["asgard_result"]])
asgard_manifest <- readRDS(required[["asgard_manifest"]])
asgard_m2_grid <- utils::read.csv(required[["asgard_m2_grid"]], stringsAsFactors = FALSE)
bcc_replay <- readRDS(required[["bcc_replay"]])
bcc_audit <- readLines(required[["bcc_audit"]], warn = FALSE)

metric_row <- function(replay, system) {
  overall <- replay$metrics$overall
  if (!is.data.frame(overall) || !nrow(overall)) {
    stop(system, " replay has no overall metrics.")
  }
  data.frame(
    system = system,
    holdout = as.character(replay$season %||% "2018-19"),
    status = as.character(replay$status %||% NA_character_),
    ignition_week = as.numeric(replay$ignition_week %||% NA_real_),
    bernoulli_nll = as.numeric(overall$bernoulli_nll[1L]),
    mae = as.numeric(overall$mae[1L]),
    n_trials = as.numeric(overall$n_trials[1L]),
    n_predictions = as.numeric(overall$n_predictions[1L]),
    stringsAsFactors = FALSE
  )
}

`%||%` <- function(x, y) if (!is.null(x)) x else y
metrics <- rbind(
  metric_row(asgard_replay, "Asgard governed retry"),
  metric_row(bcc_replay, "BCC archived run")
)
utils::write.csv(metrics, file.path(artifact_dir, "comparison_to_bcc_2018_19.csv"), row.names = FALSE)

selected_m2 <- asgard_result$selection$selected_spec
selected_m2_id <- as.character(asgard_result$selection$selected_spec_id %||% NA_character_)
training_asgard <- as.character(asgard_manifest$training_seasons %||% character(0))
training_bcc <- sub("^training_seasons=", "", bcc_audit[grepl("^training_seasons=", bcc_audit)])
training_bcc <- if (length(training_bcc)) strsplit(training_bcc[1L], ",", fixed = TRUE)[[1L]] else character(0)

boundary_rows <- function(stage, grid, selected, axes) {
  if (!is.data.frame(grid) || !is.list(selected)) return(data.frame())
  out <- lapply(intersect(axes, intersect(names(grid), names(selected))), function(axis) {
    values <- suppressWarnings(as.numeric(grid[[axis]]))
    values <- sort(unique(values[is.finite(values)]))
    chosen <- suppressWarnings(as.numeric(selected[[axis]][1L]))
    edge <- if (!length(values) || !is.finite(chosen)) "unknown" else if (chosen == values[1L]) "lower" else if (chosen == values[length(values)]) "upper" else "none"
    data.frame(stage = stage, parameter = axis, tested_min = if (length(values)) values[1L] else NA_real_, tested_max = if (length(values)) values[length(values)] else NA_real_, selected_value = chosen, boundary = edge, stringsAsFactors = FALSE)
  })
  if (length(out)) do.call(rbind, out) else data.frame()
}

m0_grid <- expand.grid(
  cls_thr = 0.26, use_cls = FALSE,
  p_thr = c(0, 0.00025, 0.0005, 0.001, 0.002, 0.003, 0.004, 0.005, 0.006),
  prev_thr = c(0, 0.00025, 0.0005, 0.001, 0.002, 0.003),
  n_consec = 5L, L = 2L, eps = 0, K_sum = 5L,
  p_sum_thr = c(0, 0.025, 0.035, 0.045, 0.05, 0.055, 0.06, 0.065),
  N_req = 4L, w_min = 13L, w_max = 26L, K_dp = 3L,
  dp_thr = 0.01, sorted = FALSE,
  KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
)
m1_grid <- tidyr::crossing(
  k_ref = c(20L, 25L, 30L, 40L, 50L),
  multi_temperature = 0.25, template_shift = 0L,
  align_rise_weight = 1, slope_window = 6L,
  slope_weight = c(8, 12, 16, 20, 30)
)
boundaries <- rbind(
  boundary_rows("M0 Asgard", m0_grid, asgard_result$components$m0$config, c("p_thr", "prev_thr", "p_sum_thr")),
  boundary_rows("M1 Asgard", m1_grid, asgard_result$components$m1$config, c("k_ref", "slope_weight")),
  boundary_rows("M2 Asgard", asgard_m2_grid, selected_m2, c("delta", "Kr", "k_f", "k_e", "alpha_state", "bias_alpha", "bias_beta", "k_sp"))
)
if (nrow(boundaries)) utils::write.csv(boundaries, file.path(artifact_dir, "comparison_to_bcc_boundaries.csv"), row.names = FALSE)

fmt <- function(x) ifelse(is.na(x), "NA", formatC(x, digits = 8, format = "fg", flag = "#"))
metric_lines <- apply(metrics, 1L, function(row) paste0(
  "| ", row[["system"]], " | ", row[["holdout"]], " | ", row[["status"]],
  " | ", fmt(as.numeric(row[["ignition_week"]])), " | ", fmt(as.numeric(row[["bernoulli_nll"]])),
  " | ", fmt(as.numeric(row[["mae"]])), " | ", row[["n_predictions"]], " |"
))
boundary_lines <- if (nrow(boundaries)) apply(boundaries, 1L, function(row) paste0(
  "| ", row[["stage"]], " | ", row[["parameter"]], " | ", row[["tested_min"]],
  " | ", row[["tested_max"]], " | ", row[["selected_value"]], " | ", row[["boundary"]], " |"
)) else "| (none recorded) | | | | | |"

report <- c(
  "# 2018–19 holdout comparison: Asgard vs BCC",
  "",
  "The holdout label is `2018-19`; season labels are not ordered. The Asgard run is the current governed API retry after the NA-safe M1 scoring fix. The BCC artifact is a historical/manual baseline and is not treated as governed evidence.",
  "",
  "## Replay metrics",
  "",
  "| system | holdout | status | ignition week | Bernoulli NLL | MAE | predictions |",
  "|---|---|---|---:|---:|---:|---:|",
  metric_lines,
  "",
  paste0("Asgard training seasons (", length(training_asgard), "): ", paste(training_asgard, collapse = ", ")), 
  paste0("BCC training seasons (", length(training_bcc), "): ", paste(training_bcc, collapse = ", ")), 
  paste0("Asgard selected M2 specification: `", selected_m2_id, "`"),
  "",
  "## Asgard boundary audit",
  "",
  "| stage | parameter | tested min | tested max | selected | boundary |",
  "|---|---|---:|---:|---:|---|",
  boundary_lines,
  "",
  "## BCC audit finding",
  "",
  "The archived BCC audit recorded unresolved positive M0 edge winners (p_thr and p_sum_thr) and therefore classified that historical run as not governed under the current boundary policy.",
  "",
  "```text",
  bcc_audit,
  "```"
)
writeLines(report, file.path(run_dir, "comparison_to_bcc_2018_19.md"))
message("Wrote Asgard/BCC comparison: ", file.path(run_dir, "comparison_to_bcc_2018_19.md"))
