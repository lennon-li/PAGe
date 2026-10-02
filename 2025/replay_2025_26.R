#!/usr/bin/env Rscript

script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script_file) || !nzchar(script_file)) script_file <- "2025/replay_2025_26.R"
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)
suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))
suppressPackageStartupMessages({
  library(dplyr)
  library(MMWRweek)
})
artifact_root <- Sys.getenv("PAGE_ARTIFACT_ROOT", "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812")
run_id <- Sys.getenv("PAGE_RUN_ID", "2025-final-api")
run_dir <- file.path(artifact_root, run_id)
artifact_dir <- file.path(run_dir, "artifacts")
hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "")
# No default. This used to fall back to /home/yeli/FLU/flu_testing_data.csv,
# which is a TRUNCATED extract (2025-26 stops at weekF 28 of 53). The
# 2026-09-17 outer-fold campaign trained every fold on it without anyone
# noticing, because a silent default cannot be reviewed. The authorized feed
# must now be named explicitly, as the production runner already requires.
if (!nzchar(hist_path)) {
  stop("Set PAGE_FLU_HIST_FILE to the authorized historical CSV.", call. = FALSE)
}
if (!file.exists(hist_path)) stop("Authorized historical CSV not found: ", hist_path)
n_weeks_in_start_year <- function(start_year) 52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(as.integer(start_year), "-12-31")))$MMWRweek == 53L)
raw <- PAGe::load_flu_hist(hist_path)
calendar <- PAGe::page_season_calendar(
  dates = as.Date(raw$week_start_date), start_week = 27L
)
allD <- raw |>
  mutate(
    pho_season = as.character(season), season = calendar$season,
    week = calendar$week, start_year = calendar$start_year,
    weekS = calendar$weekS, y = as.numeric(pos_flua), N = as.numeric(test_flu),
    weekF = calendar$weekF
  ) |>
  select(season, weekF, y, N, everything()) |>
  PAGe::prepare_surveillance_data()
kit <- readRDS(file.path(artifact_dir, "candidate_pre_holdout.rds"))
PAGe::validate_page_kit(kit)
replay <- PAGe::replay_season_holdout(kit, allD, season = "2025-26", kit_compatibility = "strict")
saveRDS(replay, file.path(artifact_dir, "holdout_2025_26_replay.rds"))
write.csv(replay$predictions, file.path(artifact_dir, "holdout_2025_26_predictions.csv"), row.names = FALSE)
write.csv(as.data.frame(replay$metrics$overall), file.path(artifact_dir, "holdout_2025_26_metrics.csv"), row.names = FALSE)
message("2025-26 replay status: ", replay$status)
