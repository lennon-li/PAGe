# Three-level nested seasonal evaluation.

.nested_scalar_number <- function(x, name, lower = -Inf, upper = Inf,
                                  lower_open = FALSE, upper_open = FALSE) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x)) {
    stop(name, " must be one finite number.", call. = FALSE)
  }
  lower_bad <- if (lower_open) x <= lower else x < lower
  upper_bad <- if (upper_open) x >= upper else x > upper
  if (lower_bad || upper_bad) {
    stop(name, " is outside its supported range.", call. = FALSE)
  }
  as.numeric(x)
}

.default_nested_exclusions <- function() {
  c("2011-12", "2015-16", "2020-21", "2021-22")
}

.default_boundary_round_limits <- function() c(M0 = 5L, M1 = 4L, M2 = 6L)

.default_m1_expansion_steps <- function() c(k_ref = 5, slope_weight = 4)

.default_m2_expansion_increment <- function() 12L

.nested_positive_integer <- function(x, name, minimum = 1L) {
  value <- .nested_scalar_number(x, name, minimum)
  if (value != round(value)) {
    stop(name, " must be an integer.", call. = FALSE)
  }
  as.integer(value)
}

.nested_round_limits <- function(x) {
  defaults <- .default_boundary_round_limits()
  if (is.null(x)) {
    return(defaults)
  }
  if (!is.numeric(x) || is.null(names(x)) ||
    !all(names(defaults) %in% names(x))) {
    stop("`max_boundary_rounds` must name M0, M1, and M2.", call. = FALSE)
  }
  raw <- x[names(defaults)]
  if (any(!is.finite(raw)) || any(raw < 1L) || any(raw != round(raw))) {
    stop("Every boundary-round limit must be a positive integer.", call. = FALSE)
  }
  out <- as.integer(raw)
  stats::setNames(out, names(defaults))
}

.nested_dir <- function(path) {
  if (is.null(path)) {
    return(NULL)
  }
  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    stop("Artifact and checkpoint directories must be non-empty paths.", call. = FALSE)
  }
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, mustWork = TRUE)
}

.nested_save_rds <- function(object, directory, name) {
  if (!is.null(directory)) saveRDS(object, file.path(directory, name))
  invisible(object)
}

.nested_save_csv <- function(object, directory, name) {
  if (!is.null(directory) && is.data.frame(object)) {
    utils::write.csv(object, file.path(directory, name), row.names = FALSE)
  }
  invisible(object)
}

.nested_stage_checkpoint <- function(checkpoint_dir, stage) {
  if (is.null(checkpoint_dir)) {
    return(NULL)
  }
  .nested_dir(file.path(checkpoint_dir, tolower(stage)))
}

.nested_record_boundary <- function(tuning, plan, stage, round,
                                    artifact_dir) {
  prefix <- tolower(stage)
  .nested_save_rds(tuning, artifact_dir, paste0(prefix, "_tuning.rds"))
  .nested_save_rds(
    plan, artifact_dir,
    paste0(prefix, "_boundary_plan_round", round, ".rds")
  )
  .nested_save_csv(
    plan$final_boundary_report, artifact_dir,
    paste0(prefix, "_boundary_report_round", round, ".csv")
  )
  if (!isTRUE(plan$settled)) {
    .nested_save_csv(
      plan$next_grid, artifact_dir,
      paste0(prefix, "_grid_round", round + 1L, ".csv")
    )
  }
  invisible(NULL)
}

.nested_inner_gate_rows <- function(tuning, seasons) {
  rows <- tuning$training_rows
  config <- tuning$selected_config
  if (!is.data.frame(rows) || is.null(config)) {
    stop("M2 tuning is missing training rows or its selected configuration.",
      call. = FALSE
    )
  }
  pieces <- lapply(seasons, function(season) {
    train <- rows[as.character(rows$season) != season, , drop = FALSE]
    test <- rows[as.character(rows$season) == season, , drop = FALSE]
    if (!nrow(train) || !nrow(test)) {
      return(NULL)
    }
    horizons <- sort(unique(as.integer(test$h)))
    by_horizon <- lapply(horizons, function(horizon) {
      spec <- config[[paste0("h", horizon)]]
      if (is.null(spec)) {
        return(NULL)
      }
      fit <- m2_subset_fit(train, spec, gamma = config$gamma)
      target <- test[as.integer(test$h) == horizon, , drop = FALSE]
      if (!nrow(target)) {
        return(NULL)
      }
      data.frame(
        season = season,
        origin = target$eval_weekF,
        target = target$target_weekF,
        horizon = horizon,
        outcome = target$y_lead / target$N_lead,
        m1_prediction = target$m1_p,
        m2_prediction = m2_subset_predict(fit, target)$p_hat,
        t_since_target = target$u + horizon,
        N_lead = target$N_lead,
        stringsAsFactors = FALSE
      )
    })
    by_horizon <- by_horizon[!vapply(by_horizon, is.null, logical(1))]
    if (!length(by_horizon)) NULL else do.call(rbind, by_horizon)
  })
  pieces <- pieces[!vapply(pieces, is.null, logical(1))]
  if (!length(pieces)) {
    stop("No inner-fold M1/M2 forecasts were available for the adoption gate.",
      call. = FALSE
    )
  }
  out <- do.call(rbind, pieces)
  rownames(out) <- NULL
  out
}

