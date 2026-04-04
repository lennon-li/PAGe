# Quick test: slope weighting + dynamic temperature on 2025-26
# Compare old (no slope/dyntemp) vs new

library(dplyr)
library(tidyr)
library(MMWRweek)
library(flualign)

wd <- "C:/Users/lennon.li/Documents/claude/PAGe"
source(file.path(wd, "R/m1_reference.R"))
source(file.path(wd, "R/m1_loso.R"))
source(file.path(wd, "R/utils.R"))
source(file.path(wd, "R/pipeline_runtime_helpers.R"))
source(file.path(wd, "R/m0_runtime.R"))
source(file.path(wd, "R/m2_runtime.R"))
source(file.path(wd, "R/pipeline_runtime.R"))
source(file.path(wd, "R/m1_runtime.R"))
source(file.path(wd, "R/m1_multi_template.R"))
source(file.path(wd, "R/getCurrentD.R"))

startWeek <- 27L

tuned  <- readRDS(file.path(wd, "data/stage1_tuning.rds"))
params <- tuned$best_params

manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)

# Historical data
allD_hist <- read.csv(file.path(wd, "data/flu_testing_data.csv")) %>%
  select(season, week, year, start_year = seasonstart, date = week_start_date,
         y = pos_flua, N = test_flu) %>%
  mutate(neg = N - y, date = as.Date(date),
         mmwr_year = ifelse(week >= 35L, start_year, start_year + 1L),
         nW_true   = n_weeks_in_start_year(start_year),
         weekF     = ((week - startWeek) %% nW_true) + 1L,
         p = y / N) %>%
  filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

# Build FS ref (reuse cached if available)
REF_CACHE <- file.path(wd, "data/ref_production.rds")
if (file.exists(REF_CACHE)) {
  ref_cache <- readRDS(REF_CACHE)
} else {
  flag_args <- list(p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L,
                    min_window = 10L, w_min = 21L, w_max = 21L, d2_relax = -0.01)
  res_deriv <- estimateDerivs(allD_hist, k = 10L)
  train_outs <- res_deriv$data %>%
    group_by(season) %>% group_split(.keep = TRUE) %>%
    purrr::map(~ do.call(flagIgnition, c(list(df = .x, manual_labels = manual_labels), flag_args)))
  aligned_train <- alignIgnition(train_outs)
  ref <- estimateRef(alignedD = aligned_train, exSeason = character(0),
                     k = 25L, n_weeks = 52L, method = "fs")
  ref$g_ref_fun_orig <- ref$g_ref_fun
  hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
  ref_cache <- list(ref = ref, hyper = hyper)
  saveRDS(ref_cache, REF_CACHE)
}
ref   <- ref_cache$ref
hyper <- ref_cache$hyper

# Current season data
currentD_full <- getCurrentD(startWeek = startWeek) %>%
  filter(season == "2025-26")

# Ignition detection
ign_out <- run_ignition_weekly(
  currentSeason  = currentD_full,
  ign_fit_or_gam = NULL,
  params         = params,
  start_week     = 1L
)

walk_start <- max(5L, as.integer(ign_out$ign_week_locked))
walk_end   <- max(currentD_full$weekF, na.rm = TRUE)
eval_weeks <- seq(walk_start, walk_end)

true_peak <- 25L  # weekF=25, MMWR week 51

run_walkforward <- function(label, slope_wt, dyn_temp, dyn_pivot) {
  cat(sprintf("\n=== %s (slope_weight=%.1f, dynamic_temp=%s, pivot=%d) ===\n",
              label, slope_wt, dyn_temp, dyn_pivot))

  results <- lapply(eval_weeks, function(ew) {
    season_to_ew <- filter(currentD_full, weekF <= ew)
    ap <- run_alignment_prospective_multi(
      currentSeason      = season_to_ew,
      ref                = ref,
      hyper              = hyper,
      ign_out            = ign_out,
      use_ci             = TRUE,
      buffer_weeks       = 0L,
      level              = 0.95,
      min_obs            = 4L,
      curvature_ratio    = 1.0,
      temperature        = 0.25,
      rise_weight        = 1.0,
      slope_weight       = slope_wt,
      slope_window       = 4L,
      dynamic_temp       = dyn_temp,
      dynamic_temp_pivot = dyn_pivot
    )
    list(eval_week = ew, peak_weekF = ap$peak_weekF, state = ap$state)
  })

  df <- do.call(rbind, lapply(results, function(r) {
    data.frame(eval_week = r$eval_week,
               peak_hat  = ifelse(is.null(r$peak_weekF), NA, r$peak_weekF),
               state     = r$state, stringsAsFactors = FALSE)
  }))

  # Only pre-peak evals for Weibull MAE
  df$error <- abs(df$peak_hat - true_peak)
  pre_peak <- df[!is.na(df$peak_hat) & df$eval_week <= true_peak, ]

  if (nrow(pre_peak) > 0) {
    t_before <- true_peak - pre_peak$eval_week
    w_weib   <- exp(-(0.1 * t_before)^2)
    mae_weib <- sum(w_weib * pre_peak$error) / sum(w_weib)
    cat(sprintf("  Weibull MAE = %.4f weeks\n", mae_weib))
  }

  # Print all predictions
  for (i in seq_len(nrow(df))) {
    r <- df[i, ]
    marker <- if (!is.na(r$peak_hat) && r$peak_hat == true_peak) " *" else ""
    cat(sprintf("  ew=%d  peak_hat=%s  err=%s%s\n",
                r$eval_week,
                ifelse(is.na(r$peak_hat), "NA", as.character(r$peak_hat)),
                ifelse(is.na(r$error), "NA", as.character(r$error)),
                marker))
  }

  invisible(df)
}

# Baseline: no slope weighting, no dynamic temp (matches previous run)
df_base <- run_walkforward("Baseline (no slope, no dyntemp)", 0, FALSE, 10L)

# New: slope weighting + dynamic temp
df_new <- run_walkforward("New (slope=0.5, dyntemp pivot=10)", 0.5, TRUE, 10L)

# Aggressive slope
df_agg <- run_walkforward("Aggressive (slope=1.0, dyntemp pivot=15)", 1.0, TRUE, 15L)

cat("\nDone.\n")
