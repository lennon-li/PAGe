## Test cond_dp2 (short-window velocity) replacing cond_inc
## Goal: fix +3 seasons (2018-19, 2024-25) without breaking others
setwd("C:/Users/lennon.li/Documents/claude/PAGe")

load("data/data.RData")
source("R/ignitionTraining.R")

ign_fit <- fitIgnition(
  dat=alignedD, event_k=1L, lead=1L,
  A_pre=6L, B_post=6L, k_week=6L, k_p=8L, k_fs=4L,
  fit_base=TRUE, verbose=FALSE
)

## ---- First: inspect short-window velocity at the critical weeks ----
cat("=== Short-window velocity (p_sm[w] - p_sm[w-K_dp2]) at key weeks ===\n\n")
bp_ref <- readRDS("data/stage1_tuning.rds")$best_params
bp_check <- c(bp_ref, list(use_dp2=TRUE, K_dp2=2L, dp_thr2=0.001))
det0 <- detectIgnitionBySeason_M0v2(ign_fit, params=bp_check, verbose=FALSE)
dt0  <- det0$data

seasons_check <- c("2018-19","2024-25","2016-17","2017-18","2022-23")
cat(sprintf("  %-9s  %4s  %6s  %8s  %8s  dp4_fire  dp2_fire\n",
            "season","week","p_sm%","dp4(w-4)","dp2(w-2)"))
cat(strrep("-",70),"\n")
for (s in seasons_check) {
  dt_s <- dt0[dt0$season == s, ]
  dt_s <- dt_s[order(dt_s$weekF), ]
  iHat_ref <- readRDS("data/stage1_tuning.rds")$compare$iWeek_hat[
    readRDS("data/stage1_tuning.rds")$compare$season == s]
  iTrue <- readRDS("data/stage1_tuning.rds")$compare$iWeek_true[
    readRDS("data/stage1_tuning.rds")$compare$season == s]
  show_rows <- dt_s[dt_s$weekF >= max(13, iTrue-2) & dt_s$weekF <= iHat_ref+1, ]
  for (k in seq_len(nrow(show_rows))) {
    r  <- show_rows[k,]
    dp4_v  <- if (!is.na(r$p_sm_lag))  sprintf("%+.3f", (r$p_sm - r$p_sm_lag)*100) else "  NA  "
    dp2_v  <- if (!is.na(r$p_sm_lag2)) sprintf("%+.3f", (r$p_sm - r$p_sm_lag2)*100) else "  NA  "
    det_m  <- if (r$weekF == iHat_ref) " <<prev_det" else ""
    true_m <- if (r$weekF == iTrue)    " [TRUE]" else ""
    cat(sprintf("  %-9s  w%02d  %6.3f  %8s  %8s  %-9s %-9s%s%s\n",
                s, r$weekF, r$p_sm*100, dp4_v, dp2_v,
                if (isTRUE(r$cond_dp))  "T" else "F",
                if (isTRUE(r$cond_dp2)) "T" else "F",
                det_m, true_m))
  }
  cat("\n")
}

## ---- LOSO grid: vary K_dp2 and dp_thr2 ----
cat("=== LOSO grid search: cond_dp2 replacing cond_inc ===\n\n")

grid_dp2 <- data.table::CJ(
  cls_thr   = 0.26, use_cls = FALSE,
  p_thr     = 0.007,
  prev_thr  = c(0.004, 0.005, 0.006),
  n_consec  = 3L, L = 2L, eps = 0,
  K_sum     = 5L, p_sum_thr = c(0.03, 0.04, 0.05),
  K_dp      = 4L, dp_thr    = c(0.012, 0.015),
  K_dp2     = c(2L, 3L),
  dp_thr2   = c(0.003, 0.005, 0.006, 0.008, 0.010),
  use_dp2   = TRUE,
  N_req     = 5L,
  w_min     = 13L, w_max = 30L,
  sorted    = FALSE
)
cat("Grid rows:", nrow(grid_dp2), "\n")

exS <- c("2011-12","2015-16","2020-21","2021-22","2025-26")
loso_dp2 <- loso_M0v2(ign_fit$data, grid=grid_dp2, exSeason=exS, verbose=FALSE)

