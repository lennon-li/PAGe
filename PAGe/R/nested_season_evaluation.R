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
  if (!is.null(directory)) {
    run_start <- getOption("page.run_rng_start", NULL)
    if (!is.null(run_start)) {
      attr(object, "reproducibility") <- list(
        run_rng_start = run_start, rng_at_save = .page_rng_snapshot()
      )
    }
    saveRDS(object, file.path(directory, name))
  }
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

# One governed selection lifecycle for outer training and the inner gate.
# `max_rounds` counts selections, including the initial grid.  A boundary plan
# is therefore always made for the final selection, and an unresolved final
# plan is a hard stop exactly as it is for the outer workflow.
.nested_selection_lifecycle <- function(stage, initial_grid, max_rounds,
                                        tune, plan, validate,
                                        artifact_dir = NULL) {
  stage <- toupper(match.arg(stage, c("M0", "M1", "M2")))
  max_rounds <- .nested_positive_integer(max_rounds, "`max_rounds`")
  current_grid <- as.data.frame(initial_grid)
  if (!nrow(current_grid)) {
    stop(stage, " selection requires a non-empty initial grid.", call. = FALSE)
  }
  history <- vector("list", max_rounds)
  tuning <- NULL
  for (attempt in seq_len(max_rounds)) {
    .nested_save_csv(
      current_grid, artifact_dir,
      paste0(tolower(stage), "_grid_round", attempt, ".csv")
    )
    tuning <- tune(current_grid, attempt, tuning)
    if (!is.list(tuning)) {
      stop(stage, " tuner did not return a tuning result.", call. = FALSE)
    }
    plan_i <- plan(tuning, current_grid, attempt)
    if (!is.list(plan_i) || is.null(plan_i$settled)) {
      stop(stage, " boundary planner did not return a settled status.", call. = FALSE)
    }
    history[[attempt]] <- plan_i
    .nested_record_boundary(tuning, plan_i, stage, attempt, artifact_dir)
    if (isTRUE(plan_i$settled)) break
    if (attempt == max_rounds || is.null(plan_i$next_grid)) break
    current_grid <- as.data.frame(plan_i$next_grid)
  }
  history <- history[!vapply(history, is.null, logical(1))]
  if (!length(history) || !isTRUE(tail(history, 1L)[[1L]]$settled)) {
    stop(stage, " boundary remained unresolved after ", max_rounds,
      " selection(s).",
      call. = FALSE
    )
  }
  validated <- validate(tuning, current_grid)
  if (!is.null(validated)) tuning <- validated
  list(tuning = tuning, grid = current_grid, history = history)
}

.nested_label_ignition <- function(aligned, season, timing_mode) {
  aligned_season <- aligned[as.character(aligned$season) == season, , drop = FALSE]
  week_col <- if (timing_mode == "fractional" && "iWeekF" %in% names(aligned)) {
    "iWeekF"
  } else {
    "iWeek"
  }
  week <- suppressWarnings(as.numeric(aligned_season[[week_col]]))
  week <- week[is.finite(week)][1L]
  if (!is.finite(week)) {
    stop("Nested M2 gate requires one finite label-truth ignition for ", season,
      ".",
      call. = FALSE
    )
  }
  locked <- as.integer(round(week))
  list(
    ign_week_locked = locked,
    ign_week_lockedF = week,
    iWeek_hat_locked = locked,
    iWeek_hat_lockedF = week,
    iWeek_hat_dynamic_last = locked,
    iWeek_hat_dynamic_lastF = week,
    df = data.frame(
      weekF = sort(unique(as.integer(aligned_season$weekF))),
      ignite_ok_now = sort(unique(as.integer(aligned_season$weekF))) >= locked
    ),
    timing_mode = timing_mode,
    source = "manual M0 ignition label truth"
  )
}

.nested_exclusion_sets <- function(seasons) {
  seasons <- sort(unique(as.character(seasons)))
  c(
    lapply(seasons, c),
    if (length(seasons) >= 2L) {
      combn(seasons, 2L, simplify = FALSE)
    } else {
      list()
    }
  )
}

# Outer-fold M1 alignment controls, passed explicitly rather than relying on
# m1_walkforward_multi() function defaults.
.nested_m1_control <- function(m1_params) {
  p <- m1_params %||% list()
  list(
    temperature = m2_subset_or(p$temperature, 0.25),
    rise_weight = m2_subset_or(p$rise_weight, 1),
    trough_weight = m2_subset_or(p$trough_weight, 0.1),
    peak_decay = m2_subset_or(p$peak_decay, 0.3),
    slope_weight = m2_subset_or(p$slope_weight, 8),
    slope_window = m2_subset_or(p$slope_window, 6L),
    dynamic_temp = isTRUE(m2_subset_or(p$dynamic_temp, FALSE)),
    dynamic_temp_pivot = m2_subset_or(p$dynamic_temp_pivot, 10L),
    spread_method = m2_subset_or(p$spread_method, "between")
  )
}

.nested_m0_params <- function(m0) {
  m0_params <- m2_subset_or(m0$best_params, m0$params)
  if (is.null(m0_params)) m0_params <- list()
  m0_params
}

.nested_m1_cache <- function(data, m0, m1, seasons, timing_mode,
                             m1_params = NULL) {
  seasons <- sort(unique(as.character(seasons)))
  excluded_sets <- .nested_exclusion_sets(seasons)
  keys <- vapply(excluded_sets, .m1_exclusion_key, character(1))
  references <- .m1_heldout_references(
    m1, seasons,
    timing_mode = timing_mode, excluded_sets = excluded_sets,
    params = m1_params
  )
  control <- .nested_m1_control(m1_params)
  label_ignition <- stats::setNames(
    lapply(seasons, function(s) {
      .nested_label_ignition(m1$aligned_train, s, timing_mode)
    }),
    seasons
  )
  m0_params <- .nested_m0_params(m0)
  predictions <- stats::setNames(lapply(seq_along(keys), function(i) {
    excluded <- excluded_sets[[i]]
    reference <- references[[keys[[i]]]]
    # A pair reference is intentionally used for both possible gate roles:
    # when s is evaluated, r's training prediction excludes both r and s.
    # Timing uses the outer fold's selected M0 parameters (detected), matching
    # the correction fit and runtime.
    do.call(
      m1_walkforward_multi,
      c(
        list(
          allD = data,
          ref = reference$ref,
          hyper = reference$hyper,
          params = m0_params,
          seasons = excluded,
          season_references = stats::setNames(
            rep(list(reference), length(excluded)), excluded
          )
        ),
        control,
        list(parallel = FALSE, verbose = FALSE, timing_mode = timing_mode)
      )
    )
  }), keys)
  list(
    references = references,
    predictions = predictions,
    label_ignition = label_ignition,
    excluded_sets = stats::setNames(excluded_sets, keys),
    reference_fit_count = length(references),
    reference_keys = keys,
    reference_fit_strategy = "singletons_plus_unordered_pairs",
    reference_fit_count_expected = as.integer(
      length(seasons) + choose(length(seasons), 2L)
    )
  )
}

