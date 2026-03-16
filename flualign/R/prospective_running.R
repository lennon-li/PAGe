# Prospective running utilities
# - Weekly/online ignition tracking and Stage-2 prospective execution helpers
# - Designed for current-season runs

#' Number of epidemiological weeks in a full season cycle
#'
#' Returns 52 or 53 depending on the ISO epidemiological week structure of the given year.
#' Uses the epidemiological week number of Dec 28, which is always in the last epiweek
#' of the year.
#'
#' @param year Integer calendar year (e.g., 2026).
#'
#' @return Integer, typically 52 or 53.
#' @export
#'
#' @examples
#' \dontrun{
#' get_full_cycle_weeks(2025)
#' get_full_cycle_weeks(2026)
#' }
get_full_cycle_weeks <- function(year) {
  # epiweek() is provided by lubridate
  max_weeks_this_year <- lubridate::epiweek(as.Date(paste0(as.integer(year), "-12-28")))
  # Weeks remaining after Week 20: (Max - 20) plus the 20 weeks of the following year
  (max_weeks_this_year - 20) + 20
}

#' Null-coalescing operator
#'
#' Returns \code{y} when \code{x} is \code{NULL}, otherwise returns \code{x}.
#'
#' @param x Any object.
#' @param y Fallback value used when \code{x} is \code{NULL}.
#'
#' @return \code{x} if not \code{NULL}, else \code{y}.
#' @keywords internal
#' @noRd
`%||%` <- function(x, y) if (!is.null(x)) x else y

#' Stable logit transform with clipping
#'
#' @param p Numeric in [0,1].
#' @param eps Clip to \code{[eps, 1-eps]} before applying \code{qlogis()}.
#'
#' @return Numeric logit-transformed values.
#' @keywords internal
#' @noRd
logit_stable <- function(p, eps = 1e-6) qlogis(pmin(pmax(p, eps), 1 - eps))

#' Extract a classifier GAM from various container objects
#'
#' Convenience helper that accepts either:
#' \itemize{
#' \item an \pkg{mgcv} \code{gam}/\code{bam} object;
#' \item a \code{gamm4} fit list with component \code{$gam};
#' \item a list returned by your \code{fitIgnition()} that contains
#'   \code{$fits$p_only_week_p$gam}.
#' }
#'
#' @param ign_fit_or_gam A trained classifier model or a container holding one.
#'
#' @return An \pkg{mgcv} \code{gam} or \code{bam} object.
#' @export
#'
#' @examples
#' \dontrun{
#' gam_cls <- get_gam_cls(ign_fit)                        # fitIgnition() output
#' gam_cls <- get_gam_cls(ign_fit$fits$p_only_week_p$gam) # direct
#' }
get_gam_cls <- function(ign_fit_or_gam) {
  if (inherits(ign_fit_or_gam, c("gam", "bam"))) return(ign_fit_or_gam)
  
  # gamm4 style list
  if (is.list(ign_fit_or_gam) &&
      "gam" %in% names(ign_fit_or_gam) &&
      inherits(ign_fit_or_gam$gam, c("gam", "bam"))) {
    return(ign_fit_or_gam$gam)
  }
  
  # fitIgnition style list
  if (is.list(ign_fit_or_gam) &&
      "fits" %in% names(ign_fit_or_gam) &&
      "p_only_week_p" %in% names(ign_fit_or_gam$fits) &&
      "gam" %in% names(ign_fit_or_gam$fits$p_only_week_p) &&
      inherits(ign_fit_or_gam$fits$p_only_week_p$gam, c("gam", "bam"))) {
    return(ign_fit_or_gam$fits$p_only_week_p$gam)
  }
  
  stop("Could not extract a GAM classifier. Pass a mgcv::gam/bam, a gamm4 list with $gam, or your full fitIgnition() output.")
}

#' Resolve a week estimate with an optional manual override
#'
#' Applies an override week to an estimated week using a selected policy:
#' \itemize{
#' \item \code{"replace"}: force the week to the override.
#' \item \code{"cap"}: final week cannot be later than override (\code{min(est, override)}).
#' \item \code{"floor"}: final week cannot be earlier than override (\code{max(est, override)}).
#' \item \code{"nearest_valid"}: snap override to the nearest value in \code{valid_weeks}.
#' }
#'
#' @param week_est Integer-ish scalar estimate (can be \code{NA}).
#' @param override_week Optional integer-ish scalar override (can be \code{NULL}/\code{NA}).
#' @param mode Override policy.
#' @param valid_weeks Integer vector of valid week values. Default 1:52.
#'
#' @return A list with elements \code{final}, \code{est}, \code{overridden}, \code{override}.
#' @export
#'
#' @examples
#' resolve_week_override(18, NULL)
#' resolve_week_override(18, 20, mode = "cap")
#' resolve_week_override(NA, 15, mode = "replace")
resolve_week_override <- function(week_est,
                                  override_week = NULL,
                                  mode = c("replace", "cap", "floor", "nearest_valid"),
                                  valid_weeks = 1:52) {
  mode <- match.arg(mode)
  est <- as.integer(week_est)
  
  if (is.null(override_week) || is.na(override_week)) {
    return(list(final = est, est = est, overridden = FALSE, override = NA_integer_))
  }
  
  ov <- as.integer(override_week)
  
  if (mode == "nearest_valid") {
    ov <- valid_weeks[which.min(abs(valid_weeks - ov))]
    return(list(final = ov, est = est, overridden = TRUE, override = ov))
  }
  
  ov <- max(min(ov, max(valid_weeks)), min(valid_weeks))
  final <- switch(
    mode,
    replace = ov,
    cap     = if (is.na(est)) ov else pmin(est, ov),
    floor   = if (is.na(est)) ov else pmax(est, ov)
  )
  
  list(final = as.integer(final), est = est, overridden = TRUE, override = ov)
}

