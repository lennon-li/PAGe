#!/usr/bin/env Rscript

# Governed 2015-16 holdout cycle.
# M0 -> M1 -> M2 are settled in order; every non-null boundary is expanded
# before the dependent stage is allowed to start.  Existing checkpoints are
# reused on resume.

suppressPackageStartupMessages(library(PAGe))
suppressPackageStartupMessages({
  library(dplyr)
  library(MMWRweek)
})

run_dir <- Sys.getenv(
  "PAGE_RUN_DIR",
  "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812/holdouts-and-docs/2015-16"
)
artifact_dir <- file.path(run_dir, "artifacts")
checkpoint_dir <- file.path(run_dir, "checkpoints")
status_path <- file.path(run_dir, "status.tsv")
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)

write_status <- function(status, detail = "") {
  row <- data.frame(
    timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    status = status, detail = detail, stringsAsFactors = FALSE
  )
  write.table(
    row, status_path, sep = "\t", row.names = FALSE,
    col.names = !file.exists(status_path), append = file.exists(status_path),
    quote = FALSE
  )
}

page_main_pid <- Sys.getpid()
options(error = function() {
  if (identical(Sys.getpid(), page_main_pid)) {
    write_status("failed", "unhandled R error; inspect run.log")
  }
  traceback(2)
  q(status = 1L, save = "no")
})

write_status("started", "governed 2015-16 M0 -> M1 -> M2 cycle")

hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv")
holdout <- "2015-16"
permanent_exclusions <- c("2011-12", "2020-21", "2021-22")
n_cores <- as.integer(Sys.getenv("PAGE_N_CORES", "12"))

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
training_seasons <- setdiff(
  sort(unique(allD$season)), c(permanent_exclusions, holdout)
)
selection <- PAGe::validate_season_selection(
  allD, training_seasons = training_seasons,
  exclude_seasons = permanent_exclusions,
  holdout_seasons = holdout, application_seasons = character(0)
)
saveRDS(selection, file.path(artifact_dir, "season_selection.rds"))

