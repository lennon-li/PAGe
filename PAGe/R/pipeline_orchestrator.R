# Public training orchestration and adaptive M2 grid planning.

.unwrap_stage_payload <- function(fit) {
  reserved <- c(
    "stage", "status", "selection", "config",
    "upstream_ids", "data_id", "artifact_id"
  )
  payload <- fit[setdiff(names(fit), reserved)]
  class(payload) <- "list"
  payload
}

.m2_parameter_names <- function() {
  c(
    "delta", "Kr", "k_f", "k_e", "alpha_state",
    "k_r", "k_de", "k_sp", "bias_alpha", "bias_beta"
  )
}

.m2_optional_df_axes <- function() {
  c("k_e", "k_r", "k_de", "k_sp")
}

#' Default parameter-specific M2 NLL gain caps
#'
#' The caps are applied to matched adjacent comparisons during governed M2
#' boundary inspection. A value of zero means that only a non-improving move
#' (an exact tie or a deterioration) is stopped by the practical-gain rule.
#' Smoothing dimensions use the thresholds documented in the tuning playbook;
#' structural axes use zero because their scales are discrete and not directly
#' comparable to NLL changes on continuous axes. The `k_z`, `k_u`, and `k_d`
#' basis-size caps cover the governed `offset_subset_v1` family and use the
#' same smoothing-dimension threshold as `k_f`/`k_sp`; `intercept` is a
#' structural binary axis with a zero cap.
#'
#' @return A named non-negative numeric vector covering every tuned M2 axis.
#' @export
default_m2_nll_gain_caps <- function() {
  c(
    delta = 0,
    Kr = 0,
    k_f = 0.00025,
    k_e = 0.001,
    alpha_state = 0.001,
    k_r = 0.0005,
    k_de = 0.00005,
    k_sp = 0.00025,
    bias_alpha = 0.00005,
    bias_beta = 0.00005,
    k_z = 0.00025,
    k_u = 0.00025,
    k_d = 0.00025,
    intercept = 0
  )
}

.m2_locked_grid_row <- function() {
  data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
    alpha_state = 0.20, k_r = 0L, k_de = 0L, k_sp = 8L,
    bias_alpha = 0.05, bias_beta = 0
  )
}

.m2_number_label <- function(x) {
  format(as.numeric(x), scientific = FALSE, trim = TRUE, digits = 12L)
}

.m2_spec_ids <- function(grid) {
  grid <- as.data.frame(grid)
  required <- .m2_parameter_names()
  if (!all(required %in% names(grid))) {
    stop(
      "M2 grid is missing columns: ",
      paste(setdiff(required, names(grid)), collapse = ", ")
    )
  }
  vapply(seq_len(nrow(grid)), function(i) {
    paste0(
      "d", sprintf("%+d", as.integer(grid$delta[i])),
      "_Kr", as.integer(grid$Kr[i]),
      "_kf", as.integer(grid$k_f[i]),
      "_ke", as.integer(grid$k_e[i]),
      "_as", .m2_number_label(grid$alpha_state[i]),
      "_kr", as.integer(grid$k_r[i]),
      "_kde", as.integer(grid$k_de[i]),
      "_ksp", as.integer(grid$k_sp[i]),
      "_ba", .m2_number_label(grid$bias_alpha[i]),
      "_bb", .m2_number_label(grid$bias_beta[i])
    )
  }, character(1))
}

.validate_m2_grid <- function(grid, bias_alpha = 0.05, bias_beta = 0) {
  grid <- as.data.frame(grid)
  required <- c(
    "delta", "Kr", "k_f", "k_e", "alpha_state",
    "k_r", "k_de", "k_sp"
  )
  missing <- setdiff(required, names(grid))
  if (length(missing) > 0L) {
    stop("M2 grid is missing columns: ", paste(missing, collapse = ", "))
  }
  if (!"bias_alpha" %in% names(grid)) grid$bias_alpha <- bias_alpha
  if (!"bias_beta" %in% names(grid)) grid$bias_beta <- bias_beta

  numeric_cols <- .m2_parameter_names()
  for (nm in numeric_cols) {
    if (!is.numeric(grid[[nm]]) || any(!is.finite(grid[[nm]]))) {
      stop("M2 grid column `", nm, "` must contain finite numeric values.")
    }
  }
  integer_cols <- c("delta", "Kr", "k_f", "k_e", "k_r", "k_de", "k_sp")
  for (nm in integer_cols) {
    if (any(abs(grid[[nm]] - round(grid[[nm]])) > 1e-8)) {
      stop("M2 grid column `", nm, "` must contain integers.")
    }
    grid[[nm]] <- as.integer(round(grid[[nm]]))
  }
  if (any(grid$delta < 0L) || any(grid$Kr < 1L) ||
    any(grid$k_f < 2L) || any(grid$k_e < 0L) || any(grid$k_e == 1L) ||
    any(grid$k_r < 0L) || any(grid$k_de < 0L) || any(grid$k_sp < 0L)) {
    stop("M2 grid integer parameters are outside their supported bounds; k_e must be 0 (drop) or >= 2.")
  }
  for (nm in c("alpha_state", "bias_alpha", "bias_beta")) {
    if (any(grid[[nm]] < 0 | grid[[nm]] > 1)) {
      stop("M2 grid column `", nm, "` must be in [0, 1].")
    }
    grid[[nm]] <- as.numeric(grid[[nm]])
  }
  grid
}

