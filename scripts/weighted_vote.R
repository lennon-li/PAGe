## Weighted voting comparison: binary N_req=5 vs weighted gate scores
setwd("C:/Users/lennon.li/Documents/claude/PAGe")

load("data/data.RData")
source("R/ignitionTraining.R")
source("R/getCurrentD.R")

ign_fit <- fitIgnition(
  dat=alignedD, event_k=1L, lead=1L,
  A_pre=6L, B_post=6L, k_week=6L, k_p=8L, k_fs=4L,
  fit_base=TRUE, verbose=FALSE
)

tuned   <- readRDS("data/stage1_tuning.rds")
bp      <- tuned$best_params
compare <- tuned$compare

## ---- Weights from binding analysis ----------------------------------------
##  gate     | binds | mean lead | weight
##  cond_dp  |  9/10 |    0.0   |  2.0   <- rate-limiting; mandatory at thr=4
##  cond_sum |  1/10 |   -2.7   |  1.0
##  cond_p   |  0/10 |   -3.9   |  0.8
##  cond_prev|  0/10 |   -4.6   |  0.8
##  cond_inc |  0/10 |   -6.9   |  0.4   <- trivial once others fire
##
##  threshold = 4.0
##  Possible firing combos (all require dp):
##    dp + p + prev + inc = 4.0  (fires even without sum)
##    dp + sum + p        = 3.8  (does NOT fire — sum doesn't compensate inc)
##    dp + sum + p + prev = 4.6  (fires)

weights   <- c(cond_sum=1.0, cond_p=0.8, cond_prev=0.8, cond_inc=0.4, cond_dp=2.0)
score_thr <- 4.0

bp_w      <- c(bp, list(gate_weights=weights, score_thr=score_thr))
bp_w$N_req <- NULL

## ---- Historical (LOSO): binary vs weighted ---------------------------------
det_bin <- detectIgnitionBySeason_M0v2(ign_fit, params=bp,   iWeek=TRUE, verbose=FALSE)
det_wt  <- detectIgnitionBySeason_M0v2(ign_fit, params=bp_w, iWeek=TRUE, verbose=FALSE)

comp_bin <- det_bin$compare
comp_wt  <- det_wt$compare

result <- merge(
  comp_bin[, c("season","iWeek_true","iWeek_hat","diff")],
  comp_wt[,  c("season","iWeek_hat","diff")],
  by="season", suffixes=c("_bin","_wt")
)
## exclude 2015-16 (covid-excluded)
result <- result[result$season != "2015-16", ]
result <- result[order(result$iWeek_true), ]

cat("=== Historical LOSO: binary (N_req=5) vs weighted (score_thr=4.0) ===\n")
cat(sprintf("  Weights: dp=%.1f  sum=%.1f  p=%.1f  prev=%.1f  inc=%.1f  thr=%.1f\n\n",
            weights["cond_dp"], weights["cond_sum"], weights["cond_p"],
            weights["cond_prev"], weights["cond_inc"], score_thr))
cat(sprintf("  %-9s  %4s  %11s  %11s  %6s\n",
            "season","true","binary","weighted","delta"))
cat(strrep("-", 52), "\n")
for (i in seq_len(nrow(result))) {
  r     <- result[i,]
  delta <- r$iWeek_hat_wt - r$iWeek_hat_bin
  flag  <- if (delta != 0) " **" else ""
  cat(sprintf("  %-9s  w%02d  w%02d (%+d)     w%02d (%+d)     %+d%s\n",
              r$season, r$iWeek_true,
              r$iWeek_hat_bin, r$diff_bin,
              r$iWeek_hat_wt,  r$diff_wt,
              delta, flag))
}
cat(strrep("-", 52), "\n")
cat(sprintf("  MAE:          %.2f         %.2f\n\n",
            mean(abs(result$diff_bin)), mean(abs(result$diff_wt))))

