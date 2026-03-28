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

# ---- 1. Build allD ----
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

cat("=== allD ===\n")
cat("seasons:", paste(sort(unique(allD$season)), collapse=", "), "\n")
cat("weekF range:", paste(range(allD$weekF), collapse="-"), "\n")

tuned  <- readRDS("data/stage1_tuning.rds")
params <- tuned$best_params
cat("\n=== params ===\n")
print(params)

# ---- 2. Test run_ignition_weekly on 2017-18 ----
cat("\n=== run_ignition_weekly on 2017-18 (weeks 10-30) ===\n")
test_raw <- filter(allD, season == "2017-18", weekF <= 30)
cat("test_raw rows:", nrow(test_raw), "\n")
cat("test_raw weekF:", paste(test_raw$weekF, collapse=","), "\n")

ign_out <- run_ignition_weekly(
  currentSeason  = test_raw,
  ign_fit_or_gam = NULL,
  params         = params,
  start_week     = 10L
)

cat("ign_week_locked:", ign_out$ign_week_locked, "\n")
cat("iWeek_hat_locked:", ign_out$iWeek_hat_locked, "\n")
cat("\nign_out$df:\n")
print(as.data.frame(ign_out$df[, c("weekF","ignite_ok_now","iWeek_hat_dynamic")]))

# ---- 3. Test training pipeline on training seasons for 2017-18 ----
cat("\n=== Training pipeline for 2017-18 ===\n")
TEST_SEASON   <- "2017-18"
manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)
tr_seasons  <- setdiff(sort(unique(allD$season)), TEST_SEASON)
train_allD  <- filter(allD, season %in% tr_seasons)
cat("Training seasons:", paste(tr_seasons, collapse=", "), "\n")

cat("\nRunning estimateDerivs...\n")
res_deriv <- estimateDerivs(train_allD, k = 10)
cat("estimateDerivs done. Columns:", paste(names(res_deriv$data), collapse=", "), "\n")

cat("\nRunning flagIgnition per season...\n")
train_outs <- res_deriv$data %>%
  group_by(season) %>%
  group_split(.keep = TRUE) %>%
  purrr::map(~ flagIgnition(
    df = .x, manual_labels = manual_labels,
    p_thresh=0.01, k1=0.4, k_c=0.01, n_consec=2L,
    min_window=10L, w_min=21L, w_max=21L, d2_relax=-0.01
  ))
cat("flagIgnition done. N seasons:", length(train_outs), "\n")
iWeeks <- sapply(train_outs, function(x) x$ignition$weekF)
cat("iWeeks:", paste(iWeeks, collapse=", "), "\n")

cat("\nRunning alignIgnition...\n")
aligned_train <- alignIgnition(train_outs)
cat("aligned_train rows:", nrow(aligned_train), "\n")
cat("anchorWeek attr:", attr(aligned_train, "anchorWeek"), "\n")
cat("iWeek col unique:", paste(sort(unique(aligned_train$iWeek)), collapse=", "), "\n")

cat("\nRunning estimateRef...\n")
ref <- estimateRef(alignedD = aligned_train, exSeason = character(0), k = 10, n_weeks = 52)
cat("estimateRef done. anchorWeek:", ref$anchorWeek, "\n")
cat("ref$dat rows:", nrow(ref$dat), "\n")

cat("\nrunning learn_alignment_hyperparams...\n")
hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
cat("hyper names:", paste(names(hyper), collapse=", "), "\n")

cat("\n=== All diagnostics passed ===\n")
