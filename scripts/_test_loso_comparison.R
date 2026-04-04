suppressPackageStartupMessages({
  library(tidyverse); library(mgcv); library(gamm4); library(gratia)
  library(data.table); library(MMWRweek)
  devtools::load_all("flualign", quiet = TRUE)
})
# Source non-package scripts that define detectIgnition_oneSeason etc.
source("R/m0_retro.R")
source("R/m0_training.R")
source("R/pipeline_runtime_helpers.R")
source("R/m0_runtime.R")
source("R/m2_runtime.R")
source("R/pipeline_runtime.R")

startWeek <- 27
manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
) - 1

allD <- read.csv("data/flu_testing_data.csv") %>%
  select(season, week, year, start_year = seasonstart, y = pos_flua, N = test_flu) %>%
  mutate(
    neg = N - y,
    nW_true = 52L + as.integer(MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L),
    weekF = ((week - startWeek) %% nW_true) + 1L,
    p = y / N
  ) %>%
  filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

tuned  <- readRDS("data/stage1_tuning.rds")
params <- tuned$best_params

EXCLUDE <- "2015-16"
TEST_SEAS <- c("2023-24")  # just one season for speed

cat("=== Testing baseline (single ref, no time weights) ===\n")
wf_base <- loso_walkforward(
  allD = allD, params = params, manual_labels = manual_labels,
  exclude_seasons = EXCLUDE, test_seasons = TEST_SEAS,
  k_deriv = 20L, k_ref = 25L, n_weeks = 52L,
  buffer_weeks = 5L, curvature_ratio = 1.0,
  align_rise_weight = 1.0,
  use_multi_template = FALSE, ref_method = "binomial",
  n_cores = parallel::detectCores() - 1L, verbose = TRUE
)
cat(sprintf("Baseline rows: %d\n", nrow(wf_base$params_df)))

cat("\n=== Testing C: Weighted (FS ref, rise_weight=3) ===\n")
wf_wt <- loso_walkforward(
  allD = allD, params = params, manual_labels = manual_labels,
  exclude_seasons = EXCLUDE, test_seasons = TEST_SEAS,
  k_deriv = 20L, k_ref = 25L, n_weeks = 52L,
  buffer_weeks = 5L, curvature_ratio = 1.0,
  align_rise_weight = 3.0, align_trough_weight = 0.1,
  use_multi_template = FALSE, ref_method = "fs",
  n_cores = parallel::detectCores() - 1L, verbose = TRUE
)
cat(sprintf("Weighted rows: %d\n", nrow(wf_wt$params_df)))

cat("\n=== Testing A: Multi-template ===\n")
wf_multi <- loso_walkforward(
  allD = allD, params = params, manual_labels = manual_labels,
  exclude_seasons = EXCLUDE, test_seasons = TEST_SEAS,
  k_deriv = 20L, k_ref = 25L, n_weeks = 52L,
  buffer_weeks = 5L, curvature_ratio = 1.0,
  align_rise_weight = 1.0,
  use_multi_template = TRUE, ref_method = "fs",
  multi_temperature = 0.5,
  n_cores = parallel::detectCores() - 1L, verbose = TRUE
)
cat(sprintf("Multi rows: %d\n", nrow(wf_multi$params_df)))

# Compare peak estimates
true_peak <- allD %>% filter(season == "2023-24") %>%
  slice_max(p, n = 1) %>% pull(weekF)
cat(sprintf("\nTrue peak weekF for 2023-24: %d\n", true_peak))

for (nm in c("Baseline", "Weighted", "Multi")) {
  wf <- switch(nm, Baseline = wf_base, Weighted = wf_wt, Multi = wf_multi)
  last_row <- wf$params_df %>% filter(!is.na(t_peak)) %>%
    slice_max(eval_week, n = 1)
  cat(sprintf("  %s: peak_weekF=%d, tau=%.2f, delta=%.3f\n",
              nm, last_row$peak_weekF, last_row$tau, last_row$delta))
}

cat("\n=== All LOSO comparison tests passed ===\n")
