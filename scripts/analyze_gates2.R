## Analyze gate-firing patterns per LOSO season (corrected: use weekF)
setwd("C:/Users/lennon.li/Documents/claude/PAGe")

load("data/data.RData")
source("R/ignitionTraining.R")

ign_fit <- fitIgnition(
  dat=alignedD, event_k=1L, lead=1L,
  A_pre=6L, B_post=6L, k_week=6L, k_p=8L, k_fs=4L,
  fit_base=TRUE, verbose=FALSE
)

tuned   <- readRDS("data/stage1_tuning.rds")
bp      <- tuned$best_params
compare <- tuned$compare

det <- detectIgnitionBySeason_M0v2(ign_fit, params = bp)
dt  <- det$data

gate_cols <- c("cond_sum","cond_p","cond_prev","cond_inc","cond_dp")
N_req     <- bp$N_req  # 5

cat("N_req =", N_req, "\n\n")

## ---- Per-season gate analysis using weekF -----------------------------------
rows <- lapply(seq_len(nrow(compare)), function(i) {
  s     <- compare$season[i]
  iTrue <- compare$iWeek_true[i]
  iHat  <- compare$iWeek_hat[i]
  diff  <- compare$diff[i]

  dt_s  <- dt[dt$season == s, ]
  dt_s  <- dt_s[order(dt_s$weekF), ]

  ## Detection row: weekF == iWeek_hat (ignite_flag=TRUE)
  hat_row <- dt_s[dt_s$weekF == iHat, ]

  ## First weekF each gate became TRUE (within season window w_min to w_max)
  w_min <- bp$w_min; w_max <- bp$w_max
  dt_w  <- dt_s[dt_s$weekF >= w_min & dt_s$weekF <= w_max, ]
  first_fire <- sapply(gate_cols, function(g) {
    if (!g %in% names(dt_w)) return(NA_integer_)
    wks <- dt_w$weekF[isTRUE(dt_w[[g]]) | dt_w[[g]] == TRUE]
    if (length(wks) == 0) return(NA_integer_)
    as.integer(min(wks, na.rm=TRUE))
  })

  ## Gates TRUE at detection weekF
  at_hat  <- sapply(gate_cols, function(g) {
    if (!g %in% names(hat_row) || nrow(hat_row) == 0) return(FALSE)
    isTRUE(hat_row[[g]][1])
  })
  names(at_hat) <- gate_cols

  ## Binding gate = last to fire among those TRUE at detection
  ff_at_hat <- first_fire[at_hat]
  binding   <- if (length(ff_at_hat) == 0 || all(is.na(ff_at_hat))) "?" else
                 names(which.max(ff_at_hat))

  ## n_hit and p_sm at detection
  n_hit_hat <- if ("n_hit" %in% names(hat_row) && nrow(hat_row) > 0) hat_row$n_hit[1] else NA
  p_sm_hat  <- if ("p_sm"  %in% names(hat_row) && nrow(hat_row) > 0) round(hat_row$p_sm[1]*100, 3) else NA

  data.frame(
    season       = s,
    iTrue        = iTrue,
    iHat         = iHat,
    diff         = diff,
    p_sm_pct     = p_sm_hat,
    n_hit        = n_hit_hat,
    binding_gate = binding,
    sum_ff       = first_fire["cond_sum"],
    p_ff         = first_fire["cond_p"],
    prev_ff      = first_fire["cond_prev"],
    inc_ff       = first_fire["cond_inc"],
    dp_ff        = first_fire["cond_dp"],
    stringsAsFactors = FALSE, row.names = NULL
  )
})
res_df <- do.call(rbind, rows)

cat("=== Per-season gate firing (ff = first weekF gate became TRUE within w_min:w_max) ===\n\n")
print(res_df, row.names=FALSE)

## Relative first-fire (relative to iHat)
cat("\n=== Relative first-fire (ff - iHat; negative = fired before detection) ===\n\n")
ff_cols    <- c("sum_ff","p_ff","prev_ff","inc_ff","dp_ff")
gate_short <- c("sum","p","prev","inc","dp")
rel_df <- data.frame(season=res_df$season, iHat=res_df$iHat, diff=res_df$diff, binding=res_df$binding_gate)
for (j in seq_along(ff_cols)) {
  rel_df[[gate_short[j]]] <- res_df[[ff_cols[j]]] - res_df$iHat
}
print(rel_df, row.names=FALSE)

cat("\n=== Binding gate frequency ===\n")
print(table(res_df$binding_gate))

cat("\n=== Gate-level summary (relative to iHat; negative = fires before detection) ===\n")
for (j in seq_along(gate_cols)) {
  g   <- gate_cols[j]
  col <- ff_cols[j]
  rel <- res_df[[col]] - res_df$iHat
  n_bind <- sum(res_df$binding_gate == g, na.rm=TRUE)
  cat(sprintf("  %-12s  mean=%+.1f  range=[%+d,%+d]  n_binding=%d\n",
              g, mean(rel, na.rm=TRUE),
              as.integer(min(rel, na.rm=TRUE)),
              as.integer(max(rel, na.rm=TRUE)),
              n_bind))
}

cat("\n=== Gate states AT detection weekF ===\n")
for (i in seq_len(nrow(compare))) {
  s    <- compare$season[i]
  iHat <- compare$iWeek_hat[i]
  dt_s <- dt[dt$season == s & dt$weekF == iHat, ]
  flags <- sapply(gate_cols, function(g) if (isTRUE(dt_s[[g]][1])) "T" else "F")
  n_h  <- if ("n_hit" %in% names(dt_s)) dt_s$n_hit[1] else NA
  p_h  <- if ("p_sm"  %in% names(dt_s)) round(dt_s$p_sm[1]*100,3) else NA
  cat(sprintf("  %s (det=w%02d, true=w%02d, diff=%+d, p_sm=%.3f%%): %s  n_hit=%d\n",
              s, iHat, compare$iWeek_true[i], compare$diff[i], p_h,
              paste(paste0(sub("cond_","",gate_cols),"=",flags), collapse="  "),
              n_h))
}

## Week-by-week for all seasons: show w_min to iHat+2
cat("\n=== Week-by-week gate timeline (w13 to detection+2) ===\n")
for (i in seq_len(nrow(compare))) {
  s    <- compare$season[i]
  iHat <- compare$iWeek_hat[i]
  iTrue<- compare$iWeek_true[i]
  dt_s <- dt[dt$season == s & dt$weekF >= 13 & dt$weekF <= iHat+2, ]
  dt_s <- dt_s[order(dt_s$weekF), ]
  cat(sprintf("\n-- %s (det=w%02d, true=w%02d, diff=%+d) --\n", s, iHat, iTrue, iHat-iTrue))
  for (k in seq_len(nrow(dt_s))) {
    row   <- dt_s[k, ]
    flags <- sapply(gate_cols, function(g) if (isTRUE(row[[g]])) "T" else "F")
    n_h   <- if (!is.na(row$n_hit)) as.integer(row$n_hit) else 0
    p_v   <- if (!is.na(row$p_sm)) sprintf("%.3f", row$p_sm*100) else "NA"
    det_m <- if (row$weekF == iHat)  " <<DET" else ""
    true_m<- if (row$weekF == iTrue) " [TRUE]" else ""
    cat(sprintf("  w%02d p=%s%%  %s  vote=%d%s%s\n",
                row$weekF, p_v,
                paste(paste0(sub("cond_","",gate_cols),"=",flags), collapse=" "),
                n_h, det_m, true_m))
  }
}