expand_until_settled <- function(tuning, stage, grid, tune_again,
                                 max_rounds = 8L) {
  m2_gain_caps <- if (identical(stage, "M2")) {
    PAGe::default_m2_nll_gain_caps()
  } else {
    NULL
  }
  for (round in seq_len(max_rounds)) {
    report <- PAGe::inspect_tuning_boundaries(
      tuning, stage = stage, grid = grid, warn = FALSE,
      min_nll_gain = m2_gain_caps
    )
    write.csv(
      report,
      file.path(artifact_dir, paste0(
        tolower(stage), "_boundary_report_round", round, ".csv"
      )), row.names = FALSE
    )
    if (!any(report$decision == "expand_required")) {
      return(list(tuning = tuning, grid = grid, report = report))
    }

    if (identical(stage, "M1")) {
      grid_next <- PAGe::expand_tuning_grid(
        tuning, stage = stage, grid = grid, n_weeks = 52L,
        steps = c(k_ref = 1),
        m1_k_ref_bounds = c(lower = 10L, upper = 52L)
      )
    } else {
      grid_next <- PAGe::expand_tuning_grid(
        tuning, stage = stage, grid = grid
      )
    }
    if (nrow(grid_next) <= nrow(grid)) {
      stop(
        stage, " remains at a configured hard boundary after ", round,
        " expansion round(s); dependent stage was not started.",
        call. = FALSE
      )
    }
    grid <- grid_next
    write.csv(
      grid, file.path(artifact_dir, paste0(
        tolower(stage), "_expanded_grid_round", round, ".csv"
      )), row.names = FALSE
    )
    tuning <- tune_again(grid)
  }
  stop(stage, " remained unresolved after ", max_rounds,
       " expansion rounds; dependent stage was not started.", call. = FALSE)
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
    checkpoint_dir = file.path(checkpoint_dir, "m0"),
    previous_results = m0
  )
)
m0 <- PAGe::validate_m0_tuning(
  m0_cycle$tuning, grid = m0_cycle$grid, check_boundaries = TRUE
)
saveRDS(m0, file.path(artifact_dir, "m0_tuning.rds"))
write.csv(m0_cycle$grid, file.path(artifact_dir, "m0_grid.csv"), row.names = FALSE)
m0_fit <- PAGe::fit_m0(
  allD, selection, config = m0$best_params, manual_labels = manual_labels
)
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
if (any(m1_cycle$report$decision == "expand_required")) {
  stop("M1 remained unresolved after expansion; M2 was not started.", call. = FALSE)
}
m1 <- PAGe::validate_m1_tuning(m1_cycle$tuning, check_boundaries = TRUE)
saveRDS(m1, file.path(artifact_dir, "m1_tuning.rds"))
write.csv(m1_cycle$grid, file.path(artifact_dir, "m1_grid.csv"), row.names = FALSE)
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
m2_grid <- PAGe::plan_m2_grid(NULL, max_finalists = 6L, max_specs = 64L)
expanded_m2 <- list.files(
  artifact_dir, pattern = "^m2_expanded_grid_round[0-9]+\\.csv$",
  full.names = TRUE
)
if (length(expanded_m2)) {
  round_number <- as.integer(sub(
    "^m2_expanded_grid_round([0-9]+)\\.csv$", "\\1", basename(expanded_m2)
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
  n_cores = n_cores, checkpoint_dir = file.path(checkpoint_dir, "m2"),
  verbose = TRUE
)
m2_cycle <- expand_until_settled(
  m2, "M2", m2_grid,
  function(grid) PAGe::tune_m2(
    allD, selection = selection, m0 = m0, m1 = m1, grid = grid,
    n_cores = n_cores, checkpoint_dir = file.path(checkpoint_dir, "m2"),
    verbose = TRUE
  )
)
m2 <- PAGe::validate_m2_tuning(
  m2_cycle$tuning,
  check_boundaries = TRUE,
  min_nll_gain = PAGe::default_m2_nll_gain_caps()
)
saveRDS(m2, file.path(artifact_dir, "m2_tuning.rds"))
write.csv(m2_cycle$grid, file.path(artifact_dir, "m2_grid.csv"), row.names = FALSE)

m2_fit <- PAGe::fit_m2(
  allD, selection, m0 = m0, m1 = m1, config = m2$best_spec,
  n_cores = n_cores, verbose = TRUE
)
m2 <- PAGe::freeze_m2(m2_fit, tuning = m2)
kit <- PAGe::assemble_kit(m0, m1, m2, best_spec_id = m2$best_spec_id)
PAGe::validate_page_kit(kit)
saveRDS(m2, file.path(artifact_dir, "m2_frozen.rds"))
saveRDS(kit, file.path(artifact_dir, "candidate_pre_holdout.rds"))

write_status("running", "M2 settled; strict 2015-16 replay")
replay <- PAGe::replay_season_holdout(
  kit, allD, season = holdout, kit_compatibility = "strict"
)
if (!identical(as.character(replay$status), "unseen_replay_complete")) {
  stop("Replay did not satisfy unseen-replay contract: ", replay$status,
       call. = FALSE)
}
if (!is.data.frame(replay$predictions) || !nrow(replay$predictions)) {
  stop("Replay returned no predictions for ", holdout, call. = FALSE)
}
saveRDS(replay, file.path(artifact_dir, "holdout_2015_16_replay.rds"))
saveRDS(replay$metrics, file.path(artifact_dir, "holdout_2015_16_metrics.rds"))
write.csv(replay$predictions,
          file.path(artifact_dir, "holdout_2015_16_predictions.csv"),
          row.names = FALSE)
write.csv(as.data.frame(replay$metrics$overall),
          file.path(artifact_dir, "holdout_2015_16_metrics.csv"),
          row.names = FALSE)
run_summary <- list(
  holdout_season = holdout,
  training_seasons = training_seasons,
  replay_status = replay$status,
  ignition_week = replay$ignition_week,
  n_predictions = nrow(replay$predictions),
  metrics = replay$metrics$overall,
  selected_m2 = m2$best_spec_id,
  package_version = as.character(utils::packageVersion("PAGe")),
  artifact_root = run_dir
)
saveRDS(run_summary, file.path(artifact_dir, "run_summary.rds"))
write_status("success", paste0(
  "predictions=", nrow(replay$predictions),
  "; selected_m2=", m2$best_spec_id
))
message("2015-16 governed holdout replay complete: ",
        nrow(replay$predictions), " predictions")
