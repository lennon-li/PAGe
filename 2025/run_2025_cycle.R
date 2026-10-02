#!/usr/bin/env Rscript

# Governed outer-fold end-to-end runner (phase 2, predeclared minimum-gain
# gate) for the 11-season nested walk-forward validation campaign. Originally
# written for 2025-26 only; now general -- set PAGE_HOLDOUT_SEASON to pick
# which of the 11 eligible seasons is this run's unseen outer holdout.
#
# Fixed contract:
#   Outer holdout: PAGE_HOLDOUT_SEASON, default "2025-26" (never used for
#   tuning, fitting, gate calibration, or model choice). Training/inner-LOSO:
#   the other 10 of the 11 eligible seasons (2012-13, 2013-14, 2014-15,
#   2016-17, 2017-18, 2018-19, 2019-20, 2022-23, 2023-24, 2024-25, 2025-26,
#   minus whichever is the current holdout).
#   Fixed exclusions (always out, regardless of holdout): 2011-12, 2015-16,
#   2020-21, 2021-22.
#   M2 is the governed offset_subset_v1 family: the saved M1 logit is the
#   mandatory offset with coefficient one; the all-off candidate reproduces M1
#   bit-for-bit.  No fallback to the historical v16 family.
#   The current holdout's manual ignition label is absent from every
#   training/tuning call and is joined only after replay predictions are
#   frozen.
#
# Per-stage resume: M0/M1/M2 each save a frozen/settled checkpoint to
# artifact_dir once they complete; re-invoking with the SAME PAGE_RUN_ID
# after a crash skips straight past already-completed stages. A fresh
# PAGE_RUN_ID (new run_dir) always recomputes from scratch.

script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script_file) || !nzchar(script_file)) script_file <- "2025/run_2025_cycle.R"
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)

args <- commandArgs(trailingOnly = TRUE)
preflight_only <- "--preflight" %in% args

suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))
suppressPackageStartupMessages({
  library(dplyr)
  library(MMWRweek)
})

`%||%` <- function(x, y) if (!is.null(x)) x else y

env_num <- function(name, default) {
  value <- Sys.getenv(name, NA_character_)
  if (is.na(value) || !nzchar(value)) {
    return(default)
  }
  as.numeric(value)
}

# ---- Predeclared runner parameters (policy inputs, not tuned values) ----
EARLY_WEIGHT <- env_num("PAGE_EARLY_WEIGHT", 2)
EARLY_MAX_T_SINCE <- env_num("PAGE_EARLY_MAX_T_SINCE", 12)
MIN_GAIN_COMBINED <- env_num("PAGE_MIN_GAIN", 0.0012)
MIN_GAIN_H2 <- env_num("PAGE_MIN_GAIN_H2", 0.0020)
GATE_CONFIDENCE <- env_num("PAGE_CONFIDENCE", 0.95)
MAX_SEASON_DEGRADATION <- env_num("PAGE_MAX_SEASON_DEGRADATION", 0)

artifact_root <- Sys.getenv(
  "PAGE_ARTIFACT_ROOT",
  "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812"
)
run_id <- Sys.getenv("PAGE_RUN_ID", "2025-26-e2e-phase2-min-gain-20260911")
run_dir <- file.path(artifact_root, run_id)
artifact_dir <- file.path(run_dir, "artifacts")
checkpoint_dir <- file.path(run_dir, "checkpoints")

if (file.exists(file.path(artifact_dir, "run_summary.rds"))) {
  stop("Refusing to overwrite a completed run: ", run_dir)
}
dir.create(artifact_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(checkpoint_dir, showWarnings = FALSE)

status_path <- file.path(run_dir, "status.tsv")
write_status <- function(status, detail = "") {
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

hist_path <- Sys.getenv("PAGE_FLU_HIST_FILE", "")
# No default. This used to fall back to /home/yeli/FLU/flu_testing_data.csv,
# which is a TRUNCATED extract (2025-26 stops at weekF 28 of 53). The
# 2026-09-17 outer-fold campaign trained every fold on it without anyone
# noticing, because a silent default cannot be reviewed. The authorized feed
# must now be named explicitly, as the production runner already requires.
if (!nzchar(hist_path)) {
  stop("Set PAGE_FLU_HIST_FILE to the authorized historical CSV.", call. = FALSE)
}
if (!file.exists(hist_path)) stop("Authorized historical CSV not found: ", hist_path)

n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(
    as.Date(paste0(as.integer(start_year), "-12-31"))
  )$MMWRweek == 53L)
}

# ---- Data entry contract: canonical schema -> prepare_surveillance_data() ----
# The authorized source already uses PAGe canonical column names, so no
# prepare_page_data() remapping is required; this is recorded in the manifest.
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

