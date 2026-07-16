# Public training orchestration and adaptive M2 grid planning.

.m2_parameter_names <- function() {
  c(
    "delta", "Kr", "k_f", "k_e", "alpha_state",
    "k_r", "k_de", "k_sp", "bias_alpha", "bias_beta"
  )
}

.m2_locked_grid_row <- function() {
  data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
    alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
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

.validate_m2_grid <- function(grid, bias_alpha = 0.4, bias_beta = 0) {
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
    any(grid$k_f < 2L) || any(grid$k_e < 2L) ||
    any(grid$k_r < 0L) || any(grid$k_de < 0L) || any(grid$k_sp < 0L)) {
    stop("M2 grid integer parameters are outside their supported bounds.")
  }
  for (nm in c("alpha_state", "bias_alpha", "bias_beta")) {
    if (any(grid[[nm]] < 0 | grid[[nm]] > 1)) {
      stop("M2 grid column `", nm, "` must be in [0, 1].")
    }
    grid[[nm]] <- as.numeric(grid[[nm]])
  }
  grid
}

.m2_spec_from_row <- function(row) {
  stage2_make_spec(
    delta = row$delta, Kr = row$Kr, T = "S",
    k_f = row$k_f, k_e = row$k_e,
    alpha_state = row$alpha_state,
    k_r = row$k_r, k_de = row$k_de, k_sp = row$k_sp,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = row$bias_alpha, bias_beta = row$bias_beta
  )
}

