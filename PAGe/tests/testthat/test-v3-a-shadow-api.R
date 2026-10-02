library(testthat)

.find_shadow_repo <- function() {
  d <- normalizePath(getwd(),winslash='/',mustWork=TRUE)
  for(i in 0:7) {
    if(file.exists(file.path(d,'PAGe','DESCRIPTION')) && file.exists(file.path(d,'scripts','v3_a_shadow_helpers_v1.R'))) return(d)
    d <- dirname(d)
  }
  stop('A shadow repository root not found')
}

.shadow_repo <- .find_shadow_repo(); .oldwd <- setwd(.shadow_repo); on.exit(setwd(.oldwd),add=TRUE)
for(.f in sort(list.files('PAGe/R',pattern='[.]R$',full.names=TRUE))) sys.source(.f,envir=environment())
sys.source('scripts/v3_a_shadow_helpers_v1.R',envir=environment())

.fixture <- function(name) {
  p <- file.path('PAGe','inst','extdata','v3-week12',name)
  if(!file.exists(p)) stop('fixture missing: ',name)
  p
}

test_that('EXP050 H2 artifact is frozen, shadow-only, and release-bound', {
  skip_if(!file.exists(.PAGE_A_EXP050_PATH), 'EXP050 artifact is not checked into this repository')
  a <- .page_a_shadow_load_exp050()
  expect_identical(a$version,'v3-a-exp050-h2-shadow-v1')
  expect_identical(a$status,'experimental_shadow')
  expect_false(a$production_eligible)
  expect_identical(a$canonical_release_id,.PAGE_V3_RELEASE_ID)
  expect_identical(a$scope$request_option,'exp050_h2')
  expect_identical(as.integer(a$scope$horizons),2L)
  expect_identical(names(a$fit$coefficients),c('(Intercept)','horizon_fh2','growth1','growth2','exp050'))
  expect_true(a$evidence$plus2_relative_mae_gain > 0)
  expect_false(a$evidence$plus2_relative_mae_gain >= .05)
})

test_that('EXP050 runtime uses exact causal t-4 through t history', {
  p <- read.csv(.fixture('ignition-panel.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  f <- .page_a_shadow_runtime_features(p,12L)
  z <- p[p$weekF %in% 8:12,]; z <- z[order(z$weekF),]
  ln <- log(z$N_A); d <- c(ln[5]-ln[4],ln[4]-ln[3],ln[3]-ln[2],ln[2]-ln[1]); w <- .5^(0:3)
  expect_equal(f$exp050,sum(d*w)/sum(w),tolerance=1e-14)
  bad <- p[p$weekF!=10,]
  expect_error(.page_a_shadow_runtime_features(bad,12L),'exact weeks')
})

test_that('EXP050 challenger is future invariant and does not replace canonical A1', {
  p <- read.csv(.fixture('ignition-panel.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  fc <- page_v3_forecast(p,season='2026-27',origin_weekF=12L)
  a2 <- fc$forecasts[fc$forecasts$type=='A' & fc$forecasts$horizon==2L,]
  q1 <- .page_a_shadow_predict_exp050_h2(p,12L,100*a2$forecast)
  p2 <- p; p2$y_A[p2$weekF>12] <- p2$N_A[p2$weekF>12]
  q2 <- .page_a_shadow_predict_exp050_h2(p2,12L,100*a2$forecast)
  expect_equal(q1$challenger_forecast_pct,q2$challenger_forecast_pct,tolerance=1e-14)
  expect_equal(q1$canonical_forecast_pct,100*a2$forecast,tolerance=1e-14)
  expect_true(q1$canonical_unchanged)
  expect_identical(q1$challenger_route,'shadow_A1form_EXP050_h2')
})

test_that('trigger request supports OFF default and explicit EXP050 H2', {
  sys.source('scripts/v3_weekly_api_helpers_v4.R',envir=environment())
  cfg <- list(season='2026-27',forecast_release_id=.PAGE_FORECAST_RELEASE_ID)
  base <- sprintf('{"season":"2026-27","expected_release_id":"%s"}',.PAGE_FORECAST_RELEASE_ID)
  exp <- sprintf('{"season":"2026-27","expected_release_id":"%s","a_shadow_option":"exp050_h2"}',.PAGE_FORECAST_RELEASE_ID)
  b <- .api_validate_trigger_request(base,cfg); e <- .api_validate_trigger_request(exp,cfg)
  expect_identical(b$a_shadow_option,'off')
  expect_identical(e$a_shadow_option,'exp050_h2')
  expect_false(identical(.api_request_digest(b,'olis'),.api_request_digest(e,'olis')))
  expect_error(.api_validate_trigger_request(sprintf('{"season":"2026-27","expected_release_id":"%s","a_shadow_option":"bad"}',.PAGE_FORECAST_RELEASE_ID),cfg),'shadow option')
})