cat("\nNames in loso_dp2:", paste(names(loso_dp2), collapse=", "), "\n")
bp_new  <- loso_dp2$best_params %||% loso_dp2$best_params_loso
comp_new <- loso_dp2$compare %||% loso_dp2$loso_compare
cat("\nBest LOSO params (dp2 system):\n")
print(unlist(bp_new))
cat("\nLOSO compare table:\n")
print(comp_new)
cat("\nLOSO summary:\n")
print(loso_dp2$summary)

## ---- Side-by-side: old vs new ----
compare_old <- readRDS("data/stage1_tuning.rds")$compare
exS_hist <- c("2011-12","2015-16","2020-21","2021-22","2025-26")
compare_old <- compare_old[!compare_old$season %in% exS_hist, ]
comp_new_hist <- comp_new[!comp_new$season %in% exS_hist, ]

cat("\n=== Side-by-side: binary N_req=5 (old) vs cond_dp2 LOSO (new) ===\n")
cat(sprintf("  %-9s  %4s  %10s  %10s  %6s\n","season","true","old(cond_inc)","new(cond_dp2)","delta"))
cat(strrep("-",52),"\n")
merged <- merge(compare_old[,c("season","iWeek_true","iWeek_hat","diff")],
                comp_new_hist[,c("season","iWeek_hat","diff")],
                by="season", suffixes=c("_old","_new"))
merged <- merged[order(merged$iWeek_true),]
for (i in seq_len(nrow(merged))) {
  r <- merged[i,]
  delta <- r$iWeek_hat_new - r$iWeek_hat_old
  flag  <- if (delta != 0) " **" else ""
  cat(sprintf("  %-9s  w%02d  w%02d (%+d)     w%02d (%+d)     %+d%s\n",
              r$season, r$iWeek_true,
              r$iWeek_hat_old, r$diff_old,
              r$iWeek_hat_new, r$diff_new,
              delta, flag))
}
cat(strrep("-",52),"\n")
cat(sprintf("  MAE:          %.2f         %.2f\n",
            mean(abs(merged$diff_old)), mean(abs(merged$diff_new))))

## ---- 2025-26 prospective ----
cat("\n=== 2025-26 prospective (best dp2 params) ===\n")
suppressPackageStartupMessages({
  library(dplyr); library(magrittr); library(tidyr); library(lubridate); library(MMWRweek)
})
currentSeason <- tryCatch(
  getCurrentD() |> dplyr::select(-newWeek, -season),
  error=function(e) { cat("getCurrentD() failed:", conditionMessage(e), "\n"); NULL }
)
if (!is.null(currentSeason)) {
  currentSeason$season <- "2025-26"
  gam_cls <- ign_fit$fits$base$gam
  cur_dt  <- data.table::as.data.table(currentSeason)
  cur_dt[, p_cls_p := as.numeric(mgcv::predict.gam(gam_cls, newdata=.SD, type="response"))]

  bp_new <- loso_dp2$best_params %||% loso_dp2$best_params_loso
  det_cur <- detectIgnitionBySeason_M0v2(cur_dt, params=bp_new, iWeek=FALSE, verbose=FALSE)
  iHat_new <- det_cur$by_season$iWeek_hat
  cat(sprintf("  Detection: %s\n", if(is.na(iHat_new)) "NOT YET" else paste0("w",iHat_new)))

  gate_cols <- c("cond_sum","cond_p","cond_prev","cond_dp2","cond_dp")
  dt_cur <- det_cur$data
  dt_s   <- dt_cur[order(dt_cur$weekF),]
  max_wk <- max(dt_s$weekF[!is.na(dt_s$p)], na.rm=TRUE)
  dt_s   <- dt_s[dt_s$weekF >= 13 & dt_s$weekF <= max_wk,]
  cat("\n  Gate timeline (2025-26, from w13):\n")
  for (k in seq_len(nrow(dt_s))) {
    row   <- dt_s[k,]
    flags <- sapply(gate_cols, function(g) if(isTRUE(row[[g]])) "T" else "F")
    p_v   <- if(!is.na(row$p_sm)) sprintf("%.3f", row$p_sm*100) else "NA"
    det_m <- if(!is.na(iHat_new) && row$weekF==iHat_new) " <<DETECTED" else ""
    cat(sprintf("  w%02d p=%s%%  %s%s\n", row$weekF, p_v,
                paste(paste0(sub("cond_","",gate_cols),"=",flags),collapse=" "), det_m))
  }
}
