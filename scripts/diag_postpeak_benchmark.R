#!/usr/bin/env Rscript
# TASK A: benchmark PAGe:::forecast_post_peak_gam() against M1 as a 1-2 week
# ahead forecaster across the 11 eligible seasons. DIAGNOSIS ONLY.
# Run from the repository root: Rscript scripts/diag_postpeak_benchmark.R

suppressPackageStartupMessages({
  library(PAGe)
})

csv_path <- "/home/yeli/FLU/flu_testing_data_orvt_20260916.csv"
kit_dir <- "results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/artifacts"
out_rows <- "results/m1-diagnosis/task_a_rows.csv"
out_summary <- "results/m1-diagnosis/task_a_metrics.rds"

eligible <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18", "2018-19",
  "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
)
min_obs_weeks <- 10L
implaus_hi <- 0.40
observed_max <- 0.362

stopifnot(file.exists(csv_path), dir.exists(kit_dir))

# ---- observed data ----
raw <- PAGe::load_flu_hist(csv_path)
cal <- PAGe::page_season_calendar(dates = as.Date(raw$week_start_date), start_week = 27L)
obs <- data.frame(
  season = cal$season,
  weekF = as.integer(cal$weekF),
  y = as.numeric(raw$pos_flua),
  N = as.numeric(raw$test_flu),
  stringsAsFactors = FALSE
)
obs <- obs[is.finite(obs$y) & is.finite(obs$N) & obs$N > 0, ]
obs$neg <- obs$N - obs$y
obs$p <- obs$y / obs$N
obs <- obs[obs$season %in% eligible, ]
obs$key <- paste(obs$season, obs$weekF, sep = "|")

observed_max <- max(observed_max, max(obs$p, na.rm = TRUE))

# ---- frozen template + M1 recorded predictions ----
f <- readRDS(file.path(kit_dir, "m1_frozen.rds"))
g_ref_fun <- f$ref$g_ref_fun

t <- readRDS(file.path(kit_dir, "m2_tuning.rds"))
mp <- as.data.frame(t$m1_train_preds)
mp <- mp[mp$season %in% eligible, ]

origins <- unique(mp[, c("season", "eval_weekF")])
origins$n_obs_weeks <- mapply(
  function(s, w) sum(obs$season == s & obs$weekF <= w),
  origins$season, origins$eval_weekF
)
n_orig_pre <- nrow(origins)
origins <- origins[origins$n_obs_weeks >= min_obs_weeks, ]
origins$origin_key <- paste(origins$season, origins$eval_weekF, sep = "|")

