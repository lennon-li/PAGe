# M2 runtime utilities for pseudo-prospective forecasting

#' Extract Stage-2 hyperparameters from tuning output
#'
#' Pulls the commonly used Stage-2 hyperparameters from a list or 1-row
#' data frame, supporting alternate column names (\code{shift} as an alias
#' for \code{delta}). Any keys not recognised as core hyperparameters are
#' collected in \code{extra}.
#'
#' @param best_mean_nll A list or 1-row data frame containing tuned
#'   parameters. Recognised keys: \code{delta} (or \code{shift}), \code{K},
#'   \code{leads}, \code{use_ramp}.
#'
#' @return A list with \code{delta} (integer template shift), \code{K}
#'   (integer EMA half-life), \code{leads} (integer vector of forecast
#'   horizons), \code{use_ramp} (logical), and \code{extra} (list of any
#'   remaining keys).
#' @keywords internal
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
build_stage2_pseudo_prospective_list <- function(
    currentSeason,
    template_df,
    best_mean_nll,
    iWeek_hat,
    align = TRUE,
    anchorWeek = 19L,
    pre_buffer = 1L,
    n_weeks = 53L,
    eps = 1e-6,
    date_col = if ("date" %in% names(currentSeason)) "date" else NULL
) {
  stopifnot(is.data.frame(currentSeason), is.data.frame(template_df))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  
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
  
  d_truth <- dplyr::as_tibble(currentSeason) |>
    dplyr::mutate(
      weekF = as.integer(.data$weekF),
      y     = as.integer(.data$y),
      N     = if ("N" %in% names(currentSeason)) as.integer(.data$N) else as.integer(.data$y + .data$neg),
      neg   = if ("neg" %in% names(currentSeason)) as.integer(.data$neg) else as.integer(.data$N - .data$y),
      date  = if (has_date) as.Date(.data[[date_col]]) else as.Date(NA)
    ) |>
    dplyr::filter(!is.na(.data$weekF), .data$weekF >= 1L, .data$weekF <= n_weeks) |>
    dplyr::group_by(.data$weekF) |>
    dplyr::summarise(
      y_true   = sum(.data$y, na.rm = TRUE),
      N_true   = sum(.data$N, na.rm = TRUE),
      neg_true = sum(.data$neg, na.rm = TRUE),
      p_true   = y_true / pmax(N_true, 1L),
      date_true = {x <- date; x <- x[!is.na(x)]; if (length(x)) x[1] else as.Date(NA)},
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$weekF)
  
  max_obs_weekF <- suppressWarnings(max(d_truth$weekF[is.finite(d_truth$p_true)], na.rm = TRUE))
  if (!is.finite(max_obs_weekF)) max_obs_weekF <- 0L
  max_obs_weekF <- as.integer(max_obs_weekF)
  
  grid <- dplyr::tibble(weekF = seq.int(1L, n_weeks)) |>
    dplyr::left_join(d_truth, by = "weekF")
  
  if (isTRUE(align)) {
    grid$newWeek_raw <- as.integer(grid$weekF - as.integer(iWeek_hat) + as.integer(anchorWeek))
  } else {
    grid$newWeek_raw <- as.integer(grid$weekF)
  }
  grid$newWeek <- pmin(pmax(grid$newWeek_raw, nw_min), nw_max)
  
  tpl <- dplyr::as_tibble(template_df) |>
    dplyr::transmute(newWeek = as.integer(.data$newWeek), template_fit = as.numeric(.data$fit))
  tpl_shift <- dplyr::as_tibble(template_df) |>
    dplyr::transmute(newWeek_shift = as.integer(.data$newWeek), template_fit_shift = as.numeric(.data$fit))
  
  base_full <- grid |>
    dplyr::left_join(tpl, by = "newWeek") |>
    dplyr::mutate(
      iWeek_used = as.integer(iWeek_hat),
      delta = as.integer(delta),
      newWeek_shift = pmin(pmax(.data$newWeek + .data$delta, nw_min), nw_max)
    ) |>
    dplyr::left_join(tpl_shift, by = "newWeek_shift") |>
    dplyr::mutate(
      template_fit_shift = dplyr::coalesce(.data$template_fit_shift, .data$template_fit),
      phase = ifelse(.data$weekF < iWeek_hat, 0L, 1L),
      t_since = as.numeric(.data$weekF - iWeek_hat),
      omega   = ramp_weight(.data$t_since, K = K),
      logit_f     = logit_stable(.data$template_fit_shift, eps = eps),
      logit_f_eff = .data$omega * .data$logit_f
    ) |>
    dplyr::arrange(.data$weekF)
  
  build_snapshot <- function(asof_weekF) {
    asof_weekF <- as.integer(asof_weekF)
    
    d <- base_full |>
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
      d |> dplyr::mutate(lead = factor(paste0("h", h), levels = lead_levels))
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

  # ---- Soft ceiling from training data distribution ----
  # Prevents extrapolation artifacts from producing unrealistically high
  # predicted positivity.  Below p_knee the function is identity; above
  # it tanh-squashes toward p_ceil.
  p_train <- tryCatch({
    mf <- stage2_fit$model
    as.numeric(mf[[1]][, 1]) / rowSums(mf[[1]])
  }, error = function(e) NULL)
  if (!is.null(p_train) && length(p_train) > 10L) {
    p_knee <- as.numeric(stats::quantile(p_train, 0.95, na.rm = TRUE))
    p_train_max <- max(p_train, na.rm = TRUE)
    # Ceiling = historical max + half the gap between max and 95th %ile
    p_ceil <- p_train_max + 0.5 * (p_train_max - p_knee)
    p_ceil <- min(p_ceil, 1.0)  # never exceed 1
  } else {
    p_knee <- 0.26; p_ceil <- 0.40
  }
  soft_cap_p <- function(p) {
    above <- p > p_knee
    p[above] <- p_knee + (p_ceil - p_knee) *
      tanh((p[above] - p_knee) / (p_ceil - p_knee))
    p
  }
  
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
    
    base <- d |>
      dplyr::arrange(.data$weekF) |>
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
      N_lookup <- base |> dplyr::select(.data$weekF, N = .data$N)
      N_lookup$N <- as.integer(N_lookup$N)
    }
    
    base$logN_now <- if ("logN_now" %in% names(base)) as.numeric(base$logN_now) else {
      if ("N" %in% names(base)) log(pmax(as.numeric(base$N), 1)) else NA_real_
    }
    # Cap logN_now at training range to prevent extrapolation of s(logN_now)
    if ("logN_now" %in% names(stage2_fit$model)) {
      logN_range <- range(stage2_fit$model$logN_now, na.rm = TRUE)
      base$logN_now <- pmin(pmax(base$logN_now, logN_range[1]), logN_range[2])
    }

    z_now <- logit_stable(base$p_obs, eps = 1e-6)
    base$z_ema <- if ("z_ema" %in% names(base)) as.numeric(base$z_ema) else ewma(z_now, alpha_state)
    
    ok_fit <- !is.na(d$toFit) & d$toFit == 1L
    asof_weekF <- if (any(ok_fit)) max(as.integer(d$weekF[ok_fit]), na.rm = TRUE) else max(base$weekF, na.rm = TRUE)
    asof_weekF <- as.integer(asof_weekF)
    
    d2 <- d |>
      dplyr::left_join(base |> dplyr::select(.data$weekF, .data$z_ema, .data$logN_now),
                       by = "weekF")
    
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
      
      need <- c("logit_f_eff", "z_ema", "logN_now", "lead", "season")
      miss <- setdiff(need, names(nd))
      if (length(miss)) stop("Prediction rows missing: ", paste(miss, collapse = ", "))
      
      pr  <- stats::predict(stage2_fit, newdata = nd, type = "link", se.fit = TRUE, exclude = ex)
      eta <- as.numeric(pr$fit)
      se  <- as.numeric(pr$se.fit)
      
      p_hat <- soft_cap_p(stats::plogis(eta))

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
        p_lo <- soft_cap_p(stats::plogis(eta - zcrit * se))
        p_hi <- soft_cap_p(stats::plogis(eta + zcrit * se))
      } else {
        pi <- binom_pi_prop(eta, se, N_use, level = level, B = as.integer(pi_B), seed = as.integer(pi_seed))
        p_lo <- soft_cap_p(pi$lo)
        p_hi <- soft_cap_p(pi$hi)
      }
      
      pred_long <- tibble::tibble(
        weekF = weekF_target,
        lead  = as.character(nd$lead),
        p_hat = p_hat,
        p_lo  = p_lo,
        p_hi  = p_hi
      )
      
      pred_wide <- pred_long |>
        tidyr::pivot_wider(
          names_from  = .data$lead,
          values_from = c(.data$p_hat, .data$p_lo, .data$p_hi),
          names_glue  = "{.value}_{lead}"
        )
    }
    
    w_max_obs  <- suppressWarnings(max(base$weekF, na.rm = TRUE)); if (!is.finite(w_max_obs)) w_max_obs <- 1L
    w_max_pred <- if (!is.null(pred_wide)) suppressWarnings(max(pred_wide$weekF, na.rm = TRUE)) else w_max_obs
    if (!is.finite(w_max_pred)) w_max_pred <- w_max_obs
    
    out <- tibble::tibble(weekF = seq.int(1L, as.integer(max(w_max_obs, w_max_pred)))) |>
      dplyr::left_join(
        base |> dplyr::select(.data$weekF, .data$newWeek, .data$date, .data$p_obs, .data$p_ref, .data$p_true),
        by = "weekF"
      )
    
    if (!is.null(pred_wide)) out <- out |> dplyr::left_join(pred_wide, by = "weekF")
    
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
    
    pred <- d |>
      dplyr::select(dplyr::all_of(c(xvar,
                                    "p_hat_h1","p_lo_h1","p_hi_h1",
                                    "p_hat_h2","p_lo_h2","p_hi_h2"))) |>
      tidyr::pivot_longer(
        cols = -dplyr::all_of(xvar),
        names_to = c(".value", "h"),
        names_pattern = "p_(hat|lo|hi)_(h[12])"
      ) |>
      dplyr::transmute(
        snapshot = snap,
        x = .data[[xvar]],
        h = factor(.data$h, levels = c("h1","h2")),
        p_hat = as.numeric(.data$hat),
        p_lo  = as.numeric(.data$lo),
        p_hi  = as.numeric(.data$hi)
      )
    
    truth <- d |>
      dplyr::filter(.data$weekF %in% c(asof + 1L, asof + 2L)) |>
      dplyr::mutate(
        h = dplyr::case_when(
          .data$weekF == asof + 1L ~ "h1",
          .data$weekF == asof + 2L ~ "h2",
          TRUE ~ NA_character_
        ),
        h = factor(.data$h, levels = c("h1","h2")),
        x = .data[[xvar]]
      ) |>
      dplyr::transmute(snapshot = snap, x = .data$x, h = .data$h, p_true = as.numeric(.data$p_true)) |>
      dplyr::filter(is.finite(.data$p_true), !is.na(.data$h))
    
    vlines <- dplyr::tibble(snapshot = snap, asof_x = asof_x, ign_x = ign_x)
    
    list(obs = obs, ref = ref, pred = pred, truth = truth, v = vlines)
  }
  
  parts <- Map(function(d, name, i) build_one_long(d, name, get_ign(i)), ppp, nm, seq_along(ppp))
  
  obs_all   <- dplyr::bind_rows(lapply(parts, `[[`, "obs"))
  pred_all  <- dplyr::bind_rows(lapply(parts, `[[`, "pred"))  |> dplyr::filter(.data$h %in% h_plot)
  truth_all <- dplyr::bind_rows(lapply(parts, `[[`, "truth")) |> dplyr::filter(.data$h %in% h_plot)
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
    
    pred2 <- pred |>
      dplyr::filter(is.finite(.data$p_hat), is.finite(.data$p_lo), is.finite(.data$p_hi), !is.na(.data$x)) |>
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
