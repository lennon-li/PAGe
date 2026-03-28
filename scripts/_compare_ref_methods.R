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

ex <- c("2011-12", "2020-21", "2021-22", "2025-26")
cat("\n===== Reference curve comparison =====\n\n")

for (m in c("binomial", "binomial_weighted", "gaussian_logit", "median_smooth")) {
  kk <- if (m %in% c("binomial", "binomial_weighted")) 30 else 20
  r <- estimateRef(alignedD, exSeason = ex, k = kk, method = m,
                   peak_weight_boost = 3, trough_weight = 0.1)
  pk <- r$pred_df$newWeek[which.max(r$pred_df$fit)]
  pkv <- round(max(r$pred_df$fit), 4)
  stbl <- summary(r$mod2$gam)$s.table
  nw_row <- grep("newWeek", rownames(stbl))
  edf_val <- if (length(nw_row)) round(stbl[nw_row[1], "edf"], 1) else round(sum(r$mod2$gam$edf), 1)
  cat(sprintf("%-25s  k=%2d  edf=%5.1f  peak_week=%2d  peak_p=%.4f\n", m, kk, edf_val, pk, pkv))
}
