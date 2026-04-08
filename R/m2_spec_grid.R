# ============================================================
# 1) stage2_make_spec()
# ============================================================

#' Create a Stage-2 training specification (hyperparameters + derived objects)
#'
#' Builds a spec list that defines:
#' \itemize{
#'   \item template shift \code{delta}
#'   \item template ramp length \code{Kr}
#'   \item training buffer window \code{Kb} (weeks before ignition)
#'   \item spline basis sizes \code{k_*}
#'   \item template entry mode \code{T} (smooth/offset/none)
#'   \item derived: \code{spec$formula} and \code{spec$exclude_newseason}
#' }
#'
#' This function expects two project helpers to exist:
#' \itemize{
#'   \item \code{stage2_build_joint_formula(spec)}
#'   \item \code{stage2_exclude_newseason(spec)}
#' }
#'
#' @param delta Integer template shift in weeks.
#' @param Kr Integer ramp length (>=1). Kr=1 means "immediate" ramp after ignition week.
#' @param k_f Integer basis size for template smooth (only used when \code{T="S"}).
#' @param alpha_state Numeric EWMA decay in (0,1) used to compute \code{z_ema}.
#' @param Kb Integer buffer (weeks before ignition) included in training window:
#'   training rows satisfy \code{weekF >= ign_weekF - Kb}.
#' @param leads Integer horizons (usually \code{c(1L,2L)}).
#' @param T Template entry mode:
#'   \code{"S"} = smooth term; \code{"O"} = offset; \code{"N"} = no template.
#' @param template_mode Back-compat alias of \code{T}: "smooth"/"offset"/"none".
#' @param use_ramp Deprecated. If \code{FALSE}, forces \code{Kr=1}.
#'
#' @param k_w,k_s,k_e,k_n,k_1,k_2 Integer basis sizes for smooth terms.
#'   Set any to 0L to disable the corresponding term.
#' @param bs_week Basis name for week smooths (typical: "ts").
#' @param bs_fs_marginal Marginal basis used by factor-smooth \code{bs="fs"} via \code{xt=list(bs=...)}.
#' @param use_season_re Back-compat flag (season RE is always included).
#'
#' @param K Deprecated alias of \code{Kr}.
#' @param pre_buffer Deprecated alias of \code{Kb}.
#'
#' @return A list \code{spec} containing hyperparameters plus:
#' \itemize{
#'   \item \code{spec$formula} joint model formula
#'   \item \code{spec$exclude_newseason} terms to exclude for new-season prediction
#'   \item \code{spec$best_row} small data.frame for printing
#' }
#' @export
stage2_make_spec <- function(
    delta = 0L,
    Kr = 3L,
    k_f = 6L,
    alpha_state = 0.30,
    Kb = 0L,
    leads = c(1L, 2L),
    
    T = c("S", "O", "N"),
    template_mode = NULL,
    use_ramp = NULL,
    
    k_e = 6L,
    k_n = 6L,
    k_1 = 6L,
    k_2 = 6L,
    k_w = 0L,
    k_s = 0L,
    
    bs_week = "ts",
    bs_fs_marginal = "tp",
    use_season_re = TRUE,
    lambda_w = 0,       # training preference (not tuned): time-decay weight for early-season emphasis
    w_floor  = 0.05,

    anchorWeek = 20L,

    # --- deprecated aliases ---
    K = NULL,
    pre_buffer = NULL
) {
  if (!is.null(K)) Kr <- K
  if (!is.null(pre_buffer)) Kb <- pre_buffer
  
  if (!is.null(template_mode)) {
    template_mode <- match.arg(template_mode, choices = c("smooth","offset","none"))
    T <- switch(template_mode, smooth = "S", offset = "O", none = "N")
  } else {
    T <- match.arg(T, choices = c("S","O","N"))
  }
  template_mode2 <- switch(T, S = "smooth", O = "offset", N = "none")
  
  if (!is.null(use_ramp) && !isTRUE(use_ramp)) Kr <- 1L
  if (!isTRUE(use_season_re)) use_season_re <- TRUE
  
  spec <- list(
    delta = if (is.na(delta)) NA_integer_ else as.integer(delta),
    Kr    = if (is.na(Kr))    NA_integer_ else as.integer(Kr),
    k_f   = as.integer(k_f),
    alpha_state = as.numeric(alpha_state),
    Kb    = as.integer(Kb),
    leads = as.integer(leads),
    
    T = T,
    template_mode = template_mode2,
    
    k_w = as.integer(k_w),
    k_s = as.integer(k_s),
    k_e = as.integer(k_e),
    k_n = as.integer(k_n),
    k_1 = as.integer(k_1),
    k_2 = as.integer(k_2),
    
    bs_week = bs_week,
    bs_fs_marginal = bs_fs_marginal,

    use_season_re = TRUE,
    lambda_w   = as.numeric(lambda_w),
    w_floor    = as.numeric(w_floor),
    anchorWeek = as.integer(anchorWeek)
  )
  
  spec$best_row <- data.frame(
    delta = spec$delta,
    Kr    = spec$Kr,
    k_f   = spec$k_f,
    alpha_state = spec$alpha_state,
    Kb = spec$Kb,
    stringsAsFactors = FALSE
  )
  
  spec$exclude_newseason <- stage2_exclude_newseason(spec)
  spec$formula <- stage2_build_joint_formula(spec)
  spec
}