# PAGE_HOLDOUT_SEASON selects which of the 11 outer-fold seasons is the
# unseen holdout for this run; the other 10 (plus the 4 permanent
# exclusions, always out) become the training/inner-LOSO universe. This
# script was originally written for 2025-26 only; it's now the general
# per-season outer-fold runner for the whole nested walk-forward campaign.
holdout <- Sys.getenv("PAGE_HOLDOUT_SEASON", "2025-26")
permanent_exclusions <- c("2011-12", "2015-16", "2020-21", "2021-22")
eligible_seasons <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18",
  "2018-19", "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
)
if (!holdout %in% eligible_seasons) {
  stop("PAGE_HOLDOUT_SEASON must be one of: ", paste(eligible_seasons, collapse = ", "))
}
packet_training <- setdiff(eligible_seasons, holdout)
all_seasons <- unique(as.character(allD$season))
# Any season present in the data but not on the eligible list is excluded by
# construction, not just the four permanent exclusions. Without this the
# runner inherited whatever extra seasons the CSV happened to carry: a feed
# covering the in-progress 2026-27 (9 observed weeks) pushed it straight into
# training_seasons and tripped the season contract check. Deriving the
# exclusion set from the eligible list keeps the contract stable as the feed
# grows, and records the real exclusions in the training plan.
non_eligible <- setdiff(all_seasons, eligible_seasons)
exclude_seasons <- union(permanent_exclusions, non_eligible)
training_seasons <- setdiff(all_seasons, c(exclude_seasons, holdout))
if (!setequal(training_seasons, packet_training)) {
  stop(
    "Season contract mismatch. Expected: ",
    paste(packet_training, collapse = ", "),
    " | Got: ", paste(training_seasons, collapse = ", ")
  )
}
# ---- Season completeness contract (added 2026-09-18) ----
# eligible_seasons is a hardcoded list, so an eligible season that is only
# PARTIALLY observed used to pass straight through into training: the
# 2026-09-17 campaign trained all ten folds on a 2025-26 truncated at weekF
# 28 of 52, because the supplied CSV stopped there. A half season still has
# an ignition but no observed decline, so it silently corrupts the M1
# reference curve, the timing truth and the M2 training rows. The production
# runner (2026/run_2026_27_final_kit.R) already drops short seasons on
# observed-vs-expected coverage; this runner never got that guard. Hard stop
# rather than a warning or a silent drop: an outer-fold campaign must not
# quietly change which seasons it trained on.
season_coverage <- allD |>
  dplyr::filter(.data$season %in% eligible_seasons) |>
  dplyr::group_by(.data$season) |>
  dplyr::summarise(
    observed = dplyr::n_distinct(.data$weekF),
    expected = n_weeks_in_start_year(dplyr::first(.data$start_year)),
    .groups = "drop"
  ) |>
  dplyr::mutate(short_by = .data$expected - .data$observed)
incomplete <- season_coverage[season_coverage$short_by > 0L, , drop = FALSE]
if (nrow(incomplete)) {
  stop(
    "Incomplete eligible season(s) in ", hist_path, ": ",
    paste(sprintf(
      "%s (%d of %d weeks)", incomplete$season, incomplete$observed,
      incomplete$expected
    ), collapse = "; "),
    ". Supply a CSV covering every eligible season in full, or remove the ",
    "season from eligible_seasons deliberately.",
    call. = FALSE
  )
}
message(sprintf(
  "[seasons] %d eligible seasons, all complete (%d-%d weeks observed).",
  nrow(season_coverage), min(season_coverage$observed),
  max(season_coverage$observed)
))

selection <- PAGe::validate_season_selection(
  allD,
  training_seasons = training_seasons,
  exclude_seasons = exclude_seasons, holdout_seasons = holdout,
  application_seasons = character(0)
)
stopifnot(!holdout %in% selection$training_seasons)

# Training-only manual ignition labels (canonical weekF space, startWeek=27).
# Whichever season is currently the holdout has its own label deliberately
# stripped from the training set here; it's still available (via
# full_manual_labels, pre-strip) for retrospective-only scoring after that
# season's replay predictions are frozen.
full_manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L, "2025-26" = 19L
)
manual_labels_train <- full_manual_labels[
  names(full_manual_labels) %in% all_seasons & names(full_manual_labels) != holdout
]
stopifnot(!holdout %in% names(manual_labels_train))

n_cores <- as.integer(Sys.getenv(
  "PAGE_N_CORES",
  min(parallel::detectCores(logical = TRUE) - 2L, 16L)
))
n_cores <- max(1L, n_cores)

m0_grid0 <- PAGe:::.default_m0_grid()
# The M0 eligibility window floor is an operational constant, not a tuned
# axis: it stayed fixed at 13 across every round of the v2.0 grid while only
# the thresholds varied. Epidemiological review moved it to weekF 8, the week
# the weekly run actually starts and the minimum history PAGe needs, with
# w_max left at 26. Declared per run so the value lands in the run's own log
# and manifest; the package default is untouched. Mirrors the hook in
# 2026/run_2026_27_final_kit.R so the outer campaign and the production kit
# can be run on the same declared cycle.
m0_w_min_text <- Sys.getenv("PAGE_M0_W_MIN", "")
if (nzchar(m0_w_min_text)) {
  m0_w_min <- suppressWarnings(as.integer(m0_w_min_text))
  if (is.na(m0_w_min) || !grepl("^[0-9]+$", m0_w_min_text)) {
    stop("PAGE_M0_W_MIN must be a positive integer week.", call. = FALSE)
  }
  if (!"w_min" %in% names(m0_grid0)) {
    stop("M0 grid has no w_min column to override.", call. = FALSE)
  }
  if (any(as.integer(m0_grid0$w_max) < m0_w_min)) {
    stop("PAGE_M0_W_MIN must not exceed w_max in any M0 specification.", call. = FALSE)
  }
  m0_grid0$w_min <- m0_w_min
  message(sprintf("[recipe] M0 w_min overridden to %d (w_max unchanged).", m0_w_min))
}
m1_grid0 <- PAGe::default_m1_grid()
m2_grid0 <- PAGe::m2_subset_grid()
m1_hard_caps <- PAGe::default_m1_hard_caps()
m2_gain_caps <- PAGe::default_m2_nll_gain_caps()

