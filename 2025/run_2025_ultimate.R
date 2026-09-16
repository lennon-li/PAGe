#!/usr/bin/env Rscript

# 2025-26 ultimate outer-fold run through the exported PAGe::run_outer_fold()
# API only. Predeclared protocol per task packet 2026-09-11 (Permission L2).
# The 2025-26 holdout is touched only inside the strict post-freeze replay
# performed by the API. Boundary expansion, the M2 adoption gate, the all-off
# M1 fallback, strict replay, and artifact retention are delegated entirely to
# run_outer_fold()/train_outer_fold(). This wrapper never calls the legacy
# stage-by-stage runner.

script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script_file) || !nzchar(script_file)) {
  script_file <- "2025/run_2025_ultimate.R"
}
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)

# Use a recorded deterministic seed for every new run; callers may override it.
seed_text <- Sys.getenv("PAGE_RUN_SEED", "20260915")
if (nzchar(seed_text)) {
  seed <- suppressWarnings(as.integer(seed_text))
  if (is.na(seed) || !grepl("^[0-9]+$", seed_text)) stop("PAGE_RUN_SEED must be a nonnegative integer.")
  set.seed(seed)
  options(page.run_seed = seed)
}
if (!exists(".Random.seed", .GlobalEnv, inherits = FALSE)) invisible(stats::runif(1L))
run_rng_start <- list(kind = RNGkind(), state = .Random.seed, seed = getOption("page.run_seed"))


args <- commandArgs(trailingOnly = TRUE)
preflight_only <- "--preflight" %in% args

package_library <- Sys.getenv("PAGE_PACKAGE_LIBRARY", "")
if (nzchar(package_library) && dir.exists(package_library)) {
  .libPaths(unique(c(package_library, .libPaths())))
}
if (!requireNamespace("PAGe", quietly = TRUE)) {
  stop("Current PAGe package is unavailable; run the launcher first.")
}
suppressPackageStartupMessages(library(PAGe))
suppressPackageStartupMessages({
  library(dplyr)
  library(MMWRweek)
})

# ---- Predeclared protocol (policy inputs, all explicit) ----
HOLDOUT <- "2025-26"
EXCLUDE <- c("2011-12", "2015-16", "2020-21", "2021-22")
EXPECTED_TRAINING <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18",
  "2018-19", "2019-20", "2022-23", "2023-24", "2024-25"
)
N_CORES <- as.integer(Sys.getenv("PAGE_N_CORES", "8"))
if (!is.finite(N_CORES) || N_CORES < 1L) {
  stop("PAGE_N_CORES must be a positive integer.")
}

# ---- Decided new-cycle recipe (declared explicitly; never package defaults) ----
# PROTOCOL v2.0, recorded 2026-09-15: M0 grid unchanged; M1 fixed at
# k_ref = 30, slope_weight = 16; M2 stage A is the 192-row intercept x
# k_z {0,3,4,5} x k_u {0,7,8,9} x k_d {0,3,4,5,6,7} grid; stage B (k_tau
# {0,3,4,5} x conf_scale {none, peak_ci}) is built by the package as
# implemented; gate_nesting = "full"; scoring = page_v2.
M0_GRID <- PAGe:::.default_m0_grid()
M1_GRID <- data.frame(
  k_ref = 30L, multi_temperature = 0.25, template_shift = 0L,
  align_rise_weight = 1.0, slope_window = 6L, slope_weight = 16.0
)
M1_PARAMS <- list(
  k_ref = 30L, ref_method = "fs", temperature = 0.25, rise_weight = 1.0,
  trough_weight = 0.1, peak_decay = 0.3, slope_weight = 16.0,
  slope_window = 6L, dynamic_temp = FALSE, dynamic_temp_pivot = 10L,
  spread_method = "between"
)
M2_STAGE_A_GRID <- PAGe::m2_subset_grid(
  k_z_values = c(0L, 3L, 4L, 5L),
  k_u_values = c(0L, 7L, 8L, 9L),
  k_d_values = c(0L, 3L, 4L, 5L, 6L, 7L),
  k_tau_values = 0L, conf_scale = "none",
  alpha_state = 0.2, gamma = 1.4
)
GATE_NESTING <- "full"
RECIPE <- list(
  m0_grid = M0_GRID, m1_grid = M1_GRID, m1_params = M1_PARAMS,
  m2_grid = M2_STAGE_A_GRID, gate_nesting = GATE_NESTING
)

