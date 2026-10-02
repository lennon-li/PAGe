#!/usr/bin/env Rscript

# Governed 2014-15 holdout cycle using the current PAGe stage API.
#
# The held-out season is an identifier, not a chronological boundary. Every
# season other than the explicit permanent exclusions and 2014-15 is included
# in the training selection, including 2025-26 when it is present in the
# authorized input. M0 must settle before M1; M1 must settle before M2; the
# holdout is replayed only after the complete kit is frozen and validated.

script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script_file) || !nzchar(script_file)) {
  script_file <- "2014/run_2014_cycle.R"
}
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)

args <- commandArgs(trailingOnly = TRUE)
preflight <- "--preflight" %in% args

suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))
suppressPackageStartupMessages({
  library(dplyr)
  library(MMWRweek)
})

`%||%` <- function(x, y) if (!is.null(x)) x else y

artifact_root <- Sys.getenv(
  "PAGE_ARTIFACT_ROOT",
  "/home/yeli/PAGe-bcc-artifacts/seasonal-archive-20260818/2014-15/runs"
)
run_id <- Sys.getenv("PAGE_RUN_ID", "2014-15-latest-api-20260818")
run_dir <- file.path(artifact_root, run_id)
artifact_dir <- file.path(run_dir, "artifacts")
checkpoint_dir <- file.path(run_dir, "checkpoints")
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)

status_path <- file.path(run_dir, "status.tsv")
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
  # Worker teardown errors must not overwrite a completed terminal status.
  if (identical(Sys.getpid(), page_main_pid)) {
    write_status("failed", "unhandled R error; inspect run.log")
  }
  traceback(2)
  q(status = 1L, save = "no")
})

hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv")
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

holdout <- "2014-15"
holdout_slug <- gsub("[^A-Za-z0-9]+", "_", holdout)
stage_summary_path <- file.path(artifact_dir, "stage_summaries.tsv")
write_stage_summary <- function(stage, status, specs = NA_integer_,
                                report = NULL, selected = NULL,
                                artifacts = character(), detail = "") {
  decisions <- if (!is.null(report) && nrow(report)) {
    paste(unique(as.character(report$decision)), collapse = ",")
  } else ""
  selected_text <- if (is.null(selected)) "" else
    paste(capture.output(dput(selected)), collapse = " ")
  row <- data.frame(
    timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    stage = stage, status = status, specs = specs,
    boundary_decisions = decisions, selected = selected_text,
    artifacts = paste(artifacts, collapse = ","), detail = detail,
    stringsAsFactors = FALSE
  )
  write.table(
    row, stage_summary_path, sep = "\t", row.names = FALSE,
    col.names = !file.exists(stage_summary_path),
    append = file.exists(stage_summary_path), quote = FALSE
  )
  saveRDS(row, file.path(artifact_dir,
                         paste0(tolower(stage), "_artifact_summary.rds")))
}
permanent_exclusions <- c("2011-12", "2015-16", "2020-21", "2021-22")
all_seasons <- sort(unique(as.character(allD$season)))
training_seasons <- setdiff(all_seasons, c(permanent_exclusions, holdout))
selection <- PAGe::validate_season_selection(
  allD,
  training_seasons = training_seasons,
  exclude_seasons = permanent_exclusions,
  holdout_seasons = holdout,
  application_seasons = character(0)
)

manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L, "2025-26" = 19L
)
n_cores <- as.integer(Sys.getenv(
  "PAGE_N_CORES", parallel::detectCores(logical = TRUE)
))
n_cores <- max(1L, n_cores)

if (preflight) {
  cat("2014-15 governed runner preflight OK\n")
  cat("training seasons:", paste(training_seasons, collapse = ", "), "\n")
  cat("holdout:", holdout, "\n")
  cat("cores:", n_cores, "\n")
  quit(save = "no", status = 0L)
}

repo_commit <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE),
                        error = function(e) NA_character_)
