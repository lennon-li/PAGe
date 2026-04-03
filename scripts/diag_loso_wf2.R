setwd("C:/Users/lennon.li/Documents/claude/PAGe")

library(MMWRweek)
library(flualign)
library(dplyr)
library(purrr)
library(future)
library(furrr)
library(mgcv)
library(gamm4)
library(gratia)

source("R/estimateRef.R")
source("R/loso_alignment.R")
source("R/utils.R")
source("R/prospective_running.R")

startWeek <- 27
allD <- read.csv("data/flu_testing_data.csv") %>%
  select(season, week, year, start_year = seasonstart, date = week_start_date,
         y = pos_flua, N = test_flu) %>%
  mutate(neg = N - y, date = as.Date(date),
         mmwr_year = ifelse(week >= 35L, start_year, start_year + 1L),
         nW_true   = n_weeks_in_start_year(start_year),
         weekF     = ((week - startWeek) %% nW_true) + 1L,
         p = y / N) %>%
  filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

tuned  <- readRDS("data/stage1_tuning.rds")
params <- tuned$best_params

manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)

cat("=== Running loso_walkforward ===\n")
wf <- loso_walkforward(
  allD          = allD,
  params        = params,
  walk_start    = 10L,
  walk_end      = 30L,
  manual_labels = manual_labels,
  test_seasons  = "2017-18",
  k_deriv       = 10,
  k_ref         = 10,
  n_weeks       = 52,
  n_cores       = 1L,
  verbose       = TRUE
)

cat("\n=== params_df ===\n")
print(as.data.frame(wf$params_df[, c("season","eval_week","iWeek_hat","iWeek_true","fallback_reason","tau","t_peak")]))

cat("\n=== forecast_df summary ===\n")
cat("nrow:", nrow(wf$forecast_df), "\n")
if (nrow(wf$forecast_df) > 0) {
  cat("eval_weeks with forecasts:", paste(sort(unique(wf$forecast_df$eval_week)), collapse=", "), "\n")
  cat("kind values:", paste(unique(wf$forecast_df$kind), collapse=", "), "\n")
  cat("Sample rows:\n")
  print(head(wf$forecast_df, 10))
}