.nested_m2_decision <- function(rows, early_weight, early_max_t_since,
                                min_gain, min_gain_by_horizon, confidence,
                                max_season_degradation,
                                pre_ignition_weight = 0, late_weight = 1,
                                denominator_col = NULL) {
  decide_m2_vs_m1(
    rows,
    outcome_col = "outcome",
    m1_col = "m1_prediction",
    m2_col = "m2_prediction",
    season_col = "season",
    origin_col = "origin",
    target_col = "target",
    horizon_col = "horizon",
    t_since_col = "t_since_target",
    phase_break = early_max_t_since,
    phase_weights = c(
      pre_ignition = pre_ignition_weight,
      early = early_weight,
      late = late_weight
    ),
    denominator_col = denominator_col,
    min_gain = min_gain,
    min_gain_by_horizon = min_gain_by_horizon,
    confidence = confidence,
    max_season_degradation = max_season_degradation
  )
}

.nested_score_denominators <- function(score_scale) {
  score_scale <- match.arg(score_scale, c("equal_week", "test_count"))
  if (identical(score_scale, "equal_week")) {
    return(list(primary = NULL, sensitivity = "N_lead", sensitivity_scale = "test_count"))
  }
  list(primary = "N_lead", sensitivity = NULL, sensitivity_scale = "equal_week")
}

.nested_all_off_config <- function(config, tuning) {
  all_off <- m2_subset_config(
    h1 = m2_subset_spec(),
    h2 = m2_subset_spec(),
    alpha_state = config$alpha_state,
    gamma = config$gamma
  )
  off_id <- m2_subset_spec()$id
  off_row <- tuning$grid[as.character(tuning$grid$id) == off_id, , drop = FALSE]
  if (!nrow(off_row)) {
    stop("The M2 grid does not contain the required exact all-off fallback.",
      call. = FALSE
    )
  }
  list(config = all_off, row = off_row[1L, , drop = FALSE])
}

