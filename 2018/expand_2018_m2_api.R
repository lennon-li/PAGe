#!/usr/bin/env Rscript

# Additive M2 boundary expansion for the exchangeable 2018-19 development
# cycle. Existing Phase-2 scores are migrated into a v2 checkpoint and are
# never recomputed; only newly appended specification IDs are evaluated.

script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script_file) || !nzchar(script_file)) {
  script_file <- "2018/expand_2018_m2_api.R"
}
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)
suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))
suppressPackageStartupMessages({
  library(dplyr)
  library(MMWRweek)
})

artifact_root <- Sys.getenv(
  "PAGE_ARTIFACT_ROOT",
  "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812"
)
source_dir <- file.path(artifact_root, "2018-final2-expanded")
run_dir <- file.path(artifact_root, "2018-final2-expanded-api")
artifact_dir <- file.path(run_dir, "artifacts")
checkpoint_dir <- file.path(run_dir, "checkpoints", "m2")
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
status_path <- file.path(run_dir, "status.tsv")
write_status <- function(status, detail = "") {
  row <- data.frame(
    timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    status = status, detail = detail, stringsAsFactors = FALSE
  )
  write.table(row, status_path, sep = "\t", row.names = FALSE,
              col.names = !file.exists(status_path), append = file.exists(status_path),
              quote = FALSE)
}
options(error = function() {
  write_status("failed", "unhandled error; inspect run.log")
  traceback(2)
  q(status = 1L, save = "no")
})

write_status("started", "preflight")
hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv")
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(
    as.Date(paste0(as.integer(start_year), "-12-31"))
  )$MMWRweek == 53L)
}
raw <- PAGe::load_flu_hist(hist_path)
allD <- raw |>
  mutate(
    season = as.character(season), week = as.integer(week),
    start_year = as.integer(seasonstart), y = as.numeric(pos_flua),
    N = as.numeric(test_flu),
    weekF = ((week - 27L) %% n_weeks_in_start_year(start_year)) + 1L
  ) |>
  select(season, weekF, y, N, everything()) |>
  PAGe::prepare_surveillance_data()

old_result <- readRDS(file.path(source_dir, "artifacts", "training_result.rds"))
old_m2 <- readRDS(file.path(source_dir, "artifacts", "m2_tuning.rds"))
selection <- readRDS(file.path(source_dir, "artifacts", "season_selection.rds"))
if (!inherits(selection, "page_season_selection")) {
  selection <- PAGe::validate_season_selection(
    allD,
    training_seasons = selection$training_seasons,
    exclude_seasons = selection$exclude_seasons,
    holdout_seasons = selection$holdout_seasons,
    application_seasons = selection$application_seasons
  )
}

# Recreate the frozen upstream stages from the original selected configs. This
# is fitting, not grid tuning; M0/M1 candidate scores are not rerun.
m0_fit <- PAGe::fit_m0(
  allD, selection, config = old_result$tuning$m0$best_params,
  manual_labels = old_result$components$m0$manual_labels,
  flag_args = old_result$components$m0$flag_args
)
m0 <- PAGe::freeze_m0(m0_fit)
m1_fit <- PAGe::fit_m1(
  allD, selection, m0 = m0,
  config = old_result$components$m1$m1_params
)
m1 <- PAGe::freeze_m1(m1_fit)

current <- old_m2
old_grid <- old_m2$grid
old_results <- old_m2$cv_results
if (is.null(old_results) || !length(old_results)) {
  stop("Original M2 result has no reusable cv_results.")
}
# Older archived objects may carry incomplete list names after serialization;
# the canonical IDs in the saved grid are authoritative.
names(old_results) <- PAGe:::.m2_spec_ids(old_grid)

