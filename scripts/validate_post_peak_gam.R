#!/usr/bin/env Rscript
# Validation of PAGe::forecast_post_peak_gam() (dead code, zero live callers).
# Read-only benchmark: real function vs plain-GAM baseline vs recorded M1.
# Writes nothing outside stdout + an optional RDS in the scratch dir.

suppressMessages({
  library(PAGe)
  library(mgcv)
})

ART <- file.path(
  "results/final-kit-2026-27",
  "20260918T1520Z-final-2026-27-wmin8-venkata", "artifacts"
)
OUT <- Sys.getenv("PPG_OUT", "")

# ---- data -----------------------------------------------------------------
raw <- PAGe::load_flu_hist("/home/yeli/FLU/flu_testing_data_orvt_20260916.csv")
cal <- PAGe::page_season_calendar(
  dates = as.Date(raw$week_start_date), start_week = 27L
)
dat <- data.frame(
  season = cal$season,
  weekF  = as.integer(cal$weekF),
  y      = as.numeric(raw$pos_flua),
  N      = as.numeric(raw$test_flu)
)
dat$neg <- dat$N - dat$y
dat <- dat[!is.na(dat$y) & !is.na(dat$N) & dat$N > 0, ]
dat <- dat[order(dat$season, dat$weekF), ]
dat$p_obs <- dat$y / dat$N

g_ref_fun <- readRDS(file.path(ART, "m1_frozen.rds"))$ref$g_ref_fun

m1p <- as.data.frame(readRDS(file.path(ART, "m2_tuning.rds"))$m1_train_preds)
m1p <- m1p[, c("season", "eval_weekF", "target_weekF", "h", "m1_p_hat")]

SEASONS <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18", "2018-19",
  "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
)

# ---- plain-GAM baseline ---------------------------------------------------
baseline_gam <- function(train, target_weekF) {
  fit <- try(mgcv::gam(
    cbind(y, neg) ~ s(weekF, k = 8),
    family = stats::binomial(), data = train, method = "REML"
  ), silent = TRUE)
  if (inherits(fit, "try-error")) {
    return(list(p = NA_real_, err = as.character(fit)))
  }
  p <- try(as.numeric(stats::predict(
    fit, newdata = data.frame(weekF = target_weekF), type = "response"
  )), silent = TRUE)
  if (inherits(p, "try-error")) {
    return(list(p = NA_real_, err = as.character(p)))
  }
  list(p = p, err = NA_character_)
}

# ---- the function under test ----------------------------------------------
# newWeek is documented as "sequential index". weekF is exactly that: a
# 1..52/53 within-season index anchored at start_week=27. g_ref_fun from the
# frozen M1 ref is also indexed on weekF (its peak sits at weekF ~28, i.e.
# January), so weekF is passed straight through with no transform.
call_ppg <- function(train, target_weekF, use_ref, use_weights) {
  cs <- data.frame(
    newWeek = as.integer(train$weekF),
    y       = train$y,
    neg     = train$neg
  )
  res <- try(PAGe::forecast_post_peak_gam(
    currentSeason = cs,
    g_ref_fun     = if (use_ref) g_ref_fun else NULL,
    max_newWeek   = 53L,
    k_smooth      = 8,
    use_weights   = use_weights
  ), silent = TRUE)
  if (inherits(res, "try-error")) {
    return(list(p = NA_real_, err = trimws(as.character(res))))
  }
  pd <- res$pred_df
  i <- match(target_weekF, pd$newWeek)
  if (is.na(i)) {
    return(list(p = NA_real_, err = "target_weekF absent from pred_df"))
  }
  list(p = pd$p_hat[i], err = NA_character_)
}

# ---- walk-forward grid ----------------------------------------------------
rows <- list()
for (s in SEASONS) {
  ds <- dat[dat$season == s, ]
  wks <- sort(ds$weekF)
  for (ev in wks) {
    train <- ds[ds$weekF <= ev, ]
    if (nrow(train) < 10L) next
    for (h in 1:2) {
      tw <- ev + h
      act <- ds$p_obs[match(tw, ds$weekF)]
      if (is.na(act)) next
      a <- call_ppg(train, tw, use_ref = TRUE, use_weights = TRUE)
      b <- call_ppg(train, tw, use_ref = FALSE, use_weights = TRUE)
      cwt <- call_ppg(train, tw, use_ref = TRUE, use_weights = FALSE)
      bl <- baseline_gam(train, tw)
      rows[[length(rows) + 1L]] <- data.frame(
        season = s, eval_weekF = ev, target_weekF = tw, h = h,
        n_train = nrow(train), actual = act,
        ppg_ref = a$p, ppg_ref_err = a$err,
        ppg_noref = b$p, ppg_noref_err = b$err,
        ppg_ref_nw = cwt$p, ppg_ref_nw_err = cwt$err,
        base = bl$p, base_err = bl$err,
        stringsAsFactors = FALSE
      )
    }
  }
}
res <- do.call(rbind, rows)
res <- merge(res, m1p, by = c("season", "eval_weekF", "target_weekF", "h"),
             all.x = TRUE)

