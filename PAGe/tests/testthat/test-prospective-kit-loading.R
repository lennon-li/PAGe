test_that("strict kit loading fails closed for missing canonical fields", {
  kit_dir <- withr::local_tempdir()
  saveRDS(list(ref = list(), hyper = list()), file.path(kit_dir, "ref_production.rds"))
  saveRDS(list(best_params = list(p_thr = 0.005)), file.path(kit_dir, "stage1_tuning.rds"))

  saveRDS(list(fit = "fit", spec = list(k_f = 4L)),
          file.path(kit_dir, "m2_production.rds"))
  expect_error(
    load_prospective_kit(kit_dir),
    "M1_PARAMS.*compatibility = \\\"locked_defaults\\\""
  )

  saveRDS(list(ref = list(), hyper = list(), M1_PARAMS = list(k_ref = 25L)),
          file.path(kit_dir, "ref_production.rds"))
  saveRDS(list(fit = "fit"), file.path(kit_dir, "m2_production.rds"))
  saveRDS(list(best_spec = list(legacy = TRUE)),
          file.path(kit_dir, "nested_loso_v12_production.rds"))
  expect_error(
    load_prospective_kit(kit_dir),
    "m2_production\\$spec.*compatibility = \\\"legacy\\\""
  )
})

test_that("locked-default compatibility uses the centralized M1 defaults", {
  kit_dir <- withr::local_tempdir()
  saveRDS(list(ref = list(), hyper = list()), file.path(kit_dir, "ref_production.rds"))
  saveRDS(list(fit = "fit", spec = list(k_f = 4L)),
          file.path(kit_dir, "m2_production.rds"))
  saveRDS(list(best_params = list(p_thr = 0.005)), file.path(kit_dir, "stage1_tuning.rds"))

  expect_warning(
    kit <- load_prospective_kit(kit_dir, compatibility = "locked_defaults"),
    "centralized locked M1 defaults"
  )
  expected_defaults <- tryCatch(
    PAGe:::.default_m1_params(),
    error = function(e) .default_m1_params()
  )
  expect_identical(kit$M1_PARAMS, expected_defaults)
  expect_identical(kit$best_spec, list(k_f = 4L))
})

test_that("legacy compatibility is the only mode that discovers old LOSO specs", {
  kit_dir <- withr::local_tempdir()
  saveRDS(
    list(ref = list(), hyper = list(), M1_PARAMS = list(k_ref = 25L)),
    file.path(kit_dir, "ref_production.rds")
  )
  saveRDS(list(fit = "fit"), file.path(kit_dir, "m2_production.rds"))
  saveRDS(list(best_spec = list(legacy = TRUE)),
          file.path(kit_dir, "nested_loso_v12_production.rds"))
  saveRDS(list(best_params = list(p_thr = 0.005)), file.path(kit_dir, "stage1_tuning.rds"))

  expect_warning(
    kit <- load_prospective_kit(kit_dir, compatibility = "legacy"),
    "Legacy compatibility.*deprecated nested LOSO"
  )
  expect_identical(kit$best_spec, list(legacy = TRUE))
})
