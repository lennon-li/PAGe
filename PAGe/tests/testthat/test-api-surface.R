test_that("high-level training API functions are exported and have expected formals", {
  expected <- list(
    build_m0     = c("allD", "exclude", "manual_labels", "flag_args"),
    tune_m0      = c("allD", "loso_seasons", "exclude", "grid"),
    build_m1     = c("allD", "m0", "exclude", "exclude_live"),
    tune_m1      = c("allD", "m0", "m1", "loso_seasons"),
    build_m2     = c("allD", "m0", "m1", "loso_seasons"),
    train_m2     = c("allD", "m0", "m1", "best_spec"),
    assemble_kit = c("m0", "m1", "m2_model", "best_spec_id")
  )

  for (fn in names(expected)) {
    expect_true(exists(fn, where = asNamespace("PAGe"), inherits = FALSE),
                info = sprintf("%s should be defined in PAGe namespace", fn))
    f <- get(fn, envir = asNamespace("PAGe"))
    formal_nms <- names(formals(f))
    for (arg in expected[[fn]]) {
      expect_true(arg %in% formal_nms,
                  info = sprintf("%s should have formal '%s'", fn, arg))
    }
  }
})

test_that("runtime API aliases delegate to canonical functions", {
  # run_m0 -> run_m0_detection; run_m1 -> run_m1_alignment;
  # run_m2 -> run_m2_forecast; run_pipeline -> run_prospective_pipeline
  aliases <- c(run_m0 = "run_m0_detection",
               run_m1 = "run_m1_alignment",
               run_m2 = "run_m2_forecast",
               run_pipeline = "run_prospective_pipeline")

  for (alias in names(aliases)) {
    expect_true(exists(alias, where = asNamespace("PAGe"), inherits = FALSE),
                info = sprintf("alias %s should be exported", alias))
    body_src <- paste(deparse(body(get(alias, envir = asNamespace("PAGe")))),
                      collapse = " ")
    expect_match(body_src, aliases[[alias]], fixed = TRUE,
                 info = sprintf("%s body should delegate to %s",
                                alias, aliases[[alias]]))
  }
})

test_that("exported helpers with no Rd before this audit now have Rd files", {
  man_dir <- system.file("man", package = "PAGe")
  # When testing via devtools::test(), system.file returns "" for man/;
  # skip silently if we cannot locate the package source.
  skip_if(man_dir == "")
  for (nm in c("checkSeasonLength", "makeTable", "negloglik_tau_delta",
               "peak_summary_from_fit", "plotRes")) {
    expect_true(file.exists(file.path(man_dir, paste0(nm, ".Rd"))),
                info = sprintf("man/%s.Rd should exist", nm))
  }
})
