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

anchorWeek <- attr(alignedD, "anchorWeek")

cat("\n===== Per-season peak weeks (newWeek space) =====\n\n")

peaks <- alignedD %>%
  group_by(season) %>%
  summarise(
    obs_peak_nw    = newWeek[which.max(replace(p,   is.na(p),   -Inf))],
    smooth_peak_nw = newWeek[which.max(replace(fit, is.na(fit), -Inf))],
    .groups = "drop"
  )

print(as.data.frame(peaks))

cat("\n===== Summary statistics =====\n")
cat(sprintf("Anchor week: %d\n", anchorWeek))
cat(sprintf("Observed peak  — mean: %.1f, median: %.1f, sd: %.1f\n",
            mean(peaks$obs_peak_nw), median(peaks$obs_peak_nw), sd(peaks$obs_peak_nw)))
cat(sprintf("Smoothed peak  — mean: %.1f, median: %.1f, sd: %.1f\n",
            mean(peaks$smooth_peak_nw), median(peaks$smooth_peak_nw), sd(peaks$smooth_peak_nw)))

cat("\n===== Per-season peak weeks (weekF space, pre-alignment) =====\n\n")

peaks_wf <- alignedD %>%
  group_by(season) %>%
  summarise(
    obs_peak_wf    = weekF[which.max(replace(p,   is.na(p),   -Inf))],
    smooth_peak_wf = weekF[which.max(replace(fit, is.na(fit), -Inf))],
    iWeek = iWeek[1],
    .groups = "drop"
  )

print(as.data.frame(peaks_wf))

cat(sprintf("\nObs peak weekF    — mean: %.1f, median: %.1f\n",
            mean(peaks_wf$obs_peak_wf), median(peaks_wf$obs_peak_wf)))
cat(sprintf("Smooth peak weekF — mean: %.1f, median: %.1f\n",
            mean(peaks_wf$smooth_peak_wf), median(peaks_wf$smooth_peak_wf)))
