#!/usr/bin/env Rscript

# Replay the frozen 2018-19 candidate produced by run_2018_cycle.R.
# This script is intentionally separate from tuning: the holdout is touched
# only after the pre-holdout kit has been validated and frozen.

script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script_file) || !nzchar(script_file)) {
  script_file <- "2018/replay_2018_19.R"
}
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)

if (!requireNamespace("devtools", quietly = TRUE)) {
  stop("The replay requires the devtools package.")
}
suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))
suppressPackageStartupMessages({
  library(dplyr)
  library(MMWRweek)
})

artifact_root <- Sys.getenv(
  "PAGE_ARTIFACT_ROOT",
  "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812"
)
run_id <- Sys.getenv("PAGE_RUN_ID", "2018-final2")
run_dir <- file.path(artifact_root, run_id)
artifact_dir <- file.path(run_dir, "artifacts")
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)

holdout_season <- "2018-19"
candidate_path <- file.path(artifact_dir, "candidate_pre_holdout.rds")
hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv")
if (!file.exists(candidate_path)) stop("Candidate kit not found: ", candidate_path)
if (!file.exists(hist_path)) stop("Authorized historical CSV not found: ", hist_path)

n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(
    as.Date(paste0(as.integer(start_year), "-12-31"))
  )$MMWRweek == 53L)
}

raw <- PAGe::load_flu_hist(hist_path)
allD <- raw |>
  mutate(
    season = as.character(season),
    week = as.integer(week),
    start_year = as.integer(seasonstart),
    y = as.numeric(pos_flua),
    N = as.numeric(test_flu),
    weekF = ((week - 27L) %% n_weeks_in_start_year(start_year)) + 1L
  ) |>
  select(season, weekF, y, N, everything()) |>
  PAGe::prepare_surveillance_data()

candidate <- readRDS(candidate_path)
PAGe::validate_page_kit(candidate)
training_seasons <- as.character(
  if (is.null(candidate$m2_production$training_seasons)) {
    character(0)
  } else {
    candidate$m2_production$training_seasons
  }
)
if (holdout_season %in% training_seasons) {
  stop("Holdout leakage: ", holdout_season, " is present in the frozen M2 training seasons.")
}
replay <- PAGe::replay_season_holdout(
  candidate,
  allD,
  season = holdout_season,
  kit_compatibility = "strict"
)
if (!identical(as.character(replay$status), "unseen_replay_complete")) {
  stop("Replay did not satisfy the unseen-replay contract: ", replay$status)
}
if (!is.data.frame(replay$predictions) || !nrow(replay$predictions)) {
  stop("Replay returned no predictions for ", holdout_season)
}

saveRDS(replay, file.path(artifact_dir, "holdout_2018_19_replay.rds"))
saveRDS(replay$metrics, file.path(artifact_dir, "holdout_2018_19_metrics.rds"))
utils::write.csv(
  replay$predictions,
  file.path(artifact_dir, "holdout_2018_19_predictions.csv"),
  row.names = FALSE
)
utils::write.csv(
  as.data.frame(replay$metrics$overall, stringsAsFactors = FALSE),
  file.path(artifact_dir, "holdout_2018_19_metrics.csv"),
  row.names = FALSE
)
writeLines(
  c(
    paste0("status=", replay$status),
    paste0("season=", replay$season),
    paste0("ignition_week=", replay$ignition_week),
    paste0("ignition_status=", replay$ignition_status),
    paste0("n_predictions=", nrow(replay$predictions))
  ),
  file.path(run_dir, "replay_status.txt")
)

message("2018-19 unseen replay complete: ", nrow(replay$predictions), " predictions")
