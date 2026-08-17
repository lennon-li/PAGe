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
    M1 = c(slope_weight = 0),
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
        paste0(
          "value ", .stage_number_label(null_value),
          " is the predeclared drop/null"
        )
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
#' @param hard_caps Optional named numeric vector or named list of lower/upper
#'   hard caps. An edge exactly at a declared cap is reported as
#'   `stop_hard_cap` rather than `expand_required`.
#' @param min_nll_gain M2-only NLL improvement threshold. Defaults to
#'   \code{default_m2_nll_gain_caps()}; supply a named numeric vector for
#'   parameter-specific thresholds, or one unnamed number to apply the same
#'   threshold to every M2 axis. Omitted names use the governed defaults. When
#'   a selected edge has a matched adjacent NLL comparison and its outward
#'   gain is less than or equal to the threshold, it is reported as
#'   `stop_small_gain`.
#'
#' @return A data frame with tested range, selected value, boundary, decision,
#'   and reason for every varying numeric axis.
#' @export
inspect_tuning_boundaries <- function(x,
                                      stage = c("M0", "M1", "M2"),
                                      grid = NULL,
                                      warn = TRUE,
                                      null_axes = NULL,
                                      hard_caps = NULL,
                                      min_nll_gain = NULL) {
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
    stage, grid, selected,
    null_axes = null_axes,
    null_values = .stage_null_values(stage)
  )
  if (!is.null(hard_caps) && nrow(report)) {
    cap_names <- names(hard_caps)
    for (parameter in intersect(cap_names, report$parameter)) {
      cap <- hard_caps[[parameter]]
      if (is.list(hard_caps)) {
        cap <- suppressWarnings(as.numeric(cap))
        names(cap) <- names(hard_caps[[parameter]])
        upper <- cap[["upper"]]
        lower <- cap[["lower"]]
      } else {
        upper <- suppressWarnings(as.numeric(cap))
        lower <- NA_real_
      }
      hit_upper <- is.finite(upper) & report$boundary == "upper" &
        report$selected_value == upper & report$tested_max == upper
      hit_lower <- is.finite(lower) & report$boundary == "lower" &
        report$selected_value == lower & report$tested_min == lower
      hit <- hit_upper | hit_lower
      if (any(hit)) {
        report$decision[hit] <- "stop_hard_cap"
        report$reason[hit] <- paste0(
          "selected value is the declared hard cap (",
          ifelse(hit_upper[hit], upper, lower), ")"
        )
      }
    }
  }
  if (stage == "M2" && is.null(min_nll_gain)) {
    min_nll_gain <- x$min_nll_gain %||% default_m2_nll_gain_caps()
  }
  if (stage == "M2" && !is.null(min_nll_gain) && nrow(report)) {
    gain_thresholds <- .normalize_m2_nll_gain(min_nll_gain, report$parameter)
    report$min_nll_gain <- unname(gain_thresholds[report$parameter])
    report$nll_gain <- NA_real_
    for (i in which(report$decision == "expand_required")) {
      threshold <- report$min_nll_gain[i]
      if (!is.finite(threshold)) next
      evidence <- .m2_boundary_nll_gain(
        x,
        parameter = report$parameter[i],
        boundary = report$boundary[i]
      )
      report$nll_gain[i] <- evidence
      if (is.finite(evidence) && evidence <= threshold) {
        report$decision[i] <- "stop_small_gain"
        report$reason[i] <- paste0(
          "matched outward NLL gain ", format(evidence, digits = 6),
          " is <= min_nll_gain ", format(threshold, digits = 6)
        )
      } else if (!is.finite(evidence)) {
        report$reason[i] <- paste0(
          report$reason[i], "; no matched adjacent NLL comparison"
        )
      }
    }
  }
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

