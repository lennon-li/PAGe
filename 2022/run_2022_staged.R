#!/usr/bin/env Rscript

# Staged 2022-23 cycle: reuse settled M0, gate expanded M1, then tune M2.
suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))
suppressPackageStartupMessages({ library(dplyr); library(MMWRweek) })

run_dir <- normalizePath(Sys.getenv(
  "PAGE_CYCLE_DIR",
  "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812/2022-final-expanded-v2"
), mustWork = FALSE)
artifact_dir <- file.path(run_dir, "artifacts")
checkpoint_dir <- file.path(run_dir, "checkpoints")
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
status_path <- file.path(run_dir, "status.tsv")
write_status <- function(status, detail = "") {
  row <- data.frame(timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
                    status = status, detail = detail)
  write.table(row, status_path, sep = "\t", row.names = FALSE,
              col.names = !file.exists(status_path), append = file.exists(status_path),
              quote = FALSE)
}
options(error = function() {
  write_status("failed", "unhandled R error; inspect run.log")
  traceback(2)
  q(status = 1L, save = "no")
})

hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv")
old_m2_path <- Sys.getenv(
  "PAGE_OLD_M2_TUNING",
  "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812/holdouts-and-docs/2024/exchangeable/artifacts/m2_tuning.rds"
)
m0_dir <- file.path(run_dir, "m0_settlement")
m0_tuning_path <- file.path(m0_dir, "m0_tuning.rds")
m0_grid_path <- file.path(m0_dir, "m0_grid.csv")
m2_grid_path <- file.path(run_dir, "m2_planned_grid.csv")
for (p in c(hist_path, old_m2_path, m0_tuning_path, m0_grid_path, m2_grid_path)) {
  if (!file.exists(p)) stop("Required artifact missing: ", p)
}

n_weeks <- function(y) 52L + as.integer(MMWRweek::MMWRweek(
  as.Date(paste0(as.integer(y), "-12-31"))
)$MMWRweek == 53L)
raw <- PAGe::load_flu_hist(hist_path)
allD <- raw |>
  mutate(season = as.character(season), week = as.integer(week),
         start_year = as.integer(seasonstart), y = as.numeric(pos_flua),
         N = as.numeric(test_flu),
         weekF = ((week - 27L) %% n_weeks(start_year)) + 1L) |>
  select(season, weekF, y, N, everything()) |>
  PAGe::prepare_surveillance_data()

permanent_exclusions <- c("2011-12", "2015-16", "2020-21", "2021-22")
holdout_season <- Sys.getenv("PAGE_HOLDOUT_SEASON", "2022-23")
all_seasons <- sort(unique(allD$season))
training_seasons <- setdiff(all_seasons, c(permanent_exclusions, holdout_season))
selection <- PAGe::validate_season_selection(
  allD, training_seasons = training_seasons,
  exclude_seasons = permanent_exclusions, holdout_seasons = holdout_season,
  application_seasons = character(0)
)
manual_labels <- c(
  "2012-13"=18L, "2013-14"=20L, "2014-15"=20L, "2015-16"=24L,
  "2016-17"=19L, "2017-18"=20L, "2018-19"=19L, "2019-20"=22L,
  "2022-23"=15L, "2023-24"=20L, "2024-25"=23L, "2025-26"=19L
)

write_status("started", "reusing settled M0; M1 expansion before M2")
m0_grid <- read.csv(m0_grid_path, stringsAsFactors = FALSE)
m0_tuning <- readRDS(m0_tuning_path)
m0_tuning$grid <- m0_grid
PAGe::validate_m0_tuning(m0_tuning, grid = m0_grid, check_boundaries = TRUE)
m0 <- PAGe::freeze_m0(
  PAGe::fit_m0(allD, selection, config = m0_tuning$best_params,
               manual_labels = manual_labels),
  tuning = m0_tuning
)
saveRDS(m0_tuning, file.path(artifact_dir, "m0_tuning.rds"))
write.csv(m0_grid, file.path(artifact_dir, "m0_grid.csv"), row.names = FALSE)

m1_grid <- data.table::CJ(
  k_ref = c(15L, 20L, 25L, 30L, 40L, 50L),
  multi_temperature = 0.25, template_shift = 0L,
  align_rise_weight = 1.0, slope_window = 6L,
  slope_weight = c(4.0, 8.0, 12.0, 16.0, 20.0, 30.0),
  sorted = FALSE
)
write_status("running", paste0("M1 expanded; specs=", nrow(m1_grid),
                               "; cores=", parallel::detectCores()))