#' Run pseudo real-time ignition detection and report threshold conditions weekly
#'
#' Starting at \code{start_week}, iteratively processes each observed week in the
#' current season. At each processed week \code{w}, it:
#' \enumerate{
#' \item takes rows with \code{weekF <= w};
#' \item predicts \code{p_cls_p} using a trained classifier GAM;
#' \item calls \code{detectIgnition_oneSeason()} on that partial data;
#' \item records whether each threshold condition is met (based on \code{params});
#' \item records \code{iWeek_hat_dynamic} returned by the detector (can vary across weeks).
#' }
#'
#' The returned list includes:
#' \itemize{
#' \item \code{df}: a data frame with one row per processed week.
#' \item \code{iWeek_hat_dynamic_last}: detector's \code{iWeek_hat} at the last processed week.
#' \item \code{iWeek_hat_locked}: the first non-NA \code{iWeek_hat_dynamic} (a "first-hit lock").
#' \item \code{ign_week_locked}: the first processed week where \code{ignite_ok_now} is TRUE.
#' }
#'
#' @param currentSeason Data frame/tibble for one season. Must contain \code{y} and
#'   either \code{neg} or \code{N}, and a within-season week column (default \code{weekF}).
#'   If \code{p} exists, it is used; otherwise \code{p = y/(y+neg)} is computed.
#' @param ign_fit_or_gam A trained classifier GAM (mgcv \code{gam}/\code{bam}) or
#'   an object containing one (see \code{\link{get_gam_cls}}).
#' @param params List of tuned threshold parameters used by your detector.
#'   Common names include \code{cls_thr}, \code{p_cum_thr}, \code{p_thr},
#'   \code{prev_thr}, \code{n_consec}, \code{w_min}, \code{w_max}.
#'   Missing thresholds are reported as \code{NA} conditions.
#' @param start_week Integer. First \code{weekF} to start producing output rows.
#'   Earlier weeks are still used as history when slicing \code{weekF <= w}.
#' @param week_col Name of the within-season week column in \code{currentSeason}.
#' @return A list with components \code{df}, \code{iWeek_hat_dynamic_last},
#'   \code{iWeek_hat_locked}, \code{ign_week_locked}.
#' @export
run_ignition_weekly <- function(currentSeason,
                                ign_fit_or_gam = NULL,
                                params,
                                start_week = 5L,
                                week_col = "weekF") {
  stopifnot(is.data.frame(currentSeason), is.list(params))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Please install tibble.")

  if (!exists("detectIgnition_oneSeason", mode = "function")) {
    stop("detectIgnition_oneSeason() was not found. Source your Stage-1 file before calling this function.")
  }

  use_cls <- isTRUE(params$use_cls)
  if (!is.null(ign_fit_or_gam)) {
    gam_cls <- get_gam_cls(ign_fit_or_gam)
  } else if (use_cls) {
    stop("ign_fit_or_gam must be provided when params$use_cls = TRUE")
  } else {
    gam_cls <- NULL
  }
  
  d0 <- dplyr::as_tibble(currentSeason) %>%
    dplyr::transmute(
      season = if ("season" %in% names(.)) as.character(.data$season) else NA_character_,
      weekF  = as.integer(.data[[week_col]]),
      y      = as.integer(.data$y),
      N      = if ("N" %in% names(.)) as.integer(.data$N) else as.integer(.data$y + .data$neg),
      neg    = if ("neg" %in% names(.)) as.integer(.data$neg) else as.integer(.data$N - .data$y),
      p      = if ("p" %in% names(.)) as.numeric(.data$p) else .data$y / pmax(.data$y + .data$neg, 1L)
    ) %>%
    dplyr::filter(!is.na(.data$weekF), is.finite(.data$weekF), .data$weekF >= 1L) %>%
    dplyr::mutate(weekF = pmin(.data$weekF, 52L)) %>%
    dplyr::arrange(.data$weekF) %>%
    dplyr::group_by(.data$season, .data$weekF) %>%
    dplyr::summarise(
      y = sum(.data$y, na.rm = TRUE),
      N = sum(.data$N, na.rm = TRUE),
      neg = sum(.data$neg, na.rm = TRUE),
      p = .data$y / pmax(.data$y + .data$neg, 1L),
      .groups = "drop"
    )
  
  weeks_all  <- sort(unique(d0$weekF))
  weeks_eval <- weeks_all[weeks_all >= as.integer(start_week)]
  if (!length(weeks_eval)) {
    out_df <- tibble::tibble(weekF = integer(), iWeek_hat_dynamic = integer())
    return(list(
      df = out_df,
      iWeek_hat_dynamic_last = NA_integer_,
      iWeek_hat_locked = NA_integer_,
      ign_week_locked = NA_integer_
    ))
  }
  
  rows <- lapply(weeks_eval, function(w) {
    d_now <- d0 %>%
      dplyr::filter(.data$weekF <= w) %>%
      dplyr::mutate(p_cls_p = if (!is.null(gam_cls))
        as.numeric(stats::predict(gam_cls, newdata = ., type = "response"))
      else
        0)
    
    det <- detectIgnition_oneSeason(as.data.frame(d_now), params = params)
    now <- det$now %||% data.frame()
    
    p_now_fallback       <- tail(d_now$p, 1)
    cum_p_now_fallback   <- sum(d_now$p, na.rm = TRUE)
    prev_now_fallback    <- sum(d_now$y, na.rm = TRUE) / pmax(sum(d_now$N, na.rm = TRUE), 1)
    p_cls_p_now_fallback <- tail(d_now$p_cls_p, 1)
    
    p_now       <- now$p_now       %||% p_now_fallback
    cum_p_now   <- now$cum_p_now   %||% cum_p_now_fallback
    prev_now    <- now$prev_now    %||% prev_now_fallback
    p_cls_p_now <- now$p_cls_p_now %||% p_cls_p_now_fallback
    n_hit_now   <- now$n_hit_now   %||% NA_integer_
    
    d1_last <- now$d1_last %||% NA_real_
    d2_last <- now$d2_last %||% NA_real_
    
    ok_w_inrange <- now$cond_win  %||% NA
    ok_cls       <- now$cond_cls  %||% NA
    ok_cum_p     <- now$cond_cum  %||% NA
    ok_p         <- now$cond_p    %||% NA
    ok_prev      <- now$cond_prev %||% NA
    ok_nconsec   <- now$cond_inc  %||% NA
    
    ignite_ok_now <- now$ignite_ok_now %||% NA
    
    tibble::tibble(
      weekF = as.integer(w),
      p_now = as.numeric(p_now),
      cum_p_now = as.numeric(cum_p_now),
      prev_now = as.numeric(prev_now),
      p_cls_p_now = as.numeric(p_cls_p_now),
      n_hit_now = if (is.null(n_hit_now)) NA_integer_ else as.integer(n_hit_now),
      d1_last = as.numeric(d1_last),
      d2_last = as.numeric(d2_last),
      ok_w_inrange = as.logical(ok_w_inrange),
      ok_cls = as.logical(ok_cls),
      ok_p = as.logical(ok_p),
      ok_cum_p = as.logical(ok_cum_p),
      ok_prev = as.logical(ok_prev),
      ok_n_consec = as.logical(ok_nconsec),
      ignite_ok_now = as.logical(ignite_ok_now),
      iWeek_hat_dynamic = if (is.null(det$iWeek_hat)) NA_integer_ else as.integer(det$iWeek_hat)
    )
  })
  
  df <- dplyr::bind_rows(rows)
  
  ign_week_locked <- suppressWarnings(min(df$weekF[df$ignite_ok_now %in% TRUE], na.rm = TRUE))
  ign_week_locked <- ifelse(is.infinite(ign_week_locked), NA_integer_, as.integer(ign_week_locked))
  
  iwh_locked <- suppressWarnings(min(df$iWeek_hat_dynamic, na.rm = TRUE))
  iwh_locked <- ifelse(is.infinite(iwh_locked), NA_integer_, as.integer(iwh_locked))

  list(
    df = df,
    iWeek_hat_dynamic_last = df$iWeek_hat_dynamic[nrow(df)],
    iWeek_hat_locked = iwh_locked,
    ign_week_locked = ign_week_locked
  )
}

#' Extract Stage-2 hyperparameters from tuning output
#'
#' Helper to pull commonly used Stage-2 hyperparameters from a list or 1-row data.frame,
#' supporting alternate names (e.g., \code{shift} for \code{delta}).
#'
#' @param best_mean_nll A list or 1-row data.frame containing tuned parameters. Looks for
#'   \code{delta} (or \code{shift}), \code{K}, \code{leads}, and optionally \code{use_ramp}.
#'
#' @return A list with elements \code{delta}, \code{K}, \code{leads}, \code{use_ramp}, and \code{extra}.
#' @keywords internal
#' @noRd
stage2_extract_hyperparams <- function(best_mean_nll) {
  get1 <- function(obj, nm, default = NULL) {
    if (is.list(obj) && !is.data.frame(obj) && !is.null(obj[[nm]])) return(obj[[nm]])
    if (is.data.frame(obj) && nm %in% names(obj)) return(obj[[nm]][1])
    default
  }
  
  delta    <- get1(best_mean_nll, "delta", get1(best_mean_nll, "shift", 0L))
  K        <- get1(best_mean_nll, "K", 3L)
  leads    <- get1(best_mean_nll, "leads", c(1L, 2L))
  use_ramp <- get1(best_mean_nll, "use_ramp", TRUE)
  
  extra <- list()
  if (is.list(best_mean_nll) && !is.data.frame(best_mean_nll)) {
    keep <- setdiff(names(best_mean_nll), c("delta","shift","K","leads","use_ramp"))
    extra <- best_mean_nll[keep]
  }
  
  list(
    delta = as.integer(delta),
    K = as.integer(K),
    leads = as.integer(leads),
    use_ramp = isTRUE(use_ramp),
    extra = extra
  )
}

