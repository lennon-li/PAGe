`%||%` <- function(x, y) if (!is.null(x)) x else y

# ============================================================
# Prospective ignition detection (M0)
#   Stage-1: ignition classifier scores (fitIgnition)
#   Stage-0: rule-based detector + tuning (detectIgnitionBySeason_M0v2, tuneIgnitionGrid_M0v2)
#
# Key design choices (current implementation):
#   - Classifier score is used as ONE vote (NOT mandatory) in an N-of-5 rule.
#   - Evidence includes a rolling-sum gate on weekly positivity p over K_sum weeks.
#   - Trend gate uses a noise-tolerant rule on a rolling-mean smoothed series p_sm.
#   - Tuning is treated as training: thresholds/hyperparameters selected by grid search.
# ============================================================


#' Fit ignition classifier scores (Stage-1)
#'
#' Fits a smooth probabilistic classifier for an "ignition event window" and appends
#' predicted scores to the full dataset. This function supports up to three variants:
#' \itemize{
#'   \item \strong{Base} (default): random intercept by season via \code{gamm4::gamm4()}.
#'   \item \strong{Slope} (optional): random intercept + random slope on \code{week_col}.
#'   \item \strong{FS} (optional): season-varying week shape via \code{mgcv::bam()} with \code{bs="fs"}.
#' }
#'
#' \strong{Training window (balanced around ignition).}
#' For each season, the reference ignition week is
#' \code{iWeek_true = min(week_col[phase==1])}.
#' Training data are restricted to a per-season window:
#' \code{week in [iWeek_true - A_pre, iWeek_true + B_post]}.
#'
#' \strong{Event labeling (shifted earlier).}
#' The positive event window is shifted earlier by \code{lead} weeks:
#' \code{event(s,w)=1} if
#' \code{iWeek_true - lead - event_k <= week <= iWeek_true - lead}.
#' This produces an "onset-like" score that can peak before the truth ignition week.
#'
#' \strong{Prospective transfer.}
#' The detector should use population-level predictions (excluding season-specific effects).
#' In this implementation:
#' \itemize{
#'   \item For \code{gamm4} fits: population-level score is \code{predict(fit$gam, ...)} (random effects excluded).
#'   \item For \code{fs} fit: population-level score is computed by excluding the \code{s(week,season)} smooth.
#' }
#'
#' @param dat data.frame containing at least \code{season_col, week_col, phase_col, p_col}.
#' @param season_col Season identifier column name. Default \code{"season"}.
#' @param week_col Within-season week column name. Default \code{"weekF"}.
#' @param phase_col Phase indicator column name. Default \code{"phase"}.
#' @param p_col Weekly positivity/proportion column name. Default \code{"p"}.
#' @param event_k Integer >= 0. Event window width parameter (positives span \code{event_k+1} weeks). Default \code{1}.
#' @param lead Integer >= 0. Shifts the event window earlier by \code{lead} weeks. Default \code{1}.
#' @param A_pre Integer >= 0. Weeks before \code{iWeek_true} included in training. Default \code{6}.
#' @param B_post Integer >= 0. Weeks after \code{iWeek_true} included in training. Default \code{6}.
#' @param k_week Basis dimension for \code{s(week)}. Default \code{6}.
#' @param k_p Basis dimension for \code{s(p)}. Default \code{8}.
#' @param k_fs Basis dimension for the factor-smooth deviation \code{s(week,season,bs="fs")}. Default \code{4}.
#' @param fit_base Logical. Fit the base model. Default \code{TRUE}.
#' @param fit_slope Logical. Fit the random-slope model. Default \code{FALSE}.
#' @param fit_fs Logical. Fit the factor-smooth (fs) model. Default \code{FALSE}.
#' @param select Logical. Passed to \code{gamm4::gamm4(select=...)}. Default \code{FALSE}.
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#'
#' @return A list with:
#' \describe{
#'   \item{data}{Full dataset with added score columns (see below).}
#'   \item{train_data}{Training subset with \code{event} label and per-row bounds.}
#'   \item{iWeek_by_season}{Season-level truth ignition week table.}
#'   \item{fits}{List of fitted objects for each enabled model.}
#' }
#'
#' \strong{Added score columns (in \code{$data}).}
#' \itemize{
#'   \item \code{p_cls_p}: base population-level score (gamm4 fixed-effects prediction).
#'   \item \code{p_cls_base_pop}: alias of \code{p_cls_p} for clarity.
#'   \item \code{p_cls_slope_pop}: population-level score for the random-slope model (if fitted).
#'   \item \code{p_cls_fs_pop}: population-level score for the fs model (if fitted).
#'   \item \code{p_cls_fs_full}: full fs score including season deviations (if fitted; retrospective only).
#' }
#'
#' @export
fitIgnition <- function(
    dat,
    season_col = "season",
    week_col   = "weekF",
    phase_col  = "phase",
    p_col      = "p",
    event_k = 1L,
    lead    = 1L,
    A_pre   = 6L,
    B_post  = 6L,
    k_week  = 6L,
    k_p     = 8L,
    k_fs    = 4L,
    fit_base  = TRUE,
    fit_slope = FALSE,
    fit_fs    = FALSE,
    select = FALSE,
    verbose = TRUE
) {
  stopifnot(is.data.frame(dat))
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need package: data.table")
  if (!requireNamespace("gamm4", quietly = TRUE)) stop("Need package: gamm4")
  if (isTRUE(fit_fs) && !requireNamespace("mgcv", quietly = TRUE)) stop("Need package: mgcv for fit_fs=TRUE")
  
  DT_all <- data.table::as.data.table(data.table::copy(dat))
  
  need <- c(season_col, week_col, phase_col, p_col)
  miss <- setdiff(need, names(DT_all))
  if (length(miss)) stop("fitIgnition: dat missing cols: ", paste(miss, collapse = ", "))
  
  data.table::setorderv(DT_all, c(season_col, week_col))
  DT_all[, (season_col) := as.factor(get(season_col))]
  DT_all[, (week_col)   := as.integer(get(week_col))]
  
  # truth ignition week
  iWeek_dt <- DT_all[get(phase_col) == 1L,
                     .(iWeek_true = suppressWarnings(min(get(week_col), na.rm = TRUE))),
                     by = season_col]
  if (nrow(iWeek_dt) == 0L) stop("fitIgnition: no phase==1 rows found; cannot infer iWeek_true.")
  
  # training window + labeling
  DT_tr <- iWeek_dt[DT_all, on = season_col]
  DT_tr <- DT_tr[!is.na(iWeek_true)]
  
  event_k <- as.integer(event_k)
  lead    <- as.integer(lead)
  A_pre   <- as.integer(A_pre)
  B_post  <- as.integer(B_post)
  
  DT_tr[, w_lo_train := pmax(1L, iWeek_true - A_pre)]
  DT_tr[, w_hi_train := iWeek_true + B_post]
  
  DT_tr[, lo_event := pmax(1L, iWeek_true - lead - event_k)]
  DT_tr[, hi_event := iWeek_true - lead]
  
  # ensure event window is included even if A_pre is too small
  DT_tr[, w_lo_train := pmin(w_lo_train, lo_event)]
  
  DT_tr <- DT_tr[get(week_col) >= w_lo_train & get(week_col) <= w_hi_train]
  DT_tr[, event := as.integer(get(week_col) >= lo_event & get(week_col) <= hi_event)]
  
  if (isTRUE(verbose)) {
    n_pos <- sum(DT_tr$event == 1L, na.rm = TRUE)
    n_all <- nrow(DT_tr)
    message("[fitIgnition] train window: [iWeek_true - A_pre, iWeek_true + B_post]  A_pre=", A_pre, " B_post=", B_post)
    message("[fitIgnition] label window: [iWeek_true - lead - event_k, iWeek_true - lead]  lead=", lead, " event_k=", event_k)
    message("[fitIgnition] train rows=", n_all,
            " seasons=", data.table::uniqueN(DT_tr[[season_col]]),
            " event==1 count=", n_pos, " prevalence=", signif(n_pos / n_all, 3))
  }
  
  rhs_fixed <- paste0(
    "s(", week_col, ", bs='ts', k=", as.integer(k_week), ") + ",
    "s(", p_col,    ", bs='ts', k=", as.integer(k_p),    ")"
  )
  form_fixed <- stats::as.formula(paste0("event ~ ", rhs_fixed))
  
  fits <- list()
  
  pred_into <- function(gam_obj, outcol) {
    DT_all[, (outcol) := stats::predict(gam_obj, newdata = DT_all, type = "response")]
    invisible(NULL)
  }
  
  # (1) base
  if (isTRUE(fit_base)) {
    if (verbose) message("[fitIgnition] fitting base (random intercept)")
    fit_base_obj <- gamm4::gamm4(
      formula = form_fixed,
      random  = stats::as.formula(paste0("~(1|", season_col, ")")),
      data    = DT_tr,
      family  = stats::binomial(),
      nAGQ    = 1,
      select  = select
    )
    fits$base <- fit_base_obj
    pred_into(fit_base_obj$gam, "p_cls_p")            # canonical name used downstream
    DT_all[, p_cls_base_pop := p_cls_p]               # alias
  }
  
  # (2) random slope on week (population-level via $gam)
  if (isTRUE(fit_slope)) {
    if (verbose) message("[fitIgnition] fitting slope (random intercept + slope on week)")
    fit_slope_obj <- gamm4::gamm4(
      formula = form_fixed,
      random  = stats::as.formula(paste0("~(1 + ", week_col, "|", season_col, ")")),
      data    = DT_tr,
      family  = stats::binomial(),
      nAGQ    = 1,
      select  = select
    )
    fits$slope <- fit_slope_obj
    pred_into(fit_slope_obj$gam, "p_cls_slope_pop")
  }
  
  # (3) factor-smooth by season (mgcv::bam)
  if (isTRUE(fit_fs)) {
    if (verbose) message("[fitIgnition] fitting fs (s(week,season), bs='fs')")
    DT_tr[, (season_col) := as.factor(get(season_col))]
    
    term_fs <- paste0("s(", week_col, ",", season_col, ", bs='fs', k=", as.integer(k_fs), ")")
    form_fs <- stats::as.formula(paste0(
      "event ~ ",
      "s(", week_col, ", bs='ts', k=", as.integer(k_week), ") + ",
      "s(", p_col,    ", bs='ts', k=", as.integer(k_p),    ") + ",
      term_fs
    ))
    
    fit_fs_obj <- mgcv::bam(
      formula  = form_fs,
      data     = DT_tr,
      family   = stats::binomial(),
      method   = "fREML",
      discrete = TRUE
    )
    fits$fs <- fit_fs_obj
    
    # full score (includes season deviations)
    DT_all[, p_cls_fs_full := stats::predict(fit_fs_obj, newdata = DT_all, type = "response")]
    
    # population-level score: exclude the fs smooth label robustly
    fs_labels <- vapply(fit_fs_obj$smooth, function(sm) sm$label, character(1))
    pat <- paste0("^s\\(", week_col, ",", season_col, "\\)")
    fs_excl <- fs_labels[grepl(pat, fs_labels)]
    if (length(fs_excl) != 1L) {
      stop("fitIgnition(fs): could not uniquely identify fs smooth label for exclude=. Found: ",
           paste(fs_excl, collapse = ", "))
    }
    DT_all[, p_cls_fs_pop := stats::predict(fit_fs_obj, newdata = DT_all, type = "response", exclude = fs_excl)]
  }
  
  list(
    data = as.data.frame(DT_all),
    train_data = as.data.frame(DT_tr),
    iWeek_by_season = as.data.frame(iWeek_dt),
    fits = fits
  )
}