repo_status <- tryCatch(system2("git", c("status", "--short"), stdout = TRUE),
                        error = function(e) NA_character_)
saveRDS(selection, file.path(artifact_dir, "season_selection.rds"))
saveRDS(list(
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  protocol = "latest-governed-api; exchangeable-season nested LOSO",
  repo_root = repo_root, repo_commit = repo_commit, repo_status = repo_status,
  input_path = normalizePath(hist_path),
  input_sha256 = digest::digest(file = hist_path, algo = "sha256"),
  data_seasons = all_seasons, training_seasons = training_seasons,
  exclude_seasons = permanent_exclusions, holdout_seasons = holdout,
  manual_labels = manual_labels, n_cores = n_cores
), file.path(artifact_dir, "run_manifest.rds"))
write_status("started", paste0("holdout=", holdout, "; cores=", n_cores))

# ---- M0: tune, inspect/expand, validate, fit, and freeze -----------------
m0_seed <- list(
  best_params = PAGe:::.default_m0_params(),
  grid = PAGe:::.default_m0_grid()
)
m0_grid <- PAGe::expand_tuning_grid(m0_seed, stage = "M0")
m0_checkpoint <- file.path(checkpoint_dir, "m0")
m0_tuning <- NULL
for (attempt in seq_len(8L)) {
  write_status("m0_running", paste0("attempt=", attempt,
                                     "; specs=", nrow(m0_grid)))
  m0_tuning <- PAGe::tune_m0(
    allD, grid = m0_grid, manual_labels = manual_labels,
    n_cores = n_cores, verbose = TRUE, selection = selection,
    checkpoint_dir = m0_checkpoint,
    previous_results = if (attempt == 1L) NULL else m0_tuning$tuning
  )
  m0_report <- PAGe::inspect_tuning_boundaries(m0_tuning, "M0", warn = TRUE)
  saveRDS(m0_tuning, file.path(artifact_dir, "m0_tuning.rds"))
  write.csv(m0_report, file.path(artifact_dir, "m0_boundary_report.csv"),
            row.names = FALSE)
  if (!any(m0_report$decision == "expand_required")) break
  m0_grid <- PAGe::expand_tuning_grid(m0_tuning, stage = "M0")
}
m0_tuning <- PAGe::validate_m0_tuning(
  m0_tuning, grid = m0_grid, check_boundaries = TRUE
)
m0 <- PAGe::freeze_m0(PAGe::fit_m0(
  allD, selection, config = m0_tuning$best_params,
  manual_labels = manual_labels, flag_args = PAGe:::.default_flag_args()
), tuning = m0_tuning)
saveRDS(m0, file.path(artifact_dir, "m0_frozen.rds"))
write_status("m0_settled", paste0("specs=", nrow(m0_grid)))
write_stage_summary(
  "M0", "settled", specs = nrow(m0_grid), report = m0_report,
  selected = m0_tuning$best_params,
  artifacts = c("m0_tuning.rds", "m0_boundary_report.csv", "m0_frozen.rds")
)

