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
    lambda_w = 0,
    w_floor  = 0.05,

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
    lambda_w = as.numeric(lambda_w),
    w_floor  = as.numeric(w_floor)
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
prep_stage2_m1_features <- function(alignedD_prosp,
                                    template_df,
                                    spec,
                                    ignD = NULL,
                                    eps = 1e-6,
                                    n_weeks = NULL) {
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Please install data.table.")
  if (!is.list(spec) || !all(c("delta","Kr","alpha_state","T") %in% names(spec))) {
    stop("spec must be a list from stage2_make_spec() with delta/Kr/alpha_state/T.")
  }
  
  DT <- data.table::as.data.table(data.table::copy(alignedD_prosp))
  need <- c("season","weekF","newWeek")
  miss <- setdiff(need, names(DT))
  if (length(miss)) stop("alignedD_prosp missing columns: ", paste(miss, collapse = ", "))
  
  y_col <- if ("y" %in% names(DT)) "y" else if ("x" %in% names(DT)) "x" else stop("Need y or x.")
  n_col <- if ("N" %in% names(DT)) "N" else if ("n" %in% names(DT)) "n" else stop("Need N or n.")
  
  d1_src <- if ("d1_link" %in% names(DT)) "d1_link" else if ("d1" %in% names(DT)) "d1" else NULL
  d2_src <- if ("d2_link" %in% names(DT)) "d2_link" else if ("d2" %in% names(DT)) "d2" else NULL
  
  DT[, `:=`(
    y_now  = as.integer(get(y_col)),
    N_now  = as.integer(get(n_col)),
    d1_now = if (!is.null(d1_src)) as.numeric(get(d1_src)) else NA_real_,
    d2_now = if (!is.null(d2_src)) as.numeric(get(d2_src)) else NA_real_
  )]
  
  if (is.null(n_weeks)) n_weeks <- as.integer(max(template_df$newWeek, na.rm = TRUE))
  ref_logit_fun <- make_ref_logit_fun_from_template(template_df, n_weeks = n_weeks)
  
  # ignition week per season
  ign_tbl <- NULL
  if ("iWeek" %in% names(DT) && any(!is.na(DT$iWeek))) {
    ign_tbl <- DT[!is.na(iWeek), .(ign_weekF = suppressWarnings(min(as.integer(iWeek), na.rm = TRUE))), by = season]
    ign_tbl[!is.finite(ign_weekF), ign_weekF := NA_integer_]
  } else if ("ignition" %in% names(DT) && any(DT$ignition == 1, na.rm = TRUE)) {
    ign_tbl <- DT[ignition == 1, .(ign_weekF = min(as.integer(weekF), na.rm = TRUE)), by = season]
  } else if (!is.null(ignD)) {
    IG <- data.table::as.data.table(data.table::copy(ignD))
    if (!all(c("season","weekF") %in% names(IG))) stop("ignD must contain season and weekF.")
    if ("rule_level" %in% names(IG)) {
      ign_tbl <- IG[is.finite(rule_level) & rule_level > 0, .(ign_weekF = min(as.integer(weekF))), by = season]
    }
    if (is.null(ign_tbl) || nrow(ign_tbl) == 0L) {
      if ("rule_name" %in% names(IG)) {
        ign_tbl <- IG[!is.na(rule_name) & rule_name != "", .(ign_weekF = min(as.integer(weekF))), by = season]
      }
    }
  }
  if (is.null(ign_tbl) || nrow(ign_tbl) == 0L) {
    stop("Cannot derive ign_weekF: need iWeek or ignition in alignedD_prosp, or provide ignD.")
  }
  
  DT[ign_tbl, ign_weekF := i.ign_weekF, on = "season"]
  DT[, t_rel := as.integer(weekF) - as.integer(ign_weekF)]
  
  # template covariate with ramp omega(t;Kr)
  DT[, `:=`(omega = 0.0, newWeek_shift = NA_integer_, logit_template = NA_real_, logit_f_eff = 0.0)]
  if (!identical(spec$T, "N") && !is.na(spec$delta) && !is.na(spec$Kr)) {
    Kr <- as.integer(spec$Kr)
    DT[!is.na(ign_weekF), omega := pmin(1, pmax(0, t_rel / Kr))]
    DT[!is.na(ign_weekF), newWeek_shift := wrap_week(newWeek + as.integer(spec$delta), n_weeks)]
    DT[!is.na(ign_weekF), logit_template := ref_logit_fun(newWeek_shift)]
    DT[!is.na(ign_weekF), logit_f_eff := omega * logit_template]
  }
  
  # EWMA state
  DT[, p_now := pmin(1 - eps, pmax(eps, y_now / pmax(1L, N_now)))]
  DT[, logit_y_now := qlogis(p_now)]
  a <- as.numeric(spec$alpha_state %||% NA_real_)
  if (is.na(a)) {
    DT[, z_ema := NA_real_]
  } else {
    data.table::setorderv(DT, c("season","weekF"))
    DT[, z_ema := ewma_recursive(logit_y_now, a), by = season]
  }
  
  DT[, logN_now := log(pmax(1L, N_now))]
  DT[]
}


