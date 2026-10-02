find_page_repo_root_orvt_readiness <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates, '2026', 'run_page_orvt_source_preflight_v1.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]], winslash = '/', mustWork = TRUE)
}

.make_orvt_ab_fixture <- function(path, repo) {
  src <- file.path(repo, 'PAGe', 'tests', 'testthat', 'fixtures', 'orvt_new.txt')
  x <- utils::read.csv(src, stringsAsFactors = FALSE, check.names = FALSE)
  b <- x
  b$Virus <- 'Influenza B'
  b$`# of positive tests` <- pmax(0, floor(b$`# of positive tests` / 2))
  b$`Percent positivity (%)` <- 100 * b$`# of positive tests` / b$`Total # of tests`
  utils::write.csv(rbind(x, b), path, row.names = FALSE)
  invisible(path)
}

test_that('ORVT source preflight accepts the required origin and rejects stale publication', {
  repo <- find_page_repo_root_orvt_readiness()
  skip_if(is.na(repo), 'PAGe repo unavailable')
  old <- setwd(repo)
  on.exit(setwd(old), add = TRUE)

  td <- tempfile('orvt-preflight-test-')
  dir.create(td)
  input <- .make_orvt_ab_fixture(file.path(td, 'orvt.csv'), repo)
  rscript <- file.path(R.home('bin'), 'Rscript')

  pass_json <- file.path(td, 'pass.json')
  pass_out <- system2(
    rscript,
    c('--vanilla', '2026/run_page_orvt_source_preflight_v1.R',
      '--season=2026-27', '--min-weekF=9', paste0('--input=', input),
      paste0('--result-path=', pass_json)),
    stdout = TRUE, stderr = TRUE
  )
  pass_status <- attr(pass_out, 'status')
  if (is.null(pass_status)) pass_status <- 0L
  expect_identical(as.integer(pass_status), 0L)
  pass <- jsonlite::fromJSON(pass_json, simplifyVector = TRUE)
  expect_true(isTRUE(pass$ok))
  expect_identical(pass$source_mode, 'orvt')
  expect_identical(as.integer(pass$origin_weekF), 9L)
  expect_true(is.finite(pass$A$N) && is.finite(pass$B$N))

  fail_json <- file.path(td, 'fail.json')
  fail_out <- suppressWarnings(system2(
    rscript,
    c('--vanilla', '2026/run_page_orvt_source_preflight_v1.R',
      '--season=2026-27', '--min-weekF=10', paste0('--input=', input),
      paste0('--result-path=', fail_json)),
    stdout = TRUE, stderr = TRUE
  ))
  fail_status <- attr(fail_out, 'status')
  expect_identical(as.integer(fail_status), 1L)
  fail <- jsonlite::fromJSON(fail_json, simplifyVector = TRUE)
  expect_false(isTRUE(fail$ok))
  expect_match(fail$detail, 'latest weekF is 9, below required minimum 10', fixed = TRUE)
})

test_that('API sanitized worker environment preserves transport configuration', {
  repo <- find_page_repo_root_orvt_readiness()
  skip_if(is.na(repo), 'PAGe repo unavailable')
  old <- setwd(repo)
  on.exit(setwd(old), add = TRUE)
  local_env <- new.env(parent = globalenv())
  sys.source('2026/page_weekly_api_v4.R', envir = local_env)

  withr::local_envvar(c(
    HTTPS_PROXY = 'http://proxy.invalid:8080',
    NO_PROXY = '127.0.0.1,localhost',
    SSL_CERT_FILE = '/tmp/page-test-ca.pem'
  ))
  env <- local_env$.page_api_sanitized_env()
  expect_identical(unname(env[['HTTPS_PROXY']]), 'http://proxy.invalid:8080')
  expect_identical(unname(env[['NO_PROXY']]), '127.0.0.1,localhost')
  expect_identical(unname(env[['SSL_CERT_FILE']]), '/tmp/page-test-ca.pem')
  expect_identical(unname(env[['R_PROFILE_USER']]), '/dev/null')
  expect_identical(unname(env[['R_ENVIRON_USER']]), '/dev/null')
})


test_that('weekly trigger enforces official source mode and minimum origin', {
  repo <- find_page_repo_root_orvt_readiness()
  skip_if(is.na(repo), 'PAGe repo unavailable')
  skip_if(Sys.which('sh') == '', 'sh unavailable')
  skip_if(Sys.which('jq') == '', 'jq unavailable')

  td <- tempfile('orvt-trigger-test-')
  dir.create(td)
  cycle <- file.path(td, 'cycle')
  body <- file.path(td, 'body.json')
  cfg <- file.path(td, 'curl.cfg')
  fake_curl <- file.path(td, 'curl')
  provenance_file <- file.path(td, 'provenance.json')
  writeLines('cycle-test', cycle)
  Sys.chmod(cycle, '0600')
  writeLines('{}', body)
  writeLines('# fake curl config', cfg)
  writeLines(c(
    '#!/bin/sh',
    'case "$*" in',
    '  *"-X POST"*) printf \'%s\\n\' \'{"run_id":"wr_test"}\' ;;',
    '  *"/provenance"*) cat "${FAKE_PROVENANCE_FILE:?}" ;;',
    '  *"/v1/weekly-runs/wr_test"*) printf \'%s\\n\' \'{"status":"succeeded"}\' ;;',
    '  *) exit 7 ;;',
    'esac'
  ), fake_curl)
  Sys.chmod(fake_curl, '0755')

  trigger <- file.path(repo, 'deploy', 'systemd', 'page-weekly-trigger')
  run_case <- function(provenance) {
    writeLines(provenance, provenance_file)
    env <- c(
      paste0('PATH=', td, .Platform$path.sep, Sys.getenv('PATH')),
      paste0('FAKE_PROVENANCE_FILE=', provenance_file),
      'PAGE_API_URL=http://127.0.0.1:8088',
      paste0('PAGE_WEEKLY_CYCLE_ID_FILE=', cycle),
      paste0('PAGE_TRIGGER_CURL_CONFIG=', cfg),
      paste0('PAGE_TRIGGER_BODY=', body),
      'PAGE_TRIGGER_POLL_SECONDS=0',
      'PAGE_TRIGGER_MAX_POLLS=1',
      'PAGE_TRIGGER_REQUIRE_SOURCE_MODE=orvt',
      'PAGE_TRIGGER_MIN_WEEKF=12'
    )
    out <- system2('sh', trigger, stdout = TRUE, stderr = TRUE, env = env)
    status <- attr(out, 'status')
    if (is.null(status)) status <- 0L
    list(out = out, status = as.integer(status))
  }

  good <- run_case('{"source_mode":"orvt","origin_weekF":12}')
  expect_identical(good$status, 0L)

  stale <- suppressWarnings(run_case('{"source_mode":"orvt","origin_weekF":11}'))
  expect_identical(stale$status, 1L)
  expect_true(any(grepl('origin_weekF=11; required minimum=12', stale$out, fixed = TRUE)))

  fallback <- suppressWarnings(run_case('{"source_mode":"olis","origin_weekF":12}'))
  expect_identical(fallback$status, 1L)
  expect_true(any(grepl('source_mode=olis; required=orvt', fallback$out, fixed = TRUE)))
})
