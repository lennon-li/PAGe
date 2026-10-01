#!/usr/bin/env Rscript

# Additive M1 expansion for the BCC 2016-17 checkpoint. This script only
# inspects the saved 25-row score cache and writes the API-produced grid/report;
# it never reruns completed specifications.

suppressPackageStartupMessages(library(PAGe))

run_dir <- Sys.getenv(
  "PAGE_RUN_DIR",
  "/mnt/nfsv4/Users/yeli/PAGe-artifacts/asgard-archive-20260812/bcc-2016-17-v2"
)
checkpoint_dir <- file.path(run_dir, "checkpoints", "m1")
artifact_dir <- file.path(run_dir, "artifacts")
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)

scores <- readRDS(file.path(checkpoint_dir, "tune_m1_results.rds"))
if (!is.data.frame(scores) || nrow(scores) != 25L) {
  stop("Expected the completed 25-row BCC M1 score cache.")
}

base_grid <- data.table::CJ(
  k_ref = c(20L, 25L, 30L, 40L, 50L),
  multi_temperature = 0.25,
  template_shift = 0L,
  align_rise_weight = 1.0,
  slope_window = 6L,
  slope_weight = c(8.0, 12.0, 16.0, 20.0, 30.0),
  sorted = FALSE
)
base_grid$spec_id <- sprintf("s%03d", seq_len(nrow(base_grid)))
x <- list(
  scores = dplyr::left_join(base_grid, scores, by = "spec_id"),
  best = NULL,
  grid = base_grid
)
x$best <- dplyr::slice_min(x$scores, mae_weibull, n = 1L, with_ties = FALSE)

report <- PAGe::inspect_tuning_boundaries(x, stage = "M1", warn = TRUE)
expanded <- PAGe::expand_tuning_grid(x, stage = "M1")

write.csv(expanded, file.path(artifact_dir, "m1_expanded_grid_api.csv"), row.names = FALSE)
write.csv(report, file.path(artifact_dir, "m1_boundary_report_api.csv"), row.names = FALSE)
saveRDS(
  list(
    original_n = nrow(base_grid), expanded_n = nrow(expanded),
    added_ids = setdiff(expanded$spec_id, base_grid$spec_id),
    grid = expanded, boundary_report = report
  ),
  file.path(artifact_dir, "m1_expansion_api.rds")
)
cat(sprintf(
  "expanded %d -> %d specs; added %s\n",
  nrow(base_grid), nrow(expanded),
  paste(setdiff(expanded$spec_id, base_grid$spec_id), collapse = ",")
))
print(report)