.m2_specs_from_grid <- function(grid, bias_alpha = 0.4, bias_beta = 0) {
  grid <- .validate_m2_grid(grid, bias_alpha = bias_alpha, bias_beta = bias_beta)
  grid$spec_id <- .m2_spec_ids(grid)
  specs <- lapply(seq_len(nrow(grid)), function(i) {
    .m2_spec_from_row(grid[i, , drop = FALSE])
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
  provenance <- "incumbent:v16"
  changes <- list(
    delta = 1L, Kr = 2L, k_f = c(3L, 5L), k_e = 3L,
    alpha_state = c(0.10, 0.20), k_r = 2L, k_de = 2L,
    k_sp = c(4L, 8L), bias_alpha = c(0, 0.10), bias_beta = 0.05
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
  prior_ids <- if ("spec_id" %in% names(previous_results$grid)) {
    as.character(previous_results$grid$spec_id)
  } else {
    .m2_spec_ids(grid)
  }
  summary <- as.data.frame(previous_results$summary)
  if (!"spec_id" %in% names(summary)) {
    stop("`previous_results$summary` must contain `spec_id`.")
  }
  metric <- if ("bernoulli_nll" %in% names(summary)) {
    "bernoulli_nll"
  } else if ("mean_nll" %in% names(summary)) {
    "mean_nll"
  } else {
    NULL
  }
  if (is.null(metric) && is.data.frame(previous_results$scores) &&
    "spec_id" %in% names(previous_results$scores)) {
    scores <- as.data.frame(previous_results$scores)
    metric <- if ("bernoulli_nll" %in% names(scores)) {
      "bernoulli_nll"
    } else if ("mean_nll" %in% names(scores)) {
      "mean_nll"
    } else {
      NULL
    }
    if (!is.null(metric)) {
      summary <- stats::aggregate(
        scores[[metric]],
        list(spec_id = as.character(scores$spec_id)),
        mean,
        na.rm = TRUE
      )
      names(summary)[2L] <- metric
    }
  }
  if (is.null(metric)) {
    stop("Previous M2 results need `bernoulli_nll` or `mean_nll` scores.")
  }

  matched <- match(as.character(summary$spec_id), prior_ids)
  keep <- !is.na(matched) & is.finite(summary[[metric]])
  if (!any(keep)) {
    stop("Previous M2 `summary$spec_id` values do not match its grid.")
  }
  ranked <- grid[matched[keep], .m2_parameter_names(), drop = FALSE]
  ranked$.metric <- as.numeric(summary[[metric]][keep])
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
#' results, the plan contains the deployed v16 specification and one-factor
#' neighbors. With prior results, it retains v16, greedily retains diverse
#' high-performing finalists, adds one-factor neighbors around the prior
#' winner, and expands grid boundaries reached by that winner.
#'
#' @param previous_results Optional prior \code{build_m2()} result containing
#'   \code{summary} and \code{grid}; \code{scores} may supply a missing summary
#'   metric. Ranking uses \code{bernoulli_nll}, then \code{mean_nll}.
#' @param max_finalists Maximum number of diverse prior finalists to retain.
#' @param max_specs Hard cap on returned specifications.
#'
#' @return A data frame with M2 parameters, stable \code{spec_id}, and
#'   semicolon-separated \code{provenance} for every row.
#' @export
plan_m2_grid <- function(previous_results = NULL,
                         max_finalists = 6L,
                         max_specs = 64L) {
  max_finalists <- as.integer(max_finalists)
  max_specs <- as.integer(max_specs)
  if (length(max_finalists) != 1L || is.na(max_finalists) || max_finalists < 1L) {
    stop("`max_finalists` must be a positive integer.")
  }
  if (length(max_specs) != 1L || is.na(max_specs) || max_specs < 1L) {
    stop("`max_specs` must be a positive integer.")
  }

  ranked <- .rank_previous_m2(previous_results)
  if (is.null(ranked)) {
    return(.initial_m2_grid(max_specs))
  }

  finalists <- .select_diverse_m2(ranked, max_finalists)
  winner <- ranked[1L, .m2_parameter_names(), drop = FALSE]
  previous_grid <- attr(ranked, "previous_grid")
  rows <- list(.m2_locked_grid_row())
  provenance <- "incumbent:v16"

  for (i in seq_len(nrow(finalists))) {
    rows[[length(rows) + 1L]] <- finalists[i, .m2_parameter_names(), drop = FALSE]
    provenance <- c(provenance, paste0("prior_finalist:", i))
  }

  default_steps <- c(
    delta = 1, Kr = 1, k_f = 1, k_e = 1, alpha_state = 0.05,
    k_r = 2, k_de = 2, k_sp = 2, bias_alpha = 0.05, bias_beta = 0.05
  )
  for (nm in .m2_parameter_names()) {
    observed <- sort(unique(previous_grid[[nm]]))
    current <- winner[[nm]]
    step <- if (length(observed) > 1L) min(diff(observed)) else default_steps[[nm]]

    boundary_values <- numeric(0)
    if (current == min(observed)) boundary_values <- c(boundary_values, current - step)
    if (current == max(observed)) boundary_values <- c(boundary_values, current + step)
    for (value in unique(boundary_values)) {
      candidate <- winner
      candidate[[nm]] <- value
      if (.m2_candidate_is_valid(candidate) && !value %in% observed) {
        rows[[length(rows) + 1L]] <- candidate
        provenance <- c(provenance, paste0("boundary:", nm))
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
  if (!.is_canonical_promotion_report(promotion, require_locked = TRUE)) {
    stop(
      "`promotion` must be a canonical check_promotion() report using the ",
      "locked release thresholds."
    )
  }
  released <- present && isTRUE(promotion$pass)
  list(
    season = holdout_season, present = present, released = released,
    status = if (!present) {
      "not_present"
    } else if (released) {
      "released"
    } else {
      "promotion_failed"
    },
    promotion_pass = isTRUE(promotion$pass)
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
#' @param promotion Optional canonical report returned by
#'   \code{check_promotion()} with the locked 2 percent NLL, 5 percent horizon,
#'   and 10 percent phase thresholds. Schema validation checks structure and
#'   internal consistency, not cryptographic provenance. A malformed, custom-
#'   threshold, or failed report never releases the holdout.
#' @param loso_seasons LOSO folds passed to all tuning stages.
#' @param n_cores Parallel worker count passed to tuning stages.
#' @param checkpoint_dir Optional parent checkpoint directory.
#' @param verbose Logical progress flag.
#' @param m0_grid,m1_grid Optional explicit M0 and M1 tuning grids.
#' @param m2_grid Optional explicit M2 grid; \code{NULL} uses
#'   \code{plan_m2_grid(previous_results)}.
#' @param max_m2_finalists,max_m2_specs Adaptive M2 plan caps.
#' @param selection_method Final full-LOSO selection rule passed to
#'   \code{select_m2_candidate()}. Defaults to minimum Bernoulli NLL.
#' @param racing Logical; conservatively pre-race the planned M2 grid. This is
#'   off by default and requires \code{racing_evaluator}.
#' @param racing_evaluator Callback returning partial fold-level scores. Partial
#'   results only eliminate clear losers; surviving specs still run full LOSO.
#' @param racing_stages,racing_min_survivors Racing schedule and survivor floor.
#' @param manual_labels,flag_args,m1_params Locked component settings.
#'
#' @return A transparent list with \code{mode}, \code{components},
#'   \code{tuning} (NULL for refresh), \code{grid},
#'   \code{grid_provenance}, full-result \code{selection}, optional
#'   \code{racing} diagnostics, transparent \code{holdout} release state, and
#'   deployment \code{kit}.
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
  max_m2_finalists = 6L,
  max_m2_specs = 64L,
  selection_method = c("min_nll", "one_se", "pareto"),
  racing = FALSE,
  racing_evaluator = NULL,
  racing_stages = c(3L, 6L),
  racing_min_survivors = 3L,
  manual_labels = .default_manual_labels(),
  flag_args = .default_flag_args(),
  m1_params = .default_m1_params()
) {
  mode <- match.arg(mode)
  selection_method <- match.arg(selection_method)
  n_cores <- as.integer(max(1L, n_cores))
  allD <- prepare_surveillance_data(allD)
  if (!nrow(allD)) stop("`allD` must contain at least one surveillance row.")
  holdout <- .resolve_holdout_release(allD, prospective_holdout, promotion)
  effective_exclude <- unique(c(
    exclude,
    if (holdout$present && !holdout$released) prospective_holdout else character(0)
  ))
  pipeline_data <- if (holdout$present && !holdout$released) {
    allD[as.character(allD$season) != prospective_holdout, , drop = FALSE]
  } else {
    allD
  }
  holdout$effective_exclude <- effective_exclude

  if (mode == "refresh") {
    m0 <- build_m0(
      pipeline_data,
      exclude = effective_exclude, manual_labels = manual_labels,
      flag_args = flag_args
    )
    m1 <- build_m1(
      pipeline_data,
      m0 = m0, exclude = effective_exclude, m1_params = m1_params
    )
    best_spec <- .valid_previous_m2_spec(previous_results)
    if (is.null(best_spec)) best_spec <- .default_m2_spec()
    m2_model <- train_m2(
      pipeline_data,
      m0 = m0, m1 = m1, best_spec = best_spec,
      exclude = effective_exclude, verbose = verbose
    )
    kit <- assemble_kit(m0, m1, m2_model)
    return(structure(list(
      mode = mode,
      components = list(m0 = m0, m1 = m1, m2 = m2_model),
      tuning = NULL, grid = NULL, grid_provenance = NULL,
      selection = NULL, racing = NULL, holdout = holdout, kit = kit
    ), class = c("page_training_result", "list")))
  }

  m0 <- tune_m0(
    pipeline_data,
    loso_seasons = loso_seasons, exclude = effective_exclude,
    grid = m0_grid, manual_labels = manual_labels, flag_args = flag_args,
    n_cores = n_cores, verbose = verbose
  )
  m1_initial <- build_m1(
    pipeline_data,
    m0 = m0, exclude = effective_exclude, m1_params = m1_params
  )
  m1_checkpoint <- if (is.null(checkpoint_dir)) {
    NULL
  } else {
    file.path(checkpoint_dir, "m1")
  }
  m1_tuning <- tune_m1(
    pipeline_data,
    m0 = m0, m1 = m1_initial, loso_seasons = loso_seasons,
    grid = m1_grid, n_cores = n_cores,
    checkpoint_dir = m1_checkpoint, verbose = verbose
  )
  tuned_m1_params <- .m1_params_from_tuning(m1_params, m1_tuning)
  m1 <- build_m1(
    pipeline_data,
    m0 = m0, exclude = effective_exclude, m1_params = tuned_m1_params
  )

  if (is.null(m2_grid)) {
    m2_grid <- plan_m2_grid(
      previous_results,
      max_finalists = max_m2_finalists,
      max_specs = max_m2_specs
    )
  }
  m2_checkpoint <- if (is.null(checkpoint_dir)) {
    NULL
  } else {
    file.path(checkpoint_dir, "m2")
  }
  run_full_m2 <- function(grid, ...) {
    build_m2(
      pipeline_data,
      m0 = m0, m1 = m1, loso_seasons = loso_seasons,
      exclude_seas = effective_exclude,
      holdout_season = if (holdout$released) NULL else prospective_holdout,
      grid = grid, n_cores = n_cores,
      checkpoint_dir = m2_checkpoint, verbose = verbose
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
  selection <- select_m2_candidate(m2_tuning, method = selection_method)
  if (is.null(selection$selected_spec)) {
    stop("Selected M2 specification could not be reconstructed from tuning results.")
  }
  m2_model <- train_m2(
    pipeline_data,
    m0 = m0, m1 = m1, best_spec = selection$selected_spec,
    exclude = effective_exclude, verbose = verbose
  )
  kit <- assemble_kit(
    m0, m1, m2_model,
    best_spec_id = selection$selected_spec_id
  )

  structure(list(
    mode = mode,
    components = list(m0 = m0, m1 = m1, m2 = m2_model),
    tuning = list(m0 = m0$tuning, m1 = m1_tuning, m2 = m2_tuning),
    grid = m2_tuning$grid,
    grid_provenance = m2_tuning$grid$provenance %||% NULL,
    selection = selection,
    racing = racing_result,
    holdout = holdout,
    kit = kit
  ), class = c("page_training_result", "list"))
}