# One-season view of the nested M1 cache used by the fully nested gate: the
# walk-forward timing uses that gate season's nested M0 parameters and the
# explicit nested M1 controls. References are supplied by the caller so they
# can be shared across seasons with identical M1 controls.
.nested_m1_cache_season <- function(data, m0, m1, seasons, timing_mode,
                                    m1_params = NULL, reference = NULL,
                                    excluded_sets = NULL) {
  seasons <- sort(unique(as.character(seasons)))
  excluded_sets <- excluded_sets %||% .nested_exclusion_sets(seasons)
  excluded_sets <- lapply(excluded_sets, function(x) {
    sort(unique(as.character(x)))
  })
  keys <- vapply(excluded_sets, .m1_exclusion_key, character(1))
  reference <- reference %||% .m1_heldout_references(
    m1, seasons,
    timing_mode = timing_mode, excluded_sets = excluded_sets,
    params = m1_params
  )
  control <- .nested_m1_control(m1_params)
  m0_params <- .nested_m0_params(m0)
  predictions <- stats::setNames(lapply(seq_along(keys), function(i) {
    excluded <- excluded_sets[[i]]
    ref_i <- reference[[keys[[i]]]]
    do.call(
      m1_walkforward_multi,
      c(
        list(
          allD = data,
          ref = ref_i$ref,
          hyper = ref_i$hyper,
          params = m0_params,
          seasons = excluded,
          season_references = stats::setNames(
            rep(list(ref_i), length(excluded)), excluded
          )
        ),
        control,
        list(parallel = FALSE, verbose = FALSE, timing_mode = timing_mode)
      )
    )
  }), keys)
  list(
    references = reference,
    predictions = predictions,
    excluded_sets = stats::setNames(excluded_sets, keys),
    reference_fit_count = length(reference),
    reference_keys = keys
  )
}

# Fully nested upstream selection for the gate. For each gate season `s` this
# re-runs, on the seasons other than `s` only, the same M0 selection the outer
# fold used. When the recipe supplies a multi-value M1 grid it also re-runs M1
# selection. Fixed (single-value) axes are passed through unchanged.
.nested_upstream_selection <- function(data, training_seasons, exclude = character(0),
                                       holdout = character(0),
                                       m0_grid, m0_flag_args, manual_labels,
                                       m1_grid, m1_params,
                                       m1_min_gain = 0.05,
                                       m1_hard_caps = default_m1_hard_caps(),
                                       m1_prefer_simpler = TRUE,
                                       m0_max_rounds = .default_boundary_round_limits()[["M0"]],
                                       m1_max_rounds = .default_boundary_round_limits()[["M1"]],
                                       m0_expansion_steps = NULL,
                                       m1_expansion_steps = .default_m1_expansion_steps(),
                                       timing_mode = "legacy",
                                       timing_targets = NULL,
                                       n_cores = 1L, verbose = FALSE) {
  data <- as.data.frame(data)
  training_seasons <- sort(unique(as.character(training_seasons)))
  if (length(training_seasons) < 2L) {
    stop("Fully nested upstream selection requires at least two gate seasons.",
      call. = FALSE
    )
  }
  nested_m1 <- is.data.frame(m1_grid) && nrow(as.data.frame(m1_grid)) > 1L
  m0_by_season <- stats::setNames(vector("list", length(training_seasons)), training_seasons)
  m1_by_season <- stats::setNames(vector("list", length(training_seasons)), training_seasons)
  m0_params_by_season <- stats::setNames(vector("list", length(training_seasons)), training_seasons)
  m0_boundaries_by_season <- stats::setNames(vector("list", length(training_seasons)), training_seasons)
  m1_boundaries_by_season <- stats::setNames(vector("list", length(training_seasons)), training_seasons)
  for (season in training_seasons) {
    season_data <- data[as.character(data$season) != season, , drop = FALSE]
    selection <- validate_season_selection(
      season_data,
      training_seasons = setdiff(training_seasons, season),
      exclude_seasons = exclude,
      holdout_seasons = holdout,
      application_seasons = character(0)
    )
    labels <- manual_labels
    if (!is.null(names(manual_labels))) {
      labels <- manual_labels[names(manual_labels) != season]
    }
    m0_life <- .nested_selection_lifecycle(
      stage = "M0", initial_grid = m0_grid, max_rounds = m0_max_rounds,
      tune = function(current_grid, attempt, previous) {
        tune_m0(
          season_data,
          grid = current_grid,
          manual_labels = labels,
          flag_args = m0_flag_args,
          n_cores = n_cores,
          verbose = verbose,
          selection = selection,
          timing_truth = timing_targets,
          timing_mode = timing_mode,
          previous_results = if (attempt == 1L) {
            NULL
          } else {
            previous$tuning %||% previous
          }
        )
      },
      plan = function(x, current_grid, attempt) {
        if (!inherits(x, "page_m0_tuning")) {
          plan <- tryCatch(
            boundary_action_plan(
              x,
              stage = "M0", steps = m0_expansion_steps
            ),
            error = function(e) NULL
          )
          if (!is.null(plan)) {
            return(plan)
          }
          return(structure(list(
            stage = "M0", settled = TRUE,
            final_boundary_report = data.frame(), unresolved = data.frame(),
            next_grid = NULL
          ), class = "page_boundary_action_plan"))
        }
        boundary_action_plan(
          x,
          stage = "M0", steps = m0_expansion_steps
        )
      },
      validate = function(x, current_grid) {
        if (inherits(x, "page_m0_tuning")) {
          validate_m0_tuning(x, grid = current_grid, check_boundaries = TRUE)
        } else {
          x
        }
      }
    )
    m0_tuning <- m0_life$tuning
    m0_boundaries_by_season[[season]] <- m0_life$history
    frozen_m0 <- freeze_m0(
      fit_m0(
        season_data,
        selection,
        config = m0_tuning$best_params,
        manual_labels = labels,
        flag_args = m0_flag_args,
        timing_truth = timing_targets
      ),
      tuning = m0_tuning
    )
    m0_by_season[[season]] <- frozen_m0
    m0_params_by_season[[season]] <- .nested_m0_params(frozen_m0)
    if (nested_m1) {
      m1_life <- .nested_selection_lifecycle(
        stage = "M1", initial_grid = m1_grid, max_rounds = m1_max_rounds,
        tune = function(current_grid, attempt, previous) {
          tune_m1(
            season_data,
            m0 = frozen_m0,
            m1 = list(m1_params = m1_params),
            grid = current_grid,
            n_cores = n_cores,
            verbose = verbose,
            selection = selection,
            manual_labels = labels,
            timing_truth = timing_targets,
            timing_mode = timing_mode
          )
        },
        plan = function(x, current_grid, attempt) {
          x$hard_caps <- m1_hard_caps
          if (!inherits(x, "page_m1_tuning")) {
            plan <- tryCatch(
              boundary_action_plan(
                x,
                stage = "M1", hard_caps = m1_hard_caps,
                m1_min_gain = m1_min_gain,
                m1_prefer_simpler = m1_prefer_simpler,
                steps = m1_expansion_steps
              ),
              error = function(e) NULL
            )
            if (!is.null(plan)) {
              return(plan)
            }
            return(structure(list(
              stage = "M1", settled = TRUE,
              final_boundary_report = data.frame(), unresolved = data.frame(),
              next_grid = NULL
            ), class = "page_boundary_action_plan"))
          }
          boundary_action_plan(
            x,
            stage = "M1", hard_caps = m1_hard_caps,
            m1_min_gain = m1_min_gain,
            m1_prefer_simpler = m1_prefer_simpler,
            steps = m1_expansion_steps
          )
        },
        validate = function(x, current_grid) {
          if (!inherits(x, "page_m1_tuning")) {
            return(x)
          }
          x$hard_caps <- m1_hard_caps
          m1_selection <- select_m1_candidate(
            x,
            min_gain = m1_min_gain,
            prefer_simpler = m1_prefer_simpler, hard_caps = m1_hard_caps
          )
          x$best <- m1_selection$selected
          x$m1_selection <- m1_selection
          validate_m1_tuning(
            x,
            check_boundaries = TRUE, hard_caps = m1_hard_caps
          )
        }
      )
      m1_tuning <- m1_life$tuning
      m1_boundaries_by_season[[season]] <- m1_life$history
      m1_by_season[[season]] <- .m1_params_from_tuning(m1_params, m1_tuning)
    } else {
      m1_by_season[[season]] <- m1_params
    }
  }
  list(
    m0 = m0_by_season,
    m1_params = m1_by_season,
    m0_params = m0_params_by_season,
    boundaries = list(m0 = m0_boundaries_by_season, m1 = m1_boundaries_by_season),
    nested_m1 = nested_m1,
    axes = c("m0", if (nested_m1) "m1"),
    provenances = list(
      m0 = "nested M0 grid selection on seasons excluding the gate season",
      m1 = if (nested_m1) {
        "nested M1 grid selection on seasons excluding the gate season"
      } else {
        "M1 recipe axis fixed (single-value grid); outer selected M1 controls passed through"
      }
    )
  )
}