.normalize_m2_nll_gain <- function(min_nll_gain, parameters) {
  if (!is.numeric(min_nll_gain) || !length(min_nll_gain) ||
    anyNA(min_nll_gain) || any(!is.finite(min_nll_gain)) ||
    any(min_nll_gain < 0)) {
    stop(
      "`min_nll_gain` must contain finite non-negative numeric values.",
      call. = FALSE
    )
  }
  supplied_names <- names(min_nll_gain)
  if (is.null(supplied_names) || !length(supplied_names)) {
    if (length(min_nll_gain) != 1L) {
      stop(
        "An unnamed `min_nll_gain` must be one scalar; use names for ",
        "parameter-specific thresholds.",
        call. = FALSE
      )
    }
    return(stats::setNames(rep(min_nll_gain, length(parameters)), parameters))
  }
  if (anyNA(supplied_names) || any(!nzchar(supplied_names)) ||
    anyDuplicated(supplied_names)) {
    stop("`min_nll_gain` names must be unique and non-empty.", call. = FALSE)
  }
  known_parameters <- unique(c(
    parameters,
    if (exists(".m2_parameter_names", mode = "function")) {
      .m2_parameter_names()
    } else {
      character(0)
    }
  ))
  unknown <- setdiff(supplied_names, known_parameters)
  if (length(unknown)) {
    stop(
      "`min_nll_gain` contains unknown M2 parameter(s): ",
      paste(unknown, collapse = ", "),
      call. = FALSE
    )
  }
  defaults <- if (exists("default_m2_nll_gain_caps", mode = "function")) {
    default_m2_nll_gain_caps()
  } else {
    stats::setNames(rep(0, length(known_parameters)), known_parameters)
  }
  out <- defaults[parameters]
  matched_names <- intersect(supplied_names, parameters)
  out[matched_names] <- as.numeric(min_nll_gain[matched_names])
  out
}

.m2_boundary_nll_gain <- function(x, parameter, boundary) {
  if (is.null(x$best_spec_id) || !is.character(x$best_spec_id) ||
    length(x$best_spec_id) != 1L) {
    return(NA_real_)
  }
  sensitivity <- tryCatch(
    extract_nll_sensitivity(
      x,
      metric = "bernoulli_nll", parameters = .m2_parameter_names()
    ),
    error = function(e) NULL
  )
  matched <- sensitivity$matched_gains %||% NULL
  if (!is.data.frame(matched) || !nrow(matched)) {
    return(NA_real_)
  }
  selected_id <- as.character(x$best_spec_id)
  if (boundary == "upper") {
    rows <- matched[matched$to_spec_id == selected_id, , drop = FALSE]
    if (!nrow(rows)) {
      return(NA_real_)
    }
    return(as.numeric(rows$adjacent_gain[1L]))
  }
  if (boundary == "lower") {
    rows <- matched[matched$from_spec_id == selected_id, , drop = FALSE]
    if (!nrow(rows)) {
      return(NA_real_)
    }
    return(as.numeric(-rows$adjacent_gain[1L]))
  }
  NA_real_
}

