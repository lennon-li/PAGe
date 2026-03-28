## Continuous scoring: replace binary yes/no with "how much"
## Each gate outputs a ratio score [0, cap], weighted sum >= threshold fires detection.
##
## Score definitions (all prospective):
##   s_sum  = min(p_sumK   / p_sum_thr,  cap)
##   s_p    = min(p_sm     / p_thr,      cap)
##   s_prev = min(prev     / prev_thr,   cap)
##   s_inc  = proportion of recent k_inc weeks with dp > -eps  (0 to 1)
##   s_dp   = min(max(0, (p_sm - p_sm_lag) / dp_thr),  cap)
##
## Total = w_sum*s_sum + w_p*s_p + w_prev*s_prev + w_inc*s_inc + w_dp*s_dp
## Fire when total >= score_thr  AND  w_min <= week <= w_max

setwd("C:/Users/lennon.li/Documents/claude/PAGe")
suppressPackageStartupMessages({
  library(data.table); library(dplyr); library(magrittr)
  library(tidyr); library(lubridate); library(MMWRweek)
  library(future); library(furrr)
})
load("data/data.RData")
source("R/ignitionTraining.R")
source("R/getCurrentD.R")

ign_fit <- fitIgnition(
  dat=alignedD, event_k=1L, lead=1L,
  A_pre=6L, B_post=6L, k_week=6L, k_p=8L, k_fs=4L,
  fit_base=TRUE, verbose=FALSE
)

## --------------------------------------------------------------------------
## Core detection function: continuous scoring mode
## --------------------------------------------------------------------------
detect_continuous <- function(dat,
                              p_thr, prev_thr, p_sum_thr, dp_thr,
                              w_sum, w_p, w_prev, w_inc, w_dp,
                              score_thr, cap = 2,
                              K_sum=5L, K_dp=4L, L=2L, eps=0,
                              n_consec=3L, w_min=13L, w_max=30L,
                              season_col="season", week_col="weekF",
                              y_col="y", N_col="N") {
  DT <- data.table::as.data.table(data.table::copy(dat))
  data.table::setorderv(DT, c(season_col, week_col))

  # prevalence
  DT[, cum_y := cumsum(get(y_col)), by=season_col]
  DT[, cum_N := cumsum(get(N_col)), by=season_col]
  DT[, prev  := fifelse(cum_N > 0, cum_y / cum_N, NA_real_)]

  # rolling sum
  DT[, p0    := fifelse(is.na(p), 0, p)]
  DT[, p_sumK:= frollsum(p0, n=K_sum, align="right", fill=NA_real_), by=season_col]

  # smoothed level + velocity
  DT[, p_sm     := frollmean(p, n=L, align="right", fill=NA_real_), by=season_col]
  DT[, dp       := p_sm - shift(p_sm, 1L, type="lag"), by=season_col]
  DT[, p_sm_lag := shift(p_sm, K_dp, type="lag"), by=season_col]

  # trend: proportion of recent k_inc weeks with dp > -eps
  k_inc    <- max(1L, n_consec - 1L)
  need_inc <- max(1L, k_inc - 1L)
  DT[, inc := as.integer(dp > -eps)]
  DT[, inc_roll := frollsum(inc, n=k_inc, align="right", fill=NA_real_), by=season_col]

  # continuous scores (clipped to [0, cap])
  clip <- function(x, lo=0, hi=cap) pmin(pmax(x, lo), hi)
  DT[, s_sum  := clip(p_sumK / p_sum_thr)]
  DT[, s_p    := clip(p_sm   / p_thr)]
  DT[, s_prev := clip(prev   / prev_thr)]
  DT[, s_inc  := clip(inc_roll / k_inc, lo=0, hi=1)]
  DT[, s_dp   := clip(fifelse(!is.na(p_sm_lag),
                              (p_sm - p_sm_lag) / dp_thr, 0), lo=0)]

  # total score and detection
  DT[, score     := w_sum*s_sum + w_p*s_p + w_prev*s_prev + w_inc*s_inc + w_dp*s_dp]
  DT[, cond_win  := get(week_col) >= w_min & get(week_col) <= w_max]
  DT[, ignite_ok := cond_win & !is.na(score) & score >= score_thr]

  by_hat <- DT[ignite_ok==TRUE, .(iWeek_hat=min(get(week_col),na.rm=TRUE)), by=season_col]
  all_s  <- DT[, .(season_tmp=unique(get(season_col)))]
  setnames(all_s,"season_tmp",season_col)
  by_hat <- merge(all_s, by_hat, by=season_col, all.x=TRUE, sort=FALSE)
  list(by_season=as.data.frame(by_hat), data=as.data.frame(DT))
}

