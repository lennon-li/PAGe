#!/usr/bin/env Rscript
# TASK B diagnostic: is M1's `peak_passed` gate reliable enough to switch the
# point forecast to an observed-data GAM?
#
# READ-ONLY: loads recorded M1 per-week states plus observed surveillance and
# compares the first `post_peak` eval week against the true (raw and
# GAM-smoothed) observed peak week for each eligible season.
#
# See results/m1-diagnosis/briefs/TASK_B.md.
# Usage: Rscript scripts/diag_peak_passed_timing.R

suppressPackageStartupMessages({
  library(mgcv)
})

kit_preds <- file.path(
  "results/final-kit-2026-27",
  "20260918T1520Z-final-2026-27-wmin8-venkata",
  "artifacts/m2_tuning.rds"
)
hist_csv <- "/home/yeli/FLU/flu_testing_data_orvt_20260916.csv"
out_dir <- "results/m1-diagnosis"
out_csv <- file.path(out_dir, "task_b_seasons.csv")
out_trig_csv <- file.path(out_dir, "task_b_triggers.csv")

seasons <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18", "2018-19",
  "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
)

# --- Recorded M1 state per forecast origin ---------------------------------
preds <- as.data.frame(readRDS(kit_preds)$m1_train_preds)
preds <- preds[preds$forecast_available %in% TRUE, , drop = FALSE]

# --- Observed data on the weekF scale --------------------------------------
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

# --- True peak references ---------------------------------------------------
true_peak <- function(d) {
  d <- d[order(d$weekF), , drop = FALSE]
  raw_pk <- d$weekF[which.max(d$pos)]
  sm_pk <- NA_real_
  sm_val <- NA_real_
  if (nrow(d) >= 12 && length(unique(d$weekF)) >= 6) {
    fit <- try(
      mgcv::gam(cbind(y, N - y) ~ s(weekF, k = 10),
        family = binomial(), data = d
      ),
      silent = TRUE
    )
    if (!inherits(fit, "try-error")) {
      grid <- data.frame(weekF = seq(min(d$weekF), max(d$weekF), by = 0.1))
      eta <- as.numeric(predict(fit, newdata = grid))
      if (any(is.finite(eta))) {
        sm_pk <- grid$weekF[which.max(eta)]
        sm_val <- stats::plogis(max(eta, na.rm = TRUE))
      }
    }
  }
  list(raw = raw_pk, smooth = sm_pk, peak_pos = max(d$pos), smooth_pos = sm_val)
}

# --- Counterfactual "safer trigger" helpers ---------------------------------
first_declining <- function(d, w_all, k) {
  for (w in w_all) {
    h <- d$pos[d$weekF <= w]
    if (length(h) < k + 1L) next
    if (all(diff(utils::tail(h, k + 1L)) < 0)) {
      return(w)
    }
  }
  NA_real_
}
first_margin <- function(d, w_all, frac, min_vals = 3L) {
  for (w in w_all) {
    h <- d$pos[d$weekF <= w]
    if (length(h) < min_vals) next
    if (utils::tail(h, 1) <= (1 - frac) * max(h)) {
      return(w)
    }
  }
  NA_real_
}
first_pp_buffer <- function(ps, w_all, b) {
  for (w in w_all) {
    hi <- ps$peak_weekF_hi[ps$eval_weekF == w]
    if (length(hi) == 0L) next
    if (w >= max(hi, na.rm = TRUE) + b) {
      return(w)
    }
  }
  NA_real_
}
# peak_passed AND k consecutive declining observed weeks.
first_pp_and_decl <- function(ps, d, k) {
  w_all <- sort(unique(ps$eval_weekF))
  for (w in w_all) {
    st <- unique(ps$m1_state[ps$eval_weekF == w])[1]
    if (!identical(st, "post_peak")) next
    h <- d$pos[d$weekF <= w]
    if (length(h) >= k + 1L && all(diff(utils::tail(h, k + 1L)) < 0)) {
      return(w)
    }
  }
  NA_real_
}
# Persistence: require peak_passed to hold for k consecutive recorded origins.
first_persist <- function(ps, k) {
  w_all <- sort(unique(ps$eval_weekF))
  st <- vapply(w_all, function(w) {
    unique(ps$m1_state[ps$eval_weekF == w])[1]
  }, character(1))
  for (i in seq_along(w_all)) {
    if (i < k) next
    if (all(st[(i - k + 1L):i] == "post_peak")) {
      return(w_all[i])
    }
  }
  NA_real_
}