plan <- PAGe::plan_training(
  allD,
  mode = "retune", prospective_holdout = holdout,
  # Must be the DERIVED exclusion set, not just the four permanent ones.
  # plan_training() builds the actual training universe as data minus
  # exclude minus holdout, independently of the `selection` object above, so
  # passing permanent_exclusions here let any season the CSV happened to
  # carry enter training silently -- the in-progress 2026-27 did exactly
  # that once the feed was switched to the full ORVT file.
  exclude = exclude_seasons, n_cores = n_cores,
  checkpoint_dir = checkpoint_dir,
  m0_grid = m0_grid0, m1_grid = m1_grid0, m2_grid = m2_grid0,
  m1_hard_caps = m1_hard_caps
)
support <- PAGe::preflight_support_audit(
  allD,
  m0_grid = m0_grid0, m1_grid = m1_grid0, selection = selection
)
saveRDS(plan, file.path(artifact_dir, "training_plan.rds"))
saveRDS(support, file.path(artifact_dir, "preflight_support_audit.rds"))
writeLines(capture.output(print(plan)), file.path(artifact_dir, "training_plan.txt"))
writeLines(capture.output(str(support, max.level = 2)), file.path(artifact_dir, "preflight_support_audit.txt"))

has_fail <- function(node) {
  if (is.list(node)) {
    st <- node$status
    if (!is.null(st) && any(as.character(st) == "fail")) {
      return(TRUE)
    }
    if (!length(node)) {
      return(FALSE)
    }
    return(any(vapply(node, has_fail, logical(1))))
  }
  if (!is.null(names(node)) && "status" %in% names(node)) {
    return(any(as.character(node[["status"]]) == "fail"))
  }
  FALSE
}
if (isTRUE(has_fail(support$m0))) {
  stop("M0 preflight support audit failed; see preflight_support_audit.txt")
}

if (preflight_only) {
  cat(holdout, "outer-fold pilot preflight OK\n")
  cat("holdout:", holdout, "(isolated:", !holdout %in% selection$training_seasons, ")\n")
  cat("training seasons:", paste(selection$training_seasons, collapse = ", "), "\n")
  cat("exclusions:", paste(permanent_exclusions, collapse = ", "), "\n")
  cat("labels contain holdout:", holdout %in% names(manual_labels_train), "\n")
  cat("m2 family: offset_subset_v1; specs:", nrow(m2_grid0), "\n")
  cat("early_weight:", EARLY_WEIGHT, "early_max_t_since:", EARLY_MAX_T_SINCE, "\n")
  cat("gates: min_gain=", MIN_GAIN_COMBINED, " min_gain_h2=", MIN_GAIN_H2,
    " confidence=", GATE_CONFIDENCE, " max_season_degradation=",
    MAX_SEASON_DEGRADATION, "\n",
    sep = ""
  )
  cat("cores:", n_cores, "\n")
  cat("run_dir:", run_dir, "\n")
  cat("--- M0/M1 support audit (compact) ---\n")
  cat(paste(head(utils::capture.output(str(support, max.level = 2)), 60L), collapse = "\n"), "\n")
  quit(save = "no", status = 0L)
}