# Fully nested gate M2 selection. Runs the same shared selection procedure as
# the outer search on rows whose M1 features exclude the gate season, using the
# recipe's original (pre-expansion) grid. No object derived from outer scores
# may enter: the expanded outer grid, stage-B membership, and rankings are
# deliberately not referenced.
.nested_gate_select_config <- function(tuning, training_rows,
                                       training_seasons = NULL,
                                       row_weights = NULL,
                                       grid = NULL,
                                       expansion = NULL,
                                       alpha_state = NULL,
                                       gamma = NULL,
                                       scored_seasons_by_horizon = NULL) {
  training_rows <- as.data.frame(training_rows)
  if (!nrow(training_rows)) {
    stop("Fully nested M2 gate has no training rows.", call. = FALSE)
  }
  training_seasons <- sort(unique(as.character(
    training_seasons %||% training_rows$season
  )))
  recipe_grid <- grid %||% tuning$recipe_grid
  if (is.null(recipe_grid)) {
    stop("Fully nested M2 gate requires the recipe's original M2 grid.",
      call. = FALSE
    )
  }
  grid <- as.data.frame(recipe_grid)
  if (!nrow(grid)) {
    stop("Fully nested M2 gate requires a non-empty M2 candidate grid.",
      call. = FALSE
    )
  }
  n <- nrow(training_rows)
  if (is.null(row_weights)) row_weights <- rep(1, n)
  row_weights <- as.numeric(row_weights)
  if (length(row_weights) != n) {
    stop("Nested gate scoring weights must be one per training row.", call. = FALSE)
  }
  row_weights[!is.finite(row_weights)] <- 0
  score_scale <- tuning$scoring$score_scale %||% "equal_week"
  nll_primary <- if (identical(score_scale, "equal_week")) {
    "nll_equal_week"
  } else {
    "nll_test_count"
  }
  mae_primary <- if (identical(score_scale, "equal_week")) {
    "mae_equal_week"
  } else {
    "mae_test_count"
  }
  alpha_state <- alpha_state %||% tuning$alpha_state %||%
    m2_subset_config()$alpha_state
  gamma <- gamma %||% (if ("gamma" %in% names(grid)) {
    grid$gamma[1L]
  } else {
    m2_subset_config()$gamma
  })
  if (is.null(scored_seasons_by_horizon)) {
    scored_seasons_by_horizon <- lapply(1:2, function(h) {
      idx <- as.integer(training_rows$h) == h
      w <- row_weights[idx]
      keep <- is.finite(w) & w > 0
      sort(unique(as.character(training_rows$season[idx][keep])))
    })
    names(scored_seasons_by_horizon) <- as.character(1:2)
  }
  expansion <- expansion %||% list(enabled = FALSE)
  max_rounds <- if (isTRUE(expansion$enabled)) {
    expansion$max_rounds %||% 1L
  } else {
    1L
  }
  as_gate_tuning <- function(core) {
    out <- list(
      family = m2_subset_family(), grid = core$grid, scores = core$scores,
      summary = core$summary, selected = core$selected,
      selected_config = core$selected_config, best_spec_id = core$best_spec_id,
      alpha_state = alpha_state, min_nll_gain = expansion$min_nll_gain %||%
        default_m2_nll_gain_caps(), coverage = core$coverage,
      recipe_grid = grid
    )
    # A real outer tuning object carries the provenance required by the public
    # M2 validator.  Keep the lightweight shape used by internal synthetic
    # callers, while validating the governed path whenever that provenance is
    # available.
    if (inherits(tuning, "page_m2_subset_tuning")) {
      out$selection <- tuning$selection
      out$selection$training_seasons <- training_seasons
      out$data_id <- digest::digest(training_rows)
      out$training_rows <- training_rows
      out$m1_train_preds <- training_rows[, c(
        "season", "eval_weekF", "target_weekF", "h", "forecast_available",
        "unavailable_reason"
      ), drop = FALSE]
      out$m1_train_preds$m1_p_hat <- training_rows$m1_p
      out$declaration_provenance <- tuning$declaration_provenance %||%
        "nested gate rows"
      out$scoring <- tuning$scoring %||% list()
      # The gate trains on the s-excluded rows passed to this function. Its
      # scored-season metadata must describe this gate dataset, not the outer
      # tuning object's season universe.
      out$scoring$scored_seasons <- scored_seasons_by_horizon
    }
    class(out) <- c("page_m2_subset_tuning", "page_m2_tuning", "list")
    out
  }
  life <- .nested_selection_lifecycle(
    stage = "M2", initial_grid = grid, max_rounds = max_rounds,
    tune = function(current_grid, attempt, previous) {
      core <- .m2_subset_select_core(
        training_data = training_rows, row_weights = row_weights,
        grid = current_grid, training_seasons = training_seasons,
        scored_seasons_by_horizon = scored_seasons_by_horizon,
        nll_primary = nll_primary, mae_primary = mae_primary,
        alpha_state = alpha_state, gamma = gamma,
        label = "Nested gate M2 selection",
        evaluation_label = "nested"
      )
      as_gate_tuning(core)
    },
    plan = function(x, current_grid, attempt) {
      boundary_action_plan(
        x,
        stage = "M2", steps = expansion$steps,
        max_specs = nrow(x$grid) + (expansion$increment %||% 0L)
      )
    },
    validate = function(x, current_grid) {
      if (inherits(tuning, "page_m2_subset_tuning")) {
        validate_m2_tuning(
          x,
          check_boundaries = TRUE,
          min_nll_gain = expansion$min_nll_gain %||% default_m2_nll_gain_caps()
        )
      }
      x
    }
  )
  core <- life$tuning
  list(
    config = core$selected_config,
    selected_ids = stats::setNames(
      vapply(core$selected, function(x) as.character(x$id[1L]), character(1)),
      c("h1", "h2")
    ),
    grid = core$grid, scores = core$scores, selection = core,
    history = life$history, alpha_state = alpha_state, gamma = gamma
  )
}

