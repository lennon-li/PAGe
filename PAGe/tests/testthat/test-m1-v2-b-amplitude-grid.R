test_that("M1-v2 accepts a type-specific amplitude grid without changing A default", {
  make_season <- function(season, peak, amp) {
    w <- 1:32
    p <- amp * exp(-0.5 * ((w - peak) / 3)^2)
    N <- rep(2000L, length(w))
    data.frame(season=season, weekF=w, y=round(N*p), N=N)
  }
  hist <- rbind(
    make_season("s1",16,.03),
    make_season("s2",17,.06),
    make_season("s3",18,.10),
    make_season("s4",16.5,.14)
  )
  truth <- do.call(rbind,lapply(sort(unique(hist$season)),function(s){
    f <- retrospective_gam_peak_truth(hist, season=s, k=6L, grid_step=.05)
    data.frame(season=s, peak_week_decimal=f$peak_week_decimal)
  }))

  bgrid <- seq(.005,.25,by=.005)
  lib <- fit_m1_v2_library(hist,truth,k=6L,grid_step=.05,tau_step=.2,
                           amplitude_grid=bgrid)
  expect_equal(lib$config$amplitude_grid,bgrid)
  expect_equal(lib$forecast$amplitude_grid,bgrid)
  expect_equal(lib$passage$amplitude_grid,bgrid)
  expect_lt(min(lib$forecast$amplitude_grid), .08)

  lib_default <- fit_m1_v2_library(hist,truth,k=6L,grid_step=.05,tau_step=.2)
  expect_equal(lib_default$config$amplitude_grid, seq(.08,.44,by=.02))
})

test_that("M1-v2 rejects malformed amplitude grids", {
  expect_error(.normalize_m1_v2_amplitude_grid(c(.01,.02)), "at least three")
  expect_error(.normalize_m1_v2_amplitude_grid(c(.01,.02,.04,.05)), "regularly spaced")
  expect_error(.normalize_m1_v2_amplitude_grid(c(0,.01,.02)), "strictly inside")
})