# ============================================================
# 2) expand_grid_specs()  (NOW varies ALL hyperparams)
# ============================================================

#' Expand a hyperparameter grid into Stage-2 spec objects (ALL hyperparams can vary)
#'
#' Creates a cartesian product over all supplied grids and returns:
#' \itemize{
#'   \item a named list of \code{spec} objects (\code{$specs})
#'   \item a data.frame describing the grid (\code{$grid})
#' }
#'
#' Special handling:
#' \itemize{
#'   \item \code{k_f} is only meaningful when \code{T=="S"}.
#'     For \code{T!="S"}, \code{k_f} is set to NA by default to avoid unnecessary expansion.
#' }
#'
#' @param delta_grid Integer vector.
#' @param Kr_grid Integer vector for ramp length.
#' @param T_grid Character vector in \code{c("O","S","N")}.
#' @param k_f_grid Integer vector (used only when \code{T=="S"}).
#'
#' @param alpha_state Numeric vector in (0,1).
#' @param Kb_grid Integer vector for ignition buffer length.
#'
#' @param leads Integer vector of horizons (typically fixed to \code{c(1L,2L)}).
#'
#' @param k_w_grid,k_s_grid,k_e_grid,k_n_grid,k_1_grid,k_2_grid Integer vectors for smooth basis sizes.
#' @param bs_week_grid Character vector for week smooth basis.
#' @param bs_fs_marginal_grid Character vector for fs marginal basis.
#'
#' @param drop_unused_kf_for_nonS If TRUE, sets \code{k_f=NA} for \code{T!="S"}.
#' @param verbose Logical.
#'
#' @return List with \code{specs}, \code{grid}, and \code{n}.
#' @export
expand_grid_specs <- function(
    delta_grid = -3:3,
    Kr_grid    = 1:6,
    T_grid     = c("O","S"),
    k_f_grid   = c(6L, 8L, 10L),
    alpha_state = c(0.25),
    Kb_grid     = c(0L, 1L),
    leads = c(1L, 2L),
    k_w_grid = c(8L),
    k_s_grid = c(0L),
    k_e_grid = c(6L),
    k_n_grid = c(6L),
    k_1_grid = c(6L),
    k_2_grid = c(0L),
    bs_week_grid        = "ts",
    bs_fs_marginal_grid = "tp",
    drop_unused_kf_for_nonS = TRUE,
    verbose = TRUE
) {
  if (!exists("stage2_make_spec", mode = "function")) {
    stop("expand_grid_specs() expects stage2_make_spec() to be defined.")
  }
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Please install data.table.")
  
  DT <- data.table::CJ(
    delta = as.integer(delta_grid),
    Kr    = as.integer(Kr_grid),
    T     = as.character(T_grid),
    
    alpha_state = as.numeric(alpha_state),
    Kb    = as.integer(Kb_grid),
    
    k_w   = as.integer(k_w_grid),
    k_s   = as.integer(k_s_grid),
    k_e   = as.integer(k_e_grid),
    k_n   = as.integer(k_n_grid),
    k_1   = as.integer(k_1_grid),
    k_2   = as.integer(k_2_grid),
    
    bs_week        = as.character(bs_week_grid),
    bs_fs_marginal = as.character(bs_fs_marginal_grid),
    
    unique = TRUE,
    sorted = FALSE
  )
  
  k_f_grid <- as.integer(k_f_grid)
  
  DT_S <- DT[T == "S"]
  DT_N <- DT[T != "S"]
  
  if (nrow(DT_S) > 0L) {
    DT_S <- DT_S[, .(k_f = k_f_grid), by = setdiff(names(DT_S), "k_f")]
  } else {
    DT_S <- DT_S[, k_f := integer(0)]
  }
  
  if (nrow(DT_N) > 0L) {
    if (isTRUE(drop_unused_kf_for_nonS)) DT_N[, k_f := NA_integer_] else DT_N[, k_f := k_f_grid[1]]
  }
  
  grid <- data.table::rbindlist(list(DT_N, DT_S), use.names = TRUE, fill = TRUE)
  data.table::setorder(grid, T, delta, Kr, k_f, alpha_state, Kb, k_w, k_s, k_e, k_n, k_1, k_2)
  
  grid[, spec_id := ifelse(
    T == "S",
    sprintf("T%s_d%+d_Kr%d_kf%d_as%.2f_Kb%d_kw%d_ks%d_ke%d_kn%d_k1%d_k2%d",
            T, delta, Kr, k_f, alpha_state, Kb, k_w, k_s, k_e, k_n, k_1, k_2),
    sprintf("T%s_d%+d_Kr%d_as%.2f_Kb%d_kw%d_ks%d_ke%d_kn%d_k1%d_k2%d",
            T, delta, Kr, alpha_state, Kb, k_w, k_s, k_e, k_n, k_1, k_2)
  )]
  
  specs <- Map(
    f = function(delta, Kr, T, k_f, alpha_state, Kb,
                 k_w, k_s, k_e, k_n, k_1, k_2,
                 bs_week, bs_fs_marginal) {
      if (is.na(k_f)) k_f <- k_f_grid[1]
      stage2_make_spec(
        delta = delta, Kr = Kr, T = T, k_f = k_f,
        alpha_state = alpha_state,
        Kb = Kb,
        leads = as.integer(leads),
        
        k_w = k_w, k_s = k_s, k_e = k_e, k_n = k_n, k_1 = k_1, k_2 = k_2,
        bs_week = bs_week, bs_fs_marginal = bs_fs_marginal
      )
    },
    grid$delta, grid$Kr, grid$T, grid$k_f, grid$alpha_state, grid$Kb,
    grid$k_w, grid$k_s, grid$k_e, grid$k_n, grid$k_1, grid$k_2,
    grid$bs_week, grid$bs_fs_marginal
  )
  names(specs) <- grid$spec_id
  
  if (isTRUE(verbose)) {
    message("[expand_grid_specs] n_specs=", nrow(grid),
            " | delta=", length(delta_grid),
            " Kr=", length(Kr_grid),
            " Kb=", length(Kb_grid),
            " T=", paste(unique(T_grid), collapse=","),
            " | alpha_state=", paste(as.numeric(alpha_state), collapse=","))
  }
  
  list(specs = specs, grid = as.data.frame(grid), n = nrow(grid))
}