## --------------------------------------------------------------------------
## LOSO with continuous scoring
## --------------------------------------------------------------------------
dat_hist    <- ign_fit$data
exS         <- c("2011-12","2015-16","2020-21","2021-22","2025-26")
all_seasons <- unique(dat_hist$season)
tune_seasons<- setdiff(all_seasons, exS)

## Truth
truth_dt <- dat_hist[dat_hist$phase==1,] |>
  group_by(season) |> summarise(iWeek_true=min(weekF,na.rm=TRUE), .groups="drop") |>
  as.data.frame()

## Grid: tune core thresholds + weights + global score_thr
## Fix weights from binding analysis, tune thresholds + score_thr
grid_cont <- data.table::CJ(
  p_thr     = c(0.006, 0.007, 0.009),
  prev_thr  = c(0.004, 0.005, 0.006),
  p_sum_thr = c(0.03, 0.04, 0.05),
  dp_thr    = c(0.010, 0.015, 0.020),
  w_sum=1.0, w_p=0.8, w_prev=0.8, w_inc=0.2, w_dp=2.0,
  score_thr = c(3.5, 4.0, 4.5, 5.0),
  cap       = 2.0,
  K_sum=5L, K_dp=4L, L=2L, eps=0, n_consec=3L,
  w_min=13L, w_max=30L, sorted=FALSE
)
cat("Continuous score grid:", nrow(grid_cont), "rows\n")

## LOSO loop (parallel)
plan(multisession, workers=parallel::detectCores()-1)
loss_fn <- function(diff) sum(pmax(diff-2,0)) + 3*sum(diff < -2) + sum(abs(diff))

loso_results <- furrr::future_map(tune_seasons, function(held_out) {
  train_s <- setdiff(tune_seasons, held_out)
  train_d <- dat_hist[dat_hist$season %in% train_s,]
  truth_tr<- truth_dt[truth_dt$season %in% train_s,]

  best_loss <- Inf; best_i <- 1L
  for (i in seq_len(nrow(grid_cont))) {
    g <- as.list(grid_cont[i,])
    det <- detect_continuous(train_d,
                             p_thr=g$p_thr, prev_thr=g$prev_thr,
                             p_sum_thr=g$p_sum_thr, dp_thr=g$dp_thr,
                             w_sum=g$w_sum, w_p=g$w_p, w_prev=g$w_prev,
                             w_inc=g$w_inc, w_dp=g$w_dp,
                             score_thr=g$score_thr, cap=g$cap,
                             K_sum=g$K_sum, K_dp=g$K_dp, L=g$L, eps=g$eps,
                             n_consec=g$n_consec, w_min=g$w_min, w_max=g$w_max)
    comp <- merge(det$by_season, truth_tr, by="season")
    comp$diff <- comp$iWeek_hat - comp$iWeek_true
    lss <- loss_fn(comp$diff[!is.na(comp$diff)]) +
           1000*sum(is.na(comp$iWeek_hat))
    if (lss < best_loss) { best_loss <- lss; best_i <- i }
  }
  as.list(grid_cont[best_i,])
}, .options=furrr::furrr_options(seed=TRUE))
plan(sequential)