## Show score at detection for each season (weighted)
cat("=== Score at detection week ===\n")
dt_wt <- det_wt$data
gate_cols <- c("cond_sum","cond_p","cond_prev","cond_inc","cond_dp")
for (i in seq_len(nrow(comp_wt))) {
  s <- comp_wt$season[i]
  if (s == "2015-16") next
  iHat <- comp_wt$iWeek_hat[i]
  row  <- dt_wt[dt_wt$season == s & dt_wt$weekF == iHat, ]
  if (nrow(row) == 0) next
  flags <- sapply(gate_cols, function(g) if (isTRUE(row[[g]][1])) "T" else "F")
  sc    <- sprintf("%.1f", row$score[1])
  cat(sprintf("  %s (w%02d): %s  score=%s\n", s, iHat,
              paste(paste0(sub("cond_","",gate_cols),"=",flags), collapse="  "), sc))
}

## ---- 2025-26 current season -----------------------------------------------
cat("\n=== 2025-26 prospective (current season) ===\n")

suppressPackageStartupMessages({
  library(dplyr); library(magrittr); library(tidyr); library(lubridate); library(MMWRweek)
})
currentSeason <- tryCatch(
  getCurrentD() |> dplyr::select(-newWeek, -season),
  error=function(e) { cat("getCurrentD() failed:", conditionMessage(e), "\n"); NULL }
)

if (!is.null(currentSeason)) {
  currentSeason$season <- "2025-26"
  cat("Current season weeks available: w1 to w",
      max(currentSeason$weekF[!is.na(currentSeason$p)], na.rm=TRUE), "\n\n")

  ## Score current season with the classifier from ign_fit
  ## Attach classifier predictions to current season
  gam_cls <- ign_fit$fits$base$gam
  cur_dt  <- data.table::as.data.table(currentSeason)
  cur_dt[, p_cls_p := as.numeric(mgcv::predict.gam(gam_cls, newdata=.SD, type="response"))]

  ## Run both systems on current season
  det_cur_bin <- detectIgnitionBySeason_M0v2(cur_dt, params=bp,   iWeek=FALSE, verbose=FALSE)
  det_cur_wt  <- detectIgnitionBySeason_M0v2(cur_dt, params=bp_w, iWeek=FALSE, verbose=FALSE)

  iHat_bin <- det_cur_bin$by_season$iWeek_hat
  iHat_wt  <- det_cur_wt$by_season$iWeek_hat

  cat(sprintf("  Binary   detection: %s\n",
              if (is.na(iHat_bin)) "NOT YET" else paste0("w", iHat_bin)))
  cat(sprintf("  Weighted detection: %s\n\n",
              if (is.na(iHat_wt))  "NOT YET" else paste0("w", iHat_wt)))

  ## Gate timeline
  dt_cur <- det_cur_wt$data
  dt_s   <- dt_cur[order(dt_cur$weekF), ]
  max_wk <- max(dt_s$weekF[!is.na(dt_s$p)], na.rm=TRUE)
  dt_s   <- dt_s[dt_s$weekF >= 13 & dt_s$weekF <= max_wk, ]

  cat("  Gate timeline (2025-26, from w13):\n")
  for (k in seq_len(nrow(dt_s))) {
    row   <- dt_s[k,]
    flags <- sapply(gate_cols, function(g) if (isTRUE(row[[g]])) "T" else "F")
    sc    <- if (!is.na(row$score)) sprintf("%.1f", row$score) else "NA"
    p_v   <- if (!is.na(row$p_sm)) sprintf("%.3f", row$p_sm*100) else "NA"
    det_m <- if (!is.na(iHat_wt) && row$weekF == iHat_wt) " <<DETECTED" else ""
    cat(sprintf("  w%02d p=%s%%  %s  score=%s%s\n",
                row$weekF, p_v,
                paste(paste0(sub("cond_","",gate_cols),"=",flags), collapse=" "),
                sc, det_m))
  }
} else {
  cat("Could not retrieve current season data.\n")
}
