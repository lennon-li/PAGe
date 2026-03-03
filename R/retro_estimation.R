# Retrospective estimation utilities
# - Stage-1 ignition classifier fitting and retrospective tuning/evaluation
# - These functions may use full-season information and multi-season grids


`%||%` <- function(x, y) if (!is.null(x)) x else y




#' Grid search ignition detection parameters (OS-aware parallel)
#'
#' Tunes ignition detection thresholds over a parameter grid by repeatedly calling
#' \code{\link{detectIgnitionBySeason}} and comparing predicted ignition weeks to
#' historical "true" ignition weeks inferred from `phase==1`.
#'
#' The evaluation is parallelized in an OS-aware way:
#' - Windows: PSOCK cluster (`parallel::makeCluster()` + `parLapply()`)
#' - Linux/macOS: forked processes (`parallel::mclapply()`)
#'
#' ## Required columns
#' `dat` must contain:
#' - `season`, `weekF`, `phase`, `p`, `p_cls_p`, `y`, `N`
#'
#' ## Truth definition
#' For each season, the "true" ignition week is:
#' `iWeek_true = min(weekF[phase == 1])`.
#'
#' ## Scoring
#' For each parameter set, the function computes:
#' - `diff = iWeek_hat - iWeek_true`
#' - `sum_abs = sum(abs(diff))` across seasons (ignoring `NA` diffs)
#' - `max_abs = max(abs(diff))` across seasons (worst-case; `Inf` if all missing)
#' - `n_miss =` number of seasons with `iWeek_hat = NA`
#' - `score = sum_abs + lambda * max_abs + miss_penalty * n_miss`
#'
#' Selection is lexicographic:
#' 1) minimize `sum_abs`
#' 2) among parameter sets with `sum_abs <= min(sum_abs) + sum_tol`, minimize `max_abs`
#' 3) tie-breakers: minimize `n_miss`, then minimize `score`
#'
#' @param dat Multi-season data.frame with required columns.
#' @param grid data.frame of parameter combinations. Any missing parameter columns
#' among `cls_thr`, `p_cum_thr`, `p_thr`, `prev_thr`, `n_consec`, `N`, `w_min`, `w_max`
#' will be filled with defaults (see below).
#' @param miss_penalty Numeric. Penalty added per missing season detection (`iWeek_hat=NA`).
#' Default 20.
#' @param lambda Numeric. Weight on the worst-case absolute error `max_abs` in the combined `score`.
#' Default 10.
#' @param sum_tol Numeric >= 0. Tolerance applied when forming the candidate set after minimizing
#' `sum_abs`: keep rows with `sum_abs <= min_sum + sum_tol`. Default 0.
#' @param ncores Integer >= 1. Number of cores. If 1, runs serially. Default 10.
#' @param verbose Logical. If `TRUE`, prints progress and best result summary. Default `TRUE`.
#' @param progress_every Integer. Master-side progress update frequency (in number of grid rows).
#' Default 200.
#'
#' @return A list with:
#' \describe{
#'   \item{best_params}{Named list of best parameter values (subset of columns in `grid`).}
#'   \item{results}{data.frame = `grid` plus evaluation metrics (`score`, `sum_abs`, `max_abs`, `n_miss`, `mean_abs`, `sd_abs`).}
#'   \item{best_row}{Single-row data.frame containing the best parameter set and its metrics.}
#' }
#'
#' @export
tuneIgnitionGrid <- function(dat, grid,
                             miss_penalty = 20,
                             lambda = 10,
                             sum_tol = 0,
                             ncores = 10L,
                             verbose = TRUE,
                             progress_every = 200L) {
  stopifnot(is.data.frame(dat), is.data.frame(grid))
  requireNamespace("dplyr")
  
  need <- c("season", "weekF", "phase", "p", "p_cls_p", "y", "N")
  miss <- setdiff(need, names(dat))
  if (length(miss)) stop("tuneIgnitionGrid: dat missing cols: ", paste(miss, collapse = ", "))
  
  truth <- dat %>%
    dplyr::group_by(season) %>%
    dplyr::summarise(
      iWeek_true = suppressWarnings(min(weekF[phase == 1L], na.rm = TRUE)),
      .groups = "drop"
    )
  if (nrow(truth) == 0L) stop("tuneIgnitionGrid: no phase==1 found; cannot compute iWeek_true.")
  
  defaults <- list(
    cls_thr = 0.25,
    p_cum_thr = 0.20,
    p_thr = 0.01,
    prev_thr = 0.01,     # NEW
    n_consec = 3L,
    N = 3L,
    w_min = 13L,
    w_max = 30L
  )
  for (nm in names(defaults)) if (!nm %in% names(grid)) grid[[nm]] <- defaults[[nm]]
  #' Score one parameter setting (internal)
  #'
  #' Internal helper for `tuneIgnitionGrid()`; evaluates one row of the tuning grid.
  #'
  #' @param i Integer row index into the tuning grid.
  #'
  #' @return A 1-row data.frame of scores for this grid setting.
  #' @keywords internal
  
  
  score_one_i <- function(i) {
    params <- as.list(grid[i, , drop = FALSE])
    
    det_out <- detectIgnitionBySeason(dat, params, keep_signals = FALSE, verbose = FALSE)
    pred <- det_out$by_season[, c("season", "iWeek_hat")]
    
    joined <- dplyr::left_join(truth, pred, by = "season") %>%
      dplyr::mutate(
        diff = iWeek_hat - iWeek_true,
        abs_diff = abs(diff),
        miss = is.na(iWeek_hat)
      )
    
    n_miss  <- sum(joined$miss)
    sum_abs <- sum(joined$abs_diff, na.rm = TRUE)
    max_abs <- if (all(is.na(joined$abs_diff))) Inf else max(joined$abs_diff, na.rm = TRUE)
    
    score <- sum_abs + lambda * max_abs + miss_penalty * n_miss
    
    c(score = score, sum_abs = sum_abs, max_abs = max_abs,
      n_miss = n_miss, mean_abs = mean(joined$abs_diff, na.rm = TRUE),
      sd_abs = stats::sd(joined$abs_diff, na.rm = TRUE))
  }
  
  idx <- seq_len(nrow(grid))
  ncores <- as.integer(ncores %||% 1L)
  if (is.na(ncores) || ncores < 1L) ncores <- 1L
  
  if (verbose) {
    message("[tuneIgnitionGrid] evaluating ", length(idx), " parameter sets...",
            "  ncores=", ncores,
            "  os=", .Platform$OS.type)
  }
  
  if (ncores == 1L) {
    metrics <- matrix(NA_real_, nrow = length(idx), ncol = 6)
    colnames(metrics) <- c("score","sum_abs","max_abs","n_miss","mean_abs","sd_abs")
    for (ii in idx) {
      metrics[ii, ] <- score_one_i(ii)
      if (verbose && (ii %% progress_every == 0L)) {
        message("[tuneIgnitionGrid] progress ", ii, "/", length(idx))
      }
    }
  } else {
    requireNamespace("parallel")
    
    if (identical(.Platform$OS.type, "windows")) {
      cl <- parallel::makeCluster(ncores)
      on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
      parallel::clusterEvalQ(cl, { library(dplyr); NULL })
      
      parallel::clusterExport(
        cl,
        varlist = c("dat","truth","grid","miss_penalty","lambda",
                    "detectIgnitionBySeason","detectIgnition_oneSeason","%||%",
                    "score_one_i"),
        envir = environment()
      )
      
      chunks <- split(idx, ceiling(seq_along(idx) / progress_every))
      res_list <- vector("list", length(chunks))
      done <- 0L
      for (cc in seq_along(chunks)) {
        res_list[[cc]] <- parallel::parLapply(cl, chunks[[cc]], score_one_i)
        done <- done + length(chunks[[cc]])
        if (verbose) message("[tuneIgnitionGrid] progress ", done, "/", length(idx))
      }
      metrics <- do.call(rbind, lapply(res_list, function(x) do.call(rbind, x)))
      
    } else {
      chunks <- split(idx, ceiling(seq_along(idx) / progress_every))
      res_list <- vector("list", length(chunks))
      done <- 0L
      for (cc in seq_along(chunks)) {
        res_list[[cc]] <- parallel::mclapply(chunks[[cc]], score_one_i, mc.cores = ncores)
        done <- done + length(chunks[[cc]])
        if (verbose) message("[tuneIgnitionGrid] progress ", done, "/", length(idx))
      }
      metrics <- do.call(rbind, lapply(res_list, function(x) do.call(rbind, x)))
    }
  }
  
  res <- cbind(grid, as.data.frame(metrics))
  
  min_sum <- min(res$sum_abs, na.rm = TRUE)
  cand <- res[res$sum_abs <= (min_sum + sum_tol), , drop = FALSE]
  
  best_i <- with(cand, {
    o <- order(max_abs, n_miss, score)
    rownames(cand)[o[1]]
  })
  best_row <- cand[best_i, , drop = FALSE]
  
  best_params <- as.list(best_row[, c(
    "cls_thr","p_cum_thr","p_thr","prev_thr","n_consec","N","w_min","w_max"
  ), drop = FALSE])
  
  if (verbose) {
    message("[tuneIgnitionGrid] best sum_abs=", best_row$sum_abs,
            " max_abs=", best_row$max_abs,
            " n_miss=", best_row$n_miss,
            " score=", best_row$score)
    message("[tuneIgnitionGrid] best params: ",
            paste(names(best_params), unlist(best_params), sep="=", collapse=", "))
  }
  
  list(best_params = best_params, results = res, best_row = best_row)
}

