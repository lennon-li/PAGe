#!/usr/bin/env Rscript
# Final post-evaluation fit: all eligible seasons, inner LOSO, no outer replay.
# Full runs are launched by launch_2026_27_final_kit.sh after the r5 gate.
args <- commandArgs(trailingOnly = TRUE)
if (any(!args %in% "--preflight")) stop("Only --preflight is supported.")
preflight_only <- "--preflight" %in% args
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) != 1L) stop("Invoke this runner with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), mustWork = TRUE)
repo_root <- normalizePath(Sys.getenv(
  "PAGE_REPO_ROOT", file.path(dirname(script_file), "..")
), mustWork = TRUE)
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


run_root <- Sys.getenv("PAGE_RUN_ROOT", file.path(repo_root, "results", "final-kit-2026-27"))
run_id <- Sys.getenv("PAGE_RUN_ID", "")
if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", run_id)) {
  stop("PAGE_RUN_ID must be a fresh simple identifier (letters, digits, dot, underscore, hyphen).")
}
run_dir <- file.path(run_root, run_id)
reserved <- c(
  "status.tsv", "artifacts", "checkpoints", "runner.claim", "final_kit.rds",
  "platform_manifest.rds", "run_summary.rds"
)
if (any(file.exists(file.path(run_dir, reserved)))) {
  stop("Refusing to overwrite an existing run: ", run_dir)
}
dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
probe <- tempfile(".write_probe_", tmpdir = run_dir)
if (!file.create(probe, showWarnings = FALSE)) stop("Run directory is not writable: ", run_dir)
unlink(probe)
run_dir <- normalizePath(run_dir, mustWork = TRUE)
status_path <- if (preflight_only) NA_character_ else file.path(run_dir, "status.tsv")
write_status <- function(status, detail = "") {
  if (is.na(status_path)) {
    return(invisible(NULL))
  }
  row <- data.frame(
    timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    status = status, detail = gsub("[\t\r\n]", " ", detail), stringsAsFactors = FALSE
  )
  write.table(row, status_path,
    sep = "\t", row.names = FALSE,
    col.names = !file.exists(status_path), append = file.exists(status_path), quote = FALSE
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
if (!preflight_only) {
  if (!dir.create(file.path(run_dir, "runner.claim"), showWarnings = FALSE)) {
    # A competing runner owns the status file.
    status_path <- NA_character_
    stop("Another runner already claimed this run directory.")
  }
  write_status("started", paste0("run_id=", run_id, " entry=PAGe::train_outer_fold holdout=NULL"))
}

package_library <- Sys.getenv("PAGE_PACKAGE_LIBRARY", "")
if (!nzchar(package_library) || !dir.exists(package_library)) {
  stop("PAGE_PACKAGE_LIBRARY must name the freshly installed scratch/run-local library.")
}
package_library <- normalizePath(package_library, mustWork = TRUE)
.libPaths(unique(c(package_library, .libPaths())))
if (!requireNamespace("PAGe", quietly = TRUE) ||
  !identical(normalizePath(find.package("PAGe")), file.path(package_library, "PAGe"))) {
  stop("PAGe must be loaded from PAGE_PACKAGE_LIBRARY.")
}
suppressPackageStartupMessages(library(dplyr))
# Permanent exclusions plus the incomplete current season: a season without a
# full calendar of observed weeks has no observed peak, so it cannot be scored
# or supply timing truth. Coverage is checked against the MMWR calendar below.
EXCLUDE <- c("2011-12", "2015-16", "2020-21", "2021-22")
EXPECTED_TRAINING <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18", "2018-19",
  "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
)
cores_text <- Sys.getenv("PAGE_N_CORES", "8")
N_CORES <- suppressWarnings(as.integer(cores_text))
if (!grepl("^[1-9][0-9]*$", cores_text) || is.na(N_CORES)) {
  stop("PAGE_N_CORES must be a positive integer.")
}
backend <- Sys.getenv("PAGE_FUTURE_BACKEND", "auto")
if (!backend %in% c("auto", "multicore", "multisession")) stop("Invalid PAGE_FUTURE_BACKEND.")
hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "")
if (!nzchar(hist_path) || !file.exists(hist_path)) stop("Set PAGE_FLU_HIST_FILE to the authorized CSV.")
hist_path <- normalizePath(hist_path, mustWork = TRUE)
sha256 <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
input_sha256 <- sha256(hist_path)