# ============================================================
# 4) train_stage2_joint_m1()
# ============================================================

#' Fit the Stage-2 joint M1 model for a given spec
#'
#' Internally stacks data across \code{spec$leads} and fits \code{mgcv::bam()} using \code{spec$formula}.
#' Training window is applied via:
#' \code{weekF >= ign_weekF - Kb}, where \code{Kb = spec$Kb}.
#'
#' Creates \code{season_h = interaction(season, lead)} to match your formula usage.
#' Saves \code{fit$stage2_levels} for safe LOSO/new-season prediction alignment.
#'
#' @param feat Output of \code{prep_stage2_m1_features()}.
#' @param spec Output of \code{stage2_make_spec()} (must contain \code{formula}, \code{Kb}, \code{leads}).
#' @param seasons_keep Optional vector of seasons to include for training (used in LOSO).
#' @param drop_future If TRUE, drop rows where target outcomes are unavailable.
#' @param nthreads Threads for \code{mgcv::bam()}.
#' @param method \code{bam()} fitting method (default "fREML").
#' @param discrete Logical; discrete approximation (default TRUE).
#' @param return_data If TRUE, return stacked training data as \code{d_train}.
#' @param ... Passed to \code{mgcv::bam()}.
#'
#' @return List with \code{fit}, \code{spec}, and optionally \code{d_train}.
#' @export
train_stage2_joint_m1 <- function(feat,
                                  spec,
                                  seasons_keep = NULL,
                                  drop_future = TRUE,
                                  nthreads = 4L,
                                  method = "fREML",
                                  discrete = TRUE,
                                  return_data = TRUE,
                                  ...) {
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Please install data.table.")
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Please install mgcv.")
  
  DT <- data.table::as.data.table(data.table::copy(feat))
  if (!is.null(seasons_keep)) DT <- DT[season %in% seasons_keep]
  
  H  <- as.integer(spec$leads %||% c(1L,2L))
  Kb <- as.integer(spec$Kb %||% 0L)
  
  data.table::setorderv(DT, c("season","weekF"))
  
  d_train <- data.table::rbindlist(lapply(H, function(hh) {
    d <- data.table::copy(DT)
    d[, `:=`(
      lead_n = hh,
      lead   = factor(hh, levels = H),
      y_lead = data.table::shift(y_now, n = hh, type = "lead"),
      N_lead = data.table::shift(N_now, n = hh, type = "lead")
    ), by = season]
    d
  }), use.names = TRUE)
  
  d_train <- d_train[weekF >= (ign_weekF - Kb)]
  if (isTRUE(drop_future)) d_train <- d_train[!is.na(y_lead) & !is.na(N_lead)]
  
  d_train[, season := factor(season)]
  d_train[, lead   := factor(lead, levels = H)]
  d_train[, season_h := factor(interaction(season, lead, drop = TRUE))]
  
  form <- spec$formula
  if (is.null(form)) form <- stage2_build_joint_formula(spec)
  
  fit <- mgcv::bam(
    formula  = form,
    data     = d_train,
    family   = binomial(),
    method   = method,
    discrete = discrete,
    nthreads = as.integer(nthreads),
    ...
  )
  
  fit$stage2_levels <- list(
    season   = levels(d_train$season),
    lead     = levels(d_train$lead),
    season_h = levels(d_train$season_h)
  )
  
  if (isTRUE(return_data)) list(fit = fit, d_train = d_train, spec = spec) else list(fit = fit, spec = spec)
}


# ============================================================
# 5) tune_stage2_loso_spec_grid()
# ============================================================