#' Plot classifier scores by season and model
#'
#' Visualization helper for Stage-1 classifier scores produced by [fitIgnition()].
#' It will plot any score columns that exist in \code{ign_fit$data}; missing score columns
#' are silently dropped (so it works when only the base model is fitted).
#'
#' Each facet corresponds to one \code{model | season} panel.
#' Two vertical reference lines are drawn per panel:
#' \itemize{
#'   \item dashed: truth ignition week \code{iWeek_true = min(weekF[phase==1])}.
#'   \item dotted: label endpoint week \code{iWeek_true - lead} used in classifier training.
#' }
#' Horizontal dotted lines can be added via \code{thr} to visually assess score thresholds.
#'
#' @param ign_fit Output from [fitIgnition()] (list with \code{$data}) or a data.frame.
#' @param score_cols Named character vector of score columns to plot (name used as model label).
#' @param x_col Week column to plot on x-axis. Default \code{"weekF"}.
#' @param x_max Plot only weeks \code{<= x_max}. Default \code{30}.
#' @param y_max Y-axis maximum. Default \code{0.3}.
#' @param lead Label shift used in [fitIgnition()] (dotted line at \code{iWeek_true - lead}). Default \code{1}.
#' @param thr Optional numeric vector of horizontal reference lines.
#' @param use_plotly If TRUE returns \code{plotly::ggplotly(p)}. Default TRUE.
#' @param ncol Optional integer; number of columns in \code{facet_wrap()}.
#' @return A ggplot object, or plotly object if \code{use_plotly=TRUE}.
#' @export
plot_cls_models_by_season <- function(ign_fit,
                                      score_cols = c(
                                        base  = "p_cls_p",
                                        slope = "p_cls_slope_pop",
                                        fs    = "p_cls_fs_pop"
                                      ),
                                      x_col = "weekF",
                                      x_max = 30L,
                                      y_max = 0.3,
                                      lead = 1L,
                                      thr = NULL,
                                      use_plotly = TRUE,
                                      ncol = NULL) {
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Need package: dplyr")
  if (!requireNamespace("tidyr", quietly = TRUE)) stop("Need package: tidyr")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Need package: ggplot2")
  
  dat0 <- if (is.data.frame(ign_fit)) ign_fit else ign_fit$data
  stopifnot(is.data.frame(dat0))
  
  lead  <- as.integer(lead)
  x_max <- as.integer(x_max)
  y_max <- as.numeric(y_max)
  if (!is.null(ncol)) ncol <- as.integer(ncol)
  
  keep <- unname(score_cols) %in% names(dat0)
  score_cols <- score_cols[keep]
  if (length(score_cols) == 0L) stop("plot_cls_models_by_season: none of score_cols exist in ign_fit$data.")
  
  need <- c("season", x_col, "phase", unname(score_cols))
  miss <- setdiff(need, names(dat0))
  if (length(miss)) stop("plot_cls_models_by_season: missing cols: ", paste(miss, collapse = ", "))
  
  # truth ignition week per season
  truth <- dat0 |>
    dplyr::group_by(.data$season) |>
    dplyr::summarise(
      iWeek_true = suppressWarnings(min(.data[[x_col]][.data$phase == 1L], na.rm = TRUE)),
      .groups = "drop"
    ) |>
    dplyr::mutate(iWeek_label_end = .data$iWeek_true - lead)
  
  dfp <- dat0 |>
    dplyr::select(.data$season, .data$phase, dplyr::all_of(x_col), dplyr::all_of(unname(score_cols))) |>
    dplyr::mutate(x = suppressWarnings(as.integer(.data[[x_col]]))) |>
    dplyr::filter(!is.na(.data$x), .data$x <= x_max) |>
    dplyr::left_join(truth, by = "season") |>
    tidyr::pivot_longer(
      cols = dplyr::all_of(unname(score_cols)),
      names_to = "model_col",
      values_to = "score"
    ) |>
    dplyr::mutate(
      model = factor(.data$model_col, levels = unname(score_cols), labels = names(score_cols)),
      panel = factor(paste0(.data$model, " | ", .data$season))
    ) |>
    dplyr::arrange(.data$model, .data$season, .data$x)
  
  vlines <- dfp |>
    dplyr::distinct(.data$panel, .data$iWeek_true, .data$iWeek_label_end)
  
  p <- ggplot2::ggplot(dfp, ggplot2::aes(x = .data$x, y = .data$score, group = .data$panel)) +
    ggplot2::geom_line() +
    ggplot2::geom_vline(data = vlines, ggplot2::aes(xintercept = .data$iWeek_true),
                        linetype = "dashed", inherit.aes = FALSE) +
    ggplot2::geom_vline(data = vlines, ggplot2::aes(xintercept = .data$iWeek_label_end),
                        linetype = "dotted", inherit.aes = FALSE) +
    ggplot2::facet_wrap(~panel, ncol = ncol) +
    ggplot2::coord_cartesian(
      xlim = c(min(dfp$x, na.rm = TRUE), x_max),
      ylim = c(0, y_max)
    ) +
    ggplot2::labs(x = x_col, y = "classifier score")
  
  if (!is.null(thr) && length(thr) > 0) {
    p <- p + ggplot2::geom_hline(yintercept = thr, linetype = "dotted", inherit.aes = FALSE)
  }
  
  if (isTRUE(use_plotly)) {
    if (!requireNamespace("plotly", quietly = TRUE)) stop("Need package: plotly")
    return(plotly::ggplotly(p))
  }
  p
}


