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
                               data_id = NULL) {
  payload <- list(
    stage = stage,
    selection = unclass(selection),
    config = config,
    upstream = upstream_ids,
    data_id = data_id
  )
  paste0(stage, "_", digest::digest(payload, algo = "sha256"))
}

.record_stage_provenance <- function(stage,
                                     selection,
                                     config,
                                     upstream_ids = NULL,
                                     data_id = NULL,
                                     status = "draft") {
  list(
    stage = stage,
    status = status,
    selection = selection,
    config = config,
    upstream_ids = upstream_ids,
    data_id = data_id,
    artifact_id = .stage_artifact_id(
      stage, selection, config, upstream_ids, data_id
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
    data_id = data_id
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
    x$stage, x$selection, x$config, x$upstream_ids, x$data_id
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
    !identical(unname(fit$config[shared]), unname(selected[shared]))) {
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
    stage, fit$selection, fit$config, fit$upstream_ids, fit$data_id
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
#' Promotes a draft M0 fit to immutable frozen status. When \code{tuning}
#' is supplied, it is validated first via \code{validate_m0_tuning()}.
#'
#' @param fit A \code{page_m0_fit} in draft or frozen state.
#' @param tuning Optional \code{page_m0_tuning} result to validate.
#' @param ... Reserved.
#'
#' @return The \code{page_m0_fit} in \code{frozen} state.
#' @export
freeze_m0 <- function(fit, tuning = NULL, ...) {
  .freeze_stage(fit, tuning, "m0")
}

#' Validate an M0 tuning result
#'
#' Rejects zero evaluable folds, non-finite selection metrics, missing
#' selected configuration, or mismatched folds.
#'
#' @param x A \code{page_m0_tuning} object.
#' @param ... Reserved.
#'
#' @return \code{x}, invisibly, if valid.
#' @export
validate_m0_tuning <- function(x, ...) {
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
#' @param tuning Optional \code{page_m1_tuning} to validate.
#' @param ... Reserved.
#'
#' @return The \code{page_m1_fit} in \code{frozen} state.
#' @export
freeze_m1 <- function(fit, tuning = NULL, ...) {
  .freeze_stage(fit, tuning, "m1")
}

#' Validate an M1 tuning result
#'
#' Rejects zero evaluable seasons, all-missing metrics, non-finite selected
#' metric, missing selected configuration, or fold/selection mismatches.
#'
#' @param x A \code{page_m1_tuning} object.
#' @param ... Reserved.
#'
#' @return \code{x}, invisibly, if valid.
#' @export
validate_m1_tuning <- function(x, ...) {
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
  .freeze_stage(fit, tuning, "m2")
}

#' Validate an M2 tuning result
#'
#' Rejects invalid grid identity, incomplete folds, non-finite selected
#' metric, or absent selected specification.
#'
#' @param x A \code{page_m2_tuning} object.
#' @param ... Reserved.
#'
#' @return \code{x}, invisibly, if valid.
#' @export
validate_m2_tuning <- function(x, ...) {
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
  invisible(x)
}