.nested_inner_gate_rows <- function(tuning, seasons, data, m0, m1,
                                    timing_mode = "legacy",
                                    timing_truth = NULL,
                                    m2_recipe_grid = NULL,
                                    m2_expansion = NULL,
                                    m1_params = NULL,
                                    gate_nesting = c("conditional", "full"),
                                    upstream = NULL,
                                    m0_grid = NULL,
                                    m0_flag_args = NULL,
                                    manual_labels = NULL,
                                    m1_grid = NULL,
                                    m1_min_gain = 0.05,
                                    m1_hard_caps = default_m1_hard_caps(),
                                    m1_prefer_simpler = TRUE,
                                    m0_max_rounds = .default_boundary_round_limits()[["M0"]],
                                    m1_max_rounds = .default_boundary_round_limits()[["M1"]],
                                    m0_expansion_steps = NULL,
                                    m1_expansion_steps = .default_m1_expansion_steps(),
                                    exclude = character(0),
                                    holdout = character(0),
                                    n_cores = 1L,
                                    verbose = FALSE) {
  rows <- tuning$training_rows
  if (!is.data.frame(rows) || is.null(tuning$selected_config) ||
    !is.data.frame(data) || !is.list(m0) || !is.list(m1)) {
    stop("M2 tuning is missing training rows or its selected configuration.",
      call. = FALSE
    )
  }
  timing_mode <- match.arg(timing_mode, c("legacy", "fractional"))
  gate_nesting <- match.arg(gate_nesting)
  seasons <- sort(unique(as.character(seasons)))
  full <- identical(gate_nesting, "full")
  if (full) {
    if (is.null(upstream)) {
      upstream <- .nested_upstream_selection(
        data = data,
        training_seasons = seasons,
        exclude = exclude,
        holdout = holdout,
        m0_grid = m0_grid %||% .default_m0_grid(),
        m0_flag_args = m0_flag_args %||% .default_flag_args(),
        manual_labels = manual_labels %||% .default_manual_labels(),
        m1_grid = m1_grid %||% data.frame(),
        m1_params = m1_params,
        m1_min_gain = m1_min_gain,
        m1_hard_caps = m1_hard_caps,
        m1_prefer_simpler = m1_prefer_simpler,
        m0_max_rounds = m0_max_rounds,
        m1_max_rounds = m1_max_rounds,
        m0_expansion_steps = m0_expansion_steps,
        m1_expansion_steps = m1_expansion_steps,
        timing_mode = timing_mode,
        timing_targets = timing_truth,
        n_cores = n_cores,
        verbose = verbose
      )
    }
    excluded_sets <- .nested_exclusion_sets(seasons)
    ref_env <- new.env(parent = emptyenv())
    reference_for <- function(excluded, params) {
      exclusion_key <- .m1_exclusion_key(excluded)
      key <- digest::digest(list(params = params, exclusion = exclusion_key))
      if (is.null(ref_env[[key]])) {
        ref_env[[key]] <- .m1_heldout_references(
          m1, seasons,
          timing_mode = timing_mode,
          excluded_sets = list(as.character(excluded)), params = params
        )[[exclusion_key]]
      }
      ref_env[[key]]
    }
    cache_for <- function(season) {
      params <- upstream$m1_params[[season]] %||% m1_params
      needed <- c(
        list(season),
        lapply(setdiff(seasons, season), function(other) c(season, other))
      )
      needed_keys <- vapply(needed, .m1_exclusion_key, character(1))
      references <- stats::setNames(
        lapply(needed, reference_for, params = params), needed_keys
      )
      .nested_m1_cache_season(
        data, upstream$m0[[season]] %||% m0, m1, seasons, timing_mode,
        m1_params = params, reference = references, excluded_sets = needed
      )
    }
    audit_axes <- upstream$axes %||% "m0"
  } else {
    cache <- .nested_m1_cache(data, m0, m1, seasons, timing_mode,
      m1_params = m1_params
    )
    cache_for <- function(season) cache
    m0_params_by_season <- NULL
    audit_axes <- character(0)
  }
  pieces <- vector("list", length(seasons))
  selected_ids <- stats::setNames(vector("list", length(seasons)), seasons)
  coverage_rows <- vector("list", length(seasons))
  m0_params_used <- stats::setNames(vector("list", length(seasons)), seasons)
  for (season_index in seq_along(seasons)) {
    season <- seasons[[season_index]]
    season_cache <- cache_for(season)
    m0_season <- if (full) upstream$m0[[season]] %||% m0 else m0
    own_key <- .m1_exclusion_key(season)
    pair_preds <- lapply(setdiff(seasons, season), function(r) {
      key <- .m1_exclusion_key(c(r, season))
      season_cache$predictions[[key]][
        as.character(season_cache$predictions[[key]]$season) == r, ,
        drop = FALSE
      ]
    })
    gate_preds <- rbind(
      season_cache$predictions[[own_key]],
      do.call(rbind, pair_preds)
    )
    m0_params_used[[season]] <- .nested_m0_params(m0_season)
    prepared <- m2_subset_make_rows(
      data = data, m0 = m0_season, m1 = m1,
      m1_train_preds = gate_preds, seasons = seasons,
      alpha_state = tuning$alpha_state %||% m2_subset_config()$alpha_state,
      timing_mode = timing_mode,
      timing_truth = timing_truth
    )
    # Keep unavailable-row accounting instead of silently dropping it: the
    # audit records scheduled/available/unavailable counts per gate season.
    gate_available <- !is.na(prepared$data$forecast_available) &
      prepared$data$forecast_available
    coverage_rows[[season_index]] <- data.frame(
      season = season,
      scheduled_rows = nrow(prepared$data),
      available_rows = sum(gate_available),
      unavailable_rows = sum(!gate_available),
      heldout_scheduled_rows = sum(as.character(prepared$data$season) == season),
      heldout_available_rows = sum(
        as.character(prepared$data$season) == season & gate_available
      ),
      heldout_unavailable_rows = sum(
        as.character(prepared$data$season) == season & !gate_available
      ),
      stringsAsFactors = FALSE
    )
    train <- prepared$data[
      as.character(prepared$data$season) != season &
        prepared$data$forecast_available, ,
      drop = FALSE
    ]
    test <- prepared$data[
      as.character(prepared$data$season) == season &
        prepared$data$forecast_available, ,
      drop = FALSE
    ]
    if (!nrow(train) || !nrow(test)) {
      next
    }
    scoring_mode <- tuning$scoring$scoring %||% "page_v2"
    gate_w <- if (identical(scoring_mode, "page_v2") &&
      "weight_page_v2" %in% names(train)) {
      as.numeric(train$weight_page_v2)
    } else {
      .m2_subset_phase_weights(
        train,
        early_weight = tuning$scoring$early_weight %||% 1,
        early_max_t_since = tuning$scoring$early_max_t_since %||% 12,
        pre_ignition_weight = tuning$scoring$pre_ignition_weight %||% 0,
        late_weight = tuning$scoring$late_weight %||% 1
      )
    }
    gate_w[!is.finite(gate_w)] <- 0
    gate_scored_by_h <- lapply(1:2, function(h) {
      idx <- as.integer(train$h) == h
      w <- gate_w[idx]
      keep <- is.finite(w) & w > 0
      sort(unique(as.character(train$season[idx][keep])))
    })
    names(gate_scored_by_h) <- as.character(1:2)
    selected <- .nested_gate_select_config(
      tuning, train,
      training_seasons = setdiff(seasons, season),
      row_weights = gate_w,
      grid = m2_recipe_grid,
      expansion = m2_expansion,
      alpha_state = tuning$alpha_state,
      gamma = tuning$selected_config$gamma,
      scored_seasons_by_horizon = gate_scored_by_h
    )
    selected_ids[[season]] <- selected$selected_ids
    horizons <- sort(unique(as.integer(test$h)))
    by_horizon <- lapply(horizons, function(horizon) {
      spec <- selected$config[[paste0("h", horizon)]]
      if (is.null(spec)) {
        return(NULL)
      }
      fit <- m2_subset_fit(train, spec, gamma = selected$config$gamma)
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
        ignition_weekF = target$ignition_weekF,
        observed_peak_weekF = target$observed_peak_weekF,
        phase = target$phase,
        weight_page_v2 = target$weight_page_v2,
        weight_legacy = target$weight_legacy,
        stringsAsFactors = FALSE
      )
    })
    by_horizon <- by_horizon[!vapply(by_horizon, is.null, logical(1))]
    pieces[[season_index]] <- if (length(by_horizon)) {
      do.call(rbind, by_horizon)
    } else {
      NULL
    }
  }
  pieces <- pieces[!vapply(pieces, is.null, logical(1))]
  if (!length(pieces)) {
    stop("No inner-fold M1/M2 forecasts were available for the adoption gate.",
      call. = FALSE
    )
  }
  out <- do.call(rbind, pieces)
  rownames(out) <- NULL
  if (full) {
    reference_fit_count <- sum(
      vapply(ls(ref_env), function(k) !is.null(ref_env[[k]]), logical(1))
    )
    reference_fit_count_expected <- as.integer(length(ls(ref_env)))
    reference_keys <- ls(ref_env)
    reference_cache <- reference_keys
    reference_fit_strategy <- paste(
      "only singleton and gate-season pair references/walks are built,",
      "with references shared by nested M1 control digest"
    )
    m0_timing_source <- paste(
      "nested per-gate-season M0 detected timing (M0 re-selected without",
      "the gate season); no manual label enters gate features"
    )
    m1_parameter_source <- if (isTRUE(upstream$nested_m1)) {
      "nested per-gate-season M1 selection; curve, anchor, and hyperparameters rebuilt per exclusion set"
    } else {
      "outer selected M1 controls (M1 axis fixed); curve, anchor, and hyperparameters rebuilt per exclusion set"
    }
    m2_gate_parameter_source <- paste(
      "shared selection core run on s-excluded rows; outer recipe grid and",
      "alpha_state/gamma propagated; fully nested upstream selection (",
      paste(audit_axes, collapse = ", "), ")"
    )
    gate_nesting_label <- "fully nested upstream selection"
  } else {
    reference_fit_count <- cache$reference_fit_count
    reference_fit_count_expected <- cache$reference_fit_count_expected
    reference_keys <- cache$reference_keys
    reference_cache <- cache$excluded_sets
    reference_fit_strategy <- cache$reference_fit_strategy
    m0_timing_source <- "outer-fold selected M0 detected timing; no manual label enters gate features"
    m1_parameter_source <- "explicit outer-fold M1 controls; curve, anchor, and hyperparameters rebuilt per exclusion set"
    m2_gate_parameter_source <- paste(
      "shared selection core run on s-excluded rows; outer recipe grid and",
      "alpha_state/gamma propagated; conditional on upstream selection"
    )
    gate_nesting_label <- "conditional on upstream selection"
  }
  attr(out, "nested_audit") <- list(
    nested = TRUE,
    gate_nesting = gate_nesting,
    gate_nesting_label = gate_nesting_label,
    nested_upstream_axes = audit_axes,
    reference_fit_count = reference_fit_count,
    reference_fit_count_expected = reference_fit_count_expected,
    reference_fit_strategy = reference_fit_strategy,
    reference_keys = reference_keys,
    reference_cache = reference_cache,
    m0_timing_source = m0_timing_source,
    m1_parameter_source = m1_parameter_source,
    m2_gate_parameter_source = m2_gate_parameter_source,
    m0_params_by_season = m0_params_used,
    m2_recipe_grid_rows = if (is.data.frame(m2_recipe_grid)) nrow(m2_recipe_grid) else NA_integer_,
    m2_selected_ids_by_season = selected_ids,
    coverage = do.call(rbind, coverage_rows),
    coverage_denominators = list(
      whole_prepared_gate_dataset = c(
        scheduled_rows = "all prepared gate rows",
        available_rows = "all available prepared gate rows",
        unavailable_rows = "all unavailable prepared gate rows"
      ),
      heldout_season = c(
        heldout_scheduled_rows = "scheduled rows for the gate season",
        heldout_available_rows = "available rows for the gate season",
        heldout_unavailable_rows = "unavailable rows for the gate season"
      )
    )
  )
  out
}