#' Plot ignition detection results (faceted)
#'
#' Convenience plotter for the output of `detectIgnitionBySeason()` / `tuneIgnitionGrid()`.
#' Draws week-by-week signals and estimated ignition week by season.
#'
#' @param det_out Output from `detectIgnitionBySeason()` (or a compatible object
#'   that includes the per-week signals and season identifiers).
#' @param smooth_col Optional name of a column in `det_out$signals` (or equivalent)
#'   used for an additional smooth/line layer. Default `NULL`.
#'
#' @return A ggplot object.
#' @export

plot_det_facet <- function(det_out, smooth_col = NULL) {
  stopifnot(is.list(det_out), is.data.frame(det_out$data), is.data.frame(det_out$by_season))
  df <- det_out$data
  
  # decide smoothed column
  if (is.null(smooth_col)) {
    smooth_col <- if ("fit" %in% names(df)) "fit" else "p_cls_p"
  }
  if (!smooth_col %in% names(df)) stop("smooth_col not found: ", smooth_col)
  
  # true + estimated ignition weeks
  truth <- df %>%
    group_by(season) %>%
    summarise(iWeek_true = suppressWarnings(min(weekF[phase == 1L], na.rm = TRUE)),
              .groups = "drop")
  
  ann <- truth %>%
    left_join(det_out$by_season %>% select(season, iWeek_hat), by = "season")
  
  # plotting data
  df_plot <- df %>%
    select(season, weekF, p, smoothed = all_of(smooth_col))
  
  ggplot(df_plot, aes(x = weekF)) +
    # observed dots
    geom_point(aes(y = p), size = 1.2, alpha = 0.8, color = "red") +
    # smoothed line
    geom_line(aes(y = smoothed), linewidth = 0.7) +
    # ignition lines
    geom_vline(data = ann, aes(xintercept = iWeek_true), linewidth = 0.6) +
    geom_vline(data = ann, aes(xintercept = iWeek_hat), linewidth = 0.6, linetype = "dashed") +
    facet_wrap(~ season, scales = "free_y") +
    labs(
      x = "weekF",
      y = "p / smoothed",
      title = "Ignition detection by season",
      subtitle = paste0("Dots = observed p; line = ", smooth_col,
                        "; solid vline = true ignition; dashed vline = estimated ignition")
    ) +
    theme_bw()
}

