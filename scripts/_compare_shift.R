library(dplyr)
wf <- readRDS("../data/loso_wf_cache.rds")
allD <- read.csv("../data/flu_testing_data.csv") %>%
  mutate(p=pos_flua/test_flu, N=test_flu,
         nW=ifelse(seasonstart %in% c(2015,2020),53,52),
         weekF=((week-27)%%nW)+1L) %>%
  filter(!season %in% c("2011-12","2015-16","2020-21","2021-22","2025-26"))
true_peaks <- allD %>% filter(!is.na(p),is.finite(p),N>0) %>%
  group_by(season) %>% slice_max(p,n=1,with_ties=FALSE) %>% ungroup() %>%
  select(season, true_peak_weekF=weekF)
fp <- wf$params_df %>% filter(!is.na(iWeek_hat)) %>%
  group_by(season) %>% slice_max(eval_week,n=1,with_ties=FALSE) %>% ungroup() %>%
  left_join(true_peaks,by="season") %>%
  mutate(err_shift1 = peak_weekF - true_peak_weekF,
         err_shift0 = (peak_weekF - 1L) - true_peak_weekF)
cat("shift=0  MAE:", round(mean(abs(fp$err_shift0),na.rm=TRUE),2),
    " | mean:", round(mean(fp$err_shift0,na.rm=TRUE),2), "\n")
cat("shift=1  MAE:", round(mean(abs(fp$err_shift1),na.rm=TRUE),2),
    " | mean:", round(mean(fp$err_shift1,na.rm=TRUE),2), "\n")