#' LOSO tuning over a spec grid with weighted scoring near ignition
#'
#' For each spec_id in \code{spec_grid$specs}:
#' \enumerate{
#'   \item Prepare features once via \code{prep_stage2_m1_features()}.
#'   \item For each held-out season, fit \code{train_stage2_joint_m1()} on the remaining seasons.
#'   \item Predict on held-out season excluding season-dependent terms (new-season evaluation).
#'   \item Score using weighted NLL / Brier / RMSE(p).
#' }
#'
#' Weighting uses **target-week time since ignition**:
#' \deqn{t_\text{target} = (w + h) - w^{(ign)}}
#' Rows with \code{0 <= t_target <= k_t} get weight \code{w_early} (default 2),
#' later rows weight 1.
#'
#' @param alignedD_prosp Raw aligned dataset.
#' @param template_df Template reference df.
#' @param spec_grid Output of \code{expand_grid_specs()} (must include \code{$specs} and \code{$grid}).
#' @param ignD Optional ignition rule table (fallback).
#' @param seasons Optional subset of seasons to include. Must be >=3 for LOSO.
#' @param k_t Integer emphasized window length (weeks since ignition on TARGET week).
#' @param w_early Numeric multiplier for emphasized window.
#' @param exclude_newseason_terms If TRUE, exclude \code{spec$exclude_newseason} when predicting held-out season.
#' @param nthreads Threads for bam fits
#' #' Parallelization uses future.apply and works on Windows (multisession) and Linux/macOS (multicore).
#' Best practice: parallelize over "spec" and set mgcv::bam(nthreads=1) to avoid oversubscription.
#'
#' @param parallel Logical; if TRUE uses future.apply.
#' @param parallel_over "spec" (recommended) or "fold".
#' @param workers Integer; number of workers. Default uses future::availableCores().
#' @param strategy "auto"|"multisession"|"multicore"|"sequential".
#' @param verbose Logical.
#'
#' @return List with:
#' \itemize{
#'   \item \code{by_season}: per-spec per-heldout-season metrics
#'   \item \code{by_spec}: aggregated metrics per spec_id
#'   \item \code{by_spec_grid}: by_spec joined back to the grid
#'   \item \code{best}: best spec row
#'   \item \code{scoring}: k_t and w_early used
#'   \item \code{timing}: elapsed and cpu seconds
#' }
#' @export
tune_stage2_loso_spec_grid <- function(alignedD_prosp,
                                       template_df,
                                       spec_grid,
                                       ignD = NULL,
                                       seasons = NULL,
                                       k_t = 10L,
                                       w_early = 2,
                                       exclude_newseason_terms = TRUE,
                                       # threading inside bam (keep 1 when parallel_over="spec")
                                       nthreads = 1L,
                                       verbose = TRUE,
                                       # parallel controls
                                       parallel = TRUE,
                                       parallel_over = c("spec","fold"),
                                       workers = NULL,
                                       strategy = c("auto","multisession","multicore","sequential"),
                                       # raise global export limit (GB); set NULL to not change
                                       max_global_size_gb = 4) {
  
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Please install data.table.")
  if (!requireNamespace("future", quietly = TRUE)) stop("Please install future.")
  if (!requireNamespace("future.apply", quietly = TRUE)) stop("Please install future.apply.")
  
  parallel_over <- match.arg(parallel_over)
  strategy <- match.arg(strategy)
  
  if (parallel_over != "spec") {
    stop("For cross-platform + memory safety, use parallel_over='spec'. (Fold-parallel is possible but heavier.)")
  }
  
  stopifnot(is.list(spec_grid), !is.null(spec_grid$specs), !is.null(spec_grid$grid))
  specs <- spec_grid$specs
  grid  <- spec_grid$grid
  
  all_seasons <- seasons %||% sort(unique(alignedD_prosp$season))
  if (length(all_seasons) < 3L) stop("LOSO needs >= 3 seasons (each training fold must have >=2 season levels).")
  
  # ---- timing ----
  t_start <- Sys.time()
  pt_start <- proc.time()
  
  # ---- future settings ----
  if (!isTRUE(parallel)) strategy_use <- "sequential" else {
    if (strategy == "auto") {
      strategy_use <- if (.Platform$OS.type == "windows") "multisession" else "multicore"
    } else strategy_use <- strategy
  }
  if (is.null(workers)) workers <- future::availableCores()
  
  # Increase max globals threshold if requested
  if (!is.null(max_global_size_gb)) {
    old_max <- getOption("future.globals.maxSize")
    new_max <- max(old_max %||% 0, as.numeric(max_global_size_gb) * 1024^3)
    options(future.globals.maxSize = new_max)
    on.exit(options(future.globals.maxSize = old_max), add = TRUE)
  }
  
  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  future::plan(strategy_use, workers = workers)
  
  if (isTRUE(verbose)) {
    message("[tune_stage2_loso_spec_grid] specs=", length(specs),
            " | seasons=", length(all_seasons),
            " | scoring: k_t=", k_t, " w_early=", w_early,
            " | exclude_newseason_terms=", exclude_newseason_terms,
            " | parallel=", parallel, " over=spec",
            " | strategy=", strategy_use, " workers=", workers,
            " | bam nthreads=", nthreads)
    if (isTRUE(parallel) && nthreads > 1L) {
      message("[tune_stage2_loso_spec_grid] NOTE: parallel over specs + bam(nthreads>1) can oversubscribe. Prefer nthreads=1.")
    }
  }
  
  # ---- Build X as (spec_id, spec) pairs so we DON'T export the full specs list as a global ----
  items <- Map(function(id, sp) list(spec_id = id, spec = sp), names(specs), specs)
  
  # ---- Worker FUN: set env to baseenv() to avoid capturing huge parent env ----
  worker_fun <- function(item,
                         alignedD_prosp, template_df, ignD, all_seasons,
                         k_t, w_early, exclude_newseason_terms,
                         nthreads) {
    
    spec_id <- item$spec_id
    sp      <- item$spec
    
    # ensure exclude list exists
    if (is.null(sp$exclude_newseason)) sp$exclude_newseason <- stage2_exclude_newseason(sp)
    
    # prep once per spec
    feat <- prep_stage2_m1_features(
      alignedD_prosp = alignedD_prosp,
      template_df    = template_df,
      spec           = sp,
      ignD           = ignD
    )
    
    # per-fold results
    out_list <- lapply(all_seasons, function(s_out) {
      train_seasons <- setdiff(all_seasons, s_out)
      
      out_fit <- train_stage2_joint_m1(
        feat = feat,
        spec = sp,
        seasons_keep = train_seasons,
        drop_future = TRUE,
        nthreads = nthreads,
        return_data = FALSE
      )
      fit_mod <- out_fit$fit
      
      d_test <- stack_stage2_joint_data(
        feat = feat,
        spec = sp,
        seasons_keep = s_out,
        drop_future = TRUE
      )
      
      # align levels for new-season prediction (avoid new factor levels)
      lev_lead   <- fit_mod$stage2_levels$lead
      lev_season <- fit_mod$stage2_levels$season
      lev_sh     <- fit_mod$stage2_levels$season_h
      
      d_test$lead <- factor(as.character(d_test$lead), levels = lev_lead)
      d_test$season <- factor(as.character(d_test$season), levels = lev_season)
      if (anyNA(d_test$season)) d_test$season[is.na(d_test$season)] <- lev_season[1]
      d_test$season_h <- interaction(d_test$season, d_test$lead, drop = TRUE)
      d_test$season_h <- factor(d_test$season_h, levels = lev_sh)
      if (anyNA(d_test$season_h)) d_test$season_h[is.na(d_test$season_h)] <- lev_sh[1]
      
      ex <- if (isTRUE(exclude_newseason_terms)) sp$exclude_newseason else NULL
      eta <- as.numeric(stats::predict(fit_mod, newdata = d_test, type = "link", exclude = ex))
      p   <- plogis(eta)
      
      # weighted scoring by TARGET week t_target = (w+h) - ign_weekF
      t_target <- (d_test$weekF + d_test$lead_n) - d_test$ign_weekF
      w <- rep(1, length(t_target))
      w[is.finite(t_target) & t_target >= 0 & t_target <= as.integer(k_t)] <- as.numeric(w_early)
      
      y <- as.numeric(d_test$y_lead)
      N <- as.numeric(d_test$N_lead)
      p <- pmin(1 - 1e-12, pmax(1e-12, p))
      
      ok <- is.finite(y) & is.finite(N) & is.finite(p) & (N > 0) & is.finite(w)
      y <- y[ok]; N <- N[ok]; p <- p[ok]; w <- w[ok]
      
      ll <- stats::dbinom(y, size = N, prob = p, log = TRUE)
      nll <- -sum(w * ll)
      
      phat <- y / N
      se2  <- (p - phat)^2
      brier_num <- sum(w * se2)
      w_sum <- sum(w)
      
      data.table::data.table(
        spec_id = spec_id,
        season_out = as.character(s_out),
        n = length(p),
        w_sum = w_sum,
        nll = nll,
        mean_nll = nll / w_sum,
        brier = brier_num / w_sum,
        rmse_p = sqrt(brier_num / w_sum),
        brier_num = brier_num
      )
    })
    
    data.table::rbindlist(out_list)
  }
  environment(worker_fun) <- baseenv()
  
  # ---- Run parallel over specs ----
  if (isTRUE(parallel)) {
    res_list <- future.apply::future_lapply(
      items,
      worker_fun,
      alignedD_prosp = alignedD_prosp,
      template_df    = template_df,
      ignD           = ignD,
      all_seasons    = all_seasons,
      k_t            = k_t,
      w_early        = w_early,
      exclude_newseason_terms = exclude_newseason_terms,
      nthreads       = nthreads,
      future.seed    = TRUE,
      future.packages = c("data.table", "mgcv")
    )
    by_season <- data.table::rbindlist(res_list, use.names = TRUE, fill = TRUE)
  } else {
    by_season <- data.table::rbindlist(
      lapply(items, worker_fun,
             alignedD_prosp = alignedD_prosp,
             template_df    = template_df,
             ignD           = ignD,
             all_seasons    = all_seasons,
             k_t            = k_t,
             w_early        = w_early,
             exclude_newseason_terms = exclude_newseason_terms,
             nthreads       = nthreads),
      use.names = TRUE, fill = TRUE
    )
  }
  
  by_spec <- by_season[, .(
    n_total = sum(n),
    w_total = sum(w_sum),
    nll = sum(nll),
    mean_nll = sum(nll) / sum(w_sum),
    brier = sum(brier_num) / sum(w_sum),
    rmse_p = sqrt(sum(brier_num) / sum(w_sum))
  ), by = spec_id][order(mean_nll)]
  
  by_spec_grid <- data.table::as.data.table(grid)[by_spec, on = "spec_id"]
  
  # ---- timing ----
  t_end <- Sys.time()
  pt_end <- proc.time()
  timing <- list(
    start = t_start,
    end = t_end,
    elapsed_sec = as.numeric(difftime(t_end, t_start, units = "secs")),
    cpu_sec = unname((pt_end - pt_start)[["user.self"]] + (pt_end - pt_start)[["sys.self"]])
  )
  
  if (isTRUE(verbose)) {
    message(sprintf("[tune_stage2_loso_spec_grid] done in %.1f sec (cpu %.1f sec)",
                    timing$elapsed_sec, timing$cpu_sec))
  }
  
  list(
    by_season = by_season,
    by_spec = by_spec,
    by_spec_grid = by_spec_grid,
    best = by_spec[1],
    scoring = list(k_t = as.integer(k_t), w_early = as.numeric(w_early)),
    timing = timing,
    parallel = list(enabled = parallel, over = "spec", strategy = strategy_use, workers = workers, bam_nthreads = nthreads,
                    future_globals_max_gb = max_global_size_gb)
  )
}



