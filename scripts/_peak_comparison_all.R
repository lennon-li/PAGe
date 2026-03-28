suppressPackageStartupMessages({
  library(tidyverse); library(mgcv); library(gamm4); library(gratia)
  library(data.table); library(MMWRweek)
  devtools::load_all("flualign", quiet = TRUE)
})

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

res <- estimateDerivs(allD, k = 20L, peak_weight_boost = 3, peak_weight_decay = 0.3,
                      ignition_weeks = manual_labels)

outs <- res$data %>%
  group_by(season) %>%
  group_split(.keep = TRUE) %>%
  purrr::map(~ flagIgnition(
    df = .x, p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2,
    min_window = 10, w_min = 21, w_max = 21, d2_relax = -0.01,
    manual_labels = manual_labels
  ))

alignedD <- alignIgnition(outs) %>%
  mutate(phase = if_else(weekF < iWeek, 0L, 1L))

ex <- c("2024-25")
df <- 20

cat("\n===== Fitting 5 methods =====\n")

ref_list <- list(
  "1. Gaussian logit"  = estimateRef(alignedD, exSeason = ex, k = df, method = "gaussian_logit",
                                     trough_weight = 0.1, peak_weight_boost = 3),
  "2. Median + smooth" = estimateRef(alignedD, exSeason = ex, k = df, method = "median_smooth"),
  "3. Factor smooth"   = estimateRef(alignedD, exSeason = ex, k = df, method = "fs",
                                     trough_weight = 0.1, peak_weight_boost = 3),
  "4. Gaussian+FS"     = estimateRef(alignedD, exSeason = ex, k = df, method = "gaussian_logit_fs",
                                     trough_weight = 0.1, peak_weight_boost = 3)
)

# --- Peak week and peak_p for each method ---
peak_tbl <- purrr::imap_dfr(ref_list, function(r, nm) {
  pk_wk  <- r$pred_df$newWeek[which.max(r$pred_df$fit)]
  pk_val <- round(max(r$pred_df$fit), 4)
  tibble::tibble(Method = nm, peak_week = pk_wk, peak_p = pk_val)
})

# --- Per-season peaks in aligned (newWeek) space ---
season_peaks <- alignedD %>%
  filter(!season %in% ex) %>%
  group_by(season) %>%
  summarise(
    obs_peak_nw    = newWeek[which.max(replace(p,   is.na(p),   -Inf))],
    smooth_peak_nw = newWeek[which.max(replace(fit, is.na(fit), -Inf))],
    obs_peak_p     = max(p, na.rm = TRUE),
    smooth_peak_p  = max(fit, na.rm = TRUE),
    .groups = "drop"
  )

cat("\n===== Method comparison =====\n\n")
print(as.data.frame(peak_tbl))

cat("\n===== Per-season peaks (aligned space) =====\n\n")
print(as.data.frame(season_peaks))

cat("\n===== Summary =====\n")
cat(sprintf("Data median peak week (obs p):     %.1f\n", median(season_peaks$obs_peak_nw)))
cat(sprintf("Data median peak week (smooth fit): %.1f\n", median(season_peaks$smooth_peak_nw)))
cat(sprintf("Data mean peak week (obs p):        %.1f\n", mean(season_peaks$obs_peak_nw)))
cat(sprintf("Data mean peak week (smooth fit):   %.1f\n", mean(season_peaks$smooth_peak_nw)))
cat(sprintf("Data median peak p (obs):           %.4f\n", median(season_peaks$obs_peak_p)))
cat(sprintf("Data median peak p (smooth):        %.4f\n", median(season_peaks$smooth_peak_p)))
cat(sprintf("Data mean peak p (obs):             %.4f\n", mean(season_peaks$obs_peak_p)))
cat(sprintf("Data mean peak p (smooth):          %.4f\n", mean(season_peaks$smooth_peak_p)))