# ============================================================
# 3) prep_stage2_m1_features()
# ============================================================

#' Prepare Stage-2 M1 features from aligned prospective data
#'
#' Computes standardized columns required by Stage-2 training/prediction:
#' \itemize{
#'   \item \code{y_now, N_now} from \code{y/N} (or \code{x/n})
#'   \item \code{d1_now, d2_now} from \code{d1_link/d2_link} if present, else \code{d1/d2}
#'   \item ignition week \code{ign_weekF} from \code{iWeek} or \code{ignition} or \code{ignD} fallback
#'   \item \code{logit_f_eff} = \code{omega(t_rel;Kr)} * template logit, where
#'     \code{omega(t;Kr)=clamp(t/Kr,0,1)} and \code{t_rel=weekF-ign_weekF}
#'   \item \code{z_ema} EWMA on observed logit positivity using \code{alpha_state}
#'   \item \code{logN_now} = log(N_now)
#' }
#'
#' Requires helper functions already in your file:
#' \code{wrap_week()}, \code{ewma_recursive()}, \code{make_ref_logit_fun_from_template()}.
#'
#' @param alignedD_prosp Data with at least season, weekF, newWeek and y/N (or x/n).
#' @param template_df Template reference df with columns \code{newWeek} and \code{fit} (logit-scale ref).
#' @param spec Spec from \code{stage2_make_spec()} (uses \code{delta}, \code{Kr}, \code{T}, \code{alpha_state}).
#' @param ignD Optional ignition rule table (fallback if iWeek/ignition not available).
#' @param eps Numeric clamp for observed p before logit.
#' @param n_weeks Optional; inferred from \code{max(template_df$newWeek)} if NULL.
#'
#' @return A data.table with original columns plus derived feature columns.
#' @export
plot_stage2_joint_fit_by_season <- function(out_m1,
                                            feat_full,
                                            dat_raw = NULL,
                                            ign_hat_df = NULL,
                                            exclude_season_re = FALSE,
                                            exclude_newseason_terms = FALSE,
                                            facet_by_lead = TRUE,
                                            trim_preign = TRUE) {
  stopifnot(is.list(out_m1), !is.null(out_m1$fit), !is.null(out_m1$spec))
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Please install data.table.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Please install ggplot2.")
  
  fit_mod <- out_m1$fit
  spec    <- out_m1$spec
  H       <- as.integer(spec$leads %||% c(1L,2L))
  
  DT <- data.table::as.data.table(data.table::copy(feat_full))
  data.table::setorderv(DT, c("season","weekF"))
  if (!"y_now" %in% names(DT) && "y" %in% names(DT)) DT[, y_now := as.integer(y)]
  if (!"N_now" %in% names(DT) && "N" %in% names(DT)) DT[, N_now := as.integer(N)]
  if (!"ign_weekF" %in% names(DT)) {
    if ("iWeek_used" %in% names(DT)) {
      DT[, ign_weekF := as.numeric(iWeek_used)]
    } else if ("iWeek_true" %in% names(DT)) {
      DT[, ign_weekF := as.numeric(iWeek_true)]
    } else if ("phase" %in% names(DT)) {
      ign_map <- DT[, .(
        ign_weekF = suppressWarnings(min(weekF[phase == 1L], na.rm = TRUE))
      ), by = season]
      ign_map[!is.finite(ign_weekF), ign_weekF := NA_real_]
      DT <- ign_map[DT, on = "season"]
    }
  }
  if (!all(c("y_now", "N_now", "ign_weekF") %in% names(DT))) {
    stop("plot_stage2_joint_fit_by_season: feat_full must provide y_now/N_now/ign_weekF, or compatible y/N/iWeek_used/phase columns.")
  }
  lead_levels <- tryCatch(levels(fit_mod$model$lead), error = function(e) NULL)

  if (is.null(lead_levels) || !length(lead_levels)) {
    lead_levels <- paste0("h", H)
  }

  already_stacked <- all(c("y_lead", "N_lead", "lead") %in% names(DT))

  if (already_stacked) {
    # Data from prep_stage2_joint is already stacked with correct y_lead/N_lead.
    # Using shift() on stacked rows gives wrong targets (shifts by row, not week).
    d_all <- DT
    d_all[, lead_n := as.integer(sub("^h", "", as.character(lead)))]
  } else {
    # Unstacked data: create lead targets via shift (one row per season-weekF).
    d_all <- data.table::rbindlist(lapply(H, function(hh) {
      d <- data.table::copy(DT)
      d[, `:=`(
        lead_n = hh,
        lead   = factor(paste0("h", hh), levels = lead_levels),
        y_lead = data.table::shift(y_now, n = hh, type = "lead"),
        N_lead = data.table::shift(N_now, n = hh, type = "lead")
      ), by = season]
      d
    }), use.names = TRUE)
  }

  d_all <- d_all[!is.na(y_lead) & !is.na(N_lead)]
  d_all[, p_obs := y_lead / N_lead]
  d_all[, post_ign := weekF >= ign_weekF]
  
  d_all[, season := factor(season)]
  d_all[, lead   := factor(lead, levels = lead_levels)]
  d_all[, season_h := factor(interaction(season, lead, drop = TRUE))]
  
  if (!is.null(dat_raw) && all(c("season","weekF","phase") %in% names(dat_raw))) {
    ign_true <- data.table::as.data.table(dat_raw)[
      , .(iWeek_true = suppressWarnings(min(weekF[phase == 1L], na.rm = TRUE))), by = season
    ]
    ign_true[!is.finite(iWeek_true), iWeek_true := NA_real_]
  } else {
    ign_true <- d_all[, .(iWeek_true = unique(ign_weekF)[1]), by = season]
  }
  
  ex <- NULL
  if (isTRUE(exclude_newseason_terms)) {
    ex <- spec$exclude_newseason
  } else if (isTRUE(exclude_season_re)) {
    ex <- "s(season)"
  }
  
  d_fit <- d_all[post_ign == TRUE]
  # predict OUTSIDE data.table NSE using fit_mod (avoids collision with a column named "fit")
  d_fit[, p_hat := as.numeric(stats::predict(fit_mod, newdata = d_fit, type = "response", exclude = ex))]

  # trim_preign: only show observations from ignition onward (cleaner plots)
  d_obs <- if (isTRUE(trim_preign)) d_fit else d_all

  p <- ggplot2::ggplot(d_obs, ggplot2::aes(x = weekF)) +
    ggplot2::geom_point(ggplot2::aes(y = p_obs), colour = "black", size = 1.0, alpha = 0.75) +
    ggplot2::geom_line(
      data = d_fit,
      ggplot2::aes(y = p_hat, group = interaction(season, lead)),
      colour = "red", linewidth = 0.9
    ) +
    ggplot2::geom_vline(data = ign_true, ggplot2::aes(xintercept = iWeek_true), linewidth = 0.6) +
    ggplot2::labs(
      x = "weekF", y = "Lead positivity",
      title = "Stage-2 fitted (post-ignition) vs observed (all weeks), by season"
    ) +
    ggplot2::theme_bw()
  
  if (!is.null(ign_hat_df)) {
    stopifnot(all(c("season","iWeek_hat") %in% names(ign_hat_df)))
    ign_hat <- data.table::as.data.table(ign_hat_df)[, .(
      season = as.character(season),
      iWeek_hat = as.numeric(iWeek_hat)
    )]
    p <- p + ggplot2::geom_vline(data = ign_hat, ggplot2::aes(xintercept = iWeek_hat),
                                 linetype = "dashed", linewidth = 0.6)
  }
  
  if (isTRUE(facet_by_lead)) {
    p + ggplot2::facet_grid(lead ~ season, scales = "free_y")
  } else {
    p + ggplot2::facet_wrap(~ season, scales = "free_y")
  }
}