# ---- M1: dependent on frozen M0; tune/expand before freezing -------------
m1_grid <- PAGe::default_m1_grid()
m1_hard_caps <- list(k_ref = c(lower = 10L, upper = 52L))
m1_checkpoint <- file.path(checkpoint_dir, "m1")
m1_tuning <- NULL
for (attempt in seq_len(8L)) {
  write_status("m1_running", paste0("attempt=", attempt,
                                     "; specs=", nrow(m1_grid)))
  m1_tuning <- PAGe::tune_m1(
    allD, m0 = m0,
    m1 = list(m1_params = PAGe:::.default_m1_params()),
    grid = m1_grid, n_cores = n_cores, checkpoint_dir = m1_checkpoint,
    verbose = TRUE, selection = selection, manual_labels = manual_labels
  )
  m1_report <- PAGe::inspect_tuning_boundaries(
    m1_tuning, "M1", warn = TRUE, hard_caps = m1_hard_caps
  )
  saveRDS(m1_tuning, file.path(artifact_dir, "m1_tuning.rds"))
  write.csv(m1_report, file.path(artifact_dir, "m1_boundary_report.csv"),
            row.names = FALSE)
  if (!any(m1_report$decision == "expand_required")) break
  m1_grid <- PAGe::expand_tuning_grid(
    m1_tuning, stage = "M1", steps = c(k_ref = 5, slope_weight = 4),
    m1_k_ref_bounds = c(lower = 10L, upper = 52L)
  )
}
m1_tuning$hard_caps <- m1_hard_caps
m1_tuning <- PAGe::validate_m1_tuning(
  m1_tuning, check_boundaries = TRUE, hard_caps = m1_hard_caps
)
m1_selection <- PAGe::select_m1_candidate(
  m1_tuning, min_gain = 0.05, prefer_simpler = TRUE,
  hard_caps = m1_hard_caps
)
m1_tuning$best <- m1_selection$selected
m1_tuning$m1_selection <- m1_selection
m1_tuning <- PAGe::validate_m1_tuning(
  m1_tuning, check_boundaries = TRUE, hard_caps = m1_hard_caps
)
m1_config <- PAGe:::.m1_params_from_tuning(
  PAGe:::.default_m1_params(), m1_tuning
)
m1 <- PAGe::freeze_m1(PAGe::fit_m1(
  allD, selection, m0 = m0, config = m1_config
), tuning = m1_tuning)
saveRDS(m1, file.path(artifact_dir, "m1_frozen.rds"))
write_status("m1_settled", paste0("specs=", nrow(m1_grid)))
write_stage_summary(
  "M1", "settled", specs = nrow(m1_tuning$grid), report = m1_report,
  selected = m1_selection$selected,
  artifacts = c("m1_tuning.rds", "m1_boundary_report.csv", "m1_frozen.rds")
)

# ---- M2: dependent on frozen M0/M1; tune/expand before freezing ----------
m2_grid <- PAGe::plan_m2_grid(NULL, max_finalists = 6L, max_specs = 64L)
m2_checkpoint <- file.path(checkpoint_dir, "m2")
m2_min_nll_gain <- c(
  delta = 0, Kr = 0, k_f = 0.00025, k_e = 0.001,
  alpha_state = 0.001, k_r = 0.0005, k_de = 0.00005,
  k_sp = 0.00025, bias_alpha = 0.00005, bias_beta = 0
)
m2_tuning <- NULL
for (attempt in seq_len(8L)) {
  write_status("m2_running", paste0("attempt=", attempt,
                                     "; specs=", nrow(m2_grid)))
  m2_tuning <- PAGe::tune_m2(
    allD, selection = selection, m0 = m0, m1 = m1,
    grid = m2_grid, n_cores = n_cores, checkpoint_dir = m2_checkpoint,
    verbose = TRUE
  )
  m2_report <- PAGe::inspect_tuning_boundaries(
    m2_tuning, "M2", warn = TRUE, min_nll_gain = m2_min_nll_gain
  )
  saveRDS(m2_tuning, file.path(artifact_dir, "m2_tuning.rds"))
  write.csv(m2_report, file.path(artifact_dir, "m2_boundary_report.csv"),
            row.names = FALSE)
  if (!any(m2_report$decision == "expand_required")) break
  m2_grid <- PAGe::expand_tuning_grid(
    m2_tuning, stage = "M2", max_specs = 96L
  )
  write.csv(
    m2_grid,
    file.path(artifact_dir, paste0("m2_expanded_grid_round", attempt, ".csv")),
    row.names = FALSE
  )
}
m2_tuning$min_nll_gain <- m2_min_nll_gain
m2_tuning <- PAGe::validate_m2_tuning(
  m2_tuning, check_boundaries = TRUE, min_nll_gain = m2_min_nll_gain
)
m2_selection <- PAGe::select_m2_candidate(m2_tuning, method = "min_nll")
if (is.null(m2_selection$selected_spec)) {
  stop("M2 selection returned no specification.")
}
m2 <- PAGe::freeze_m2(PAGe::fit_m2(
  allD, selection, m0 = m0, m1 = m1,
  config = m2_selection$selected_spec, n_cores = n_cores, verbose = TRUE
), tuning = PAGe:::.selected_m2_tuning(m2_tuning, m2_selection))
kit <- PAGe::assemble_kit(
  m0, m1, m2, best_spec_id = m2_selection$selected_spec_id
)
PAGe::validate_page_kit(kit)
saveRDS(m2, file.path(artifact_dir, "m2_frozen.rds"))
saveRDS(kit, file.path(artifact_dir, "candidate_pre_holdout.rds"))
write.csv(m2_tuning$grid, file.path(artifact_dir, "m2_grid.csv"),
          row.names = FALSE)