#' Estimate a reference (template) curve for influenza positivity
#'
#' Fits a season-pooled binomial GAMM (via \code{gamm4}) on aligned week index
#' \code{newWeek}, with a cyclic smooth and a season random intercept. Returns
#' a link-scale reference function \code{g_ref_fun} (spline over weeks),
#' a helper \code{g_ref_mu_se(u)} that returns link-scale mean and SE at arbitrary
#' \code{u}, and probability-scale reference data frames for plotting.
#'
#' @param alignedD Data frame containing aligned seasonal data with at least:
#'   \code{season}, \code{newWeek}, \code{y}, \code{neg}. Optionally contains \code{N}.
#' @param exSeason Optional character vector of season labels to exclude from
#'   reference-curve estimation (e.g., c("2020-21","2021-22")).
#' @param k Basis dimension for the cyclic smooth \code{s(newWeek, bs="cc", k=k)}.
#' @param n_weeks Integer. Number of weeks in the template domain (default 52).
#'   If you want to support 53-week seasons, you can set this to 53, but then you
#'   should also change the clamping and grid logic consistently.
#' @param nAGQ Passed to \code{gamm4}; default 1 (Laplace).
#'
#' @return A list with components:
#' \describe{
#'   \item{mod2}{The fitted \code{gamm4} object.}
#'   \item{g_ref_fun}{Function(u): natural spline of link-scale fitted values.}
#'   \item{g_ref_safe}{Function(u): \code{g_ref_fun} with u clamped to 1..n_weeks.}
#'   \item{g_ref_mu_se}{Function(u): returns list(mu, se) on link scale from the GAM.}
#'   \item{ref_df}{Tibble with \code{newWeek} and \code{p_gamm} = plogis(g_ref_fun).}
#'   \item{pred_df}{Tibble with \code{newWeek, fit, se.fit, low, high} on prob scale.}
#'   \item{anchorWeek}{Anchor week attribute if present on \code{alignedD}, else NA.}
#' }
#'
#' @export
estimateRef <- function(alignedD,
                        #' @param exSeason Optional character vector of seasons to exclude.
                        exSeason = NULL,
                        k = 10,
                        n_weeks = 52L,
                        nAGQ = 1) {
  
  # --- deps ---
  if (!requireNamespace("gamm4",  quietly = TRUE)) stop("Need 'gamm4'.")
  if (!requireNamespace("mgcv",   quietly = TRUE)) stop("Need 'mgcv'.")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Need 'tibble'.")
  if (!requireNamespace("dplyr",  quietly = TRUE)) stop("Need 'dplyr'.")
  if (!requireNamespace("gratia", quietly = TRUE)) stop("Need 'gratia' (used for derivatives).")
  
  needed <- c("season", "newWeek", "y", "neg")
  miss <- setdiff(needed, names(alignedD))
  if (length(miss) > 0) stop("alignedD is missing columns: ", paste(miss, collapse = ", "))
  
  # --- filter seasons if requested ---
  dat <- alignedD
  if (!is.null(exSeason) && length(exSeason) > 0) {
    dat <- dplyr::filter(dat, !(.data$season %in% exSeason))
  }
  
  # --- clamp week domain used for template (match your behavior) ---
  dat <- dplyr::mutate(dat, newWeek = pmin(as.integer(.data$newWeek), as.integer(n_weeks)))
  
  # --- fit common trend GAMM (binomial counts) ---
  mod2 <- gamm4::gamm4(
    cbind(y, neg) ~ s(newWeek, bs = "cc", k = k),
    random = ~(1 | season),
    data   = dat,
    family = stats::binomial(),
    nAGQ   = nAGQ
  )
  
  # --- build link-scale reference spline over 1..n_weeks ---
  grid <- data.frame(newWeek = seq_len(n_weeks))
  
  eta_hat   <- drop(stats::predict(mod2$gam, newdata = grid, type = "link"))
  g_ref_fun <- stats::splinefun(grid$newWeek, eta_hat, method = "natural")
  
  # safe clamp to [1, n_weeks] for any callers
  g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1L), n_weeks))
  
  # --- add per-row reference-curve estimate (aligned to newWeek after clamping) ---
  # This is the reference curve evaluated at each row's newWeek.
  dat <- dplyr::mutate(dat, fit_ref = stats::plogis(g_ref_safe(.data$newWeek)))
  
  # --- ref_df on prob scale ---
  weeks <- seq_len(n_weeks)
  ref_df <- tibble::tibble(
    newWeek = weeks,
    p_gamm  = stats::plogis(g_ref_fun(weeks))
  )
  
  # --- prob-scale curve + CI (your combined binomial + smooth SE approach) ---
  pr <- stats::predict(
    mod2$gam,
    newdata = dplyr::mutate(grid, season = "fit"),
    type    = "response",
    se.fit  = TRUE
  )
  
  # N for binom.se: use median N by newWeek if available, else set NA and skip binom.se
  if ("N" %in% names(dat)) {
    N_med <- tapply(dat$N, dat$newWeek, stats::median, na.rm = TRUE)
    N_vec <- as.numeric(N_med[as.character(grid$newWeek)])
  } else {
    N_vec <- rep(NA_real_, nrow(grid))
  }
  
  fit    <- as.numeric(pr$fit)
  se_fit <- as.numeric(pr$se.fit)
  
  binom_se <- if (all(is.na(N_vec))) rep(0, length(fit)) else sqrt(pmax(0, fit * (1 - fit) / N_vec))
  total_se <- sqrt(binom_se^2 + se_fit^2)
  
  low  <- pmax(0, fit - 1.96 * total_se)
  high <- pmin(1, fit + 1.96 * total_se)
  
  # derivatives on link scale at grid points (once each)
  d1_eta <- gratia::derivatives(mod2$gam, order = 1, se = TRUE, data = grid)$.derivative
  d2_eta <- gratia::derivatives(mod2$gam, order = 2, se = TRUE, data = grid)$.derivative
  
  pred_df <- tibble::tibble(
    newWeek  = grid$newWeek,
    fit      = fit,
    se.fit   = se_fit,
    binom.se = binom_se,
    total.se = total_se,
    low      = low,
    high     = high,
    season   = "fit",
    d1_eta   = d1_eta,
    d2_eta   = d2_eta,
    d1_p     = fit * (1 - fit) * d1_eta,
    d2_p     = fit * (1 - fit) * d2_eta + fit * (1 - fit) * (1 - 2 * fit) * (d1_eta^2)
  )
  
  anchorWeek <- attr(alignedD, "anchorWeek")
  if (is.null(anchorWeek)) anchorWeek <- NA_integer_
  
  # --- link-scale mean+SE function at arbitrary u ---
  g_ref_mu_se <- (function(gam_obj) {
    function(u) {
      nd  <- data.frame(newWeek = u)
      out <- stats::predict(gam_obj, newdata = nd, type = "link", se.fit = TRUE)
      list(mu = drop(out$fit), se = drop(out$se.fit))
    }
  })(mod2$gam)
  
  list(
    mod2        = mod2,
    g_ref_fun   = g_ref_fun,
    g_ref_safe  = g_ref_safe,
    g_ref_mu_se = g_ref_mu_se,
   # ref_df      = ref_df,
    pred_df     = pred_df,
    dat         = dat,        # now includes fit_ref per row (season-aligned)
    anchorWeek  = anchorWeek
  )
}

