# Stage lifecycle contracts: season selection, artifact identity/provenance,
# tuning validation gates, and guarded fit/freeze interfaces.
# No new package dependencies; uses digest (already imported).

`%||%` <- function(x, y) if (is.null(x)) y else x

# ============================================================
# Season selection
# ============================================================

#' Validate and normalize a season selection
#'
#' Checks that all requested season identifiers exist in the canonical data,
#' are scalar character values without duplicates, and that the training,
#' exclusion, holdout, and application sets are mutually disjoint. Returns a
#' normalized \code{page_season_selection} object with deterministic
#' (sorted) ordering.
#'
#' @param data A canonical surveillance data frame (must contain a
#'   \code{season} column).
#' @param training_seasons Character vector of seasons used for training.
#'   Must be non-empty.
#' @param exclude_seasons Character vector of seasons permanently excluded.
#' @param holdout_seasons Character vector of holdout evaluation seasons.
#' @param application_seasons Character vector of prospective application
#'   seasons.
#'
#' @return A \code{page_season_selection} list with sorted, validated
#'   season vectors and the full set of data seasons.
#' @export
validate_season_selection <- function(data,
                                      training_seasons,
                                      exclude_seasons = character(0),
                                      holdout_seasons = character(0),
                                      application_seasons = character(0)) {
  if (!is.data.frame(data)) {
    stop("`data` must be a data frame.", call. = FALSE)
  }
  if (!"season" %in% names(data)) {
    stop("`data` must contain a `season` column.", call. = FALSE)
  }

  .check_season_vector <- function(x, name) {
    if (!is.character(x)) {
      stop("`", name, "` must be a character vector.", call. = FALSE)
    }
    x <- trimws(x)
    if (anyNA(x) || any(!nzchar(x))) {
      stop("`", name, "` must contain non-empty, non-NA identifiers.", call. = FALSE)
    }
    if (anyDuplicated(x)) {
      stop("`", name, "` contains duplicate season identifiers.", call. = FALSE)
    }
    x
  }

  training <- .check_season_vector(training_seasons, "training_seasons")
  exclude <- .check_season_vector(exclude_seasons, "exclude_seasons")
  holdout <- .check_season_vector(holdout_seasons, "holdout_seasons")
  application <- .check_season_vector(application_seasons, "application_seasons")

  if (length(training) == 0L) {
    stop("`training_seasons` must be non-empty.", call. = FALSE)
  }

  data_season_values <- trimws(as.character(data$season))
  if (anyNA(data_season_values) || any(!nzchar(data_season_values))) {
    stop("`data$season` must contain valid season identifiers.", call. = FALSE)
  }
  data_seasons <- unique(data_season_values)

  all_requested <- c(training, exclude, holdout, application)
  unknown <- setdiff(all_requested, data_seasons)
  if (length(unknown)) {
    stop(
      "Season(s) not found in data: ",
      paste(unknown, collapse = ", "), ".",
      call. = FALSE
    )
  }

  in_data_order <- function(x) {
    x[order(match(x, data_seasons))]
  }
  training <- in_data_order(training)
  exclude <- in_data_order(exclude)
  holdout <- in_data_order(holdout)
  application <- in_data_order(application)

  sets <- list(
    training = training, exclude = exclude,
    holdout = holdout, application = application
  )
  for (i in seq_along(sets)) {
    for (j in seq_along(sets)) {
      if (j <= i) next
      overlap <- intersect(sets[[i]], sets[[j]])
      if (length(overlap)) {
        stop(
          "Season sets must be disjoint; overlap between `",
          names(sets)[i], "` and `", names(sets)[j], "`: ",
          paste(overlap, collapse = ", "), ".",
          call. = FALSE
        )
      }
    }
  }

  structure(
    list(
      training_seasons = training,
      exclude_seasons = exclude,
      holdout_seasons = holdout,
      application_seasons = application,
      data_seasons = data_seasons
    ),
    class = "page_season_selection"
  )
}

#' Extract the season selection from a stage artifact
#'
#' Generic accessor for the normalized \code{page_season_selection} recorded
#' in a stage result, kit, or replay result.
#'
#' @param x A stage artifact (fit, tuning result, or kit).
#' @param ... Reserved for method extensions.
#'
#' @return A \code{page_season_selection} object.
#' @export
season_selection <- function(x, ...) {
  UseMethod("season_selection")
}

#' @export
season_selection.page_season_selection <- function(x, ...) x

#' @export
season_selection.default <- function(x, ...) {
  selection <- if (is.list(x)) {
    x$selection %||% x$season_selection %||% x$governance$selection
  } else {
    NULL
  }
  if (inherits(selection, "page_season_selection")) {
    return(selection)
  }
  stop("No applicable `season_selection()` method for this object.", call. = FALSE)
}

# ============================================================
# Artifact identity and provenance (internal)
# ============================================================

.stage_artifact_id <- function(stage,
                               selection,
                               config,
                               upstream_ids = NULL,
                               data_id = NULL,
                               payload) {
  payload <- list(
    stage = stage,
    selection = unclass(selection),
    config = config,
    upstream = upstream_ids,
    data_id = data_id,
    fitted_payload = payload
  )
  paste0(stage, "_", digest::digest(payload, algo = "sha256"))
}