write.csv(m2_tuning$summary, file.path(artifact_dir, "m2_summary.csv"),
          row.names = FALSE)
write.csv(m2_tuning$scores, file.path(artifact_dir, "m2_fold_scores.csv"),
          row.names = FALSE)
write_status("m2_settled", paste0("specs=", nrow(m2_tuning$grid),
                                   "; selected=", m2_selection$selected_spec_id))
write_stage_summary(
  "M2", "settled", specs = nrow(m2_tuning$grid), report = m2_report,
  selected = m2_selection$selected_spec,
  artifacts = c("m2_tuning.rds", "m2_boundary_report.csv", "m2_frozen.rds",
                "candidate_pre_holdout.rds", "m2_grid.csv", "m2_summary.csv",
                "m2_fold_scores.csv"),
  detail = paste0("selected_spec_id=", m2_selection$selected_spec_id)
)

# ---- Strict holdout replay: only after all three stages are frozen --------
replay <- PAGe::replay_season_holdout(
  kit, allD, season = holdout, kit_compatibility = "strict"
)
if (!identical(as.character(replay$status), "unseen_replay_complete")) {
  stop("Replay did not satisfy unseen-replay contract: ", replay$status)
}
saveRDS(replay, file.path(artifact_dir, paste0("holdout_", holdout_slug, "_replay.rds")))
saveRDS(replay$metrics, file.path(artifact_dir, paste0("holdout_", holdout_slug, "_metrics.rds")))
write.csv(replay$predictions,
          file.path(artifact_dir, paste0("holdout_", holdout_slug, "_predictions.csv")),
          row.names = FALSE)
write.csv(as.data.frame(replay$metrics$overall),
          file.path(artifact_dir, paste0("holdout_", holdout_slug, "_metrics.csv")),
          row.names = FALSE)
write_stage_summary(
  "REPLAY", "unseen_replay_complete", specs = nrow(replay$predictions),
  selected = replay$metrics$overall,
  artifacts = c(
    paste0("holdout_", holdout_slug, "_replay.rds"),
    paste0("holdout_", holdout_slug, "_metrics.rds"),
    paste0("holdout_", holdout_slug, "_metrics.csv"),
    paste0("holdout_", holdout_slug, "_predictions.csv")
  )
)
saveRDS(list(
  status = "success",
  completed_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  holdout_season = holdout, training_seasons = training_seasons,
  selected_m2_spec_id = m2_selection$selected_spec_id,
  selected_m2_spec = m2_selection$selected_spec,
  n_predictions = nrow(replay$predictions), metrics = replay$metrics$overall,
  m0_specs = nrow(m0_grid), m1_specs = nrow(m1_tuning$grid),
  m2_specs = nrow(m2_tuning$grid), kit_governance_id = kit$governance_id,
  stage_artifact_ids = kit$stage_artifact_ids
), file.path(artifact_dir, "run_summary.rds"))
write_status("success", paste0("predictions=", nrow(replay$predictions)))
message("2014-15 governed holdout replay complete: ",
        nrow(replay$predictions), " predictions")