#' Build pseudo-prospective Stage-2 snapshot list (current season)
#'
#' Creates a sequence of "as-of week" snapshots for the current season to mimic
#' online/prospective operation. Each snapshot is a data frame containing all
#' weeks \code{weekF = 1..n_weeks}, stacked by \code{lead} (e.g. \code{h1}, \code{h2}).
#'
#' For a snapshot with as-of week \code{asof_weekF}:
#' \itemize{
#'   \item Observed fields \code{y}, \code{N}, \code{neg}, \code{p}, \code{date} are
#'         present only for \code{weekF <= asof_weekF} and set to \code{NA} afterward.
#'   \item Truth fields \code{*_true} (e.g. \code{p_true}) are retained for all available
#'         weeks (retrospective evaluation).
#'   \item \code{toFit == 1} only for origin weeks up to \code{asof_weekF} and after
#'         \code{iWeek_hat - pre_buffer}.
#'   \item Stage-2 covariates are computed: \code{newWeek}, template curve columns,
#'         and prospective derivatives (\code{d1_link}, \code{d2_link}).
#' }
#'
#' Snapshot list is built only from ignition week through the most recent observed
#' week (internally defined as the max \code{weekF} with finite \code{p_true}).
#'
#' @param currentSeason One-season data.frame with at least columns \code{weekF}, \code{y},
#'   and either \code{N} or \code{neg}. Optional \code{date} column (see \code{date_col}).
#' @param template_df Data frame with columns \code{newWeek} (integer) and \code{fit}
#'   (numeric in (0,1)) defining the reference/template curve.
#' @param best_mean_nll Tuned Stage-2 hyperparameters (list or 1-row data.frame) that may
#'   contain \code{delta} (or \code{shift}), \code{K}, and \code{leads}.
#' @param iWeek_hat Integer ignition week estimate used for phase and alignment.
#' @param align Logical. If TRUE, uses aligned \code{newWeek = weekF - iWeek_hat + anchorWeek}.
#'   If FALSE, uses \code{newWeek = weekF}.
#' @param anchorWeek Integer anchor week used when \code{align=TRUE}.
#' @param pre_buffer Integer >= 0. Weeks before ignition included for \code{toFit==1} logic.
#' @param deriv_k Integer window size passed to \code{add_prospective_derivs_link()}.
#' @param n_weeks Integer. Length of the full season axis (52 or 53).
#' @param eps Numeric small constant passed to derivative calculations.
#' @param date_col Character. Name of the date column in \code{currentSeason} (default tries \code{"date"}).
#'
#' @return A list with:
#' \describe{
#'   \item{meta}{List of snapshot metadata (e.g., \code{iWeek_hat}, \code{n_weeks}, tuned \code{delta/K/leads}).}
#'   \item{df}{Named list of snapshot data.frames, each stacked by \code{lead}.}
#' }
#'
#' @export
build_stage2_pseudo_prospective_list <- function(
    currentSeason,
    template_df,
    best_mean_nll,
    iWeek_hat,
    align = TRUE,
    anchorWeek = 19L,
    pre_buffer = 1L,
    deriv_k = 5L,
    n_weeks = 53L,
    eps = 1e-6,
    date_col = if ("date" %in% names(currentSeason)) "date" else NULL
) {
  stopifnot(is.data.frame(currentSeason), is.data.frame(template_df))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!exists("add_prospective_derivs_link", mode = "function")) {
    stop("add_prospective_derivs_link() not found.")
  }
  
  get1 <- function(obj, nm, default = NULL) {
    if (is.list(obj) && !is.data.frame(obj) && !is.null(obj[[nm]])) return(obj[[nm]])
    if (is.data.frame(obj) && nm %in% names(obj)) return(obj[[nm]][1])
    default
  }
  ramp_weight <- function(t_since, K) { K <- as.integer(K); pmin(1, pmax(0, t_since / K)) }
  
  n_weeks <- as.integer(n_weeks)
  if (!n_weeks %in% c(52L, 53L)) stop("n_weeks must be 52 or 53.")
  
  delta <- as.integer(get1(best_mean_nll, "delta", get1(best_mean_nll, "shift", 0L)))
  K     <- as.integer(get1(best_mean_nll, "K", 3L))
  leads <- as.integer(get1(best_mean_nll, "leads", c(1L, 2L)))
  
  nw_min <- min(as.integer(template_df$newWeek), na.rm = TRUE)
  nw_max <- max(as.integer(template_df$newWeek), na.rm = TRUE)
  
  has_date <- !is.null(date_col) && date_col %in% names(currentSeason)
  
  d_truth <- dplyr::as_tibble(currentSeason) %>%
    dplyr::mutate(
      weekF = as.integer(.data$weekF),
      y     = as.integer(.data$y),
      N     = if ("N" %in% names(.)) as.integer(.data$N) else as.integer(.data$y + .data$neg),
      neg   = if ("neg" %in% names(.)) as.integer(.data$neg) else as.integer(.data$N - .data$y),
      date  = if (has_date) as.Date(.data[[date_col]]) else as.Date(NA)
    ) %>%
    dplyr::filter(!is.na(.data$weekF), .data$weekF >= 1L, .data$weekF <= n_weeks) %>%
    dplyr::group_by(.data$weekF) %>%
    dplyr::summarise(
      y_true   = sum(.data$y, na.rm = TRUE),
      N_true   = sum(.data$N, na.rm = TRUE),
      neg_true = sum(.data$neg, na.rm = TRUE),
      p_true   = y_true / pmax(N_true, 1L),
      date_true = {x <- date; x <- x[!is.na(x)]; if (length(x)) x[1] else as.Date(NA)},
      .groups = "drop"
    ) %>%
    dplyr::arrange(.data$weekF)
  
  max_obs_weekF <- suppressWarnings(max(d_truth$weekF[is.finite(d_truth$p_true)], na.rm = TRUE))
  if (!is.finite(max_obs_weekF)) max_obs_weekF <- 0L
  max_obs_weekF <- as.integer(max_obs_weekF)
  
  grid <- dplyr::tibble(weekF = seq.int(1L, n_weeks)) %>%
    dplyr::left_join(d_truth, by = "weekF")
  
  if (isTRUE(align)) {
    grid$newWeek_raw <- as.integer(grid$weekF - as.integer(iWeek_hat) + as.integer(anchorWeek))
  } else {
    grid$newWeek_raw <- as.integer(grid$weekF)
  }
  grid$newWeek <- pmin(pmax(grid$newWeek_raw, nw_min), nw_max)
  
  d_deriv <- add_prospective_derivs_link(
    alignedD = grid %>% dplyr::transmute(season="current", weekF, y = y_true, neg = neg_true),
    k = as.integer(deriv_k),
    eps = eps
  ) %>%
    dplyr::transmute(weekF = as.integer(.data$weekF), d1_link = .data$d1_link, d2_link = .data$d2_link)
  
  tpl <- dplyr::as_tibble(template_df) %>%
    dplyr::transmute(newWeek = as.integer(.data$newWeek), template_fit = as.numeric(.data$fit))
  tpl_shift <- dplyr::as_tibble(template_df) %>%
    dplyr::transmute(newWeek_shift = as.integer(.data$newWeek), template_fit_shift = as.numeric(.data$fit))
  
  base_full <- grid %>%
    dplyr::left_join(d_deriv, by = "weekF") %>%
    dplyr::left_join(tpl, by = "newWeek") %>%
    dplyr::mutate(
      iWeek_used = as.integer(iWeek_hat),
      delta = as.integer(delta),
      newWeek_shift = pmin(pmax(.data$newWeek + .data$delta, nw_min), nw_max)
    ) %>%
    dplyr::left_join(tpl_shift, by = "newWeek_shift") %>%
    dplyr::mutate(
      template_fit_shift = dplyr::coalesce(.data$template_fit_shift, .data$template_fit),
      phase = ifelse(.data$weekF < iWeek_hat, 0L, 1L),
      t_since = as.numeric(.data$weekF - iWeek_hat),
      omega   = ramp_weight(.data$t_since, K = K),
      logit_f     = logit_stable(.data$template_fit_shift, eps = eps),
      logit_f_eff = .data$omega * .data$logit_f
    ) %>%
    dplyr::arrange(.data$weekF)
  
  build_snapshot <- function(asof_weekF) {
    asof_weekF <- as.integer(asof_weekF)
    
    d <- base_full %>%
      dplyr::mutate(
        y    = dplyr::if_else(.data$weekF <= asof_weekF, .data$y_true, NA_integer_),
        N    = dplyr::if_else(.data$weekF <= asof_weekF, .data$N_true, NA_integer_),
        neg  = dplyr::if_else(.data$weekF <= asof_weekF, .data$neg_true, NA_integer_),
        p    = dplyr::if_else(.data$weekF <= asof_weekF, .data$p_true, NA_real_),
        date = dplyr::if_else(.data$weekF <= asof_weekF, .data$date_true, as.Date(NA)),
        p_true = .data$p_true,
        toFit = ifelse(.data$weekF >= (as.integer(iWeek_hat) - as.integer(pre_buffer)) &
                         .data$weekF <= asof_weekF, 1L, 0L)
      )
    
    lead_levels <- paste0("h", sort(unique(leads)))
    dplyr::bind_rows(lapply(leads, function(h) {
      d %>% dplyr::mutate(lead = factor(paste0("h", h), levels = lead_levels))
    }))
  }
  
  start_w <- max(1L, as.integer(iWeek_hat))
  end_w   <- max(start_w, max_obs_weekF)
  weekFs  <- seq.int(start_w, end_w)
  
  asof_newWeek <- pmin(pmax(weekFs - as.integer(iWeek_hat) + as.integer(anchorWeek), nw_min), nw_max)
  nm <- paste0("newWeek=", asof_newWeek, "_asofWeekF=", weekFs)
  nm <- make.unique(nm, sep = "_")
  
  df_list <- lapply(weekFs, build_snapshot)
  names(df_list) <- nm
  
  list(
    meta = list(
      iWeek_hat = as.integer(iWeek_hat),
      n_weeks = n_weeks,
      max_obs_weekF = max_obs_weekF,
      delta = delta,
      K = K,
      leads = leads
    ),
    df = df_list
  )
}

