## Hybrid scoring v2: all 5 weights + gate parameters tuned via LOSO
## Hard constraint: |diff| <= 2 for all training seasons
##
##   score = w_sum  * p_sumK          (raw rolling sum)
##         + w_p    * p_sm            (raw smoothed positivity)
##         + w_prev * prev            (raw cumulative prevalence)
##         + w_inc  * cond_inc        (binary × weight)
##         + w_dp   * cond_dp         (binary × weight)
##
##   fire when score >= score_thr  AND  w_min <= week <= w_max
##
## Tuned: w_sum, w_p, w_prev, w_inc, w_dp, score_thr
##        K_dp, dp_thr  (cond_dp gate)
##        n_consec      (cond_inc gate)

setwd("C:/Users/lennon.li/Documents/claude/PAGe")
suppressPackageStartupMessages({
  library(data.table); library(dplyr); library(magrittr)
  library(tidyr); library(lubridate); library(MMWRweek)
  library(future); library(furrr)
})
load("data/data.RData")
source("R/m0_training.R")
source("R/getCurrentD.R")

ign_fit <- fitIgnition(
  dat=alignedD, event_k=1L, lead=1L,
  A_pre=6L, B_post=6L, k_week=6L, k_p=8L, k_fs=4L,
  fit_base=TRUE, verbose=FALSE
)

## --------------------------------------------------------------------------
detect_hybrid <- function(dat,
                          w_sum, w_p, w_prev, w_inc, w_dp, score_thr,
                          K_sum=5L, K_dp=4L, L=2L, eps=0, dp_thr=0.015,
                          n_consec=3L, w_min=13L, w_max=30L,
                          season_col="season", week_col="weekF",
                          y_col="y", N_col="N") {
  DT <- as.data.table(copy(as.data.frame(dat)))
  setorderv(DT, c(season_col, week_col))

  # signals
  DT[, cum_y    := cumsum(get(y_col)), by=season_col]
  DT[, cum_N    := cumsum(get(N_col)), by=season_col]
  DT[, prev     := fifelse(cum_N > 0, cum_y / cum_N, NA_real_)]
  DT[, p0       := fifelse(is.na(p), 0, p)]
  DT[, p_sumK   := frollsum(p0, n=K_sum, align="right", fill=NA_real_), by=season_col]
  DT[, p_sm     := frollmean(p, n=L, align="right", fill=NA_real_), by=season_col]
  DT[, dp       := p_sm - shift(p_sm, 1L, type="lag"), by=season_col]
  DT[, p_sm_lag := shift(p_sm, K_dp, type="lag"), by=season_col]

  # binary gates
  k_inc    <- max(1L, n_consec - 1L)
  need_inc <- max(1L, k_inc - 1L)
  DT[, inc      := as.integer(dp > -eps)]
  DT[, cond_inc := frollsum(inc, n=k_inc, align="right",
                             fill=NA_integer_) >= need_inc, by=season_col]
  DT[, cond_dp  := !is.na(p_sm_lag) & ((p_sm - p_sm_lag) >= dp_thr)]

  # score: raw continuous x weight  +  binary x weight
  DT[, score := w_sum  * fifelse(!is.na(p_sumK), p_sumK, 0) +
                w_p    * fifelse(!is.na(p_sm),   p_sm,   0) +
                w_prev * fifelse(!is.na(prev),   prev,   0) +
                w_inc  * as.numeric(cond_inc %in% TRUE) +
                w_dp   * as.numeric(cond_dp  %in% TRUE)]

  DT[, cond_win  := get(week_col) >= w_min & get(week_col) <= w_max]
  DT[, ignite_ok := cond_win & !is.na(score) & score >= score_thr]

  by_hat <- DT[ignite_ok==TRUE, .(iWeek_hat=min(get(week_col),na.rm=TRUE)), by=season_col]
  all_s  <- DT[, .(s=unique(get(season_col)))]
  setnames(all_s, "s", season_col)
  by_hat <- merge(all_s, by_hat, by=season_col, all.x=TRUE, sort=FALSE)
  list(by_season=as.data.frame(by_hat), data=as.data.frame(DT))
}