# ---- Protocol and manifest are recorded before any fitting ----
r_files <- list.files("PAGe/R", pattern = "[.]R$", full.names = TRUE)
source_hashes <- stats::setNames(
  vapply(r_files, digest::digest, character(1), file = TRUE, algo = "sha256"),
  basename(r_files)
)
manifest <- list(
  run_id = run_id,
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  protocol = paste0(
    holdout, " outer-fold e2e phase2 min-gain run; governed stage API; ",
    "M2 family offset_subset_v1; equal-week/equal-season primary scoring; ",
    "predeclared adoption gate on inner LOSO evidence only"
  ),
  repo_root = repo_root,
  git_head = tryCatch(
    trimws(system("git rev-parse HEAD 2>/dev/null", intern = TRUE)),
    error = function(e) NA_character_
  ),
  package_source_sha256 = source_hashes,
  input_path = normalizePath(hist_path),
  input_sha256 = digest::digest(file = hist_path, algo = "sha256"),
  data_entry = "load_flu_hist() -> canonical mutate -> prepare_surveillance_data(); prepare_page_data() remapping not required (canonical schema)",
  data_seasons = all_seasons,
  training_seasons = selection$training_seasons,
  exclude_seasons = exclude_seasons,
  holdout_seasons = holdout,
  manual_labels_train = manual_labels_train,
  holdout_label_isolated = TRUE,
  m2_family = "offset_subset_v1",
  m0_grid = m0_grid0, m1_grid = m1_grid0, m2_grid = m2_grid0,
  m1_hard_caps = m1_hard_caps,
  m2_min_nll_gain_caps = m2_gain_caps,
  weighting = list(
    pre_ignition_weight = 0,
    early_weight = EARLY_WEIGHT,
    early_max_t_since = EARLY_MAX_T_SINCE,
    late_weight = 1,
    primary_scale = "equal_week within season, equal season across seasons",
    primary_not_test_count_weighted = TRUE,
    test_count_weighting = "labelled sensitivity artifact only",
    primary_horizon = 2, secondary_horizon = 1
  ),
  adoption_gate = list(
    evidence = "inner training-season LOSO walk-forward matched rows only",
    min_gain = MIN_GAIN_COMBINED,
    min_gain_by_horizon = c("2" = MIN_GAIN_H2),
    confidence = GATE_CONFIDENCE,
    max_season_degradation = MAX_SEASON_DEGRADATION,
    fallback = "exact all-off M2 configuration (bit-for-bit M1)"
  ),
  n_cores = n_cores,
  artifact_dir = artifact_dir, checkpoint_dir = checkpoint_dir,
  r_version = R.version.string
)
saveRDS(manifest, file.path(artifact_dir, "run_manifest.rds"))
protocol_lines <- c(
  "# 2025-26 e2e phase2 min-gain pilot protocol (frozen before fitting)",
  "",
  paste0("- Created (UTC): ", manifest$created_utc),
  paste0("- Run ID: ", run_id),
  paste0("- Git HEAD: ", manifest$git_head),
  paste0("- Input: ", manifest$input_path, " sha256=", manifest$input_sha256),
  "- Outer holdout: 2025-26 (unseen for tuning/gate calibration/model choice).",
  paste0("- Training/inner-LOSO: ", paste(selection$training_seasons, collapse = ", ")),
  paste0("- Fixed exclusions: ", paste(permanent_exclusions, collapse = ", ")),
  "- 2025-26 manual ignition label absent from all training/tuning calls;",
  "  joined only after replay predictions are frozen (retrospective scoring).",
  "- Order: M0 tune->validate->fit->freeze; M1 (exact frozen M0 identity);",
  "  M2 offset_subset_v1 (exact frozen M0/M1 identities); assemble_kit;",
  "  validate_page_kit; strict replay of 2025-26.",
  "- Boundaries: boundary_action_plan()/inspect_tuning_boundaries() after each",
  "  round; expand_tuning_grid() additive with preserved IDs/checkpoints;",
  "  0/off is an intentional null; default_m2_nll_gain_caps() for M2 practical",
  "  stopping with complete matched-adjacent evidence; documented M1 hard caps",
  "  and selection rule; unresolved boundary stops before the next stage.",
  "- M2 family: saved M1 logit is the mandatory offset with coefficient 1;",
  "  the all-off candidate reproduces M1 bit-for-bit; optional horizon",
  "  intercept and z/u/d terms tunable with k=0 meaning off.",
  "- Weighting: pre-ignition 0; target t_since 0..12 early_weight=2; later 1;",
  "  primary equal-week within season and equal-season across seasons; no",
  "  test-count weighting of the primary metric (sensitivity artifact only).",
  "- Adoption gate (inner evidence only, predeclared): combined min_gain=0.0012,",
  "  h2 min_gain=0.0020, confidence=0.95, max_season_degradation=0.",
  "  Failure selects the exact all-off M1 configuration before opening 2025-26.",
  "- Holdout replay: strict compatibility; compare_m1_m2()/decide_m2_vs_m1()",
  "  are retrospective reporting and cannot change the selected model.",
  "- This fold is valid reconstruction/package evidence, not untouched",
  "  confirmation (historical 2025-26 results were previously examined).",
  "- Supervision: detached zero-token OS watchdog (2025/watch_2025.sh)."
)
writeLines(protocol_lines, file.path(run_dir, "PROTOCOL.md"))

stage_times <- list()
mark <- function(name, expr) {
  t0 <- proc.time()[["elapsed"]]
  out <- expr
  stage_times[[name]] <<- proc.time()[["elapsed"]] - t0
  out
}

write_status("started", paste0(
  "holdout=", holdout, "; cores=", n_cores,
  "; early_weight=", EARLY_WEIGHT,
  "; min_gain=", MIN_GAIN_COMBINED, "; min_gain_h2=", MIN_GAIN_H2
))

# ---- M0: settle before any dependent stage ----
m0_frozen_path <- file.path(artifact_dir, "m0_frozen.rds")
if (file.exists(m0_frozen_path)) {
  # Resuming this same PAGE_RUN_ID after a crash in a later stage: M0 already
  # settled and froze cleanly last attempt, so reload it instead of redoing
  # the LOSO grid search. A fresh run_id (new run_dir) always recomputes.
  m0 <- readRDS(m0_frozen_path)
  # m0_grid is only used for the final informational spec count in
  # run_summary.rds; recover it from the saved tuning artifact rather than
  # leaving it unset (m0_grid not existing crashed the summary write on a
  # resumed run).
  m0_grid <- tryCatch(
    readRDS(file.path(artifact_dir, "m0_tuning.rds"))$grid,
    error = function(e) data.frame()
  )
  write_status("m0_resumed", "loaded m0_frozen.rds from a prior attempt in this run_dir")
} else {
  m0_checkpoint <- file.path(checkpoint_dir, "m0")
  m0_grid <- m0_grid0
  m0_tuning <- NULL
  m0_settled <- FALSE
  mark("m0", {
    for (attempt in seq_len(5L)) {
      write_status("m0_running", paste0("attempt=", attempt, "; specs=", nrow(m0_grid)))
      m0_tuning <- PAGe::tune_m0(
        allD,
        grid = m0_grid, manual_labels = manual_labels_train,
        n_cores = n_cores, verbose = TRUE, selection = selection,
        checkpoint_dir = m0_checkpoint,
        previous_results = if (attempt == 1L) NULL else m0_tuning$tuning
      )
      m0_plan <- PAGe::boundary_action_plan(m0_tuning, stage = "M0")
      saveRDS(m0_tuning, file.path(artifact_dir, "m0_tuning.rds"))
      write.csv(
        m0_plan$final_boundary_report,
        file.path(artifact_dir, paste0("m0_boundary_report_round", attempt, ".csv")),
        row.names = FALSE
      )
      saveRDS(m0_plan, file.path(artifact_dir, paste0("m0_boundary_plan_round", attempt, ".rds")))
      if (isTRUE(m0_plan$settled)) {
        m0_settled <- TRUE
        break
      }
      m0_grid <- m0_plan$next_grid
      write.csv(m0_grid, file.path(artifact_dir, paste0("m0_grid_round", attempt + 1L, ".csv")), row.names = FALSE)
    }
  })
  if (!m0_settled) {
    write_status("stopped", "M0 boundary unresolved after 5 attempts")
    stop("M0 boundary unresolved; stopping before M1 per protocol.")
  }
  invisible(PAGe::validate_m0_tuning(m0_tuning, grid = m0_grid, check_boundaries = TRUE))
  m0 <- mark("m0_fit", PAGe::freeze_m0(PAGe::fit_m0(
    allD, selection,
    config = m0_tuning$best_params,
    manual_labels = manual_labels_train, flag_args = PAGe:::.default_flag_args()
  ), tuning = m0_tuning))
  saveRDS(m0, m0_frozen_path)
  write_status("m0_settled", paste0("specs=", nrow(m0_grid)))
}

