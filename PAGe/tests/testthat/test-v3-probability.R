library(testthat)

.find_prob_repo <- function() {
  d <- normalizePath(getwd(), winslash='/', mustWork=TRUE)
  for (i in 0:7) {
    if (file.exists(file.path(d,'PAGe','DESCRIPTION')) && file.exists(file.path(d,'scripts','v3_probability_helpers_v1.R'))) return(d)
    d <- dirname(d)
  }
  stop('probability API repository root not found')
}

.prob_repo <- .find_prob_repo(); .prob_oldwd <- setwd(.prob_repo); on.exit(setwd(.prob_oldwd), add=TRUE)
# Match the snapshot worker execution boundary: frozen package sources are loaded
# unchanged, then the API-side probability helper is layered on top.
for (.f in sort(list.files('PAGe/R',pattern='[.]R$',full.names=TRUE))) sys.source(.f,envir=environment())
sys.source('scripts/v3_probability_helpers_v1.R',envir=environment())

.prob_fixture <- function(name) {
  candidates <- c(file.path('PAGe','inst','extdata','v3-week12',name),
                  file.path('inst','extdata','v3-week12',name))
  hit <- candidates[file.exists(candidates)]
  if (!length(hit)) stop('v3 probability fixture not found: ',name)
  hit[[1L]]
}

test_that('API-side weighted probability helpers implement strict/inclusive semantics', {
  d <- .page_prob_new(c(.1,.2,.3),'demo','proportion',c(0,1),weights=c(.2,.3,.5))
  expect_equal(sum(d$weights),1,tolerance=1e-15)
  expect_equal(.page_prob_above(d,.2),.5,tolerance=1e-15)
  expect_equal(.page_prob_above(d,.2,TRUE),.8,tolerance=1e-15)
  expect_equal(.page_prob_below(d,.2),.2,tolerance=1e-15)
  expect_equal(.page_prob_below(d,.2,TRUE),.5,tolerance=1e-15)
})

test_that('v3 positivity exceedance uses the frozen experimental OOS calibrator', {
  panel <- read.csv(.prob_fixture('ignition-panel.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  f <- page_forecast(panel,season='2026-27',origin_weekF=12)
  d <- .page_prob_predictive_distribution(f,'A',1L)
  expect_identical(d$status,'experimental')
  expect_identical(d$outcome,'positivity_jeffreys_smoothed')
  expect_true(length(d$atoms)>10L)
  expect_equal(sum(d$weights),1,tolerance=1e-12)
  expect_match(d$calibration$calibrator_id,'^[0-9a-f]{64}$')
  p1 <- .page_prob_above(d,.01); p2 <- .page_prob_above(d,.02); p3 <- .page_prob_above(d,.03)
  expect_true(1>=p1 && p1>=p2 && p2>=p3 && p3>=0)
  expect_equal(.page_prob_above(d,0),1,tolerance=1e-15)
  expect_equal(.page_prob_above(d,1),0,tolerance=1e-15)
})

test_that('A peak distribution exactly reproduces existing passage monitoring', {
  panel <- read.csv(.prob_fixture('ignition-panel.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  f <- page_forecast(panel,season='2026-27',origin_weekF=12)
  d <- .page_prob_peak_distribution(f,'A')
  expect_identical(d$status,'experimental')
  asof <- f$origin_weekF+1
  expect_equal(.page_prob_below(d,asof,TRUE),f$monitoring$A$m1$prob_peak_passed,tolerance=1e-14)
  expect_equal(sum(d$weights[d$atoms>asof & d$atoms<=asof+1]),f$monitoring$A$m1$prob_peak_within_1w,tolerance=1e-14)
  expect_equal(sum(d$weights[d$atoms>asof & d$atoms<=asof+2]),f$monitoring$A$m1$prob_peak_within_2w,tolerance=1e-14)
  expect_equal(sum(d$weights[d$atoms>asof & d$atoms<=asof+3]),f$monitoring$A$m1$prob_peak_within_3w,tolerance=1e-14)
})

test_that('inactive peak timing fails closed', {
  panel <- read.csv(.prob_fixture('no-ignition-panel.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  f <- page_forecast(panel,season='2026-27',origin_weekF=12)
  d <- .page_prob_peak_distribution(f,'A')
  expect_identical(d$status,'unavailable')
  expect_length(d$atoms,0L)
  expect_error(.page_prob_below(d,15),'unavailable')
})

test_that('active B peak distribution exactly reproduces B passage monitoring', {
  b <- read.csv(.prob_fixture('b-active-input.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  panel <- data.frame(season=b$season,weekF=b$weekF,
    y_A=rep(1,nrow(b)),N_A=b$N_B,p_A=1/b$N_B,
    y_B=b$y_B,N_B=b$N_B,p_B=b$p_B,
    denominator_regime='orvt_type_specific',stringsAsFactors=FALSE)
  f <- page_forecast(panel,season='2026-27',origin_weekF=45)
  expect_true(f$monitoring$B$m1$available)
  d <- .page_prob_peak_distribution(f,'B')
  expect_identical(d$status,'experimental')
  expect_equal(.page_prob_below(d,f$origin_weekF+1,TRUE),f$monitoring$B$m1$prob_peak_passed,tolerance=1e-14)
})

test_that('frozen API calibrator identity is content-bound', {
  path <- 'governance/v3_probability_calibrator_v1.rds'
  expect_true(file.exists(path))
  x <- readRDS(path); stored <- x$calibrator_id; x$calibrator_id <- NULL
  expect_identical(stored,digest::digest(x,algo='sha256'))
})