.record_stage_provenance <- function(stage,
                                     selection,
                                     config,
                                     upstream_ids = NULL,
                                     data_id = NULL,
                                     payload,
                                     status = "draft") {
  list(
    stage = stage,
    status = status,
    selection = selection,
    config = config,
    upstream_ids = upstream_ids,
    data_id = data_id,
    artifact_id = .stage_artifact_id(
      stage, selection, config, upstream_ids, data_id, payload
    )
  )
}

.kit_governance_id <- function(selection, stage_artifact_ids) {
  digest::digest(
    list(
      selection = unclass(selection),
      stage_artifact_ids = stage_artifact_ids
    ),
    algo = "sha256"
  )
}

.validate_stage_config <- function(config) {
  if (!is.list(config) || !length(config) ||
    is.null(names(config)) || any(!nzchar(names(config)))) {
    stop("`config` must be a non-empty named list.", call. = FALSE)
  }
  invisible(config)
}

.selected_training_data <- function(data, selection) {
  if (!inherits(selection, "page_season_selection")) {
    stop("`selection` must be a `page_season_selection`.", call. = FALSE)
  }
  data <- prepare_surveillance_data(data)
  checked <- validate_season_selection(
    data = data,
    training_seasons = selection$training_seasons,
    exclude_seasons = selection$exclude_seasons,
    holdout_seasons = selection$holdout_seasons,
    application_seasons = selection$application_seasons
  )
  if (!identical(unclass(checked), unclass(selection))) {
    stop("`selection` does not match the supplied data.", call. = FALSE)
  }
  data[
    as.character(data$season) %in% selection$training_seasons, ,
    drop = FALSE
  ]
}

.stage_training_data_id <- function(data) {
  column_order <- sort(names(data))
  row_order <- order(
    as.character(data$season),
    data$weekF,
    seq_len(nrow(data)),
    na.last = TRUE
  )
  digest::digest(
    data[row_order, column_order, drop = FALSE],
    algo = "sha256"
  )
}

.new_stage_fit <- function(stage,
                           selection,
                           config,
                           payload,
                           upstream_ids = NULL,
                           data_id) {
  .validate_stage_config(config)
  if (!is.list(payload)) {
    stop("The fitted stage payload must be a list.", call. = FALSE)
  }
  reserved <- c(
    "stage", "status", "selection", "config", "upstream_ids",
    "data_id", "artifact_id"
  )
  collision <- intersect(names(payload), reserved)
  if (length(collision)) {
    stop(
      "Fitted stage payload uses reserved field(s): ",
      paste(collision, collapse = ", "), ".",
      call. = FALSE
    )
  }
  provenance <- .record_stage_provenance(
    stage = stage,
    selection = selection,
    config = config,
    upstream_ids = upstream_ids,
    data_id = data_id,
    payload = payload
  )
  structure(
    c(payload, provenance),
    class = c(paste0("page_", stage, "_fit"), "list")
  )
}

# ============================================================
# Frozen-stage guard (internal)
# ============================================================

.require_frozen_stage <- function(x, stage) {
  expected_class <- paste0("page_", stage, "_fit")
  if (!inherits(x, expected_class) || !identical(x$stage, stage)) {
    stop("Expected a governed `", expected_class, "` artifact.", call. = FALSE)
  }
  if (is.null(x$status) || !identical(x$status, "frozen")) {
    stop(
      "Stage `", stage, "` artifact must be frozen. ",
      "Got status: ", x$status %||% "absent", ".",
      call. = FALSE
    )
  }
  expected_id <- .stage_artifact_id(
    x$stage, x$selection, x$config, x$upstream_ids, x$data_id,
    .stage_fit_payload(x)
  )
  if (!identical(x$artifact_id, expected_id)) {
    stop(
      "Stage `", stage, "` artifact identity integrity check failed; ",
      "the artifact may have been tampered with.",
      call. = FALSE
    )
  }
  invisible(x)
}

.check_upstream_identity <- function(fit_artifact, upstream, stage_label) {
  expected_id <- upstream$artifact_id
  recorded_id <- fit_artifact$upstream_ids[[stage_label]]
  if (!identical(expected_id, recorded_id)) {
    stop(
      "Upstream ", stage_label, " identity mismatch: artifact records `",
      recorded_id %||% "NULL", "` but received `",
      expected_id %||% "NULL", "`.",
      call. = FALSE
    )
  }
  invisible(NULL)
}

.check_selection_match <- function(sel_a, sel_b, label = "selection") {
  if (!inherits(sel_a, "page_season_selection") ||
    !inherits(sel_b, "page_season_selection") ||
    !identical(unclass(sel_a), unclass(sel_b))) {
    stop(
      "Upstream ", label, " mismatch: governed season selections differ.",
      call. = FALSE
    )
  }
  invisible(NULL)
}

# ============================================================
# M0 lifecycle
# ============================================================

.validate_stage_payload <- function(fit, stage) {
  required <- switch(stage,
    m0 = c("aligned", "seasons_used", "best_params"),
    m1 = c("ref", "hyper", "aligned_train", "m1_params", "seasons_used"),
    m2 = c(
      "fit", "feature_ranges", "m1_train_preds", "spec",
      "training_seasons"
    )
  )
  missing <- required[vapply(required, function(name) is.null(fit[[name]]), logical(1))]
  if (length(missing)) {
    stop(
      "Stage `", stage, "` fitted payload is missing field(s): ",
      paste(missing, collapse = ", "), ".",
      call. = FALSE
    )
  }
  invisible(fit)
}