#' Prospective ignition detection (M0v2) across seasons
#'
#' Applies a prospective-safe ignition detector across all seasons. The detector uses five gates:
#' \enumerate{
#'   \item classifier score gate: \code{score_col >= cls_thr}
#'   \item rolling-sum evidence gate: \code{p_sumK >= p_sum_thr} where \code{p_sumK = rollsum(p, K_sum)}
#'   \item smoothed positivity level gate: \code{p_sm >= p_thr} where \code{p_sm = rollmean(p, L)}
#'   \item cumulative prevalence gate: \code{prev >= prev_thr} where \code{prev = cumsum(y)/cumsum(N)}
#'   \item noise-tolerant trend gate on \code{p_sm} requiring sustained increases with tolerance \code{eps}
#' }
#'
#' Within the eligible window \code{w_min <= week <= w_max}, ignition is declared at the earliest
#' week where at least \code{N_req} of the five gates are satisfied (N-of-5 voting). The classifier
#' gate is a vote (not mandatory).
#'
#' @param ign_fit Either a list returned by [fitIgnition()] containing \code{$data}, or a data.frame/data.table.
#' @param params Named list of thresholds/hyperparameters.
#' @param score_col Character. Name of classifier score column. Default \code{"p_cls_p"}.
#' @param season_col,week_col Column names for season and within-season week.
#' @param y_col,N_col Column names for positives and totals.
#' @param phase_col Column name for phase indicator (used for truth if \code{truth_col} missing).
#' @param truth_col Column name for truth ignition week if stored explicitly.
#' @param keep_signals Logical. If TRUE return full row-level signals.
#' @param verbose Logical. If TRUE prints summary.
#' @param iWeek Logical. If TRUE return season-level compare table.
#' @param copy_data Logical. If FALSE operate on input data.table by reference.
#' @return list with \code{by_season} and optionally \code{data} and \code{compare}.
#' @export
detectIgnitionBySeason_M0v2 <- function(ign_fit,
                                        params,
                                        score_col = "p_cls_p",
                                        season_col = "season",
                                        week_col   = "weekF",
                                        y_col      = "y",
                                        N_col      = "N",
                                        phase_col  = "phase",
                                        truth_col  = "iWeek",
                                        keep_signals = TRUE,
                                        verbose = TRUE,
                                        iWeek = FALSE,
                                        copy_data = TRUE) {
  if (!is.list(params)) stop("params must be a list.")
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need package: data.table")
  
  dat0 <- if (is.data.frame(ign_fit) || data.table::is.data.table(ign_fit)) {
    ign_fit
  } else if (is.list(ign_fit) && is.data.frame(ign_fit$data)) {
    ign_fit$data
  } else {
    stop("detectIgnitionBySeason_M0v2(): provide a data.frame/data.table, or a list with $data.")
  }
  
  DT <- data.table::as.data.table(if (isTRUE(copy_data)) data.table::copy(dat0) else dat0)
  
  need <- c(season_col, week_col, score_col, "p", y_col, N_col)
  miss <- setdiff(need, names(DT))
  if (length(miss)) stop("detectIgnitionBySeason_M0v2: missing cols: ", paste(miss, collapse = ", "))
  
  cls_thr   <- params$cls_thr   %||% 0.20
  p_thr     <- params$p_thr     %||% 0.01
  prev_thr  <- params$prev_thr  %||% 0.01
  
  n_consec  <- as.integer(params$n_consec %||% 3L)
  L         <- as.integer(params$L %||% 2L)
  eps       <- params$eps %||% 0
  
  K_sum     <- as.integer(params$K_sum %||% 4L)
  p_sum_thr <- params$p_sum_thr %||% 0.04
  
  N_req <- as.integer(params$N_req %||% params$N %||% 3L)
  
  w_min <- as.integer(params$w_min %||% 13L)
  w_max <- as.integer(params$w_max %||% 30L)
  
  data.table::setorderv(DT, c(season_col, week_col))
  
  # prevalence evidence
  DT[, cum_y := cumsum(get(y_col)), by = season_col]
  DT[, cum_N := cumsum(get(N_col)), by = season_col]
  DT[, prev  := data.table::fifelse(cum_N > 0, cum_y / cum_N, NA_real_)]
  
  # rolling-sum evidence (prospective)
  DT[, p0 := data.table::fifelse(is.na(p), 0, p)]
  DT[, p_sumK := data.table::frollsum(p0, n = K_sum, align = "right", fill = NA_real_), by = season_col]
  
  # smoothed level + trend (prospective)
  DT[, p_sm := data.table::frollmean(p, n = L, align = "right", fill = NA_real_), by = season_col]
  DT[, dp   := p_sm - data.table::shift(p_sm, 1L, type = "lag"), by = season_col]
  
  k_inc <- max(1L, n_consec - 1L)
  DT[, inc := dp > -eps]
  need_inc <- max(1L, k_inc - 1L)
  DT[, cond_inc := data.table::frollsum(as.integer(inc), n = k_inc, align = "right", fill = NA_integer_) >= need_inc,
     by = season_col]
  
  # gates + vote count
  DT[, cond_win  := get(week_col) >= w_min & get(week_col) <= w_max]
  DT[, cond_cls  := get(score_col) >= cls_thr]
  DT[, cond_sum  := p_sumK >= p_sum_thr]
  DT[, cond_p    := p_sm >= p_thr]
  DT[, cond_prev := prev >= prev_thr]
  
  DT[, n_hit := rowSums(cbind(cond_cls, cond_sum, cond_p, cond_prev, cond_inc), na.rm = FALSE)]
  DT[, ignite_ok := cond_win & (n_hit >= N_req)]
  
  by_hat <- DT[ignite_ok %in% TRUE, .(iWeek_hat = min(get(week_col), na.rm = TRUE)), by = season_col]
  all_s  <- DT[, .(season = unique(get(season_col)))]
  data.table::setnames(all_s, "season", season_col)
  by_hat <- merge(all_s, by_hat, by = season_col, all.x = TRUE, sort = FALSE)
  
  out <- list(by_season = as.data.frame(by_hat))
  
  if (keep_signals) {
    DT2 <- merge(DT, by_hat, by = season_col, all.x = TRUE, sort = FALSE)
    DT2[, ignite_flag := !is.na(iWeek_hat) & (get(week_col) == iWeek_hat)]
    out$data <- as.data.frame(DT2)
  }
  
  if (isTRUE(iWeek)) {
    truth_dt <- NULL
    if (truth_col %in% names(DT)) {
      truth_dt <- DT[!is.na(get(truth_col)), .(iWeek_true = get(truth_col)[1L]), by = season_col]
    }
    if (is.null(truth_dt) || nrow(truth_dt) == 0L) {
      if (!(phase_col %in% names(DT))) stop("iWeek=TRUE but cannot compute truth.")
      truth_dt <- DT[get(phase_col) == 1L, .(iWeek_true = min(get(week_col), na.rm = TRUE)), by = season_col]
    }
    comp <- merge(truth_dt, by_hat, by = season_col, all.x = TRUE, sort = FALSE)
    comp[, diff := iWeek_hat - iWeek_true]
    out$compare <- as.data.frame(comp)
  }
  
  if (verbose) {
    message("[detectIgnitionBySeason_M0v2] detected seasons=", sum(!is.na(out$by_season$iWeek_hat)), " / ", nrow(out$by_season))
  }
  
  out
}