pp <- function(x) 100 * x
mae <- function(pred, act) mean(abs(pp(pred) - pp(act)), na.rm = TRUE)

meth <- c(ppg_ref = "ppg_ref", ppg_noref = "ppg_noref",
          ppg_ref_nw = "ppg_ref_nw", base = "base", m1 = "m1_p_hat")

cat("\n=== GRID ===\n")
cat("rows:", nrow(res), " seasons:", length(unique(res$season)), "\n")
cat("rows with M1 prediction:", sum(!is.na(res$m1_p_hat)), "\n\n")

cat("=== ERRORS / NA ===\n")
for (nm in c("ppg_ref", "ppg_noref", "ppg_ref_nw", "base")) {
  e <- res[[paste0(nm, "_err")]]
  cat(sprintf("%-11s NA pred: %4d   errors: %4d\n",
              nm, sum(is.na(res[[nm]])), sum(!is.na(e))))
  if (any(!is.na(e))) print(head(unique(e[!is.na(e)]), 3))
}
cat(sprintf("%-11s NA pred: %4d\n", "m1",
            sum(is.na(res$m1_p_hat) & !is.na(res$m1_p_hat) | FALSE)))

cat("\n=== IMPLAUSIBLE (> 40% positivity) ===\n")
cat("max observed positivity in record:",
    sprintf("%.2f%%\n", 100 * max(dat$p_obs, na.rm = TRUE)))
for (nm in names(meth)) {
  v <- res[[meth[[nm]]]]
  bad <- which(!is.na(v) & v > 0.40)
  cat(sprintf("%-11s n>40%%: %3d  seasons: %2d  max: %6.2f%%\n",
              nm, length(bad), length(unique(res$season[bad])),
              100 * suppressWarnings(max(v, na.rm = TRUE))))
}

overall <- function(sub, label) {
  cat("\n===", label, "(n =", nrow(sub), ") MAE, percentage points ===\n")
  cat(sprintf("%-11s %8s\n", "method", "MAE"))
  for (nm in names(meth)) {
    cat(sprintf("%-11s %8.2f\n", nm, mae(sub[[meth[[nm]]]], sub$actual)))
  }
  cat("\nper season:\n")
  cat(sprintf("%-9s %6s %8s %8s %8s %8s %8s\n",
              "season", "n", "ppg_ref", "ppg_nor", "ppg_nw", "base", "m1"))
  for (s in sort(unique(sub$season))) {
    d <- sub[sub$season == s, ]
    cat(sprintf("%-9s %6d %8.2f %8.2f %8.2f %8.2f %8.2f\n", s, nrow(d),
                mae(d$ppg_ref, d$actual), mae(d$ppg_noref, d$actual),
                mae(d$ppg_ref_nw, d$actual), mae(d$base, d$actual),
                mae(d$m1_p_hat, d$actual)))
  }
  cat("\nby horizon:\n")
  for (h in 1:2) {
    d <- sub[sub$h == h, ]
    cat(sprintf("h=%d n=%4d  ppg_ref %6.2f  ppg_nor %6.2f  ppg_nw %6.2f  base %6.2f  m1 %6.2f\n",
                h, nrow(d), mae(d$ppg_ref, d$actual), mae(d$ppg_noref, d$actual),
                mae(d$ppg_ref_nw, d$actual), mae(d$base, d$actual),
                mae(d$m1_p_hat, d$actual)))
  }
}

overall(res, "FULL WALK-FORWARD GRID")
sub <- res[!is.na(res$m1_p_hat), ]
overall(sub, "M1-MATCHED SUBSET")

cat("\n=== ppg_ref vs base, head-to-head (full grid) ===\n")
ok <- !is.na(res$ppg_ref) & !is.na(res$base)
d1 <- abs(res$ppg_ref[ok] - res$actual[ok])
d2 <- abs(res$base[ok] - res$actual[ok])
cat(sprintf("ppg_ref better in %d / %d rows (%.1f%%)\n",
            sum(d1 < d2), sum(ok), 100 * mean(d1 < d2)))
cat(sprintf("mean |diff| between the two predictions: %.3f pp; max %.3f pp\n",
            mean(pp(abs(res$ppg_ref[ok] - res$base[ok]))),
            max(pp(abs(res$ppg_ref[ok] - res$base[ok])))))
w <- which(ok)[order(-(d1 - d2)[])[1:8]]
cat("\nworst rows for ppg_ref vs base:\n")
print(res[w, c("season", "eval_weekF", "target_weekF", "h",
               "actual", "ppg_ref", "base", "m1_p_hat")], row.names = FALSE)

if (nzchar(OUT)) saveRDS(res, OUT)
cat("\ndone\n")
