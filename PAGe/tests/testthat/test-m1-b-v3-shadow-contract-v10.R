find_week12_repo <- function() {
  candidates <- c(".", "..", "../..", "../../..")
  hit <- candidates[file.exists(file.path(candidates, "scripts",
    "v3_m1_b_runtime_helpers_v9.R"))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]], winslash = "/", mustWork = TRUE)
}

test_that("M1-B v10 preserves the v9 fitted library and binds week12 provenance", {
  repo <- find_week12_repo()
  skip_if(is.na(repo), "repository unavailable")
  old_wd <- setwd(repo)
  on.exit(setwd(old_wd), add = TRUE)
  skip_if_not(file.exists("artifacts/m1-b-v3-peak-v10/m1_b_v3_peak_artifact.rds"))
  old <- readRDS("artifacts/m1-b-v3-peak-v9/m1_b_v3_peak_artifact.rds")
  source("scripts/v3_m1_b_runtime_helpers_v9.R", local = environment())
  new <- load_m1_b_v3_artifact()
  expect_identical(new$version, "m1-b-v3-peak-v10")
  expect_identical(new$library, old$library)
  expect_identical(
    new$library$provenance$library_hash,
    old$library$provenance$library_hash
  )
  expect_identical(new$activity_marker$window, c(12L, 40L))
  expect_identical(
    new$runtime_contract$required_helper,
    "scripts/v3_m1_b_runtime_helpers_v9.R"
  )
})

test_that("M1-B v10 fixed-origin posteriors equal v9", {
  repo <- find_week12_repo()
  skip_if(is.na(repo), "repository unavailable")
  old_wd <- setwd(repo)
  on.exit(setwd(old_wd), add = TRUE)
  panel <- read.csv("artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv")
  old <- readRDS("artifacts/m1-b-v3-peak-v9/m1_b_v3_peak_artifact.rds")
  new <- readRDS("artifacts/m1-b-v3-peak-v10/m1_b_v3_peak_artifact.rds")
  env8 <- new.env(parent = globalenv())
  env9 <- new.env(parent = globalenv())
  sys.source("scripts/v3_m1_b_runtime_helpers_v8.R", env8)
  sys.source("scripts/v3_m1_b_runtime_helpers_v9.R", env9)
  for (origin in c(35L, 40L, 45L)) {
    d <- panel[panel$season == "2025-26" & panel$weekF <= origin,
      c("season", "weekF", "y_B", "N_B", "p_B")]
    names(d)[3:5] <- c("y", "N", "p")
    d$season <- "2026-27"
    activity <- 34.39027
    p8 <- env8$m1_b_v3_peak_posterior(old, d, activity, origin)
    p9 <- env9$m1_b_v3_peak_posterior(new, d, activity, origin)
    expect_equal(p9$posterior$probability, p8$posterior$probability,
      tolerance = 1e-12)
    q8 <- env8$m1_b_v3_passage_posterior(old, d, activity, origin)
    q9 <- env9$m1_b_v3_passage_posterior(new, d, activity, origin)
    expect_equal(q9$prob_peak_passed, q8$prob_peak_passed, tolerance = 1e-12)
  }
})
