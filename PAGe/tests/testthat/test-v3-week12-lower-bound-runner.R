find_week12_runner_repo <- function() {
  candidates <- c(".", "..", "../..", "../../..")
  hit <- candidates[file.exists(file.path(candidates, "2026",
    "run_weekly_shadow_v3_week12_v1.R"))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]], winslash = "/", mustWork = TRUE)
}

test_that("week12 runner withholds week11 and issues four shadow forecasts at week12", {
  repo <- find_week12_runner_repo()
  skip_if(is.na(repo), "repository unavailable")
  old_wd <- setwd(repo)
  on.exit(setwd(old_wd), add = TRUE)
  env <- new.env(parent = globalenv())
  sys.source("2026/run_weekly_shadow_v3_week12_v1.R", env)
  panel <- read.csv("artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv")
  make_fixture <- function(origin) {
    d <- panel[panel$season == "2025-26" & panel$weekF <= origin,
      c("season", "weekF", "y_A", "N_A", "p_A", "y_B", "N_B", "p_B",
        "denominator_regime")]
    d$season <- "2026-27"
    d$denominator_regime <- "orvt_type_specific"
    path <- tempfile(fileext = ".csv")
    write.csv(d, path, row.names = FALSE)
    path
  }
  r11 <- env$.shadow_v3_main(c("--season=2026-27",
    paste0("--typed-panel=", make_fixture(11L)),
    paste0("--output-root=", tempfile("week11-"))))
  expect_equal(nrow(r11$predictions), 4L)
  expect_true(all(is.na(r11$predictions$forecast)))
  expect_true(all(r11$predictions$timing_reason ==
    "not_in_validated_window_before_weekF12"))
  r12 <- env$.shadow_v3_main(c("--season=2026-27",
    paste0("--typed-panel=", make_fixture(12L)),
    paste0("--output-root=", tempfile("week12-"))))
  expect_true(all(is.finite(r12$predictions$forecast)))
  expect_true(all(!r12$predictions$production_eligible))
  expect_true(all(r12$predictions$forecast[r12$predictions$type == "A"] ==
    r12$predictions$state_baseline[r12$predictions$type == "A"]))
  b <- r12$predictions[r12$predictions$type == "B", ]
  expect_identical(b$forecast[[1]], b$state_baseline[[1]])
  expect_false(b$timing_available[[2]])
  expect_identical(b$forecast[[2]], b$state_baseline[[2]])
})