## --------------------------------------------------------------------------
## LOSO
## --------------------------------------------------------------------------
dat_hist     <- ign_fit$data
exS          <- c("2011-12","2015-16","2020-21","2021-22","2025-26")
tune_seasons <- setdiff(unique(dat_hist$season), exS)

truth_dt <- dat_hist[dat_hist$phase==1, ] |>
  group_by(season) |> summarise(iWeek_true=min(weekF,na.rm=TRUE),.groups="drop") |>
  as.data.frame()

## Grid: 5 weights + score_thr + gate params (K_dp, dp_thr, n_consec)
grid_h <- CJ(
  w_sum     = c(5, 15, 30),
  w_p       = c(30, 60, 100),
  w_prev    = c(50, 100),
  w_inc     = c(0.1, 0.3),
  w_dp      = c(0.5, 1.0, 2.0),
  score_thr = c(2.0, 2.5, 3.0),
  K_dp      = c(3L, 4L, 5L),
  dp_thr    = c(0.008, 0.012, 0.015),
  n_consec  = c(2L, 3L),
  sorted    = FALSE
)
cat(sprintf("Hybrid grid v2: %d rows\n", nrow(grid_h)))

## Loss: hard penalty for |diff| > 2 or any miss; minimize MAE otherwise
loss_fn <- function(diff) {
  if (any(is.na(diff)))   return(1e9)
  if (any(abs(diff) > 2)) return(1e6 + sum(abs(diff)))
  sum(abs(diff))
}

plan(multisession, workers=parallel::detectCores()-1)
loso_bp <- furrr::future_map(tune_seasons, function(held_out) {
  train_s  <- setdiff(tune_seasons, held_out)
  train_d  <- dat_hist[dat_hist$season %in% train_s, ]
  truth_tr <- truth_dt[truth_dt$season %in% train_s, ]

  best_loss <- Inf; best_i <- 1L
  for (i in seq_len(nrow(grid_h))) {
    g <- grid_h[i]
    det <- detect_hybrid(train_d,
                         w_sum=g$w_sum, w_p=g$w_p, w_prev=g$w_prev,
                         w_inc=g$w_inc, w_dp=g$w_dp, score_thr=g$score_thr,
                         K_dp=as.integer(g$K_dp), dp_thr=g$dp_thr,
                         n_consec=as.integer(g$n_consec))
    comp <- merge(det$by_season, truth_tr, by="season")
    comp$diff <- comp$iWeek_hat - comp$iWeek_true
    lss <- loss_fn(comp$diff)
    if (lss < best_loss) { best_loss <- lss; best_i <- i }
  }
  as.list(grid_h[best_i])
}, .options=furrr::furrr_options(seed=TRUE))
plan(sequential)

## Evaluate on held-out seasons
held_results <- lapply(seq_along(tune_seasons), function(fi) {
  s  <- tune_seasons[fi]
  bp <- loso_bp[[fi]]
  det <- detect_hybrid(dat_hist[dat_hist$season==s, ],
                       w_sum=bp$w_sum, w_p=bp$w_p, w_prev=bp$w_prev,
                       w_inc=bp$w_inc, w_dp=bp$w_dp, score_thr=bp$score_thr,
                       K_dp=as.integer(bp$K_dp), dp_thr=bp$dp_thr,
                       n_consec=as.integer(bp$n_consec))
  iTrue <- truth_dt$iWeek_true[truth_dt$season==s]
  iHat  <- det$by_season$iWeek_hat
  data.frame(season=s, iWeek_true=iTrue, iWeek_hat=iHat, diff=iHat-iTrue,
             w_sum=bp$w_sum, w_p=bp$w_p, w_prev=bp$w_prev,
             w_inc=bp$w_inc, w_dp=bp$w_dp, score_thr=bp$score_thr,
             K_dp=bp$K_dp, dp_thr=bp$dp_thr, n_consec=bp$n_consec)
})
loso_comp <- do.call(rbind, held_results)
loso_comp <- loso_comp[order(loso_comp$iWeek_true), ]

