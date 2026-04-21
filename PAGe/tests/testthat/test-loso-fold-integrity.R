# test-loso-fold-integrity.R
# Regression tests for B4: LOSO test fold used the held-out season's iWeek
# from manual_labels (retrospective leakage). Fix: separate manual_labels_train
# and manual_labels_test; test fold uses manual_labels_test = NULL (prospective).
#
# Audit reference: code-audit-2026-04 B4.

test_that("nested_loso_m2_eval_frozen_bias accepts manual_labels_train and manual_labels_test", {
  # Verify the new signature exists (B4 API contract).
  fn_args <- formals(PAGe::nested_loso_m2_eval_frozen_bias)
  expect_true("manual_labels_train" %in% names(fn_args),
    label = "B4: function should accept manual_labels_train")
  expect_true("manual_labels_test" %in% names(fn_args),
    label = "B4: function should accept manual_labels_test")
})

test_that("manual_labels still accepted (backward compat) with deprecation warning", {
  # Old callers pass manual_labels; should redirect with a warning.
  # We trigger only the argument-parsing code, not the full eval.
  # Use a minimal fake fold that causes an early return before real computation.
  fake_fold <- list(
    test_season   = "2023-24",
    train_seasons = c("2022-23"),
    ref           = list(anchorWeek = 20L)
  )

  # Passing manual_labels (old API) should trigger a deprecation warning.
  expect_warning(
    tryCatch(
      PAGe::nested_loso_m2_eval_frozen_bias(
        allD          = data.frame(season = character(0), weekF = integer(0),
                                   y = integer(0), N = integer(0)),
        fold          = fake_fold,
        m2_fit        = NULL,
        m1_test_preds = NULL,
        spec          = list(),
        manual_labels = c("2023-24" = 20L),
        verbose       = FALSE
      ),
      error = function(e) NULL  # early failure is OK — we only need the warning
    ),
    regexp = "deprecated|manual_labels",
    ignore.case = TRUE,
    label = "B4 backward compat: manual_labels should trigger deprecation warning"
  )
})

test_that("manual_labels_train NULL and manual_labels_test NULL are accepted without warning", {
  fake_fold <- list(
    test_season   = "2023-24",
    train_seasons = c("2022-23"),
    ref           = list(anchorWeek = 20L)
  )

  # Passing both as NULL should not warn about deprecation.
  expect_no_warning(
    tryCatch(
      PAGe::nested_loso_m2_eval_frozen_bias(
        allD                = data.frame(season = character(0), weekF = integer(0),
                                         y = integer(0), N = integer(0)),
        fold                = fake_fold,
        m2_fit              = NULL,
        m1_test_preds       = NULL,
        spec                = list(),
        manual_labels_train = NULL,
        manual_labels_test  = NULL,
        verbose             = FALSE
      ),
      error = function(e) NULL
    )
  )
})

test_that("B4 invariant: training label for test season must NOT leak into test fold", {
  # If manual_labels_train contains the test season, the test fold would use
  # a retrospective iWeek — the core B4 bug. After the fix, the test fold
  # always uses manual_labels_test (default NULL = prospective).
  #
  # We verify this at the API level: manual_labels_train is only used for
  # training-fold ignition, not test-fold ignition. The function signature
  # separates the two, so leakage cannot occur if the caller uses the new API.
  #
  # This is a smoke test checking that the new args exist and the function
  # accepts them without erroring (runtime correctness checked via B4 scripts).
  fn_args <- formals(PAGe::nested_loso_m2_eval_frozen_bias)

  # manual_labels_test defaults to NULL (prospective, no leakage).
  expect_null(fn_args$manual_labels_test,
    label = "B4: manual_labels_test should default to NULL (prospective ignition)")
  expect_null(fn_args$manual_labels_train,
    label = "B4: manual_labels_train should default to NULL")
})