.stage_fit_payload <- function(fit) {
  reserved <- c(
    "stage", "status", "selection", "config", "upstream_ids",
    "data_id", "artifact_id"
  )
  fit[setdiff(names(fit), reserved)]
}

.selected_tuning_config <- function(tuning, stage) {
  if (identical(stage, "m0")) {
    return(tuning$best_params %||% tuning$tuning$best_params)
  }
  if (identical(stage, "m1")) {
    if (!is.data.frame(tuning$best) || nrow(tuning$best) != 1L) {
      return(NULL)
    }
    return(as.list(tuning$best[1L, , drop = FALSE]))
  }
  tuning$best_spec %||% {
    grid <- tuning$grid
    if (is.data.frame(grid) && "spec_id" %in% names(grid)) {
      row <- grid[grid$spec_id == tuning$best_spec_id, , drop = FALSE]
      if (nrow(row) == 1L) as.list(row[1L, , drop = FALSE]) else NULL
    } else {
      NULL
    }
  }
}

.check_tuning_match <- function(fit, tuning, stage) {
  validator <- get(paste0("validate_", stage, "_tuning"), mode = "function")
  validator(tuning)
  if (is.null(tuning$selection)) {
    stop("Governed tuning is missing its season selection.", call. = FALSE)
  }
  .check_selection_match(fit$selection, tuning$selection, "tuning selection")
  if (!is.null(tuning$data_id) && !identical(fit$data_id, tuning$data_id)) {
    stop("Fit and tuning training-data identities do not match.", call. = FALSE)
  }
  selected <- .selected_tuning_config(tuning, stage)
  if (!is.list(selected) || !length(selected)) {
    stop("Tuning is missing its selected configuration.", call. = FALSE)
  }
  shared <- intersect(names(fit$config), names(selected))
  if (!length(shared) ||
    !isTRUE(all.equal(
      unname(fit$config[shared]), unname(selected[shared]),
      check.attributes = FALSE
    ))) {
    stop("Fit configuration does not match the tuning selection.", call. = FALSE)
  }
  invisible(tuning)
}

.freeze_stage <- function(fit, tuning, stage) {
  expected_class <- paste0("page_", stage, "_fit")
  if (!inherits(fit, expected_class) || !identical(fit$stage, stage)) {
    stop("`fit` must be a `", expected_class, "`.", call. = FALSE)
  }
  if (identical(fit$status, "frozen")) {
    .require_frozen_stage(fit, stage)
    return(fit)
  }
  if (!identical(fit$status, "draft")) {
    stop("Stage fit status must be `draft` before freezing.", call. = FALSE)
  }
  .validate_stage_payload(fit, stage)
  if (!is.null(tuning)) {
    .check_tuning_match(fit, tuning, stage)
  }
  fit$status <- "frozen"
  fit$artifact_id <- .stage_artifact_id(
    stage, fit$selection, fit$config, fit$upstream_ids, fit$data_id,
    .stage_fit_payload(fit)
  )
  fit
}

#' Fit an M0 ignition configuration (draft artifact)
#'
#' Fits the existing fixed M0 implementation using only the selected training
#' seasons and records the fitted payload and its provenance.
#'
#' @param data Canonical surveillance data frame.
#' @param selection A \code{page_season_selection} from
#'   \code{validate_season_selection()}.
#' @param config Named list of M0 detection parameters.
#' @param ... Reserved for future use.
#'
#' @return A \code{page_m0_fit} list in \code{draft} state.
#' @export
fit_m0 <- function(data, selection, config, ...) {
  .validate_stage_config(config)
  training_data <- .selected_training_data(data, selection)
  payload <- build_m0(
    training_data,
    exclude = character(0),
    best_params = config,
    ...
  )
  .new_stage_fit(
    stage = "m0",
    selection = selection,
    config = config,
    payload = payload,
    data_id = .stage_training_data_id(training_data)
  )
}

#' Freeze an M0 draft artifact
#'
#' Promotes a draft M0 fit to immutable frozen status. Governed tuning is
#' boundary-validated before the fit can be frozen.
#'
#' @param fit A \code{page_m0_fit} in draft or frozen state.
#' @param tuning Optional \code{page_m0_tuning} result to validate. Governed
#'   tuning must include its complete grid for boundary validation.
#' @param ... Reserved.
#'
#' @return The \code{page_m0_fit} in \code{frozen} state.
#' @export
freeze_m0 <- function(fit, tuning = NULL, ...) {
  if (inherits(tuning, "page_m0_tuning") && !is.null(tuning$selection)) {
    tuning <- validate_m0_tuning(
      tuning,
      grid = tuning$grid, check_boundaries = TRUE
    )
  }
  .freeze_stage(fit, tuning, "m0")
}

.stage_null_values <- function(stage) {
  stage <- toupper(stage)
  switch(stage,
    M0 = c(p_thr = 0, prev_thr = 0, p_sum_thr = 0),
    M1 = numeric(0),
    M2 = c(
      delta = 0, Kr = 1, k_e = 0, k_r = 0, k_de = 0,
      k_sp = 0, bias_alpha = 0, bias_beta = 0
    ),
    numeric(0)
  )
}

