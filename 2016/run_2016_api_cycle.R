#!/usr/bin/env Rscript

# Governed BCC 2016-17 holdout cycle with package-level boundary expansion.
# Every stage checkpoints its scores; an unresolved edge is expanded through
# expand_tuning_grid() and resumed before the dependent stage is allowed.

suppressPackageStartupMessages(library(PAGe))
suppressPackageStartupMessages({
  library(dplyr)
  library(MMWRweek)
})

run_dir <- Sys.getenv(
  "PAGE_RUN_DIR",
  "/mnt/nfsv4/Users/yeli/PAGe-artifacts/asgard-archive-20260812/bcc-2016-17-v3"
)
artifact_dir <- file.path(run_dir, "artifacts")
checkpoint_dir <- file.path(run_dir, "checkpoints")
status_path <- file.path(run_dir, "status.tsv")
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)

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

page_main_pid <- Sys.getpid()
options(error = function() {
  # Do not let a future worker's late teardown error overwrite the main
  # process terminal status after a successful strict replay.
  if (identical(Sys.getpid(), page_main_pid)) {
    write_status("failed", "unhandled R error; inspect run.log")
  }
  traceback(2)
  q(status = 1L, save = "no")
})

write_status("started", "governed M0 -> M1 -> M2 cycle with API expansion")

hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/repos/PAGe/data/flu_testing_data.csv")
holdout <- "2016-17"
permanent_exclusions <- c("2011-12", "2015-16", "2020-21", "2021-22")
n_cores <- as.integer(Sys.getenv("PAGE_N_CORES", "16"))

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

manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L, "2025-26" = 19L
)
training_seasons <- setdiff(sort(unique(allD$season)), c(permanent_exclusions, holdout))
selection <- PAGe::validate_season_selection(
  allD,
  training_seasons = training_seasons,
  exclude_seasons = permanent_exclusions,
  holdout_seasons = holdout,
  application_seasons = character(0)
)

expand_until_settled <- function(tuning, stage, grid, tune_again, max_rounds = 8L) {
  for (round in seq_len(max_rounds)) {
    # The first pass may legitimately identify an edge; defer user-facing
    # warnings until the final report so a deferred R warning cannot be
    # mistaken for a boundary that was passed to the dependent stage.
    report <- PAGe::inspect_tuning_boundaries(tuning, stage = stage, grid = grid, warn = FALSE)
    write.csv(report, file.path(artifact_dir, paste0(tolower(stage), "_boundary_report_round", round, ".csv")), row.names = FALSE)
    if (!any(report$decision == "expand_required")) return(list(tuning = tuning, grid = grid, report = report))
    grid <- PAGe::expand_tuning_grid(tuning, stage = stage, grid = grid)
    write.csv(grid, file.path(artifact_dir, paste0(tolower(stage), "_expanded_grid_round", round, ".csv")), row.names = FALSE)
    tuning <- tune_again(grid)
  }
  stop(stage, " remained unresolved after ", max_rounds, " expansion rounds.", call. = FALSE)
}

write_status("running", paste0("M0 tuning; cores=", n_cores))
m0_grid <- PAGe:::.default_m0_grid()
m0 <- PAGe::tune_m0(
  allD, grid = m0_grid, manual_labels = manual_labels,
  n_cores = n_cores, verbose = TRUE, selection = selection,
  checkpoint_dir = file.path(checkpoint_dir, "m0")
)
m0_cycle <- expand_until_settled(
  m0, "M0", m0_grid,
  function(grid) PAGe::tune_m0(
    allD, grid = grid, manual_labels = manual_labels,
    n_cores = n_cores, verbose = TRUE, selection = selection,
    checkpoint_dir = file.path(checkpoint_dir, "m0"), previous_results = m0
  )
)
m0 <- PAGe::validate_m0_tuning(m0_cycle$tuning, grid = m0_cycle$grid, check_boundaries = TRUE)
m0_fit <- PAGe::fit_m0(allD, selection, config = m0$best_params, manual_labels = manual_labels)
m0 <- PAGe::freeze_m0(m0_fit, tuning = m0)
saveRDS(m0, file.path(artifact_dir, "m0_frozen.rds"))

