# Gate nesting depth (`gate_nesting`) regression tests. Expensive stage
# fitting/tuning is mocked; the nesting wiring and provenance are real.

.nestopt_fixture <- function() {
  seasons <- c("A", "B", "C")
  data <- do.call(rbind, lapply(seq_along(seasons), function(i) {
    data.frame(
      season = seasons[[i]], weekF = 1:10,
      y = 5L + i, N = 100L, stringsAsFactors = FALSE
    )
  }))
  aligned <- data
  aligned$iWeek <- 3L
  list(
    seasons = seasons,
    data = data,
    m0 = list(best_params = list(outer = TRUE)),
    m1 = list(
      aligned_train = aligned,
      m1_params = list(k_ref = 3L, ref_method = "fs")
    ),
    tuning = list(
      training_rows = data.frame(season = seasons),
      selected_config = PAGe:::m2_subset_config(),
      grid = PAGe:::m2_subset_grid(k_values = c(0L, 3L)),
      alpha_state = 0.2,
      scoring = list(
        scoring = "legacy_0_12", score_scale = "equal_week",
        early_weight = 1, early_max_t_since = 12,
        pre_ignition_weight = 0, late_weight = 1
      )
    )
  )
}

.nestopt_mocks <- function(expr, seasons, tune_log, wf_log, ...) {
  local_mocked_bindings(
    tune_m0 = function(allD, ...) {
      present <- sort(unique(as.character(allD$season)))
      excluded <- setdiff(seasons, present)
      tune_log$items[[length(tune_log$items) + 1L]] <- list(
        excluded = excluded,
        seasons = present
      )
      list(best_params = list(marker = excluded))
    },
    fit_m0 = function(data, selection, config, ...) {
      list(best_params = config, selection = selection)
    },
    freeze_m0 = function(x, ...) x,
    tune_m1 = function(allD, m0, grid, ...) {
      present <- sort(unique(as.character(allD$season)))
      list(
        best = data.frame(
          k_ref = 25L,
          excluded = paste(setdiff(seasons, present), collapse = ","),
          stringsAsFactors = FALSE
        )
      )
    },
    select_m1_candidate = function(x, ...) list(selected = x$best),
    .m1_params_from_tuning = function(base, tuning) {
      base$k_ref <- as.integer(tuning$best$k_ref[1L])
      base
    },
    .m1_heldout_references = function(m1, seasons, timing_mode,
                                      excluded_sets = NULL, params = NULL) {
      keys <- vapply(excluded_sets, PAGe:::.m1_exclusion_key, character(1))
      stats::setNames(lapply(excluded_sets, function(excluded) {
        list(
          ref = list(key = PAGe:::.m1_exclusion_key(excluded)),
          hyper = list(), excluded_seasons = sort(excluded)
        )
      }), keys)
    },
    m1_walkforward_multi = function(seasons, season_references, ...) {
      dots <- list(...)
      wf_log$items[[length(wf_log$items) + 1L]] <- list(
        seasons = as.character(seasons),
        params = dots$params,
        m1 = season_references
      )
      do.call(rbind, lapply(seasons, function(s) {
        d <- expand.grid(eval_weekF = 4:8, h = 1:2)
        d$season <- s
        d$target_weekF <- d$eval_weekF + d$h
        d$m1_p_hat <- 0.2 + 0.01 * d$h
        d$forecast_available <- TRUE
        d$unavailable_reason <- NA_character_
        d
      }))
    },
    m2_subset_fit = function(data, spec, gamma = 1.4, ...) {
      list(
        spec = spec, feature_ranges = list(),
        coefficient = mean(data$y_lead)
      )
    },
    m2_subset_predict = function(fit, target, ...) {
      list(p_hat = rep(0.2 + fit$coefficient / 1000, nrow(target)))
    },
    run_ignition_weekly = function(currentSeason, params = list(),
                                   start_week = 5L, timing_mode = "legacy", ...) {
      list(
        ign_week_locked = 3L, iWeek_hat_locked = 3L,
        ign_week_lockedF = 3, iWeek_hat_lockedF = 3,
        detection_failed = FALSE,
        df = data.frame(
          weekF = currentSeason$weekF, ignite_ok_now = TRUE
        )
      )
    },
    .package = "PAGe"
  )
  force(expr)
}