PROTOCOL_ARGS <- list(
  timing_mode = "fractional",
  pre_ignition_weight = 0,
  early_weight = 2,
  early_max_t_since = 12,
  late_weight = 1,
  scoring = "page_v2",
  score_scale = "equal_week",
  min_gain = 0.0012,
  min_gain_by_horizon = c("2" = 0.002),
  confidence = 0.95,
  max_season_degradation = 0,
  m1_min_gain = 0.05,
  max_boundary_rounds = c(M0 = 10L, M1 = 4L, M2 = 6L),
  m0_expansion_steps = c(p_thr = 0.001, prev_thr = 0.001, p_sum_thr = 0.01),
  m1_expansion_steps = c(k_ref = 5, slope_weight = 4),
  m2_expansion_increment = 12L,
  m0_grid = M0_GRID,
  m1_grid = M1_GRID,
  m1_params = M1_PARAMS,
  m2_grid = M2_STAGE_A_GRID,
  gate_nesting = GATE_NESTING,
  n_cores = N_CORES
)

run_root <- Sys.getenv(
  "PAGE_RUN_ROOT",
  "/home/yeli/repos/PAGe/results/manuscript/nested-outer-2025-26-ultimate-20260911"
)
run_id <- Sys.getenv("PAGE_RUN_ID", "")
hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "/home/yeli/FLU/flu_testing_data.csv")
if (!file.exists(hist_path)) stop("Authorized historical CSV not found: ", hist_path)

run_dir <- if (nzchar(run_id)) file.path(run_root, run_id) else NA_character_
status_path <- NA_character_ # set only after the refuse-overwrite check passes

write_status <- function(status, detail = "") {
  if (is.na(status_path)) {
    return(invisible(NULL))
  }
  row <- data.frame(
    timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    status = status, detail = detail, stringsAsFactors = FALSE
  )
  write.table(
    row, status_path,
    sep = "\t", row.names = FALSE,
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

# ---- Canonical data contract (same transform as the proven 2025 runner) ----
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(
    as.Date(paste0(as.integer(start_year), "-12-31"))
  )$MMWRweek == 53L)
}

raw <- PAGe::load_flu_hist(hist_path)
calendar <- PAGe::page_season_calendar(
  dates = as.Date(raw$week_start_date), start_week = 27L
)
allD <- raw |>
  mutate(
    pho_season = as.character(season),
    season = calendar$season, week = calendar$week,
    start_year = calendar$start_year, weekS = calendar$weekS,
    y = as.numeric(pos_flua),
    N = as.numeric(test_flu),
    weekF = calendar$weekF
  ) |>
  select(season, weekF, y, N, everything()) |>
  PAGe::prepare_surveillance_data()

# ---- Preflight validation (no model fitting) ----
all_seasons <- sort(unique(as.character(allD$season)))
if (!(HOLDOUT %in% all_seasons)) stop("Holdout season absent from data: ", HOLDOUT)
training_seasons <- setdiff(all_seasons, c(EXCLUDE, HOLDOUT))
if (!setequal(training_seasons, EXPECTED_TRAINING)) {
  stop(
    "Season contract mismatch. Got training: ",
    paste(training_seasons, collapse = ", ")
  )
}
manual_labels_default <- PAGe:::.default_manual_labels()
holdout_rows <- sum(as.character(allD$season) == HOLDOUT)
season_week_counts <- allD |>
  dplyr::group_by(.data$season) |>
  dplyr::summarise(
    rows = dplyr::n(),
    weeks = dplyr::n_distinct(.data$weekF),
    min_weekF = min(.data$weekF, na.rm = TRUE),
    max_weekF = max(.data$weekF, na.rm = TRUE),
    .groups = "drop"
  )
cat(sprintf(
  "preflight ok: %d seasons, %d training, %d excluded, holdout %s (%d rows isolated)\n",
  length(all_seasons), length(training_seasons),
  sum(EXCLUDE %in% all_seasons), HOLDOUT, holdout_rows
))
cat("season/week counts:\n")
print(season_week_counts, row.names = FALSE)