#' Train a nested-tuned PAGe kit
#'
#' Runs the first two levels of the manuscript evaluation. When `holdout` is
#' supplied, that season is kept outside all fitting and selection. Within the
#' remaining seasons, the stage tuners perform leave-one-season-out
#' walk-forward evaluation, boundary grids are expanded until settled, and the
#' phase-weighted M2-versus-M1 adoption rule is applied before a frozen kit is
#' assembled. `holdout = NULL` is reserved for the final post-evaluation fit on
#' all eligible seasons.
#'
#' @param data Canonical multi-season surveillance data.
#' @param holdout Optional character scalar identifying the outer-held-out
#'   season. Use `NULL` only to fit the final kit after the evaluation procedure
#'   has been fixed.
#' @param exclude Character vector of fixed exclusions. Defaults to the
#'   protocol exclusions `"2011-12"`, `"2015-16"`, `"2020-21"`, and
#'   `"2021-22"`.
#' @param manual_labels Optional named ignition-week labels. Any label for
#'   `holdout` is removed before tuning.
#' @param timing_labels Optional timing-v2 label object or list of objects.
#'   The earlier ignition week is converted to the existing M0/M1 contract;
#'   peak weeks and the normalized uncertainty pairs are retained in the
#'   training result and artifacts. Any object for `holdout` is removed before
#'   tuning, while the complete supplied input is retained for provenance.
#'   Cannot be combined with `manual_labels`.
#' @param m0_grid,m1_grid,m2_grid Initial stage tuning grids.
#' @param m0_flag_args Named M0 ignition flag arguments forwarded to
#'   `tune_m0()` and `fit_m0()`. Defaults to the package detector defaults
#'   (`.default_flag_args()`).
#' @param m1_params Named baseline M1 settings that `tune_m1()` searches
#'   around. Defaults to `.default_m1_params()`.
#' @param m2_family M2 model family forwarded to `tune_m2()` and `fit_m2()`.
#'   Defaults to `m2_subset_family()` (`"offset_subset_v1"`).
#' @param early_weight Weight for target-relative weeks zero through
#'   `early_max_t_since`.
#' @param early_max_t_since Last target-relative week receiving `early_weight`.
#' @param pre_ignition_weight Phase weight for pre-ignition targets. The
#'   manuscript protocol is `0`.
#' @param late_weight Phase weight for targets later than `early_max_t_since`.
#'   The manuscript protocol is `1`.
#' @param score_scale M2 tuning scale. The manuscript primary is `equal_week`;
#'   `test_count` is available as a sensitivity analysis.
#' @param min_gain Overall M2 NLL gain required over M1.
#' @param min_gain_by_horizon Optional named horizon-specific gain floors.
#' @param confidence One-sided season-level confidence used by the adoption
#'   rule.
#' @param max_season_degradation Largest permitted season-specific M2 NLL loss.
#' @param m1_min_gain Practical M1 improvement needed for added complexity.
#' @param m1_hard_caps Governed M1 hard caps.
#' @param m1_prefer_simpler Logical; prefer the simplest M1 candidate within
#'   `m1_min_gain` of the best. Defaults to `TRUE`.
#' @param m2_min_nll_gain Parameter-specific M2 boundary gain caps.
#' @param max_boundary_rounds Named positive integer vector for M0, M1, and M2.
#'   Defaults to `c(M0 = 5L, M1 = 4L, M2 = 6L)`.
#' @param m0_expansion_steps Optional named adjacent expansion steps forwarded
#'   to `boundary_action_plan()` for M0. `NULL` uses the grid-derived spacing.
#' @param m1_expansion_steps Named positive adjacent expansion steps forwarded
#'   to `boundary_action_plan()` for M1. Defaults to `c(k_ref = 5,
#'   slope_weight = 4)`.
#' @param m2_expansion_steps Optional named adjacent expansion steps forwarded
#'   to `boundary_action_plan()` for M2. `NULL` uses the grid-derived spacing.
#' @param m2_expansion_increment Additional grid rows permitted per M2
#'   boundary expansion round. Defaults to `12L`.
#' @param min_training_seasons Minimum number of outer-training seasons
#'   required before fitting. Defaults to `2L`, the leave-one-season-out
#'   minimum.
#' @param n_cores Number of workers supplied to stage tuners. Defaults to one
#'   fewer than `parallel::detectCores()`.
#' @param checkpoint_dir Optional resumable checkpoint directory.
#' @param artifact_dir Optional directory receiving grids, tuning objects,
#'   boundary reports, decisions, frozen stages, and the final kit.
#' @param verbose Logical progress flag.
#'
#' @return A `page_outer_training` object containing the season selection,
#'   tuning results, boundary histories, adoption evidence, frozen stages, and
#'   assembled kit.
#' @export
train_outer_fold <- function(
  data,
  holdout = NULL,
  exclude = .default_nested_exclusions(),
  manual_labels = NULL,
  timing_labels = NULL,
  m0_grid = .default_m0_grid(),
  m0_flag_args = .default_flag_args(),
  m1_grid = default_m1_grid(),
  m1_params = .default_m1_params(),
  m2_grid = m2_subset_grid(),
  m2_family = m2_subset_family(),
  early_weight = 2,
  early_max_t_since = 12,
  pre_ignition_weight = 0,
  late_weight = 1,
  score_scale = c("equal_week", "test_count"),
  min_gain = 0.0012,
  min_gain_by_horizon = c("2" = 0.002),
  confidence = 0.95,
  max_season_degradation = 0,
  m1_min_gain = 0.05,
  m1_hard_caps = default_m1_hard_caps(),
  m1_prefer_simpler = TRUE,
  m2_min_nll_gain = default_m2_nll_gain_caps(),
  max_boundary_rounds = .default_boundary_round_limits(),
  m0_expansion_steps = NULL,
  m1_expansion_steps = .default_m1_expansion_steps(),
  m2_expansion_steps = NULL,
  m2_expansion_increment = .default_m2_expansion_increment(),
  min_training_seasons = 2L,
  n_cores = max(1L, parallel::detectCores() - 1L),
  checkpoint_dir = NULL,
  artifact_dir = NULL,
  verbose = TRUE,
  timing_mode = c("legacy", "fractional")
) {
  score_scale <- match.arg(score_scale)
  timing_mode <- match.arg(timing_mode)
  if (!is.null(manual_labels) && !is.null(timing_labels)) {
    stop("Supply either `manual_labels` or `timing_labels`, not both.", call. = FALSE)
  }
  if (!is.character(m2_family) || length(m2_family) != 1L ||
    !identical(m2_family, m2_subset_family())) {
    stop(
      "`train_outer_fold()` currently supports only M2 family `",
      m2_subset_family(), "` because its adoption gate requires the exact ",
      "all-off M1 fallback.",
      call. = FALSE
    )
  }
  if (!is.list(m0_flag_args) || !length(m0_flag_args) ||
    is.null(names(m0_flag_args))) {
    stop("`m0_flag_args` must be a non-empty named list.", call. = FALSE)
  }
  if (!is.list(m1_params) || !length(m1_params) || is.null(names(m1_params))) {
    stop("`m1_params` must be a non-empty named list.", call. = FALSE)
  }
  if (!is.logical(m1_prefer_simpler) || length(m1_prefer_simpler) != 1L ||
    is.na(m1_prefer_simpler)) {
    stop("`m1_prefer_simpler` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.numeric(m1_expansion_steps) || !length(m1_expansion_steps) ||
    is.null(names(m1_expansion_steps)) ||
    any(!is.finite(m1_expansion_steps)) || any(m1_expansion_steps <= 0)) {
    stop("`m1_expansion_steps` must be a named vector of positive steps.",
      call. = FALSE
    )
  }
  m2_expansion_increment <- .nested_positive_integer(
    m2_expansion_increment, "`m2_expansion_increment`"
  )
  min_training_seasons <- .nested_positive_integer(
    min_training_seasons, "`min_training_seasons`",
    minimum = 2L
  )
  early_weight <- .nested_scalar_number(early_weight, "`early_weight`", 0)
  early_max_t_since <- .nested_positive_integer(
    early_max_t_since, "`early_max_t_since`",
    minimum = 0L
  )
  pre_ignition_weight <- .nested_scalar_number(
    pre_ignition_weight, "`pre_ignition_weight`", 0
  )
  late_weight <- .nested_scalar_number(late_weight, "`late_weight`", 0)
  min_gain <- .nested_scalar_number(min_gain, "`min_gain`", 0)
  confidence <- .nested_scalar_number(
    confidence, "`confidence`", 0, 1, TRUE, TRUE
  )
  max_season_degradation <- .nested_scalar_number(
    max_season_degradation, "`max_season_degradation`", 0
  )
  rounds <- .nested_round_limits(max_boundary_rounds)
  n_cores <- .nested_positive_integer(n_cores, "`n_cores`")
  artifact_dir <- .nested_dir(artifact_dir)
  checkpoint_dir <- .nested_dir(checkpoint_dir)

  data <- prepare_surveillance_data(data)
  final_fit <- is.null(holdout)
  holdout <- if (final_fit) character(0) else as.character(holdout)
  if (!final_fit &&
    (length(holdout) != 1L || is.na(holdout) || !nzchar(holdout))) {
    stop("`holdout` must be NULL or identify exactly one season.",
      call. = FALSE
    )
  }
  seasons <- unique(as.character(data$season))
  if (!final_fit && !holdout %in% seasons) {
    stop("Outer holdout is absent from `data`: ", holdout, call. = FALSE)
  }
  exclude <- intersect(unique(as.character(exclude)), seasons)
  if (!final_fit && holdout %in% exclude) {
    stop("The outer holdout cannot also be a fixed exclusion.", call. = FALSE)
  }
  training_seasons <- setdiff(seasons, c(exclude, holdout))
  if (length(training_seasons) < min_training_seasons) {
    stop("At least ", min_training_seasons,
      " outer-training seasons are required.",
      call. = FALSE
    )
  }
  selection <- validate_season_selection(
    data,
    training_seasons = training_seasons,
    exclude_seasons = exclude,
    holdout_seasons = holdout,
    application_seasons = character(0)
  )
  supplied_timing_labels <- timing_labels
  timing_labels <- .timing_v2_filter_holdout(
    timing_labels,
    if (final_fit) NULL else holdout
  )
  if (!is.null(timing_labels)) {
    manual_labels <- as_manual_labels_v2(timing_labels)
  }
  timing_targets <- if (timing_mode == "fractional") {
    if (is.null(timing_labels)) {
      stop("Fractional timing requires `timing_labels`.", call. = FALSE)
    }
    as_timing_targets_v2(timing_labels)
  } else {
    NULL
  }
  if (is.null(manual_labels)) manual_labels <- .default_manual_labels()
  if (!final_fit && !is.null(names(manual_labels))) {
    manual_labels <- manual_labels[names(manual_labels) != holdout]
  }
  if (!final_fit && holdout %in% names(manual_labels)) {
    stop("The outer holdout label was not isolated.", call. = FALSE)
  }

  protocol <- list(
    analysis_role = if (final_fit) "final_fit" else "outer_fold_training",
    holdout = holdout,
    training_seasons = selection$training_seasons,
    exclude_seasons = selection$exclude_seasons,
    weighting = list(
      pre_ignition = pre_ignition_weight,
      early = early_weight,
      early_max_t_since = early_max_t_since,
      late = late_weight,
      score_scale = score_scale,
      season_aggregation = "equal"
    ),
    adoption = list(
      min_gain = min_gain,
      min_gain_by_horizon = min_gain_by_horizon,
      confidence = confidence,
      max_season_degradation = max_season_degradation
    ),
    model = list(
      m2_family = m2_family,
      m0_flag_args = m0_flag_args,
      m1_params = m1_params,
      m1_prefer_simpler = m1_prefer_simpler,
      timing_mode = timing_mode
    ),
    timing_labels_v2 = supplied_timing_labels,
    timing_labels_v2_training = timing_labels,
    expansion = list(
      m0_steps = m0_expansion_steps,
      m1_steps = m1_expansion_steps,
      m2_steps = m2_expansion_steps,
      m2_increment = m2_expansion_increment,
      min_training_seasons = min_training_seasons
    ),
    max_boundary_rounds = rounds
  )
  .nested_save_rds(protocol, artifact_dir, "protocol.rds")
  if (!is.null(supplied_timing_labels)) {
    .nested_save_rds(
      supplied_timing_labels, artifact_dir, "timing_labels_v2.rds"
    )
  }

  m0_checkpoint <- .nested_stage_checkpoint(checkpoint_dir, "M0")
  m0_tuning <- NULL
  m0_history <- vector("list", rounds[["M0"]])
  current_grid <- as.data.frame(m0_grid)
  for (attempt in seq_len(rounds[["M0"]])) {
    .nested_save_csv(
      current_grid,
      artifact_dir,
      paste0("m0_grid_round", attempt, ".csv")
    )
    m0_tuning <- tune_m0(
      data,
      grid = current_grid,
      manual_labels = manual_labels,
      flag_args = m0_flag_args,
      n_cores = n_cores,
      verbose = verbose,
      selection = selection,
      checkpoint_dir = m0_checkpoint,
      timing_truth = timing_targets,
      timing_mode = timing_mode,
      previous_results = if (attempt == 1L) NULL else m0_tuning$tuning
    )
    plan <- boundary_action_plan(
      m0_tuning,
      stage = "M0",
      steps = m0_expansion_steps
    )
    m0_history[[attempt]] <- plan
    .nested_record_boundary(m0_tuning, plan, "M0", attempt, artifact_dir)
    if (isTRUE(plan$settled)) break
    current_grid <- plan$next_grid
  }
  m0_history <- m0_history[!vapply(m0_history, is.null, logical(1))]
  if (!length(m0_history) || !isTRUE(tail(m0_history, 1L)[[1L]]$settled)) {
    stop("M0 boundary remained unresolved; M1 was not started.", call. = FALSE)
  }
  validate_m0_tuning(m0_tuning, grid = current_grid, check_boundaries = TRUE)
  m0 <- freeze_m0(fit_m0(
    data,
    selection,
    config = m0_tuning$best_params,
    manual_labels = manual_labels,
    flag_args = m0_flag_args,
    timing_truth = timing_targets
  ), tuning = m0_tuning)
  .nested_save_rds(m0, artifact_dir, "m0_frozen.rds")

  m1_checkpoint <- .nested_stage_checkpoint(checkpoint_dir, "M1")
  m1_tuning <- NULL
  m1_history <- vector("list", rounds[["M1"]])
  current_grid <- as.data.frame(m1_grid)
  for (attempt in seq_len(rounds[["M1"]])) {
    .nested_save_csv(
      current_grid,
      artifact_dir,
      paste0("m1_grid_round", attempt, ".csv")
    )
    m1_tuning <- tune_m1(
      data,
      m0 = m0,
      m1 = list(m1_params = m1_params),
      grid = current_grid,
      n_cores = n_cores,
      checkpoint_dir = m1_checkpoint,
      verbose = verbose,
      selection = selection,
      manual_labels = manual_labels,
      timing_truth = timing_targets,
      timing_mode = timing_mode
    )
    m1_tuning$hard_caps <- m1_hard_caps
    plan <- boundary_action_plan(
      m1_tuning,
      stage = "M1",
      hard_caps = m1_hard_caps,
      m1_min_gain = m1_min_gain,
      m1_prefer_simpler = m1_prefer_simpler,
      steps = m1_expansion_steps
    )
    m1_history[[attempt]] <- plan
    .nested_record_boundary(m1_tuning, plan, "M1", attempt, artifact_dir)
    if (isTRUE(plan$settled)) break
    current_grid <- plan$next_grid
  }
  m1_history <- m1_history[!vapply(m1_history, is.null, logical(1))]
  if (!length(m1_history) || !isTRUE(tail(m1_history, 1L)[[1L]]$settled)) {
    stop("M1 boundary remained unresolved; M2 was not started.", call. = FALSE)
  }
  m1_selection <- select_m1_candidate(
    m1_tuning,
    min_gain = m1_min_gain,
    prefer_simpler = m1_prefer_simpler,
    hard_caps = m1_hard_caps
  )
  m1_tuning$best <- m1_selection$selected
  m1_tuning$m1_selection <- m1_selection
  validate_m1_tuning(
    m1_tuning,
    check_boundaries = TRUE,
    hard_caps = m1_hard_caps
  )
  m1_config <- .m1_params_from_tuning(m1_params, m1_tuning)
  m1 <- freeze_m1(fit_m1(
    data,
    selection,
    m0 = m0,
    config = m1_config,
    timing_mode = timing_mode,
    timing_truth = timing_targets
  ), tuning = m1_tuning)
  .nested_save_rds(m1_selection, artifact_dir, "m1_selection.rds")
  .nested_save_rds(m1, artifact_dir, "m1_frozen.rds")

  m2_checkpoint <- .nested_stage_checkpoint(checkpoint_dir, "M2")
  m2_tuning <- NULL
  m2_history <- vector("list", rounds[["M2"]])
  current_grid <- as.data.frame(m2_grid)
  m1_train_preds <- NULL
  for (attempt in seq_len(rounds[["M2"]])) {
    .nested_save_csv(
      current_grid,
      artifact_dir,
      paste0("m2_grid_round", attempt, ".csv")
    )
    m2_tuning <- tune_m2(
      data,
      selection = selection,
      m0 = m0,
      m1 = m1,
      grid = current_grid,
      family = m2_family,
      checkpoint_dir = m2_checkpoint,
      early_weight = early_weight,
      early_max_t_since = early_max_t_since,
      pre_ignition_weight = pre_ignition_weight,
      late_weight = late_weight,
      score_scale = score_scale,
      m1_train_preds = m1_train_preds,
      n_cores = n_cores,
      verbose = verbose,
      timing_mode = timing_mode
    )
    m1_train_preds <- m2_tuning$m1_train_preds
    m2_tuning$min_nll_gain <- m2_min_nll_gain
    plan <- boundary_action_plan(
      m2_tuning,
      stage = "M2",
      steps = m2_expansion_steps,
      max_specs = nrow(current_grid) + m2_expansion_increment
    )
    m2_history[[attempt]] <- plan
    .nested_record_boundary(m2_tuning, plan, "M2", attempt, artifact_dir)
    .nested_save_csv(m2_tuning$grid, artifact_dir, "m2_grid.csv")
    .nested_save_csv(m2_tuning$scores, artifact_dir, "m2_fold_scores.csv")
    .nested_save_csv(m2_tuning$summary, artifact_dir, "m2_summary.csv")
    if (isTRUE(plan$settled)) break
    current_grid <- plan$next_grid
  }
  m2_history <- m2_history[!vapply(m2_history, is.null, logical(1))]
  if (!length(m2_history) || !isTRUE(tail(m2_history, 1L)[[1L]]$settled)) {
    stop("M2 boundary remained unresolved; no kit was assembled.", call. = FALSE)
  }
  validate_m2_tuning(
    m2_tuning,
    check_boundaries = TRUE,
    min_nll_gain = m2_min_nll_gain
  )

  inner_rows <- .nested_inner_gate_rows(m2_tuning, selection$training_seasons)
  score_denominators <- .nested_score_denominators(score_scale)
  gate <- .nested_m2_decision(
    inner_rows,
    early_weight = early_weight,
    early_max_t_since = early_max_t_since,
    min_gain = min_gain,
    min_gain_by_horizon = min_gain_by_horizon,
    confidence = confidence,
    max_season_degradation = max_season_degradation,
    pre_ignition_weight = pre_ignition_weight,
    late_weight = late_weight,
    denominator_col = score_denominators$primary
  )
  gate_sensitivity <- .nested_m2_decision(
    inner_rows,
    early_weight = early_weight,
    early_max_t_since = early_max_t_since,
    min_gain = min_gain,
    min_gain_by_horizon = min_gain_by_horizon,
    confidence = confidence,
    max_season_degradation = max_season_degradation,
    pre_ignition_weight = pre_ignition_weight,
    late_weight = late_weight,
    denominator_col = score_denominators$sensitivity
  )
  selected_config <- m2_tuning$selected_config
  tuned_spec_id <- m2_tuning$best_spec_id
  if (identical(gate$decision, "use_m2")) {
    applied <- list(
      action = "use_m2",
      tuned_spec_id = tuned_spec_id,
      applied_spec_id = tuned_spec_id,
      reasons = gate$reasons
    )
  } else {
    fallback <- .nested_all_off_config(selected_config, m2_tuning)
    selected_config <- fallback$config
    m2_tuning$selected_config <- selected_config
    m2_tuning$selected <- list(h1 = fallback$row, h2 = fallback$row)
    m2_tuning$best_spec_id <- paste0(
      "h1:", fallback$row$id, "|h2:", fallback$row$id
    )
    applied <- list(
      action = "keep_m1",
      tuned_spec_id = tuned_spec_id,
      applied_spec_id = m2_tuning$best_spec_id,
      reasons = gate$reasons
    )
  }
  validate_m2_tuning(m2_tuning)
  .nested_save_csv(inner_rows, artifact_dir, "inner_gate_matched_rows.csv")
  .nested_save_rds(gate, artifact_dir, "inner_gate_decision.rds")
  .nested_save_rds(
    gate_sensitivity,
    artifact_dir,
    paste0(
      "inner_gate_decision_", score_denominators$sensitivity_scale,
      "_sensitivity.rds"
    )
  )
  .nested_save_rds(applied, artifact_dir, "gate_decision_applied.rds")

  m2 <- freeze_m2(fit_m2(
    data,
    selection,
    m0 = m0,
    m1 = m1,
    config = selected_config,
    family = m2_family,
    m1_train_preds = m2_tuning$m1_train_preds,
    n_cores = n_cores,
    verbose = verbose,
    timing_mode = timing_mode,
    timing_truth = timing_targets
  ), tuning = m2_tuning)
  kit <- assemble_kit(
    m0,
    m1,
    m2,
    best_spec_id = m2_tuning$best_spec_id
  )
  validate_page_kit(kit)
  .nested_save_rds(m2, artifact_dir, "m2_frozen.rds")
  .nested_save_rds(kit, artifact_dir, "candidate_pre_holdout.rds")

  result <- structure(list(
    protocol = protocol,
    selection = selection,
    tuning = list(m0 = m0_tuning, m1 = m1_tuning, m2 = m2_tuning),
    boundaries = list(m0 = m0_history, m1 = m1_history, m2 = m2_history),
    gate = list(
      matched = inner_rows,
      primary = gate,
      sensitivity = gate_sensitivity,
      sensitivity_scale = score_denominators$sensitivity_scale,
      applied = applied
    ),
    stages = list(m0 = m0, m1 = m1, m2 = m2),
    timing_labels_v2 = supplied_timing_labels,
    timing_labels_v2_training = timing_labels,
    kit = kit
  ), class = c("page_outer_training", "list"))
  .nested_save_rds(result, artifact_dir, "outer_training_result.rds")
  result
}

#' Fit the final deployment pipeline after nested evaluation
#'
#' Applies the same inner walk-forward tuning, boundary expansion, weighting,
#' and M2-versus-M1 adoption procedure to every eligible historical season.
#' Call this only after the evaluation protocol has been fixed; it does not
#' produce an additional outer-holdout estimate.
#'
#' @inheritParams train_outer_fold
#' @param ... Additional arguments passed to `train_outer_fold()`.
#'
#' @return A `page_final_training` object containing the fitted all-season kit
#'   and its complete tuning evidence.
#' @export
fit_final_pipeline <- function(data,
                               exclude = .default_nested_exclusions(),
                               ...) {
  result <- train_outer_fold(
    data,
    holdout = NULL,
    exclude = exclude,
    ...
  )
  class(result) <- c("page_final_training", class(result))
  result
}

.nested_replay_rows <- function(replay) {
  predictions <- replay$predictions
  m2_predictions <- replay$stages$m2_predictions
  if (!is.data.frame(predictions) || !is.data.frame(m2_predictions)) {
    stop("Replay output is missing prediction frames.", call. = FALSE)
  }
  horizon <- as.integer(sub("^h", "", as.character(predictions$lead)))
  m2_horizon <- if ("h" %in% names(m2_predictions)) {
    as.integer(sub("^h", "", as.character(m2_predictions$h)))
  } else {
    as.integer(sub("^h", "", as.character(m2_predictions$lead)))
  }
  pred_target <- predictions$target_weekF %||%
    (as.numeric(predictions$weekF) + horizon)
  m2_target <- m2_predictions$target_weekF %||%
    (as.numeric(m2_predictions$eval_week) + m2_horizon)
  pred_key <- .assert_unique_forecast_keys(
    predictions$weekF, horizon, "Replay predictions",
    target = pred_target
  )
  .assert_forecast_target_consistency(
    predictions$weekF, horizon, pred_target, "Replay predictions"
  )
  m2_key <- .assert_unique_forecast_keys(
    m2_predictions$eval_week, m2_horizon, "Replay M1 predictions",
    target = m2_target
  )
  .assert_forecast_target_consistency(
    m2_predictions$eval_week, m2_horizon, m2_target,
    "Replay M1 predictions"
  )
  index <- match(pred_key, m2_key)
  unmatched <- which(is.na(index))
  if (length(unmatched)) {
    stop(
      "Replay predictions contain ", length(unmatched),
      " forecast key(s) with no matched M1 prediction: ",
      paste(utils::head(pred_key[unmatched], 3L), collapse = ", "), ".",
      call. = FALSE
    )
  }
  ledger <- replay$forecast_ledger
  if (is.data.frame(ledger) &&
    all(c("weekF", "lead", "scorable") %in% names(ledger))) {
    scorable <- which(as.logical(ledger$scorable))
    ledger_key <- .forecast_key(
      ledger$weekF[scorable], ledger$lead[scorable],
      ledger$target_weekF[scorable] %||% NULL
    )
    .assert_forecast_key_match(
      pred_key, ledger_key, "Replay predictions", "scorable replay ledger"
    )
  }
  out <- data.frame(
    season = as.character(predictions$season),
    origin = predictions$weekF,
    target = pred_target,
    horizon = horizon,
    outcome = predictions$p_obs,
    m1_prediction = m2_predictions$m1_p[index],
    m2_prediction = predictions$p_hat,
    t_since_target = predictions$t_since + horizon,
    N_lead = predictions$N_lead,
    stringsAsFactors = FALSE
  )
  complete <- stats::complete.cases(out[c(
    "outcome", "m1_prediction", "m2_prediction", "t_since_target"
  )])
  if (any(!complete)) {
    stop(
      "Replay comparison contains ", sum(!complete),
      " matched forecast row(s) with missing M1/M2 values or timing.",
      call. = FALSE
    )
  }
  if (!nrow(out)) stop("No matched M1/M2 rows were produced by replay.", call. = FALSE)
  rownames(out) <- NULL
  out
}

#' Train and replay one outer-held-out season
#'
#' Combines `train_outer_fold()` with a strict `replay_season_holdout()` call.
#' The outer season is first accessed for prediction only after the training
#' procedure, grids, and M2-versus-M1 decision are frozen.
#'
#' @inheritParams train_outer_fold
#' @param timing_labels Optional timing-v2 label object or list of objects;
#'   passed through to `train_outer_fold()` after holdout isolation.
#' @param ... Additional arguments passed to `train_outer_fold()`.
#'
#' @return A `page_outer_fold_result` containing training evidence, replay,
#'   matched forecast rows, and phase-weighted M2-versus-M1 metrics.
#' @export
run_outer_fold <- function(data, holdout, artifact_dir = NULL,
                           checkpoint_dir = NULL, timing_labels = NULL,
                           timing_mode = c("legacy", "fractional"), ...) {
  timing_mode <- match.arg(timing_mode)
  artifact_dir <- .nested_dir(artifact_dir)
  checkpoint_dir <- .nested_dir(checkpoint_dir)
  training <- train_outer_fold(
    data,
    holdout = holdout,
    artifact_dir = artifact_dir,
    checkpoint_dir = checkpoint_dir,
    timing_labels = timing_labels,
    timing_mode = timing_mode,
    ...
  )
  replay <- replay_season_holdout(
    training$kit,
    data,
    season = holdout,
    kit_compatibility = "strict",
    timing_mode = timing_mode
  )
  if (!identical(as.character(replay$status), "unseen_replay_complete")) {
    stop("Outer replay did not complete under the unseen-season contract.",
      call. = FALSE
    )
  }
  rows <- .nested_replay_rows(replay)
  weighting <- training$protocol$weighting
  adoption <- training$protocol$adoption
  score_denominators <- .nested_score_denominators(weighting$score_scale)
  metrics <- .nested_m2_decision(
    rows,
    early_weight = weighting$early,
    early_max_t_since = weighting$early_max_t_since,
    min_gain = adoption$min_gain,
    min_gain_by_horizon = adoption$min_gain_by_horizon,
    confidence = adoption$confidence,
    max_season_degradation = adoption$max_season_degradation,
    pre_ignition_weight = weighting$pre_ignition,
    late_weight = weighting$late,
    denominator_col = score_denominators$primary
  )
  sensitivity <- .nested_m2_decision(
    rows,
    early_weight = weighting$early,
    early_max_t_since = weighting$early_max_t_since,
    min_gain = adoption$min_gain,
    min_gain_by_horizon = adoption$min_gain_by_horizon,
    confidence = adoption$confidence,
    max_season_degradation = adoption$max_season_degradation,
    pre_ignition_weight = weighting$pre_ignition,
    late_weight = weighting$late,
    denominator_col = score_denominators$sensitivity
  )
  result <- structure(list(
    holdout = holdout,
    training = training,
    replay = replay,
    predictions = rows,
    metrics = metrics,
    sensitivity = sensitivity,
    sensitivity_scale = score_denominators$sensitivity_scale
  ), class = c("page_outer_fold_result", "list"))
  .nested_save_rds(replay, artifact_dir, "outer_replay.rds")
  .nested_save_csv(rows, artifact_dir, "outer_predictions.csv")
  .nested_save_rds(result, artifact_dir, "outer_fold_result.rds")
  result
}

#' Run the complete nested seasonal evaluation
#'
#' Rotates every requested season through the outer holdout. Each outer fold
#' independently performs inner leave-one-season-out tuning, boundary
#' expansion, M2-versus-M1 adoption, frozen-kit fitting, and strict weekly
#' replay. Completed fold artifacts may be reused when `resume = TRUE`.
#'
#' @param data Canonical multi-season surveillance data.
#' @param holdouts Seasons to hold out in turn. Defaults to every season not in
#'   `exclude`.
#' @param exclude Fixed excluded seasons. Defaults to the protocol exclusions
#'   `"2011-12"`, `"2015-16"`, `"2020-21"`, and `"2021-22"`.
#' @param artifact_dir Parent directory for one subdirectory per outer fold.
#' @param checkpoint_dir Optional parent checkpoint directory.
#' @param resume Reuse a completed `outer_fold_result.rds` when its recorded
#'   holdout matches the requested fold.
#' @param timing_labels Optional timing-v2 label object or list of objects;
#'   passed to each outer fold after that fold's holdout is isolated.
#' @param ... Additional arguments passed to `run_outer_fold()`.
#'
#' @return A `page_nested_season_evaluation` containing all fold results,
#'   canonical out-of-fold predictions, and equal-season primary and
#'   test-count-weighted sensitivity summaries.
#' @export
nested_season_evaluation <- function(
  data,
  holdouts = NULL,
  exclude = .default_nested_exclusions(),
  artifact_dir = NULL,
  checkpoint_dir = NULL,
  resume = TRUE,
  timing_labels = NULL,
  ...
) {
  data <- prepare_surveillance_data(data)
  seasons <- unique(as.character(data$season))
  exclude <- intersect(unique(as.character(exclude)), seasons)
  if (is.null(holdouts)) holdouts <- setdiff(seasons, exclude)
  holdouts <- unique(as.character(holdouts))
  if (!length(holdouts) || anyNA(holdouts) || any(!nzchar(holdouts))) {
    stop("`holdouts` must contain at least one season.", call. = FALSE)
  }
  if (!all(holdouts %in% seasons)) {
    stop("Some requested holdouts are absent from `data`.", call. = FALSE)
  }
  if (any(holdouts %in% exclude)) {
    stop("A requested outer holdout is also a fixed exclusion.", call. = FALSE)
  }
  artifact_dir <- .nested_dir(artifact_dir)
  checkpoint_dir <- .nested_dir(checkpoint_dir)

  dots <- list(...)
  dots$timing_labels <- timing_labels
  data_id <- .stage_training_data_id(data)
  folds <- stats::setNames(vector("list", length(holdouts)), holdouts)
  for (holdout in holdouts) {
    slug <- gsub("[^A-Za-z0-9]+", "_", holdout)
    fold_artifacts <- if (is.null(artifact_dir)) {
      NULL
    } else {
      .nested_dir(file.path(artifact_dir, slug))
    }
    fold_checkpoints <- if (is.null(checkpoint_dir)) {
      NULL
    } else {
      .nested_dir(file.path(checkpoint_dir, slug))
    }
    completed <- if (is.null(fold_artifacts)) {
      NULL
    } else {
      file.path(fold_artifacts, "outer_fold_result.rds")
    }
    request_id <- digest::digest(list(
      data_id = data_id,
      holdout = holdout,
      exclude = sort(exclude),
      arguments = dots
    ), algo = "sha256")
    prior <- NULL
    if (isTRUE(resume) && !is.null(completed) && file.exists(completed)) {
      prior <- readRDS(completed)
      if (!inherits(prior, "page_outer_fold_result") ||
        !identical(as.character(prior$holdout), holdout)) {
        stop("Completed fold artifact does not match holdout: ", holdout,
          call. = FALSE
        )
      }
      if (!identical(prior$request_id, request_id)) {
        stop(
          "Completed fold artifact does not match the requested data or ",
          "controls for holdout ", holdout, ". Use `resume = FALSE` and a ",
          "new artifact directory.",
          call. = FALSE
        )
      }
    }
    if (is.null(prior)) {
      call_args <- c(list(
        data = data,
        holdout = holdout,
        exclude = exclude,
        artifact_dir = fold_artifacts,
        checkpoint_dir = fold_checkpoints
      ), dots)
      prior <- do.call(run_outer_fold, call_args)
      prior$request_id <- request_id
      .nested_save_rds(prior, fold_artifacts, "outer_fold_result.rds")
    }
    folds[[holdout]] <- prior
  }
  rows <- do.call(rbind, lapply(folds, `[[`, "predictions"))
  rownames(rows) <- NULL
  first_protocol <- folds[[1L]]$training$protocol
  weighting <- first_protocol$weighting
  adoption <- first_protocol$adoption
  score_denominators <- .nested_score_denominators(weighting$score_scale)
  primary <- .nested_m2_decision(
    rows,
    early_weight = weighting$early,
    early_max_t_since = weighting$early_max_t_since,
    min_gain = adoption$min_gain,
    min_gain_by_horizon = adoption$min_gain_by_horizon,
    confidence = adoption$confidence,
    max_season_degradation = adoption$max_season_degradation,
    pre_ignition_weight = weighting$pre_ignition,
    late_weight = weighting$late,
    denominator_col = score_denominators$primary
  )
  sensitivity <- .nested_m2_decision(
    rows,
    early_weight = weighting$early,
    early_max_t_since = weighting$early_max_t_since,
    min_gain = adoption$min_gain,
    min_gain_by_horizon = adoption$min_gain_by_horizon,
    confidence = adoption$confidence,
    max_season_degradation = adoption$max_season_degradation,
    pre_ignition_weight = weighting$pre_ignition,
    late_weight = weighting$late,
    denominator_col = score_denominators$sensitivity
  )
  result <- structure(list(
    holdouts = holdouts,
    folds = folds,
    predictions = rows,
    primary = primary,
    sensitivity = sensitivity,
    sensitivity_scale = score_denominators$sensitivity_scale,
    timing_labels_v2 = timing_labels
  ), class = c("page_nested_season_evaluation", "list"))
  .nested_save_csv(rows, artifact_dir, "outer_predictions_all_seasons.csv")
  .nested_save_rds(result, artifact_dir, "nested_season_evaluation.rds")
  result
}
