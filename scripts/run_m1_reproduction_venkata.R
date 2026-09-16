#!/usr/bin/env Rscript
# M1-only reproduction of the 2025-26 outer-fold gate run (r4) with the
# alignment-reuse implementation. Re-runs round-1 M1 tuning on the same
# training seasons, frozen M0, timing labels, grid, and protocol, then compares
# every score against the r4 reference table. No holdout data are used.
#
# Required environment:
#   PAGE_M1_RUN_DIR    fresh run directory (created by the launcher)
#   PAGE_M1_INPUT_DIR  directory holding the r4 reference inputs + manifest
#   PAGE_FLU_HIST_FILE authorized historical CSV
#   PAGE_PACKAGE_LIBRARY run-local library with the verified PAGe build
# Optional: PAGE_N_CORES (default 8, matching r4).

suppressPackageStartupMessages(library(dplyr))

env <- function(name, default = NULL) {
  value <- Sys.getenv(name, "")
  if (!nzchar(value)) {
    if (is.null(default)) stop("Missing environment variable: ", name, call. = FALSE)
    return(default)
  }
  value
}

run_dir <- env("PAGE_M1_RUN_DIR")
input_dir <- env("PAGE_M1_INPUT_DIR")
hist_path <- env("PAGE_FLU_HIST_FILE")
lib <- env("PAGE_PACKAGE_LIBRARY")
n_cores <- as.integer(env("PAGE_N_CORES", "8"))
.libPaths(unique(c(lib, .libPaths())))

status_path <- file.path(run_dir, "status.tsv")
write_status <- function(status, detail = "") {
  row <- data.frame(
    timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    status = status, detail = detail
  )
  utils::write.table(row, status_path,
    sep = "\t", row.names = FALSE, quote = FALSE,
    col.names = !file.exists(status_path), append = file.exists(status_path)
  )
}
main_pid <- Sys.getpid()
options(error = function() {
  if (identical(Sys.getpid(), main_pid)) write_status("failed", "unhandled R error; inspect run.log")
  traceback(2)
  q(status = 1L, save = "no")
})

# ---- Input integrity: every reference input must match its recorded hash ----
manifest <- utils::read.table(file.path(input_dir, "inputs.sha256"),
  col.names = c("sha256", "file"), stringsAsFactors = FALSE
)
sha256 <- function(path) digest::digest(file = path, algo = "sha256")
for (i in seq_len(nrow(manifest))) {
  path <- if (identical(manifest$file[i], "flu_testing_data.csv")) hist_path else file.path(input_dir, manifest$file[i])
  if (!identical(sha256(path), manifest$sha256[i])) {
    stop("Input hash mismatch: ", manifest$file[i], call. = FALSE)
  }
}
if (!identical(normalizePath(find.package("PAGe")), normalizePath(file.path(lib, "PAGe")))) {
  stop("PAGe did not load from the run-local library.", call. = FALSE)
}
write_status("started", sprintf("n_cores=%d; inputs verified", n_cores))

# ---- Canonical data contract (identical to 2025/run_2025_ultimate.R) ----
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
    pho_season = as.character(season), season = calendar$season,
    week = calendar$week, start_year = calendar$start_year,
    weekS = calendar$weekS, y = as.numeric(pos_flua),
    N = as.numeric(test_flu),
    weekF = calendar$weekF
  ) |>
  select(season, weekF, y, N, everything()) |>
  PAGe::prepare_surveillance_data()

m0 <- readRDS(file.path(input_dir, "m0_frozen.rds"))
timing_labels <- readRDS(file.path(input_dir, "timing_labels_v2.rds"))
grid <- utils::read.csv(file.path(input_dir, "m1_grid_round1.csv"))
reference <- as.data.frame(readRDS(file.path(input_dir, "tune_m1_results.rds"))$scores)
if ("2025-26" %in% m0$selection$training_seasons) stop("Holdout present in training selection.", call. = FALSE)

write_status("tuning", sprintf("specs=%d; training_seasons=%d", nrow(grid), length(m0$selection$training_seasons)))
t0 <- Sys.time()
result <- PAGe::tune_m1(
  allD,
  m0 = m0,
  m1 = list(m1_params = PAGe:::.default_m1_params()),
  grid = grid,
  n_cores = n_cores,
  checkpoint_dir = file.path(run_dir, "checkpoints", "m1"),
  verbose = TRUE,
  selection = m0$selection,
  manual_labels = PAGe:::as_manual_labels_v2(timing_labels),
  timing_truth = PAGe:::as_timing_targets_v2(timing_labels),
  timing_mode = "fractional"
)
elapsed_min <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
saveRDS(result, file.path(run_dir, "m1_tuning_reproduction.rds"))

# ---- Exact comparison against the r4 reference scores ----
score_cols <- c(
  "mae_uniform", "mae_exp", "mae_weibull",
  "mae_med_uniform", "mae_med_exp", "mae_med_weibull", "n_seasons"
)
new_scores <- as.data.frame(result$scores)
cmp <- merge(reference[c("spec_id", score_cols)], new_scores[c("spec_id", score_cols)],
  by = "spec_id", suffixes = c("_ref", "_new"), all = TRUE
)
cmp$max_abs_diff <- apply(
  abs(as.matrix(cmp[paste0(score_cols, "_ref")]) - as.matrix(cmp[paste0(score_cols, "_new")])),
  1, max
)
utils::write.csv(cmp, file.path(run_dir, "m1_score_comparison.csv"), row.names = FALSE)

identical_scores <- nrow(cmp) == nrow(reference) && all(is.finite(cmp$max_abs_diff)) && all(cmp$max_abs_diff == 0)
summary <- data.frame(
  elapsed_min = round(elapsed_min, 2),
  n_cores = n_cores,
  specs = nrow(new_scores),
  identical_scores = identical_scores,
  max_abs_diff = max(cmp$max_abs_diff, na.rm = TRUE),
  best_spec_ref = reference$spec_id[which.min(reference$mae_weibull)],
  best_spec_new = result$best$spec_id
)
utils::write.csv(summary, file.path(run_dir, "summary.csv"), row.names = FALSE)
print(summary)
write_status(
  "complete",
  sprintf(
    "elapsed_min=%.1f; identical_scores=%s; best=%s",
    elapsed_min, identical_scores, result$best$spec_id
  )
)