## Evaluate each fold on held-out season
cat("\n=== LOSO continuous score results ===\n\n")
held_results <- lapply(seq_along(tune_seasons), function(fi) {
  s  <- tune_seasons[fi]
  bp <- loso_results[[fi]]
  held_d <- dat_hist[dat_hist$season == s,]
  det <- detect_continuous(held_d,
                           p_thr=bp$p_thr, prev_thr=bp$prev_thr,
                           p_sum_thr=bp$p_sum_thr, dp_thr=bp$dp_thr,
                           w_sum=bp$w_sum, w_p=bp$w_p, w_prev=bp$w_prev,
                           w_inc=bp$w_inc, w_dp=bp$w_dp,
                           score_thr=bp$score_thr, cap=bp$cap,
                           K_sum=bp$K_sum, K_dp=bp$K_dp, L=bp$L, eps=bp$eps,
                           n_consec=bp$n_consec, w_min=bp$w_min, w_max=bp$w_max)
  iTrue <- truth_dt$iWeek_true[truth_dt$season==s]
  iHat  <- det$by_season$iWeek_hat
  data.frame(season=s, iWeek_true=iTrue, iWeek_hat=iHat,
             diff=iHat-iTrue, score_thr=bp$score_thr,
             p_thr=bp$p_thr, prev_thr=bp$prev_thr, dp_thr=bp$dp_thr)
})
loso_comp <- do.call(rbind, held_results)
loso_comp <- loso_comp[order(loso_comp$iWeek_true),]

## Compare to binary
compare_bin <- readRDS("data/stage1_tuning.rds")$compare
compare_bin <- compare_bin[!compare_bin$season %in% exS,]

merged <- merge(compare_bin[,c("season","iWeek_true","iWeek_hat","diff")],
                loso_comp[,c("season","iWeek_hat","diff","score_thr")],
                by="season", suffixes=c("_bin","_cont"))
merged <- merged[order(merged$iWeek_true),]

cat(sprintf("  %-9s  %4s  %11s  %14s  %6s\n",
            "season","true","binary","continuous","delta"))
cat(strrep("-",58),"\n")
for (i in seq_len(nrow(merged))) {
  r <- merged[i,]
  delta <- r$iWeek_hat_cont - r$iWeek_hat_bin
  flag  <- if (delta != 0) " **" else ""
  cat(sprintf("  %-9s  w%02d  w%02d (%+d)     w%02d (%+d,thr=%.1f)  %+d%s\n",
              r$season, r$iWeek_true,
              r$iWeek_hat_bin, r$diff_bin,
              r$iWeek_hat_cont, r$diff_cont, r$score_thr,
              delta, flag))
}
cat(strrep("-",58),"\n")
cat(sprintf("  MAE:          %.2f          %.2f\n\n",
            mean(abs(merged$diff_bin),na.rm=TRUE),
            mean(abs(merged$diff_cont),na.rm=TRUE)))

## Score timeline for problem seasons
cat("=== Score timeline for key seasons (best fold params) ===\n")
prob_seasons <- c("2018-19","2024-25","2016-17")
for (ps in prob_seasons) {
  fi <- which(tune_seasons==ps)
  if (length(fi)==0) next
  bp <- loso_results[[fi]]
  dt_s <- dat_hist[dat_hist$season==ps,]
  det  <- detect_continuous(dt_s,
                            p_thr=bp$p_thr, prev_thr=bp$prev_thr,
                            p_sum_thr=bp$p_sum_thr, dp_thr=bp$dp_thr,
                            w_sum=bp$w_sum, w_p=bp$w_p, w_prev=bp$w_prev,
                            w_inc=bp$w_inc, w_dp=bp$w_dp,
                            score_thr=bp$score_thr, cap=bp$cap,
                            K_sum=bp$K_sum, K_dp=bp$K_dp, L=bp$L, eps=bp$eps,
                            n_consec=bp$n_consec, w_min=bp$w_min, w_max=bp$w_max)
  iTrue <- truth_dt$iWeek_true[truth_dt$season==ps]
  iHat  <- det$by_season$iWeek_hat
  dt_out <- det$data
  dt_out <- dt_out[order(dt_out$weekF),]
  dt_show<- dt_out[dt_out$weekF>=max(13,iTrue-2) & dt_out$weekF<=iHat+1,]
  cat(sprintf("\n-- %s (true=w%02d, detected=w%02d, diff=%+d, thr=%.1f) --\n",
              ps, iTrue, iHat, iHat-iTrue, bp$score_thr))
  cat(sprintf("   %4s  %6s  %5s  %5s  %5s  %5s  %5s  %7s\n",
              "week","p_sm%","s_sum","s_p","s_prev","s_inc","s_dp","score"))
  for (k in seq_len(nrow(dt_show))) {
    r <- dt_show[k,]
    det_m <- if (!is.na(iHat) && r$weekF==iHat)  " <<DET" else ""
    true_m<- if (r$weekF==iTrue) " [TRUE]" else ""
    cat(sprintf("   w%02d  %6.3f  %5.2f  %5.2f  %5.2f  %5.2f  %5.2f  %7.2f%s%s\n",
                r$weekF, ifelse(is.na(r$p_sm),0,r$p_sm*100),
                ifelse(is.na(r$s_sum),0,r$s_sum),
                ifelse(is.na(r$s_p),0,r$s_p),
                ifelse(is.na(r$s_prev),0,r$s_prev),
                ifelse(is.na(r$s_inc),0,r$s_inc),
                ifelse(is.na(r$s_dp),0,r$s_dp),
                ifelse(is.na(r$score),0,r$score),
                det_m, true_m))
  }
}