test_that("gate_nesting defaults to full and rejects invalid values", {
  expect_identical(
    eval(formals(PAGe::train_outer_fold)$gate_nesting)[[1L]], "full"
  )
  expect_identical(
    eval(formals(PAGe::run_outer_fold)$gate_nesting)[[1L]], "full"
  )
  expect_identical(
    eval(formals(PAGe::nested_season_evaluation)$gate_nesting)[[1L]], "full"
  )
  expect_error(
    PAGe::train_outer_fold(data.frame(), gate_nesting = "nope"),
    "arg"
  )
  expect_error(
    PAGe::run_outer_fold(data.frame(), "A", gate_nesting = "nope"),
    "arg"
  )
  expect_error(
    PAGe::nested_season_evaluation(data.frame(), gate_nesting = "nope"),
    "arg"
  )
})

test_that("full re-selects M0 without each gate season", {
  fixture <- .nestopt_fixture()
  tune_log <- new.env(parent = emptyenv())
  tune_log$items <- list()
  wf_log <- new.env(parent = emptyenv())
  wf_log$items <- list()
  out <- NULL
  .nestopt_mocks(
    {
      out <- PAGe:::.nested_inner_gate_rows(
        fixture$tuning, fixture$seasons, fixture$data,
        fixture$m0, fixture$m1,
        m2_recipe_grid = fixture$tuning$grid,
        m1_params = list(k_ref = 3L),
        gate_nesting = "full",
        m0_grid = data.frame(x = 1),
        m0_flag_args = list(a = 1),
        manual_labels = stats::setNames(rep(1L, 3), fixture$seasons),
        m1_grid = data.frame(k_ref = 3L),
        exclude = character(), holdout = character(),
        n_cores = 1L, verbose = FALSE
      )
    },
    fixture$seasons,
    tune_log,
    wf_log
  )
  excluded <- sort(vapply(tune_log$items, function(x) x$excluded, character(1)))
  expect_identical(excluded, fixture$seasons)
  expect_true(all(vapply(
    tune_log$items,
    function(x) length(x$excluded) == 1L, logical(1)
  )))
  markers <- unique(vapply(wf_log$items, function(x) x$params$marker, character(1)))
  expect_setequal(markers, fixture$seasons)
  audit <- attr(out, "nested_audit")
  expect_identical(audit$gate_nesting, "full")
  expect_identical(audit$nested_upstream_axes, "m0")
  expect_match(audit$m2_gate_parameter_source, "fully nested")
})

test_that("conditional reuses the outer M0 and does not tune upstream", {
  fixture <- .nestopt_fixture()
  tune_log <- new.env(parent = emptyenv())
  tune_log$items <- list()
  wf_log <- new.env(parent = emptyenv())
  wf_log$items <- list()
  out <- NULL
  .nestopt_mocks(
    {
      out <- PAGe:::.nested_inner_gate_rows(
        fixture$tuning, fixture$seasons, fixture$data,
        fixture$m0, fixture$m1,
        m2_recipe_grid = fixture$tuning$grid,
        m1_params = list(k_ref = 3L),
        gate_nesting = "conditional",
        m0_grid = data.frame(x = 1),
        m0_flag_args = list(a = 1),
        manual_labels = stats::setNames(rep(1L, 3), fixture$seasons),
        m1_grid = data.frame(k_ref = 3L),
        exclude = character(), holdout = character(),
        n_cores = 1L, verbose = FALSE
      )
    },
    fixture$seasons,
    tune_log,
    wf_log
  )
  expect_length(tune_log$items, 0L)
  expect_true(all(vapply(
    wf_log$items,
    function(x) identical(x$params, fixture$m0$best_params), logical(1)
  )))
  audit <- attr(out, "nested_audit")
  expect_identical(audit$gate_nesting, "conditional")
  expect_identical(audit$nested_upstream_axes, character(0))
  expect_match(audit$m2_gate_parameter_source, "conditional on upstream selection")
})