.nested_m2_decision <- function(rows, early_weight, early_max_t_since,
                                min_gain, min_gain_by_horizon, confidence,
                                max_season_degradation,
                                pre_ignition_weight = 0, late_weight = 1,
                                denominator_col = NULL,
                                scoring = c("page_v2", "legacy_0_12")) {
  scoring <- match.arg(scoring)
  page <- identical(scoring, "page_v2") &&
    "weight_page_v2" %in% names(rows)
  effective_scoring <- if (page) "page_v2" else "legacy_0_12"
  decide_m2_vs_m1(
    rows,
    outcome_col = "outcome",
    m1_col = "m1_prediction",
    m2_col = "m2_prediction",
    season_col = "season",
    origin_col = "origin",
    target_col = "target",
    horizon_col = "horizon",
    phase_col = if (page) "phase" else NULL,
    t_since_col = if (page) NULL else "t_since_target",
    phase_break = if (page) NULL else early_max_t_since,
    phase_weights = c(
      pre_ignition = pre_ignition_weight,
      early = early_weight,
      late = late_weight
    ),
    denominator_col = denominator_col,
    min_gain = min_gain,
    min_gain_by_horizon = min_gain_by_horizon,
    confidence = confidence,
    max_season_degradation = max_season_degradation,
    scoring = effective_scoring,
    score_weight_col = if (page) "weight_page_v2" else NULL
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

# Output-only work must neither abort the primary fold nor consume its RNG.
.nested_shadow_attempt <- function(expr) {
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit(
    {
      if (had_seed) {
        assign(".Random.seed", seed, envir = .GlobalEnv)
      } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
        rm(".Random.seed", envir = .GlobalEnv)
      }
    },
    add = TRUE
  )
  tryCatch(force(expr), error = function(e) {
    list(
      status = paste0("failed:", conditionMessage(e)),
      m1_prediction_equal = e$m1_prediction_equal %||% NA
    )
  })
}

.nested_shadow_record <- function(shadow, artifact_dir) {
  saved <- .nested_shadow_attempt(.nested_save_rds(
    shadow[setdiff(names(shadow), "kit")], artifact_dir, "shadow_m2_status.rds"
  ))
  if (startsWith(saved$status, "failed:")) shadow$status <- saved$status
  shadow
}

.nested_shadow_match <- function(primary, shadow) {
  keys <- c("season", "origin", "target", "horizon")
  key <- function(rows) do.call(paste, c(rows[keys], sep = "\r"))
  primary_key <- key(primary)
  shadow_key <- key(shadow)
  if (anyNA(primary[keys]) || anyNA(shadow[keys]) ||
    anyDuplicated(primary_key) || anyDuplicated(shadow_key) ||
    !setequal(primary_key, shadow_key)) {
    stop("Shadow replay forecast keys differ from the primary replay.", call. = FALSE)
  }
  shadow <- shadow[match(primary_key, shadow_key), , drop = FALSE]
  if (!isTRUE(all.equal(primary$m1_prediction, shadow$m1_prediction,
    tolerance = 0, check.attributes = FALSE
  ))) {
    error <- simpleError("Shadow replay M1 predictions differ from the primary replay.")
    error$m1_prediction_equal <- FALSE
    stop(error)
  }
  shadow
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
#' @param shadow_m2 Logical; additionally fit and replay the tuned M2 candidate
#'   for output-only comparison when an outer fold keeps M1. Defaults to `TRUE`.
#'   Failures are recorded without failing the primary fold. Final all-season
#'   fits never build a shadow. `FALSE` preserves the original output schema.
#' @param gate_nesting Inner-gate nesting depth. `"full"` (default) re-runs
#'   selection, inside each gate season's excluded dataset, for every upstream
#'   axis the recipe actually tunes (M0 always; M1 only when its grid has more
#'   than one value) before re-running the full M2 selection procedure.
#'   `"conditional"` re-runs the full M2 selection procedure only and passes
#'   the outer fold's selected M0/M1 settings through unchanged; its evidence
#'   is labelled `"conditional on upstream selection"`. Both options use nested
#'   M1 references (rows of `r` exclude `r` and the gate season) and identical
#'   estimator settings, and both are recorded in run provenance and kit
#'   metadata.
#'
#' @return A `page_outer_training` object containing the season selection,
#'   tuning results, boundary histories, adoption evidence, frozen stages, and
#'   assembled kit. With `shadow_m2 = TRUE`, the returned `shadow_m2` contains
#'   a status and, when built, the shadow kit. Shadow evidence is saved in
#'   separate `shadow_m2_kit.rds` and `shadow_m2_status.rds` artifacts; the
#'   existing primary training artifact retains its original schema.
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
  scoring = c("page_v2", "legacy_0_12"),
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
  timing_mode = c("legacy", "fractional"),
  gate_nesting = c("full", "conditional"),
  shadow_m2 = TRUE
) {
  score_scale <- match.arg(score_scale)
  scoring <- match.arg(scoring)
  timing_mode <- match.arg(timing_mode)
  gate_nesting <- match.arg(gate_nesting)
  if (!is.logical(shadow_m2) || length(shadow_m2) != 1L || is.na(shadow_m2)) {
    stop("`shadow_m2` must be TRUE or FALSE.", call. = FALSE)
  }
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
    gate_nesting = gate_nesting,
    gate_nesting_label = if (identical(gate_nesting, "conditional")) {
      "conditional on upstream selection"
    } else {
      "fully nested upstream selection"
    },
    training_seasons = selection$training_seasons,
    exclude_seasons = selection$exclude_seasons,
    weighting = list(
      pre_ignition = pre_ignition_weight,
      early = early_weight,
      early_max_t_since = early_max_t_since,
      late = late_weight,
      scoring = scoring,
      page_scoring_weights = page_scoring_weights(),
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
      timing_mode = timing_mode,
      scoring = scoring,
      timing_truth = timing_targets
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
  m0_life <- .nested_selection_lifecycle(
    stage = "M0", initial_grid = m0_grid, max_rounds = rounds[["M0"]],
    tune = function(current_grid, attempt, previous) {
      tune_m0(
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
        previous_results = if (attempt == 1L) {
          NULL
        } else {
          previous$tuning %||% previous
        }
      )
    },
    plan = function(x, current_grid, attempt) {
      boundary_action_plan(x, stage = "M0", steps = m0_expansion_steps)
    },
    validate = function(x, current_grid) {
      validate_m0_tuning(x, grid = current_grid, check_boundaries = TRUE)
    },
    artifact_dir = artifact_dir
  )
  m0_tuning <- m0_life$tuning
  m0_history <- m0_life$history
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
  m1_life <- .nested_selection_lifecycle(
    stage = "M1", initial_grid = m1_grid, max_rounds = rounds[["M1"]],
    tune = function(current_grid, attempt, previous) {
      x <- tune_m1(
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
      x$hard_caps <- m1_hard_caps
      x
    },
    plan = function(x, current_grid, attempt) {
      boundary_action_plan(
        x,
        stage = "M1", hard_caps = m1_hard_caps,
        m1_min_gain = m1_min_gain,
        m1_prefer_simpler = m1_prefer_simpler,
        steps = m1_expansion_steps
      )
    },
    validate = function(x, current_grid) {
      m1_selection <- select_m1_candidate(
        x,
        min_gain = m1_min_gain,
        prefer_simpler = m1_prefer_simpler, hard_caps = m1_hard_caps
      )
      x$best <- m1_selection$selected
      x$m1_selection <- m1_selection
      validate_m1_tuning(
        x,
        check_boundaries = TRUE, hard_caps = m1_hard_caps
      )
    },
    artifact_dir = artifact_dir
  )
  m1_tuning <- m1_life$tuning
  m1_history <- m1_life$history
  m1_selection <- m1_tuning$m1_selection
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
  m1_train_preds <- NULL
  m2_life <- .nested_selection_lifecycle(
    stage = "M2", initial_grid = m2_grid, max_rounds = rounds[["M2"]],
    tune = function(current_grid, attempt, previous) {
      x <- tune_m2(
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
        scoring = scoring,
        score_scale = score_scale,
        m1_train_preds = m1_train_preds,
        n_cores = n_cores,
        verbose = verbose,
        timing_mode = timing_mode,
        timing_truth = timing_targets
      )
      m1_train_preds <<- x$m1_train_preds
      x$min_nll_gain <- m2_min_nll_gain
      x$recipe_grid <- as.data.frame(m2_grid)
      x
    },
    plan = function(x, current_grid, attempt) {
      .nested_save_csv(x$grid, artifact_dir, "m2_grid.csv")
      .nested_save_csv(x$scores, artifact_dir, "m2_fold_scores.csv")
      .nested_save_csv(x$summary, artifact_dir, "m2_summary.csv")
      boundary_action_plan(
        x,
        stage = "M2", steps = m2_expansion_steps,
        max_specs = nrow(x$grid) + m2_expansion_increment
      )
    },
    validate = function(x, current_grid) {
      validate_m2_tuning(
        x,
        check_boundaries = TRUE, min_nll_gain = m2_min_nll_gain
      )
    },
    artifact_dir = artifact_dir
  )
  m2_tuning <- m2_life$tuning
  m2_history <- m2_life$history

  m2_tuning$recipe_grid <- as.data.frame(m2_grid)
  inner_rows <- .nested_inner_gate_rows(
    m2_tuning, selection$training_seasons,
    data = data, m0 = m0, m1 = m1, timing_mode = timing_mode,
    timing_truth = timing_targets,
    m2_recipe_grid = m2_grid,
    m2_expansion = list(
      enabled = TRUE,
      steps = m2_expansion_steps,
      increment = m2_expansion_increment,
      max_rounds = rounds[["M2"]],
      min_nll_gain = m2_min_nll_gain
    ),
    m1_params = m1_config,
    gate_nesting = gate_nesting,
    m0_grid = m0_grid,
    m0_flag_args = m0_flag_args,
    manual_labels = manual_labels,
    m1_grid = m1_grid,
    m1_min_gain = m1_min_gain,
    m1_hard_caps = m1_hard_caps,
    m1_prefer_simpler = m1_prefer_simpler,
    m0_max_rounds = rounds[["M0"]],
    m1_max_rounds = rounds[["M1"]],
    m0_expansion_steps = m0_expansion_steps,
    m1_expansion_steps = m1_expansion_steps,
    exclude = selection$exclude_seasons,
    holdout = selection$holdout_seasons,
    n_cores = n_cores,
    verbose = verbose
  )
  inner_audit <- attr(inner_rows, "nested_audit") %||% list(
    nested = TRUE, reference_fit_count = NA_integer_,
    reference_keys = character()
  )
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
    denominator_col = score_denominators$primary,
    scoring = scoring
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
    denominator_col = score_denominators$sensitivity,
    scoring = scoring
  )
  selected_config <- m2_tuning$selected_config
  tuned_spec_id <- m2_tuning$best_spec_id
  if (shadow_m2) shadow_tuning <- m2_tuning
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
  .nested_save_rds(inner_audit, artifact_dir, "inner_gate_audit.rds")

  if (shadow_m2) {
    shadow <- .nested_shadow_attempt({
      if (final_fit) {
        list(status = "final_fit_no_shadow")
      } else if (identical(applied$action, "use_m2")) {
        list(status = "not_needed_use_m2")
      } else if (all(vapply(
        shadow_tuning$selected_config[c("h1", "h2")],
        function(x) identical(x$id, m2_subset_spec()$id), logical(1)
      ))) {
        list(status = "not_needed_tuned_all_off")
      } else {
        shadow_stage <- freeze_m2(fit_m2(
          data,
          selection,
          m0 = m0,
          m1 = m1,
          config = shadow_tuning$selected_config,
          family = m2_family,
          m1_train_preds = shadow_tuning$m1_train_preds,
          n_cores = n_cores,
          verbose = verbose,
          timing_mode = timing_mode,
          timing_truth = timing_targets
        ), tuning = shadow_tuning)
        shadow_kit <- assemble_kit(m0, m1, shadow_stage,
          best_spec_id = tuned_spec_id
        )
        shadow_kit$gate_nesting <- gate_nesting
        validate_page_kit(shadow_kit)
        .nested_save_rds(shadow_kit, artifact_dir, "shadow_m2_kit.rds")
        list(status = "built", kit = shadow_kit, tuned_spec_id = tuned_spec_id)
      }
    })
  }

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
  kit$gate_nesting <- gate_nesting
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
      applied = applied,
      nesting = gate_nesting,
      nesting_label = protocol$gate_nesting_label,
      nested_audit = inner_audit
    ),
    stages = list(m0 = m0, m1 = m1, m2 = m2),
    timing_labels_v2 = supplied_timing_labels,
    timing_labels_v2_training = timing_labels,
    kit = kit
  ), class = c("page_outer_training", "list"))
  .nested_save_rds(result, artifact_dir, "outer_training_result.rds")
  if (shadow_m2) result$shadow_m2 <- .nested_shadow_record(shadow, artifact_dir)
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

