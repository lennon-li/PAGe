# test-label-safety-fixes.R
# Audit Item 5: ignition label safety fixes.
#   1. flagIgnition() defaults to detection-only (manual_labels = NULL).
#   2. page_manual_ignition_labels() exposes the retrospective label vector.
#   3. assert_loso_test_season_absent() protects LOSO folds from label leakage.
#   4. nested_loso_m2_eval_weekly_refit() gains B4 train/test label separation,
#      a lifecycle deprecation warning, and dz_ema standardization.
#   5. expand_grid_specs() bias_alpha_grid default is the canonical 0.05.

# ---- helpers ----
.make_season_df <- function(season = "2023-24", weeks = 15:30) {
  data.frame(
    season = season,
    weekF  = as.integer(weeks),
    fit    = 0.05,
    d1     = 0.5,
    d1_low = 0.1,
    d2     = 0.01,
    y      = 50L,
    N      = 1000L,
    stringsAsFactors = FALSE
  )
}

# =====================================================================
# Item 1: flagIgnition manual_labels defaults to NULL (detection only)
# =====================================================================

test_that("flagIgnition manual_labels defaults to NULL", {
  expect_null(formals(PAGe:::flagIgnition)$manual_labels,
    label = "Item 5.1: manual_labels must default to NULL")
})

test_that("flagIgnition without manual_labels runs algorithmic detection", {
  out <- PAGe:::flagIgnition(.make_season_df(), p_thresh = 0.01, k1 = 0.4)
  expect_true(out$ignition$rule_name[1] %in% c("core_run", "cumfit_and_slope",
    "slope_run_d1_gt_k1", "slope_run_d1_gt_0"),
    label = "Item 5.1: detection rule should fire, not 'manual'")
  expect_false(identical(out$ignition$rule_name[1], "manual"),
    label = "Item 5.1: no manual override when manual_labels = NULL")
})

test_that("flagIgnition with page_manual_ignition_labels() bypasses detection", {
  labels <- PAGe::page_manual_ignition_labels()
  season <- "2023-24"
  expect_true(season %in% names(labels),
    label = "Item 5.2: 2023-24 should be in the historical labels")
  out <- PAGe:::flagIgnition(.make_season_df(season), p_thresh = 0.01, k1 = 0.4,
    manual_labels = labels)
  expect_equal(out$ignition$rule_name[1], "manual",
    label = "Item 5.2: manual override restores retrospective label")
  expect_equal(out$ignition$weekF[1], as.integer(labels[[season]]),
    label = "Item 5.2: manual iWeek matches accessor value")
})

# =====================================================================
# Item 2: page_manual_ignition_labels accessor
# =====================================================================

test_that("page_manual_ignition_labels is exported and returns named integers", {
  expect_true("page_manual_ignition_labels" %in% getNamespaceExports("PAGe"),
    label = "Item 5.2: accessor should be exported")
  labs <- PAGe::page_manual_ignition_labels()
  expect_type(labs, "integer")
  expect_true(!is.null(names(labs)))
  expect_true(length(labs) >= 8L,
    label = "Item 5.2: should contain the full historical label set")
  expect_equal(labs[["2024-25"]], 23L)
  expect_equal(labs[["2012-13"]], 18L)
})

# =====================================================================
# Item 3: assert_loso_test_season_absent reusable assertion
# =====================================================================

test_that("assert_loso_test_season_absent passes for NULL or absent labels", {
  expect_invisible(PAGe:::assert_loso_test_season_absent("2023-24", NULL))
  expect_invisible(PAGe:::assert_loso_test_season_absent("2023-24",
    c("2022-23" = 15L)))
  expect_invisible(PAGe:::assert_loso_test_season_absent(NULL,
    c("2023-24" = 20L)))
})

test_that("assert_loso_test_season_absent stops when test season is in labels", {
  expect_error(
    PAGe:::assert_loso_test_season_absent("2023-24", c("2023-24" = 20L),
      "manual_labels_train"),
    class = "simpleError",
    label = "Item 5.3: hard stop on training-label leakage"
  )
  expect_error(
    PAGe:::assert_loso_test_season_absent("2023-24", c("2023-24" = 20L)),
    regexp = "LOSO label safety",
    label = "Item 5.3: error message identifies the safety issue"
  )
})

test_that("assert_loso_test_season_absent warns with action = 'warn'", {
  expect_warning(
    PAGe:::assert_loso_test_season_absent("2023-24", c("2023-24" = 20L),
      "manual_labels_test", action = "warn"),
    regexp = "LOSO label safety",
    label = "Item 5.3: soft warn for test-fold override"
  )
})

