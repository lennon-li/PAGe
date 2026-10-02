find_week12_m2_repo <- function() {
  candidates <- c(".", "..", "../..", "../../..")
  hit <- candidates[file.exists(file.path(candidates, "scripts",
    "v3_m2_b_runtime_helpers_v5.R"))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]], winslash = "/", mustWork = TRUE)
}

test_that("M2-B v5 is week12-only, shadow-only, and payload preserving", {
  repo <- find_week12_m2_repo()
  skip_if(is.na(repo), "repository unavailable")
  old_wd <- setwd(repo)
  on.exit(setwd(old_wd), add = TRUE)
  old <- readRDS("artifacts/m2-b-v3-shadow-v3/m2_b_v3_shadow_artifact.rds")
  source("scripts/v3_m2_b_runtime_helpers_v5.R", local = environment())
  new <- load_m2_b_v3_shadow_artifact()
  expect_identical(new$version, "m2-b-v3-shadow-v5")
  expect_identical(new$status, "shadow_only_prospective_research")
  expect_false(new$production_eligible)
  expect_identical(new$state, old$state)
  expect_identical(new$shape, old$shape)
  expect_identical(new$runtime_contract$min_origin_week, 12L)
  expect_identical(new$runtime_contract$min_history_observations, 3L)
  expect_identical(new$activity$params$w_min, 12L)
  expect_identical(new$activity$params$w_max, 40L)
})

test_that("M2-B v5 accepts week12 and requires exact origin support", {
  repo <- find_week12_m2_repo()
  skip_if(is.na(repo), "repository unavailable")
  old_wd <- setwd(repo)
  on.exit(setwd(old_wd), add = TRUE)
  source("scripts/v3_m2_b_runtime_helpers_v5.R", local = environment())
  a <- load_m2_b_v3_shadow_artifact()
  m1 <- load_m1_b_v3_artifact()
  panel <- read.csv("artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv")
  d <- panel[panel$season == "2025-26" & panel$weekF <= 12,
    c("season", "weekF", "y_B", "N_B", "p_B")]
  names(d)[3:5] <- c("y", "N", "p")
  d$season <- "2026-27"
  h1 <- m2_b_v3_shadow_forecast(a, m1, d, 12L, 1L)
  h2 <- m2_b_v3_shadow_forecast(a, m1, d, 12L, 2L)
  expect_identical(h1$forecast, h1$B1_forecast)
  expect_false(h2$timing_available)
  expect_identical(h2$forecast, h2$B1_forecast)
  expect_error(m2_b_v3_shadow_forecast(a, m1, d[d$weekF != 11, ], 12L, 1L),
    "consecutive")
})
