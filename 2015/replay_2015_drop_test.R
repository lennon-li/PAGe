#!/usr/bin/env Rscript

# Freeze and replay the current 2015-16 drop-test candidate.  The archived M1
# envelope predates the current payload-bound identity contract; migrate that
# identity in memory only and write new artifacts under distinct filenames.

root <- Sys.getenv(
  "PAGE_RUN_DIR",
  "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812/holdouts-and-docs/2015-16"
)
hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv")
n_cores <- as.integer(Sys.getenv("PAGE_N_CORES", "12"))
artifact_dir <- file.path(root, "artifacts")

pkgload::load_all("PAGe", quiet = TRUE)
suppressPackageStartupMessages({
  library(dplyr)
  library(MMWRweek)
})

raw <- PAGe::load_flu_hist(hist_path)
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(
    MMWRweek::MMWRweek(as.Date(paste0(as.integer(start_year), "-12-31")))$MMWRweek == 53L
  )
}
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

selection <- readRDS(file.path(artifact_dir, "season_selection.rds"))
m0 <- readRDS(file.path(artifact_dir, "m0_frozen.rds"))
m1 <- readRDS(file.path(artifact_dir, "m1_frozen.rds"))
tuning <- readRDS(file.path(artifact_dir, "m2_drop_test_tuning.rds"))

training_data <- PAGe:::.selected_training_data(allD, selection)
current_m1_id <- PAGe:::.stage_artifact_id(
  m1$stage, m1$selection, m1$config, m1$upstream_ids, m1$data_id,
  PAGe:::.stage_fit_payload(m1)
)
m1_current <- m1
m1_current$artifact_id <- current_m1_id

message("[2015 replay] fitting selected spec: ", tuning$best_spec_id)
m2_fit <- PAGe::fit_m2(
  allD, selection, m0 = m0, m1 = m1_current,
  config = tuning$best_spec, n_cores = n_cores, verbose = TRUE
)
m2 <- PAGe::freeze_m2(m2_fit, tuning = tuning)
kit <- PAGe::assemble_kit(m0, m1_current, m2, best_spec_id = tuning$best_spec_id)
PAGe::validate_page_kit(kit)

kit_path <- file.path(artifact_dir, "candidate_pre_holdout_drop_test.rds")
replay_path <- file.path(artifact_dir, "holdout_2015_16_replay_drop_test.rds")
saveRDS(m2, file.path(artifact_dir, "m2_frozen_drop_test.rds"))
saveRDS(kit, kit_path)

message("[2015 replay] running strict unseen replay")
replay <- PAGe::replay_season_holdout(
  kit, allD, season = "2015-16", kit_compatibility = "strict"
)
stopifnot(identical(as.character(replay$status), "unseen_replay_complete"))
saveRDS(replay, replay_path)
saveRDS(replay$metrics, file.path(artifact_dir, "holdout_2015_16_metrics_drop_test.rds"))
write.csv(
  replay$predictions,
  file.path(artifact_dir, "holdout_2015_16_predictions_drop_test.csv"),
  row.names = FALSE
)
write.csv(
  as.data.frame(replay$metrics$overall),
  file.path(artifact_dir, "holdout_2015_16_metrics_drop_test.csv"),
  row.names = FALSE
)
message(
  "[2015 replay] status=", replay$status,
  " n_predictions=", nrow(replay$predictions),
  " nll=", format(replay$metrics$overall$bernoulli_nll, digits = 10),
  " mae=", format(replay$metrics$overall$mae, digits = 10)
)