# ---- M1: frozen M0 identity; documented hard caps and selection rule ----
m1_frozen_path <- file.path(artifact_dir, "m1_frozen.rds")
if (file.exists(m1_frozen_path)) {
  m1 <- readRDS(m1_frozen_path)
  m1_grid <- tryCatch(
    readRDS(file.path(artifact_dir, "m1_tuning.rds"))$grid,
    error = function(e) data.frame()
  )
  write_status("m1_resumed", "loaded m1_frozen.rds from a prior attempt in this run_dir")
} else {
  m1_checkpoint <- file.path(checkpoint_dir, "m1")
  m1_grid <- m1_grid0
  m1_tuning <- NULL
  m1_settled <- FALSE
  mark("m1", {
    for (attempt in seq_len(4L)) {
      write_status("m1_running", paste0("attempt=", attempt, "; specs=", nrow(m1_grid)))
      m1_tuning <- PAGe::tune_m1(
        allD,
        m0 = m0,
        m1 = list(m1_params = PAGe:::.default_m1_params()),
        grid = m1_grid, n_cores = n_cores, checkpoint_dir = m1_checkpoint,
        verbose = TRUE, selection = selection
      )
      m1_tuning$hard_caps <- m1_hard_caps
      m1_plan <- PAGe::boundary_action_plan(
        m1_tuning,
        stage = "M1", hard_caps = m1_hard_caps,
        steps = c(k_ref = 5, slope_weight = 4)
      )
      saveRDS(m1_tuning, file.path(artifact_dir, "m1_tuning.rds"))
      write.csv(
        m1_plan$final_boundary_report,
        file.path(artifact_dir, paste0("m1_boundary_report_round", attempt, ".csv")),
        row.names = FALSE
      )
      saveRDS(m1_plan, file.path(artifact_dir, paste0("m1_boundary_plan_round", attempt, ".rds")))
      if (isTRUE(m1_plan$settled)) {
        m1_settled <- TRUE
        break
      }
      m1_grid <- m1_plan$next_grid
      write.csv(m1_grid, file.path(artifact_dir, paste0("m1_grid_round", attempt + 1L, ".csv")), row.names = FALSE)
    }
  })
  if (!m1_settled) {
    write_status("stopped", "M1 boundary unresolved after 4 attempts")
    stop("M1 boundary unresolved; stopping before M2 per protocol.")
  }
  m1_selection <- PAGe::select_m1_candidate(
    m1_tuning,
    min_gain = 0.05, prefer_simpler = TRUE, hard_caps = m1_hard_caps
  )
  m1_tuning$best <- m1_selection$selected
  m1_tuning$m1_selection <- m1_selection
  saveRDS(m1_selection, file.path(artifact_dir, "m1_selection.rds"))
  invisible(PAGe::validate_m1_tuning(
    m1_tuning,
    check_boundaries = TRUE, hard_caps = m1_hard_caps
  ))
  m1_config <- PAGe:::.m1_params_from_tuning(PAGe:::.default_m1_params(), m1_tuning)
  m1 <- mark("m1_fit", PAGe::freeze_m1(PAGe::fit_m1(
    allD, selection,
    m0 = m0, config = m1_config
  ), tuning = m1_tuning))
  saveRDS(m1, m1_frozen_path)
  write_status("m1_settled", paste0("specs=", nrow(m1_grid)))
}