# --- Per-season assembly ----------------------------------------------------
rows <- lapply(seasons, function(s) {
  d <- obs[obs$season == s, , drop = FALSE]
  ps <- preds[preds$season == s, , drop = FALSE]
  tp <- true_peak(d)

  pp <- ps[ps$m1_state == "post_peak", , drop = FALSE]
  first_pp <- if (nrow(pp) == 0L) NA_real_ else min(pp$eval_weekF)
  last_eval <- max(ps$eval_weekF, na.rm = TRUE)

  m1_at_fire <- if (is.na(first_pp)) {
    NA_real_
  } else {
    stats::median(pp$peak_weekF[pp$eval_weekF == first_pp], na.rm = TRUE)
  }
  m1_final <- stats::median(
    ps$peak_weekF[ps$eval_weekF == last_eval],
    na.rm = TRUE
  )

  data.frame(
    season = s,
    n_obs_weeks = nrow(d),
    true_peak_raw = tp$raw,
    true_peak_smooth = round(tp$smooth, 1),
    peak_pos = round(tp$peak_pos, 4),
    smooth_peak_pos = round(tp$smooth_pos, 4),
    first_post_peak = first_pp,
    lag_raw = first_pp - tp$raw,
    lag_smooth = round(first_pp - tp$smooth, 1),
    m1_peak_at_fire = round(m1_at_fire, 1),
    m1_peak_final = round(m1_final, 1),
    m1_peak_err_at_fire = round(m1_at_fire - tp$raw, 1),
    m1_peak_err_final = round(m1_final - tp$raw, 1),
    n_forecast_rows = nrow(ps),
    n_post_peak_rows = nrow(pp),
    n_early_rows_raw = sum(pp$eval_weekF < tp$raw),
    n_early_rows_smooth = sum(pp$eval_weekF < tp$smooth),
    stringsAsFactors = FALSE
  )
})
tab <- do.call(rbind, rows)

# --- Counterfactual trigger table ------------------------------------------
trig <- lapply(seasons, function(s) {
  d <- obs[obs$season == s, , drop = FALSE]
  d <- d[order(d$weekF), , drop = FALSE]
  ps <- preds[preds$season == s, , drop = FALSE]
  w_all <- sort(unique(ps$eval_weekF))
  tp <- true_peak(d)
  fire <- c(
    decl2 = first_declining(d, w_all, 2L),
    decl3 = first_declining(d, w_all, 3L),
    margin20 = first_margin(d, w_all, 0.20),
    margin30 = first_margin(d, w_all, 0.30),
    pp_buffer1 = first_pp_buffer(ps, w_all, 1L),
    pp_buffer2 = first_pp_buffer(ps, w_all, 2L),
    persist2 = first_persist(ps, 2L),
    persist3 = first_persist(ps, 3L),
    pp_decl2 = first_pp_and_decl(ps, d, 2L),
    pp_decl3 = first_pp_and_decl(ps, d, 3L)
  )
  data.frame(
    season = s,
    true_peak_raw = tp$raw,
    true_peak_smooth = round(tp$smooth, 1),
    as.list(fire),
    stringsAsFactors = FALSE,
    row.names = NULL,
    check.names = FALSE
  )
})
trig <- do.call(rbind, trig)
names(trig) <- c(
  "season", "true_peak_raw", "true_peak_smooth",
  "fire_decl2", "fire_decl3", "fire_margin20", "fire_margin30",
  "fire_pp_buffer1", "fire_pp_buffer2", "fire_persist2", "fire_persist3",
  "fire_pp_decl2", "fire_pp_decl3"
)
for (nm in c(
  "decl2", "decl3", "margin20", "margin30", "pp_buffer1", "pp_buffer2",
  "persist2", "persist3", "pp_decl2", "pp_decl3"
)) {
  col_fire <- paste0("fire_", nm)
  trig[[paste0("lag_", nm, "_raw")]] <- trig[[col_fire]] - trig$true_peak_raw
  trig[[paste0("lag_", nm, "_smooth")]] <-
    round(trig[[col_fire]] - trig$true_peak_smooth, 1)
}

# --- Console summary --------------------------------------------------------
cat("\n=== Per-season peak_passed timing (lag = first post_peak - true peak) ===\n")
print(tab[, c(
  "season", "true_peak_raw", "true_peak_smooth", "first_post_peak",
  "lag_raw", "lag_smooth"
)], row.names = FALSE)