#' Produce per-snapshot Stage-2 forecast series (h1/h2) on the target-week axis
#'
#' Takes pseudo-prospective snapshots produced by
#' \code{build_stage2_pseudo_prospective_list()} and applies a fitted Stage-2 model
#' to produce forecasts aligned to the *target* week:
#' \itemize{
#' \item \code{h1} predictions are placed at \code{weekF_target = weekF_origin + 1}
#' \item \code{h2} predictions are placed at \code{weekF_target = weekF_origin + 2}
#' }
#'
#' The returned time series for each snapshot contains:
#' \itemize{
#' \item \code{weekF}, \code{newWeek}, \code{date}
#' \item \code{p_obs}: observed probability (masked beyond the as-of week)
#' \item \code{p_true}: retrospective truth (if present in snapshots)
#' \item \code{p_ref}: reference/template curve (from \code{ref_col})
#' \item \code{p_hat_h1}, \code{p_lo_h1}, \code{p_hi_h1}
#' \item \code{p_hat_h2}, \code{p_lo_h2}, \code{p_hi_h2}
#' \item \code{asof_weekF}: the as-of origin week for that snapshot
#' }
#'
#' Uncertainty bands are computed as link-scale confidence intervals for the mean,
#' transformed back to the response scale via \code{plogis()}.
#'
#' @param pp Output of \code{build_stage2_pseudo_prospective_list()} (list with \code{meta} and \code{df})
#'   or a compatible list of snapshot data.frames.
#' @param stage2_fit A fitted \pkg{mgcv} \code{gam}/\code{bam} Stage-2 model.
#' @param which Which snapshots to process: \code{"all"} (default) or \code{"latest"}.
#' @param horizons Integer vector of horizons to include (default \code{c(1L,2L)} -> \code{h1,h2}).
#' @param alpha_state Numeric in (0,1). If \code{z_ema} is missing, it is computed as an EWMA
#'   on the logit scale using this alpha. Defaults to \code{pp$meta$alpha_state} if present, else 0.3.
#' @param ref_col Character. Column name used as background reference curve (default \code{"template_fit_shift"}).
#' @param exclude_season_re Logical. If TRUE (default), excludes \code{s(season)} during prediction.
#' @param ci_level Confidence level for intervals (default 0.95).
#' @param date_step_days Integer days per week when imputing missing dates (default 7).
#'
#' @return If \code{which="latest"}, returns a single data.frame.
#'   If \code{which="all"}, returns a list of data.frames (one per snapshot) in the same order as input snapshots.
#'
#' @export
stage2_predict_series <- function(pp,
                                  stage2_fit,
                                  which = c("all", "latest"),
                                  horizons = c(1L, 2L),
                                  alpha_state = NULL,
                                  ref_col = "template_fit_shift",
                                  exclude_season_re = TRUE,
                                  interval = c("pi", "ci"),
                                  level = 0.95,
                                  pi_B = 2000L,
                                  pi_seed = 1L,
                                  date_step_days = 7L) {
  stopifnot(inherits(stage2_fit, c("gam", "bam")))
  which <- match.arg(which)
  interval <- match.arg(interval)
  
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("tidyr", quietly = TRUE)) stop("Please install tidyr.")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Please install tibble.")
  
  df_list <- if (is.list(pp) && !is.null(pp$df)) pp$df else pp
  if (is.data.frame(df_list)) df_list <- list(df_list)
  if (!is.list(df_list)) stop("pp must be list(meta, df=list_of_dfs) or list_of_dfs.")
  
  df_list <- df_list[vapply(df_list, is.data.frame, logical(1))]
  if (!length(df_list)) stop("No snapshot data.frames found in pp$df.")
  if (which == "latest") df_list <- df_list[length(df_list)]
  
  if (is.null(alpha_state)) alpha_state <- (pp$meta$alpha_state %||% 0.3)
  alpha_state <- as.numeric(alpha_state)
  if (!is.finite(alpha_state) || alpha_state <= 0 || alpha_state >= 1) alpha_state <- 0.3
  
  lev_lead   <- tryCatch(levels(stage2_fit$model$lead),   error = function(e) NULL)
  lev_season <- tryCatch(levels(stage2_fit$model$season), error = function(e) NULL)
  ex <- if (isTRUE(exclude_season_re)) "s(season)" else NULL
  
  zcrit <- stats::qnorm((1 + level) / 2)
  want_leads <- paste0("h", as.integer(horizons))
  if (!is.null(lev_lead)) want_leads <- intersect(want_leads, lev_lead)
  lead_to_int <- function(x) as.integer(sub("^h", "", as.character(x)))
  
  ewma <- function(z, alpha) {
    out <- numeric(length(z))
    out[1] <- z[1]
    if (length(z) > 1) for (i in 2:length(z)) out[i] <- alpha * z[i] + (1 - alpha) * out[i - 1]
    out
  }
  
  impute_weekly <- function(df, week_col = "weekF", value_col, step) {
    w <- df[[week_col]]
    v <- df[[value_col]]
    ok <- which(is.finite(w) & !is.na(v))
    if (!length(ok)) return(df)
    
    first_i <- ok[which.min(w[ok])]
    last_i  <- ok[which.max(w[ok])]
    w1 <- as.integer(w[first_i]); v1 <- v[first_i]
    w2 <- as.integer(w[last_i]);  v2 <- v[last_i]
    
    miss_pre <- which(is.na(v) & is.finite(w) & as.integer(w) < w1)
    if (length(miss_pre)) v[miss_pre] <- v1 + step * (as.integer(w[miss_pre]) - w1)
    
    miss_post <- which(is.na(v) & is.finite(w) & as.integer(w) > w2)
    if (length(miss_post)) v[miss_post] <- v2 + step * (as.integer(w[miss_post]) - w2)
    
    df[[value_col]] <- v
    df
  }
  
  # ---- NEW: predictive interval helper (binomial PI on proportion) ----
  binom_pi_prop <- function(eta, se, N_use, level = 0.95, B = 2000L, seed = 1L) {
    n <- length(eta)
    N_use <- pmax(1L, as.integer(N_use))
    if (seed %||% NA_integer_ |> is.finite()) set.seed(as.integer(seed))
    
    eta_draw <- matrix(
      stats::rnorm(B * n, mean = rep(eta, each = B), sd = rep(se, each = B)),
      nrow = B
    )
    p_draw <- stats::plogis(eta_draw)
    
    y_draw <- matrix(
      stats::rbinom(B * n, size = rep(N_use, each = B), prob = as.vector(p_draw)),
      nrow = B
    )
    p_obs_draw <- sweep(y_draw, 2, N_use, "/")
    
    probs <- c((1 - level) / 2, 1 - (1 - level) / 2)
    
    if (requireNamespace("matrixStats", quietly = TRUE)) {
      qs <- matrixStats::colQuantiles(p_obs_draw, probs = probs, na.rm = TRUE)
      list(lo = qs[, 1], hi = qs[, 2])
    } else {
      qs <- apply(p_obs_draw, 2, stats::quantile, probs = probs, na.rm = TRUE, names = FALSE)
      list(lo = qs[1, ], hi = qs[2, ])
    }
  }
  
  pred_one <- function(d) {
    stopifnot(is.data.frame(d))
    if (!("weekF" %in% names(d))) stop("Snapshot missing weekF.")
    if (!("lead" %in% names(d)))  stop("Snapshot missing lead.")
    if (!("toFit" %in% names(d))) d$toFit <- 1L
    
    base <- d %>%
      dplyr::arrange(.data$weekF) %>%
      dplyr::distinct(.data$weekF, .keep_all = TRUE)
    
    base$weekF <- as.integer(base$weekF)
    base$newWeek <- if ("newWeek" %in% names(base)) as.integer(base$newWeek) else NA_integer_
    base$date <- if ("date" %in% names(base)) as.Date(base$date) else as.Date(NA)
    
    if (!"p" %in% names(base)) {
      if (all(c("y", "N") %in% names(base))) base$p <- as.numeric(base$y) / pmax(as.numeric(base$N), 1)
      else stop("Need p or (y,N) in snapshot to form p_obs.")
    }
    base$p_obs <- as.numeric(base$p)
    base$p_true <- if ("p_true" %in% names(base)) as.numeric(base$p_true) else NA_real_
    
    if (!is.null(ref_col) && ref_col %in% names(base)) {
      base$p_ref <- as.numeric(base[[ref_col]])
    } else if ("template_fit_shift" %in% names(base)) {
      base$p_ref <- as.numeric(base$template_fit_shift)
    } else if ("template_fit" %in% names(base)) {
      base$p_ref <- as.numeric(base$template_fit)
    } else {
      base$p_ref <- NA_real_
    }
    
    # Keep an N lookup if available (for PI)
    N_lookup <- NULL
    if ("N" %in% names(base)) {
      N_lookup <- base %>% dplyr::select(.data$weekF, N = .data$N)
      N_lookup$N <- as.integer(N_lookup$N)
    }
    
    base$logN_now <- if ("logN_now" %in% names(base)) as.numeric(base$logN_now) else {
      if ("N" %in% names(base)) log(pmax(as.numeric(base$N), 1)) else NA_real_
    }
    
    z_now <- logit_stable(base$p_obs, eps = 1e-6)
    base$z_ema <- if ("z_ema" %in% names(base)) as.numeric(base$z_ema) else ewma(z_now, alpha_state)
    
    ok_fit <- !is.na(d$toFit) & d$toFit == 1L
    asof_weekF <- if (any(ok_fit)) max(as.integer(d$weekF[ok_fit]), na.rm = TRUE) else max(base$weekF, na.rm = TRUE)
    asof_weekF <- as.integer(asof_weekF)
    
    d2 <- d %>%
      dplyr::left_join(base %>% dplyr::select(.data$weekF, .data$z_ema, .data$logN_now),
                       by = "weekF")
    
    if (!"d1_now" %in% names(d2) && "d1_link" %in% names(d2)) d2$d1_now <- d2$d1_link
    if (!"d2_now" %in% names(d2) && "d2_link" %in% names(d2)) d2$d2_now <- d2$d2_link
    
    if (!"season" %in% names(d2)) {
      d2$season <- if (!is.null(lev_season)) factor(lev_season[1], levels = lev_season) else factor("current")
    } else if (!is.null(lev_season)) {
      d2$season <- factor(as.character(d2$season), levels = lev_season)
      d2$season[is.na(d2$season)] <- lev_season[1]
    }
    
    idx <- which(!is.na(d2$toFit) & d2$toFit == 1L & as.character(d2$lead) %in% want_leads)
    
    pred_wide <- NULL
    if (length(idx)) {
      nd <- d2[idx, , drop = FALSE]
      if (!is.null(lev_lead)) nd$lead <- factor(as.character(nd$lead), levels = lev_lead)
      
      need <- c("logit_f_eff", "z_ema", "logN_now", "d1_now", "d2_now", "lead", "season")
      miss <- setdiff(need, names(nd))
      if (length(miss)) stop("Prediction rows missing: ", paste(miss, collapse = ", "))
      
      pr  <- stats::predict(stage2_fit, newdata = nd, type = "link", se.fit = TRUE, exclude = ex)
      eta <- as.numeric(pr$fit)
      se  <- as.numeric(pr$se.fit)
      
      p_hat <- stats::plogis(eta)
      
      h <- lead_to_int(nd$lead)
      weekF_target <- as.integer(nd$weekF) + h
      
      # ---- N used for PI ----
      N_target <- rep(NA_integer_, length(weekF_target))
      if (!is.null(N_lookup)) {
        N_target <- N_lookup$N[match(weekF_target, N_lookup$weekF)]
      }
      # fallback proxy: current N from logN_now
      N_proxy <- pmax(1L, as.integer(round(exp(as.numeric(nd$logN_now)))))
      N_use <- ifelse(is.na(N_target) | N_target < 1L, N_proxy, N_target)
      
      if (interval == "ci") {
        p_lo <- stats::plogis(eta - zcrit * se)
        p_hi <- stats::plogis(eta + zcrit * se)
      } else {
        pi <- binom_pi_prop(eta, se, N_use, level = level, B = as.integer(pi_B), seed = as.integer(pi_seed))
        p_lo <- pi$lo
        p_hi <- pi$hi
      }
      
      pred_long <- tibble::tibble(
        weekF = weekF_target,
        lead  = as.character(nd$lead),
        p_hat = p_hat,
        p_lo  = p_lo,
        p_hi  = p_hi
      )
      
      pred_wide <- pred_long %>%
        tidyr::pivot_wider(
          names_from  = .data$lead,
          values_from = c(.data$p_hat, .data$p_lo, .data$p_hi),
          names_glue  = "{.value}_{lead}"
        )
    }
    
    w_max_obs  <- suppressWarnings(max(base$weekF, na.rm = TRUE)); if (!is.finite(w_max_obs)) w_max_obs <- 1L
    w_max_pred <- if (!is.null(pred_wide)) suppressWarnings(max(pred_wide$weekF, na.rm = TRUE)) else w_max_obs
    if (!is.finite(w_max_pred)) w_max_pred <- w_max_obs
    
    out <- tibble::tibble(weekF = seq.int(1L, as.integer(max(w_max_obs, w_max_pred)))) %>%
      dplyr::left_join(
        base %>% dplyr::select(.data$weekF, .data$newWeek, .data$date, .data$p_obs, .data$p_ref, .data$p_true),
        by = "weekF"
      )
    
    if (!is.null(pred_wide)) out <- out %>% dplyr::left_join(pred_wide, by = "weekF")
    
    if (any(!is.na(out$date))) {
      out <- impute_weekly(out, "weekF", "date", as.difftime(date_step_days, units = "days"))
    }
    if (any(!is.na(out$newWeek))) {
      out <- impute_weekly(out, "weekF", "newWeek", 1L)
      out$newWeek <- as.integer(out$newWeek)
    }
    
    out$asof_weekF <- asof_weekF
    out
  }
  
  res <- lapply(df_list, pred_one)
  if (which == "latest") res[[1]] else res
}
#' Plot observed vs Stage-2 forecasts across pseudo-prospective snapshots
#'
#' Visualizes the output of \code{stage2_predict_series()}.
#' For each snapshot, plots:
#' \itemize{
#' \item observed \code{p_obs} as points
#' \item forecast mean curves for \code{h1} (blue) and \code{h2} (green)
#' \item optional uncertainty ribbons (from \code{p_lo_h*}/\code{p_hi_h*})
#' \item truth stars at \code{asof_weekF+1} and \code{asof_weekF+2} using \code{p_true}
#' \item vertical line at \code{asof_weekF} (red) and ignition week (black dashed)
#' \item optional reference curve \code{p_ref} as a grey background line
#' }
#'
#' The x-axis uses \code{date} if present, otherwise \code{weekF}.
#'
#' @param ppp Output from \code{stage2_predict_series()} (list of snapshot data.frames or a single data.frame).
#' @param ign_week Ignition week (integer). Can be a scalar applied to all snapshots, or a vector/list aligned to snapshots.
#' @param facet Logical. If TRUE (default) returns one faceted \code{ggplot}; if FALSE returns a list of plots.
#' @param ncol Integer number of facet columns when \code{facet=TRUE}.
#' @param show_ref Logical. If TRUE, draws \code{p_ref} in grey when available.
#' @param show_pi Logical. If TRUE, draws ribbons from \code{p_lo_h*}/\code{p_hi_h*}.
#' @param base_size Base font size passed to \code{ggplot2::theme_minimal()}.
#'
#' @return A \code{ggplot} object if \code{facet=TRUE}; otherwise a named list of \code{ggplot} objects.
#' @export
plot_stage2 <- function(ppp,
                        ign_week,
                        facet = TRUE,
                        ncol = 4,
                        show_ref = TRUE,
                        show_pi = TRUE,
                        interval = c("pi", "ci", "none"),
                        h_plot = c("h1", "h2"),   # NEW: choose horizons to plot
                        base_size = 10) {
  stopifnot(is.list(ppp), length(ppp) > 0)
  interval <- match.arg(interval)
  h_plot <- match.arg(h_plot, choices = c("h1", "h2"), several.ok = TRUE)
  
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("tidyr", quietly = TRUE)) stop("Please install tidyr.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Please install ggplot2.")
  
  show_band <- isTRUE(show_pi) && interval != "none"
  
  nm <- names(ppp)
  if (is.null(nm)) nm <- paste0("snap_", seq_along(ppp))
  
  get_ign <- function(i) {
    if (length(ign_week) == 1L) return(as.integer(ign_week))
    if (!is.null(names(ign_week)) && nm[i] %in% names(ign_week)) return(as.integer(ign_week[[nm[i]]]))
    if (length(ign_week) == length(ppp)) return(as.integer(ign_week[[i]]))
    NA_integer_
  }
  
  has_date <- ("date" %in% names(ppp[[1]])) && any(!is.na(ppp[[1]]$date))
  xvar <- if (has_date) "date" else "weekF"
  
  build_one_long <- function(d, snap, iw) {
    d <- dplyr::as_tibble(d)
    d$weekF <- as.integer(d$weekF)
    if (has_date) d$date <- as.Date(d$date)
    
    need <- c("weekF","p_obs","p_true","p_hat_h1","p_hat_h2","p_lo_h1","p_lo_h2","p_hi_h1","p_hi_h2","asof_weekF")
    miss <- setdiff(need, names(d))
    if (length(miss)) stop("Snapshot df missing: ", paste(miss, collapse = ", "))
    
    asof <- as.integer(unique(d$asof_weekF)[1])
    asof_x <- if (has_date) d$date[match(asof, d$weekF)] else asof
    ign_x  <- NA
    if (is.finite(iw)) ign_x <- if (has_date) d$date[match(as.integer(iw), d$weekF)] else as.integer(iw)
    
    obs <- dplyr::tibble(snapshot = snap, x = d[[xvar]], p_obs = as.numeric(d$p_obs))
    
    ref <- NULL
    if (isTRUE(show_ref) && "p_ref" %in% names(d) && any(is.finite(d$p_ref))) {
      ref <- dplyr::tibble(snapshot = snap, x = d[[xvar]], p_ref = as.numeric(d$p_ref))
    }
    
    pred <- d %>%
      dplyr::select(dplyr::all_of(c(xvar,
                                    "p_hat_h1","p_lo_h1","p_hi_h1",
                                    "p_hat_h2","p_lo_h2","p_hi_h2"))) %>%
      tidyr::pivot_longer(
        cols = -dplyr::all_of(xvar),
        names_to = c(".value", "h"),
        names_pattern = "p_(hat|lo|hi)_(h[12])"
      ) %>%
      dplyr::transmute(
        snapshot = snap,
        x = .data[[xvar]],
        h = factor(.data$h, levels = c("h1","h2")),
        p_hat = as.numeric(.data$hat),
        p_lo  = as.numeric(.data$lo),
        p_hi  = as.numeric(.data$hi)
      )
    
    truth <- d %>%
      dplyr::filter(.data$weekF %in% c(asof + 1L, asof + 2L)) %>%
      dplyr::mutate(
        h = dplyr::case_when(
          .data$weekF == asof + 1L ~ "h1",
          .data$weekF == asof + 2L ~ "h2",
          TRUE ~ NA_character_
        ),
        h = factor(.data$h, levels = c("h1","h2")),
        x = .data[[xvar]]
      ) %>%
      dplyr::transmute(snapshot = snap, x = .data$x, h = .data$h, p_true = as.numeric(.data$p_true)) %>%
      dplyr::filter(is.finite(.data$p_true), !is.na(.data$h))
    
    vlines <- dplyr::tibble(snapshot = snap, asof_x = asof_x, ign_x = ign_x)
    
    list(obs = obs, ref = ref, pred = pred, truth = truth, v = vlines)
  }
  
  parts <- Map(function(d, name, i) build_one_long(d, name, get_ign(i)), ppp, nm, seq_along(ppp))
  
  obs_all   <- dplyr::bind_rows(lapply(parts, `[[`, "obs"))
  pred_all  <- dplyr::bind_rows(lapply(parts, `[[`, "pred"))  %>% dplyr::filter(.data$h %in% h_plot)
  truth_all <- dplyr::bind_rows(lapply(parts, `[[`, "truth")) %>% dplyr::filter(.data$h %in% h_plot)
  v_all     <- dplyr::bind_rows(lapply(parts, `[[`, "v"))
  ref_all   <- dplyr::bind_rows(lapply(parts, `[[`, "ref"))
  
  col_map <- c(h1 = "blue", h2 = "green")[h_plot]
  fill_map <- c(h1 = "blue", h2 = "green")[h_plot]
  
  make_plot <- function(obs, pred, truth, v, ref = NULL, title = NULL) {
    p <- ggplot2::ggplot()
    
    if (isTRUE(show_ref) && !is.null(ref) && nrow(ref)) {
      p <- p + ggplot2::geom_line(
        data = ref,
        ggplot2::aes(x = .data$x, y = .data$p_ref),
        color = "grey60", linewidth = 1.2, alpha = 0.65
      )
    }
    
    p <- p + ggplot2::geom_point(
      data = obs,
      ggplot2::aes(x = .data$x, y = .data$p_obs),
      size = 1.2, alpha = 0.9
    )
    
    pred2 <- pred %>%
      dplyr::filter(is.finite(.data$p_hat), is.finite(.data$p_lo), is.finite(.data$p_hi), !is.na(.data$x)) %>%
      dplyr::arrange(.data$h, .data$x)
    
    if (show_band && nrow(pred2)) {
      p <- p + ggplot2::geom_ribbon(
        data = pred2,
        ggplot2::aes(x = .data$x, ymin = .data$p_lo, ymax = .data$p_hi,
                     fill = .data$h, group = .data$h),
        alpha = 0.18
      )
    }
    
    if (nrow(pred2)) {
      p <- p + ggplot2::geom_line(
        data = pred2,
        ggplot2::aes(x = .data$x, y = .data$p_hat, color = .data$h, group = .data$h),
        linewidth = 0.95
      )
    }
    
    if (nrow(truth)) {
      p <- p + ggplot2::geom_point(
        data = truth,
        ggplot2::aes(x = .data$x, y = .data$p_true, color = .data$h, group = .data$h),
        shape = 8, size = 2.5, stroke = 1.2
      )
    }
    
    p <- p + ggplot2::geom_vline(
      data = v, ggplot2::aes(xintercept = .data$asof_x),
      color = "red", linewidth = 0.85
    )
    
    if (any(!is.na(v$ign_x))) {
      p <- p + ggplot2::geom_vline(
        data = dplyr::filter(v, !is.na(.data$ign_x)),
        ggplot2::aes(xintercept = .data$ign_x),
        linetype = "dashed", linewidth = 0.85
      )
    }
    
    p +
      ggplot2::scale_color_manual(values = col_map, name = NULL, drop = TRUE) +
      ggplot2::scale_fill_manual(values = fill_map, name = NULL, drop = TRUE) +
      ggplot2::labs(x = xvar, y = "p", title = title) +
      ggplot2::theme_minimal(base_size = base_size) +
      ggplot2::theme(panel.grid = ggplot2::element_blank())
  }
  
  if (isTRUE(facet)) {
    make_plot(obs_all, pred_all, truth_all, v_all, ref_all, title = NULL) +
      ggplot2::facet_wrap(~ snapshot, ncol = ncol, scales = "free_y")
  } else {
    plots <- vector("list", length(ppp))
    names(plots) <- nm
    for (i in seq_along(nm)) {
      s <- nm[i]
      plots[[i]] <- make_plot(
        obs   = dplyr::filter(obs_all, .data$snapshot == s),
        pred  = dplyr::filter(pred_all, .data$snapshot == s),
        truth = dplyr::filter(truth_all, .data$snapshot == s),
        v     = dplyr::filter(v_all, .data$snapshot == s),
        ref   = dplyr::filter(ref_all, .data$snapshot == s),
        title = s
      )
    }
    plots
  }
}

