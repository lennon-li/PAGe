# Fully nested inner-gate regression tests. All M1/M2 fitting is mocked.

.nested_gate_fixture <- function() {
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
    data = data,
    m0 = list(best_params = list()),
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
    ),
    seasons = seasons
  )
}

.with_nested_gate_mocks <- function(expr, calls, fit_log) {
  local_mocked_bindings(
    .m1_heldout_references = function(m1, seasons, timing_mode,
                                      excluded_sets = NULL, params = NULL) {
      calls$excluded_sets <<- excluded_sets
      keys <- vapply(excluded_sets, PAGe:::.m1_exclusion_key, character(1))
      stats::setNames(lapply(excluded_sets, function(excluded) {
        list(
          ref = list(key = PAGe:::.m1_exclusion_key(excluded)),
          hyper = list(), excluded_seasons = sort(excluded)
        )
      }), keys)
    },
    m1_walkforward_multi = function(seasons, season_references, ...) {
      do.call(rbind, lapply(seasons, function(s) {
        reference <- season_references[[s]]
        d <- expand.grid(eval_weekF = 4:8, h = 1:2)
        d$season <- s
        d$target_weekF <- d$eval_weekF + d$h
        d$m1_p_hat <- 0.2 + 0.01 * d$h +
          0.001 * length(reference$excluded_seasons)
        d$forecast_available <- TRUE
        d$unavailable_reason <- NA_character_
        d
      }))
    },
    m2_subset_fit = function(data, spec, gamma = 1.4, ...) {
      fit_log$items[[length(fit_log$items) + 1L]] <- list(
        seasons = paste(sort(unique(as.character(data$season))), collapse = ","),
        signature = paste(data$season, data$y_lead, collapse = "|"),
        gamma = gamma,
        coefficient = mean(data$y_lead)
      )
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

test_that("nested cache fits each singleton and unordered pair once", {
  fixture <- .nested_gate_fixture()
  calls <- new.env(parent = emptyenv())
  calls$excluded_sets <- NULL
  fit_log <- new.env(parent = emptyenv())
  fit_log$items <- list()
  .with_nested_gate_mocks(
    {
      cache <- PAGe:::.nested_m1_cache(
        fixture$data, fixture$m0, fixture$m1, fixture$seasons, "legacy"
      )
      expect_identical(cache$reference_fit_count, 6L)
      expect_setequal(
        cache$reference_keys,
        c("A", "B", "C", "A\rB", "A\rC", "B\rC")
      )
      expect_length(calls$excluded_sets, 6L)
      expect_identical(length(fit_log$items), 0L)
      expect_identical(PAGe:::.m1_exclusion_key(c("C", "A", "C")), "A\rC")
    },
    calls,
    fit_log
  )
})

test_that("season perturbation cannot alter that season's nested correction", {
  fixture <- .nested_gate_fixture()
  calls <- new.env(parent = emptyenv())
  calls$excluded_sets <- NULL
  fit_log <- new.env(parent = emptyenv())
  fit_log$items <- list()
  result <- list()
  gate_tuning <- fixture$tuning
  gate_tuning$alpha_state <- 0.8
  gate_tuning$grid$alpha_state <- 0.8
  gate_tuning$grid$gamma <- 9
  gate_tuning$selected_config <- PAGe:::m2_subset_config(
    alpha_state = 0.8, gamma = 9
  )
  .with_nested_gate_mocks(
    {
      result[[1L]] <- PAGe:::.nested_inner_gate_rows(
        gate_tuning, fixture$seasons, fixture$data, fixture$m0, fixture$m1,
        m2_recipe_grid = gate_tuning$grid
      )
      changed <- fixture$data
      changed$y[changed$season == "C" & changed$weekF == 10L] <- 40L
      result[[2L]] <- PAGe:::.nested_inner_gate_rows(
        gate_tuning, fixture$seasons, changed, fixture$m0, fixture$m1,
        m2_recipe_grid = gate_tuning$grid
      )
    },
    calls,
    fit_log
  )

  first_c <- result[[1L]][result[[1L]]$season == "C", , drop = FALSE]
  second_c <- result[[2L]][result[[2L]]$season == "C", , drop = FALSE]
  expect_identical(first_c$m2_prediction, second_c$m2_prediction)
  expect_true(any(first_c$outcome != second_c$outcome))
  expect_identical(
    attr(result[[1L]], "nested_audit")$m2_selected_ids_by_season[["C"]],
    attr(result[[2L]], "nested_audit")$m2_selected_ids_by_season[["C"]]
  )
  first_audit <- attr(result[[1L]], "nested_audit")
  expect_identical(first_audit$reference_fit_count, 6L)
  expect_identical(first_audit$reference_fit_count_expected, 6L)
  expect_match(
    first_audit$m2_gate_parameter_source,
    "shared selection core"
  )
  expect_true(all(vapply(fit_log$items, function(x) x$gamma == 9, logical(1))))
})

test_that("governed legacy M2 requires an explicit compatibility flag", {
  expect_error(
    PAGe::tune_m2(
      data.frame(), list(), list(), list(), data.frame(),
      family = "legacy"
    ),
    "allow_legacy"
  )
  expect_true("allow_legacy" %in% names(formals(PAGe::tune_m2)))
  expect_identical(eval(formals(PAGe::tune_m2)$family)[[1L]], "offset_subset_v1")
  expect_error(
    PAGe::train_pipeline(data.frame(), m2_family = "legacy"),
    "allow_legacy"
  )
})

test_that("gate M2 selection ignores the outer post-expansion grid", {
  fixture <- .nested_gate_fixture()
  calls <- new.env(parent = emptyenv())
  calls$excluded_sets <- NULL
  fit_log <- new.env(parent = emptyenv())
  fit_log$items <- list()
  base <- fixture$tuning
  base$recipe_grid <- base$grid
  leaked <- base
  leaked$grid <- PAGe:::m2_subset_grid(k_values = c(0L, 3L, 4L))
  leaked$scores <- data.frame(
    spec_id = as.character(leaked$grid$id),
    bernoulli_nll = rev(seq_len(nrow(leaked$grid)))
  )
  out <- list()
  .with_nested_gate_mocks(
    {
      out[[1L]] <- PAGe:::.nested_inner_gate_rows(
        base, fixture$seasons, fixture$data, fixture$m0, fixture$m1,
        m2_recipe_grid = base$grid
      )
      out[[2L]] <- PAGe:::.nested_inner_gate_rows(
        leaked, fixture$seasons, fixture$data, fixture$m0, fixture$m1,
        m2_recipe_grid = base$grid
      )
    },
    calls,
    fit_log
  )
  expect_identical(
    attr(out[[1L]], "nested_audit")$m2_selected_ids_by_season,
    attr(out[[2L]], "nested_audit")$m2_selected_ids_by_season
  )
})
