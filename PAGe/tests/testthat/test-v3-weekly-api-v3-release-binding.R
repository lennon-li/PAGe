library(testthat)

find_repo_api_v3 <- function() {
  d <- normalizePath(getwd(), winslash = '/', mustWork = TRUE)
  for (i in 0:6) {
    if (file.exists(file.path(d, 'PAGe/DESCRIPTION'))) return(d)
    d <- dirname(d)
  }
  stop('repo root not found')
}

make_olis_fixture <- function(path, n_weeks) {
  dates <- as.Date('2026-07-05') + 7 * seq.int(0, n_weeks - 1L)
  flu_a_pos <- c(2, 3, 4, 5, 8, 12, 18, 26, 38, 62, 115, 154)
  flu_b_pos <- c(0, 0, 1, 0, 1, 1, 1, 2, 1, 2, 2, 3)
  r <- list(
    fluA = data.frame(date = dates, pos = flu_a_pos[seq_along(dates)], tests = rep(4000, n_weeks)),
    fluB = data.frame(date = dates, pos = flu_b_pos[seq_along(dates)], tests = rep(4000, n_weeks))
  )
  save(r, file = path)
}

run_api_v3_worker <- function(repo, dep, mount, fixture, run_id) {
  source('scripts/v3_weekly_api_helpers_v3.R', local = TRUE)
  job <- file.path(mount, 'jobs')
  out <- file.path(mount, 'out')
  cfg <- list(
    repo_root = repo, api_deployment_dir = dep$deployment_dir, job_root = job,
    output_root = out, artifact_mount = mount, season = '2026-27',
    source_mode = 'olis', forecast_release_id = .PAGE_FORECAST_RELEASE_ID,
    forecast_release_dir = file.path(repo, 'artifacts/v3-shadow-release-v3', .PAGE_FORECAST_RELEASE_ID),
    rscript = Sys.which('Rscript'), max_runtime_seconds = 300L, olis_fallback = fixture,
    transaction_schema = file.path(repo, 'governance/v3_weekly_api_transaction_schema_v1.csv'),
    api_environment = file.path(repo, 'governance/v3_weekly_api_environment_v1.tsv')
  )
  jd <- .api_job_dir(cfg, run_id)
  dir.create(jd, recursive = TRUE)
  .api_atomic_write_json(list(run_id = run_id, api_contract_version = .PAGE_API_CONTRACT,
    season = '2026-27', expected_release_id = .PAGE_FORECAST_RELEASE_ID,
    source_mode = 'olis', created_utc = .api_now(), service_instance_id = 'test'),
    .api_request_path(cfg, run_id), TRUE)
  .api_atomic_write_json(.api_external_worker_config(cfg), file.path(jd, 'worker_config.json'), TRUE)
  env <- c(PATH = Sys.getenv('PATH'), HOME = '/nonexistent/page-api-home',
    R_LIBS_USER = '/nonexistent/page-api-user-library',
    R_LIBS_SITE = '/usr/local/lib/R/site-library:/usr/lib/R/site-library',
    R_PROFILE_USER = '/dev/null', R_ENVIRON_USER = '/dev/null', TZ = 'UTC',
    LANG = 'C.UTF-8', LC_ALL = 'C.UTF-8')
  proc <- processx::run(Sys.which('Rscript'), c('--vanilla',
    '2026/run_page_weekly_api_worker_v3.R', paste0('--job-root=', job),
    paste0('--run-id=', run_id)), wd = repo, env = env, timeout = 360000,
    stdout = '|', stderr = '|', error_on_status = FALSE)
  list(proc = proc, cfg = cfg, job_dir = jd)
}

