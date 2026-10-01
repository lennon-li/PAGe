#!/usr/bin/env Rscript

# Replay the frozen 2016-17 candidate with the installed PAGe package.

script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script_file) || !nzchar(script_file)) {
  script_file <- "2016/replay_2016_17.R"
}
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)

suppressPackageStartupMessages(library(PAGe))
suppressPackageStartupMessages({ library(dplyr); library(MMWRweek) })

artifact_root <- Sys.getenv(
  "PAGE_ARTIFACT_ROOT",
  "/mnt/nfsv4/Users/yeli/PAGe-artifacts/asgard-archive-20260812"
)
run_id <- Sys.getenv("PAGE_RUN_ID", "bcc-2016-17-v1")
run_dir <- file.path(artifact_root, run_id)
artifact_dir <- file.path(run_dir, "artifacts")
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)

holdout_season <- "2016-17"
candidate_path <- file.path(artifact_dir, "candidate_pre_holdout.rds")
hist_path <- Sys.getenv(
  "PAGE_FLU_HIST_FILE", "/home/yeli/repos/PAGe/data/flu_testing_data.csv"
)
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
    season = as.character(season), week = as.integer(week),
    start_year = as.integer(seasonstart), y = as.numeric(pos_flua),
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
  stop("Holdout leakage: ", holdout_season,
       " is present in the frozen M2 training seasons.")
}
replay <- PAGe::replay_season_holdout(
  candidate, allD, season = holdout_season, kit_compatibility = "strict"
)
if (!identical(as.character(replay$status), "unseen_replay_complete")) {
  stop("Replay did not satisfy the unseen-replay contract: ", replay$status)
}
if (!is.data.frame(replay$predictions) || !nrow(replay$predictions)) {
  stop("Replay returned no predictions for ", holdout_season)
}

saveRDS(replay, file.path(artifact_dir, "holdout_2016_17_replay.rds"))
saveRDS(replay$metrics, file.path(artifact_dir, "holdout_2016_17_metrics.rds"))
write.csv(replay$predictions,
          file.path(artifact_dir, "holdout_2016_17_predictions.csv"),
          row.names = FALSE)
write.csv(as.data.frame(replay$metrics$overall, stringsAsFactors = FALSE),
          file.path(artifact_dir, "holdout_2016_17_metrics.csv"),
          row.names = FALSE)
writeLines(c(
  paste0("status=", replay$status), paste0("season=", replay$season),
  paste0("ignition_week=", replay$ignition_week),
  paste0("ignition_status=", replay$ignition_status),
  paste0("n_predictions=", nrow(replay$predictions))
), file.path(run_dir, "replay_status.txt"))
message("2016-17 unseen replay complete: ", nrow(replay$predictions), " predictions")