# ---- Recipe preflight: the decided recipe must be exactly in force ----
preflight_recipe <- function(recipe) {
  m1_rows <- nrow(recipe$m1_grid)
  m2_rows <- nrow(recipe$m2_grid)
  m0_rows <- nrow(recipe$m0_grid)
  nesting <- recipe$gate_nesting
  cat(sprintf(
    "recipe: M0 rows = %d; M1 rows = %d; M2 stage-A rows = %d; gate_nesting = %s\n",
    m0_rows, m1_rows, m2_rows, nesting
  ))
  cat(sprintf(
    "recipe: M1 k_ref = %s; M1 slope_weight = %s; M2 k_z = %s; M2 k_u = %s; M2 k_d = %s; M2 k_tau = %s; M2 conf_scale = %s\n",
    paste(unique(recipe$m1_grid$k_ref), collapse = ","),
    paste(unique(recipe$m1_grid$slope_weight), collapse = ","),
    paste(sort(unique(recipe$m2_grid$k_z)), collapse = ","),
    paste(sort(unique(recipe$m2_grid$k_u)), collapse = ","),
    paste(sort(unique(recipe$m2_grid$k_d)), collapse = ","),
    paste(sort(unique(recipe$m2_grid$k_tau)), collapse = ","),
    paste(sort(unique(recipe$m2_grid$conf_scale)), collapse = ",")
  ))
  if (m1_rows != 1L) {
    stop("Recipe preflight failed: M1 grid rows = ", m1_rows, ", expected 1.")
  }
  if (m2_rows != 192L) {
    stop("Recipe preflight failed: M2 stage-A rows = ", m2_rows, ", expected 192.")
  }
  if (!identical(nesting, "full")) {
    stop("Recipe preflight failed: gate_nesting = ", nesting, ", expected full.")
  }
  invisible(TRUE)
}
preflight_recipe(RECIPE)

if (preflight_only) {
  cat("preflight-only mode: data and season selection validated; no fit started\n")
  q(save = "no", status = 0L)
}

# Build the opt-in timing-v2 input for eligible training seasons only. The
# earlier ignition week preserves the legacy scalar training contract; peak
# labels are retained as auditable timing metadata and are not model inputs.
timing_labels_training <- lapply(training_seasons, function(season) {
  review <- PAGe::review_season_timing_v2(allD, season = season)
  n_weeks <- max(52L, max(review$signals$weekF, na.rm = TRUE))
  ignition <- as.integer(manual_labels_default[[season]])
  if (!is.finite(ignition)) {
    stop("No ignition label is available for training season: ", season)
  }
  ignition_pair <- if (ignition < n_weeks) {
    c(ignition, ignition + 1L)
  } else {
    c(ignition - 1L, ignition)
  }
  peak <- as.integer(review$peak_summary$peak_weekF[[1L]])
  if (!is.finite(peak)) {
    stop("No peak label is available for training season: ", season)
  }
  peak_pair <- if (peak < n_weeks) c(peak, peak + 1L) else c(peak - 1L, peak)
  PAGe::finalize_season_timing_v2(
    review,
    ignition = ignition_pair,
    peak = peak_pair,
    n_weeks = n_weeks,
    annotator = "2025-26 outer-fold protocol",
    note = "Legacy ignition reference plus reviewed observed peak pair."
  )
})
names(timing_labels_training) <- training_seasons

# ---- Fresh run directory; refuse overwrite ----
if (!nzchar(run_id)) stop("PAGE_RUN_ID must be set for a full run.")
if (!is.na(status_path) && file.exists(status_path)) {
  stop("Refusing to overwrite an existing run: ", run_dir)
}
artifact_dir <- file.path(run_dir, "artifacts")
checkpoint_dir <- file.path(run_dir, "checkpoints")
if (dir.exists(artifact_dir)) {
  stop("Refusing to overwrite existing artifacts: ", artifact_dir)
}
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(checkpoint_dir, showWarnings = FALSE)
if (file.access(run_dir, mode = 2L) != 0L || file.access(run_dir, mode = 4L) != 0L) {
  stop("Run directory is not writable/readable by the current user: ", run_dir)
}
status_path <- file.path(run_dir, "status.tsv")

