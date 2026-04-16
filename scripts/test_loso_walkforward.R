setwd("C:/Users/lennon.li/Documents/claude/PAGe")
devtools::load_all("flualign", quiet = TRUE)

library(tidyverse)
library(MMWRweek)
library(PAGe)

# ---- rebuild alignedD -------------------------------------------------------
startWeek <- 27

n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

allD <- read.csv("data/flu_testing_data.csv") %>%
  select(season, week, year, start_year = seasonstart, date = week_start_date,
         y = pos_flua, N = test_flu) %>%
  mutate(neg = N - y, date = as.Date(date),
         mmwr_year = ifelse(week >= 35L, start_year, start_year + 1L),
         nW_true   = n_weeks_in_start_year(start_year),
         weekS     = ((week - startWeek) %% nW_true) + 1L,
         weekF     = ((week - startWeek) %% nW_true) + 1L,
         p = y / N) %>%
  filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

res_deriv <- estimateDerivs(allD, k = 10)

outs <- res_deriv$data %>%
  group_by(season) %>%
  group_split(.keep = TRUE) %>%
  purrr::map(~ flagIgnition(
    df = .x, p_thresh = 0.01, k1 = 0.4, k_c = 0.01,
    n_consec = 2, min_window = 10, w_min = 21, w_max = 21, d2_relax = -0.01
  ))

alignedD <- alignIgnition(outs) %>%
  mutate(phase = if_else(weekF < iWeek, 0L, 1L))

# ---- run walk-forward on ONE season -----------------------------------------
TEST_SEASON <- "2017-18"

wf <- loso_walkforward(
  alignedD   = alignedD,
  walk_start = 10,
  walk_end   = 30,
  test_seasons = TEST_SEASON,
  k          = 10,
  n_weeks    = 52,
  n_cores    = parallel::detectCores() - 1L,
  verbose    = TRUE
)

cat("\nparams_df:\n")
print(wf$params_df)

# ---- Plot 1: alignment params over eval_week --------------------------------
p_params <- wf$params_df %>%
  select(eval_week, tau, delta, a, b, t_peak, t_peak_lo, t_peak_hi, allow_scale) %>%
  pivot_longer(c(tau, delta, a, b, t_peak), names_to = "param", values_to = "value") %>%
  ggplot(aes(eval_week, value)) +
  geom_line(linewidth = 0.8) +
  geom_point(aes(shape = allow_scale), size = 2) +
  # peak CI ribbon (only for t_peak panel)
  geom_ribbon(
    data = ~filter(.x, param == "t_peak"),
    aes(ymin = as.numeric(NA), ymax = as.numeric(NA)),  # placeholder; added below
    alpha = 0
  ) +
  facet_wrap(~param, scales = "free_y") +
  labs(title = paste("Walk-forward alignment params —", TEST_SEASON),
       x = "Evaluation week (newWeek)", y = "Estimate",
       shape = "allow_scale") +
  theme_bw()

# add peak CI ribbon separately
p_params <- wf$params_df %>%
  ggplot(aes(eval_week)) +
  facet_wrap(~param, scales = "free_y") +
  theme_bw()

# cleaner approach: long format with CI columns kept for t_peak
params_long <- wf$params_df %>%
  select(eval_week, tau, delta, a, b, t_peak, t_peak_lo, t_peak_hi, allow_scale) %>%
  pivot_longer(c(tau, delta, a, b, t_peak), names_to = "param", values_to = "value") %>%
  left_join(
    wf$params_df %>% select(eval_week, t_peak_lo, t_peak_hi),
    by = "eval_week"
  ) %>%
  mutate(lo = if_else(param == "t_peak", t_peak_lo, NA_real_),
         hi = if_else(param == "t_peak", t_peak_hi, NA_real_))

p_params <- ggplot(params_long, aes(eval_week, value)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.25, fill = "steelblue", na.rm = TRUE) +
  geom_line(linewidth = 0.8, colour = "steelblue") +
  geom_point(aes(colour = allow_scale), size = 2) +
  scale_colour_manual(values = c("TRUE" = "steelblue", "FALSE" = "tomato")) +
  facet_wrap(~param, scales = "free_y") +
  labs(title = paste("Walk-forward alignment params —", TEST_SEASON),
       x = "Evaluation week (newWeek)", y = "Estimate",
       colour = "allow_scale") +
  theme_bw()

print(p_params)

# ---- Plot 2: forecast curves at selected eval weeks -------------------------
# actual observed data for reference
obs_s <- alignedD %>%
  filter(season == TEST_SEASON) %>%
  mutate(p_obs = y / (y + neg))

eval_show <- c(12, 15, 18, 21, 24, 27, 30)
eval_show <- eval_show[eval_show >= min(wf$forecast_df$eval_week) &
                         eval_show <= max(wf$forecast_df$eval_week)]

p_forecast <- wf$forecast_df %>%
  filter(eval_week %in% eval_show, kind == "forecast") %>%
  mutate(eval_label = paste("week", eval_week)) %>%
  ggplot(aes(newWeek, p_hat, colour = factor(eval_week), fill = factor(eval_week))) +
  geom_ribbon(aes(ymin = p_lo, ymax = p_hi), alpha = 0.15, colour = NA) +
  geom_line(linewidth = 0.7) +
  geom_vline(aes(xintercept = eval_week, colour = factor(eval_week)),
             linetype = "dashed", linewidth = 0.4) +
  geom_point(data = obs_s, aes(x = newWeek, y = p_obs),
             inherit.aes = FALSE, colour = "black", size = 1.5, alpha = 0.6) +
  labs(title = paste("Walk-forward forecasts —", TEST_SEASON),
       subtitle = "Dashed line = eval week; black dots = observed",
       x = "newWeek", y = "Predicted positivity",
       colour = "eval_week", fill = "eval_week") +
  theme_bw()

print(p_forecast)

# ---- Plot 3: tau stability (distribution across eval weeks) -----------------
p_tau <- wf$params_df %>%
  filter(!is.na(tau)) %>%
  ggplot(aes(eval_week, tau)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_ribbon(aes(ymin = tau - 2, ymax = tau + 2), alpha = 0.1, fill = "steelblue") +
  geom_line(linewidth = 1, colour = "steelblue") +
  geom_point(size = 2.5, colour = "steelblue") +
  labs(title = paste("Tau (shift) stability over walk-forward —", TEST_SEASON),
       x = "Evaluation week (newWeek)", y = "tau") +
  theme_bw()

print(p_tau)