# =====================================================================
# Item 4: weekly_refit B4 train/test label separation + deprecation
# =====================================================================

test_that("weekly_refit accepts manual_labels_train and manual_labels_test", {
  fn_args <- formals(PAGe:::nested_loso_m2_eval_weekly_refit)
  expect_true("manual_labels_train" %in% names(fn_args),
    label = "B4: weekly_refit should accept manual_labels_train")
  expect_true("manual_labels_test" %in% names(fn_args),
    label = "B4: weekly_refit should accept manual_labels_test")
  expect_null(fn_args$manual_labels_train,
    label = "B4: manual_labels_train defaults to NULL")
  expect_null(fn_args$manual_labels_test,
    label = "B4: manual_labels_test defaults to NULL (prospective)")
})

test_that("weekly_refit emits a lifecycle deprecation warning", {
  fake_fold <- list(
    test_season   = "2023-24",
    train_seasons = c("2022-23"),
    ref           = list(anchorWeek = 20L)
  )
  expect_warning(
    tryCatch(
      PAGe:::nested_loso_m2_eval_weekly_refit(
        allD          = data.frame(season = character(0), weekF = integer(0),
                                   y = integer(0), N = integer(0)),
        fold          = fake_fold,
        m1_test_preds = NULL,
        spec          = list(),
        verbose       = FALSE
      ),
      error = function(e) NULL
    ),
    regexp = "deprecated|legacy",
    ignore.case = TRUE,
    label = "Item 5.4: weekly_refit should emit a deprecation warning"
  )
})

test_that("weekly_refit old manual_labels redirects with deprecation + assertion", {
  fake_fold <- list(
    test_season   = "2023-24",
    train_seasons = c("2022-23"),
    ref           = list(anchorWeek = 20L)
  )
  # Passing manual_labels containing the test season triggers the redirect
  # warning, then the assertion stops (caught by tryCatch).
  expect_warning(
    tryCatch(
      PAGe:::nested_loso_m2_eval_weekly_refit(
        allD          = data.frame(season = character(0), weekF = integer(0),
                                   y = integer(0), N = integer(0)),
        fold          = fake_fold,
        m1_test_preds = NULL,
        spec          = list(),
        manual_labels = c("2023-24" = 20L),
        verbose       = FALSE
      ),
      error = function(e) NULL
    ),
    regexp = "deprecated|manual_labels|legacy",
    ignore.case = TRUE,
    label = "B4 compat: manual_labels redirect emits deprecation warning"
  )
})

test_that("weekly_refit train/test NULL accepted without leakage warning", {
  fake_fold <- list(
    test_season   = "2023-24",
    train_seasons = c("2022-23"),
    ref           = list(anchorWeek = 20L)
  )
  # Only the .Deprecated lifecycle warning should fire (not a label-safety
  # error), and the function should return early (empty allD).
  res <- suppressWarnings(
    PAGe:::nested_loso_m2_eval_weekly_refit(
      allD                = data.frame(season = character(0), weekF = integer(0),
                                       y = integer(0), N = integer(0)),
      fold                = fake_fold,
      m1_test_preds       = NULL,
      spec                = list(),
      manual_labels_train = NULL,
      manual_labels_test  = NULL,
      verbose             = FALSE
    )
  )
  expect_true(is.list(res) && all(c("scores", "predictions") %in% names(res)))
})

# =====================================================================
# Item 5: expand_grid_specs bias_alpha default is canonical 0.05
# =====================================================================

test_that("expand_grid_specs bias_alpha_grid defaults to 0.05", {
  fn_args <- formals(PAGe:::expand_grid_specs)
  expect_equal(eval(fn_args$bias_alpha_grid), 0.05,
    label = "Item 5.5: bias_alpha_grid default should be canonical 0.05")
})

test_that("expand_grid_specs default specs carry bias_alpha = 0.05", {
  skip_if_not_installed("data.table")
  out <- suppressMessages(PAGe:::expand_grid_specs(
    delta_grid = 0L, Kr_grid = 1L, T_grid = "O",
    Kb_grid = 0L, k_f_grid = 6L, verbose = FALSE
  ))
  expect_true(length(out$specs) >= 1L)
  expect_true(all(vapply(out$specs, function(s) s$bias_alpha == 0.05, logical(1))),
    label = "Item 5.5: every default spec should have bias_alpha = 0.05")
})
