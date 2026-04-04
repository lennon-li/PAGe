## Analyze gate-firing patterns per LOSO season
setwd("C:/Users/lennon.li/Documents/claude/PAGe")

load("data/data.RData")
source("R/m0_training.R")

## Build ign_fit (same call as in QMD)
ign_fit <- fitIgnition(
  dat    = alignedD,
  event_k = 1L, lead = 1L,
  A_pre   = 6L, B_post = 6L,
  k_week  = 6L, k_p = 8L, k_fs = 4L,
  fit_base = TRUE, verbose = FALSE
)

tuned   <- readRDS("data/stage1_tuning.rds")
bp      <- tuned$best_params
compare <- tuned$compare

cat("Best params:\n"); print(unlist(bp)); cat("\n")

## Run detection on ALL seasons with best_params
det <- detectIgnitionBySeason_M0v2(ign_fit, params = bp)
dt  <- det$data

gate_cols <- c("cond_sum","cond_p","cond_prev","cond_inc","cond_dp")

## ---- Per-season gate firing analysis ----------------------------------------
rows <- lapply(seq_len(nrow(compare)), function(i) {
  s     <- compare$season[i]
  iTrue <- compare$iWeek_true[i]
  iHat  <- compare$iWeek_hat[i]
  diff  <- compare$diff[i]

  dt_s <- dt[dt$season == s, ]

  ## First week each gate became TRUE
  first_fire <- sapply(gate_cols, function(g) {
    if (!g %in% names(dt_s)) return(NA_integer_)
    wks <- dt_s$iWeek[dt_s[[g]] == TRUE]
    if (length(wks) == 0) return(NA_integer_)
    as.integer(min(wks, na.rm=TRUE))
  })

  ## Gates TRUE at detection week
  hat_row <- dt_s[dt_s$iWeek == iHat, ]
  at_hat  <- sapply(gate_cols, function(g) {
    if (!g %in% names(hat_row) || nrow(hat_row) == 0) return(FALSE)
    isTRUE(hat_row[[g]][1])
  })
  names(at_hat) <- gate_cols

  ## Binding gate = last to fire among those TRUE at detection
  ff_at_hat <- first_fire[at_hat]
  binding   <- if (length(ff_at_hat) == 0 || all(is.na(ff_at_hat))) "?" else
                 names(which.max(ff_at_hat))

  ## p_sm value at detection week
  p_at_hat <- if ("p_sm" %in% names(hat_row) && nrow(hat_row) > 0)
                round(hat_row$p_sm[1]*100, 3) else NA

  data.frame(
    season       = s,
    iTrue        = iTrue,
    iHat         = iHat,
    diff         = diff,
    p_sm_pct     = p_at_hat,
    binding_gate = binding,
    sum_ff       = first_fire["cond_sum"],
    p_ff         = first_fire["cond_p"],
    prev_ff      = first_fire["cond_prev"],
    inc_ff       = first_fire["cond_inc"],
    dp_ff        = first_fire["cond_dp"],
    n_TRUE       = sum(at_hat, na.rm=TRUE),
    stringsAsFactors = FALSE, row.names = NULL
  )
})
res_df <- do.call(rbind, rows)

cat("=== Per-season gate firing (ff = first-fire week) ===\n\n")
print(res_df, row.names=FALSE)

## Relative first-fire
cat("\n=== Relative first-fire (first-fire MINUS iHat; negative = fired early, 0 = binding) ===\n\n")
ff_cols  <- c("sum_ff","p_ff","prev_ff","inc_ff","dp_ff")
gate_short <- c("sum","p","prev","inc","dp")
rel_df <- data.frame(season=res_df$season, diff=res_df$diff)
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

cat("\n=== Gate states AT detection week ===\n")
for (i in seq_len(nrow(compare))) {
  s    <- compare$season[i]
  iHat <- compare$iWeek_hat[i]
  dt_s <- dt[dt$season == s & dt$iWeek == iHat, ]
  flags <- sapply(gate_cols, function(g) if (isTRUE(dt_s[[g]][1])) "T" else "F")
  cat(sprintf("  %s (w%02d, true=w%02d, diff=%+d): %s\n",
              s, iHat, compare$iWeek_true[i], compare$diff[i],
              paste(paste0(sub("cond_","",gate_cols),"=",flags), collapse="  ")))
}

## Also show week-by-week for seasons with diff > 2 or < -1 (problematic)
prob_seasons <- compare$season[abs(compare$diff) >= 2]
cat("\n=== Week-by-week gate timeline for |diff|>=2 seasons ===\n")
for (s in prob_seasons) {
  cat(sprintf("\n-- %s (diff=%+d) --\n", s,
              compare$diff[compare$season == s]))
  dt_s <- dt[dt$season == s & dt$iWeek >= 10 & dt$iWeek <= 30, ]
  iHat  <- compare$iWeek_hat[compare$season == s]
  iTrue <- compare$iWeek_true[compare$season == s]
  for (k in seq_len(nrow(dt_s))) {
    row <- dt_s[k, ]
    flags <- sapply(gate_cols, function(g) if (isTRUE(row[[g]])) "T" else "F")
    marker <- ""
    if (row$iWeek == iHat)  marker <- " << DETECTED"
    if (row$iWeek == iTrue) marker <- paste0(marker, " [TRUE ONSET]")
    p_sm_val <- if ("p_sm" %in% names(row)) sprintf("p_sm=%.3f", row$p_sm*100) else ""
    cat(sprintf("  w%02d %s  %s  vote=%d%s\n",
                row$iWeek, p_sm_val,
                paste(paste0(sub("cond_","",gate_cols),"=",flags), collapse=" "),
                sum(unlist(row[,gate_cols])==TRUE, na.rm=TRUE),
                marker))
  }
}