test_that("upstream selection nests M1 only when its grid is multi-value", {
  fixture <- .nestopt_fixture()
  m1_log <- new.env(parent = emptyenv())
  m1_log$items <- list()
  local_mocked_bindings(
    tune_m0 = function(allD, ...) {
      present <- sort(unique(as.character(allD$season)))
      list(best_params = list(marker = setdiff(fixture$seasons, present)))
    },
    fit_m0 = function(data, selection, config, ...) {
      list(best_params = config, selection = selection)
    },
    freeze_m0 = function(x, ...) x,
    tune_m1 = function(allD, m0, grid, ...) {
      present <- sort(unique(as.character(allD$season)))
      m1_log$items[[length(m1_log$items) + 1L]] <- list(
        excluded = setdiff(fixture$seasons, present),
        k_ref = m0$best_params$marker
      )
      list(best = data.frame(k_ref = 25L))
    },
    select_m1_candidate = function(x, ...) list(selected = x$best),
    .m1_params_from_tuning = function(base, tuning) {
      base$k_ref <- as.integer(tuning$best$k_ref[1L])
      base
    },
    .package = "PAGe"
  )
  single <- PAGe:::.nested_upstream_selection(
    fixture$data, fixture$seasons,
    m0_grid = data.frame(x = 1), m0_flag_args = list(a = 1),
    manual_labels = stats::setNames(rep(1L, 3), fixture$seasons),
    m1_grid = data.frame(k_ref = 3L),
    m1_params = list(k_ref = 3L)
  )
  expect_false(single$nested_m1)
  expect_identical(single$axes, "m0")
  expect_length(m1_log$items, 0L)

  multi <- PAGe:::.nested_upstream_selection(
    fixture$data, fixture$seasons,
    m0_grid = data.frame(x = 1), m0_flag_args = list(a = 1),
    manual_labels = stats::setNames(rep(1L, 3), fixture$seasons),
    m1_grid = data.frame(k_ref = c(20L, 30L)),
    m1_params = list(k_ref = 3L)
  )
  expect_true(multi$nested_m1)
  expect_identical(single$m0_params, multi$m0_params)
  excluded <- sort(vapply(m1_log$items, function(x) x$excluded, character(1)))
  expect_identical(excluded, fixture$seasons)
})

test_that("gate_nesting is recorded in provenance and kit metadata", {
  fixture <- .nestopt_fixture()
  tuning <- fixture$tuning
  tuning$m1_train_preds <- data.frame(season = c("A", "B"), carry = 1)
  tuning$recipe_grid <- tuning$grid
  m2_decision <- list(
    decision = "use_m2", reasons = character(),
    metrics = list(), seasons = list()
  )
  local_mocked_bindings(
    tune_m0 = function(...) list(best_params = list(ok = TRUE)),
    boundary_action_plan = function(...) list(settled = TRUE),
    validate_m0_tuning = function(...) NULL,
    fit_m0 = function(...) list(stage = "m0"),
    freeze_m0 = function(x, ...) x,
    tune_m1 = function(...) list(best = data.frame(k_ref = 25L)),
    select_m1_candidate = function(...) list(selected = data.frame(k_ref = 25L)),
    validate_m1_tuning = function(...) NULL,
    .m1_params_from_tuning = function(...) list(k_ref = 25L),
    fit_m1 = function(...) list(stage = "m1"),
    freeze_m1 = function(x, ...) x,
    tune_m2 = function(...) tuning,
    validate_m2_tuning = function(...) NULL,
    .nested_inner_gate_rows = function(..., gate_nesting = "conditional") {
      structure(
        data.frame(season = "A", x = 1),
        nested_audit = list(gate_nesting = gate_nesting)
      )
    },
    .nested_m2_decision = function(...) m2_decision,
    fit_m2 = function(data, selection, m0, m1, config, ...) list(config = config),
    freeze_m2 = function(x, tuning, ...) x,
    assemble_kit = function(m0, m1, m2, best_spec_id) {
      list(m0 = m0, m1 = m1, m2 = m2, best_spec_id = best_spec_id)
    },
    validate_page_kit = function(x, ...) invisible(x),
    .package = "PAGe"
  )
  for (nesting in c("full", "conditional")) {
    directory <- withr::local_tempdir()
    result <- PAGe::train_outer_fold(
      fixture$data,
      holdout = "C",
      artifact_dir = directory,
      exclude = character(),
      manual_labels = stats::setNames(rep(1L, 3), fixture$seasons),
      m0_grid = data.frame(x = 1),
      m1_grid = data.frame(k_ref = 3L),
      m2_grid = tuning$grid,
      n_cores = 1L,
      verbose = FALSE,
      gate_nesting = nesting
    )
    expect_identical(result$protocol$gate_nesting, nesting)
    expect_identical(result$gate$nesting, nesting)
    expect_identical(attr(result$gate$matched, "nested_audit")$gate_nesting, nesting)
    expect_identical(result$kit$gate_nesting, nesting)
    protocol <- readRDS(file.path(directory, "protocol.rds"))
    expect_identical(protocol$gate_nesting, nesting)
    expected_label <- if (identical(nesting, "conditional")) {
      "conditional on upstream selection"
    } else {
      "fully nested upstream selection"
    }
    expect_identical(result$gate$nesting_label, expected_label)
    expect_identical(protocol$gate_nesting_label, expected_label)
  }
})