write_status("running", "M0 settled; M1 tuning")
m1_grid <- PAGe::default_m1_grid()
m1 <- PAGe::tune_m1(
  allD, m0 = m0, m1 = list(m1_params = PAGe::m1_make_params()),
  grid = m1_grid, n_cores = n_cores, verbose = TRUE,
  selection = selection, checkpoint_dir = file.path(checkpoint_dir, "m1"),
  manual_labels = manual_labels
)
m1_cycle <- expand_until_settled(
  m1, "M1", m1_grid,
  function(grid) PAGe::tune_m1(
    allD, m0 = m0, m1 = list(m1_params = PAGe::m1_make_params()),
    grid = grid, n_cores = n_cores, verbose = TRUE,
    selection = selection, checkpoint_dir = file.path(checkpoint_dir, "m1"),
    manual_labels = manual_labels
  )
)
# Keep the stage handoff explicit: M2 must never start from a tuning object
# whose final grid still has an unresolved non-null edge.
if (any(m1_cycle$report$decision == "expand_required")) {
  stop("M1 remained unresolved after expansion; M2 was not started.", call. = FALSE)
}
m1 <- PAGe::validate_m1_tuning(m1_cycle$tuning, check_boundaries = TRUE)
best_m1 <- m1$best[1L, , drop = FALSE]
m1_config <- PAGe::m1_make_params(
  k_ref = best_m1$k_ref, temperature = best_m1$multi_temperature,
  rise_weight = best_m1$align_rise_weight, slope_weight = best_m1$slope_weight,
  slope_window = best_m1$slope_window, ref_method = "fs"
)
m1_fit <- PAGe::fit_m1(allD, selection, m0 = m0, config = m1_config)
m1 <- PAGe::freeze_m1(m1_fit, tuning = m1)
saveRDS(m1, file.path(artifact_dir, "m1_frozen.rds"))

write_status("running", "M1 settled; M2 tuning")
# When resuming after a governed boundary stop, seed the next invocation from
# the latest expanded grid.  This preserves the M2 checkpoint identity and
# avoids rescoring the already completed specifications.
m2_grid <- PAGe::plan_m2_grid(NULL, max_finalists = 6L, max_specs = 64L)
expanded_m2 <- list.files(
  artifact_dir,
  pattern = "^m2_expanded_grid_round[0-9]+\\.csv$",
  full.names = TRUE
)
if (length(expanded_m2)) {
  round_number <- as.integer(sub(
    "^m2_expanded_grid_round([0-9]+)\\.csv$", "\\1",
    basename(expanded_m2)
  ))
  latest_grid <- expanded_m2[[which.max(round_number)]]
  resumed_grid <- tryCatch(
    utils::read.csv(latest_grid, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(error) NULL
  )
  if (is.data.frame(resumed_grid) && nrow(resumed_grid) > nrow(m2_grid)) {
    m2_grid <- resumed_grid
    message("[runner] Resuming M2 from ", basename(latest_grid),
            " (", nrow(m2_grid), " specs).")
  }
}
m2 <- PAGe::tune_m2(
  allD, selection = selection, m0 = m0, m1 = m1, grid = m2_grid,
  n_cores = n_cores, checkpoint_dir = file.path(checkpoint_dir, "m2"), verbose = TRUE
)
m2_cycle <- expand_until_settled(
  m2, "M2", m2_grid,
  function(grid) PAGe::tune_m2(
    allD, selection = selection, m0 = m0, m1 = m1, grid = grid,
    n_cores = n_cores, checkpoint_dir = file.path(checkpoint_dir, "m2"), verbose = TRUE
  )
)
m2 <- PAGe::validate_m2_tuning(m2_cycle$tuning, check_boundaries = TRUE)
saveRDS(m2, file.path(artifact_dir, "m2_tuning.rds"))

m2_fit <- PAGe::fit_m2(allD, selection, m0 = m0, m1 = m1, config = m2$best_spec, n_cores = n_cores, verbose = TRUE)
m2 <- PAGe::freeze_m2(m2_fit, tuning = m2)
kit <- PAGe::assemble_kit(m0, m1, m2, best_spec_id = m2$best_spec_id)
PAGe::validate_page_kit(kit)
saveRDS(m2, file.path(artifact_dir, "m2_frozen.rds"))
saveRDS(kit, file.path(artifact_dir, "candidate_pre_holdout.rds"))

replay <- PAGe::replay_season_holdout(kit, allD, season = holdout, kit_compatibility = "strict")
saveRDS(replay, file.path(artifact_dir, "holdout_2016_17_replay.rds"))
saveRDS(replay$metrics, file.path(artifact_dir, "holdout_2016_17_metrics.rds"))
write.csv(replay$predictions, file.path(artifact_dir, "holdout_2016_17_predictions.csv"), row.names = FALSE)
write_status("success", paste0("selected_m2=", m2$best_spec_id))