summ_lag <- function(x, label) {
  ok <- is.finite(x)
  cat(sprintf(
    "%s: early=%d on-time=%d late=%d never=%d | median=%s range=[%s, %s]\n",
    label, sum(x < 0, na.rm = TRUE), sum(x == 0, na.rm = TRUE),
    sum(x > 0, na.rm = TRUE), sum(!ok),
    ifelse(any(ok), as.character(stats::median(x, na.rm = TRUE)), "NA"),
    ifelse(any(ok), min(x, na.rm = TRUE), "NA"),
    ifelse(any(ok), max(x, na.rm = TRUE), "NA")
  ))
}
cat("\n=== Lag distribution (negative = fired EARLY) ===\n")
summ_lag(tab$lag_raw, "vs raw peak   ")
summ_lag(tab$lag_smooth, "vs smooth peak")

cat("\n=== Early-fire exposure (rows harmed by the proposed switch) ===\n")
cat(sprintf(
  "total forecast rows=%d | post_peak rows=%d (%.1f%%)\n",
  sum(tab$n_forecast_rows), sum(tab$n_post_peak_rows),
  100 * sum(tab$n_post_peak_rows) / sum(tab$n_forecast_rows)
))
cat(sprintf(
  "early rows (before true raw peak)    = %d (%.1f%% of all rows)\n",
  sum(tab$n_early_rows_raw),
  100 * sum(tab$n_early_rows_raw) / sum(tab$n_forecast_rows)
))
cat(sprintf(
  "early rows (before true smooth peak) = %d (%.1f%% of all rows)\n",
  sum(tab$n_early_rows_smooth),
  100 * sum(tab$n_early_rows_smooth) / sum(tab$n_forecast_rows)
))

cat("\n=== M1 peak-estimate bias (M1 peak_weekF - true raw peak) ===\n")
cat(sprintf(
  "at first fire: median=%.1f mean=%.2f range=[%.1f, %.1f]\n",
  stats::median(tab$m1_peak_err_at_fire, na.rm = TRUE),
  mean(tab$m1_peak_err_at_fire, na.rm = TRUE),
  min(tab$m1_peak_err_at_fire, na.rm = TRUE),
  max(tab$m1_peak_err_at_fire, na.rm = TRUE)
))
cat(sprintf(
  "at last eval : median=%.1f mean=%.2f range=[%.1f, %.1f]\n",
  stats::median(tab$m1_peak_err_final, na.rm = TRUE),
  mean(tab$m1_peak_err_final, na.rm = TRUE),
  min(tab$m1_peak_err_final, na.rm = TRUE),
  max(tab$m1_peak_err_final, na.rm = TRUE)
))

cat("\n=== Counterfactual safer triggers (first-fire week) ===\n")
print(trig[, c(
  "season", "true_peak_raw", "fire_decl2", "fire_decl3",
  "fire_margin20", "fire_margin30", "fire_pp_buffer1", "fire_pp_buffer2",
  "fire_persist2", "fire_persist3", "fire_pp_decl2", "fire_pp_decl3"
)], row.names = FALSE)

cat("\n=== Counterfactual trigger lags vs raw peak (negative = early) ===\n")
for (nm in c(
  "decl2", "decl3", "margin20", "margin30", "pp_buffer1", "pp_buffer2",
  "persist2", "persist3", "pp_decl2", "pp_decl3"
)) {
  x <- trig[[paste0("lag_", nm, "_raw")]]
  cat(sprintf(
    "%-10s: early=%d on-time=%d late=%d never=%d | median=%s range=[%s, %s]\n",
    nm, sum(x < 0, na.rm = TRUE), sum(x == 0, na.rm = TRUE),
    sum(x > 0, na.rm = TRUE), sum(is.na(x)),
    ifelse(any(is.finite(x)), as.character(stats::median(x, na.rm = TRUE)), "NA"),
    ifelse(any(is.finite(x)), min(x, na.rm = TRUE), "NA"),
    ifelse(any(is.finite(x)), max(x, na.rm = TRUE), "NA")
  ))
}

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
utils::write.csv(tab, out_csv, row.names = FALSE)
utils::write.csv(trig, out_trig_csv, row.names = FALSE)
cat(sprintf("\nwrote %s\nwrote %s\n", out_csv, out_trig_csv))
