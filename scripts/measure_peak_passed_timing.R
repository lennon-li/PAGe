#!/usr/bin/env Rscript
# Measure the timing reliability of M1's `peak_passed` signal.
# READ-ONLY analysis: loads recorded M1 per-week states and observed
# surveillance data, then compares the first `post_peak` eval week against the
# true (raw and GAM-smoothed) observed peak week for each eligible season.
#
# Usage: Rscript scripts/measure_peak_passed_timing.R

suppressPackageStartupMessages({
  library(mgcv)
})

kit_preds <- file.path(
  "results/final-kit-2026-27",
  "20260918T1520Z-final-2026-27-wmin8-venkata",
  "artifacts/m2_tuning.rds"
)
hist_csv <- "/home/yeli/FLU/flu_testing_data_orvt_20260916.csv"

p <- readRDS(kit_preds)$m1_train_preds
p <- as.data.frame(p)
p <- p[isTRUE(TRUE) & p$forecast_available %in% TRUE, , drop = FALSE]

raw <- PAGe::load_flu_hist(hist_csv)
cal <- PAGe::page_season_calendar(
  dates = as.Date(raw$week_start_date), start_week = 27L
)
obs <- data.frame(
  season = cal$season,
  weekF = cal$weekF,
  y = as.numeric(raw$pos_flua),
  N = as.numeric(raw$test_flu)
)
obs <- obs[is.finite(obs$y) & is.finite(obs$N) & obs$N > 0, , drop = FALSE]
obs$pos <- obs$y / obs$N

seasons <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18", "2018-19",
  "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
)

true_peak <- function(d) {
  d <- d[order(d$weekF), , drop = FALSE]
  raw_pk <- d$weekF[which.max(d$pos)]
  sm_pk <- NA_real_
  if (nrow(d) >= 12) {
    fit <- try(
      mgcv::gam(cbind(y, N - y) ~ s(weekF, k = 10),
        family = binomial(), data = d
      ),
      silent = TRUE
    )
    if (!inherits(fit, "try-error")) {
      grid <- data.frame(weekF = seq(min(d$weekF), max(d$weekF), by = 0.1))
      eta <- as.numeric(predict(fit, newdata = grid))
      sm_pk <- grid$weekF[which.max(eta)]
    }
  }
  list(raw = raw_pk, smooth = sm_pk, peak_pos = max(d$pos))
}

rows <- lapply(seasons, function(s) {
  d <- obs[obs$season == s, , drop = FALSE]
  ps <- p[p$season == s, , drop = FALSE]
  tp <- true_peak(d)
  pp <- ps[ps$m1_state == "post_peak", , drop = FALSE]
  first_pp <- if (nrow(pp) == 0) NA_real_ else min(pp$eval_weekF)
  # M1 point estimate of the peak: value carried at the first post_peak week,
  # and (for reference) the estimate at the last eval week of the season.
  est_at_fire <- if (is.na(first_pp)) {
    NA_real_
  } else {
    median(pp$peak_weekF[pp$eval_weekF == first_pp], na.rm = TRUE)
  }
  est_final <- {
    lw <- max(ps$eval_weekF, na.rm = TRUE)
    median(ps$peak_weekF[ps$eval_weekF == lw], na.rm = TRUE)
  }
  # early-fire rows: labelled post_peak at an eval week strictly before the
  # true peak (both raw and smoothed references).
  n_rows <- nrow(ps)
  n_pp <- nrow(pp)
  early_raw <- sum(pp$eval_weekF < tp$raw)
  early_sm <- sum(pp$eval_weekF < tp$smooth)
  data.frame(
    season = s,
    n_weeks_obs = nrow(d),
    true_peak_raw = tp$raw,
    true_peak_smooth = round(tp$smooth, 1),
    peak_pos = round(tp$peak_pos, 3),
    first_post_peak = first_pp,
    lag_raw = first_pp - tp$raw,
    lag_smooth = round(first_pp - tp$smooth, 1),
    m1_peak_est_at_fire = round(est_at_fire, 1),
    m1_peak_est_final = round(est_final, 1),
    est_err_raw = round(est_at_fire - tp$raw, 1),
    est_err_final_raw = round(est_final - tp$raw, 1),
    n_rows = n_rows,
    n_post_peak_rows = n_pp,
    n_early_rows_raw = early_raw,
    n_early_rows_smooth = early_sm,
    stringsAsFactors = FALSE
  )
})
tab <- do.call(rbind, rows)

cat("\n=== Per-season peak_passed timing ===\n")
print(tab[, c(
  "season", "true_peak_raw", "true_peak_smooth", "first_post_peak",
  "lag_raw", "lag_smooth"
)], row.names = FALSE)