.stage_boundary_report <- function(stage, grid, selected,
                                   null_axes = character(),
                                   null_values = .stage_null_values(stage)) {
  if (!is.data.frame(grid) || !nrow(grid)) {
    stop(
      stage, " boundary validation requires the complete tuning `grid`.",
      call. = FALSE
    )
  }
  # `tune_m0()` may retain a data.table grid.  Normalize before selecting
  # multiple columns; data.table interprets `grid[axis_names]` as a join.
  grid <- as.data.frame(grid)
  axis_names <- intersect(names(grid), names(selected))
  axis_names <- axis_names[vapply(
    grid[axis_names],
    function(values) {
      is.numeric(values) &&
        length(unique(values[is.finite(values)])) >= 2L
    },
    logical(1)
  )]
  boundary_rows <- lapply(axis_names, function(parameter) {
    tested <- sort(unique(grid[[parameter]][is.finite(grid[[parameter]])]))
    chosen <- as.numeric(selected[[parameter]][1L])
    edge <- if (!is.finite(chosen)) {
      "unknown"
    } else if (isTRUE(all.equal(chosen, tested[1L]))) {
      "lower"
    } else if (isTRUE(all.equal(chosen, tested[length(tested)]))) {
      "upper"
    } else {
      "none"
    }
    null_value <- if (parameter %in% names(null_values)) {
      as.numeric(null_values[[parameter]])
    } else {
      NA_real_
    }
    is_null <- edge != "none" &&
      (parameter %in% null_axes || parameter %in% names(null_values)) &&
      is.finite(null_value) &&
      isTRUE(all.equal(chosen, null_value))
    data.frame(
      stage = stage, parameter = parameter,
      tested_min = tested[1L], tested_max = tested[length(tested)],
      selected_value = chosen, boundary = edge,
      decision = if (edge == "none") {
        "stop_bracketed"
      } else if (is_null) {
        "accept_null_drop"
      } else {
        "expand_required"
      },
      reason = if (edge == "none") {
        "selected value is bracketed"
      } else if (is_null) {
        paste0("value ", .stage_number_label(null_value),
               " is the predeclared drop/null")
      } else {
        paste0("selected non-null ", stage, " axis is at a tested edge")
      },
      stringsAsFactors = FALSE
    )
  })
  if (length(boundary_rows)) {
    do.call(rbind, boundary_rows)
  } else {
    data.frame(
      stage = character(0), parameter = character(0),
      tested_min = numeric(0), tested_max = numeric(0),
      selected_value = numeric(0), boundary = character(0),
      decision = character(0), reason = character(0),
      stringsAsFactors = FALSE
    )
  }
}

.stage_number_label <- function(x) {
  format(as.numeric(x), scientific = FALSE, trim = TRUE, digits = 12L)
}

#' Inspect tuning boundaries and optionally warn about unresolved edges
#'
#' Reports every genuinely tuned numeric axis and marks an edge winner as
#' `expand_required`, unless that value is a predeclared null/drop. The report
#' is deliberately separate from the hard freeze gate so users can inspect a
#' result, expand its grid, and resume tuning from the same checkpoint.
#'
#' @param x A stage tuning result, or a data frame containing the tuning grid.
#' @param stage One of `"M0"`, `"M1"`, or `"M2"`.
#' @param grid Optional complete grid. When omitted, uses `x$grid`.
#' @param warn Logical; emit a warning when a non-null edge requires expansion.
#' @param null_axes Optional names of axes whose zero value is an accepted
#'   drop/null. Stage defaults are used when omitted.
#'
#' @return A data frame with tested range, selected value, boundary, decision,
#'   and reason for every varying numeric axis.
#' @export
inspect_tuning_boundaries <- function(x,
                                      stage = c("M0", "M1", "M2"),
                                      grid = NULL,
                                      warn = TRUE,
                                      null_axes = NULL) {
  stage <- toupper(match.arg(stage))
  if (is.data.frame(x) && is.null(grid)) grid <- x
  if (is.null(grid)) grid <- x$grid
  selected <- switch(stage,
    M0 = x$best_params %||% x$tuning$best_params,
    M1 = x$best %||% x$best_params,
    M2 = x$best_spec %||% x$best
  )
  if (is.null(selected)) {
    stop(stage, " tuning is missing its selected configuration.", call. = FALSE)
  }
  if (is.data.frame(selected)) selected <- selected[1L, , drop = FALSE]
  if (is.null(null_axes)) null_axes <- character(0)
  report <- .stage_boundary_report(
    stage, grid, selected, null_axes = null_axes,
    null_values = .stage_null_values(stage)
  )
  unresolved <- report[report$decision == "expand_required", , drop = FALSE]
  if (isTRUE(warn) && nrow(unresolved)) {
    message <- paste0(
      stage, " tuning winner is on an unresolved non-null boundary (",
      paste(unresolved$parameter, collapse = ", "),
      "). Call expand_tuning_grid() and rerun the stage with the same ",
      "checkpoint_dir to score only the added specifications."
    )
    condition <- structure(
      simpleWarning(message),
      class = c("page_boundary_warning", "warning", "condition")
    )
    warning(condition)
  }
  class(report) <- c("page_boundary_report", class(report))
  report
}

