# Read-only planning for governed PAGe training.

#' Plan a governed PAGe training run without fitting or launching workers
#'
#' Normalizes the season sets, grids, M1 caps, support checks, and resource
#' settings that a subsequent \code{train_pipeline()} call would use. This is
#' a dry run: it does not fit models, create checkpoints, or write artifacts.
#'
#' @param allD Multi-season surveillance data.
#' @param mode One of \code{"refresh"} or \code{"retune"}.
#' @param previous_results Optional prior M2 tuning result used to plan its grid.
#' @param exclude Seasons excluded from training and fitting.
#' @param prospective_holdout Season held out until promotion evidence releases it.
#' @param promotion Optional verified promotion evidence.
#' @param loso_seasons LOSO fold selector: \code{"all"}, \code{"alternating"},
#'   or an explicit character vector.
#' @param n_cores Requested worker count.
#' @param checkpoint_dir Optional parent checkpoint directory; it is reported but
#'   not created.
#' @param m0_grid,m1_grid Optional explicit M0/M1 grids.
#' @param m2_grid Optional explicit M2 grid; otherwise \code{plan_m2_grid()} is
#'   used.
#' @param max_m2_finalists,max_m2_specs Bounds for an automatically planned M2 grid.
#' @param m1_hard_caps M1 hard-cap policy.
#'
#' @return A \code{page_training_plan} containing season selection, grids,
#'   support audit, cap policy, and resource estimates.
#' @export
plan_training <- function(
  allD,
  mode = c("refresh", "retune"),
  previous_results = NULL,
  exclude = c("2011-12", "2015-16", "2020-21", "2021-22"),
  prospective_holdout = "2025-26",
  promotion = NULL,
  loso_seasons = "all",
  n_cores = parallel::detectCores() - 1L,
  checkpoint_dir = NULL,
  m0_grid = .default_m0_grid(),
  m1_grid = default_m1_grid(),
  m2_grid = NULL,
  max_m2_finalists = 6L,
  max_m2_specs = 64L,
  m1_hard_caps = default_m1_hard_caps()
) {
  mode <- match.arg(mode)
  n_cores <- as.integer(max(1L, n_cores))
  allD <- prepare_surveillance_data(allD)
  if (!nrow(allD)) {
    stop("`allD` must contain at least one surveillance row.", call. = FALSE)
  }
  m1_hard_caps <- .normalize_m1_hard_caps(m1_hard_caps)
  holdout <- .resolve_holdout_release(allD, prospective_holdout, promotion)
  if (mode == "retune" && holdout$released) {
    stop(
      "Post-acceptance retuning is not permitted; use `mode = \"refresh\"`.",
      call. = FALSE
    )
  }

  data_seasons <- unique(as.character(allD$season))
  held_out <- holdout$present && !holdout$released
  holdout_seasons <- if (held_out) prospective_holdout else character(0)
  exclude_seasons <- intersect(exclude, data_seasons)
  eligible_seasons <- setdiff(data_seasons, c(exclude_seasons, holdout_seasons))

  if (mode == "refresh") {
    if (holdout$released) {
      locked <- promotion$candidate_config
      training_seasons <- unique(c(
        as.character(locked$training_seasons), prospective_holdout
      ))
      training_seasons <- intersect(training_seasons, data_seasons)
    } else {
      training_seasons <- eligible_seasons
    }
    application_seasons <- character(0)
  } else {
    training_seasons <- if (identical(loso_seasons, "all")) {
      eligible_seasons
    } else if (identical(loso_seasons, "alternating")) {
      eligible_seasons[c(TRUE, FALSE)]
    } else if (is.character(loso_seasons)) {
      intersect(loso_seasons, eligible_seasons)
    } else {
      stop("`loso_seasons` must be 'all', 'alternating', or a character vector.",
        call. = FALSE
      )
    }
    application_seasons <- setdiff(eligible_seasons, training_seasons)
  }
  if (!length(training_seasons)) {
    stop("The plan has no trainable seasons after exclusions and holdout handling.",
      call. = FALSE
    )
  }
  selection <- validate_season_selection(
    allD,
    training_seasons = training_seasons,
    exclude_seasons = exclude_seasons,
    holdout_seasons = holdout_seasons,
    application_seasons = application_seasons
  )

  if (is.null(m2_grid)) {
    m2_grid <- plan_m2_grid(
      previous_results,
      max_finalists = max_m2_finalists,
      max_specs = max_m2_specs
    )
  }
  if (!is.data.frame(m0_grid) || !nrow(m0_grid)) {
    stop("`m0_grid` must be a non-empty data frame.", call. = FALSE)
  }
  if (!is.data.frame(m1_grid) || !nrow(m1_grid)) {
    stop("`m1_grid` must be a non-empty data frame.", call. = FALSE)
  }
  if (!is.data.frame(m2_grid) || !nrow(m2_grid)) {
    stop("`m2_grid` must be a non-empty data frame.", call. = FALSE)
  }

  support <- preflight_support_audit(
    allD,
    m0_grid = m0_grid,
    m1_grid = m1_grid,
    m2_grid = m2_grid,
    n_weeks = 52L,
    selection = selection
  )
  structure(
    list(
      mode = mode,
      selection = selection,
      holdout = holdout,
      grids = list(m0 = m0_grid, m1 = m1_grid, m2 = m2_grid),
      grid_sizes = c(
        M0 = nrow(m0_grid), M1 = nrow(m1_grid), M2 = nrow(m2_grid)
      ),
      m1_hard_caps = m1_hard_caps,
      resources = list(
        n_cores = n_cores,
        checkpoint_dir = checkpoint_dir,
        estimated_specs = nrow(m0_grid) + nrow(m1_grid) + nrow(m2_grid)
      ),
      support = support,
      next_steps = c(
        "Review support$M0 and support$M1 before tuning.",
        "Complete the M1 handoff, then rerun preflight_support_audit() with m2_data before M2 workers.",
        "Use the same checkpoint_dir when expanding a governed boundary."
      )
    ),
    class = "page_training_plan"
  )
}

#' @export
print.page_training_plan <- function(x, ...) {
  cat("PAGe Training Plan (read-only)\n")
  cat("Mode: ", x$mode, "\n", sep = "")
  cat("Training seasons: ", length(x$selection$training_seasons), "\n", sep = "")
  cat("Holdout: ", paste(x$selection$holdout_seasons, collapse = ", "), "\n", sep = "")
  cat("Grid sizes: ", paste(names(x$grid_sizes), x$grid_sizes, collapse = ", "), "\n", sep = "")
  cat("Workers: ", x$resources$n_cores, "\n", sep = "")
  invisible(x)
}