m1_tuning <- PAGe::tune_m1(
  allD, m0 = m0,
  m1 = list(m1_params = PAGe:::.default_m1_params()),
  grid = m1_grid, n_cores = parallel::detectCores(),
  checkpoint_dir = file.path(checkpoint_dir, "m1"), verbose = TRUE,
  selection = selection, manual_labels = manual_labels
)
PAGe::validate_m1_tuning(m1_tuning, check_boundaries = TRUE)
tuned_m1_params <- PAGe:::.m1_params_from_tuning(
  PAGe:::.default_m1_params(), m1_tuning
)
m1 <- PAGe::freeze_m1(
  PAGe::fit_m1(allD, selection, m0 = m0, config = tuned_m1_params),
  tuning = m1_tuning
)
saveRDS(m1_tuning, file.path(artifact_dir, "m1_tuning.rds"))

m2_grid <- read.csv(m2_grid_path, stringsAsFactors = FALSE)
write.csv(m2_grid, file.path(artifact_dir, "m2_planned_grid.csv"), row.names = FALSE)
write_status("running", paste0("M2; specs=", nrow(m2_grid),
                               "; cores=", parallel::detectCores()))
m2_tuning <- PAGe::tune_m2(
  allD, selection = selection, m0 = m0, m1 = m1, grid = m2_grid,
  n_cores = parallel::detectCores(),
  checkpoint_dir = file.path(checkpoint_dir, "m2"), verbose = TRUE
)
PAGe::validate_m2_tuning(m2_tuning)
m2_selection <- PAGe::select_m2_candidate(m2_tuning, method = "min_nll")
if (is.null(m2_selection$selected_spec)) stop("M2 selection returned no specification.")
m2_model <- PAGe::freeze_m2(
  PAGe::fit_m2(allD, selection, m0 = m0, m1 = m1,
               config = m2_selection$selected_spec,
               n_cores = parallel::detectCores(), verbose = TRUE),
  tuning = PAGe:::.selected_m2_tuning(m2_tuning, m2_selection)
)
kit <- PAGe::assemble_kit(m0, m1, m2_model,
                          best_spec_id = m2_selection$selected_spec_id)
PAGe::validate_page_kit(kit)

result <- structure(list(
  mode = "retune_staged",
  components = list(m0 = PAGe:::.unwrap_stage_payload(m0),
                    m1 = PAGe:::.unwrap_stage_payload(m1),
                    m2 = PAGe:::.unwrap_stage_payload(m2_model)),
  tuning = list(m0 = m0_tuning, m1 = m1_tuning, m2 = m2_tuning),
  grid = m2_tuning$grid,
  grid_provenance = m2_tuning$grid$provenance %||% NULL,
  selection = m2_selection, racing = NULL,
  holdout = list(present = TRUE, released = FALSE,
                 prospective_holdout = holdout_season),
  kit = kit
), class = c("page_training_result", "list"))
saveRDS(result, file.path(artifact_dir, "training_result.rds"))
saveRDS(kit, file.path(artifact_dir, "candidate_pre_holdout.rds"))
saveRDS(m2_tuning, file.path(artifact_dir, "m2_tuning.rds"))
write.csv(m2_tuning$grid, file.path(artifact_dir, "m2_grid.csv"), row.names = FALSE)
write.csv(m2_tuning$summary, file.path(artifact_dir, "m2_summary.csv"), row.names = FALSE)
write.csv(m2_tuning$scores, file.path(artifact_dir, "m2_fold_scores.csv"), row.names = FALSE)
saveRDS(selection, file.path(artifact_dir, "season_selection.rds"))

boundary_m0 <- PAGe:::.stage_boundary_report(
  "M0", m0_grid, m0_tuning$best_params,
  null_axes = c("p_thr", "prev_thr", "p_sum_thr")
)
boundary_m1 <- PAGe:::.stage_boundary_report("M1", m1_tuning$grid, m1_tuning$best)
boundary_m2 <- PAGe:::.stage_boundary_report(
  "M2", m2_tuning$grid, m2_selection$selected_spec,
  null_axes = c("delta", "k_e", "k_r", "k_de", "k_sp", "bias_alpha", "bias_beta", "Kr")
)
boundary_report <- rbind(boundary_m0, boundary_m1, boundary_m2)
write.csv(boundary_report, file.path(artifact_dir, "boundary_report.csv"), row.names = FALSE)
saveRDS(boundary_report, file.path(artifact_dir, "boundary_report.rds"))
unresolved <- subset(boundary_report, stage %in% c("M0", "M1") &
                                   decision == "expand_required")
if (nrow(unresolved)) {
  stop("Unresolved M0/M1 boundary: ",
       paste(unresolved$parameter, collapse = ", "))
}

saveRDS(list(
  status = "success",
  completed_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  holdout_season = holdout_season, training_seasons = training_seasons,
  selected_m2_spec_id = m2_selection$selected_spec_id,
  selected_m2_spec = m2_selection$selected_spec,
  kit_governance_id = kit$governance_id,
  stage_artifact_ids = kit$stage_artifact_ids,
  boundary_report = boundary_report
), file.path(artifact_dir, "run_summary.rds"))
write_status("success", "M0 reused; M1 expanded gate passed; M2 frozen")
