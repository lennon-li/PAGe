#!/usr/bin/env Rscript

# Governed 2018-19 holdout cycle.  All valid seasons other than the explicit
# permanent exclusions and 2018-19 are training seasons; season labels have no
# chronological precedence in this split.

script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script_file) || !nzchar(script_file)) {
  script_file <- "2018/run_2018_cycle.R"
}
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)

if (!requireNamespace("devtools", quietly = TRUE)) {
  stop("The 2018-19 cycle requires the devtools package.")
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
run_dir <- file.path(artifact_root, "2018")
artifact_dir <- file.path(run_dir, "artifacts")
checkpoint_dir <- file.path(run_dir, "checkpoints")
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)

status_path <- file.path(run_dir, "status.tsv")
log_path <- file.path(run_dir, "run.log")
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
  write_status("failed", "unhandled R error; inspect run.log")
  traceback(2)
  q(status = 1L, save = "no")
})
write_status("started", "preflight")

hist_path <- Sys.getenv(
  "PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv"
)
if (!file.exists(hist_path)) {
  stop("Authorized historical CSV not found: ", hist_path)
}
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

all_seasons <- sort(unique(allD$season))
permanent_exclusions <- c("2011-12", "2015-16", "2020-21", "2021-22")
holdout_season <- "2018-19"
training_seasons <- setdiff(all_seasons, c(permanent_exclusions, holdout_season))
selection <- PAGe::validate_season_selection(
  allD,
  training_seasons = training_seasons,
  exclude_seasons = permanent_exclusions,
  holdout_seasons = holdout_season,
  application_seasons = character(0)
)
m0_grid <- data.table::CJ(
  cls_thr = 0.26, use_cls = FALSE,
  p_thr = c(0.001, 0.002, 0.003, 0.004, 0.005),
  prev_thr = c(0.0005, 0.001, 0.002, 0.003),
  n_consec = 5L, L = 2L, eps = 0, K_sum = 5L,
  p_sum_thr = c(0.045, 0.050, 0.055, 0.060), N_req = 4L,
  w_min = 13L, w_max = 26L, K_dp = 3L, dp_thr = 0.01,
  sorted = FALSE
)
saveRDS(selection, file.path(artifact_dir, "season_selection.rds"))
saveRDS(
  list(
    created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    repo_root = repo_root,
    input_path = normalizePath(hist_path),
    input_sha256 = digest::digest(file = hist_path, algo = "sha256"),
    n_rows = nrow(allD), data_seasons = all_seasons,
    training_seasons = training_seasons,
    exclude_seasons = permanent_exclusions,
    holdout_seasons = holdout_season,
    application_seasons = character(0),
    n_cores = parallel::detectCores(), m0_grid_n = nrow(m0_grid)
  ),
  file.path(artifact_dir, "run_manifest.rds")
)

write_status("running", paste0("retune; cores=", parallel::detectCores()))
started <- Sys.time()
result <- PAGe::train_pipeline(
  allD = allD, mode = "retune", prospective_holdout = holdout_season,
  loso_seasons = training_seasons, exclude = permanent_exclusions,
  m0_grid = m0_grid,
  selection_method = "min_nll", racing = FALSE,
  n_cores = parallel::detectCores(), checkpoint_dir = checkpoint_dir,
  verbose = TRUE
)
PAGe::validate_page_kit(result$kit)
saveRDS(result, file.path(artifact_dir, "training_result.rds"))
saveRDS(result$kit, file.path(artifact_dir, "candidate_pre_holdout.rds"))
saveRDS(result$tuning$m0, file.path(artifact_dir, "m0_tuning.rds"))
saveRDS(result$tuning$m1, file.path(artifact_dir, "m1_tuning.rds"))
saveRDS(result$tuning$m2, file.path(artifact_dir, "m2_tuning.rds"))
write.csv(result$grid, file.path(artifact_dir, "m2_grid.csv"), row.names = FALSE)
write.csv(result$tuning$m2$summary,
          file.path(artifact_dir, "m2_summary.csv"), row.names = FALSE)
write.csv(result$tuning$m2$scores,
          file.path(artifact_dir, "m2_fold_scores.csv"), row.names = FALSE)
elapsed_hours <- as.numeric(difftime(Sys.time(), started, units = "hours"))
saveRDS(
  list(
    status = "success",
    completed_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    elapsed_hours = elapsed_hours, holdout_season = holdout_season,
    training_seasons = training_seasons,
    selected_m2_spec_id = result$selection$selected_spec_id,
    selected_m2_spec = result$selection$selected_spec,
    kit_governance_id = result$kit$governance_id,
    stage_artifact_ids = result$kit$stage_artifact_ids
  ),
  file.path(artifact_dir, "run_summary.rds")
)
write_status("success", paste0("elapsed_hours=", round(elapsed_hours, 3)))