#' Select an M1 candidate with a practical-gain backoff rule
#'
#' When a more flexible `k_ref` is only marginally better, select the smallest
#' tested `k_ref` within `min_gain` weeks of the best M1 score. This keeps an
#' upper-cap winner from being accepted solely because it is more flexible.
#'
#' @param x A `page_m1_tuning` object.
#' @param min_gain Numeric minimum M1 Weibull-MAE improvement, in weeks, needed
#'   to justify the more complex candidate. Defaults to 0.05.
#' @param prefer_simpler Logical; choose the smallest eligible `k_ref`.
#'
#' @return A list containing `selected`, `selected_spec_id`, the best and
#'   selected scores, and the backoff gain.
#' @export
select_m1_candidate <- function(x, min_gain = 0.05, prefer_simpler = TRUE) {
  if (!inherits(x, "page_m1_tuning")) {
    stop("`x` must be a `page_m1_tuning` object.", call. = FALSE)
  }
  if (!is.numeric(min_gain) || length(min_gain) != 1L ||
    !is.finite(min_gain) || min_gain < 0) {
    stop("`min_gain` must be one finite non-negative number.", call. = FALSE)
  }
  scores <- x$scores
  if (!is.data.frame(scores) || !nrow(scores) ||
    !"mae_weibull" %in% names(scores)) {
    stop("M1 tuning is missing finite `mae_weibull` scores.", call. = FALSE)
  }
  finite <- is.finite(scores$mae_weibull)
  scores <- scores[finite, , drop = FALSE]
  if (!nrow(scores)) stop("M1 tuning has no finite candidate scores.", call. = FALSE)
  if (!"k_ref" %in% names(scores) &&
    is.data.frame(x$best) && nrow(x$best) > 0L) {
    best_row <- x$best[1L, , drop = FALSE]
    if (!"mae_weibull" %in% names(best_row) ||
      !is.finite(best_row$mae_weibull[[1L]])) {
      best_row$mae_weibull <- min(scores$mae_weibull)
    }
  } else {
    best_i <- which.min(scores$mae_weibull)
    best_row <- scores[best_i, , drop = FALSE]
  }
  selected_row <- best_row
  if (isTRUE(prefer_simpler) && "k_ref" %in% names(scores)) {
    by_k <- stats::aggregate(
      scores$mae_weibull,
      list(k_ref = as.numeric(scores$k_ref)),
      min
    )
    names(by_k)[2L] <- "mae_weibull"
    eligible <- by_k[by_k$mae_weibull <=
      best_row$mae_weibull[[1L]] + min_gain, , drop = FALSE]
    if (nrow(eligible)) {
      selected_k <- min(eligible$k_ref)
      candidates <- scores[as.numeric(scores$k_ref) == selected_k, , drop = FALSE]
      selected_row <- candidates[which.min(candidates$mae_weibull), , drop = FALSE]
    }
  }
  selected_score <- selected_row$mae_weibull[[1L]]
  best_score <- best_row$mae_weibull[[1L]]
  selected_id <- if ("spec_id" %in% names(selected_row)) {
    as.character(selected_row$spec_id[[1L]])
  } else {
    NA_character_
  }
  best_id <- if ("spec_id" %in% names(best_row)) {
    as.character(best_row$spec_id[[1L]])
  } else {
    NA_character_
  }
  list(
    selected = selected_row,
    selected_spec_id = selected_id,
    best = best_row,
    best_score = best_score,
    selected_score = selected_score,
    gain_to_best = selected_score - best_score,
    min_gain = min_gain,
    backed_off = !identical(selected_id, best_id)
  )
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
  if (!is.null(supplied)) {
    return(as.numeric(supplied))
  }
  if (length(values) < 2L) {
    return(1)
  }
  adjacent <- if (edge == "lower") {
    values[2L] - values[1L]
  } else {
    values[length(values)] - values[length(values) - 1L]
  }
  # Boundary expansion is exploratory; halve the observed spacing so a new
  # point does not jump past a narrow optimum. Explicit `steps` are unchanged.
  adjacent / 2
}

.m1_integer_axes <- function() c("k_ref", "slope_window")

.m1_k_ref_bounds <- function() c(lower = 10L, upper = 50L)

.validate_m1_k_ref_bounds <- function(bounds, n_weeks = 52L) {
  if (is.null(bounds)) {
    return(NULL)
  }
  bound_names <- names(bounds)
  bounds <- suppressWarnings(as.numeric(bounds))
  names(bounds) <- bound_names
  if (length(bounds) != 2L || any(!is.finite(bounds)) ||
    is.null(names(bounds)) || !all(c("lower", "upper") %in% names(bounds)) ||
    bounds[["lower"]] < 2 || bounds[["upper"]] > n_weeks ||
    bounds[["lower"]] > bounds[["upper"]] ||
    any(bounds != round(bounds))) {
    stop(
      "`m1_k_ref_bounds` must be named integer bounds `lower` and `upper` ",
      "within [2, ", n_weeks, "] with lower <= upper.",
      call. = FALSE
    )
  }
  out <- as.integer(bounds)
  names(out) <- names(bounds)
  out
}

.m0_integer_axes <- function() {
  c("n_consec", "L", "K_sum", "N_req", "w_min", "w_max")
}