iteration <- 0L
repeat {
  iteration <- iteration + 1L
  report <- PAGe::inspect_tuning_boundaries(
    current, stage = "M2", grid = current$grid, warn = FALSE
  )
  write.csv(report, file.path(artifact_dir, paste0("m2_boundary_report_", iteration, ".csv")),
            row.names = FALSE)
  unresolved <- subset(report, decision == "expand_required")
  if (!nrow(unresolved)) break

  next_grid <- PAGe::expand_tuning_grid(current, stage = "M2", grid = current$grid)
  new_ids <- setdiff(PAGe:::.m2_spec_ids(next_grid), names(old_results))
  if (!length(new_ids)) stop("Boundary expansion proposed no new M2 specification IDs.")
  write_status("running", paste0("M2 expansion iteration ", iteration,
                                  "; new_specs=", length(new_ids),
                                  "; cores=", parallel::detectCores()))

  # Seed a current-version checkpoint with all old scores. build_m2 then
  # evaluates only the appended IDs while retaining the same data/stage context.
  training_data <- PAGe:::.selected_training_data(allD, selection)
  checkpoint_identity <- PAGe:::.m2_checkpoint_identity(
    allD = training_data, test_seasons = selection$training_seasons,
    grid = next_grid, m0 = m0, m1 = m1
  )
  saveRDS(list(
    schema = "page_m2_phase2_checkpoint", version = 2L,
    identity = checkpoint_identity, results = old_results
  ), file.path(checkpoint_dir, "build_m2_phase2.rds"))

  tuned <- PAGe::tune_m2(
    allD, selection = selection, m0 = m0, m1 = m1, grid = next_grid,
    n_cores = parallel::detectCores(), checkpoint_dir = checkpoint_dir,
    verbose = TRUE
  )
  current <- PAGe::validate_m2_tuning(tuned, check_boundaries = FALSE)
  old_results <- current$cv_results
  saveRDS(current, file.path(artifact_dir, paste0("m2_tuning_api_", iteration, ".rds")))
}

current <- PAGe::validate_m2_tuning(current, check_boundaries = TRUE)
saveRDS(current, file.path(artifact_dir, "m2_tuning_api.rds"))
write.csv(current$grid, file.path(artifact_dir, "m2_grid_api.csv"), row.names = FALSE)
write.csv(current$summary, file.path(artifact_dir, "m2_summary_api.csv"), row.names = FALSE)
write.csv(current$scores, file.path(artifact_dir, "m2_fold_scores_api.csv"), row.names = FALSE)
saveRDS(m0, file.path(artifact_dir, "m0_frozen_api.rds"))
saveRDS(m1, file.path(artifact_dir, "m1_frozen_api.rds"))

m2_fit <- PAGe::fit_m2(
  allD, selection, m0 = m0, m1 = m1,
  config = current$best_spec, n_cores = parallel::detectCores(), verbose = TRUE
)
m2 <- PAGe::freeze_m2(m2_fit, tuning = current)
kit <- PAGe::assemble_kit(m0, m1, m2, best_spec_id = current$best_spec_id)
PAGe::validate_page_kit(kit)
saveRDS(kit, file.path(artifact_dir, "candidate_pre_holdout_api.rds"))
saveRDS(selection, file.path(artifact_dir, "season_selection.rds"))

replay <- PAGe::replay_season_holdout(kit, allD, season = "2018-19")
saveRDS(replay, file.path(artifact_dir, "holdout_2018_19_replay_api.rds"))
write.csv(replay$metrics$overall, file.path(artifact_dir, "holdout_2018_19_metrics_api.csv"), row.names = FALSE)
write.csv(replay$predictions, file.path(artifact_dir, "holdout_2018_19_predictions_api.csv"), row.names = FALSE)
write.csv(PAGe::inspect_tuning_boundaries(current, stage = "M2", grid = current$grid, warn = FALSE),
          file.path(artifact_dir, "m2_boundary_report_final.csv"), row.names = FALSE)
write_status("success", paste0("selected_m2=", current$best_spec_id,
                                "; specs=", nrow(current$grid)))