# ---- M2: governed offset_subset_v1 family on frozen M0/M1 identities ----
m2_settled_path <- file.path(artifact_dir, "m2_settled.rds")
if (file.exists(m2_settled_path)) {
  m2_tuning <- readRDS(m2_settled_path)
  write_status("m2_resumed", "loaded m2_settled.rds from a prior attempt in this run_dir")
} else {
  m2_checkpoint <- file.path(checkpoint_dir, "m2")
  m2_grid <- m2_grid0
  m2_tuning <- NULL
  m1_preds_carry <- NULL
  m2_settled <- FALSE
  write.csv(m2_grid, file.path(artifact_dir, "m2_grid_round1.csv"), row.names = FALSE)
  mark("m2", {
    for (attempt in seq_len(6L)) {
      write_status("m2_running", paste0(
        "attempt=", attempt, "; specs=", nrow(m2_grid),
        "; scale=equal_week; early_weight=", EARLY_WEIGHT
      ))
      m2_tuning <- PAGe::tune_m2(
        allD,
        selection = selection, m0 = m0, m1 = m1,
        grid = m2_grid, family = "offset_subset_v1",
        checkpoint_dir = m2_checkpoint,
        early_weight = EARLY_WEIGHT,
        early_max_t_since = EARLY_MAX_T_SINCE,
        score_scale = "equal_week",
        m1_train_preds = m1_preds_carry,
        n_cores = n_cores, verbose = TRUE
      )
      m1_preds_carry <- m2_tuning$m1_train_preds
      m2_tuning$min_nll_gain <- m2_gain_caps
      # expand_tuning_grid() adds exactly one probe row per unresolved
      # (axis, direction) pair across BOTH horizons -- round 1 against this
      # data legitimately needed 15 new rows (multiple k_z/k_u/k_d boundary
      # hits at once), so +12 was too tight and stopped a correct expansion.
      # +40 leaves real headroom while still catching genuine runaway growth.
      m2_plan <- PAGe::boundary_action_plan(
        m2_tuning,
        stage = "M2", max_specs = nrow(m2_grid) + 40L
      )
      saveRDS(m2_tuning, file.path(artifact_dir, "m2_tuning.rds"))
      write.csv(m2_tuning$grid, file.path(artifact_dir, "m2_grid.csv"), row.names = FALSE)
      write.csv(m2_tuning$scores, file.path(artifact_dir, "m2_fold_scores.csv"), row.names = FALSE)
      write.csv(m2_tuning$summary, file.path(artifact_dir, "m2_summary.csv"), row.names = FALSE)
      write.csv(
        m2_plan$final_boundary_report,
        file.path(artifact_dir, paste0("m2_boundary_report_round", attempt, ".csv")),
        row.names = FALSE
      )
      saveRDS(m2_plan, file.path(artifact_dir, paste0("m2_boundary_plan_round", attempt, ".rds")))
      if (isTRUE(m2_plan$settled)) {
        m2_settled <- TRUE
        break
      }
      m2_grid <- m2_plan$next_grid
      write.csv(m2_grid, file.path(artifact_dir, paste0("m2_grid_round", attempt + 1L, ".csv")), row.names = FALSE)
    }
  })
  if (!m2_settled) {
    write_status("stopped", "M2 subset boundary unresolved after 6 attempts")
    stop("M2 boundary unresolved; stopping before kit assembly per protocol.")
  }
  invisible(PAGe::validate_m2_tuning(
    m2_tuning,
    check_boundaries = TRUE, min_nll_gain = m2_gain_caps
  ))
  saveRDS(m2_tuning, m2_settled_path)
}