.validate_m0_grid_support <- function(grid, data = NULL,
                                      season_col = "season",
                                      week_col = "weekF") {
  grid <- as.data.frame(grid, stringsAsFactors = FALSE)
  if (!nrow(grid)) {
    stop("M0 grid is empty.", call. = FALSE)
  }
  numeric_axes <- c(
    "cls_thr", "p_thr", "prev_thr", "p_sum_thr", "eps"
  )
  for (parameter in intersect(numeric_axes, names(grid))) {
    values <- suppressWarnings(as.numeric(grid[[parameter]]))
    bad <- !is.finite(values) | values < 0
    if (parameter != "eps") bad <- bad | values > 1
    if (any(bad)) {
      stop(
        "M0 grid `", parameter, "` contains unsupported value(s): ",
        paste(unique(values[bad]), collapse = ", "),
        ". Thresholds must be finite values in [0, 1] and eps must be non-negative.",
        call. = FALSE
      )
    }
  }
  for (parameter in intersect(.m0_integer_axes(), names(grid))) {
    values <- suppressWarnings(as.numeric(grid[[parameter]]))
    bad <- !is.finite(values) | values != round(values) | values < 1
    if (any(bad)) {
      stop(
        "M0 grid `", parameter, "` contains unsupported value(s): ",
        paste(unique(values[bad]), collapse = ", "),
        ". Values must be positive integers.",
        call. = FALSE
      )
    }
  }
  if (all(c("w_min", "w_max") %in% names(grid)) &&
    any(as.numeric(grid$w_min) > as.numeric(grid$w_max))) {
    stop("M0 grid requires w_min <= w_max for every specification.", call. = FALSE)
  }
  if ("N_req" %in% names(grid) && any(as.numeric(grid$N_req) > 5)) {
    stop("M0 grid `N_req` cannot exceed the five available detector gates.", call. = FALSE)
  }
  if (!is.null(data)) {
    data <- as.data.frame(data)
    if (!all(c(season_col, week_col) %in% names(data))) {
      stop(
        "M0 support validation requires `", season_col, "` and `",
        week_col, "` columns.",
        call. = FALSE
      )
    }
    weeks <- split(data[[week_col]], data[[season_col]])
    n_weeks <- vapply(weeks, function(x) length(unique(x[is.finite(x)])), integer(1))
    if (!length(n_weeks) || any(n_weeks < 1L)) {
      stop("M0 data has no usable within-season week support.", call. = FALSE)
    }
    max_required <- intersect(c("n_consec", "L", "K_sum"), names(grid))
    if (length(max_required) && any(vapply(max_required, function(nm) {
      any(as.numeric(grid[[nm]]) > min(n_weeks))
    }, logical(1)))) {
      bad <- max_required[vapply(max_required, function(nm) {
        any(as.numeric(grid[[nm]]) > min(n_weeks))
      }, logical(1))]
      stop(
        "M0 grid requests more observations than the shortest training season supports (",
        paste(bad, collapse = ", "), "; minimum usable weeks=", min(n_weeks), ").",
        call. = FALSE
      )
    }
    if (all(c("w_min", "w_max") %in% names(grid))) {
      week_values <- data[[week_col]]
      week_range <- range(week_values[is.finite(week_values)], na.rm = TRUE)
      if (any(as.numeric(grid$w_min) < week_range[1L]) ||
        any(as.numeric(grid$w_max) > week_range[2L])) {
        stop(
          "M0 grid ignition window lies outside the observed week domain [",
          week_range[1L], ", ", week_range[2L], "].",
          call. = FALSE
        )
      }
    }
  }
  invisible(grid)
}

.validate_m1_grid_support <- function(grid, n_weeks = 52L) {
  if (!is.numeric(n_weeks) || length(n_weeks) != 1L ||
    !is.finite(n_weeks) || n_weeks < 2 ||
    n_weeks != as.integer(n_weeks)) {
    stop("`n_weeks` must be one integer of at least 2.", call. = FALSE)
  }
  n_weeks <- as.integer(n_weeks)
  grid <- as.data.frame(grid, stringsAsFactors = FALSE)
  for (parameter in .m1_integer_axes()) {
    if (!parameter %in% names(grid)) next
    values <- suppressWarnings(as.numeric(grid[[parameter]]))
    bad <- !is.finite(values) | values != round(values) |
      values < 2 | values > n_weeks
    if (any(bad)) {
      invalid <- paste(unique(values[bad]), collapse = ", ")
      stop(
        "M1 grid `", parameter, "` contains unsupported value(s): ",
        invalid, ". Values must be integers in [2, ", n_weeks,
        "] for the ", n_weeks, "-week reference domain.",
        call. = FALSE
      )
    }
  }
  invisible(grid)
}

