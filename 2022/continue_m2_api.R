#!/usr/bin/env Rscript

# Continue the 2022-23 governed cycle from settled M0 and expanded M1
# artifacts. This intentionally does not call tune_m0() or tune_m1(); both
# grids are already settled and their fitted stage artifacts are rebuilt only
# as inputs required by the dependent M2 search.

repo_root <- "/home/yeli/repos/PAGe"
artifact_dir <- "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812/2022-final-expanded-v3"
checkpoint_dir <- file.path(artifact_dir, "checkpoints")
status_path <- file.path(artifact_dir, "m2_continuation_status.tsv")

write_status <- function(status, detail = "") {
  row <- data.frame(
    timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    status = status,
    detail = detail,
    stringsAsFactors = FALSE
  )
  write.table(
    row, status_path, sep = "\t", row.names = FALSE,
    col.names = !file.exists(status_path), append = file.exists(status_path),
    quote = FALSE
  )
}

options(error = function() {
  write_status("failed", "unhandled R error; inspect m2_continuation.log")
  traceback(2)
  q(status = 1L, save = "no")
})

setwd(repo_root)
suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))
suppressPackageStartupMessages({
  library(dplyr)
  library(MMWRweek)
})

write_status("started", "M2 continuation from settled M0 and expanded M1")

hist_path <- "/home/yeli/FLU/flu_testing_data.csv"
holdout <- "2022-23"
permanent_exclusions <- c("2011-12", "2015-16", "2020-21", "2021-22")
n_cores <- as.integer(Sys.getenv("PAGE_N_CORES", unset = "12"))

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

training_seasons <- setdiff(
  sort(unique(allD$season)),
  c(permanent_exclusions, holdout)
)
selection <- PAGe::validate_season_selection(
  allD,
  training_seasons = training_seasons,
  exclude_seasons = permanent_exclusions,
  holdout_seasons = holdout,
  application_seasons = character(0)
)

m0_tuning <- readRDS(file.path(artifact_dir, "artifacts", "m0_tuning.rds"))
m1_tuning <- readRDS(file.path(artifact_dir, "m1_expanded_tuning_api.rds"))
m2_grid <- read.csv(
  file.path(artifact_dir, "m2_planned_grid.csv"),
  stringsAsFactors = FALSE
)

# Promote the API-produced low-level M1 result to the governed shape needed by
# freeze_m1(); its scores and grid are exactly the expanded checkpoint result.
m1_tuning$selection <- selection
m1_tuning$data_id <- PAGe:::.stage_training_data_id(
  PAGe:::.selected_training_data(allD, selection)
)
m1_tuning$manual_labels <- m0_tuning$manual_labels[training_seasons] - 1L
class(m1_tuning) <- c("page_m1_tuning", "list")
m1_tuning <- PAGe::validate_m1_tuning(m1_tuning, check_boundaries = TRUE)

write_status("running", paste0("fitting governed M0/M1 inputs; M2 specs=", nrow(m2_grid), "; cores=", n_cores))

m0_fit <- PAGe::fit_m0(
  allD, selection, config = m0_tuning$best_params,
  manual_labels = m0_tuning$manual_labels,
  flag_args = m0_tuning$flag_args
)
m0 <- PAGe::freeze_m0(m0_fit, tuning = m0_tuning)

best_m1 <- m1_tuning$best[1L, , drop = FALSE]
m1_config <- PAGe::m1_make_params(
  k_ref = best_m1$k_ref,
  temperature = best_m1$multi_temperature,
  rise_weight = best_m1$align_rise_weight,
  slope_weight = best_m1$slope_weight,
  slope_window = best_m1$slope_window,
  ref_method = "fs",
  trough_weight = 0.1,
  peak_decay = 0.3
)
m1_fit <- PAGe::fit_m1(allD, selection, m0 = m0, config = m1_config)
m1 <- PAGe::freeze_m1(m1_fit, tuning = m1_tuning)

saveRDS(m0, file.path(artifact_dir, "m0_frozen_api.rds"))
saveRDS(m1, file.path(artifact_dir, "m1_frozen_api.rds"))

m2_tuning <- PAGe::tune_m2(
  allD,
  selection = selection,
  m0 = m0,
  m1 = m1,
  grid = m2_grid,
  n_cores = n_cores,
  checkpoint_dir = file.path(checkpoint_dir, "m2"),
  verbose = TRUE
)
m2_tuning <- PAGe::validate_m2_tuning(m2_tuning, check_boundaries = TRUE)
saveRDS(m2_tuning, file.path(artifact_dir, "m2_tuning_api.rds"))

m2_fit <- PAGe::fit_m2(
  allD, selection, m0 = m0, m1 = m1,
  config = m2_tuning$best_spec,
  n_cores = n_cores,
  verbose = TRUE
)
m2 <- PAGe::freeze_m2(m2_fit, tuning = m2_tuning)
kit <- PAGe::assemble_kit(
  m0, m1, m2,
  best_spec_id = m2_tuning$best_spec_id
)
PAGe::validate_page_kit(kit)
saveRDS(m2, file.path(artifact_dir, "m2_frozen_api.rds"))
saveRDS(kit, file.path(artifact_dir, "candidate_pre_holdout_api.rds"))
write_status("success", paste0("selected_m2=", m2_tuning$best_spec_id))
