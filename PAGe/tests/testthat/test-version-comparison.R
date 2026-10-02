test_that("page_version_metrics exposes only scoped verified comparisons", {
  x <- page_version_metrics()
  expect_s3_class(x, "data.frame")
  expect_equal(nrow(x), 5L)
  expect_true(all(c("comparison_scope", "component", "v1_legacy", "v2", "v3", "caveat") %in% names(x)))
  m1 <- x[x$component == "M1_A_peak_timing", ]
  expect_equal(m1$v1_legacy, 1.375185, tolerance = 1e-6)
  expect_equal(m1$v2, 1.092541, tolerance = 1e-6)
  expect_true(is.na(m1$v3))
  b <- x[x$comparison_scope == "chronological_B" & x$horizon == 2, ]
  expect_equal(b$v2, 0.514551588220607, tolerance = 1e-14)
  expect_equal(b$v3, 0.436010448358419, tolerance = 1e-14)
  expect_equal(b$relative_gain_v2_to_v3, 0.152640, tolerance = 1e-6)
})

test_that("v3 model accessor exposes public release metadata", {
  x <- page_models()
  expect_identical(x$release_id, "5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b")
  expect_s3_class(x$manifest, "data.frame")
  expect_identical(nrow(x$manifest), 5L)
  expect_match(x$manifest_sha256, "^[0-9a-f]{64}$")
})