.nested_scoring_export <- function(rows, data, timing_labels = NULL) {
  timing_truth <- if (!is.null(timing_labels)) {
    tryCatch(as_timing_targets_v2(timing_labels), error = function(e) NULL)
  } else {
    NULL
  }
  meta <- .page_scoring_metadata(data, timing_truth = timing_truth)
  refs <- unique(meta[, c("season", "ignition_weekF", "observed_peak_weekF"), drop = FALSE])
  refs <- refs[!duplicated(refs$season), , drop = FALSE]
  out <- rows
  out$origin_weekF <- as.numeric(out$origin)
  out$target_weekF <- as.numeric(out$target)
  out$h <- as.integer(out$horizon)
  out$ignition_weekF <- refs$ignition_weekF[match(out$season, refs$season)]
  out$observed_peak_weekF <- refs$observed_peak_weekF[match(out$season, refs$season)]
  phase <- page_phase_weights(
    out, page_scoring_weights(),
    season_col = "season", target_col = "target_weekF",
    ignition_col = "ignition_weekF", peak_col = "observed_peak_weekF",
    allow_censored = TRUE
  )
  out$phase <- phase$phase
  out$weight_page_v2 <- phase$weight
  out$weight_legacy <- .m2_subset_phase_weights(
    data.frame(u = out$t_since_target - out$h, h = out$h),
    early_weight = 2, early_max_t_since = 12,
    pre_ignition_weight = 0, late_weight = 1
  )
  out$forecast_available <- if ("forecast_available" %in% names(rows)) {
    as.logical(rows$forecast_available)
  } else {
    rep(TRUE, nrow(out))
  }
  out$forecast_available[is.na(out$forecast_available)] <- FALSE
  out$unavailable_reason <- if ("unavailable_reason" %in% names(rows)) {
    as.character(rows$unavailable_reason)
  } else {
    rep(NA_character_, nrow(out))
  }
  out$y <- as.numeric(out$outcome * out$N_lead)
  out$N <- as.numeric(out$N_lead)
  out$m1_p <- as.numeric(out$m1_prediction)
  out$gate_applied_p <- as.numeric(out$m2_prediction)
  out$shadow_m2_p <- if ("m2_shadow_prediction" %in% names(out)) {
    as.numeric(out$m2_shadow_prediction)
  } else if ("shadow_m2_p" %in% names(out)) {
    as.numeric(out$shadow_m2_p)
  } else {
    rep(NA_real_, nrow(out))
  }
  dates <- if ("week_start_date" %in% names(data)) data$week_start_date else NULL
  if (!is.null(dates)) {
    key <- paste(as.character(data$season), as.numeric(data$weekF), sep = "\r")
    lookup <- stats::setNames(as.character(dates), key)
    out$origin_week_start_date <- unname(lookup[paste(out$season, out$origin_weekF, sep = "\r")])
    out$target_week_start_date <- unname(lookup[paste(out$season, out$target_weekF, sep = "\r")])
  } else {
    out$origin_week_start_date <- NA_character_
    out$target_week_start_date <- NA_character_
  }
  out
}

