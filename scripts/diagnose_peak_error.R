wf   <- readRDS("data/loso_wf_cache.rds")
allD <- read.csv("data/flu_testing_data.csv")

library(dplyr)

# True peaks
true_peaks <- allD %>%
  mutate(p = pos_flua / test_flu,
         nW = n_distinct(week[week >= 27 | week < 27]),
         weekF = ((week - 27L) %% 53L) + 1L) %>%
  filter(!is.na(p), is.finite(p), test_flu > 0) %>%
  group_by(season) %>%
  slice_max(p, n=1, with_ties=FALSE) %>%
  ungroup() %>%
  select(season, true_peak_weekF = weekF)

pdf <- wf$params_df %>%
  filter(!is.na(t_peak), !is.na(iWeek_true)) %>%
  mutate(pred_peak_weekF = round(t_peak - anchorWeek + iWeek_hat)) %>%
  left_join(true_peaks, by="season") %>%
  filter(!is.na(true_peak_weekF), eval_week <= true_peak_weekF) %>%
  mutate(
    error       = pred_peak_weekF - true_peak_weekF,   # signed
    abs_error   = abs(error),
    t           = eval_week - iWeek_true,
    t_bin       = cut(t, breaks=c(-1,2,5,10,15,100), labels=c("0-2","3-5","6-10","11-15","16+"))
  )

cat("=== Error by weeks-since-ignition ===\n")
pdf %>% group_by(t_bin) %>%
  summarise(n=n(), mae=mean(abs_error), bias=mean(error), sd=sd(error)) %>%
  print()

cat("\n=== Error by season ===\n")
pdf %>% group_by(season) %>%
  summarise(n=n(), mae=mean(abs_error), bias=mean(error)) %>%
  arrange(desc(mae)) %>% print()

cat("\n=== Ignition error contribution ===\n")
pdf %>% mutate(ign_error = iWeek_hat - iWeek_true) %>%
  summarise(
    mean_ign_error = mean(ign_error, na.rm=TRUE),
    sd_ign_error   = sd(ign_error, na.rm=TRUE),
    cor_ign_peak   = cor(ign_error, error, use="complete.obs")
  ) %>% print()