.selected_stage_config <- function(x, stage, grid) {
  selected <- switch(stage,
    M0 = x$best_params %||% x$tuning$best_params,
    M1 = x$best %||% x$best_params,
    M2 = x$best_spec %||% x$best
  )
  if (is.data.frame(selected)) selected <- selected[1L, , drop = FALSE]
  selected <- as.list(selected)
  out <- as.list(grid[1L, , drop = FALSE])
  for (nm in intersect(names(selected), names(out))) out[[nm]] <- selected[[nm]][1L]
  as.data.frame(out, stringsAsFactors = FALSE)
}

.grid_adjacent_step <- function(values, edge, supplied = NULL) {
  values <- sort(unique(as.numeric(values)))
  if (!is.null(supplied)) return(as.numeric(supplied))
  if (length(values) < 2L) return(1)
  if (edge == "lower") values[2L] - values[1L] else
    values[length(values)] - values[length(values) - 1L]
}

.valid_stage_expansion_value <- function(stage, parameter, value) {
  if (!is.finite(value)) return(FALSE)
  if (stage == "M0") {
    if (parameter == "cls_thr") return(value >= 0 && value <= 1)
    if (parameter %in% c("p_thr", "prev_thr", "p_sum_thr", "eps")) return(value >= 0)
    if (parameter %in% c("n_consec", "L", "K_sum", "N_req", "w_min", "w_max")) return(value >= 1)
    return(TRUE)
  }
  if (stage == "M1") {
    if (parameter %in% c("k_ref", "slope_window")) return(value >= 2)
    if (parameter %in% c("multi_temperature", "align_rise_weight", "slope_weight")) return(value >= 0)
  }
  TRUE
}

.m0_grid_spec_ids <- function(grid) {
  grid <- as.data.frame(grid)
  vapply(seq_len(nrow(grid)), function(i) {
    paste0("m0_", digest::digest(as.list(grid[i, , drop = FALSE]), algo = "xxhash64"))
  }, character(1))
}

#' Expand a tuning grid at every unresolved winner boundary
#'
#' This is the user-facing companion to `inspect_tuning_boundaries()`. It
#' appends one valid adjacent value per unresolved axis and preserves every
#' existing row and specification identity. Pass the returned grid to the
#' same `tune_*()` function with its existing `checkpoint_dir`; M1 and M2
#' checkpoints reuse completed specifications, while M0 reuses cached grid
#' scores when the prior tuning object is supplied as `previous_results`.
#'
#' @param x A tuning result or a grid data frame.
#' @param stage One of `"M0"`, `"M1"`, or `"M2"`.
#' @param grid Optional grid override.
#' @param steps Optional named numeric vector overriding adjacent spacing.
#' @param max_specs Optional cap on returned rows.
#'
#' @return The original grid with new boundary rows appended. New rows carry
#'   `provenance = "boundary:<parameter>"` when that column is available.
#' @export
expand_tuning_grid <- function(x,
                               stage = c("M0", "M1", "M2"),
                               grid = NULL,
                               steps = NULL,
                               max_specs = NULL) {
  stage <- toupper(match.arg(stage))
  if (is.null(grid)) grid <- x$grid %||% x
  grid <- as.data.frame(grid, stringsAsFactors = FALSE)
  if (!nrow(grid)) stop("Cannot expand an empty tuning grid.", call. = FALSE)

  if (stage == "M2") {
    planned <- plan_m2_grid(
      previous_results = if (is.list(x)) x else NULL,
      max_specs = max_specs %||% max(64L, nrow(grid) + 32L)
    )
    # The adaptive planner intentionally caps its own plan; expansion must
    # never discard already scored rows.
    planned <- planned[setdiff(names(planned), "provenance")]
    all_names <- union(names(grid), names(planned))
    for (nm in setdiff(all_names, names(grid))) grid[[nm]] <- NA
    for (nm in setdiff(all_names, names(planned))) planned[[nm]] <- NA
    grid <- rbind(grid[all_names], planned[all_names])
  } else {
    report <- inspect_tuning_boundaries(x, stage = stage, grid = grid, warn = FALSE)
    unresolved <- report[report$decision == "expand_required", , drop = FALSE]
    if (nrow(unresolved)) {
      selected <- .selected_stage_config(x, stage, grid)
      new_rows <- lapply(seq_len(nrow(unresolved)), function(i) {
        row <- selected
        parameter <- unresolved$parameter[i]
        step <- .grid_adjacent_step(
          grid[[parameter]], unresolved$boundary[i],
          if (!is.null(steps)) steps[[parameter]] else NULL
        )
        value <- unresolved$selected_value[i] +
          if (unresolved$boundary[i] == "lower") -step else step
        if (!.valid_stage_expansion_value(stage, parameter, value)) {
          stop(
            "Expansion for ", stage, " axis `", parameter,
            "` would leave its supported domain (value ",
            .stage_number_label(value), "). Supply an explicit valid `steps` value.",
            call. = FALSE
          )
        }
        row[[parameter]] <- value
        if ("spec_id" %in% names(row)) row$spec_id <- NA_character_
        row
      })
      grid <- rbind(grid, do.call(rbind, new_rows))
    }
  }

  if (stage == "M2") {
    grid <- .validate_m2_grid(grid)
    grid <- .deduplicate_m2_grid(grid)
  } else {
    grid <- unique(grid)
    if (stage == "M0") {
      if (!"spec_id" %in% names(grid)) {
        grid$spec_id <- .m0_grid_spec_ids(grid)
      } else {
        missing_ids <- is.na(grid$spec_id) | !nzchar(grid$spec_id)
        if (any(missing_ids)) {
          grid$spec_id[missing_ids] <- .m0_grid_spec_ids(
            grid[missing_ids, setdiff(names(grid), "spec_id"), drop = FALSE]
          )
        }
      }
    } else if (!"spec_id" %in% names(grid)) {
      grid$spec_id <- sprintf("s%03d", seq_len(nrow(grid)))
    } else {
      missing_ids <- is.na(grid$spec_id) | !nzchar(grid$spec_id)
      if (any(missing_ids)) {
        used <- as.character(grid$spec_id[!missing_ids])
        proposed <- character(sum(missing_ids))
        counter <- nrow(grid)
        for (j in seq_along(proposed)) {
          repeat {
            counter <- counter + 1L
            candidate <- sprintf("s%03d", counter)
            if (!candidate %in% used && !candidate %in% proposed[seq_len(j - 1L)]) break
          }
          proposed[j] <- candidate
        }
        grid$spec_id[missing_ids] <- proposed
      }
      if (anyDuplicated(grid$spec_id)) {
        stop("Expanded grid has duplicate spec_id values.", call. = FALSE)
      }
    }
  }
  if (!is.null(max_specs)) grid <- utils::head(grid, as.integer(max_specs))
  grid
}