# ---- Provenance: source snapshot identity + session info ----
git_head <- trimws(system2("git", c("rev-parse", "HEAD"), stdout = TRUE))
git_branch <- trimws(system2("git", c("rev-parse", "--abbrev-ref", "HEAD"), stdout = TRUE))
pkg_porcelain <- system2("git", c("status", "--porcelain", "--", "PAGe"), stdout = TRUE)
pkg_diff <- paste(system2("git", c("diff", "--", "PAGe"), stdout = TRUE), collapse = "\n")
hash_of <- function(txt) {
  tf <- tempfile()
  writeLines(txt, tf)
  on.exit(unlink(tf))
  unname(tools::md5sum(tf))
}
provenance <- list(
  captured_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  repo_root = repo_root,
  git_head = git_head,
  git_branch = git_branch,
  package_dirty_files = pkg_porcelain,
  package_scoped_diff_md5 = hash_of(pkg_diff),
  package_porcelain_md5 = hash_of(paste(pkg_porcelain, collapse = "\n")),
  package_description = read.dcf(file.path("PAGe", "DESCRIPTION"))[1, c("Package", "Version")],
  entry_point = "PAGe::run_outer_fold (exported API)",
  input_csv = hist_path,
  input_csv_md5 = unname(tools::md5sum(hist_path)),
  holdout = HOLDOUT,
  exclude = EXCLUDE,
  training_seasons = sort(training_seasons),
  n_training_seasons = length(training_seasons),
  timing_label_input = "timing-v2",
  recipe = RECIPE,
  recipe_summary = c(
    m0_rows = nrow(M0_GRID), m1_rows = nrow(M1_GRID),
    m2_stage_a_rows = nrow(M2_STAGE_A_GRID),
    m1_k_ref = unique(M1_GRID$k_ref),
    m1_slope_weight = unique(M1_GRID$slope_weight),
    gate_nesting = GATE_NESTING, scoring = "page_v2"
  ),
  protocol_args = PROTOCOL_ARGS,
  r_version = R.version.string,
  session_pid = page_main_pid
)
provenance$rng_start <- run_rng_start
provenance$package_versions <- PAGe:::.page_dependency_versions()
saveRDS(provenance, file.path(run_dir, "provenance.rds"))

source_files <- c(
  file.path("PAGe", c("DESCRIPTION", "NAMESPACE")),
  list.files(file.path("PAGe", "R"), full.names = TRUE)
)
source_files <- source_files[file.exists(source_files)]
source_manifest <- data.frame(
  path = source_files,
  bytes = as.numeric(file.info(source_files)$size),
  md5 = unname(tools::md5sum(source_files)),
  stringsAsFactors = FALSE
)
utils::write.csv(
  source_manifest,
  file.path(run_dir, "package_source_manifest.csv"),
  row.names = FALSE
)
snapshot_root <- file.path(run_dir, "source_snapshot")
for (source_file in source_files) {
  destination <- file.path(snapshot_root, source_file)
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(source_file, destination, overwrite = FALSE)) {
    stop("Could not preserve package source snapshot: ", source_file)
  }
}
sink(file.path(run_dir, "session_info.txt"))
print(provenance)
print(utils::sessionInfo())
sink()

write_status("started", paste0("run_id=", run_id, " entry=PAGe::run_outer_fold"))
write_status("training", paste0(
  "holdout=", HOLDOUT,
  " training_seasons=", length(training_seasons),
  " n_cores=", N_CORES
))

t0 <- Sys.time()
result <- PAGe:::.page_training_audit(do.call(PAGe::run_outer_fold, c(
  list(
    data = allD,
    holdout = HOLDOUT,
    timing_labels = timing_labels_training,
    artifact_dir = artifact_dir,
    checkpoint_dir = checkpoint_dir,
    exclude = EXCLUDE,
    verbose = TRUE
  ),
  PROTOCOL_ARGS
)), directory = run_dir)
elapsed_s <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

saveRDS(list(
  run_id = run_id,
  holdout = HOLDOUT,
  completed_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  elapsed_seconds = elapsed_s,
  artifact_dir = artifact_dir,
  checkpoint_dir = checkpoint_dir,
  metrics = result$metrics,
  sensitivity = result$sensitivity,
  gate_applied = result$training$gate$applied,
  protocol = result$training$protocol,
  source_manifest = source_manifest
), file.path(run_dir, "run_summary.rds"))

write_status("complete", sprintf(
  "elapsed_s=%.0f artifacts=%s", round(elapsed_s), artifact_dir
))
cat(sprintf("run complete in %.1f min: %s\n", elapsed_s / 60, artifact_dir))
q(save = "no", status = 0L)