test_that('API v3 binds canonical weekF12 release and closes weekF11', {
  skip_if_not_installed('processx')
  repo <- find_repo_api_v3()
  old <- setwd(repo)
  on.exit(setwd(old), add = TRUE)
  source('scripts/v3_weekly_api_helpers_v3.R')
  source('scripts/v3_weekly_api_deployment_helpers_v3.R')
  source('scripts/build_v3_weekly_api_deployment_v3.R', local = environment())

  expect_identical(.PAGE_API_CONTRACT, 'page-weekly-api-v3')
  expect_identical(.PAGE_FORECAST_RELEASE_ID,
    '5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b')

  td <- tempfile('api-v3-binding-')
  dir.create(td)
  mount <- file.path(td, 'mount')
  job <- file.path(mount, 'jobs')
  out <- file.path(mount, 'out')
  dep_root <- file.path(mount, 'deployments')
  dir.create(job, recursive = TRUE)
  dir.create(out)
  dir.create(dep_root)
  fixture12 <- file.path(td, 'weekF12.RData')
  fixture11 <- file.path(td, 'weekF11.RData')
  make_olis_fixture(fixture12, 12L)
  make_olis_fixture(fixture11, 11L)
  release_dir <- file.path(repo, 'artifacts/v3-shadow-release-v3', .PAGE_FORECAST_RELEASE_ID)
  opt <- list(deployment_root = dep_root, artifact_mount = mount,
    artifact_fs_type = NULL, artifact_mount_source = NULL, job_root = job,
    output_root = out, source_mode = 'olis', season = '2026-27',
    bind_host = '127.0.0.1', port = '8088', rscript = Sys.which('Rscript'),
    forecast_release_dir = release_dir, olis_fallback = fixture12,
    max_runtime_seconds = '300', mode = 'test')
  dep <- .api_build_deployment(opt, repo)
  manifest <- utils::read.delim(file.path(dep$deployment_dir, 'deployment_manifest.tsv'),
    sep = '\t', stringsAsFactors = FALSE, check.names = FALSE)
  expect_true('scripts/v3_weekly_api_helpers_v3.R' %in% manifest$path)
  expect_true('2026/run_page_weekly_api_worker_v3.R' %in% manifest$path)
  expect_true('2026/run_page_weekly_api_preflight_v3.R' %in% manifest$path)
  expect_true('2026/run_weekly_shadow_release_v5.R' %in% manifest$path)
  expect_true('2026/page_weekly_api_v1.R' %in% manifest$path)

  pf_path <- file.path(td, 'preflight.json')
  pf <- processx::run(Sys.which('Rscript'), c('--vanilla',
    '2026/run_page_weekly_api_preflight_v3.R',
    paste0('--deployment-dir=', dep$deployment_dir), paste0('--repo-root=', repo),
    paste0('--release-dir=', release_dir),
    paste0('--expected-release-id=', .PAGE_FORECAST_RELEASE_ID),
    paste0('--result-path=', pf_path)), wd = repo, timeout = 120,
    stdout = '|', stderr = '|', error_on_status = FALSE)
  expect_identical(as.integer(pf$status), 0L)
  expect_true(jsonlite::fromJSON(pf_path)$ok)

  run12 <- run_api_v3_worker(repo, dep, mount, fixture12,
    paste0('wr_', paste(rep('1', 32), collapse = '')))
  expect_identical(as.integer(run12$proc$status), 0L,
    info = paste(run12$proc$stdout, run12$proc$stderr))
  result12 <- .api_read_json(file.path(run12$job_dir, 'result.json'))
  expect_identical(as.integer(result12$origin_weekF), 12L)
  expect_identical(result12$release_id, .PAGE_FORECAST_RELEASE_ID)
  expect_length(result12$forecasts, 4L)
  expect_true(all(vapply(result12$forecasts, function(x) is.finite(as.numeric(x$v3_pct)), logical(1))))
  expect_true(all(vapply(result12$forecasts, function(x) x$v3_route %in% .PAGE_ROUTE_ALLOWLIST, logical(1))))
  provenance <- .api_read_json(file.path(run12$job_dir, 'provenance.json'))
  expect_identical(provenance$effective_panel_sha256, result12$effective_panel_sha256)
  expect_identical(provenance$source_mode, 'olis')
  expect_true(file.exists(file.path(run12$job_dir, 'transaction_ref.json')))

  opt11 <- opt
  opt11$olis_fallback <- fixture11
  dep11 <- .api_build_deployment(opt11, repo)
  run11 <- run_api_v3_worker(repo, dep11, mount, fixture11,
    paste0('wr_', paste(rep('2', 32), collapse = '')))
  expect_false(file.exists(file.path(run11$job_dir, 'result.json')))
  receipt <- .api_read_json(.api_worker_result_path(run11$cfg,
    paste0('wr_', paste(rep('2', 32), collapse = ''))))
  expect_identical(receipt$status, 'failed')
  expect_false(identical(receipt$status, 'succeeded'))
  expect_false(file.exists(file.path(run11$job_dir, 'transaction_ref.json')))
})