.enforce_stage_boundaries <- function(stage, report) {
  unresolved <- report[report$decision == "expand_required", , drop = FALSE]
  if (nrow(unresolved)) {
    stop(
      stage, " tuning has unresolved non-null boundary: ",
      paste(unresolved$parameter, collapse = ", "),
      ". Expand the ", stage,
      " grid before freezing or starting the downstream stage.",
      call. = FALSE
    )
  }
  invisible(report)
}

#' Validate an M0 tuning result
#'
#' Rejects zero evaluable folds, non-finite selection metrics, missing
#' selected configuration, or mismatched folds.
#' Governed workflows can also require every genuinely tuned M0 axis to be
#' bracketed or explicitly accepted as a null/drop choice.
#'
#' @param x A \code{page_m0_tuning} object.
#' @param grid Complete M0 grid used for tuning when boundary checks are
#'   enabled.
#' @param check_boundaries Logical; require all varying numeric M0 axes to be
#'   bracketed, except predeclared null/drop values.
#' @param ... Reserved.
#'
#' @return \code{x}, invisibly, if valid.
#' @export
validate_m0_tuning <- function(x, grid = NULL, check_boundaries = FALSE, ...) {
  if (!inherits(x, "page_m0_tuning")) {
    stop("`x` must be a `page_m0_tuning` object.", call. = FALSE)
  }
  folds <- x$folds %||% x$tuning$folds %||% list()
  if (length(folds) == 0L) {
    stop("M0 tuning has zero evaluable folds.", call. = FALSE)
  }
  best_params <- x$best_params %||% x$tuning$best_params
  if (is.null(best_params) || !is.list(best_params) || !length(best_params)) {
    stop("M0 tuning is missing `best_params` (selected configuration).", call. = FALSE)
  }
  results <- x$results
  if (is.data.frame(results) && nrow(results) > 0L && "score" %in% names(results)) {
    best_score <- results$score[1L]
    if (!is.finite(best_score)) {
      stop("M0 tuning selected metric is non-finite.", call. = FALSE)
    }
  }
  summary <- x$summary %||% x$tuning$summary
  if (is.list(summary) && !is.null(summary$mean_abs) &&
    !is.finite(summary$mean_abs)) {
    stop("M0 tuning selected metric is non-finite.", call. = FALSE)
  }
  if (!is.null(x$selection)) {
    fold_seasons <- names(folds)
    if (is.null(fold_seasons) ||
      !setequal(fold_seasons, x$selection$training_seasons)) {
      stop("M0 tuning fold/selection mismatch.", call. = FALSE)
    }
  }
  if (isTRUE(check_boundaries)) {
    report <- inspect_tuning_boundaries(
      x, stage = "M0", grid = grid, warn = TRUE,
      null_axes = c("p_thr", "prev_thr", "p_sum_thr")
    )
    x$boundary_report <- report
    .enforce_stage_boundaries("M0", report)
  }
  invisible(x)
}

# ============================================================
# M1 lifecycle
# ============================================================

#' Fit an M1 alignment configuration (draft artifact)
#'
#' Constructs a draft M1 stage artifact. Requires a frozen M0 with matching
#' training selection.
#'
#' @param data Canonical surveillance data frame.
#' @param selection A \code{page_season_selection}.
#' @param m0 A frozen \code{page_m0_fit}.
#' @param config Named list of M1 alignment parameters.
#' @param ... Reserved.
#'
#' @return A \code{page_m1_fit} list in \code{draft} state.
#' @export
fit_m1 <- function(data, selection, m0, config, ...) {
  .require_frozen_stage(m0, "m0")
  .check_selection_match(selection, m0$selection)
  .validate_stage_config(config)
  training_data <- .selected_training_data(data, selection)
  payload <- build_m1(
    training_data,
    m0 = m0,
    exclude = character(0),
    exclude_live = FALSE,
    m1_params = config,
    ...
  )
  upstream_ids <- list(m0 = m0$artifact_id)
  .new_stage_fit(
    stage = "m1",
    selection = selection,
    config = config,
    payload = payload,
    upstream_ids = upstream_ids,
    data_id = .stage_training_data_id(training_data)
  )
}

