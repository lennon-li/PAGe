#!/usr/bin/env Rscript
# ─────────────────────────────────────────────────────────────────────────────
# M1 alignment hyperparameter tuning via LOSO grid search
#
# Grid:  k_ref × multi_temperature × template_shift × align_rise_weight
#        3 × 3 × 3 × 3 = 81 specifications
#
# Metric: Weibull-weighted peak MAE  w(t) = exp(-(0.1t)^2)
#
# Usage:
#   Rscript scripts/tune_m1_alignment.R
#   Rscript scripts/tune_m1_alignment.R --cores=4
# ─────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(tibble)
  library(mgcv)
  library(gamm4)
  library(gratia)
  library(MMWRweek)
  library(future)
  library(furrr)
})

# ---- Parse CLI args ----
args <- commandArgs(trailingOnly = TRUE)
n_cores_arg <- NULL
for (a in args) {
  if (grepl("^--cores=", a)) n_cores_arg <- as.integer(sub("^--cores=", "", a))
}
N_CORES <- if (!is.null(n_cores_arg)) n_cores_arg else (parallel::detectCores() - 1L)

# ---- Load package ----
devtools::load_all("flualign", quiet = TRUE)

# ---- Constants ----
startWeek <- 27L
EXCLUDE_SEAS <- "2015-16"

manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
) - 1L

n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

# ---- Load data ----
message("Loading data...")
allD <- read.csv("data/flu_testing_data.csv") %>%
  select(season, week, year, start_year = seasonstart,
         date = week_start_date, y = pos_flua, N = test_flu) %>%
  mutate(
    neg       = N - y,
    date      = as.Date(date),
    mmwr_year = ifelse(week >= 35L, start_year, start_year + 1L),
    nW_true   = n_weeks_in_start_year(start_year),
    weekF     = ((week - startWeek) %% nW_true) + 1L,
    p         = y / N
  ) %>%
  filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

# ---- Stage-1 params ----
tuned  <- readRDS("data/stage1_tuning.rds")
params <- tuned$best_params

# ---- Define grid: 81 specs ----
grid <- expand.grid(
  k_ref             = c(15L, 20L, 25L),
  multi_temperature = c(0.5, 1.0, 2.0),
  template_shift    = c(-1L, 0L, 1L),
  align_rise_weight = c(1.0, 2.0, 3.0),
  stringsAsFactors  = FALSE
)

message(sprintf("Grid: %d specs  |  Cores: %d", nrow(grid), N_CORES))

# ---- Run tuning ----
results <- tune_m1_alignment(
  allD              = allD,
  params            = params,
  grid              = grid,
  manual_labels     = manual_labels,
  exclude_seasons   = EXCLUDE_SEAS,
  n_weeks           = 52L,
  n_cores           = N_CORES,
  checkpoint_dir    = "data/m1_tune_ckpt",
  # Fixed args for all specs
  k_deriv           = 20L,
  buffer_weeks      = 5L,
  use_ci            = TRUE,
  use_multi_template = TRUE,
  ref_method        = "fs",
  peak_weight_boost = 3,
  peak_weight_decay = 0.3,
  verbose           = TRUE
)

# ---- Save final results ----
saveRDS(results, "data/m1_alignment_tuning.rds")

# ---- Print top 10 ----
message("\n===== Top 10 specs by Weibull-weighted peak MAE =====\n")
top10 <- results$scores %>%
  head(10) %>%
  select(spec_id, k_ref, multi_temperature, template_shift,
         align_rise_weight, mae_uniform, mae_exp, mae_weibull, n_seasons)
print(as.data.frame(top10), row.names = FALSE)

message(sprintf("\nBest: %s  (mae_weibull = %.4f)",
                results$best$spec_id, results$best$mae_weibull))
message("Results saved to data/m1_alignment_tuning.rds")