# ---- Decided new-cycle recipe (declared explicitly; never package defaults) ----
# PROTOCOL v2.0, recorded 2026-09-15: M0 grid unchanged; M1 fixed at
# k_ref = 30, slope_weight = 16; M2 stage A is the 192-row intercept x
# k_z {0,3,4,5} x k_u {0,7,8,9} x k_d {0,3,4,5,6,7} grid; stage B (k_tau
# {0,3,4,5} x conf_scale {none, peak_ci}) is built by the package as
# implemented; gate_nesting = "full"; scoring = page_v2.
M0_GRID <- PAGe:::.default_m0_grid()
# PROTOCOL v2.1, 2026-09-18: the M0 eligibility window floor (w_min) is an
# operational constant, not a tuned axis -- it was held fixed at 13 across all
# three rounds of the v2.0 M0 grid. Epidemiological review moved it to the
# week the weekly run actually starts (weekF 8, the minimum history PAGe needs
# to run), leaving w_max = 26 untouched. Declared here rather than by editing
# the package default so the value is recorded in the run's source snapshot.
# Verified before adoption: at the v2.0 SELECTED M0 parameters this changes no
# detection in any of the 12 detected historical seasons (all ignition weeks
# identical), and it does not make 2026-27 ignite -- the binding constraint
# there is the 4-of-5 vote, not the window. It does change detections for
# 38/40 OTHER grid specs, which is why the tuning is re-run rather than the
# stored value patched.
m0_w_min_text <- Sys.getenv("PAGE_M0_W_MIN", "")
if (nzchar(m0_w_min_text)) {
  m0_w_min <- suppressWarnings(as.integer(m0_w_min_text))
  if (is.na(m0_w_min) || !grepl("^[0-9]+$", m0_w_min_text)) {
    stop("PAGE_M0_W_MIN must be a positive integer week.")
  }
  if (!"w_min" %in% names(M0_GRID)) stop("M0 grid has no w_min column to override.")
  if (any(as.integer(M0_GRID$w_max) < m0_w_min)) {
    stop("PAGE_M0_W_MIN must not exceed w_max in any M0 specification.")
  }
  M0_GRID$w_min <- m0_w_min
  message(sprintf("[recipe] M0 w_min overridden to %d (w_max unchanged).", m0_w_min))
}
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

all_seasons <- sort(unique(as.character(allD$season)))
# Drop seasons whose observed weeks do not cover the MMWR calendar (the current
# partial season): no observed peak, so they cannot be scored or supply timing truth.
season_coverage <- allD |>
  dplyr::group_by(.data$season) |>
  dplyr::summarise(
    observed = dplyr::n_distinct(.data$weekF),
    expected = dplyr::first(PAGe::page_season_calendar(
      mmwr_year = as.integer(substr(.data$season[1], 1L, 4L)), week = 27L
    )$nW_true),
    .groups = "drop"
  )
INCOMPLETE <- season_coverage$season[season_coverage$observed < season_coverage$expected]
if (length(INCOMPLETE)) {
  cat(sprintf("excluding incomplete seasons: %s\n", paste(INCOMPLETE, collapse = ", ")))
}
training_seasons <- setdiff(all_seasons, c(EXCLUDE, INCOMPLETE))
season_week_counts <- allD |>
  dplyr::group_by(.data$season) |>
  dplyr::summarise(
    rows = dplyr::n(),
    weeks = dplyr::n_distinct(.data$weekF),
    min_weekF = min(.data$weekF, na.rm = TRUE),
    max_weekF = max(.data$weekF, na.rm = TRUE),
    .groups = "drop"
  )
if (!setequal(training_seasons, EXPECTED_TRAINING)) {
  stop("Season contract mismatch. Got training: ", paste(training_seasons, collapse = ", "))
}
selection <- PAGe::validate_season_selection(
  allD,
  training_seasons = training_seasons,
  exclude_seasons = intersect(c(EXCLUDE, INCOMPLETE), all_seasons),
  holdout_seasons = character(0), application_seasons = character(0)
)
cat("season/week counts:\n")
print(season_week_counts, row.names = FALSE)
manual_labels_default <- PAGe:::.default_manual_labels()
if (!all(training_seasons %in% names(manual_labels_default))) stop("Missing manual ignition labels.")

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
    annotator = "2026-27 final-kit protocol",
    note = "Legacy ignition reference plus reviewed observed peak pair."
  )
})
names(timing_labels_training) <- training_seasons