## Side-by-side comparison
compare_bin <- readRDS("data/stage1_tuning.rds")$compare
compare_bin <- compare_bin[!compare_bin$season %in% exS, ]
merged <- merge(compare_bin[, c("season","iWeek_true","iWeek_hat","diff")],
                loso_comp[, c("season","iWeek_hat","diff",
                               "w_sum","w_p","w_prev","w_inc","w_dp","score_thr",
                               "K_dp","dp_thr","n_consec")],
                by="season", suffixes=c("_bin","_hyb"))
merged <- merged[order(merged$iWeek_true), ]

cat("\n=== LOSO: binary N_req=5 vs hybrid (hard |diff|<=2 constraint) ===\n")
cat(sprintf("  %-9s  %4s  %10s  %10s  %6s\n","season","true","binary","hybrid","delta"))
cat(strrep("-",52),"\n")
for (i in seq_len(nrow(merged))) {
  r <- merged[i,]
  delta <- r$iWeek_hat_hyb - r$iWeek_hat_bin
  flag  <- if (delta != 0) " **" else ""
  cat(sprintf("  %-9s  w%02d  w%02d (%+d)     w%02d (%+d)     %+d%s\n",
              r$season, r$iWeek_true,
              r$iWeek_hat_bin, r$diff_bin,
              r$iWeek_hat_hyb, r$diff_hyb,
              delta, flag))
}
cat(strrep("-",52),"\n")
cat(sprintf("  MAE:          %.2f          %.2f\n\n",
            mean(abs(merged$diff_bin),na.rm=TRUE),
            mean(abs(merged$diff_hyb),na.rm=TRUE)))

cat("Per-fold best params:\n")
cat(sprintf("  %-9s  w_sum  w_p  w_prev  w_inc  w_dp  thr   K_dp  dp_thr  n_cns\n","season"))
for (i in seq_len(nrow(loso_comp))) {
  r <- loso_comp[i,]
  cat(sprintf("  %-9s  %5g  %4g  %6g  %5g  %4g  %.2f  %4d  %.4f  %d\n",
              r$season, r$w_sum, r$w_p, r$w_prev, r$w_inc, r$w_dp, r$score_thr,
              r$K_dp, r$dp_thr, r$n_consec))
}