cat("\n=== Row counts ===\n")
print(tab[, c(
  "season", "n_rows", "n_post_peak_rows", "n_early_rows_raw",
  "n_early_rows_smooth"
)], row.names = FALSE)

cat("\n=== M1 peak estimate vs true peak ===\n")
print(tab[, c(
  "season", "true_peak_raw", "m1_peak_est_at_fire", "est_err_raw",
  "m1_peak_est_final", "est_err_final_raw"
)], row.names = FALSE)

lag <- tab$lag_raw
lags <- tab$lag_smooth
cat("\n=== Lag distribution (weeks; negative = fired EARLY) ===\n")
cat(sprintf(
  "vs raw peak    : early=%d on-time=%d late=%d | median=%s range=[%s, %s]\n",
  sum(lag < 0, na.rm = TRUE), sum(lag == 0, na.rm = TRUE),
  sum(lag > 0, na.rm = TRUE), median(lag, na.rm = TRUE),
  min(lag, na.rm = TRUE), max(lag, na.rm = TRUE)
))
cat(sprintf(
  "vs smooth peak : early=%d on-time=%d late=%d | median=%s range=[%s, %s]\n",
  sum(lags < 0, na.rm = TRUE), sum(lags == 0, na.rm = TRUE),
  sum(lags > 0, na.rm = TRUE), median(lags, na.rm = TRUE),
  min(lags, na.rm = TRUE), max(lags, na.rm = TRUE)
))
cat(sprintf("seasons never firing post_peak: %d\n", sum(is.na(lag))))

cat("\n=== Early-fire exposure (rows the proposed fix would harm) ===\n")
cat(sprintf(
  "total rows=%d, post_peak rows=%d, early rows (raw peak)=%d, early rows (smooth peak)=%d\n",
  sum(tab$n_rows), sum(tab$n_post_peak_rows),
  sum(tab$n_early_rows_raw), sum(tab$n_early_rows_smooth)
))

cat("\n=== M1 peak-estimate bias summary (est - true raw peak) ===\n")
cat(sprintf(
  "at-fire: median=%s mean=%s range=[%s, %s]\n",
  median(tab$est_err_raw, na.rm = TRUE),
  round(mean(tab$est_err_raw, na.rm = TRUE), 2),
  min(tab$est_err_raw, na.rm = TRUE), max(tab$est_err_raw, na.rm = TRUE)
))
cat(sprintf(
  "final  : median=%s mean=%s range=[%s, %s]\n",
  median(tab$est_err_final_raw, na.rm = TRUE),
  round(mean(tab$est_err_final_raw, na.rm = TRUE), 2),
  min(tab$est_err_final_raw, na.rm = TRUE),
  max(tab$est_err_final_raw, na.rm = TRUE)
))

# --- Counterfactual: would a "k consecutive declining weeks" trigger be safer?
cat("\n=== Counterfactual triggers (first eval week satisfying rule) ===\n")
cf <- lapply(seasons, function(s) {
  d <- obs[obs$season == s, , drop = FALSE]
  d <- d[order(d$weekF), , drop = FALSE]
  ps <- p[p$season == s, , drop = FALSE]
  evals <- sort(unique(ps$eval_weekF))
  tp <- true_peak(d)
  fire_decl <- function(k) {
    for (w in evals) {
      h <- d$pos[d$weekF <= w]
      if (length(h) < k + 1) next
      tail_h <- utils::tail(h, k + 1)
      if (all(diff(tail_h) < 0)) return(w)
    }
    NA_real_
  }
  fire_margin <- function(frac) {
    for (w in evals) {
      h <- d$pos[d$weekF <= w]
      if (length(h) < 3) next
      if (utils::tail(h, 1) <= (1 - frac) * max(h)) return(w)
    }
    NA_real_
  }
  data.frame(
    season = s, true_peak_raw = tp$raw,
    decl2 = fire_decl(2), decl3 = fire_decl(3),
    margin20 = fire_margin(0.20), margin30 = fire_margin(0.30),
    stringsAsFactors = FALSE
  )
})
cf <- do.call(rbind, cf)
cf$lag_decl2 <- cf$decl2 - cf$true_peak_raw
cf$lag_decl3 <- cf$decl3 - cf$true_peak_raw
cf$lag_margin20 <- cf$margin20 - cf$true_peak_raw
cf$lag_margin30 <- cf$margin30 - cf$true_peak_raw
print(cf, row.names = FALSE)

saveRDS(
  list(timing = tab, counterfactual = cf),
  file.path(
    Sys.getenv("PAGE_SCRATCH", tempdir()), "peak_passed_timing.rds"
  )
)
invisible(NULL)