#' Grid-search tuning for M0v2 ignition detector (late- and >2-week-penalized)
#'
#' Tunes M0v2 ignition thresholds over a parameter grid by repeatedly calling
#' [detectIgnitionBySeason_M0v2()] and comparing estimated ignition weeks to season-level
#' truth ignition weeks.
#'
#' @param ign_fit Either [fitIgnition()] output (list with \code{$data}) or a data.frame/data.table.
#' @param grid data.frame of parameter combinations; missing columns are filled by defaults.
#' @param score_col Character. Classifier score column name. Default \code{"p_cls_p"}.
#' @param week_col,season_col Column names for within-season week and season.
#' @param phase_col Column name used if \code{truth_col} is unavailable.
#' @param truth_col Column name for truth ignition week if stored.
#' @param exSeason Optional character vector of seasons to exclude from tuning (but still evaluate afterward).
#' @param miss_penalty Numeric. Penalty per missing season detection.
#' @param lambda Numeric. Weight on worst-case error \code{max_abs}.
#' @param kappa Numeric. Extra weight on late errors.
#' @param gamma Numeric. Penalty for exceeding ±2 weeks.
#' @param gamma_late Numeric. Extra penalty for being late >2.
#' @param iWeek Logical. Use \code{truth_col} if available; otherwise infer from \code{phase_col}.
#' @param ncores Integer >= 1. Number of cores.
#' @param verbose Logical. Print progress.
#' @param progress_every Integer. Chunk size for progress updates.
#' @return List with best params, full results, runtime, and evaluation tables.
#' @export
tuneIgnitionGrid_M0v2 <- function(ign_fit,
                                  grid,
                                  score_col = "p_cls_p",
                                  week_col  = "weekF",
                                  season_col = "season",
                                  phase_col = "phase",
                                  truth_col = "iWeek",
                                  exSeason = NULL,
                                  miss_penalty = 20,
                                  lambda = 20,
                                  kappa = 2,
                                  gamma = 25,
                                  gamma_late = 25,
                                  iWeek = TRUE,
                                  ncores = 10L,
                                  verbose = TRUE,
                                  progress_every = 200L) {
  start_time <- Sys.time()
  pt0 <- proc.time()
  
  stopifnot(is.data.frame(grid))
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need package: data.table")
  if (!requireNamespace("parallel", quietly = TRUE)) stop("Need package: parallel")
  
  dat0 <- if (is.data.frame(ign_fit) || data.table::is.data.table(ign_fit)) {
    ign_fit
  } else if (is.list(ign_fit) && is.data.frame(ign_fit$data)) {
    ign_fit$data
  } else {
    stop("Provide a data.frame/data.table or fitIgnition output list with $data.")
  }
  
  DT_all <- data.table::as.data.table(data.table::copy(dat0))
  
  need_det <- c(season_col, week_col, "p", score_col, "y", "N")
  miss_det <- setdiff(need_det, names(DT_all))
  if (length(miss_det)) stop("tuneIgnitionGrid_M0v2: missing cols: ", paste(miss_det, collapse = ", "))
  
  seasons_all <- unique(DT_all[[season_col]])
  
  exSeason <- exSeason %||% NULL
  if (!is.null(exSeason) && length(exSeason) > 0) {
    exSeason <- intersect(as.character(exSeason), as.character(seasons_all))
  } else {
    exSeason <- character(0)
  }
  
  seasons_tune <- setdiff(as.character(seasons_all), exSeason)
  if (length(seasons_tune) == 0L) stop("All seasons excluded; nothing left to tune on.")
  
  DT_base <- DT_all[get(season_col) %in% seasons_tune]
  
  # truth: all seasons
  truth_all <- NULL
  if (isTRUE(iWeek) && truth_col %in% names(DT_all)) {
    truth_all <- DT_all[!is.na(get(truth_col)), .(iWeek_true = get(truth_col)[1L]), by = season_col]
  }
  if (is.null(truth_all) || nrow(truth_all) == 0L) {
    if (!(phase_col %in% names(DT_all))) stop("Cannot compute truth: missing iWeek and phase.")
    truth_all <- DT_all[get(phase_col) == 1L, .(iWeek_true = min(get(week_col), na.rm = TRUE)), by = season_col]
  }
  
  all_s <- DT_all[, .(season_tmp = unique(get(season_col)))]
  data.table::setnames(all_s, "season_tmp", season_col)
  truth_all <- merge(all_s, truth_all, by = season_col, all.x = TRUE, sort = FALSE)
  truth_tune <- truth_all[get(season_col) %in% seasons_tune]
  
  defaults <- list(
    cls_thr   = 0.20,
    p_thr     = 0.01,
    prev_thr  = 0.01,
    n_consec  = 3L,
    L         = 2L,
    eps       = 0,
    K_sum     = 4L,
    p_sum_thr = 0.04,
    N_req     = 3L,
    w_min     = 13L,
    w_max     = 30L
  )
  for (nm in names(defaults)) if (!nm %in% names(grid)) grid[[nm]] <- defaults[[nm]]
  
  score_one_i <- function(i) {
    params <- as.list(grid[i, , drop = FALSE])
    
    det <- detectIgnitionBySeason_M0v2(
      ign_fit = DT_base,
      params  = params,
      score_col = score_col,
      week_col  = week_col,
      season_col = season_col,
      keep_signals = FALSE,
      verbose = FALSE,
      iWeek = FALSE,
      copy_data = FALSE
    )$by_season
    
    pred <- data.table::as.data.table(det)
    if (!(season_col %in% names(pred)) && "season" %in% names(pred)) data.table::setnames(pred, "season", season_col)
    
    joined <- merge(truth_tune, pred, by = season_col, all.x = TRUE, sort = FALSE)
    
    joined[, diff := iWeek_hat - iWeek_true]
    joined[, abs_diff := abs(diff)]
    joined[, late := pmax(diff, 0)]
    joined[, over2 := pmax(abs_diff - 2, 0)]
    joined[, late_over2 := pmax(diff - 2, 0)]
    joined[, miss := is.na(iWeek_hat)]
    
    n_miss <- sum(joined$miss)
    n_over2 <- sum(joined$abs_diff > 2, na.rm = TRUE)
    n_late_over2 <- sum(joined$diff > 2, na.rm = TRUE)
    
    sum_loss <- sum(
      joined$abs_diff +
        kappa * joined$late +
        gamma * joined$over2 +
        gamma_late * joined$late_over2,
      na.rm = TRUE
    )
    
    max_abs <- if (all(is.na(joined$abs_diff))) Inf else max(joined$abs_diff, na.rm = TRUE)
    score <- sum_loss + lambda * max_abs + miss_penalty * n_miss
    
    c(score = score,
      sum_loss = sum_loss,
      max_abs = max_abs,
      n_miss = n_miss,
      n_over2 = n_over2,
      n_late_over2 = n_late_over2,
      mean_abs = mean(joined$abs_diff, na.rm = TRUE))
  }
  
  idx <- seq_len(nrow(grid))
  ncores <- as.integer(ncores %||% 1L)
  if (is.na(ncores) || ncores < 1L) ncores <- 1L
  
  if (verbose) {
    message("[tuneIgnitionGrid_M0v2] tuning seasons=", length(seasons_tune),
            " excluded=", length(exSeason),
            " grid=", length(idx),
            " ncores=", ncores,
            " os=", .Platform$OS.type)
    if (length(exSeason)) message("[tuneIgnitionGrid_M0v2] exSeason: ", paste(exSeason, collapse = ", "))
  }
  
  if (ncores == 1L) {
    metrics <- t(vapply(idx, score_one_i, numeric(7)))
    colnames(metrics) <- c("score","sum_loss","max_abs","n_miss","n_over2","n_late_over2","mean_abs")
  } else {
    if (identical(.Platform$OS.type, "windows")) {
      cl <- parallel::makeCluster(ncores)
      on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
      parallel::clusterEvalQ(cl, { library(data.table); NULL })
      parallel::clusterExport(
        cl,
        varlist = c("DT_base","grid","truth_tune","score_col","week_col","season_col",
                    "miss_penalty","lambda","kappa","gamma","gamma_late",
                    "detectIgnitionBySeason_M0v2","score_one_i","%||%"),
        envir = environment()
      )
      chunks <- split(idx, ceiling(seq_along(idx) / progress_every))
      res_list <- lapply(chunks, function(ch) parallel::parLapply(cl, ch, score_one_i))
      metrics <- do.call(rbind, lapply(res_list, function(x) do.call(rbind, x)))
    } else {
      chunks <- split(idx, ceiling(seq_along(idx) / progress_every))
      res_list <- lapply(chunks, function(ch) parallel::mclapply(ch, score_one_i, mc.cores = ncores))
      metrics <- do.call(rbind, lapply(res_list, function(x) do.call(rbind, x)))
    }
  }
  
  res <- cbind(grid, as.data.frame(metrics))
  
  o <- with(res, order(n_over2, n_late_over2, max_abs, n_miss, score))
  best_row <- res[o[1], , drop = FALSE]
  
  best_params <- as.list(best_row[, c(
    "cls_thr","p_thr","prev_thr","n_consec","L","eps","K_sum","p_sum_thr","N_req","w_min","w_max"
  ), drop = FALSE])
  
  # evaluate on all seasons (including excluded)
  det_all <- detectIgnitionBySeason_M0v2(
    ign_fit = DT_all,
    params  = best_params,
    score_col = score_col,
    week_col  = week_col,
    season_col = season_col,
    keep_signals = FALSE,
    verbose = FALSE,
    iWeek = FALSE,
    copy_data = FALSE
  )$by_season
  
  pred_all <- data.table::as.data.table(det_all)
  if (!(season_col %in% names(pred_all)) && "season" %in% names(pred_all)) data.table::setnames(pred_all, "season", season_col)
  
  eval_all <- merge(truth_all, pred_all, by = season_col, all.x = TRUE, sort = FALSE)
  eval_all[, diff := iWeek_hat - iWeek_true]
  
  eval_tune <- eval_all[get(season_col) %in% seasons_tune]
  eval_excl <- if (length(exSeason)) eval_all[get(season_col) %in% exSeason] else eval_all[0]
  
  elapsed_sec <- unname((proc.time() - pt0)[["elapsed"]])
  runtime <- list(start_time = start_time, end_time = Sys.time(), elapsed_seconds = elapsed_sec,
                  n_grid = nrow(grid), ncores = ncores, os = .Platform$OS.type,
                  seasons_tuned = length(seasons_tune), seasons_excluded = length(exSeason))
  
  if (verbose) {
    message("[tuneIgnitionGrid_M0v2] best: n_over2=", best_row$n_over2,
            " n_late_over2=", best_row$n_late_over2,
            " max_abs=", best_row$max_abs,
            " n_miss=", best_row$n_miss,
            " score=", best_row$score)
    message("[tuneIgnitionGrid_M0v2] params: ",
            paste(names(best_params), unlist(best_params), sep="=", collapse=", "))
    message("[tuneIgnitionGrid_M0v2] runtime: ", round(elapsed_sec, 2), " sec")
  }
  
  list(
    best_params = best_params,
    results = res,
    best_row = best_row,
    truth_all = as.data.frame(truth_all),
    truth_tune = as.data.frame(truth_tune),
    runtime = runtime,
    exSeason = exSeason,
    seasons_tune = seasons_tune,
    eval_all = as.data.frame(eval_all),
    eval_tune = as.data.frame(eval_tune),
    eval_excluded = as.data.frame(eval_excl)
  )
}