## Score timelines for key seasons
cat("\n=== Score timeline for key seasons ===\n")
for (ps in c("2018-19","2024-25","2016-17","2017-18")) {
  fi   <- which(tune_seasons==ps); if (!length(fi)) next
  bp   <- loso_bp[[fi]]
  det  <- detect_hybrid(dat_hist[dat_hist$season==ps, ],
                        w_sum=bp$w_sum, w_p=bp$w_p, w_prev=bp$w_prev,
                        w_inc=bp$w_inc, w_dp=bp$w_dp, score_thr=bp$score_thr,
                        K_dp=as.integer(bp$K_dp), dp_thr=bp$dp_thr,
                        n_consec=as.integer(bp$n_consec))
  iTrue <- truth_dt$iWeek_true[truth_dt$season==ps]
  iHat  <- det$by_season$iWeek_hat
  dt    <- det$data[order(det$data$weekF), ]
  show_from <- max(13L, iTrue - 4L)
  show_to   <- if (is.na(iHat)) iTrue + 4L else max(iHat, iTrue) + 1L
  dt    <- dt[dt$weekF >= show_from & dt$weekF <= show_to, ]
  cat(sprintf("\n-- %s  true=w%02d  det=%s  diff=%s\n",
              ps, iTrue,
              if(is.na(iHat)) "MISS" else paste0("w",iHat),
              if(is.na(iHat)) "NA"   else sprintf("%+d", iHat-iTrue)))
  cat(sprintf("   params: w_sum=%g  w_p=%g  w_prev=%g  w_inc=%g  w_dp=%g  thr=%.2f  K_dp=%d  dp_thr=%.4f  n_consec=%d\n",
              bp$w_sum, bp$w_p, bp$w_prev, bp$w_inc, bp$w_dp, bp$score_thr,
              bp$K_dp, bp$dp_thr, bp$n_consec))
  cat(sprintf("   %4s  %7s  %7s  %7s  inc  dp   %7s\n","wk","p_sumK","p_sm","prev","score"))
  for (k in seq_len(nrow(dt))) {
    r <- dt[k,]
    det_m  <- if (!is.na(iHat)  && r$weekF==iHat)  " <<DET"  else ""
    true_m <- if (r$weekF==iTrue) " [TRUE]" else ""
    cat(sprintf("   w%02d  %7.4f  %7.4f  %7.4f   %s    %s  %7.3f%s%s\n",
                r$weekF,
                ifelse(is.na(r$p_sumK),0,r$p_sumK),
                ifelse(is.na(r$p_sm),0,r$p_sm),
                ifelse(is.na(r$prev),0,r$prev),
                ifelse(isTRUE(r$cond_inc),"T","F"),
                ifelse(isTRUE(r$cond_dp),"T","F"),
                ifelse(is.na(r$score),0,r$score),
                det_m, true_m))
  }
}

## 2025-26 prospective — params from fold with smallest |diff|
mode_row <- loso_comp[which.min(abs(loso_comp$diff)), ]
cat(sprintf("\n=== 2025-26 prospective (fold params from %s) ===\n", mode_row$season))
currentSeason <- tryCatch(
  getCurrentD() |> dplyr::select(-newWeek, -season),
  error=function(e) { cat("getCurrentD failed:", conditionMessage(e),"\n"); NULL }
)
if (!is.null(currentSeason)) {
  currentSeason$season <- "2025-26"
  det_cur <- detect_hybrid(currentSeason,
                           w_sum=mode_row$w_sum, w_p=mode_row$w_p,
                           w_prev=mode_row$w_prev, w_inc=mode_row$w_inc,
                           w_dp=mode_row$w_dp, score_thr=mode_row$score_thr,
                           K_dp=as.integer(mode_row$K_dp), dp_thr=mode_row$dp_thr,
                           n_consec=as.integer(mode_row$n_consec))
  iHat_cur <- det_cur$by_season$iWeek_hat
  cat(sprintf("  Detection: %s\n",
              if(is.na(iHat_cur)) "NOT YET" else paste0("w",iHat_cur)))
  dt_c <- det_cur$data[order(det_cur$data$weekF), ]
  max_wk <- max(dt_c$weekF[!is.na(dt_c$p)], na.rm=TRUE)
  dt_c   <- dt_c[dt_c$weekF>=13 & dt_c$weekF<=max_wk, ]
  cat(sprintf("   %4s  %7s  %7s  %7s  inc  dp   %7s\n","wk","p_sumK","p_sm","prev","score"))
  for (k in seq_len(nrow(dt_c))) {
    r <- dt_c[k,]
    det_m <- if (!is.na(iHat_cur) && r$weekF==iHat_cur) " <<DET" else ""
    cat(sprintf("   w%02d  %7.4f  %7.4f  %7.4f   %s    %s  %7.3f%s\n",
                r$weekF,
                ifelse(is.na(r$p_sumK),0,r$p_sumK),
                ifelse(is.na(r$p_sm),0,r$p_sm),
                ifelse(is.na(r$prev),0,r$prev),
                ifelse(isTRUE(r$cond_inc),"T","F"),
                ifelse(isTRUE(r$cond_dp),"T","F"),
                ifelse(is.na(r$score),0,r$score), det_m))
  }
}
