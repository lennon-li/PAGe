source("R/utils.R")
source("R/pipeline_runtime_helpers.R")
source("R/m0_runtime.R")
source("R/m2_runtime.R")
source("R/pipeline_runtime.R")
source("R/m1_runtime.R")

library(dplyr)

allD <- read.csv("data/flu_testing_data.csv") %>%
  mutate(p = pos_flua / test_flu, N = test_flu,
         weekF = ((week - 27L) %% 53L) + 1L)

wf  <- readRDS("data/loso_wf_cache.rds")
cal <- fit_peak_calibration(wf$params_df, allD)

cat(sprintf("Prior: mu_prior = %.2f newWeeks, sigma_prior = %.2f weeks\n\n",
            cal$mu_prior, cal$sigma_prior))

cd <- cal$cal_df %>%
  mutate(
    bias_raw    = pred_peak_weekF - true_peak_weekF,
    bias_shrunk = pred_post_weekF - true_peak_weekF,
    bias_final  = pred_post_weekF - true_peak_weekF - fitted(cal$bias_gam)
  )

cat("=== MAE by stage ===\n")
cat(sprintf("Raw:                    MAE = %.3f, bias = %.3f\n",
            mean(abs(cd$bias_raw)),    mean(cd$bias_raw)))
cat(sprintf("After shrinkage:        MAE = %.3f, bias = %.3f\n",
            mean(abs(cd$bias_shrunk)), mean(cd$bias_shrunk)))
cat(sprintf("After shrinkage + GAM:  MAE = %.3f, bias = %.3f\n",
            mean(abs(cd$bias_final)),  mean(cd$bias_final)))

cat("\n=== MAE by season (final) ===\n")
cd %>%
  group_by(season) %>%
  summarise(
    mae_raw   = round(mean(abs(bias_raw)),    2),
    mae_final = round(mean(abs(bias_final)),  2),
    improvement = round(mae_raw - mae_final, 2)
  ) %>%
  arrange(desc(mae_raw)) %>%
  print()

cat("\n=== Shrinkage: mean weight by t_bin ===\n")
cd %>%
  mutate(t_bin = cut(t_since_ign, c(-1,2,5,10,15,100),
                     labels=c("0-2","3-5","6-10","11-15","16+"))) %>%
  group_by(t_bin) %>%
  summarise(mean_shrinkage = round(mean(shrinkage), 3),
            mae_raw = round(mean(abs(bias_raw)), 2),
            mae_final = round(mean(abs(bias_final)), 2)) %>%
  print()

cat("\n=== k_ref results ===\n")
k <- readRDS("data/k_ref_tuning.rds")
print(k)