# ============================================================
# LOSO wrapper for M0v2 (strict): refit classifier each fold
# Requires: fitIgnition(), tuneIgnitionGrid_M0v2(), detectIgnitionBySeason_M0v2()
# ============================================================

loso_M0v2 <- function(dat,
                      grid,
                      # pass-through knobs
                      season_col = "season",
                      week_col   = "weekF",
                      phase_col  = "phase",
                      p_col      = "p",
                      score_col  = "p_cls_p",
                      # optional: exclude some seasons from BOTH training+evaluation
                      drop_seasons = NULL,
                      # extra exclusions for tuning only (in addition to the heldout season)
                      exSeason_tune = NULL,
                      # arguments passed to fitIgnition() each fold
                      fit_args = list(
                        fit_base = TRUE,
                        fit_slope = FALSE,
                        fit_fs = FALSE,
                        event_k = 1L,
                        lead = 1L,
                        A_pre = 6L,
                        B_post = 6L,
                        k_week = 6L,
                        k_p = 8L,
                        k_fs = 4L,
                        select = FALSE,
                        verbose = FALSE
                      ),
                      # arguments passed to tuneIgnitionGrid_M0v2() each fold
                      tune_args = list(
                        miss_penalty = 20,
                        lambda = 20,
                        kappa = 2,
                        gamma = 25,
                        gamma_late = 25,
                        iWeek = TRUE,
                        ncores = 10L,
                        verbose = FALSE,
                        progress_every = 200L
                      ),
                      verbose = TRUE) {
  
  `%||%` <- function(x, y) if (!is.null(x)) x else y
  mode1 <- function(x) {
    x <- x[!is.na(x)]
    if (!length(x)) return(NA)
    ux <- unique(x)
    ux[which.max(tabulate(match(x, ux)))]
  }
  
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need package: data.table")
  stopifnot(is.data.frame(dat), is.data.frame(grid))
  
  DT <- data.table::as.data.table(data.table::copy(dat))
  
  # optionally drop some seasons entirely
  if (!is.null(drop_seasons) && length(drop_seasons) > 0) {
    DT <- DT[!(get(season_col) %in% drop_seasons)]
  }
  
  seasons <- sort(unique(as.character(DT[[season_col]])))
  if (length(seasons) < 2L) stop("Need at least 2 seasons for LOSO.")
  
  t0_all <- proc.time()
  start_time <- Sys.time()
  
  fold_out <- vector("list", length(seasons))
  names(fold_out) <- seasons
  
  for (ss in seasons) {
    if (verbose) message("[loso_M0v2] fold holdout=", ss)
    
    DT_train <- DT[get(season_col) != ss]
    DT_test  <- DT[get(season_col) == ss]
    
    # ---- 1) refit classifier on training seasons ----
    t_fit0 <- proc.time()
    fit_call <- c(list(
      dat = as.data.frame(DT_train),
      season_col = season_col,
      week_col   = week_col,
      phase_col  = phase_col,
      p_col      = p_col
    ), fit_args)
    ign_fit <- do.call(fitIgnition, fit_call)
    t_fit <- unname((proc.time() - t_fit0)[["elapsed"]])
    
    DT_train_scored <- data.table::as.data.table(ign_fit$data)
    
    # ---- 2) score heldout season using fold classifier (population-level) ----
    if (is.null(ign_fit$fits$base) || is.null(ign_fit$fits$base$gam)) {
      stop("loso_M0v2: fitIgnition did not produce fits$base$gam; ensure fit_base=TRUE.")
    }
    gam_base <- ign_fit$fits$base$gam
    p_hat <- stats::predict(gam_base, newdata = as.data.frame(DT_test), type = "response")
    
    DT_test_scored <- data.table::copy(DT_test)
    DT_test_scored[, (score_col) := p_hat]
    if (!("p_cls_base_pop" %in% names(DT_test_scored)) && score_col == "p_cls_p") {
      DT_test_scored[, p_cls_base_pop := get(score_col)]
    }
    
    # ---- 3) tune detector thresholds on training seasons only ----
    t_tune0 <- proc.time()
    tune_call <- c(list(
      ign_fit    = as.data.frame(DT_train_scored),
      grid       = grid,
      score_col  = score_col,
      week_col   = week_col,
      season_col = season_col,
      phase_col  = phase_col,
      truth_col  = tune_args$truth_col %||% "iWeek",
      exSeason   = exSeason_tune
    ), tune_args)
    
    tuned <- do.call(tuneIgnitionGrid_M0v2, tune_call)
    t_tune <- unname((proc.time() - t_tune0)[["elapsed"]])
    best_params <- tuned$best_params
    
    # ---- 4) apply detector to heldout season ----
    t_det0 <- proc.time()
    det <- detectIgnitionBySeason_M0v2(
      ign_fit = as.data.frame(DT_test_scored),
      params  = best_params,
      score_col = score_col,
      week_col  = week_col,
      season_col = season_col,
      phase_col  = phase_col,
      keep_signals = FALSE,
      verbose = FALSE,
      iWeek = TRUE,
      copy_data = TRUE
    )
    t_det <- unname((proc.time() - t_det0)[["elapsed"]])
    
    comp <- det$compare
    comp <- comp[match(ss, comp[[season_col]]), , drop = FALSE]
    
    fold_out[[ss]] <- list(
      season = ss,
      best_params = best_params,
      compare = comp,
      timing = list(
        fit_seconds  = t_fit,
        tune_seconds = t_tune,
        detect_seconds = t_det
      )
    )
  }
  
  # ---- bind fold results ----
  comp_all <- data.table::rbindlist(lapply(fold_out, function(x) data.table::as.data.table(x$compare)),
                                    fill = TRUE)
  comp_all[, abs_diff := abs(diff)]
  
  summary <- list(
    n_seasons = nrow(comp_all),
    n_miss = sum(is.na(comp_all$iWeek_hat)),
    mean_abs = mean(comp_all$abs_diff, na.rm = TRUE),
    median_abs = stats::median(comp_all$abs_diff, na.rm = TRUE),
    max_abs = suppressWarnings(max(comp_all$abs_diff, na.rm = TRUE)),
    mean_diff = mean(comp_all$diff, na.rm = TRUE)
  )
  
  # ---- NEW: aggregate a single best parameter set from fold-specific best_params ----
  bp_df <- data.table::rbindlist(lapply(fold_out, function(x) data.table::as.data.table(x$best_params)),
                                 fill = TRUE)
  
  # expected parameter names (only aggregate those that exist)
  num_par <- intersect(c("cls_thr","p_thr","prev_thr","p_sum_thr","eps"), names(bp_df))
  int_par <- intersect(c("n_consec","L","K_sum","N_req","w_min","w_max"), names(bp_df))
  
  best_params_loso <- list()
  for (nm in num_par) best_params_loso[[nm]] <- as.numeric(stats::median(as.numeric(bp_df[[nm]]), na.rm = TRUE))
  for (nm in int_par) best_params_loso[[nm]] <- as.integer(mode1(as.integer(bp_df[[nm]])))
  
  # runtime
  elapsed_all <- unname((proc.time() - t0_all)[["elapsed"]])
  runtime <- list(
    start_time = start_time,
    end_time = Sys.time(),
    elapsed_seconds = elapsed_all,
    n_folds = length(seasons)
  )
  
  list(
    folds = fold_out,
    compare = as.data.frame(comp_all),
    summary = summary,
    runtime = runtime,
    
    # NEW outputs
    best_params = best_params_loso,
    best_params_by_fold = as.data.frame(bp_df)
  )
}  
  
  #' Plot truth vs detected ignition week by season (faceted)
  #'
  #' @param det_out Output list from detectIgnitionBySeason_M0v2().
  #'   Must contain $data with per-week rows. If $compare is present, it is used for
  #'   truth/hat weeks; otherwise it will be constructed from phase==1 and $by_season.
  #' @param x_col Week index column. Default "weekF".
  #' @param y_cols Character vector of columns to plot as time series (if present).
  #'   Default c("p","p_sm").
  #' @param x_max Optional max week to plot (e.g., 30). Default 30.
  #' @param ncol Facet columns. Default 4.
  #' @param y_max Optional y-axis max (e.g., 0.3). Default NULL (no cap).
  #' @param use_plotly If TRUE return plotly::ggplotly(p). Default TRUE.
  #'
  #' @return ggplot or plotly object.
  #' @export
  plot_ignition_detect_vs_truth <- function(det_out,
                                            x_col = "weekF",
                                            y_cols = c("p", "p_sm"),
                                            x_max = 30L,
                                            ncol = 4L,
                                            y_max = NULL,
                                            use_plotly = TRUE) {
    if (!requireNamespace("dplyr", quietly = TRUE)) stop("Need package: dplyr")
    if (!requireNamespace("tidyr", quietly = TRUE)) stop("Need package: tidyr")
    if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Need package: ggplot2")
    
    if (!is.list(det_out) || is.null(det_out$data)) {
      stop("det_out must be the list returned by detectIgnitionBySeason_M0v2() with $data.")
    }
    df <- det_out$data
    
    if (!("season" %in% names(df))) stop("det_out$data must contain column: season")
    if (!(x_col %in% names(df))) stop("det_out$data must contain x_col: ", x_col)
    
    # build compare table if not provided
    comp <- det_out$compare
    if (is.null(comp) || !all(c("season","iWeek_hat") %in% names(comp))) {
      if (is.null(det_out$by_season) || !all(c("season","iWeek_hat") %in% names(det_out$by_season))) {
        stop("det_out must contain $compare or $by_season with columns season,iWeek_hat.")
      }
      if (!("phase" %in% names(df))) {
        stop("Cannot infer truth ignition week: det_out$data has no 'phase' and det_out$compare is missing.")
      }
      truth <- df |>
        dplyr::group_by(.data$season) |>
        dplyr::summarise(
          iWeek_true = suppressWarnings(min(.data[[x_col]][.data$phase == 1L], na.rm = TRUE)),
          .groups = "drop"
        )
      comp <- truth |>
        dplyr::left_join(det_out$by_season, by = "season") |>
        dplyr::mutate(diff = .data$iWeek_hat - .data$iWeek_true)
    }
    
    # keep only y columns that exist
    y_cols <- y_cols[y_cols %in% names(df)]
    if (length(y_cols) == 0L) stop("None of y_cols exist in det_out$data: ", paste(y_cols, collapse = ", "))
    
    x_max <- as.integer(x_max)
    ncol  <- as.integer(ncol)
    
    # long data for plotting multiple series on same panel
    dfp <- df |>
      dplyr::mutate(.x = suppressWarnings(as.integer(.data[[x_col]]))) |>
      dplyr::filter(!is.na(.data$.x), .data$.x <= x_max) |>
      dplyr::select(.data$season, .data$.x, dplyr::all_of(y_cols)) |>
      tidyr::pivot_longer(cols = dplyr::all_of(y_cols),
                          names_to = "series",
                          values_to = "value") |>
      dplyr::arrange(.data$season, .data$series, .data$.x)
    
    vlines <- comp |>
      dplyr::select(.data$season, .data$iWeek_true, .data$iWeek_hat) |>
      dplyr::distinct()
    
    p <- ggplot2::ggplot(dfp, ggplot2::aes(x = .data$.x, y = .data$value, group = .data$series)) +
      ggplot2::geom_line() +
      ggplot2::facet_wrap(~season, ncol = ncol) +
      ggplot2::geom_vline(
        data = vlines,
        ggplot2::aes(xintercept = .data$iWeek_true),
        linetype = "dashed",
        inherit.aes = FALSE
      ) +
      ggplot2::geom_vline(
        data = vlines,
        ggplot2::aes(xintercept = .data$iWeek_hat),
        linetype = "solid",
        inherit.aes = FALSE
      ) +
      ggplot2::labs(x = x_col, y = "value")
    
    if (!is.null(y_max)) {
      p <- p + ggplot2::coord_cartesian(ylim = c(0, as.numeric(y_max)))
    }
    
    # Optional: show a legend only if multiple series are plotted
    if (length(y_cols) > 1L) {
      p <- p + ggplot2::aes(linetype = .data$series) + ggplot2::guides(linetype = ggplot2::guide_legend(title = NULL))
    }
    
    if (isTRUE(use_plotly)) {
      if (!requireNamespace("plotly", quietly = TRUE)) stop("Need package: plotly")
      return(plotly::ggplotly(p))
    }
    p
  }