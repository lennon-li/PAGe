#' Flag influenza ignition week (4-rule minimal version)
#'
#' Rules:
#' 1) Core run (no w_min gating): fit>=p_thresh & d1>k1 for n_consec weeks
#'    (OR 1-week if d2 > d2_relax and core holds that week)
#' 2) Slow-start (fallback only, gated by w_min): cum_p_fit > k_c & d1 > k1 (single-week)
#' 3) Relaxed run (fallback only, gated by w_min): fit>=p_thresh & d1 > k1 for n_consec
#'    (OR 1-week if d2 > d2_relax)
#' 4) Minimal run (fallback only, gated by w_min AND weekF > w_max): fit>=p_thresh & d1 > 0 for n_consec
#'    (OR 1-week if d2 > d2_relax)
#'
#' @param df data.frame for a single season. Must include weekF, fit, d1, d1_low.
#'   If d2 is missing, the 1-week d2-relaxation is skipped.
#'   If y and N are present, cum_p_obs/cum_p_fit are computed (cum_p_fit weighted by N).
#' @param p_thresh response-scale positivity threshold for rules 1/3/4.
#' @param k1 logit-scale slope threshold.
#' @param k_c threshold for cumulative fitted positivity (rule 2).
#' @param n_consec run length for run-based rules (default 2).
#' @param current_week optional integer; if provided, only consider weekF <= current_week.
#' @param min_window exclude early/late weeks by requiring weekF in [min_window, 52-min_window].
#' @param w_min fallback start week: rules 2-4 are only considered at weekF >= w_min (and only if rule 1 fails).
#' @param w_max enable rule 4 only if weekF > w_max (default 21).
#' @param d2_relax threshold for optional 1-week relaxation when d2 exists.
#' @param manual_labels named integer vector mapping season labels (e.g. "2015-16") to
#'   manually-verified ignition weekF values. When a season is found in this vector,
#'   the algorithmic detection is bypassed and the specified week is used directly.
#'   Pass \code{NULL} to always run the algorithm. Defaults to a set of pre-verified
#'   historical labels.
#'
#' @return list(data=augmented df, ignition=1-row summary)
#'
#' @details
#' Window gate (all rules): weekF in [min_window, 52-min_window], and <= current_week if provided.
#' Fallback gate (rules 2-4 only): weekF >= w_min, and only evaluated if rule 1 fails.
#' Extra gate (rule 4 only): weekF > w_max.
#'
#' @examples
#' # Use default manual labels (bypasses algorithm for known seasons)
#' # out <- flagIgnition(season_df, p_thresh = 0.01, k1 = 0.05)
#'
#' # Force algorithmic detection for all seasons
#' # out <- flagIgnition(season_df, p_thresh = 0.01, k1 = 0.05, manual_labels = NULL)
#'
flagIgnition <- function(
  df,
  p_thresh     = 0.01,
  k1,
  k_c          = 0.01,
  n_consec     = 2L,
  current_week = NULL,
  min_window   = 10L,
  w_min        = 20L,
  w_max        = 21L,
  d2_relax     = -0.01,
  manual_labels = c(
    "2012-13" = 18L,
    "2013-14" = 20L,
    "2014-15" = 20L,
    "2015-16" = 24L,
    "2016-17" = 19L,
    "2017-18" = 20L,
    "2018-19" = 19L,
    "2019-20" = 22L,
    "2022-23" = 15L,
    "2023-24" = 20L,
    "2024-25" = 23L
  )
) {
  stopifnot(
    is.data.frame(df),
    all(c("weekF", "fit", "d1", "d1_low") %in% names(df)),
    is.numeric(p_thresh), length(p_thresh) == 1L, p_thresh > 0, p_thresh < 1,
    is.numeric(k1), length(k1) == 1L,
    is.numeric(k_c), length(k_c) == 1L, k_c > 0, k_c < 1,
    is.numeric(n_consec), length(n_consec) == 1L, n_consec >= 1,
    is.numeric(min_window), length(min_window) == 1L, min_window >= 0,
    is.numeric(w_min), length(w_min) == 1L, w_min >= 1,
    is.numeric(w_max), length(w_max) == 1L,
    is.numeric(d2_relax), length(d2_relax) == 1L
  )
  if (!is.null(current_week)) {
    stopifnot(is.numeric(current_week), length(current_week) == 1L)
    current_week <- as.integer(current_week)
  }

  df <- df[order(df$weekF), , drop = FALSE]

  # Cumulative positivity (unconditional — always computed)
  if (all(c("y", "N") %in% names(df))) {
    cum_y          <- cumsum(df$y)
    cum_N          <- cumsum(df$N)
    df$cum_p_obs   <- cum_y / cum_N
    df$cum_p_fit   <- cumsum(df$fit * df$N) / cum_N
  } else {
    df$cum_p_obs   <- NA_real_
    df$cum_p_fit   <- cumsum(df$fit) / seq_along(df$fit)
  }

  # Extract season label early (needed for manual override)
  season_val <- if ("season" %in% names(df))
    unique(as.character(df$season))[1]
  else NA_character_

  # --- Manual label override ---
  manual_iWeek <- NULL
  if (!is.null(manual_labels) && !is.null(season_val) && !is.na(season_val)) {
    if (season_val %in% names(manual_labels)) {
      manual_iWeek <- as.integer(manual_labels[[season_val]])
    }
  }

  has_d2 <- "d2" %in% names(df)

  if (!is.null(manual_iWeek)) {
    # Use manually-verified ignition week directly
    i_idx        <- which(df$weekF == manual_iWeek)[1L]
    rule_level   <- NA_integer_
    rule_name_used <- "manual"

  } else {
    # --- Algorithmic detection (unchanged) ---
    in_window <- df$weekF >= min_window & df$weekF <= (52L - min_window)
    in_time   <- if (is.null(current_week))
      rep(TRUE, nrow(df))
    else (df$weekF <= current_week)
    ok_all <- in_window & in_time

    first_run_start <- function(x, L) {
      x <- as.logical(x)
      if (!length(x) || !any(x, na.rm = TRUE)) return(NA_integer_)
      r      <- rle(x)
      ends   <- cumsum(r$lengths)
      starts <- ends - r$lengths + 1L
      run_starts <- starts[r$values & r$lengths >= L]
      if (length(run_starts)) run_starts[1] else NA_integer_
    }

    rule_name <- c("core_run", "cumfit_and_slope", "slope_run_d1_gt_k1", "slope_run_d1_gt_0")
    cand      <- rep(NA_integer_, 4L)

    core1    <- ok_all & (df$fit >= p_thresh) & (df$d1 > k1)
    cand[1]  <- first_run_start(core1, n_consec)
    if (is.na(cand[1]) && has_d2) {
      idx1b <- which(core1 & (df$d2 > d2_relax))[1]
      if (length(idx1b) && !is.na(idx1b)) cand[1] <- idx1b
    }

    i_idx      <- NA_integer_
    rule_level <- NA_integer_

    if (!is.na(cand[1])) {
      i_idx      <- cand[1]
      rule_level <- 1L
    } else {
      ok_fb  <- ok_all & (df$weekF >= w_min)
      r2     <- ok_fb & (df$cum_p_fit > k_c) & (df$d1 > k1)
      cand[2] <- which(r2)[1]

      r3     <- ok_fb & (df$fit >= p_thresh) & (df$d1 > k1)
      cand[3] <- first_run_start(r3, n_consec)
      if (is.na(cand[3]) && has_d2) {
        idx3b <- which(r3 & (df$d2 > d2_relax))[1]
        if (length(idx3b) && !is.na(idx3b)) cand[3] <- idx3b
      }

      ok_r4  <- ok_fb & (df$weekF > w_max)
      r4     <- ok_r4 & (df$fit >= p_thresh) & (df$d1 > 0)
      cand[4] <- first_run_start(r4, n_consec)
      if (is.na(cand[4]) && has_d2) {
        idx4b <- which(r4 & (df$d2 > d2_relax))[1]
        if (length(idx4b) && !is.na(idx4b)) cand[4] <- idx4b
      }

      idxs <- cand[2:4]
      levs <- 2:4
      ok   <- !is.na(idxs)
      if (any(ok)) {
        wk     <- df$weekF[idxs[ok]]
        lev_ok <- levs[ok]
        idx_ok <- idxs[ok]
        ord    <- order(wk, lev_ok)
        i_idx      <- idx_ok[ord][1]
        rule_level <- lev_ok[ord][1]
      }
    }

    rule_name_used <- if (!is.na(rule_level)) rule_name[rule_level] else NA_character_
  }

  # --- Populate df columns ---
  df$rule_level <- rule_level
  df$rule_name  <- rule_name_used
  df$iWeek      <- if (!is.na(i_idx)) df$weekF[i_idx] else NA_integer_
  df$flag       <- !is.na(i_idx) & (seq_len(nrow(df)) == i_idx)
  df$ignition   <- df$flag

  # --- Build 1-row ignition summary ---
  ign <- data.frame(
    season       = season_val,
    weekF        = if (!is.na(i_idx)) df$weekF[i_idx]    else NA_integer_,
    p            = if (!is.na(i_idx)) df$fit[i_idx]      else NA_real_,
    fit          = if (!is.na(i_idx)) df$fit[i_idx]      else NA_real_,
    d1           = if (!is.na(i_idx)) df$d1[i_idx]       else NA_real_,
    d2           = if (!is.na(i_idx) && has_d2) df$d2[i_idx] else NA_real_,
    cum_p_obs    = if (!is.na(i_idx)) df$cum_p_obs[i_idx] else NA_real_,
    cum_p_fit    = if (!is.na(i_idx)) df$cum_p_fit[i_idx] else NA_real_,
    rule_level   = rule_level,
    rule_name    = rule_name_used,
    current_week = if (is.null(current_week)) NA_integer_ else current_week,
    stringsAsFactors = FALSE
  )

  list(data = df, ignition = ign)
}