#' Build the manuscript per-row export from the scheduled replay ledger
#'
#' Retains every scheduled origin/horizon, including rows whose forecast was
#' unavailable, and carries `forecast_available`/`unavailable_reason` so the
#' missing-forecast accounting is not lost. Returns `NULL` when the replay has
#' no ledger (synthetic callers), so callers fall back to matched rows.
#' @keywords internal
.nested_ledger_export <- function(replay, data, timing_labels = NULL) {
  ledger <- replay$forecast_ledger
  if (!is.data.frame(ledger) || !nrow(ledger) ||
    !all(c("weekF", "lead", "target_weekF", "scorable") %in% names(ledger))) {
    return(NULL)
  }
  rows <- data.frame(
    season = as.character(ledger$season),
    origin = as.numeric(ledger$weekF),
    target = as.numeric(ledger$target_weekF),
    horizon = as.integer(ledger$lead),
    outcome = as.numeric(ledger$p_obs),
    m1_prediction = if ("m1_p" %in% names(ledger)) ledger$m1_p else NA_real_,
    m2_prediction = if ("p_hat" %in% names(ledger)) ledger$p_hat else NA_real_,
    t_since_target = as.numeric(ledger$t_since) + as.numeric(ledger$lead),
    N_lead = if ("N_lead" %in% names(ledger)) ledger$N_lead else NA_real_,
    forecast_available = if ("forecast_available" %in% names(ledger)) {
      as.logical(ledger$forecast_available)
    } else {
      as.logical(ledger$scorable)
    },
    unavailable_reason = if ("unavailable_reason" %in% names(ledger)) {
      as.character(ledger$unavailable_reason)
    } else {
      rep(NA_character_, nrow(ledger))
    },
    stringsAsFactors = FALSE
  )
  .nested_scoring_export(rows, data, timing_labels = timing_labels)
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
#'   matched forecast rows, and phase-weighted M2-versus-M1 metrics. Before
#'   matching, the replay is checked for forecast-key completeness and
#'   consistency against its independent evaluation schedule; unmatched keys
#'   or matched rows with missing M1/M2 values are errors. With `shadow_m2 = TRUE`,
#'   predictions also contain `m2_shadow_prediction` and `shadow_status`, and the
#'   result includes `shadow_metrics` and `shadow_m1_prediction_equal`. Failed
#'   or absent shadows have missing predictions and no shadow metrics. Shadow
#'   metrics are also saved in `outer_shadow_metrics.rds`.
#' @export
run_outer_fold <- function(data, holdout, artifact_dir = NULL,
                           checkpoint_dir = NULL, timing_labels = NULL,
                           timing_mode = c("legacy", "fractional"),
                           gate_nesting = c("full", "conditional"),
                           shadow_m2 = TRUE, ...) {
  timing_mode <- match.arg(timing_mode)
  gate_nesting <- match.arg(gate_nesting)
  artifact_dir <- .nested_dir(artifact_dir)
  checkpoint_dir <- .nested_dir(checkpoint_dir)
  training <- train_outer_fold(
    data,
    holdout = holdout,
    artifact_dir = artifact_dir,
    checkpoint_dir = checkpoint_dir,
    timing_labels = timing_labels,
    timing_mode = timing_mode,
    gate_nesting = gate_nesting,
    shadow_m2 = shadow_m2,
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
  rows <- .nested_scoring_export(
    .nested_replay_rows(replay), data,
    timing_labels = training$protocol$timing_labels_v2
  )
  weighting <- training$protocol$weighting
  adoption <- training$protocol$adoption
  scoring <- weighting$scoring %||% "page_v2"
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
    denominator_col = score_denominators$primary,
    scoring = scoring
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
    denominator_col = score_denominators$sensitivity,
    scoring = scoring
  )
  result <- structure(list(
    holdout = holdout,
    gate_nesting = gate_nesting,
    training = training,
    replay = replay,
    predictions = rows,
    metrics = metrics,
    sensitivity = sensitivity,
    sensitivity_scale = score_denominators$sensitivity_scale
  ), class = c("page_outer_fold_result", "list"))
  if (shadow_m2) {
    shadow <- training$shadow_m2 %||% list(status = "absent")
    comparison <- .nested_shadow_attempt({
      shadow_rows <- NULL
      m1_equal <- NA
      if (identical(shadow$status, "built")) {
        shadow_replay <- replay_season_holdout(
          shadow$kit, data,
          season = holdout,
          kit_compatibility = "strict", timing_mode = timing_mode
        )
        if (!identical(as.character(shadow_replay$status), "unseen_replay_complete")) {
          stop("Shadow replay did not complete under the unseen-season contract.",
            call. = FALSE
          )
        }
        shadow_rows <- .nested_scoring_export(
          .nested_shadow_match(rows, .nested_replay_rows(shadow_replay)),
          data,
          timing_labels = training$protocol$timing_labels_v2
        )
        m1_equal <- TRUE
      } else if (shadow$status %in% c("not_needed_use_m2", "not_needed_tuned_all_off")) {
        shadow_rows <- rows
        m1_equal <- TRUE
      }
      shadow_metrics <- if (!is.null(shadow_rows)) {
        .nested_m2_decision(
          shadow_rows,
          early_weight = weighting$early,
          early_max_t_since = weighting$early_max_t_since,
          min_gain = adoption$min_gain,
          min_gain_by_horizon = adoption$min_gain_by_horizon,
          confidence = adoption$confidence,
          max_season_degradation = adoption$max_season_degradation,
          pre_ignition_weight = weighting$pre_ignition,
          late_weight = weighting$late,
          denominator_col = score_denominators$primary,
          scoring = scoring
        )
      } else {
        NULL
      }
      .nested_save_rds(shadow_metrics, artifact_dir, "outer_shadow_metrics.rds")
      list(
        status = shadow$status, m1_prediction_equal = m1_equal,
        prediction = if (is.null(shadow_rows)) rep(NA_real_, nrow(rows)) else shadow_rows$m2_prediction,
        metrics = shadow_metrics
      )
    })
    if (startsWith(comparison$status, "failed:")) {
      .nested_shadow_attempt(.nested_save_rds(
        NULL, artifact_dir, "outer_shadow_metrics.rds"
      ))
    }
    status <- .nested_shadow_record(list(
      status = comparison$status,
      m1_prediction_equal = comparison$m1_prediction_equal %||% NA
    ), artifact_dir)
    rows$m2_shadow_prediction <- comparison$prediction %||% rep(NA_real_, nrow(rows))
    rows$shadow_status <- status$status
    result$predictions <- rows
    result["shadow_metrics"] <- list(comparison$metrics)
    result$shadow_status <- status$status
    result$shadow_m1_prediction_equal <- status$m1_prediction_equal
  }
  # Per-row manuscript export is written after shadow predictions are known,
  # from the scheduled forecast ledger, retaining unavailable rows with their
  # forecast_available/unavailable_reason accounting.
  export_rows <- .nested_ledger_export(
    replay, data,
    timing_labels = training$protocol$timing_labels_v2
  )
  if (is.null(export_rows)) export_rows <- rows
  if (shadow_m2) {
    rk <- paste(rows$season, rows$origin, rows$target, rows$horizon, sep = "\r")
    ek <- paste(export_rows$season, export_rows$origin, export_rows$target,
      export_rows$horizon,
      sep = "\r"
    )
    export_rows$m2_shadow_prediction <- (
      comparison$prediction %||% rep(NA_real_, nrow(rows))
    )[match(ek, rk)]
    export_rows$shadow_m2_p <- export_rows$m2_shadow_prediction
    export_rows$shadow_status <- status$status
  } else {
    export_rows$m2_shadow_prediction <- NA_real_
    export_rows$shadow_m2_p <- NA_real_
    export_rows$shadow_status <- NA_character_
  }
  .nested_save_csv(export_rows, artifact_dir, "outer_predictions_per_row.csv")
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
#' replay. Completed fold artifacts may be reused when `resume = TRUE`. Every
#' fold replay must pass the forecast-key completeness and consistency checks
#' before its rows contribute to the aggregate.
#'
#' @param data Canonical multi-season surveillance data.
#' @param holdouts Seasons to hold out in turn. Defaults to every season not in
#'   `exclude`.
#' @param exclude Fixed excluded seasons. Defaults to the protocol exclusions
#'   `"2011-12"`, `"2015-16"`, `"2020-21"`, and `"2021-22"`.
#' @param artifact_dir Parent directory for one subdirectory per outer fold.
#' @param checkpoint_dir Optional parent checkpoint directory.
#' @param resume Reuse a completed `outer_fold_result.rds` when its recorded
#'   holdout matches the requested fold. Legacy results without shadow fields
#'   load with shadow status `absent`; they are not refit to add shadow evidence.
#' @param timing_labels Optional timing-v2 label object or list of objects;
#'   passed to each outer fold after that fold's holdout is isolated.
#' @param gate_nesting Inner-gate nesting depth forwarded to every outer fold.
#'   See `train_outer_fold()`; defaults to `"full"`.
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
  gate_nesting = c("full", "conditional"),
  ...
) {
  gate_nesting <- match.arg(gate_nesting)
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
  dots$gate_nesting <- gate_nesting
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
    if (!identical(dots$shadow_m2, FALSE) && is.null(prior$shadow_status)) {
      prior$shadow_status <- "absent"
      prior["shadow_metrics"] <- list(NULL)
      prior$shadow_m1_prediction_equal <- NA
      prior$predictions$m2_shadow_prediction <- rep(NA_real_, nrow(prior$predictions))
      prior$predictions$shadow_status <- "absent"
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
    gate_nesting = gate_nesting,
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