.m2_spec_from_row <- function(row, timing_mode = c("legacy", "fractional")) {
  timing_mode <- match.arg(timing_mode)
  stage2_make_spec(
    delta = row$delta, Kr = row$Kr, T = "S",
    k_f = row$k_f, k_e = row$k_e,
    alpha_state = row$alpha_state,
    k_r = row$k_r, k_de = row$k_de, k_sp = row$k_sp,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = row$bias_alpha, bias_beta = row$bias_beta,
    timing_mode = timing_mode
  )
}

.m2_specs_from_grid <- function(grid, bias_alpha = 0.05, bias_beta = 0,
                                timing_mode = c("legacy", "fractional")) {
  timing_mode <- match.arg(timing_mode)
  grid <- .validate_m2_grid(grid, bias_alpha = bias_alpha, bias_beta = bias_beta)
  grid$spec_id <- .m2_spec_ids(grid)
  specs <- lapply(seq_len(nrow(grid)), function(i) {
    .m2_spec_from_row(grid[i, , drop = FALSE], timing_mode = timing_mode)
  })
  names(specs) <- grid$spec_id
  list(specs = specs, grid = grid)
}

.deduplicate_m2_grid <- function(grid) {
  grid$spec_id <- .m2_spec_ids(grid)
  ids <- unique(grid$spec_id)
  out <- lapply(ids, function(id) {
    idx <- which(grid$spec_id == id)
    row <- grid[idx[1L], , drop = FALSE]
    row$provenance <- paste(unique(grid$provenance[idx]), collapse = ";")
    row
  })
  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

.initial_m2_grid <- function(max_specs) {
  incumbent <- .m2_locked_grid_row()
  rows <- list(incumbent)
  provenance <- "incumbent:v16-corrected"
  changes <- list(
    delta = 1L, Kr = 2L, k_f = c(3L, 5L), k_e = c(0L, 3L),
    alpha_state = c(0.10, 0.20), k_r = c(0L, 2L), k_de = c(0L, 2L),
    k_sp = c(0L, 4L, 8L), bias_alpha = c(0, 0.10), bias_beta = 0.05
  )
  for (nm in names(changes)) {
    for (value in changes[[nm]]) {
      candidate <- incumbent
      candidate[[nm]] <- value
      rows[[length(rows) + 1L]] <- candidate
      provenance <- c(provenance, paste0("initial_neighbor:", nm))
    }
  }
  grid <- do.call(rbind, rows)
  grid$provenance <- provenance
  grid <- .deduplicate_m2_grid(.validate_m2_grid(grid))
  utils::head(grid, max_specs)
}

.rank_previous_m2 <- function(previous_results) {
  if (is.null(previous_results)) {
    return(NULL)
  }
  if (!is.list(previous_results)) {
    stop("`previous_results` must be NULL or a list.")
  }
  has_summary <- !is.null(previous_results$summary)
  has_grid <- !is.null(previous_results$grid)
  if (!has_summary && !has_grid) {
    return(NULL)
  }
  if (!has_summary || !has_grid) {
    stop("`previous_results` must contain both `summary` and `grid`.")
  }
  if (!is.data.frame(previous_results$summary) ||
    !is.data.frame(previous_results$grid)) {
    stop("`previous_results$summary` and `$grid` must be data frames.")
  }

  grid <- .validate_m2_grid(previous_results$grid)
  canonical_ids <- .m2_spec_ids(grid)
  prior_ids <- canonical_ids
  if ("spec_id" %in% names(previous_results$grid)) {
    prior_ids <- as.character(previous_results$grid$spec_id)
    if (length(prior_ids) != nrow(grid) ||
      anyNA(prior_ids) || any(!nzchar(prior_ids)) ||
      !identical(prior_ids, canonical_ids)) {
      stop(
        "`previous_results$grid$spec_id` must exactly match the grid ",
        "parameter identities."
      )
    }
  }
  if (anyDuplicated(prior_ids)) {
    stop("`previous_results$grid` must contain unique parameter specifications.")
  }
  summary <- as.data.frame(previous_results$summary)
  if (!"spec_id" %in% names(summary)) {
    stop("`previous_results$summary` must contain `spec_id`.")
  }

  collapse_metric <- function(data, metric) {
    if (!is.data.frame(data) ||
      !all(c("spec_id", metric) %in% names(data))) {
      return(NULL)
    }
    if (!is.numeric(data[[metric]])) {
      stop("Previous M2 metric `", metric, "` must be numeric.")
    }
    ids <- as.character(data$spec_id)
    keep <- !is.na(ids) & nzchar(ids) & is.finite(data[[metric]])
    if (!any(keep)) {
      return(NULL)
    }
    values <- split(as.numeric(data[[metric]][keep]), ids[keep])
    data.frame(
      spec_id = names(values),
      metric = vapply(values, mean, numeric(1)),
      stringsAsFactors = FALSE
    )
  }

  scores <- if (is.data.frame(previous_results$scores)) {
    as.data.frame(previous_results$scores)
  } else {
    NULL
  }
  metric_values <- NULL
  metric_source <- NULL
  for (metric in c("bernoulli_nll", "mean_nll")) {
    from_summary <- collapse_metric(summary, metric)
    from_scores <- collapse_metric(scores, metric)
    summary_match <- if (is.null(from_summary)) {
      rep(NA_integer_, length(prior_ids))
    } else {
      match(prior_ids, from_summary$spec_id)
    }
    scores_match <- if (is.null(from_scores)) {
      rep(NA_integer_, length(prior_ids))
    } else {
      match(prior_ids, from_scores$spec_id)
    }
    values <- rep(NA_real_, length(prior_ids))
    sources <- rep(NA_character_, length(prior_ids))
    has_summary_value <- !is.na(summary_match)
    if (any(has_summary_value)) {
      values[has_summary_value] <- from_summary$metric[summary_match[has_summary_value]]
      sources[has_summary_value] <- "summary"
    }
    has_score_value <- is.na(values) & !is.na(scores_match)
    if (any(has_score_value)) {
      values[has_score_value] <- from_scores$metric[scores_match[has_score_value]]
      sources[has_score_value] <- "scores"
    }
    if (any(is.finite(values))) {
      metric_values <- values
      metric_source <- sources
      break
    }
  }
  if (is.null(metric_values)) {
    stop("Previous M2 results need finite `bernoulli_nll` or `mean_nll` scores.")
  }

  keep <- is.finite(metric_values)
  if (!any(keep)) {
    stop("Previous M2 `summary$spec_id` values do not match its grid.")
  }
  ranked <- grid[keep, .m2_parameter_names(), drop = FALSE]
  ranked$.metric <- metric_values[keep]
  ranked$.metric_source <- metric_source[keep]
  ranked <- ranked[order(ranked$.metric, .m2_spec_ids(ranked)), , drop = FALSE]
  attr(ranked, "previous_grid") <- grid[, .m2_parameter_names(), drop = FALSE]
  ranked
}

.select_diverse_m2 <- function(ranked, max_finalists) {
  pool <- utils::head(ranked, max(max_finalists, max_finalists * 3L))
  selected <- 1L
  while (length(selected) < min(max_finalists, nrow(pool))) {
    remaining <- setdiff(seq_len(nrow(pool)), selected)
    distances <- vapply(remaining, function(i) {
      pairwise <- vapply(selected, function(j) {
        left <- unlist(pool[i, .m2_parameter_names(), drop = FALSE],
          use.names = FALSE
        )
        right <- unlist(pool[j, .m2_parameter_names(), drop = FALSE],
          use.names = FALSE
        )
        sum(left != right)
      }, numeric(1))
      c(minimum = min(pairwise), total = sum(pairwise))
    }, numeric(2))
    pick <- order(
      -distances["minimum", ], -distances["total", ],
      pool$.metric[remaining]
    )[1L]
    selected <- c(selected, remaining[pick])
  }
  pool[selected, , drop = FALSE]
}

.m2_candidate_is_valid <- function(row) {
  !inherits(try(.validate_m2_grid(row), silent = TRUE), "try-error")
}

#' Plan a bounded M2 tuning grid
#'
#' Creates a compact, explainable M2 grid. Without compatible prior tuning
#' results, the plan contains the current v16-corrected incumbent and one-factor
#' neighbors. With prior results, it retains v16, greedily retains diverse
#' high-performing finalists, adds one-factor neighbors around the prior
#' winner, and expands grid boundaries reached by that winner using half the
#' spacing adjacent to each reached boundary.
#'
#' Boundary expansion proposes only new configurations that pass the M2 grid
#' validity contract. A meaningful null boundary, such as an optional smooth
#' set to zero, need not be expanded past its valid domain. The EMA smooth
#' specifically supports \code{k_e = 0} (drop) or \code{k_e >= 2}; \code{k_e = 1}
#' is invalid. If
#' \code{max_specs} truncates a search with a remaining boundary, report that
#' boundary as unresolved rather than as a bracketed optimum. Grid expansion
#' is a pre-holdout development activity.
#'
#' @param previous_results Optional prior \code{build_m2()} result containing
#'   \code{summary} and \code{grid}. Grid specification IDs, when supplied,
#'   must match their canonical parameter identities. Duplicate finite summary
#'   metrics are averaged by specification; fold-level \code{scores} fill
#'   missing or non-finite summary metrics. Ranking uses
#'   \code{bernoulli_nll}, then \code{mean_nll}.
#' @param max_finalists Maximum number of diverse prior finalists to retain.
#' @param max_specs Hard cap on returned specifications.
#'
#' @return A data frame with M2 parameters, stable \code{spec_id}, and
#'   semicolon-separated \code{provenance} for every row.
#' @export
plan_m2_grid <- function(previous_results = NULL,
                         max_finalists = 6L,
                         max_specs = 64L) {
  if (!is.numeric(max_finalists) || length(max_finalists) != 1L ||
    !is.finite(max_finalists) || max_finalists < 1L ||
    max_finalists != floor(max_finalists)) {
    stop("`max_finalists` must be a positive integer.")
  }
  if (!is.numeric(max_specs) || length(max_specs) != 1L ||
    !is.finite(max_specs) || max_specs < 1L ||
    max_specs != floor(max_specs)) {
    stop("`max_specs` must be a positive integer.")
  }
  max_finalists <- as.integer(max_finalists)
  max_specs <- as.integer(max_specs)

  ranked <- .rank_previous_m2(previous_results)
  if (is.null(ranked)) {
    return(.initial_m2_grid(max_specs))
  }

  finalists <- .select_diverse_m2(ranked, max_finalists)
  winner <- ranked[1L, .m2_parameter_names(), drop = FALSE]
  previous_grid <- attr(ranked, "previous_grid")
  rows <- list(.m2_locked_grid_row())
  provenance <- "incumbent:v16-corrected"

  for (i in seq_len(nrow(finalists))) {
    rows[[length(rows) + 1L]] <- finalists[i, .m2_parameter_names(), drop = FALSE]
    provenance <- c(provenance, paste0("prior_finalist:", i))
  }

  default_steps <- c(
    delta = 1, Kr = 1, k_f = 1, k_e = 1, alpha_state = 0.05,
    k_r = 2, k_de = 2, k_sp = 2, bias_alpha = 0.05, bias_beta = 0.05
  )
  integer_axes <- c("delta", "Kr", "k_f", "k_e", "k_r", "k_de", "k_sp")
  for (nm in .m2_parameter_names()) {
    observed <- sort(unique(previous_grid[[nm]]))
    current <- winner[[nm]]

    boundary_values <- numeric(0)
    if (current == min(observed)) {
      step <- if (length(observed) > 1L) {
        observed[2L] - observed[1L]
      } else {
        default_steps[[nm]]
      }
      step <- step / 2
      if (nm %in% integer_axes) step <- max(1, ceiling(step))
      boundary_values <- c(boundary_values, current - step)
    }
    if (current == max(observed)) {
      step <- if (length(observed) > 1L) {
        observed[length(observed)] - observed[length(observed) - 1L]
      } else {
        default_steps[[nm]]
      }
      step <- step / 2
      if (nm %in% integer_axes) step <- max(1, ceiling(step))
      boundary_values <- c(boundary_values, current + step)
    }
    # Optional smooths always have an explicit zero/drop candidate. Add it
    # even when a later positive expansion has made the selected value appear
    # interior; otherwise a practical-gain cap could settle without scoring
    # the drop model.
    if (nm %in% .m2_optional_df_axes() && !0L %in% observed) {
      boundary_values <- c(boundary_values, 0L)
    }
    for (value in unique(boundary_values)) {
      if (nm %in% integer_axes) value <- as.integer(round(value))
      candidate <- winner
      candidate[[nm]] <- value
      if (.m2_candidate_is_valid(candidate) && !value %in% observed) {
        rows[[length(rows) + 1L]] <- candidate
        label <- if (nm %in% .m2_optional_df_axes() && value == 0L) {
          paste0("boundary:", nm, ":drop")
        } else {
          paste0("boundary:", nm)
        }
        provenance <- c(provenance, label)
      }
    }

    lower <- observed[observed < current]
    upper <- observed[observed > current]
    local_values <- c(
      if (length(lower) > 0L) max(lower) else numeric(0),
      if (length(upper) > 0L) min(upper) else numeric(0)
    )
    for (value in local_values) {
      candidate <- winner
      candidate[[nm]] <- value
      if (.m2_candidate_is_valid(candidate)) {
        rows[[length(rows) + 1L]] <- candidate
        provenance <- c(provenance, paste0("local_neighbor:", nm))
      }
    }
  }

  grid <- do.call(rbind, rows)
  grid$provenance <- provenance
  grid <- .deduplicate_m2_grid(.validate_m2_grid(grid))
  utils::head(grid, max_specs)
}

.valid_previous_m2_spec <- function(previous_results) {
  if (!is.list(previous_results) || !is.list(previous_results$best_spec)) {
    return(NULL)
  }
  spec <- previous_results$best_spec
  required <- .m2_parameter_names()
  if (!all(required %in% names(spec))) {
    return(NULL)
  }
  row <- as.data.frame(spec[required], stringsAsFactors = FALSE)
  if (inherits(try(.validate_m2_grid(row), silent = TRUE), "try-error")) {
    return(NULL)
  }
  spec
}

.selected_m2_tuning <- function(tuning, selection) {
  if (!is.list(selection) || !is.character(selection$selected_spec_id) ||
    length(selection$selected_spec_id) != 1L ||
    !is.list(selection$selected_spec)) {
    stop("M2 selection is missing a valid specification.", call. = FALSE)
  }
  selected <- tuning
  selected$best_spec_id <- selection$selected_spec_id
  selected$best_spec <- selection$selected_spec
  validate_m2_tuning(selected)
  selected
}

.m1_params_from_tuning <- function(base, tuning) {
  if (is.null(tuning$best) || nrow(tuning$best) == 0L) {
    return(base)
  }
  best <- tuning$best[1L, , drop = FALSE]
  mapping <- c(
    k_ref = "k_ref", temperature = "multi_temperature",
    rise_weight = "align_rise_weight", slope_window = "slope_window",
    slope_weight = "slope_weight"
  )
  for (target in names(mapping)) {
    source <- mapping[[target]]
    if (source %in% names(best) && !is.na(best[[source]][1L])) {
      base[[target]] <- best[[source]][1L]
    }
  }
  base$k_ref <- as.integer(base$k_ref)
  base$slope_window <- as.integer(base$slope_window)
  base
}

.resolve_holdout_release <- function(allD, holdout_season, promotion) {
  if (length(holdout_season) > 1L ||
    (!is.null(holdout_season) && !nzchar(holdout_season))) {
    stop("`prospective_holdout` must be NULL or one non-empty season.")
  }
  present <- !is.null(holdout_season) &&
    holdout_season %in% as.character(allD$season)
  if (is.null(promotion)) {
    return(list(
      season = holdout_season, present = present, released = FALSE,
      status = if (present) "held_out" else "not_present",
      promotion_pass = NULL
    ))
  }
  if (!.is_verified_promotion_evidence(
    promotion,
    allD = allD,
    holdout_season = holdout_season
  )) {
    stop(
      "`promotion` must be verified promotion evidence created by ",
      "verify_promotion_evidence() for these data and this holdout season."
    )
  }
  released <- present && isTRUE(promotion$report$pass)
  list(
    season = holdout_season, present = present, released = released,
    status = if (!present) {
      "not_present"
    } else if (released) {
      "released"
    } else {
      "promotion_failed"
    },
    promotion_pass = isTRUE(promotion$report$pass)
  )
}

#' Train all PAGe pipeline components
#'
#' Runs either a locked production refresh or a full M0, M1, and M2 retune.
#' Refresh mode performs no LOSO tuning and uses a compatible prior best M2
#' specification when available, otherwise deployed v16. Retune mode uses
#' \code{plan_m2_grid()} unless an explicit M2 grid is supplied, then fits the
#' winning M2 specification on all non-excluded seasons.
#'
#' @param allD Multi-season surveillance data.
#' @param mode \code{"refresh"} for locked fitting or \code{"retune"} for LOSO
#'   tuning followed by production fitting.
#' @param previous_results Optional prior M2 tuning result.
#' @param exclude Seasons excluded from component and final production fitting.
#' @param prospective_holdout Season kept out of every tuning and fitting stage
#'   until an explicit passing promotion report releases it. Defaults to
#'   2025-26; use NULL only when no prospective holdout exists.
#' @param promotion Optional artifact-bound evidence returned by
#'   \code{verify_promotion_evidence()}. A bare \code{check_promotion()} report
#'   is not governed production evidence and cannot release the holdout. The R
#'   class is forgeable; verification of the retained bundle, manifest, data,
#'   candidate, and incumbent artifacts is the safety boundary.
#' @param loso_seasons LOSO folds passed to all tuning stages.
#' @param n_cores Parallel worker count passed to tuning stages.
#' @param checkpoint_dir Optional parent checkpoint directory.
#' @param verbose Logical progress flag.
#' @param m0_grid,m1_grid Optional explicit M0 and M1 tuning grids.
#' @param m2_grid Optional explicit M2 grid; \code{NULL} uses
#'   \code{plan_m2_grid(previous_results)}.
#' @param m2_family M2 model family. The default \code{"offset_subset_v1"}
#'   is the governed subset family; \code{"legacy"} is research/compatibility
#'   only.
#' @param allow_legacy Logical; explicitly allow the legacy research path.
#' @param max_m2_finalists,max_m2_specs Adaptive M2 plan caps.
#' @param selection_method Final full-LOSO selection rule passed to
#'   \code{select_m2_candidate()}. Defaults to minimum Bernoulli NLL.
#' @param racing Logical; conservatively pre-race the planned M2 grid. This is
#'   off by default and requires \code{racing_evaluator}.
#' @param racing_evaluator Callback returning partial fold-level scores. Partial
#'   results only eliminate clear losers; surviving specs still run full LOSO.
#' @param racing_stages,racing_min_survivors Racing schedule and survivor floor.
#' @param manual_labels,flag_args,m1_params Optional component settings. For a
#'   released holdout, these are derived exclusively from verified promotion
#'   evidence and explicit overrides are rejected.
#' @param timing_labels Optional timing-v2 label object or list of objects.
#'   When supplied, the earlier ignition weeks are converted to the existing
#'   M0/M1 training contract, while the complete timing-v2 object is retained
#'   in the result for provenance. Cannot be combined with \code{manual_labels}.
#' @param m1_min_gain Minimum M1 Weibull-MAE improvement, in weeks, required to
#'   justify a more flexible `k_ref` candidate (default 0.05).
#' @param m1_hard_caps Named M1 hard caps accepted by the boundary gate. The
#'   default is returned by \code{default_m1_hard_caps()} and bounds `k_ref`
#'   to 10--50 on the 52-week reference domain.
#' @param m2_min_nll_gain Named parameter-specific NLL gain thresholds passed to
#'   the M2 boundary gate. Defaults to \code{default_m2_nll_gain_caps()} and
#'   covers every M2 axis. A scalar applies to every M2 axis. An edge is
#'   accepted only when its matched outward gain is at or below the threshold;
#'   missing matched evidence still requires expansion.
#' @param early_weight Weight for target-relative weeks zero through
#'   \code{early_max_t_since} in subset-M2 tuning (default 2).
#' @param early_max_t_since Last target-relative week receiving
#'   \code{early_weight} (default 12).
#' @param pre_ignition_weight Weight for pre-ignition targets (default 0).
#' @param late_weight Weight for targets after \code{early_max_t_since}
#'   (default 1).
#' @param score_scale Primary subset-M2 score denominator, either
#'   \code{"equal_week"} (default) or \code{"test_count"}.
#' @param m0_params Optional M0 parameters for refresh mode. Defaults to the
#'   deployed configuration when no holdout has been released. For a released
#'   holdout it is derived exclusively from verified promotion evidence.
#' @param m2_spec_id Optional identity for an unreleased fixed refresh M2 spec;
#'   it is derived from promotion evidence after holdout acceptance.
#'
#' @return A transparent list with \code{mode}, \code{components},
#'   \code{tuning} (NULL for refresh), \code{grid},
#'   \code{grid_provenance}, full-result \code{selection}, optional
#'   \code{racing} diagnostics, transparent \code{holdout} release state,
#'   attached \code{preflight} and \code{boundary_actions} reports, and
#'   deployment \code{kit}. When supplied, \code{timing_labels_v2} preserves
#'   the complete timing-v2 label object or list used for training.
#' @export
train_pipeline <- function(
  allD,
  mode = c("refresh", "retune"),
  previous_results = NULL,
  exclude = c("2011-12", "2015-16", "2020-21", "2021-22"),
  prospective_holdout = "2025-26",
  promotion = NULL,
  loso_seasons = "all",
  n_cores = parallel::detectCores() - 1L,
  checkpoint_dir = NULL,
  verbose = TRUE,
  m0_grid = .default_m0_grid(),
  m1_grid = default_m1_grid(),
  m2_grid = NULL,
  m2_family = c("offset_subset_v1", "legacy"),
  allow_legacy = FALSE,
  max_m2_finalists = 6L,
  max_m2_specs = 64L,
  selection_method = c("min_nll", "one_se", "pareto"),
  racing = FALSE,
  racing_evaluator = NULL,
  racing_stages = c(3L, 6L),
  racing_min_survivors = 3L,
  manual_labels = NULL,
  timing_labels = NULL,
  timing_mode = c("legacy", "fractional"),
  flag_args = NULL,
  m1_params = NULL,
  m1_min_gain = 0.05,
  m1_hard_caps = default_m1_hard_caps(),
  m2_min_nll_gain = default_m2_nll_gain_caps(),
  early_weight = 2,
  early_max_t_since = 12,
  pre_ignition_weight = 0,
  late_weight = 1,
  score_scale = c("equal_week", "test_count"),
  m0_params = NULL,
  m2_spec_id = NULL
) {
  mode <- match.arg(mode)
  selection_method <- match.arg(selection_method)
  m2_family <- match.arg(m2_family)
  if (!is.logical(allow_legacy) || length(allow_legacy) != 1L ||
    is.na(allow_legacy)) {
    stop("allow_legacy must be TRUE or FALSE.", call. = FALSE)
  }
  if (identical(m2_family, "legacy") && !isTRUE(allow_legacy)) {
    stop(
      "Legacy M2 training is research/compatibility-only; set ",
      "allow_legacy = TRUE explicitly.",
      call. = FALSE
    )
  }
  if (identical(m2_family, "legacy")) {
    warning(
      "Legacy M2 training uses training features that are not season-held-out.",
      call. = FALSE
    )
  }
  timing_mode <- match.arg(timing_mode)
  score_scale <- match.arg(score_scale)
  if (!is.null(manual_labels) && !is.null(timing_labels)) {
    stop("Supply either `manual_labels` or `timing_labels`, not both.", call. = FALSE)
  }
  n_cores <- as.integer(max(1L, n_cores))
  m1_hard_caps <- .normalize_m1_hard_caps(m1_hard_caps)
  allD <- prepare_surveillance_data(allD)
  if (!nrow(allD)) stop("`allD` must contain at least one surveillance row.")
  holdout <- .resolve_holdout_release(allD, prospective_holdout, promotion)
  if (mode == "retune" && holdout$released) {
    stop(
      "Post-acceptance retuning is not permitted; use `mode = \"refresh\"` ",
      "to refit the fixed accepted specification.",
      call. = FALSE
    )
  }
  if (holdout$released) {
    locked <- promotion$candidate_config
    supplied <- list(
      m0_params = m0_params, m1_params = m1_params,
      manual_labels = manual_labels, flag_args = flag_args,
      timing_labels = timing_labels, previous_results = previous_results,
      m2_spec_id = m2_spec_id
    )
    if (any(vapply(supplied, Negate(is.null), logical(1)))) {
      stop(
        "A post-acceptance refresh derives its configuration from verified ",
        "promotion evidence; do not supply component overrides.",
        call. = FALSE
      )
    }
    m0_params <- locked$m0_params
    m1_params <- locked$m1_params
    manual_labels <- locked$manual_labels
    flag_args <- locked$flag_args
    previous_results <- list(best_spec = locked$best_spec)
    m2_spec_id <- locked$best_spec_id
  }
  if (is.null(m0_params)) {
    m0_params <- .default_m0_params()
  }
  if (is.null(m1_params)) m1_params <- .default_m1_params()
  supplied_timing_labels <- timing_labels
  timing_labels <- .timing_v2_filter_holdout(
    timing_labels,
    if (holdout$present && !holdout$released) prospective_holdout else NULL
  )
  if (!is.null(timing_labels)) manual_labels <- as_manual_labels_v2(timing_labels)
  timing_targets <- if (timing_mode == "fractional") {
    if (is.null(timing_labels)) {
      stop("Fractional timing requires `timing_labels`.", call. = FALSE)
    }
    as_timing_targets_v2(timing_labels)
  } else {
    NULL
  }
  if (is.null(manual_labels)) manual_labels <- .default_manual_labels()
  if (is.null(flag_args)) flag_args <- .default_flag_args()
  effective_exclude <- unique(c(
    exclude,
    if (holdout$present && !holdout$released) prospective_holdout else character(0)
  ))
  holdout$effective_exclude <- effective_exclude

  if (mode == "refresh") {
    data_seasons <- unique(as.character(allD$season))
    held_out <- holdout$present && !holdout$released
    holdout_seasons <- if (held_out) prospective_holdout else character(0)
    exclude_seasons <- intersect(exclude, data_seasons)
    training_seasons <- setdiff(data_seasons, c(exclude_seasons, holdout_seasons))
    if (holdout$released) {
      expected_training <- unique(c(
        as.character(locked$training_seasons),
        prospective_holdout
      ))
      if (!setequal(training_seasons, expected_training)) {
        stop(
          "A post-acceptance refresh must use the accepted candidate's ",
          "training seasons plus the released holdout.",
          call. = FALSE
        )
      }
    }
    if (!length(training_seasons)) {
      stop("`allD` must contain at least one trainable season after exclusions.")
    }
    selection <- validate_season_selection(
      allD,
      training_seasons = training_seasons,
      exclude_seasons = exclude_seasons,
      holdout_seasons = holdout_seasons
    )
    m0 <- freeze_m0(fit_m0(
      allD, selection,
      config = m0_params,
      manual_labels = manual_labels,
      flag_args = flag_args,
      timing_truth = timing_targets
    ))
    m1 <- freeze_m1(fit_m1(
      allD, selection,
      m0 = m0, config = m1_params,
      timing_mode = timing_mode, timing_truth = timing_targets
    ))
    best_spec <- .valid_previous_m2_spec(previous_results)
    if (is.null(best_spec) && m2_subset_is_family(previous_results$best_spec %||% NULL)) {
      best_spec <- m2_subset_validate_config(previous_results$best_spec)
      m2_family <- m2_subset_family()
    }
    if (is.null(best_spec)) {
      best_spec <- if (m2_family == m2_subset_family()) {
        m2_subset_validate_config(previous_results$best_spec %||% m2_subset_config())
      } else {
        .default_m2_spec()
      }
    }
    if (m2_family == m2_subset_family() && !m2_subset_is_family(best_spec)) {
      stop("M2 family `offset_subset_v1` requires an offset subset specification.", call. = FALSE)
    }
    m2_model <- freeze_m2(fit_m2(
      allD, selection,
      m0 = m0, m1 = m1,
      config = best_spec,
      family = m2_family,
      allow_legacy = allow_legacy,
      n_cores = n_cores,
      verbose = verbose,
      timing_mode = timing_mode,
      timing_truth = timing_targets
    ))
    kit <- assemble_kit(
      m0, m1, m2_model,
      best_spec_id = .m2_spec_identity(best_spec, m2_spec_id)
    )
    return(structure(list(
      mode = mode,
      components = list(
        m0 = .unwrap_stage_payload(m0),
        m1 = .unwrap_stage_payload(m1),
        m2 = .unwrap_stage_payload(m2_model)
      ),
      tuning = NULL, grid = NULL, grid_provenance = NULL,
      selection = NULL, racing = NULL, holdout = holdout,
      timing_labels_v2 = supplied_timing_labels,
      timing_labels_v2_training = timing_labels,
      kit = kit
    ), class = c("page_training_result", "list")))
  }

  data_seasons <- unique(as.character(allD$season))
  held_out <- holdout$present && !holdout$released
  holdout_seasons <- if (held_out) prospective_holdout else character(0)
  exclude_seasons <- intersect(exclude, data_seasons)
  eligible_seasons <- setdiff(data_seasons, c(exclude_seasons, holdout_seasons))
  training_seasons <- if (identical(loso_seasons, "all")) {
    eligible_seasons
  } else if (identical(loso_seasons, "alternating")) {
    eligible_seasons[c(TRUE, FALSE)]
  } else if (is.character(loso_seasons)) {
    intersect(loso_seasons, eligible_seasons)
  } else {
    stop("`loso_seasons` must be 'all', 'alternating', or a character vector.")
  }
  if (!length(training_seasons)) {
    stop("`loso_seasons` must identify at least one eligible training season.")
  }
  application_seasons <- setdiff(eligible_seasons, training_seasons)
  selection <- validate_season_selection(
    allD,
    training_seasons = training_seasons,
    exclude_seasons = exclude_seasons,
    holdout_seasons = holdout_seasons,
    application_seasons = application_seasons
  )

  preflight <- preflight_support_audit(
    allD,
    m0_grid = m0_grid,
    m1_grid = m1_grid,
    selection = selection
  )
  # Keep the audit attached to the run rather than failing before the stage
  # validators have a chance to issue their more specific errors.  Callers
  # that want a hard gate can inspect `preflight_support_audit()` directly.

  m0_tuning <- tune_m0(
    allD,
    grid = m0_grid, manual_labels = manual_labels, flag_args = flag_args,
    n_cores = n_cores, verbose = verbose,
    selection = selection,
    timing_truth = timing_targets,
    timing_mode = timing_mode
  )
  m0_tuning <- validate_m0_tuning(
    m0_tuning,
    grid = m0_grid, check_boundaries = TRUE
  )
  m0_boundary_action <- if (is.data.frame(m0_tuning$grid)) {
    boundary_action_plan(m0_tuning, stage = "M0")
  } else {
    NULL
  }
  m0 <- freeze_m0(
    fit_m0(
      allD, selection,
      config = m0_tuning$best_params,
      manual_labels = manual_labels, flag_args = flag_args,
      timing_truth = timing_targets
    ),
    tuning = m0_tuning
  )

  m1_checkpoint <- if (is.null(checkpoint_dir)) {
    NULL
  } else {
    file.path(checkpoint_dir, "m1")
  }
  m1_tuning <- tune_m1(
    allD,
    m0 = m0, m1 = list(m1_params = m1_params),
    grid = m1_grid, n_cores = n_cores,
    checkpoint_dir = m1_checkpoint, verbose = verbose,
    selection = selection,
    timing_truth = timing_targets,
    timing_mode = timing_mode
  )
  # M1 is a governed stage boundary: do not freeze an unresolved non-null
  # edge winner or spend M2 compute on a grid that must be expanded.
  m1_tuning$hard_caps <- m1_hard_caps
  m1_tuning <- validate_m1_tuning(
    m1_tuning,
    check_boundaries = TRUE, hard_caps = m1_hard_caps
  )
  m1_selection <- select_m1_candidate(
    m1_tuning,
    min_gain = m1_min_gain, prefer_simpler = TRUE,
    hard_caps = m1_hard_caps
  )
  m1_tuning$best <- m1_selection$selected
  m1_tuning$m1_selection <- m1_selection
  m1_boundary_action <- if (is.data.frame(m1_tuning$grid) &&
    all(c("k_ref", "slope_window", "slope_weight") %in% names(m1_tuning$grid))) {
    boundary_action_plan(
      m1_tuning,
      stage = "M1", hard_caps = m1_hard_caps
    )
  } else {
    NULL
  }
  tuned_m1_params <- .m1_params_from_tuning(m1_params, m1_tuning)
  m1 <- freeze_m1(
    fit_m1(
      allD, selection,
      m0 = m0, config = tuned_m1_params,
      timing_mode = timing_mode, timing_truth = timing_targets
    ),
    tuning = m1_tuning
  )

  if (is.null(m2_grid)) {
    m2_grid <- if (m2_family == m2_subset_family()) {
      m2_subset_grid()
    } else {
      plan_m2_grid(
        previous_results,
        max_finalists = max_m2_finalists,
        max_specs = max_m2_specs
      )
    }
  }
  if (isTRUE(racing) && m2_family == m2_subset_family()) {
    stop("`racing = TRUE` is not supported for M2 family `offset_subset_v1`.", call. = FALSE)
  }
  m2_preflight <- if (m2_family == m2_subset_family()) {
    NULL
  } else {
    preflight_support_audit(
      allD,
      m2_grid = m2_grid, selection = selection
    )
  }
  m2_checkpoint <- if (is.null(checkpoint_dir)) {
    NULL
  } else {
    file.path(checkpoint_dir, "m2")
  }
  run_full_m2 <- function(grid, ...) {
    tune_m2(
      allD,
      selection = selection, m0 = m0, m1 = m1,
      grid = grid, n_cores = n_cores,
      checkpoint_dir = m2_checkpoint, verbose = verbose, family = m2_family,
      early_weight = early_weight,
      early_max_t_since = early_max_t_since,
      pre_ignition_weight = pre_ignition_weight,
      late_weight = late_weight,
      score_scale = score_scale,
      allow_legacy = allow_legacy,
      timing_mode = timing_mode,
      timing_truth = timing_targets
    )
  }
  racing_result <- NULL
  if (isTRUE(racing)) {
    if (!is.function(racing_evaluator)) {
      stop("`racing=TRUE` requires a `racing_evaluator` callback.")
    }
    racing_result <- race_m2_candidates(
      m2_grid,
      evaluator = racing_evaluator,
      stages = racing_stages,
      min_survivors = racing_min_survivors,
      full_evaluator = run_full_m2
    )
    m2_tuning <- racing_result$final
  } else {
    m2_tuning <- run_full_m2(m2_grid)
  }
  if (m2_family == m2_subset_family()) {
    m2_tuning <- m2_subset_validate_tuning(m2_tuning)
    m2_tuning$min_nll_gain <- m2_min_nll_gain
    m2_boundary_action <- boundary_action_plan(
      m2_tuning,
      stage = "M2",
      max_specs = max(nrow(m2_tuning$grid) + 32L, nrow(m2_tuning$grid))
    )
    if (!isTRUE(m2_boundary_action$settled)) {
      stop(
        "M2 subset tuning has unresolved boundary values. Use ",
        "`m2_boundary_action$next_grid` with the same checkpoint_dir and ",
        "rerun `train_pipeline()`.",
        call. = FALSE
      )
    }
    m2_tuning <- validate_m2_tuning(
      m2_tuning,
      check_boundaries = TRUE,
      min_nll_gain = m2_min_nll_gain
    )
    m2_selection <- list(
      method = "complete_inner_nll",
      selected_spec_id = m2_tuning$best_spec_id,
      selected_spec = m2_tuning$selected_config,
      selected = m2_tuning$selected_config,
      candidates = m2_tuning$summary
    )
  } else {
    # M2 is the final governed tuning stage: reject a genuinely tuned edge
    # before fitting/freezing a production configuration. Users can inspect
    # the warning and call expand_tuning_grid() to extend the same checkpoint.
    m2_tuning$min_nll_gain <- m2_min_nll_gain
    m2_tuning <- validate_m2_tuning(
      m2_tuning,
      check_boundaries = TRUE,
      min_nll_gain = m2_min_nll_gain
    )
    m2_selection <- select_m2_candidate(m2_tuning, method = selection_method)
    m2_boundary_action <- boundary_action_plan(
      m2_tuning,
      stage = "M2", selection_method = selection_method
    )
  }
  if (is.null(m2_selection$selected_spec)) {
    stop("Selected M2 specification could not be reconstructed from tuning results.")
  }
  selected_m2_tuning <- .selected_m2_tuning(m2_tuning, m2_selection)
  if (m2_family == m2_subset_family()) {
    m2_model <- freeze_m2(
      fit_m2(
        allD, selection,
        m0 = m0, m1 = m1,
        config = m2_selection$selected_spec,
        family = m2_family,
        allow_legacy = allow_legacy,
        m1_train_preds = m2_tuning$m1_train_preds,
        n_cores = n_cores,
        verbose = verbose,
        timing_mode = timing_mode,
        timing_truth = timing_targets
      ),
      tuning = selected_m2_tuning
    )
  } else {
    m2_model <- freeze_m2(
      fit_m2(
        allD, selection,
        m0 = m0, m1 = m1,
        config = m2_selection$selected_spec,
        family = m2_family,
        allow_legacy = allow_legacy,
        n_cores = n_cores,
        verbose = verbose,
        timing_mode = timing_mode,
        timing_truth = timing_targets
      ),
      tuning = selected_m2_tuning
    )
  }
  kit <- assemble_kit(
    m0, m1, m2_model,
    best_spec_id = m2_selection$selected_spec_id
  )

  structure(list(
    mode = mode,
    components = list(
      m0 = .unwrap_stage_payload(m0),
      m1 = .unwrap_stage_payload(m1),
      m2 = .unwrap_stage_payload(m2_model)
    ),
    tuning = list(m0 = m0_tuning$tuning, m1 = m1_tuning, m2 = m2_tuning),
    grid = m2_tuning$grid,
    grid_provenance = m2_tuning$grid$provenance %||% NULL,
    selection = m2_selection,
    boundary_actions = list(
      m0 = m0_boundary_action,
      m1 = m1_boundary_action,
      m2 = m2_boundary_action
    ),
    racing = racing_result,
    holdout = holdout,
    timing_labels_v2 = supplied_timing_labels,
    timing_labels_v2_training = timing_labels,
    timing_mode = timing_mode,
    preflight = list(static = preflight, m2 = m2_preflight),
    kit = kit
  ), class = c("page_training_result", "list"))
}
