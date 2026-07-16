#!/usr/bin/env Rscript
# Shared setup sourced by every fresh_run script.
# This directory preserves historical research workflows. New production work
# should use train_pipeline(), replay_season_holdout(), and check_promotion().

.find_page_repo_root <- function() {
  script_file <- tryCatch(sys.frame(1L)$ofile, error = function(e) NULL)
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg)) {
    script_file <- c(script_file, sub("^--file=", "", file_arg))
  }
  starts <- unique(c(
    getwd(),
    dirname(normalizePath(script_file, mustWork = FALSE))
  ))

  for (start in starts[nzchar(starts)]) {
    candidate <- normalizePath(start, mustWork = FALSE)
    repeat {
      if (file.exists(file.path(candidate, "PAGe", "DESCRIPTION")) &&
          file.exists(file.path(candidate, "scripts", "fresh_run", "00_shared.R"))) {
        return(candidate)
      }
      parent <- dirname(candidate)
      if (identical(parent, candidate)) break
      candidate <- parent
    }
  }
  stop(
    "Could not locate the PAGe repository root. Source this file from within ",
    "the repository or run it by its absolute path."
  )
}

PAGE_REPO_ROOT <- .find_page_repo_root()
setwd(PAGE_REPO_ROOT)
rm(.find_page_repo_root)

if (requireNamespace("PAGe", quietly = TRUE)) {
  suppressPackageStartupMessages(library(PAGe))
} else if (requireNamespace("devtools", quietly = TRUE)) {
  suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))
} else {
  stop("Install PAGe or devtools before running the historical fresh_run scripts.")
}

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(future)
  library(furrr)
  library(mgcv)
  library(gamm4)
  library(MMWRweek)
  library(data.table)
})

for (f in c(
  "R/utils.R", "R/m0_retro.R", "R/m0_training.R", "R/flagIgnition.R",
  "R/m1_reference_helpers.R", "R/m1_reference.R", "R/m1_hyperparams.R",
  "R/m1_multi_template.R", "R/m1_loso.R", "R/m1_fit.R",
  "R/m2_spec_grid.R", "R/m2_training.R",
  "R/m2_loso_utils.R", "R/m2_loso_fold.R", "R/m2_loso_eval.R", "R/m2_loso_cv.R",
  "R/pipeline_bridge.R", "R/pipeline_runtime_helpers.R",
  "R/pipeline_runtime.R"
)) source(f)

n_cores <- max(1L, parallel::detectCores() - 1L)

# ---- Shared constants ----
START_WEEK   <- 27L
HOLDOUT_SEASON <- "2025-26"
EXCLUDE_PERM <- c("2011-12", "2020-21", "2021-22", HOLDOUT_SEASON)
EXCLUDE_M1   <- c(EXCLUDE_PERM, "2015-16")

manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)

flag_args <- list(
  p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L,
  min_window = 10L, w_min = 21L, w_max = 21L, d2_relax = -0.01
)

M1_PARAMS <- list(
  k_ref = 25L, ref_method = "fs", temperature = 0.25,
  rise_weight = 1.0, trough_weight = 0.1, peak_decay = 0.3,
  slope_weight = 8.0, slope_window = 6L,
  dynamic_temp = FALSE, dynamic_temp_pivot = 10L
)

n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

load_allD <- function(exclude = EXCLUDE_PERM, include_holdout = FALSE) {
  # Fail closed: the prospective holdout is never returned for fitting unless
  # a caller explicitly opts in for replay/evaluation. Production release is
  # governed by train_pipeline() and a passing check_promotion() report.
  if (!isTRUE(include_holdout)) exclude <- unique(c(exclude, HOLDOUT_SEASON))

  read.csv("data/flu_testing_data.csv") |>
    dplyr::select(season, week, year, start_year = seasonstart,
                  date = week_start_date, y = pos_flua, N = test_flu) |>
    dplyr::mutate(
      neg     = N - y,
      date    = as.Date(date),
      nW_true = n_weeks_in_start_year(start_year),
      weekF   = ((week - START_WEEK) %% nW_true) + 1L,
      p       = y / N
    ) |>
    dplyr::filter(!season %in% exclude)
}

build_aligned <- function(dat) {
  res <- estimateDerivs(dat, k = 10L)
  outs <- res$data |>
    dplyr::group_by(season) |>
    dplyr::group_split(.keep = TRUE) |>
    purrr::map(function(df)
      do.call(flagIgnition, c(list(df = df, manual_labels = manual_labels), flag_args)))
  alignIgnition(outs)
}

cat(
  "Research/compatibility fresh_run setup loaded. ",
  "Use train_pipeline() for production training. Cores:", n_cores, "\n"
)