#' Plot weekly ignition monitoring snapshots from `run_ignition_weekly()`
#'
#' Creates a lightweight monitoring plot (or plots) for weekly prospective ignition
#' detection. For each "as-of" week, it shows observed positivity up to that week,
#' a vertical line at the as-of week, and (if available) a dashed vertical line at
#' the estimated ignition week. All points at/after ignition (for that snapshot)
#' are colored red; earlier points are black.
#'
#' The function can return either:
#' \itemize{
#'   \item A single faceted \code{ggplot} (when \code{facet = TRUE})
#'   \item A named list of \code{ggplot} objects (when \code{facet = FALSE})
#' }
#'
#' @param ign_out Output from \code{run_ignition_weekly()}.
#'   Must contain \code{$df} with at least columns \code{weekF}, \code{ignite_ok_now},
#'   and \code{iWeek_hat_dynamic}. If present, \code{ign_out$ign_week_locked} and
#'   \code{ign_out$iWeek_hat_locked} will be used to switch to the locked ignition
#'   estimate after detection.
#' @param currentSeason Optional data.frame/tibble of the current season observed so far.
#'   If supplied, positivity is computed from \code{y/N} (preferred) or \code{p}.
#'   If not supplied, the function falls back to \code{ign_out$df$p_now} (must exist).
#' @param facet Logical. If \code{TRUE}, return a single faceted \code{ggplot}.
#'   If \code{FALSE}, return a named list of \code{ggplot} objects (one per as-of week).
#' @param ncol Integer. Number of columns when \code{facet = TRUE}.
#' @param base_size Numeric. Base font size for \code{theme_minimal()}.
#' @param y_max Numeric. Upper y-limit (lower fixed at 0). Default 0.20 to be consistent.
#' @param start_week Integer. Do not plot weeks strictly less than this \code{weekF}.
#'   This should match the \code{start_week} you used in \code{run_ignition_weekly()}.
#'   If \code{NULL}, tries \code{ign_out$start_week}; otherwise defaults to 1.
#' @param maxWeek Integer. Only include snapshots up to this as-of \code{weekF}.
#'   Default \code{Inf} (no extra truncation).
#' @param week_col Column name for within-season week in \code{currentSeason}. Default \code{"weekF"}.
#' @param y_col Column name for positives in \code{currentSeason}. Default \code{"y"}.
#' @param N_col Column name for total tests in \code{currentSeason}. Default \code{"N"}.
#' @param p_col Column name for observed positivity in \code{currentSeason}. Default \code{"p"}.
#' @param date_col Column name for dates in \code{currentSeason}. If present and non-missing,
#'   plotting uses \code{date} on the x-axis instead of \code{weekF}. Default \code{"date"}.
#'
#' @return If \code{facet = TRUE}, a single \code{ggplot} object.
#'   If \code{facet = FALSE}, a named list of \code{ggplot} objects with names \code{"asof_<weekF>"}.
#'
#' @examples
#' \dontrun{
#' ign_out <- run_ignition_weekly(
#'   currentSeason  = currentSeason,
#'   ign_fit_or_gam = gam_cls,
#'   params         = params_stage1,
#'   start_week     = 5L
#' )
#'
#' # Faceted monitoring plot up to week 12
#' p <- plot_ignition_weekly_snapshots(
#'   ign_out, currentSeason,
#'   facet = TRUE, ncol = 4,
#'   start_week = 5L, maxWeek = 12
#' )
#' plotly::ggplotly(p)
#'
#' # List mode: pick one plot
#' plist <- plot_ignition_weekly_snapshots(
#'   ign_out, currentSeason,
#'   facet = FALSE,
#'   start_week = 5L, maxWeek = 12
#' )
#' plotly::ggplotly(plist[["asof_12"]])
#' }
#'
#' @export
#' Plot weekly ignition monitoring snapshots from `run_ignition_weekly()`
#'
#' Generates compact monitoring plots for prospective ignition detection as data
#' arrive week-by-week. For each as-of week (a snapshot), the plot shows:
#' \itemize{
#'   \item observed positivity points up to the as-of week;
#'   \item a vertical line at the as-of week;
#'   \item once ignition is detected (locked), a dashed vertical line at the locked
#'         ignition week and all points at/after that ignition week in red.
#' }
#'
#' This function intentionally does **not** visualize any “dynamic” ignition guess
#' prior to lock. Before ignition is locked, everything stays black.
#'
#' Output modes:
#' \itemize{
#'   \item \code{facet = TRUE}: returns a single faceted \code{ggplot}
#'   \item \code{facet = FALSE}: returns a named list of \code{ggplot}s
#' }
#'
#' @param ign_out Output from \code{run_ignition_weekly()}.
#'   Must contain \code{$df} with at least \code{weekF}. If present, the function uses
#'   \code{ign_out$ign_week_locked} and \code{ign_out$iWeek_hat_locked} to define ignition.
#'   If those are missing/NA, ignition is treated as not detected.
#' @param currentSeason Optional data.frame/tibble of the current season observed so far.
#'   If supplied, positivity is computed from \code{y/N} (preferred) or \code{p}.
#'   If not supplied, falls back to \code{ign_out$df$p_now} (must exist).
#' @param facet Logical. If \code{TRUE}, return a single faceted \code{ggplot}.
#'   If \code{FALSE}, return a named list of \code{ggplot}s (one per as-of week).
#' @param ncol Integer. Number of columns when \code{facet = TRUE}.
#' @param base_size Numeric. Base font size for \code{theme_minimal()}.
#' @param y_max Numeric. Upper y-limit (lower fixed at 0). Default 0.20.
#' @param start_week Integer. Do not plot any snapshots (or points) with \code{weekF < start_week}.
#'   Set this to match \code{start_week} used in \code{run_ignition_weekly()} (e.g., 5L).
#' @param maxWeek Integer. Only include snapshots up to this as-of \code{weekF}. Default \code{Inf}.
#' @param week_col Column name for within-season week in \code{currentSeason}. Default \code{"weekF"}.
#' @param y_col Column name for positives in \code{currentSeason}. Default \code{"y"}.
#' @param N_col Column name for total tests in \code{currentSeason}. Default \code{"N"}.
#' @param p_col Column name for observed positivity in \code{currentSeason}. Default \code{"p"}.
#' @param date_col Column name for dates in \code{currentSeason}. If present and non-missing,
#'   plotting uses \code{date} on the x-axis instead of \code{weekF}. Default \code{"date"}.
#'
#' @return If \code{facet = TRUE}, a single \code{ggplot} object.
#'   If \code{facet = FALSE}, a named list of \code{ggplot} objects with names \code{"asof_<weekF>"}.
#'
#' @examples
#' \dontrun{
#' ign_out <- run_ignition_weekly(currentSeason, gam_cls, params_stage1, start_week = 5L)
#'
#' # Faceted monitoring plot up to week 14
#' p <- plot_ignition_weekly_snapshots(ign_out, currentSeason,
#'   facet = TRUE, ncol = 4, start_week = 5L, maxWeek = 14L
#' )
#' plotly::ggplotly(p)
#'
#' # List mode: show only as-of week 12
#' plist <- plot_ignition_weekly_snapshots(ign_out, currentSeason,
#'   facet = FALSE, start_week = 5L, maxWeek = 12L
#' )
#' plotly::ggplotly(plist[["asof_12"]])
#' }
#'
#' @export
#' Plot weekly ignition monitoring snapshots from `run_ignition_weekly()`
#'
#' Generates compact monitoring plots for prospective ignition detection as data
#' arrive week-by-week. For each as-of week (a snapshot), the plot shows:
#' \itemize{
#'   \item observed positivity points up to the as-of week;
#'   \item a vertical line at the as-of week;
#'   \item once ignition is detected (locked), a dashed vertical line at the locked
#'         ignition week and all points at/after that ignition week in red.
#' }
#'
#' This function intentionally does **not** visualize any “dynamic” ignition guess
#' prior to lock. Before ignition is locked, everything stays black.
#'
#' Output modes:
#' \itemize{
#'   \item \code{facet = TRUE}: returns a single faceted \code{ggplot}
#'   \item \code{facet = FALSE}: returns a named list of \code{ggplot}s
#' }
#'
#' @param ign_out Output from \code{run_ignition_weekly()}.
#'   Must contain \code{$df} with at least \code{weekF}. If present, the function uses
#'   \code{ign_out$ign_week_locked} and \code{ign_out$iWeek_hat_locked} to define ignition.
#'   If those are missing/NA, ignition is treated as not detected.
#' @param currentSeason Optional data.frame/tibble of the current season observed so far.
#'   If supplied, positivity is computed from \code{y/N} (preferred) or \code{p}.
#'   If not supplied, falls back to \code{ign_out$df$p_now} (must exist).
#' @param facet Logical. If \code{TRUE}, return a single faceted \code{ggplot}.
#'   If \code{FALSE}, return a named list of \code{ggplot}s (one per as-of week).
#' @param ncol Integer. Number of columns when \code{facet = TRUE}.
#' @param base_size Numeric. Base font size for \code{theme_minimal()}.
#' @param y_max Numeric. Upper y-limit (lower fixed at 0). Default 0.20.
#' @param start_week Integer. Do not plot any snapshots (or points) with \code{weekF < start_week}.
#'   Set this to match \code{start_week} used in \code{run_ignition_weekly()} (e.g., 5L).
#' @param maxWeek Integer. Only include snapshots up to this as-of \code{weekF}. Default \code{Inf}.
#' @param week_col Column name for within-season week in \code{currentSeason}. Default \code{"weekF"}.
#' @param y_col Column name for positives in \code{currentSeason}. Default \code{"y"}.
#' @param N_col Column name for total tests in \code{currentSeason}. Default \code{"N"}.
#' @param p_col Column name for observed positivity in \code{currentSeason}. Default \code{"p"}.
#' @param date_col Column name for dates in \code{currentSeason}. If present and non-missing,
#'   plotting uses \code{date} on the x-axis instead of \code{weekF}. Default \code{"date"}.
#'
#' @return If \code{facet = TRUE}, a single \code{ggplot} object.
#'   If \code{facet = FALSE}, a named list of \code{ggplot} objects with names \code{"asof_<weekF>"}.
#'
#' @export
plot_ignition_weekly_snapshots <- function(ign_out,
                                           currentSeason = NULL,
                                           facet = TRUE,
                                           ncol = 4,
                                           base_size = 11,
                                           y_max = 0.20,
                                           start_week = 5L,
                                           maxWeek = Inf,
                                           week_col = "weekF",
                                           y_col = "y",
                                           N_col = "N",
                                           p_col = "p",
                                           date_col = "date") {
  stopifnot(is.list(ign_out), "df" %in% names(ign_out))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Need dplyr.")
  if (!requireNamespace("tidyr", quietly = TRUE)) stop("Need tidyr.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Need ggplot2.")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Need tibble.")
  
  df <- dplyr::as_tibble(ign_out$df)
  if (!("weekF" %in% names(df))) stop("ign_out$df must contain weekF.")
  
  start_week <- as.integer(start_week)
  if (!is.finite(start_week)) start_week <- 1L
  
  maxWeek_in <- maxWeek
  maxWeek <- suppressWarnings(as.integer(maxWeek))
  if (!is.finite(maxWeek_in) || is.na(maxWeek)) maxWeek <- Inf
  
  df <- df %>%
    dplyr::mutate(weekF = as.integer(.data$weekF)) %>%
    dplyr::arrange(.data$weekF)
  
  # snapshots to include, sorted numerically
  w_seq <- df$weekF[df$weekF >= start_week & df$weekF <= maxWeek]
  w_seq <- sort(unique(w_seq))
  if (!length(w_seq)) stop("No weeks to plot: check start_week/maxWeek vs ign_out$df$weekF.")
  
  # effective maxWeek for xlim
  maxWeek_eff <- if (is.finite(maxWeek)) maxWeek else max(w_seq, na.rm = TRUE)
  x_end_weekF <- as.integer(maxWeek_eff + 1L)  # <-- requested: maxWeek + 1
  x_start_weekF <- as.integer(start_week)
  
  # ----- observed series (per weekF) -----
  has_date <- FALSE
  if (!is.null(currentSeason)) {
    obs <- dplyr::as_tibble(currentSeason)
    if (!(week_col %in% names(obs))) stop("currentSeason missing week column: ", week_col)
    
    has_p  <- p_col %in% names(obs)
    has_yN <- all(c(y_col, N_col) %in% names(obs))
    if (!has_p && !has_yN) stop("currentSeason must have either ", p_col, " or (", y_col, ", ", N_col, ").")
    
    has_date <- date_col %in% names(obs) && any(!is.na(obs[[date_col]]))
    
    obs <- obs %>%
      dplyr::transmute(
        weekF = as.integer(.data[[week_col]]),
        date  = if (has_date) as.Date(.data[[date_col]]) else as.Date(NA),
        y     = if (has_yN) as.numeric(.data[[y_col]]) else NA_real_,
        N     = if (has_yN) as.numeric(.data[[N_col]]) else NA_real_,
        p_raw = if (has_p)  as.numeric(.data[[p_col]]) else NA_real_
      ) %>%
      dplyr::filter(is.finite(.data$weekF), .data$weekF >= start_week) %>%
      dplyr::group_by(.data$weekF) %>%
      dplyr::summarise(
        date = if (has_date) min(.data$date, na.rm = TRUE) else as.Date(NA),
        p = dplyr::if_else(
          all(is.na(.data$y)) || all(is.na(.data$N)),
          mean(.data$p_raw, na.rm = TRUE),
          sum(.data$y, na.rm = TRUE) / pmax(sum(.data$N, na.rm = TRUE), 1)
        ),
        .groups = "drop"
      ) %>%
      dplyr::arrange(.data$weekF)
  } else {
    if (!("p_now" %in% names(df))) stop("No currentSeason provided and ign_out$df has no p_now.")
    obs <- df %>%
      dplyr::transmute(weekF = .data$weekF, date = as.Date(NA), p = as.numeric(.data$p_now)) %>%
      dplyr::filter(is.finite(.data$p), .data$weekF >= start_week) %>%
      dplyr::arrange(.data$weekF)
  }
  
  xvar <- if (has_date) "date" else "weekF"
  
  # map weekF -> date for xlim when date axis is used
  week_to_date <- function(w) {
    w <- as.integer(w)
    m <- obs %>% dplyr::filter(!is.na(.data$date)) %>% dplyr::select(.data$weekF, .data$date)
    if (nrow(m) == 0) return(as.Date(NA))
    
    hit <- m$date[match(w, m$weekF)]
    if (!is.na(hit)) return(hit)
    
    # extrapolate using nearest available date (weekly step = 7 days)
    if (w > max(m$weekF, na.rm = TRUE)) {
      w0 <- max(m$weekF, na.rm = TRUE)
      d0 <- m$date[which.max(m$weekF)]
      return(d0 + 7L * (w - w0))
    } else {
      w0 <- min(m$weekF, na.rm = TRUE)
      d0 <- m$date[which.min(m$weekF)]
      return(d0 - 7L * (w0 - w))
    }
  }
  
  xlim_vec <- if (has_date) {
    c(week_to_date(x_start_weekF), week_to_date(x_end_weekF))
  } else {
    c(x_start_weekF, x_end_weekF)
  }
  
  # ----- ignition lock info (scalar) -----
  ign_week_locked  <- if (!is.null(ign_out$ign_week_locked))  as.integer(ign_out$ign_week_locked)  else NA_integer_
  iWeek_hat_locked <- if (!is.null(ign_out$iWeek_hat_locked)) as.integer(ign_out$iWeek_hat_locked) else NA_integer_
  lock_ok <- is.finite(ign_week_locked) && !is.na(ign_week_locked) &&
    is.finite(iWeek_hat_locked) && !is.na(iWeek_hat_locked)
  
  # per-snapshot meta: snapshot factor is ordered by numeric week
  snap_tbl <- tibble::tibble(asof_weekF = w_seq) %>%
    dplyr::mutate(
      detected_by_now = lock_ok & (.data$asof_weekF >= ign_week_locked),
      iWeek_plot = dplyr::if_else(.data$detected_by_now, iWeek_hat_locked, NA_integer_),
      ign_col    = dplyr::if_else(.data$detected_by_now, "red", "black"),
      snapshot   = factor(paste0("asof_", .data$asof_weekF),
                          levels = paste0("asof_", w_seq))
    )
  
  # attach x positions and observed p at as-of
  snap_tbl <- snap_tbl %>%
    dplyr::left_join(
      obs %>% dplyr::transmute(weekF = .data$weekF, x = .data[[xvar]], p = .data$p),
      by = c("asof_weekF" = "weekF")
    ) %>%
    dplyr::rename(asof_x = .data$x, asof_p = .data$p)
  
  # ignition line x position (only for detected snapshots)
  ign_line <- snap_tbl %>%
    dplyr::filter(.data$detected_by_now, !is.na(.data$iWeek_plot)) %>%
    dplyr::left_join(
      obs %>% dplyr::transmute(weekF = .data$weekF, x = .data[[xvar]]),
      by = c("iWeek_plot" = "weekF")
    ) %>%
    dplyr::rename(ign_x = .data$x)
  
  # all points up to as-of (>= start_week), with red points only after locked ignition
  plot_dat <- tidyr::crossing(asof_weekF = w_seq, weekF = obs$weekF) %>%
    dplyr::filter(.data$weekF <= .data$asof_weekF, .data$weekF >= start_week) %>%
    dplyr::left_join(
      obs %>% dplyr::transmute(weekF = .data$weekF, x = .data[[xvar]], p = .data$p),
      by = "weekF"
    ) %>%
    dplyr::left_join(
      snap_tbl %>% dplyr::select(.data$asof_weekF, .data$snapshot, .data$detected_by_now, .data$iWeek_plot),
      by = "asof_weekF"
    ) %>%
    dplyr::mutate(
      point_col = dplyr::if_else(.data$detected_by_now & !is.na(.data$iWeek_plot) & (.data$weekF >= .data$iWeek_plot),
                                 "red", "black")
    ) %>%
    dplyr::arrange(.data$asof_weekF, .data$weekF)
  
  make_one <- function(asof_w) {
    asof_w <- as.integer(asof_w)
    dat <- plot_dat %>% dplyr::filter(.data$asof_weekF == asof_w)
    snap_info <- snap_tbl %>% dplyr::filter(.data$asof_weekF == asof_w)
    ign_info  <- ign_line %>% dplyr::filter(.data$asof_weekF == asof_w)
    
    p <- ggplot2::ggplot(dat, ggplot2::aes(x = .data$x, y = .data$p)) +
      ggplot2::geom_line(linewidth = 0.6, alpha = 0.6, color = "grey40", na.rm = TRUE) +
      ggplot2::geom_point(ggplot2::aes(color = .data$point_col), size = 1.6, na.rm = TRUE) +
      ggplot2::geom_vline(
        data = snap_info,
        ggplot2::aes(xintercept = .data$asof_x),
        color = "grey60", linewidth = 0.6, inherit.aes = FALSE
      ) +
      ggplot2::geom_point(
        data = snap_info,
        ggplot2::aes(x = .data$asof_x, y = .data$asof_p, color = .data$ign_col),
        size = 3.0, inherit.aes = FALSE, na.rm = TRUE
      )
    
    if (nrow(ign_info) > 0) {
      p <- p + ggplot2::geom_vline(
        data = ign_info,
        ggplot2::aes(xintercept = .data$ign_x),
        color = "red", linetype = "dashed", linewidth = 0.9, inherit.aes = FALSE
      )
    }
    
    p +
      ggplot2::scale_color_identity() +
      ggplot2::coord_cartesian(ylim = c(0, y_max), xlim = xlim_vec) +  # <-- NEW xlim
      ggplot2::labs(
        x = xvar, y = "p (observed)",
        title = paste0("asof_", asof_w,
                       " | detected = ", ifelse(snap_info$detected_by_now[1], "yes", "no"),
                       " | iWeek_hat_locked = ", ifelse(lock_ok, iWeek_hat_locked, "NA"))
      ) +
      ggplot2::theme_minimal(base_size = base_size) +
      ggplot2::theme(panel.grid.minor = ggplot2::element_blank())
  }
  
  if (isTRUE(facet)) {
    p <- ggplot2::ggplot(plot_dat, ggplot2::aes(x = .data$x, y = .data$p)) +
      ggplot2::geom_line(linewidth = 0.6, alpha = 0.6, color = "grey40", na.rm = TRUE) +
      ggplot2::geom_point(ggplot2::aes(color = .data$point_col), size = 1.2, na.rm = TRUE) +
      ggplot2::geom_vline(
        data = snap_tbl,
        ggplot2::aes(xintercept = .data$asof_x),
        color = "grey60", linewidth = 0.5, inherit.aes = FALSE
      ) +
      ggplot2::geom_point(
        data = snap_tbl,
        ggplot2::aes(x = .data$asof_x, y = .data$asof_p, color = .data$ign_col),
        size = 2.3, inherit.aes = FALSE, na.rm = TRUE
      )
    
    if (nrow(ign_line) > 0) {
      p <- p + ggplot2::geom_vline(
        data = ign_line,
        ggplot2::aes(xintercept = .data$ign_x),
        color = "red", linetype = "dashed", linewidth = 0.8, inherit.aes = FALSE
      )
    }
    
    p +
      ggplot2::scale_color_identity() +
      ggplot2::coord_cartesian(ylim = c(0, y_max), xlim = xlim_vec) +  # <-- NEW xlim
      ggplot2::labs(x = xvar, y = "p (observed)") +
      ggplot2::theme_minimal(base_size = base_size) +
      ggplot2::theme(panel.grid.minor = ggplot2::element_blank()) +
      ggplot2::facet_wrap(~ snapshot, ncol = ncol, scales = "fixed")
  } else {
    out <- lapply(w_seq, make_one)
    names(out) <- paste0("asof_", w_seq)
    out
  }
}