#' Estimate smoothed positivity and derivatives (d1/d2) by season using binomial GAMs
#'
#' Fits a separate binomial GAM for each season to smooth weekly positivity and
#' computes first and second derivatives of the fitted smooth. Returns the input
#' data augmented with fitted values, confidence intervals, and derivative estimates
#' (with simultaneous intervals), plus the fitted model objects.
#'
#' @param allD A data.frame containing (at minimum) season, week index, positives, and tests.
#' @param k Integer. Basis dimension passed to \code{mgcv::s()} for the within-season smooth.
#' @param bs Character. Smoother basis for \code{mgcv::s()}, e.g. \code{"ps"} or \code{"tp"}.
#' @param week_col Character. Column name for the within-season week index used in smoothing
#'   (default \code{"weekF"}).
#' @param season_col Character. Column name identifying season (default \code{"season"}).
#' @param y_col Character. Column name for positives (default \code{"y"}).
#' @param n_col Character. Column name for tests (default \code{"N"}).
#' @param ci_level Numeric in (0,1). Confidence level for fitted mean intervals on the response
#'   scale (default 0.95).
#' @param deriv_interval Character. Interval type passed to \code{gratia::derivatives()},
#'   typically \code{"simultaneous"} (default) or \code{"confidence"}.
#' @param method Character. Smoothing parameter estimation method passed to \code{mgcv::gam()},
#'   default \code{"REML"}.
#'
#' @return A list with two elements:
#' \describe{
#'   \item{data}{A data.frame of \code{allD} augmented with columns:
#'     \code{neg}, \code{fit}, \code{fit_low}, \code{fit_high},
#'     \code{d1}, \code{d1_low}, \code{d1_high},
#'     \code{d2}, \code{d2_low}, \code{d2_high}.}
#'   \item{models}{A named list of fitted \code{mgcv::gam} objects (one per season).}
#' }
#'
#' @importFrom stats as.formula predict qnorm
#' @import data.table
#' @export
estimateDerivs <- function(
    allD,
    k = 10,
    bs = "ps",
    week_col   = "weekF",
    season_col = "season",
    y_col      = "y",
    n_col      = "N",
    ci_level   = 0.95,
    deriv_interval = "simultaneous",
    method = "REML"
) {
  stopifnot(
    is.data.frame(allD),
    all(c(season_col, week_col, y_col, n_col) %in% names(allD))
  )
  
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Package 'mgcv' is required.")
  if (!requireNamespace("gratia", quietly = TRUE)) stop("Package 'gratia' is required.")
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Package 'data.table' is required.")
  
  DT <- data.table::as.data.table(allD)
  DT[, (season_col) := as.factor(as.character(get(season_col)))]
  DT[, neg := get(n_col) - get(y_col)]
  
  z <- stats::qnorm(1 - (1 - ci_level) / 2)
  
  idx_by_season <- split(seq_len(nrow(DT)), DT[[season_col]])
  
  fit_one <- function(idx) {
    dts <- DT[idx]
    data.table::setorderv(dts, week_col)
    
    # ensure unique week within season
    if (anyDuplicated(dts[[week_col]]) > 0L) {
      stop("Duplicate ", week_col, " within a season; cannot merge derivatives safely.")
    }
    
    fml <- stats::as.formula(
      sprintf("cbind(%s, neg) ~ s(%s, k = %d, bs = '%s')",
              y_col, week_col, k, bs)
    )
    
    g <- mgcv::gam(
      formula = fml,
      data    = dts,
      family  = binomial(),
      method  = method
    )
    
    # predictions on link scale -> transform => response-scale CI
    pr  <- stats::predict(g, newdata = dts, type = "link", se.fit = TRUE)
    eta <- as.numeric(pr$fit)
    se  <- as.numeric(pr$se.fit)
    
    dts[, `:=`(
      fit      = g$family$linkinv(eta),
      fit_low  = g$family$linkinv(eta - z * se),
      fit_high = g$family$linkinv(eta + z * se)
    )]
    
    d1 <- gratia::derivatives(g, order = 1, interval = deriv_interval, data = dts)
    d2 <- gratia::derivatives(g, order = 2, interval = deriv_interval, data = dts)
    
    d1 <- data.table::as.data.table(d1)
    d2 <- data.table::as.data.table(d2)
    
    # bring along season + week, keep only needed cols
    # (gratia output includes the covariate column named week_col, e.g. weekF)
    d1 <- d1[, .(
      season_tmp = dts[[season_col]][1],
      week_tmp   = get(week_col),
      d1         = .derivative,
      d1_low     = .lower_ci,
      d1_high    = .upper_ci
    )]
    d2 <- d2[, .(
      season_tmp = dts[[season_col]][1],
      week_tmp   = get(week_col),
      d2         = .derivative,
      d2_low     = .lower_ci,
      d2_high    = .upper_ci
    )]
    
    # ensure unique weeks in derivative outputs too
    if (anyDuplicated(d1$week_tmp) > 0L || anyDuplicated(d2$week_tmp) > 0L) {
      stop("derivatives() returned duplicate ", week_col, " values; cannot merge safely.")
    }
    
    # merge by season+week (robust across seasons)
    out <- merge(
      dts, d1,
      by.x = c(season_col, week_col),
      by.y = c("season_tmp", "week_tmp"),
      all.x = TRUE,
      sort = FALSE
    )
    out <- merge(
      out, d2,
      by.x = c(season_col, week_col),
      by.y = c("season_tmp", "week_tmp"),
      all.x = TRUE,
      sort = FALSE
    )
    
    data.table::setorderv(out, c(season_col, week_col))
    list(data = out, model = g)
  }
  
  res_list  <- lapply(idx_by_season, fit_one)
  data_out  <- data.table::rbindlist(lapply(res_list, `[[`, "data"))
  models_out <- lapply(res_list, `[[`, "model")
  names(models_out) <- names(idx_by_season)
  
  list(
    data   = as.data.frame(data_out),
    models = models_out
  )
}
#' Align within-season week index by shifting ignition to a common anchor week
#'
#' @param outs list of flagIgnition() outputs (each has $data and $ignition)
#' @param season_col season column name (default "season")
#' @param week_col within-season week column name (default "weekF")
#' @param nweek_col season length column name (default "nW_true"); if missing uses max(weekF) per season
#'
#' @return data.frame with newWeek and phase_inSeason added; attributes: anchorWeek, ignD
#' @export
alignIgnition <- function(outs,
                          season_col = "season",
                          week_col   = "weekF",
                          nweek_col  = "nW_true") {
  stopifnot(is.list(outs), length(outs) > 0)
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need 'data.table'.")
  if (!requireNamespace("purrr", quietly = TRUE)) stop("Need 'purrr'.")
  
  # bind data + ignition
  allD <- data.table::rbindlist(purrr::map(outs, "data"), fill = TRUE)
  ignD <- data.table::rbindlist(purrr::map(outs, "ignition"), fill = TRUE)
  
  stopifnot(season_col %in% names(allD), week_col %in% names(allD))
  stopifnot(season_col %in% names(ignD), week_col %in% names(ignD))
  
  # robust int coercion (handles factor/character safely)
  to_int <- function(x) suppressWarnings(as.integer(as.character(x)))
  
  allD[, (season_col) := as.character(get(season_col))]
  allD[, (week_col)   := to_int(get(week_col))]
  
  ignD[, (season_col) := as.character(get(season_col))]
  ignD[, (week_col)   := to_int(get(week_col))]
  
  # one ignition week per season (first non-NA)
  ign_small <- ignD[, .(iWeek = get(week_col)) , by = season_col][
    , .(iWeek = if (all(is.na(iWeek))) NA_integer_ else iWeek[which(!is.na(iWeek))[1]]),
    by = season_col
  ]
  
  anchorWeek <- to_int(stats::median(ign_small$iWeek, na.rm = TRUE))
  
  # named maps: season -> iWeek and season -> offset
  iweek_map  <- setNames(ign_small$iWeek, ign_small[[season_col]])
  offset_map <- setNames(anchorWeek - ign_small$iWeek, ign_small[[season_col]])
  
  # season length nW (52/53)
  if (!is.null(nweek_col) && nweek_col %in% names(allD)) {
    allD[, nW := to_int(get(nweek_col))]
    allD[is.na(nW), nW := max(get(week_col), na.rm = TRUE), by = season_col]
  } else {
    allD[, nW := max(get(week_col), na.rm = TRUE), by = season_col]
  }
  
  # lookup iWeek and offset WITHOUT merge
  allD[, iWeek  := iweek_map[get(season_col)]]
  allD[, offset := offset_map[get(season_col)]]
  
  # aligned week (wrap by nW to handle 52 vs 53)
  allD[, newWeek := ifelse(
    is.na(get(week_col)) | is.na(iWeek) | is.na(nW) | is.na(anchorWeek),
    NA_integer_,
    ((get(week_col) + offset - 1L) %% nW) + 1L
  )]
  
  # ---- phase indicator: in-season (>= ignition) vs pre-season (< ignition) ----
  allD[, phase := as.integer(
    !is.na(iWeek) &
      !is.na(get(week_col)) &
      (get(week_col) >= iWeek)
  )]
  
  allD[, offset := NULL]  # drop helper
  
  out <- as.data.frame(allD)
  attr(out, "anchorWeek") <- anchorWeek
  attr(out, "ignD")       <- as.data.frame(ign_small)
  out
}