## 2025-26 prospective
cat("\n=== 2025-26 prospective (modal fold params) ===\n")
## Use params that appear most often in LOSO folds
modal_params <- as.list(loso_comp[which.min(abs(loso_comp$diff)),
                                   c("score_thr")])
## Use first fold params as representative
bp_rep <- loso_results[[1]]

currentSeason <- tryCatch(
  getCurrentD() |> dplyr::select(-newWeek, -season),
  error=function(e) { cat("getCurrentD failed:", conditionMessage(e), "\n"); NULL }
)
if (!is.null(currentSeason)) {
  currentSeason$season <- "2025-26"
  cur_dt <- as.data.frame(currentSeason)
  det_cur <- detect_continuous(cur_dt,
                               p_thr=bp_rep$p_thr, prev_thr=bp_rep$prev_thr,
                               p_sum_thr=bp_rep$p_sum_thr, dp_thr=bp_rep$dp_thr,
                               w_sum=bp_rep$w_sum, w_p=bp_rep$w_p,
                               w_prev=bp_rep$w_prev, w_inc=bp_rep$w_inc,
                               w_dp=bp_rep$w_dp, score_thr=bp_rep$score_thr,
                               cap=bp_rep$cap,
                               K_sum=bp_rep$K_sum, K_dp=bp_rep$K_dp, L=bp_rep$L,
                               eps=bp_rep$eps, n_consec=bp_rep$n_consec,
                               w_min=bp_rep$w_min, w_max=bp_rep$w_max)
  iHat_cur <- det_cur$by_season$iWeek_hat
  cat(sprintf("  Detection: %s (thr=%.1f)\n",
              if(is.na(iHat_cur)) "NOT YET" else paste0("w",iHat_cur), bp_rep$score_thr))
  dt_c <- det_cur$data[order(det_cur$data$weekF),]
  max_wk <- max(dt_c$weekF[!is.na(dt_c$p)], na.rm=TRUE)
  dt_c   <- dt_c[dt_c$weekF>=13 & dt_c$weekF<=max_wk,]
  cat(sprintf("   %4s  %6s  %5s  %5s  %5s  %5s  %5s  %7s\n",
              "week","p_sm%","s_sum","s_p","s_prev","s_inc","s_dp","score"))
  for (k in seq_len(nrow(dt_c))) {
    r <- dt_c[k,]
    det_m <- if (!is.na(iHat_cur) && r$weekF==iHat_cur) " <<DET" else ""
    cat(sprintf("   w%02d  %6.3f  %5.2f  %5.2f  %5.2f  %5.2f  %5.2f  %7.2f%s\n",
                r$weekF, ifelse(is.na(r$p_sm),0,r$p_sm*100),
                ifelse(is.na(r$s_sum),0,r$s_sum),
                ifelse(is.na(r$s_p),0,r$s_p),
                ifelse(is.na(r$s_prev),0,r$s_prev),
                ifelse(is.na(r$s_inc),0,r$s_inc),
                ifelse(is.na(r$s_dp),0,r$s_dp),
                ifelse(is.na(r$score),0,r$score), det_m))
  }
}