#' LOSO tuning over a Stage-2 spec grid (disk-backed parallel; Linux + Windows)
#'
#' Performs leave-one-season-out (LOSO) tuning for Stage-2 by evaluating each
#' hyperparameter setting (spec) against held-out seasons, using weighted scoring
#' near ignition. This implementation is designed for **large grids** and
#' **cross-platform parallelism** (Windows + Linux/macOS) without hitting
#' `future.globals.maxSize` limits.
#'
#' ## Key design
#' - Writes large inputs (\code{alignedD_prosp}, \code{template_df}, \code{ignD}, \code{spec_grid$grid})
#'   to temporary \code{.rds} files once, then parallel workers receive only file paths + indices.
#' - Workers process \code{chunk_size} specs sequentially per job to reduce overhead.
#'
#' ## Requirements / dependencies
#' This function assumes these project functions already exist:
#' \itemize{
#'   \item \code{stage2_make_spec()}
#'   \item \code{prep_stage2_m1_features()}
#'   \item \code{stack_stage2_joint_data()}
#'   \item \code{train_stage2_joint_m1()}
#'   \item \code{stage2_exclude_newseason()} and \code{stage2_build_joint_formula()} (indirectly via spec)
#' }
#'
#' Also requires packages: \code{future}, \code{future.apply}, \code{data.table}, \code{mgcv}.
#'
#' ## Scoring weights
#' Uses **target-week** time-since-ignition:
#' \deqn{t_\mathrm{target} = (w + h) - w^{(\mathrm{ign})}}
#' Rows with \code{0 <= t_target <= k_t} are weighted \code{w_early} (default 2),
#' otherwise weight 1.
#'
#' ## Spec grid format
#' Uses \code{spec_grid$grid} (data.frame / data.table) with at least the columns:
#' \code{spec_id}, \code{delta}, \code{Kr}, \code{Kb}, \code{T}, \code{k_f},
#' \code{alpha_state}, \code{k_w}, \code{k_s}, \code{k_e}, \code{k_n},
#' \code{k_1}, \code{k_2}, \code{bs_week}, \code{bs_fs_marginal}.
#'
#' @param alignedD_prosp Aligned prospective dataset (all seasons) used for feature prep.
#'   Must contain your required columns (season/weekF/newWeek plus y/N etc).
#' @param template_df Template reference data.frame with columns \code{newWeek} and \code{fit}
#'   (logit-scale template).
#' @param spec_grid Output from \code{expand_grid_specs()}, containing \code{$grid} with
#'   the hyperparameter combinations and a unique \code{spec_id} per row.
#' @param ignD Optional ignition-rule table used as a fallback to derive ignition week
#'   when \code{iWeek} / \code{ignition} are not present in \code{alignedD_prosp}.
#' @param seasons Optional character vector of seasons to include in LOSO.
#'   If NULL, uses all seasons in \code{alignedD_prosp}. Must be >= 3.
#' @param k_t Integer. Number of **target weeks since ignition** to upweight in scoring.
#' @param w_early Numeric. Weight multiplier for the emphasized window (default 2).
#' @param exclude_newseason_terms Logical. If TRUE, predictions on the held-out season
#'   exclude season-dependent terms using \code{spec$exclude_newseason}.
#' @param workers Integer. Number of parallel workers.
#' @param strategy Future plan strategy. \code{"auto"} chooses \code{"multisession"} on Windows
#'   and \code{"multicore"} on Linux/macOS. You can force \code{"multisession"} for portability.
#' @param chunk_size Integer. Number of specs evaluated per worker job (reduces overhead).
#'   Typical values 4–16.
#' @param nthreads Integer. Threads passed to \code{mgcv::bam()} inside each worker.
#'   When \code{workers>1}, set \code{nthreads=1} to avoid CPU oversubscription.
#' @param cache_dir Directory for temporary \code{.rds} files. Defaults to \code{tempdir()}.
#'   Files are removed automatically on exit.
#' @param verbose Logical. If TRUE, prints a short run header and timing summary.
#'
#' @return A list with:
#' \itemize{
#'   \item \code{by_season}: data.table of per-spec per-heldout-season metrics
#'   \item \code{by_spec}: aggregated metrics per \code{spec_id} (ordered by \code{mean_nll})
#'   \item \code{by_spec_grid}: \code{by_spec} joined back onto \code{spec_grid$grid}
#'   \item \code{best}: best row of \code{by_spec}
#'   \item \code{scoring}: list(k_t, w_early)
#'   \item \code{timing}: list(start, end, elapsed_sec, cpu_sec)
#'   \item \code{parallel}: list(strategy, workers, chunk_size, bam_nthreads)
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' spec_grid <- expand_grid_specs(
#'   delta_grid = -1:1,
#'   Kr_grid = 1:3,
#'   Kb_grid = c(0L,1L),
#'   T_grid = c("O","S"),
#'   k_f_grid = c(6L,8L),
#'   alpha_state = c(0.25,0.35),
#'   k_w_grid = c(6L,8L),
#'   k_s_grid = c(0L),
#'   k_e_grid = c(0L,6L),
#'   k_n_grid = c(0L,6L),
#'   k_1_grid = c(4L,6L),
#'   k_2_grid = c(0L)
#' )
tune_stage2_loso_spec_grid_parallel <- function(alignedD_prosp,
                                                template_df,
                                                spec_grid,
                                                ignD = NULL,
                                                seasons = NULL,
                                                k_t = 10L,
                                                w_early = 2,
                                                exclude_newseason_terms = TRUE,
                                                # parallel controls
                                                workers = 8L,
                                                strategy = c("auto","multisession","multicore"),
                                                chunk_size = 8L,
                                                # bam threads inside each worker (keep 1 if parallel)
                                                nthreads = 1L,
                                                cache_dir = tempdir(),
                                                verbose = TRUE) {
  
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need data.table")
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Need mgcv")
  if (!requireNamespace("future", quietly = TRUE)) stop("Need future")
  if (!requireNamespace("future.apply", quietly = TRUE)) stop("Need future.apply")
  
  strategy <- match.arg(strategy)
  stopifnot(is.list(spec_grid), !is.null(spec_grid$grid))
  grid <- data.table::as.data.table(spec_grid$grid)
  
  all_seasons <- seasons %||% sort(unique(alignedD_prosp$season))
  if (length(all_seasons) < 3L) stop("Need >= 3 seasons for LOSO.")
  
  # ---- timing ----
  t_start <- Sys.time()
  pt_start <- proc.time()
  
  # ---- choose plan ----
  if (strategy == "auto") {
    strat <- if (.Platform$OS.type == "windows") "multisession" else "multicore"
  } else strat <- strategy
  
  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  future::plan(strat, workers = as.integer(workers))
  
  if (isTRUE(verbose)) {
    message("[tune_stage2_loso_spec_grid_parallel] grid_rows=", nrow(grid),
            " | seasons=", length(all_seasons),
            " | k_t=", k_t, " w_early=", w_early,
            " | strategy=", strat, " workers=", workers,
            " | chunk_size=", chunk_size,
            " | bam nthreads=", nthreads)
    if (nthreads > 1L) message("NOTE: with parallel workers, prefer bam nthreads=1 to avoid oversubscription.")
  }
  
  # ---- save big objects to disk (tiny globals to workers) ----
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  f_dat  <- file.path(cache_dir, paste0("stage2_dat_",  Sys.getpid(), "_", as.integer(runif(1,1,1e9)), ".rds"))
  f_tmp  <- file.path(cache_dir, paste0("stage2_tmp_",  Sys.getpid(), "_", as.integer(runif(1,1,1e9)), ".rds"))
  f_ign  <- file.path(cache_dir, paste0("stage2_ign_",  Sys.getpid(), "_", as.integer(runif(1,1,1e9)), ".rds"))
  f_grid <- file.path(cache_dir, paste0("stage2_grid_", Sys.getpid(), "_", as.integer(runif(1,1,1e9)), ".rds"))
  
  saveRDS(alignedD_prosp, f_dat)
  saveRDS(template_df,    f_tmp)
  saveRDS(ignD,           f_ign)
  saveRDS(grid,           f_grid)
  
  on.exit(unlink(c(f_dat, f_tmp, f_ign, f_grid), force = TRUE), add = TRUE)
  
  # ---- chunk indices ----
  idx <- seq_len(nrow(grid))
  chunk_size <- as.integer(max(1L, chunk_size))
  chunks <- split(idx, ceiling(idx / chunk_size))
  
  # ---- scoring helper inside worker (no closures that capture big env) ----
  worker_chunk <- function(idxs, f_dat, f_tmp, f_ign, f_grid,
                           all_seasons, k_t, w_early, exclude_newseason_terms, nthreads) {
    
    library(data.table)
    library(mgcv)
    
    dat  <- readRDS(f_dat)
    tmp  <- readRDS(f_tmp)
    ign  <- readRDS(f_ign)
    grid <- data.table::as.data.table(readRDS(f_grid))
    
    out <- vector("list", length(idxs))
    
    for (j in seq_along(idxs)) {
      i <- idxs[j]
      row <- grid[i]
      
      # build spec from grid row
      sp <- stage2_make_spec(
        delta = row$delta,
        Kr    = row$Kr,
        Kb    = row$Kb,
        T     = row$T,
        k_f   = ifelse(is.na(row$k_f), 6L, row$k_f),
        alpha_state = row$alpha_state,
        
        k_w = row$k_w, k_s = row$k_s, k_e = row$k_e, k_n = row$k_n, k_1 = row$k_1, k_2 = row$k_2,
        bs_week = row$bs_week, bs_fs_marginal = row$bs_fs_marginal
      )
      
      # prep once per spec
      feat <- prep_stage2_m1_features(
        alignedD_prosp = dat,
        template_df    = tmp,
        spec           = sp,
        ignD           = ign
      )
      
      # LOSO folds
      fold_res <- lapply(all_seasons, function(s_out) {
        train_seasons <- setdiff(all_seasons, s_out)
        
        fit_mod <- train_stage2_joint_m1(
          feat = feat, spec = sp,
          seasons_keep = train_seasons,
          drop_future = TRUE,
          nthreads = nthreads,
          return_data = FALSE
        )$fit
        
        d_test <- stack_stage2_joint_data(
          feat = feat, spec = sp,
          seasons_keep = s_out,
          drop_future = TRUE
        )
        
        # align factor levels safely (avoid new levels)
        lev_lead   <- fit_mod$stage2_levels$lead
        lev_season <- fit_mod$stage2_levels$season
        lev_sh     <- fit_mod$stage2_levels$season_h
        
        d_test$lead   <- factor(as.character(d_test$lead), levels = lev_lead)
        d_test$season <- factor(as.character(d_test$season), levels = lev_season)
        if (anyNA(d_test$season)) d_test$season[is.na(d_test$season)] <- lev_season[1]
        
        d_test$season_h <- interaction(d_test$season, d_test$lead, drop = TRUE)
        d_test$season_h <- factor(d_test$season_h, levels = lev_sh)
        if (anyNA(d_test$season_h)) d_test$season_h[is.na(d_test$season_h)] <- lev_sh[1]
        
        ex <- if (isTRUE(exclude_newseason_terms)) sp$exclude_newseason else NULL
        eta <- as.numeric(stats::predict(fit_mod, newdata = d_test, type = "link", exclude = ex))
        p   <- plogis(eta)
        
        # weights by TARGET week: (w+h) - ign_weekF
        t_target <- (d_test$weekF + d_test$lead_n) - d_test$ign_weekF
        w <- rep(1, length(t_target))
        w[is.finite(t_target) & t_target >= 0 & t_target <= as.integer(k_t)] <- as.numeric(w_early)
        
        y <- as.numeric(d_test$y_lead)
        N <- as.numeric(d_test$N_lead)
        p <- pmin(1 - 1e-12, pmax(1e-12, p))
        
        ok <- is.finite(y) & is.finite(N) & is.finite(p) & (N > 0) & is.finite(w)
        y <- y[ok]; N <- N[ok]; p <- p[ok]; w <- w[ok]
        
        ll <- stats::dbinom(y, size = N, prob = p, log = TRUE)
        nll <- -sum(w * ll)
        
        phat <- y / N
        se2  <- (p - phat)^2
        brier_num <- sum(w * se2)
        w_sum <- sum(w)
        
        data.table(
          spec_id = row$spec_id,
          season_out = as.character(s_out),
          n = length(p),
          w_sum = w_sum,
          nll = nll,
          mean_nll = nll / w_sum,
          brier = brier_num / w_sum,
          rmse_p = sqrt(brier_num / w_sum),
          brier_num = brier_num
        )
      })
      
      out[[j]] <- rbindlist(fold_res)
    }
    
    rbindlist(out, use.names = TRUE, fill = TRUE)
  }
  environment(worker_chunk) <- baseenv()
  
  # ---- run parallel over chunks ----
  res_chunks <- future.apply::future_lapply(
    chunks,
    worker_chunk,
    f_dat = f_dat, f_tmp = f_tmp, f_ign = f_ign, f_grid = f_grid,
    all_seasons = all_seasons,
    k_t = k_t, w_early = w_early,
    exclude_newseason_terms = exclude_newseason_terms,
    nthreads = as.integer(nthreads),
    future.seed = TRUE,
    future.packages = c("data.table", "mgcv")
  )
  
  by_season <- data.table::rbindlist(res_chunks, use.names = TRUE, fill = TRUE)
  
  by_spec <- by_season[, .(
    n_total = sum(n),
    w_total = sum(w_sum),
    nll = sum(nll),
    mean_nll = sum(nll) / sum(w_sum),
    brier = sum(brier_num) / sum(w_sum),
    rmse_p = sqrt(sum(brier_num) / sum(w_sum))
  ), by = spec_id][order(mean_nll)]
  
  by_spec_grid <- data.table::as.data.table(grid)[by_spec, on = "spec_id"]
  
  t_end <- Sys.time()
  pt_end <- proc.time()
  timing <- list(
    start = t_start,
    end = t_end,
    elapsed_sec = as.numeric(difftime(t_end, t_start, units = "secs")),
    cpu_sec = unname((pt_end - pt_start)[["user.self"]] + (pt_end - pt_start)[["sys.self"]])
  )
  
  list(
    by_season = by_season,
    by_spec = by_spec,
    by_spec_grid = by_spec_grid,
    best = by_spec[1],
    scoring = list(k_t = as.integer(k_t), w_early = as.numeric(w_early)),
    timing = timing,
    parallel = list(strategy = strat, workers = workers, chunk_size = chunk_size, bam_nthreads = nthreads)
  )
}