# Exercise the same timing conversions the training API will consume.
manual_labels <- PAGe::as_manual_labels_v2(timing_labels_training)
timing_targets <- PAGe::as_timing_targets_v2(timing_labels_training)
stopifnot(setequal(names(manual_labels), EXPECTED_TRAINING), all(is.finite(manual_labels)))
if (!identical(input_sha256, sha256(hist_path))) stop("Input changed during preflight.")

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

cat(sprintf(
  "preflight ok: %d eligible seasons; %d fixed exclusions present; holdout=NULL; n_cores=%d\n",
  length(training_seasons), sum(EXCLUDE %in% all_seasons), N_CORES
))
cat("timing-v2 ok: 11/11 ignition + reviewed peak labels; fractional targets validated\n")
cat("run directory writable; PAGe loaded from PAGE_PACKAGE_LIBRARY\n")
if (preflight_only) {
  cat("preflight-only mode: no training or replay started\n")
  q(save = "no", status = 0L)
}

artifact_dir <- file.path(run_dir, "artifacts")
checkpoint_dir <- file.path(run_dir, "checkpoints")
stopifnot(dir.create(artifact_dir), dir.create(checkpoint_dir))
optional_command <- function(command, args = character()) {
  if (!nzchar(Sys.which(command))) {
    return(NA_character_)
  }
  tryCatch(
    {
      out <- suppressWarnings(system2(command, args, stdout = TRUE, stderr = FALSE))
      if (!is.null(attr(out, "status")) && attr(out, "status") != 0L) NA_character_ else out
    },
    error = function(e) NA_character_
  )
}
optional_value <- function(expr) tryCatch(expr, error = function(e) NA_character_)
source_files <- sort(c(
  list.files("PAGe", recursive = TRUE, full.names = TRUE, all.files = TRUE),
  file.path("2026", c("run_2026_27_final_kit.R", "launch_2026_27_final_kit.sh", "watch_2026_27_final_kit.sh")),
  "2025/validate_2025_ultimate.R", "docs/final-kit-2026-27-runbook.md"
))
source_manifest <- data.frame(
  path = source_files, bytes = file.info(source_files)$size,
  sha256 = vapply(source_files, sha256, character(1)), row.names = NULL
)
utils::write.csv(source_manifest, file.path(run_dir, "source_manifest.csv"), row.names = FALSE)
for (source_file in source_files) {
  destination <- file.path(run_dir, "source_snapshot", source_file)
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(source_file, destination, overwrite = FALSE) ||
    !identical(sha256(destination), source_manifest$sha256[match(source_file, source_files)])) {
    stop("Could not preserve unchanged source snapshot: ", source_file)
  }
}
key_packages <- names(PAGe:::.page_dependency_versions())
platform <- list(
  rng_start = run_rng_start,
  captured_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  R_version = R.version.string, sessionInfo = utils::sessionInfo(),
  extSoftVersion = extSoftVersion(), La_version = La_version(),
  La_library = optional_value(La_library()), BLAS_path = utils::sessionInfo()$BLAS,
  OS = Sys.info(),
  OS_release = if (file.exists("/etc/os-release")) readLines("/etc/os-release") else NA_character_,
  CPU_model = if (file.exists("/proc/cpuinfo")) {
    unique(grep(
      "^(model name|Hardware|Processor)[[:space:]]*:", readLines("/proc/cpuinfo"),
      value = TRUE
    ))
  } else {
    NA_character_
  },
  nproc = optional_command("nproc"), n_cores = N_CORES,
  package_versions = setNames(vapply(key_packages, function(pkg) {
    as.character(utils::packageVersion(pkg))
  }, character(1)), key_packages),
  environment = Sys.getenv(c("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "PAGE_FUTURE_BACKEND")),
  repo_root = repo_root, package_library = package_library,
  git_head = optional_command("git", c("rev-parse", "HEAD")),
  git_branch = optional_command("git", c("rev-parse", "--abbrev-ref", "HEAD")),
  git_package_status = optional_command("git", c("status", "--porcelain", "--", "PAGe")),
  input_csv = hist_path, input_sha256 = input_sha256, source_manifest = source_manifest,
  gate_run_dir = Sys.getenv("PAGE_GATE_RUN_DIR"), gate_override = Sys.getenv("PAGE_GATE_OVERRIDE"),
  entry_point = "PAGe::train_outer_fold", holdout = NULL, selection = selection,
  recipe = RECIPE,
  recipe_summary = c(
    m0_rows = nrow(M0_GRID), m1_rows = nrow(M1_GRID),
    m2_stage_a_rows = nrow(M2_STAGE_A_GRID),
    m1_k_ref = unique(M1_GRID$k_ref),
    m1_slope_weight = unique(M1_GRID$slope_weight),
    gate_nesting = GATE_NESTING, scoring = "page_v2"
  ),
  protocol_args = PROTOCOL_ARGS
)
saveRDS(platform, file.path(run_dir, "platform_manifest.rds"))
writeLines(capture.output(print(platform)), file.path(run_dir, "platform_manifest.txt"))
saveRDS(timing_labels_training, file.path(run_dir, "timing_labels_v2.rds"))
write_status("training", "11 eligible seasons; inner LOSO M0 -> M1 -> M2; no outer replay")
t0 <- Sys.time()
result <- PAGe:::.page_training_audit(do.call(PAGe::train_outer_fold, c(list(
  data = allD, holdout = NULL, timing_labels = timing_labels_training,
  artifact_dir = artifact_dir, checkpoint_dir = checkpoint_dir,
  exclude = c(EXCLUDE, INCOMPLETE), verbose = TRUE
), PROTOCOL_ARGS)), directory = run_dir)
elapsed_s <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
stopifnot(
  setequal(result$selection$training_seasons, EXPECTED_TRAINING),
  length(result$selection$holdout_seasons) == 0L,
  result$gate$applied$action %in% c("use_m2", "keep_m1")
)
for (stage in c("m0", "m1", "m2")) {
  if (!isTRUE(tail(result$boundaries[[stage]], 1L)[[1L]]$settled)) {
    stop("Unsettled boundary at completion: ", stage)
  }
}
kit_path <- file.path(run_dir, "final_kit.rds")
# Keep the API's candidate artifact and a clearly named final kit with identical bytes.
if (!file.copy(file.path(artifact_dir, "candidate_pre_holdout.rds"), kit_path, overwrite = FALSE)) {
  stop("Could not preserve final frozen kit.")
}
saved_kit <- readRDS(kit_path)
invisible(PAGe::validate_page_kit(saved_kit, mode = "frozen"))
stopifnot(
  setequal(saved_kit$season_selection$training_seasons, EXPECTED_TRAINING),
  length(saved_kit$season_selection$holdout_seasons) == 0L
)
kit_hash <- sha256(kit_path)
saveRDS(
  list(
    valid = TRUE, mode = "frozen", kit_sha256 = kit_hash,
    governance_id = saved_kit$governance_id, selection = saved_kit$season_selection
  ),
  file.path(run_dir, "kit_validation.rds")
)
writeLines(paste(kit_hash, " final_kit.rds"), file.path(run_dir, "final_kit.sha256"))
saveRDS(list(
  run_id = run_id, holdout = NULL, selection = result$selection,
  completed_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), elapsed_seconds = elapsed_s,
  selected_configs = lapply(result$stages, `[[`, "config"),
  m1_selection = result$tuning$m1$best,
  adoption = result$gate[c("primary", "sensitivity", "sensitivity_scale", "applied")],
  keep_m1_fallback = identical(result$gate$applied$action, "keep_m1"),
  boundaries = result$boundaries, protocol = result$protocol,
  artifact_dir = artifact_dir, checkpoint_dir = checkpoint_dir,
  kit_sha256 = kit_hash, source_manifest = source_manifest
), file.path(run_dir, "run_summary.rds"))
write_status("complete", sprintf("elapsed_s=%.0f kit_sha256=%s", elapsed_s, kit_hash))
cat(sprintf("final kit complete in %.1f min: %s\n", elapsed_s / 60, kit_path))
q(save = "no", status = 0L)