#' Freeze an M1 draft artifact
#'
#' @param fit A \code{page_m1_fit}.
#' @param tuning Optional \code{page_m1_tuning} to validate. Governed tuning
#'   is boundary-validated before freezing.
#' @param ... Reserved.
#'
#' @return The \code{page_m1_fit} in \code{frozen} state.
#' @export
freeze_m1 <- function(fit, tuning = NULL, ...) {
  if (inherits(tuning, "page_m1_tuning") && !is.null(tuning$selection)) {
    tuning <- validate_m1_tuning(tuning, check_boundaries = TRUE)
  }
  .freeze_stage(fit, tuning, "m1")
}

#' Validate an M1 tuning result
#'
#' Rejects zero evaluable seasons, all-missing metrics, non-finite selected
#' metric, missing selected configuration, or fold/selection mismatches.
#' Governed workflows can also require every genuinely tuned M1 axis to be
#' bracketed before the fit is frozen and passed downstream.
#'
#' @param x A \code{page_m1_tuning} object.
#' @param check_boundaries Logical; require all varying numeric M1 axes in the
#'   supplied grid to have an interior selected value. This is enabled by
#'   \code{train_pipeline()} before M1 is frozen for M2.
#' @param ... Reserved.
#'
#' @return \code{x}, invisibly, if valid.
#' @export
validate_m1_tuning <- function(x, check_boundaries = FALSE, ...) {
  if (!inherits(x, "page_m1_tuning")) {
    stop("`x` must be a `page_m1_tuning` object.", call. = FALSE)
  }
  scores <- x$scores
  if (!is.data.frame(scores) || nrow(scores) == 0L) {
    stop("M1 tuning has zero evaluable seasons.", call. = FALSE)
  }
  best <- x$best
  if (!is.data.frame(best) || nrow(best) == 0L) {
    stop("M1 tuning is missing `best` (selected configuration).", call. = FALSE)
  }
  metric_col <- intersect(
    c("mae_weibull", "mae_exp", "mae_uniform", "bernoulli_nll"),
    names(scores)
  )
  if (!length(metric_col)) {
    stop("M1 tuning is missing a recognized selection metric.", call. = FALSE)
  }
  vals <- scores[[metric_col[1L]]]
  if (all(is.na(vals))) {
    stop("M1 tuning metrics are all NA (missing).", call. = FALSE)
  }
  best_vals <- best[[metric_col[1L]]]
  if (length(best_vals) != 1L || !is.finite(best_vals)) {
    stop("M1 tuning selected metric is non-finite.", call. = FALSE)
  }
  if (!is.null(x$selection) && "n_seasons" %in% names(scores)) {
    n_train <- length(x$selection$training_seasons)
    if (any(is.na(scores$n_seasons)) ||
      any(scores$n_seasons != n_train)) {
      stop(
        "M1 tuning fold/selection mismatch: every candidate must evaluate ",
        "the selected training seasons.",
        call. = FALSE
      )
    }
  }
  if (isTRUE(check_boundaries)) {
    report <- inspect_tuning_boundaries(x, stage = "M1", warn = TRUE)
    x$boundary_report <- report
    .enforce_stage_boundaries("M1", report)
  }
  invisible(x)
}

# ============================================================
# M2 lifecycle
# ============================================================

#' Tune M2 with an explicit governed season selection
#'
#' Runs the existing M2 LOSO implementation using only the selected training
#' seasons and records the selection and training-data identity on the result.
#'
#' @param data Canonical surveillance data frame.
#' @param selection A \code{page_season_selection}.
#' @param m0 A frozen \code{page_m0_fit}.
#' @param m1 A frozen \code{page_m1_fit}.
#' @param grid M2 candidate grid.
#' @param ... Additional arguments passed to \code{build_m2()}.
#'
#' @return A governed \code{page_m2_tuning} result.
#' @export
tune_m2 <- function(data, selection, m0, m1, grid, ...) {
  .require_frozen_stage(m0, "m0")
  .require_frozen_stage(m1, "m1")
  .check_selection_match(selection, m0$selection)
  .check_selection_match(selection, m1$selection)
  .check_upstream_identity(m1, m0, "m0")
  training_data <- .selected_training_data(data, selection)
  out <- build_m2(
    training_data,
    m0 = m0,
    m1 = m1,
    loso_seasons = selection$training_seasons,
    exclude_seas = character(0),
    holdout_season = NULL,
    grid = grid,
    ...
  )
  out$selection <- selection
  out$data_id <- .stage_training_data_id(training_data)
  class(out) <- c("page_m2_tuning", "list")
  out
}