# ============================================================
# 6) plot_stage2_joint_fit_by_season()
# ============================================================

#' Plot Stage-2 fit vs observed by season (observed all weeks; fit post-ignition only)
#'
#' Black points: observed lead positivity for all observed target weeks in \code{feat_full}.
#' Red lines: fitted probabilities drawn only for weeks at/after ignition.
#'
#' @param out_m1 Output of \code{train_stage2_joint_m1(return_data=TRUE)}.
#' @param feat_full Full feature table from \code{prep_stage2_m1_features()} (used for pre-ignition points).
#' @param dat_raw Optional raw data with columns season/weekF/phase to compute a "true" ignition line.
#' @param ign_hat_df Optional df with columns season, iWeek_hat (dashed line).
#' @param exclude_season_re If TRUE, exclude only \code{s(season)} in prediction.
#' @param exclude_newseason_terms If TRUE, exclude \code{out_m1$spec$exclude_newseason} in prediction.
#' @param facet_by_lead If TRUE use \code{facet_grid(lead ~ season)} else \code{facet_wrap(~season)}.
#'
#' @return A ggplot object.
#' @export
plot_stage2_joint_fit_by_season <- function(out_m1,
                                            feat_full,
                                            dat_raw = NULL,
                                            ign_hat_df = NULL,
                                            exclude_season_re = FALSE,
                                            exclude_newseason_terms = FALSE,
                                            facet_by_lead = TRUE) {
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
  
  p <- ggplot2::ggplot(d_all, ggplot2::aes(x = weekF)) +
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
