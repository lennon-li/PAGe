setwd("C:/Users/lennon.li/Documents/claude/PAGe")

library(tidyverse)
library(mgcv)
library(data.table)
library(MMWRweek)
library(flualign)

source("R/retro_estimation.R")
source("R/ignitionTraining.R")
source("R/prospective_training.R")
source("R/prospective_running.R")
source("R/module_training.R")

# ---- Settings (same as qmd) ----
startWeek  <- 27
min_window <- 10
p_thresh   <- 0.01
k1         <- 0.4
k2         <- -0.01
manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)

n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

allD <- read.csv("data/flu_testing_data.csv") %>%
  select(
    season, week, year,
    start_year = seasonstart,
    date = week_start_date,
    y = pos_flua,
    N = test_flu
  ) %>%
  mutate(
    neg       = N - y,
    date      = as.Date(date),
    mmwr_year = ifelse(week >= 35L, start_year, start_year + 1L),
    nW_true   = n_weeks_in_start_year(start_year),
    weekS     = ((week - 35L)       %% nW_true) + 1L,
    weekF     = ((week - startWeek) %% nW_true) + 1L,
    p         = y / N
  ) %>%
  filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

res <- estimateDerivs(allD, k = 10)

outs <- res$data %>%
  group_by(season) %>%
  group_split(.keep = TRUE) %>%
  purrr::map(~ flagIgnition(
    df            = .x,
    p_thresh      = p_thresh,
    k1            = k1,
    k_c           = 0.01,
    n_consec      = 2,
    min_window    = min_window,
    w_min         = 21,
    w_max         = 21,
    d2_relax      = k2,
    manual_labels = manual_labels
  ))

alignedD <- alignIgnition(outs)

grid_loso <- data.table::CJ(
  cls_thr   = 0.26,
  use_cls   = FALSE,
  p_thr     = c(0.002, 0.003, 0.004, 0.005),
  prev_thr  = c(0.001, 0.002, 0.003),
  n_consec  = 5L,
  L         = 2L,
  eps       = 0,
  K_sum     = 5L,
  p_sum_thr = c(0.050, 0.055, 0.060),
  N_req     = 4L,
  w_min     = 13L,
  w_max     = 26L,
  K_dp      = 3L,
  dp_thr    = 0.01,
  sorted    = FALSE
)

cat("Grid:", nrow(grid_loso), "x 10 folds =", nrow(grid_loso) * 10, "evals\n")

tuned <- loso_M0v2(
  dat  = alignedD,
  grid = as.data.frame(grid_loso),
  score_col    = "p_cls_p",
  drop_seasons = c("2015-16"),
  exSeason_tune = NULL,

  fit_args = list(
    fit_base = TRUE, fit_slope = FALSE, fit_fs = FALSE,
    event_k = 1L, lead = 1L, A_pre = 6L, B_post = 6L,
    k_week = 6L, k_p = 8L, k_fs = 4L,
    select = FALSE, verbose = FALSE
  ),

  tune_args = list(
    miss_penalty   = 0,
    lambda         = 20,
    kappa          = 0,
    gamma          = 25,
    gamma_late     = 0,
    iWeek          = TRUE,
    ncores         = 10L,
    verbose        = FALSE,
    progress_every = 50L
  ),

  verbose = TRUE
)

saveRDS(tuned, "data/stage1_tuning.rds")
cat("Done. Saved to data/stage1_tuning.rds\n")
print(tuned$best_params)
print(tuned$summary)
cat("\n=== compare ===\n")
tuned$compare |>
  as.data.frame() |>
  gt::gt() |>
  gt::fmt_number(columns = where(is.double), decimals = 3) |>
  gt::tab_style(
    style = list(gt::cell_fill(color = "#d4edda"), gt::cell_text(weight = "bold")),
    locations = gt::cells_body(rows = 1)
  ) |>
  print()
