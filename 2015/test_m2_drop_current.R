#!/usr/bin/env Rscript

root <- Sys.getenv(
  "PAGE_RUN_DIR",
  "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812/holdouts-and-docs/2015-16"
)
hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv")
n_cores <- as.integer(Sys.getenv("PAGE_N_CORES", "12"))
artifact_dir <- file.path(root, "artifacts")
checkpoint_dir <- file.path(root, "checkpoints", "m2")

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
grid <- read.csv(
  file.path(artifact_dir, "m2_expanded_grid_round8.csv"),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
checkpoint <- readRDS(file.path(checkpoint_dir, "build_m2_phase2.rds"))
grid$spec_id <- PAGe:::.m2_spec_ids(grid)
summary <- do.call(rbind, lapply(grid$spec_id, function(id) {
  scores <- checkpoint$results[[id]]$scores
  data.frame(
    spec_id = id,
    bernoulli_nll = mean(scores$bernoulli_nll, na.rm = TRUE)
  )
}))
planned <- PAGe::plan_m2_grid(
  list(grid = grid, summary = summary),
  max_specs = 64L
)
drop_rows <- planned[
  !planned$spec_id %in% grid$spec_id & planned$k_sp == 0L,
  ,
  drop = FALSE
]
if (nrow(drop_rows) != 1L) {
  stop("Expected exactly one new k_sp=0 candidate; found ", nrow(drop_rows), ".")
}
grid_test <- rbind(grid, drop_rows)

# The preserved M1 artifact predates the current payload-bound identity
# contract. Keep the canonical artifact untouched, but migrate its identity
# and the two checkpoint envelopes into a temporary test directory so the
# current frozen-stage guard and checkpoint extension path can be exercised.
training_data <- PAGe:::.selected_training_data(allD, selection)
current_m1_id <- PAGe:::.stage_artifact_id(
  m1$stage, m1$selection, m1$config, m1$upstream_ids, m1$data_id,
  PAGe:::.stage_fit_payload(m1)
)
m1_current <- m1
m1_current$artifact_id <- current_m1_id
scratch <- file.path(tempdir(), "page-2015-drop-test-migrated")
dir.create(scratch, recursive = TRUE, showWarnings = FALSE)
m1_phase1 <- readRDS(file.path(checkpoint_dir, "m1_phase1.rds"))
m1_phase1$identity <- PAGe:::.m1_phase1_identity(
  training_data, selection$training_seasons, m0, m1_current
)
saveRDS(m1_phase1, file.path(scratch, "m1_phase1.rds"))
current_m2_identity <- PAGe:::.m2_checkpoint_identity(
  training_data, selection$training_seasons, grid_test, m0, m1_current
)
checkpoint$identity <- list(
  context = current_m2_identity$context,
  grid = grid$spec_id
)
saveRDS(checkpoint, file.path(scratch, "build_m2_phase2.rds"))
message("[drop-test] migrated legacy M1 identity into temporary checkpoint directory")

message(
  "[drop-test] scoring ", drop_rows$spec_id,
  " with ", nrow(grid), " cached specifications and ",
  n_cores, " cores"
)
tuning <- PAGe::tune_m2(
  allD,
  selection = selection,
  m0 = m0,
  m1 = m1_current,
  grid = grid_test,
  n_cores = n_cores,
  checkpoint_dir = scratch,
  verbose = TRUE
)
caps <- PAGe::default_m2_nll_gain_caps()
tuning <- PAGe::validate_m2_tuning(
  tuning,
  check_boundaries = TRUE,
  min_nll_gain = caps
)
saveRDS(tuning, file.path(artifact_dir, "m2_drop_test_tuning.rds"))
write.csv(
  tuning$boundary_report,
  file.path(artifact_dir, "m2_drop_test_boundary_report.csv"),
  row.names = FALSE
)
write.csv(
  tuning$summary[tuning$summary$spec_id %in% drop_rows$spec_id, , drop = FALSE],
  file.path(artifact_dir, "m2_drop_test_summary.csv"),
  row.names = FALSE
)
message(
  "[drop-test] selected=", tuning$best_spec_id,
  " | drop_nll=",
  format(tuning$summary$bernoulli_nll[
    tuning$summary$spec_id == drop_rows$spec_id
  ], digits = 8)
)
