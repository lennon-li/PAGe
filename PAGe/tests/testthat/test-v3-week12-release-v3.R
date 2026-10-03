find_page_repo_root_week12_release <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'scripts','build_v3_shadow_release_v3.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

.latest_week12_release <- function(repo) {
  root <- file.path(repo,'artifacts','v3-shadow-release-v3')
  if (!dir.exists(root)) return(NA_character_)
  d <- list.dirs(root,recursive=FALSE,full.names=TRUE)
  d <- d[file.exists(file.path(d,'release_id.txt'))]
  if (!length(d)) return(NA_character_)
  d[[order(file.info(d)$mtime,decreasing=TRUE)[1]]]
}

test_that('weekF12 release builder inputs are present and canonical component versions are explicit', {
  repo <- find_page_repo_root_week12_release(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  expect_true(file.exists('artifacts/v3-b-activity-window12-40-v1/B_window12_40_detection.rds'))
  expect_true(file.exists('artifacts/v3-joint-timing-contract-v4/timing_contract_v4.csv'))
  expect_true(file.exists('artifacts/m1-b-v3-peak-v10/m1_b_v3_peak_artifact.rds'))
  expect_true(file.exists('artifacts/m2-b-v3-shadow-v5/m2_b_v3_shadow_artifact.rds'))
  inv <- read.csv('governance/v3_week12_component_inventory_v1.csv',stringsAsFactors=FALSE,check.names=FALSE)
  expect_true(any(grepl('window12-40',unlist(inv),fixed=TRUE)))
  expect_true(any(grepl('peak-v10',unlist(inv),fixed=TRUE)))
  expect_true(any(grepl('shadow-v5',unlist(inv),fixed=TRUE)))
  expect_false(any(grepl('canonical.*weekF3',apply(inv,1,paste,collapse=' '),ignore.case=TRUE)))
})

test_that('published weekF12 release validates and binds exact runtime source closure', {
  repo <- find_page_repo_root_week12_release(); skip_if(is.na(repo),'PAGe repo unavailable')
  release_dir <- .latest_week12_release(repo); skip_if(is.na(release_dir),'weekF12 release not built yet')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_shadow_release_helpers_v1.R',local=environment())
  stale <- release_dir_stale_reason(release_dir)
  skip_if(!is.null(stale),stale)
  got <- .v3_release_validate(release_dir)
  expect_identical(got$release_id,basename(release_dir))
  m <- got$manifest
  expect_true(any(m$path=='2026/run_weekly_shadow_v3_week12_v1.R'))
  expect_true(any(m$path=='2026/run_weekly_m2_b_shadow_v5.R'))
  expect_true(any(m$path=='2026/run_weekly_shadow_release_v5.R'))
  expect_true(any(m$path=='artifacts/m1-b-v3-peak-v10/m1_b_v3_peak_artifact.rds'))
  expect_true(any(m$path=='artifacts/m2-b-v3-shadow-v5/m2_b_v3_shadow_artifact.rds'))
  expect_true(any(m$path=='artifacts/v3-b-activity-window12-40-v1/B_window12_40_detection.rds'))
  expect_true(any(m$path=='artifacts/v3-joint-timing-contract-v4/timing_contract_v4.csv'))
  expect_true(all(sort(m$path[m$role=='runtime_package_source']) == sort(list.files('PAGe/R',pattern='[.]R$',full.names=TRUE))))
})
