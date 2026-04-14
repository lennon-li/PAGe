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
  # Score one parameter setting (internal).
  # Internal helper for tuneIgnitionGrid(); evaluates one row of the tuning grid.
  # @param i Integer row index into the tuning grid.
  # Returns a 1-row data.frame of scores for this grid setting.

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

# estimateRef() and estimateDerivs() are defined in m1_reference.R
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