# ---- Predeclared adoption gate on inner LOSO evidence only ----
write_status("gate_running", "inner out-of-fold matched M1/M2 replay evidence")
gate <- mark("gate", local({
  rows <- m2_tuning$training_rows
  cfg <- m2_tuning$selected_config
  matched <- do.call(rbind, lapply(selection$training_seasons, function(s) {
    # rows include forecast_available == FALSE placeholders (pre-ignition /
    # prefix-unavailable origins), which carry non-finite m1_logit/z/u/d by
    # design -- m2_subset_fit()'s own validation correctly rejects those.
    # Every other fit/predict site in the pipeline filters to
    # forecast_available first (e.g. .nested_inner_gate_rows()); this
    # hand-rolled gate loop had skipped that filter.
    avail <- !is.na(rows$forecast_available) & rows$forecast_available
    tr <- rows[rows$season != s & avail, , drop = FALSE]
    va <- rows[rows$season == s & avail, , drop = FALSE]
    if (!nrow(va)) {
      return(NULL)
    }
    preds <- lapply(1:2, function(h) {
      spec <- cfg[[paste0("h", h)]]
      fit <- PAGe:::m2_subset_fit(tr, spec, gamma = cfg$gamma)
      vh <- va[va$h == h, , drop = FALSE]
      if (!nrow(vh)) {
        return(NULL)
      }
      data.frame(
        season = s, origin = vh$eval_weekF, target = vh$target_weekF,
        horizon = h, outcome = vh$y_lead / vh$N_lead,
        m1_prediction = vh$m1_p,
        m2_prediction = PAGe:::m2_subset_predict(fit, vh)$p_hat,
        t_since_target = vh$u + h, N_lead = vh$N_lead,
        # decide_m2_vs_m1() defaults to page_v2 scoring, which needs
        # weight_page_v2 (or ignition/peak columns to derive it) -- `vh`
        # already carries the correctly-computed column, just wasn't
        # forwarded into this hand-rolled matched frame.
        weight_page_v2 = vh$weight_page_v2,
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, preds[!vapply(preds, is.null, logical(1))])
  }))
  decision <- PAGe::decide_m2_vs_m1(
    matched,
    outcome_col = "outcome", m1_col = "m1_prediction", m2_col = "m2_prediction",
    season_col = "season", origin_col = "origin", target_col = "target",
    horizon_col = "horizon", t_since_col = "t_since_target",
    phase_break = EARLY_MAX_T_SINCE,
    phase_weights = c(pre_ignition = 0, early = EARLY_WEIGHT, late = 1),
    min_gain = MIN_GAIN_COMBINED,
    min_gain_by_horizon = c("2" = MIN_GAIN_H2),
    confidence = GATE_CONFIDENCE,
    max_season_degradation = MAX_SEASON_DEGRADATION
  )
  sensitivity <- PAGe::decide_m2_vs_m1(
    matched,
    outcome_col = "outcome", m1_col = "m1_prediction", m2_col = "m2_prediction",
    season_col = "season", origin_col = "origin", target_col = "target",
    horizon_col = "horizon", t_since_col = "t_since_target",
    phase_break = EARLY_MAX_T_SINCE,
    phase_weights = c(pre_ignition = 0, early = EARLY_WEIGHT, late = 1),
    denominator_col = "N_lead",
    min_gain = MIN_GAIN_COMBINED,
    min_gain_by_horizon = c("2" = MIN_GAIN_H2),
    confidence = GATE_CONFIDENCE,
    max_season_degradation = MAX_SEASON_DEGRADATION
  )
  list(matched = matched, decision = decision, sensitivity = sensitivity)
}))
write.csv(gate$matched, file.path(artifact_dir, "inner_gate_matched_rows.csv"), row.names = FALSE)
saveRDS(gate$decision, file.path(artifact_dir, "inner_gate_decision.rds"))
saveRDS(gate$sensitivity, file.path(artifact_dir, "inner_gate_decision_test_count_sensitivity.rds"))
write.csv(gate$decision$by_season, file.path(artifact_dir, "inner_gate_by_season.csv"), row.names = FALSE)
write.csv(gate$decision$by_horizon, file.path(artifact_dir, "inner_gate_by_horizon.csv"), row.names = FALSE)

adopt_m2 <- identical(gate$decision$decision, "use_m2")
selected_config <- m2_tuning$selected_config
if (!adopt_m2) {
  all_off <- PAGe::m2_subset_config(
    h1 = PAGe:::m2_subset_spec(), h2 = PAGe:::m2_subset_spec(),
    alpha_state = selected_config$alpha_state, gamma = selected_config$gamma
  )
  gate$decision_applied <- list(
    action = "selected exact all-off M1 configuration before opening 2025-26",
    reasons = gate$decision$reasons,
    tuned_best_spec_id = m2_tuning$best_spec_id,
    applied_spec_id = all_off$h1$id
  )
  off_row <- m2_tuning$grid[as.character(m2_tuning$grid$id) == "i0_kz0_ku0_kd0", , drop = FALSE]
  m2_tuning$selected_config <- all_off
  m2_tuning$selected <- list(h1 = off_row, h2 = off_row)
  m2_tuning$best_spec_id <- paste0("h1:", off_row$id, "|h2:", off_row$id)
  selected_config <- all_off
  write_status("gate_keep_m1", paste0(
    "reasons=", paste(gate$decision$reasons, collapse = ";")
  ))
} else {
  gate$decision_applied <- list(
    action = "adopted tuned M2 offset-subset candidate",
    tuned_best_spec_id = m2_tuning$best_spec_id
  )
  write_status("gate_use_m2", paste0("spec=", m2_tuning$best_spec_id))
}
saveRDS(gate$decision_applied, file.path(artifact_dir, "gate_decision_applied.rds"))
invisible(PAGe::validate_m2_tuning(m2_tuning))

m2 <- mark("m2_fit", PAGe::freeze_m2(PAGe::fit_m2(
  allD, selection,
  m0 = m0, m1 = m1,
  config = selected_config, family = "offset_subset_v1",
  m1_train_preds = m2_tuning$m1_train_preds
), tuning = m2_tuning))
saveRDS(m2, file.path(artifact_dir, "m2_frozen.rds"))
kit <- PAGe::assemble_kit(m0, m1, m2, best_spec_id = m2_tuning$best_spec_id)
invisible(PAGe::validate_page_kit(kit))
saveRDS(kit, file.path(artifact_dir, "candidate_pre_holdout.rds"))
write_status("kit_assembled", paste0(
  "governance_id=", kit$governance_id %||% "legacy",
  "; spec=", m2_tuning$best_spec_id
))

# ---- Strict unseen replay of 2025-26 (final step) ----
replay <- mark("replay", PAGe::replay_season_holdout(
  kit, allD,
  season = holdout, kit_compatibility = "strict"
))
if (!identical(as.character(replay$status), "unseen_replay_complete")) {
  write_status("failed", paste0("replay status=", replay$status))
  stop("Replay did not satisfy the unseen-replay contract: ", replay$status)
}
saveRDS(replay, file.path(artifact_dir, "holdout_2025_26_replay.rds"))
write.csv(replay$predictions, file.path(artifact_dir, "holdout_2025_26_predictions.csv"), row.names = FALSE)
write_status("replay_frozen", paste0("predictions=", nrow(replay$predictions)))

# ---- Retrospective reporting only; predictions are already frozen ----
manual_label_holdout <- full_manual_labels[holdout]
m2_preds <- replay$stages$m2_predictions
pred <- replay$predictions
h_num <- as.integer(sub("^h", "", as.character(pred$lead)))
m2_h <- if ("h" %in% names(m2_preds)) {
  as.integer(sub("^h", "", as.character(m2_preds$h)))
} else {
  as.integer(sub("^h", "", as.character(m2_preds$lead)))
}
join_idx <- match(paste(pred$weekF, h_num), paste(m2_preds$eval_week, m2_h))
retro <- data.frame(
  season = pred$season, origin = pred$weekF, target = pred$target_weekF,
  horizon = h_num, outcome = pred$p_obs,
  m1_prediction = m2_preds$m1_p[join_idx],
  m2_prediction = pred$p_hat,
  t_since_target = pred$t_since + h_num,
  t_since_manual_origin = pred$weekF - manual_label_holdout[[1L]],
  N_lead = pred$N_lead,
  forecast_action = pred$forecast_action %||% NA_character_,
  stringsAsFactors = FALSE
)
retro <- retro[is.finite(retro$m1_prediction) & is.finite(retro$m2_prediction) &
  is.finite(retro$outcome), , drop = FALSE]
if (!nrow(retro)) {
  write_status("failed", "no matched retrospective M1/M2 rows from replay")
  stop("Retrospective matched frame is empty; replay join failed.")
}
write.csv(retro, file.path(artifact_dir, "holdout_2025_26_matched_labelled.csv"), row.names = FALSE)

# This whole block is bonus/secondary reporting on top of the ALREADY-FROZEN
# replay (predictions and the gate decision are both already saved above) --
# it must never be able to block the run from reaching run_summary.rds /
# "success". `retro` has no weight_page_v2 or ignition/peak columns (unlike
# the inner gate's `rows`), so page_v2's default scoring can't compute
# phase weights here; use scoring="legacy_0_12" (D-17's registered
# sensitivity line, not an ad hoc substitute) which only needs the
# t_since_col/phase_weights already supplied. Any other failure here is
# caught and logged rather than aborting the run.
retro_report_ok <- tryCatch(
  {
    retro_decision <- PAGe::decide_m2_vs_m1(
      retro,
      outcome_col = "outcome", m1_col = "m1_prediction", m2_col = "m2_prediction",
      season_col = "season", origin_col = "origin", target_col = "target",
      horizon_col = "horizon", t_since_col = "t_since_target",
      phase_break = EARLY_MAX_T_SINCE,
      phase_weights = c(pre_ignition = 0, early = EARLY_WEIGHT, late = 1),
      min_gain = MIN_GAIN_COMBINED,
      min_gain_by_horizon = c("2" = MIN_GAIN_H2),
      confidence = GATE_CONFIDENCE,
      max_season_degradation = MAX_SEASON_DEGRADATION,
      scoring = "legacy_0_12"
    )
    retro_comparison <- PAGe::compare_m1_m2(
      retro,
      outcome_col = "outcome", m1_col = "m1_prediction", m2_col = "m2_prediction",
      season_col = "season", origin_col = "origin", target_col = "target",
      horizon_col = "horizon"
    )
    retro_comparison_sensitivity <- PAGe::compare_m1_m2(
      retro,
      outcome_col = "outcome", m1_col = "m1_prediction", m2_col = "m2_prediction",
      season_col = "season", origin_col = "origin", target_col = "target",
      horizon_col = "horizon", denominator_col = "N_lead"
    )
    saveRDS(list(
      note = paste0(
        "Retrospective reporting on the frozen 2025-26 replay; cannot change ",
        "the pre-holdout selected model. Manual ignition label joined only ",
        "after predictions were frozen. Uses legacy_0_12 scoring (no ",
        "page_v2 weight/ignition/peak columns available on the replay join)."
      ),
      decision = retro_decision,
      comparison = retro_comparison,
      comparison_test_count_sensitivity = retro_comparison_sensitivity
    ), file.path(artifact_dir, "holdout_retrospective_report.rds"))
    write.csv(as.data.frame(retro_decision$overall), file.path(artifact_dir, "holdout_retro_decision_overall.csv"), row.names = FALSE)
    write.csv(retro_comparison$forecast$by_horizon, file.path(artifact_dir, "holdout_retro_comparison_by_horizon.csv"), row.names = FALSE)
    TRUE
  },
  error = function(e) {
    write_status("retro_report_failed", paste0(
      "non-blocking: retrospective reporting failed, frozen replay unaffected: ",
      conditionMessage(e)
    ))
    retro_decision <<- NULL
    retro_comparison <<- NULL
    FALSE
  }
)

saveRDS(list(
  status = "success",
  completed_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  holdout_season = holdout, training_seasons = selection$training_seasons,
  m2_family = "offset_subset_v1",
  gate_decision = gate$decision$decision,
  gate_applied = gate$decision_applied,
  selected_m2_spec_id = m2_tuning$best_spec_id,
  n_predictions = nrow(replay$predictions),
  m0_specs = nrow(m0_grid), m1_specs = nrow(m1_grid),
  m2_specs = nrow(m2_tuning$grid),
  kit_governance_id = kit$governance_id %||% NA_character_,
  stage_seconds = stage_times,
  retrospective = list(
    decision = retro_decision$decision,
    overall = retro_decision$overall,
    recommendation = retro_comparison$recommendation
  )
), file.path(artifact_dir, "run_summary.rds"))
writeLines(capture.output(utils::sessionInfo()), file.path(artifact_dir, "session_info.txt"))
saveRDS(stage_times, file.path(artifact_dir, "stage_timings.rds"))
write_status("success", paste0(
  "gate=", gate$decision$decision,
  "; predictions=", nrow(replay$predictions),
  "; retro=", retro_decision$decision
))
message(
  holdout, " outer-fold pilot complete: gate=", gate$decision$decision,
  "; replay predictions=", nrow(replay$predictions)
)