.valid_stage_expansion_value <- function(stage, parameter, value,
                                         n_weeks = 52L) {
  if (!is.finite(value)) {
    return(FALSE)
  }
  if (stage == "M0") {
    if (parameter == "cls_thr") {
      return(value >= 0 && value <= 1)
    }
    if (parameter %in% c("p_thr", "prev_thr", "p_sum_thr", "eps")) {
      return(value >= 0 && (parameter == "eps" || value <= 1))
    }
    if (parameter %in% c("n_consec", "L", "K_sum", "N_req", "w_min", "w_max")) {
      return(value >= 1)
    }
    return(TRUE)
  }
  if (stage == "M1") {
    if (parameter %in% .m1_integer_axes()) {
      return(value >= 2 && value <= n_weeks && value == round(value))
    }
    if (parameter %in% c("multi_temperature", "align_rise_weight", "slope_weight")) {
      return(value >= 0)
    }
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
#' appends one valid smaller adjacent value per unresolved axis and preserves every
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
#' @param n_weeks Integer reference-domain size used to guard M1 basis values.
#' @param data Optional stage data used to guard M0 rolling/window support.
#' @param m1_k_ref_bounds Named integer vector with `lower` and `upper` hard
#'   bounds for M1 `k_ref` expansion. Defaults to 10--50.
#'
#' @return The original grid with new boundary rows appended. New rows carry
#'   `provenance = "boundary:<parameter>"` when that column is available.
#' @export
expand_tuning_grid <- function(x,
                               stage = c("M0", "M1", "M2"),
                               grid = NULL,
                               steps = NULL,
                               max_specs = NULL,
                               n_weeks = 52L,
                               data = NULL,
                               m1_k_ref_bounds = .m1_k_ref_bounds()) {
  stage <- toupper(match.arg(stage))
  if (is.null(grid)) grid <- x$grid %||% x
  grid <- as.data.frame(grid, stringsAsFactors = FALSE)
  if (!nrow(grid)) stop("Cannot expand an empty tuning grid.", call. = FALSE)
  if (stage == "M0") .validate_m0_grid_support(grid, data = data)
  if (stage == "M1") {
    .validate_m1_grid_support(grid, n_weeks = n_weeks)
    bounds <- .validate_m1_k_ref_bounds(m1_k_ref_bounds, n_weeks)
    if ("k_ref" %in% names(grid) &&
      any(as.numeric(grid$k_ref) < bounds[["lower"]] |
        as.numeric(grid$k_ref) > bounds[["upper"]])) {
      stop(
        "M1 grid `k_ref` lies outside the declared hard bounds [",
        bounds[["lower"]], ", ", bounds[["upper"]], "].",
        call. = FALSE
      )
    }
  } else {
    bounds <- NULL
  }

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
    if (stage == "M1" && nrow(unresolved) &&
      "k_ref" %in% unresolved$parameter) {
      at_hard_cap <- unresolved$parameter == "k_ref" &
        ((unresolved$boundary == "upper" &
          unresolved$selected_value >= bounds[["upper"]]) |
          (unresolved$boundary == "lower" &
            unresolved$selected_value <= bounds[["lower"]]))
      unresolved <- unresolved[!at_hard_cap, , drop = FALSE]
    }
    if (nrow(unresolved)) {
      selected <- .selected_stage_config(x, stage, grid)
      new_rows <- lapply(seq_len(nrow(unresolved)), function(i) {
        row <- selected
        parameter <- unresolved$parameter[i]
        step <- .grid_adjacent_step(
          grid[[parameter]], unresolved$boundary[i],
          if (!is.null(steps) && parameter %in% names(steps)) {
            steps[[parameter]]
          } else {
            NULL
          }
        )
        integer_axes <- if (stage == "M0") {
          .m0_integer_axes()
        } else if (stage == "M1") {
          .m1_integer_axes()
        } else {
          character(0)
        }
        if (parameter %in% integer_axes) step <- max(1, ceiling(step))
        value <- unresolved$selected_value[i] +
          if (unresolved$boundary[i] == "lower") -step else step
        if (parameter %in% integer_axes) value <- as.integer(round(value))
        # A halved step can still cross the finite M1 reference domain. Move
        # to the declared hard endpoint rather than generating an impossible
        # or over-flexible reference GAM.
        if (stage == "M1" && parameter %in% .m1_integer_axes()) {
          if (parameter == "k_ref") {
            if (unresolved$boundary[i] == "upper") {
              value <- min(value, bounds[["upper"]])
            }
            if (unresolved$boundary[i] == "lower") {
              value <- max(value, bounds[["lower"]])
            }
          } else {
            if (unresolved$boundary[i] == "upper") {
              value <- min(value, as.integer(n_weeks))
            }
            if (unresolved$boundary[i] == "lower") {
              value <- max(value, 2L)
            }
          }
        }
        if (isTRUE(all.equal(
          as.numeric(value), as.numeric(unresolved$selected_value[i])
        ))) {
          stop(
            "Cannot expand ", stage, " axis `", parameter,
            "` beyond its declared hard cap. Supply a different grid or",
            " an explicit hard-cap decision.",
            call. = FALSE
          )
        }
        if (!.valid_stage_expansion_value(
          stage, parameter, value,
          n_weeks = n_weeks
        )) {
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

  if (stage == "M0") .validate_m0_grid_support(grid, data = data)
  if (stage == "M1") {
    .validate_m1_grid_support(grid, n_weeks = n_weeks)
    if ("k_ref" %in% names(grid) &&
      any(as.numeric(grid$k_ref) < bounds[["lower"]] |
        as.numeric(grid$k_ref) > bounds[["upper"]])) {
      stop(
        "Expanded M1 grid `k_ref` lies outside the declared hard bounds [",
        bounds[["lower"]], ", ", bounds[["upper"]], "].",
        call. = FALSE
      )
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
      x,
      stage = "M0", grid = grid, warn = TRUE,
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
#' @param hard_caps Optional named numeric vector or named list of lower/upper
#'   bounds, such as `list(k_ref = c(lower = 10, upper = 50))`. A selected
#'   value exactly at a hard cap is accepted and recorded as `stop_hard_cap`.
#' @param ... Reserved.
#'
#' @return \code{x}, invisibly, if valid.
#' @export
validate_m1_tuning <- function(x,
                               check_boundaries = FALSE,
                               hard_caps = NULL,
                               ...) {
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
  if ("failure_reason" %in% names(scores)) {
    failed <- scores[!is.na(scores$failure_reason) &
      nzchar(as.character(scores$failure_reason)), , drop = FALSE]
    if (nrow(failed)) {
      details <- paste(
        utils::head(paste0(failed$spec_id, ": ", failed$failure_reason), 3L),
        collapse = "; "
      )
      stop("M1 tuning contains failed candidate(s): ", details, call. = FALSE)
    }
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
    hard_caps <- hard_caps %||% x$hard_caps
    report <- inspect_tuning_boundaries(
      x,
      stage = "M1", warn = TRUE, hard_caps = hard_caps
    )
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
    tuning <- validate_m2_tuning(
      tuning,
      check_boundaries = TRUE,
      min_nll_gain = tuning$min_nll_gain %||% NULL
    )
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
#' @param min_nll_gain Named parameter-specific NLL gain threshold, or one
#'   scalar applied to every M2 axis. Defaults to
#'   \code{default_m2_nll_gain_caps()}; omitted names use the governed
#'   defaults. A boundary with matched outward gain at or below its threshold
#'   is accepted as `stop_small_gain`; a boundary without matched evidence
#'   remains unresolved.
#' @param ... Reserved.
#'
#' @return \code{x}, invisibly, if valid.
#' @export
validate_m2_tuning <- function(x,
                               check_boundaries = FALSE,
                               min_nll_gain = NULL,
                               ...) {
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
    min_nll_gain <- min_nll_gain %||% x$min_nll_gain %||%
      default_m2_nll_gain_caps()
    report <- inspect_tuning_boundaries(
      x,
      stage = "M2", warn = TRUE, min_nll_gain = min_nll_gain
    )
    x$boundary_report <- report
    if (!is.null(min_nll_gain)) x$min_nll_gain <- min_nll_gain
    .enforce_stage_boundaries("M2", report)
  }
  invisible(x)
}
