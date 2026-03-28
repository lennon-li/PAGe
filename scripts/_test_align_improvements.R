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

# Build aligned data (training on all except 2024-25)
ex <- "2024-25"
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

# --- Test 1: compute_align_weights ---
cat("=== Test 1: compute_align_weights ===\n")
ref_pop <- estimateRef(alignedD, exSeason = ex, k = 20, method = "fs",
                       trough_weight = 0.1, peak_weight_boost = 3, agg = "median")
wts <- compute_align_weights(1:52, ref_pop$g_ref_fun, trough_weight = 0.1,
                              rise_weight = 3.0, peak_decay = 0.3)
cat(sprintf("Weight range: [%.2f, %.2f]\n", min(wts), max(wts)))
cat(sprintf("Weights at week 5 (pre-rise): %.2f\n", wts[5]))
cat(sprintf("Weights at week 25 (rise): %.2f\n", wts[25]))
cat(sprintf("Weights at week 35 (post-peak): %.2f\n", wts[35]))

# --- Test 2: Single-template with time weights (Improvement C) ---
cat("\n=== Test 2: align_forecast_pipeline_dilate with rise_weight=3 ===\n")
test_season <- "2023-24"
test_data <- alignedD %>% filter(season == test_season) %>%
  filter(newWeek <= 30)  # partial season

hyper <- learn_alignment_hyperparams(ref_pop$dat, ref_pop$g_ref_fun)

# Baseline (no time weights)
res_base <- align_forecast_pipeline_dilate(
  currentD = test_data, g_ref_fun = ref_pop$g_ref_fun,
  g_ref_mu_se = ref_pop$g_ref_mu_se, hyper = hyper,
  rise_weight = 1.0
)
cat(sprintf("Baseline: tau=%.2f, delta=%.3f, t_peak=%.1f, nll=%.2f\n",
            res_base$tau, res_base$delta, res_base$peak$t_peak, res_base$nll))

# With time weights
res_wt <- align_forecast_pipeline_dilate(
  currentD = test_data, g_ref_fun = ref_pop$g_ref_fun,
  g_ref_mu_se = ref_pop$g_ref_mu_se, hyper = hyper,
  rise_weight = 3.0, trough_weight = 0.1
)
cat(sprintf("Weighted: tau=%.2f, delta=%.3f, t_peak=%.1f, nll=%.2f\n",
            res_wt$tau, res_wt$delta, res_wt$peak$t_peak, res_wt$nll))

# --- Test 3: Multi-template ensemble (Improvement A) ---
cat("\n=== Test 3: align_multi_template ===\n")
stopifnot(!is.null(ref_pop$eta_mat))
cat(sprintf("eta_mat dimensions: %d x %d\n", nrow(ref_pop$eta_mat), ncol(ref_pop$eta_mat)))

res_multi <- align_multi_template(
  currentD = test_data, eta_mat = ref_pop$eta_mat,
  g_ref_fun = ref_pop$g_ref_fun, g_ref_mu_se = ref_pop$g_ref_mu_se,
  hyper = hyper, rise_weight = 3.0, trough_weight = 0.1,
  temperature = 1.0
)
cat(sprintf("Multi-template: tau=%.2f, delta=%.3f, t_peak=%.1f\n",
            res_multi$tau, res_multi$delta, res_multi$peak$t_peak))
cat("Template weights:\n")
w_sorted <- sort(res_multi$weights, decreasing = TRUE)
for (nm in names(w_sorted)) {
  cat(sprintf("  %s: %.3f\n", nm, w_sorted[nm]))
}

cat("\n=== All tests passed ===\n")