# ---- fit forecast_post_peak_gam at each origin, both variants ----
run_variant <- function(currentSeason, g_fun, max_newWeek) {
  warns <- character(0)
  res <- tryCatch(
    withCallingHandlers(
      PAGe:::forecast_post_peak_gam(
        currentSeason,
        g_ref_fun = g_fun,
        max_newWeek = max_newWeek
      ),
      warning = function(w) {
        warns <<- c(warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) e
  )
  if (inherits(res, "error")) {
    return(list(status = "error", error = conditionMessage(res), warns = unique(warns), pred_df = NULL))
  }
  list(status = "ok", error = NA_character_, warns = unique(warns), pred_df = res$pred_df)
}

fit_origin <- function(season, eval_weekF) {
  cs <- obs[obs$season == season & obs$weekF <= eval_weekF, ]
  cs <- data.frame(newWeek = as.integer(cs$weekF), y = cs$y, neg = cs$neg)
  max_newWeek <- as.integer(eval_weekF + max(mp$h, na.rm = TRUE))
  list(
    no = run_variant(cs, NULL, max_newWeek),
    tpl = run_variant(cs, g_ref_fun, max_newWeek)
  )
}

cat(sprintf(
  "Fitting forecast_post_peak_gam at %d origins (>= %d observed weeks; %d before filter)...\n",
  nrow(origins), min_obs_weeks, n_orig_pre
))
fits <- lapply(seq_len(nrow(origins)), function(i) {
  fit_origin(origins$season[i], origins$eval_weekF[i])
})
names(fits) <- origins$origin_key

pull_pred <- function(variant, target_weekF) {
  if (is.null(variant)) {
    return(list(p = NA_real_, lo = NA_real_, hi = NA_real_, status = "no_origin_fit", in_grid = NA))
  }
  if (identical(variant$status, "error")) {
    return(list(p = NA_real_, lo = NA_real_, hi = NA_real_, status = "error", in_grid = NA))
  }
  df <- variant$pred_df
  idx <- match(target_weekF, df$newWeek)
  if (is.na(idx)) {
    return(list(p = NA_real_, lo = NA_real_, hi = NA_real_, status = "target_not_in_grid", in_grid = FALSE))
  }
  list(p = df$p_hat[idx], lo = df$p_lo[idx], hi = df$p_hi[idx], status = "ok", in_grid = TRUE)
}

n_mp <- nrow(mp)
rows <- data.frame(
  season = mp$season,
  eval_weekF = as.integer(mp$eval_weekF),
  target_weekF = as.integer(mp$target_weekF),
  h = as.integer(mp$h),
  m1_state = as.character(mp$m1_state),
  m1_forecast_available = as.logical(mp$forecast_available),
  m1_unavailable_reason = as.character(mp$unavailable_reason),
  m1_p_hat = as.numeric(mp$m1_p_hat),
  gam_no_p_hat = NA_real_,
  gam_no_p_lo = NA_real_,
  gam_no_p_hi = NA_real_,
  gam_tpl_p_hat = NA_real_,
  gam_tpl_p_lo = NA_real_,
  gam_tpl_p_hi = NA_real_,
  gam_no_status = NA_character_,
  gam_tpl_status = NA_character_,
  actual_p = NA_real_,
  actual_y = NA_real_,
  actual_N = NA_real_,
  stringsAsFactors = FALSE
)

for (i in seq_len(n_mp)) {
  key <- paste(mp$season[i], mp$eval_weekF[i], sep = "|")
  ft <- fits[[key]]
  target <- as.integer(mp$target_weekF[i])
  en <- pull_pred(if (is.null(ft)) NULL else ft$no, target)
  et <- pull_pred(if (is.null(ft)) NULL else ft$tpl, target)
  rows$gam_no_p_hat[i] <- en$p
  rows$gam_no_p_lo[i] <- en$lo
  rows$gam_no_p_hi[i] <- en$hi
  rows$gam_no_status[i] <- en$status
  rows$gam_tpl_p_hat[i] <- et$p
  rows$gam_tpl_p_lo[i] <- et$lo
  rows$gam_tpl_p_hi[i] <- et$hi
  rows$gam_tpl_status[i] <- et$status
  j <- match(paste(mp$season[i], target, sep = "|"), obs$key)
  if (!is.na(j)) {
    rows$actual_p[i] <- obs$p[j]
    rows$actual_y[i] <- obs$y[j]
    rows$actual_N[i] <- obs$N[j]
  }
}

rows$m1_err_pp <- abs(rows$m1_p_hat - rows$actual_p) * 100
rows$gam_no_err_pp <- abs(rows$gam_no_p_hat - rows$actual_p) * 100
rows$gam_tpl_err_pp <- abs(rows$gam_tpl_p_hat - rows$actual_p) * 100

write.csv(rows, out_rows, row.names = FALSE)
cat("Wrote", out_rows, "with", nrow(rows), "rows\n\n")

# ---- metrics ----
mae <- function(x, y) {
  ok <- is.finite(x) & is.finite(y)
  if (!any(ok)) {
    return(NA_real_)
  }
  mean(abs(x[ok] - y[ok])) * 100
}

methods <- c("M1", "GAM_no_template", "GAM_with_template")
method_cols <- c("m1_p_hat", "gam_no_p_hat", "gam_tpl_p_hat")

overall <- data.frame(
  method = methods,
  n_forecast = vapply(method_cols, function(cc) sum(is.finite(rows[[cc]])), integer(1)),
  mae_pp_all_rows = vapply(method_cols, function(cc) mae(rows[[cc]], rows$actual_p), numeric(1)),
  mae_pp_post_peak = vapply(method_cols, function(cc) {
    s <- rows$m1_state == "post_peak"
    mae(rows[[cc]][s], rows$actual_p[s])
  }, numeric(1)),
  mae_pp_aligning = vapply(method_cols, function(cc) {
    s <- rows$m1_state == "aligning"
    mae(rows[[cc]][s], rows$actual_p[s])
  }, numeric(1)),
  stringsAsFactors = FALSE
)

per_season_post <- do.call(rbind, lapply(eligible, function(s) {
  ss <- rows$m1_state == "post_peak" & rows$season == s
  data.frame(
    season = s,
    n_rows = sum(ss),
    M1 = mae(rows$m1_p_hat[ss], rows$actual_p[ss]),
    GAM_no_template = mae(rows$gam_no_p_hat[ss], rows$actual_p[ss]),
    GAM_with_template = mae(rows$gam_tpl_p_hat[ss], rows$actual_p[ss]),
    stringsAsFactors = FALSE
  )
}))

per_horizon <- do.call(rbind, lapply(c(1L, 2L), function(hh) {
  s <- rows$h == hh
  data.frame(
    h = hh,
    n_rows = sum(s),
    M1 = mae(rows$m1_p_hat[s], rows$actual_p[s]),
    GAM_no_template = mae(rows$gam_no_p_hat[s], rows$actual_p[s]),
    GAM_with_template = mae(rows$gam_tpl_p_hat[s], rows$actual_p[s]),
    stringsAsFactors = FALSE
  )
}))

per_season_state <- do.call(rbind, lapply(eligible, function(s) {
  ss <- rows$m1_state == "aligning" & rows$season == s
  if (!any(ss)) {
    return(NULL)
  }
  data.frame(
    season = s,
    n_rows = sum(ss),
    M1 = mae(rows$m1_p_hat[ss], rows$actual_p[ss]),
    GAM_no_template = mae(rows$gam_no_p_hat[ss], rows$actual_p[ss]),
    GAM_with_template = mae(rows$gam_tpl_p_hat[ss], rows$actual_p[ss]),
    stringsAsFactors = FALSE
  )
}))

win_rate <- function(col, subset) {
  ok <- subset & is.finite(rows[[col]]) & is.finite(rows$m1_p_hat) & is.finite(rows$actual_p)
  if (!any(ok)) {
    return(c(n = 0, win = NA_real_, tie = NA_real_))
  }
  ga <- abs(rows[[col]][ok] - rows$actual_p[ok])
  ma <- abs(rows$m1_p_hat[ok] - rows$actual_p[ok])
  c(n = sum(ok), win = mean(ga < ma), tie = mean(ga == ma))
}

state_subsets <- list(
  all = rep(TRUE, nrow(rows)),
  post_peak = rows$m1_state == "post_peak",
  aligning = rows$m1_state == "aligning",
  h1 = rows$h == 1L,
  h2 = rows$h == 2L,
  post_peak_h1 = rows$m1_state == "post_peak" & rows$h == 1L,
  post_peak_h2 = rows$m1_state == "post_peak" & rows$h == 2L
)

win_table <- do.call(rbind, lapply(names(state_subsets), function(nm) {
  s <- state_subsets[[nm]]
  w_no <- win_rate("gam_no_p_hat", s)
  w_tpl <- win_rate("gam_tpl_p_hat", s)
  data.frame(
    subset = nm,
    n = as.integer(w_no["n"]),
    gam_no_win_rate = w_no["win"],
    gam_no_tie_rate = w_no["tie"],
    gam_tpl_win_rate = w_tpl["win"],
    gam_tpl_tie_rate = w_tpl["tie"],
    stringsAsFactors = FALSE
  )
}))

implaus <- data.frame(
  method = methods,
  n_over_40pct = vapply(method_cols, function(cc) sum(rows[[cc]] > implaus_hi, na.rm = TRUE), integer(1)),
  n_over_observed_max = vapply(method_cols, function(cc) sum(rows[[cc]] > observed_max, na.rm = TRUE), integer(1)),
  max_p_hat = vapply(method_cols, function(cc) max(rows[[cc]], na.rm = TRUE), numeric(1)),
  stringsAsFactors = FALSE
)

status_counts <- data.frame(
  gam_no = as.integer(table(factor(rows$gam_no_status,
    levels = c("ok", "error", "target_not_in_grid", "no_origin_fit")
  ))),
  gam_tpl = as.integer(table(factor(rows$gam_tpl_status,
    levels = c("ok", "error", "target_not_in_grid", "no_origin_fit")
  )))
)
status_counts$status <- c("ok", "error", "target_not_in_grid", "no_origin_fit")
status_counts <- status_counts[, c("status", "gam_no", "gam_tpl")]

errors_no <- unique(rows$gam_no_status[grepl("^error", rows$gam_no_status)])
error_examples <- list(
  n_error_rows_no = sum(grepl("^error", rows$gam_no_status)),
  n_error_rows_tpl = sum(grepl("^error", rows$gam_tpl_status)),
  n_na_no = sum(!is.finite(rows$gam_no_p_hat)),
  n_na_tpl = sum(!is.finite(rows$gam_tpl_p_hat))
)
err_rows <- which(grepl("^error", rows$gam_no_status))
if (length(err_rows) > 0) {
  error_examples$example <- rows[err_rows[1], c("season", "eval_weekF", "target_weekF", "h")]
  error_examples$example_status <- rows$gam_no_status[err_rows[1]]
}
tpl_err_rows <- which(grepl("^error", rows$gam_tpl_status))
if (length(tpl_err_rows) > 0) {
  error_examples$tpl_example <- rows[tpl_err_rows[1], c("season", "eval_weekF", "target_weekF", "h")]
  error_examples$tpl_example_status <- rows$gam_tpl_status[tpl_err_rows[1]]
}

n_warn_no <- sum(vapply(fits, function(x) length(x$no$warns) > 0, logical(1)))
n_warn_tpl <- sum(vapply(fits, function(x) length(x$tpl$warns) > 0, logical(1)))
warn_msgs <- unique(unlist(lapply(fits, function(x) c(x$no$warns, x$tpl$warns))))

metrics <- list(
  overall = overall,
  per_season_post_peak = per_season_post,
  per_season_aligning = per_season_state,
  per_horizon = per_horizon,
  win_table = win_table,
  implausibility = implaus,
  status_counts = status_counts,
  failure = error_examples,
  origin_counts = data.frame(
    n_mp_rows = n_mp,
    n_origins = nrow(origins),
    n_origins_before_minobs = n_orig_pre,
    n_with_m1 = sum(is.finite(rows$m1_p_hat)),
    n_post_peak = sum(rows$m1_state == "post_peak"),
    n_aligning = sum(rows$m1_state == "aligning")
  ),
  warnings = list(
    n_origins_any_warning_no = n_warn_no,
    n_origins_any_warning_tpl = n_warn_tpl,
    messages = warn_msgs
  ),
  observed_max = observed_max
)
saveRDS(metrics, out_summary)
cat("Wrote", out_summary, "\n\n")

print(metrics$origin_counts)
cat("\nOverall MAE (percentage points)\n")
print(overall, row.names = FALSE)
cat("\nPer season, post_peak rows\n")
print(per_season_post, row.names = FALSE)
cat("\nPer season, aligning (pre-peak) rows\n")
print(per_season_state, row.names = FALSE)
cat("\nPer horizon\n")
print(per_horizon, row.names = FALSE)
cat("\nWin rates vs M1 (finite common rows)\n")
print(win_table, row.names = FALSE)
cat("\nImplausibility\n")
print(implaus, row.names = FALSE)
cat("\nReturn status counts\n")
print(status_counts, row.names = FALSE)
cat("\nFailure summary\n")
print(error_examples)
cat("\nWarnings\n")
print(metrics$warnings)