#' Fit an M2 forecast configuration (draft artifact)
#'
#' Constructs a draft M2 stage artifact. Requires frozen M0 and M1 with
#' matching identities and selection.
#'
#' @param data Canonical surveillance data frame.
#' @param selection A \code{page_season_selection}.
#' @param m0 A frozen \code{page_m0_fit}.
#' @param m1 A frozen \code{page_m1_fit}.
#' @param config Named list of M2 specification parameters.
#' @param ... Reserved.
#'
#' @return A \code{page_m2_fit} list in \code{draft} state.
#' @export
fit_m2 <- function(data, selection, m0, m1, config, ...) {
  .require_frozen_stage(m0, "m0")
  .require_frozen_stage(m1, "m1")
  .check_selection_match(selection, m0$selection)
  .check_selection_match(selection, m1$selection)
  .check_upstream_identity(m1, m0, "m0")
  .validate_stage_config(config)
  training_data <- .selected_training_data(data, selection)
  payload <- train_m2(
    training_data,
    m0 = m0,
    m1 = m1,
    best_spec = config,
    exclude = character(0),
    ...
  )
  upstream_ids <- list(m0 = m0$artifact_id, m1 = m1$artifact_id)
  .new_stage_fit(
    stage = "m2",
    selection = selection,
    config = config,
    payload = payload,
    upstream_ids = upstream_ids,
    data_id = .stage_training_data_id(training_data)
  )
}

#' Freeze an M2 draft artifact
#'
#' @param fit A \code{page_m2_fit}.
#' @param tuning Optional \code{page_m2_tuning} to validate.
#' @param ... Reserved.
#'
#' @return The \code{page_m2_fit} in \code{frozen} state.
#' @export
freeze_m2 <- function(fit, tuning = NULL, ...) {
  if (inherits(tuning, "page_m2_tuning") && !is.null(tuning$selection)) {
    tuning <- validate_m2_tuning(tuning, check_boundaries = TRUE)
  }
  .freeze_stage(fit, tuning, "m2")
}

#' Validate an M2 tuning result
#'
#' Rejects invalid grid identity, incomplete folds, non-finite selected
#' metric, or absent selected specification.
#'
#' @param x A \code{page_m2_tuning} object.
#' @param check_boundaries Logical; require every genuinely tuned M2 axis to
#'   be bracketed or an explicitly accepted null/drop.
#' @param ... Reserved.
#'
#' @return \code{x}, invisibly, if valid.
#' @export
validate_m2_tuning <- function(x, check_boundaries = FALSE, ...) {
  if (!inherits(x, "page_m2_tuning")) {
    stop("`x` must be a `page_m2_tuning` object.", call. = FALSE)
  }
  grid <- x$grid
  if (!is.data.frame(grid) || nrow(grid) == 0L) {
    stop("M2 tuning has an invalid or empty grid.", call. = FALSE)
  }
  if (!"spec_id" %in% names(grid) || anyNA(grid$spec_id) ||
    anyDuplicated(grid$spec_id)) {
    stop("M2 tuning grid has invalid or duplicate specification identities.", call. = FALSE)
  }
  best_id <- x$best_spec_id
  if (is.null(best_id) || !is.character(best_id) || !nzchar(best_id)) {
    stop("M2 tuning is missing `best_spec_id` (selected specification).", call. = FALSE)
  }
  if (!best_id %in% grid$spec_id) {
    stop("M2 tuning selected specification is absent from the grid.", call. = FALSE)
  }
  summary_df <- x$summary
  if (!is.data.frame(summary_df) || !nrow(summary_df) ||
    !all(c("spec_id", "bernoulli_nll") %in% names(summary_df))) {
    stop("M2 tuning is missing its scored summary.", call. = FALSE)
  }
  best_row <- summary_df[summary_df$spec_id == best_id, , drop = FALSE]
  if (nrow(best_row) != 1L || !is.finite(best_row$bernoulli_nll[1L])) {
    stop("M2 tuning selected metric is non-finite or missing.", call. = FALSE)
  }
  if (!is.null(x$selection) && "n_seasons" %in% names(summary_df)) {
    expected <- length(x$selection$training_seasons)
    if (any(is.na(summary_df$n_seasons)) ||
      any(summary_df$n_seasons != expected)) {
      stop("M2 tuning fold/selection mismatch.", call. = FALSE)
    }
    scores <- x$scores
    required_score_fields <- c("spec_id", "season", "bernoulli_nll")
    if (!is.data.frame(scores) ||
      !all(required_score_fields %in% names(scores))) {
      stop("M2 tuning is missing governed fold-level scores.", call. = FALSE)
    }
    expected_pairs <- expand.grid(
      spec_id = grid$spec_id,
      season = x$selection$training_seasons,
      stringsAsFactors = FALSE
    )
    observed_pairs <- unique(data.frame(
      spec_id = as.character(scores$spec_id),
      season = as.character(scores$season),
      stringsAsFactors = FALSE
    ))
    pair_key <- function(data) paste(data$spec_id, data$season, sep = "\r")
    if (!setequal(pair_key(expected_pairs), pair_key(observed_pairs)) ||
      any(!is.finite(scores$bernoulli_nll))) {
      stop("M2 tuning has incomplete or non-finite governed folds.", call. = FALSE)
    }
  }
  if (isTRUE(check_boundaries)) {
    report <- inspect_tuning_boundaries(x, stage = "M2", warn = TRUE)
    x$boundary_report <- report
    .enforce_stage_boundaries("M2", report)
  }
  invisible(x)
}
