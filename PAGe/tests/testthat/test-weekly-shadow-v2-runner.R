find_page_repo_root_weekly_v2 <- function() {
  candidates <- c(".", "..", "../..", "../../..")
  hit <- candidates[file.exists(file.path(candidates, "2026", "run_weekly_shadow_v2.R"))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]], winslash = "/", mustWork = TRUE)
}

.repo_weekly_v2 <- find_page_repo_root_weekly_v2()
if (!is.na(.repo_weekly_v2)) {
  .old_weekly_v2 <- setwd(.repo_weekly_v2)
  source("PAGe/R/season_calendar.R", local = TRUE)
  source("2026/run_weekly_shadow_v2.R", local = TRUE)
  setwd(.old_weekly_v2)
}

testthat::test_that("weekly shadow v2 OLIS loader builds one aligned A/B panel", {
  td <- tempfile("shadow-v2-")
  dir.create(td)
  f <- file.path(td, "hist_olis.RData")
  dates <- as.Date(c("2026-07-05", "2026-07-12"))
  r <- list(
    fluA = data.frame(
      date = rep(dates, each = 2),
      pos = c(2, 3, 4, 5),
      tests = c(100, 150, 120, 180)
    ),
    fluB = data.frame(
      date = rep(dates, each = 2),
      pos = c(1, 1, 1, 2),
      tests = c(100, 150, 120, 180)
    )
  )
  save(r, file = f)

  got <- .shadow_v2_panel_from_olis(f, "2026-27")
  testthat::expect_equal(got$weekF, c(1L, 2L))
  testthat::expect_equal(got$y_A, c(5, 9))
  testthat::expect_equal(got$N_A, c(250, 300))
  testthat::expect_equal(got$y_B, c(2, 3))
  testthat::expect_equal(got$N_B, c(250, 300))
  testthat::expect_equal(got$p_A, c(5 / 250, 9 / 300))
  testthat::expect_equal(got$p_B, c(2 / 250, 3 / 300))
  testthat::expect_true(all(got$denominator_regime == "orvt_type_specific"))
})

testthat::test_that("weekly shadow v2 revision audit detects retrospective changes", {
  previous <- data.frame(
    weekF = 1:2,
    y_A = c(5, 9), N_A = c(250, 300), p_A = c(.02, .03),
    y_B = c(2, 3), N_B = c(250, 300), p_B = c(.008, .01)
  )
  current <- previous
  current$y_A[2] <- 10
  current$p_A[2] <- 10 / 300
  current$N_B[1] <- 251
  current$p_B[1] <- 2 / 251

  got <- .shadow_v2_revision_audit(current, previous)
  testthat::expect_equal(nrow(got), 2L)
  testthat::expect_equal(got$delta_y_A, c(0, 1))
  testthat::expect_equal(got$delta_N_B, c(1, 0))
  testthat::expect_equal(got$revised_A, c(FALSE, TRUE))
  testthat::expect_equal(got$revised_B, c(TRUE, FALSE))
})

testthat::test_that("weekly shadow v2 CLI requires season and validates source", {
  testthat::expect_error(.shadow_v2_parse_args(character()), "--season")
  got <- .shadow_v2_parse_args(c("--season=2026-27", "--source=olis", "--input=x.RData"))
  testthat::expect_identical(got$season, "2026-27")
  testthat::expect_identical(got$source, "olis")
  testthat::expect_identical(got$input, "x.RData")
  testthat::expect_error(
    .shadow_v2_parse_args(c("--season=2026-27", "--source=bad")),
    "auto, orvt, or olis"
  )
})