#' Build the joint Stage-2 mgcv formula from a spec
#'
#' Uses your naming convention:
#' - ramp length is Kr (used in features, not formula)
#' - buffer is Kb (used in stacking, not formula)
#' - spline basis sizes are k_*
#'
#' Required columns in the stacked training data:
#' y_lead, N_lead, lead, season, season_h, logit_f_eff, newWeek,
#' z_ema, logN_now, d1_now, d2_now (some may be unused depending on k_*).
#'
#' @param spec A spec list from stage2_make_spec().
#' @return An R formula suitable for mgcv::bam().
#' @export
stage2_build_joint_formula <- function(spec) {
  stopifnot(is.list(spec), all(c("T","k_f","k_w","k_s","k_e","k_n","k_1","k_2","bs_week","bs_fs_marginal") %in% names(spec)))
  
  bs1 <- spec$bs_week %||% "ts"
  
  rhs <- c("-1 + lead",
           "s(season, bs='re')")
  
  # template term
  if (identical(spec$T, "O")) {
    rhs <- c(rhs, "offset(logit_f_eff)")
  } else if (identical(spec$T, "S")) {
    rhs <- c(rhs, sprintf("s(logit_f_eff, by=lead, bs='%s', k=%d)", bs1, as.integer(spec$k_f)))
  }
  
  # global aligned-time correction
  if (as.integer(spec$k_w) > 0L) {
    rhs <- c(rhs, sprintf("s(newWeek, by=lead, bs='%s', k=%d)", bs1, as.integer(spec$k_w)))
  }
  
  # season-specific deviation (factor-smooth)
  if (as.integer(spec$k_s) > 0L) {
    rhs <- c(rhs, sprintf("s(newWeek, season_h, bs='fs', k=%d, xt=list(bs='%s'))",
                          as.integer(spec$k_s), spec$bs_fs_marginal %||% "tp"))
  }
  
  # EMA state
  if (as.integer(spec$k_e) > 0L) {
    rhs <- c(rhs, sprintf("s(z_ema, by=lead, bs='%s', k=%d)", bs1, as.integer(spec$k_e)))
  }
  
  # testing volume
  if (as.integer(spec$k_n) > 0L) {
    rhs <- c(rhs, sprintf("s(logN_now, by=lead, bs='%s', k=%d)", bs1, as.integer(spec$k_n)))
  }
  
  # derivatives
  if (as.integer(spec$k_1) > 0L) {
    rhs <- c(rhs, sprintf("s(d1_now, by=lead, bs='%s', k=%d)", bs1, as.integer(spec$k_1)))
  }
  if (as.integer(spec$k_2) > 0L) {
    rhs <- c(rhs, sprintf("s(d2_now, by=lead, bs='%s', k=%d)", bs1, as.integer(spec$k_2)))
  }
  
  stats::as.formula(paste0("cbind(y_lead, N_lead - y_lead) ~ ", paste(rhs, collapse = " + ")))
}

#' Terms to exclude for new-season prediction
#'
#' When forecasting a brand-new season, season-dependent terms cannot be used.
#' This returns the mgcv smooth labels to exclude in predict(..., exclude = ...).
#'
#' @param spec A spec list from stage2_make_spec().
#' @return Character vector of smooth labels to exclude.
#' @export
stage2_exclude_newseason <- function(spec) {
  ex <- c("s(season)")  # always exclude season RE for new season
  if (!is.null(spec$k_s) && as.integer(spec$k_s) > 0L) {
    ex <- c(ex, "s(newWeek,season_h)")
  }
  ex
}
