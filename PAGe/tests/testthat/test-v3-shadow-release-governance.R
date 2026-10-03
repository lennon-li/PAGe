find_page_repo_root_release_v3 <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'scripts','v3_shadow_release_helpers_v1.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

.latest_v3_release_dir <- function(repo) {
  root <- file.path(repo,'artifacts','v3-shadow-release-v1')
  if (!dir.exists(root)) return(NA_character_)
  d <- list.dirs(root,recursive=FALSE,full.names=TRUE)
  d <- d[file.exists(file.path(d,'release_id.txt'))]
  if (!length(d)) return(NA_character_)
  d[[order(file.info(d)$mtime,decreasing=TRUE)[1]]]
}

test_that('release manifest canonicalization and release ID are order invariant', {
  repo <- find_page_repo_root_release_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_shadow_release_helpers_v1.R',local=environment())
  paths <- c('governance/v3_b_season_policy_v1.csv','governance/v3_runtime_environment_v1.tsv')
  m <- .v3_release_manifest_frame(c('policy','runtime_environment'),paths)
  expect_identical(.v3_release_id_from_manifest(m),.v3_release_id_from_manifest(m[2:1,,drop=FALSE]))
  expect_error(.v3_release_manifest_frame(c('x','x'),c(paths[1],paths[1])),'Duplicate release manifest role/path',fixed=TRUE)
})

test_that('published release validates full hashes environment and exact PAGe/R closure', {
  repo <- find_page_repo_root_release_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  release_dir <- .latest_v3_release_dir(repo); skip_if(is.na(release_dir),'v3 release unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_shadow_release_helpers_v1.R',local=environment())
  stale <- release_dir_stale_reason(release_dir)
  skip_if(!is.null(stale),stale)
  got <- .v3_release_validate(release_dir)
  expect_identical(got$release_id,basename(release_dir))
  manifest <- got$manifest
  expect_true(all(sort(manifest$path[manifest$role=='runtime_package_source']) == sort(list.files('PAGe/R',pattern='[.]R$',full.names=TRUE))))
  expect_identical(sum(manifest$role=='runtime_environment'),1L)
  env_path <- manifest$path[manifest$role=='runtime_environment'][[1]]
  runtime_env <- read.delim(env_path,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  expected_runtime_packages <- c('data.table','digest','lattice','Matrix','mgcv','MMWRweek','nlme')
  expect_setequal(setdiff(runtime_env$component,'R'),expected_runtime_packages)
  observed_versions <- vapply(expected_runtime_packages,function(pkg) as.character(packageVersion(pkg)),character(1))
  declared_versions <- setNames(runtime_env$version,runtime_env$component)[expected_runtime_packages]
  expect_identical(unname(declared_versions),unname(observed_versions))

  # Unexpected dynamically sourced code must fail preflight.
  surprise <- 'PAGe/R/__v3_release_unexpected_test__.R'
  writeLines('# temporary release-closure test',surprise)
  on.exit(unlink(surprise),add=TRUE)
  expect_error(.v3_release_validate(release_dir),'runtime package-source set differs',fixed=TRUE)
  unlink(surprise)
})

test_that('authoritative one-source launcher gives v2 and v3 the same release and effective panel', {
  repo <- find_page_repo_root_release_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  release_dir <- .latest_v3_release_dir(repo); skip_if(is.na(release_dir),'v3 release unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('2026/run_weekly_shadow_release_v3.R',local=environment())

  stale <- release_dir_stale_reason(release_dir); skip_if(!is.null(stale),stale)
  td <- tempfile('release-tx-'); dir.create(td)
  f <- file.path(td,'hist.RData')
  dates <- as.Date('2026-07-05') + 7*(0:14)
  r <- list(
    fluA=data.frame(date=dates,pos=round(seq(2,30,length.out=15)),tests=rep(1000,15)),
    fluB=data.frame(date=dates,pos=round(seq(1,8,length.out=15)),tests=rep(1000,15)))
  save(r,file=f)
  res <- .shadow_release_main(c('--season=2026-27','--source=olis',paste0('--input=',f),paste0('--release-dir=',release_dir),paste0('--output-root=',file.path(td,'out'))))
  expect_true(file.exists(file.path(res$run_dir,'COMPLETED')))
  expect_true(file.exists(file.path(res$run_dir,'v2_v3_comparison.csv')))
  cmp <- read.csv(file.path(res$run_dir,'v2_v3_comparison.csv'),check.names=FALSE)
  expect_identical(nrow(cmp),4L)
  expect_true(all(cmp$release_id==res$release_id))
  expect_true(length(unique(cmp$effective_panel_sha256))==1L)
  tx <- .shadow_release_read_tsv(file.path(res$run_dir,'source_transaction.tsv'))
  expect_identical(unname(tx[['status']]),'COMPLETE')
  expect_identical(unname(tx[['release_id']]),res$release_id)
})


test_that('authoritative launcher publishes only after staged transaction is fully complete', {
  repo <- find_page_repo_root_release_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  release_dir <- .latest_v3_release_dir(repo); skip_if(is.na(release_dir),'v3 release unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('2026/run_weekly_shadow_release_v3.R',local=environment())

  stale <- release_dir_stale_reason(release_dir); skip_if(!is.null(stale),stale)
  td <- tempfile('release-tx-failure-'); dir.create(td)
  f <- file.path(td,'hist.RData')
  dates <- as.Date('2026-07-05') + 7*(0:14)
  r <- list(
    fluA=data.frame(date=dates,pos=round(seq(2,30,length.out=15)),tests=rep(1000,15)),
    fluB=data.frame(date=dates,pos=round(seq(1,8,length.out=15)),tests=rep(1000,15)))
  save(r,file=f)

  # Inject a failure in finalization before the publish rename. A correct
  # transaction must leave no final-looking comparison directory.
  .shadow_release_rebase_tsv <- function(...) stop('injected pre-publish failure',call.=FALSE)
  out_root <- file.path(td,'out')
  expect_error(
    .shadow_release_main(c('--season=2026-27','--source=olis',paste0('--input=',f),paste0('--release-dir=',release_dir),paste0('--output-root=',out_root))),
    'injected pre-publish failure',fixed=TRUE)

  season_root <- file.path(out_root,'2026-27')
  top <- list.dirs(season_root,recursive=FALSE,full.names=FALSE)
  publishable <- setdiff(top,c('.pending','failures'))
  expect_length(publishable,0L)
  receipts <- list.files(file.path(season_root,'failures'),pattern='[.]tsv$',full.names=TRUE)
  expect_length(receipts,1L)
  failed_dirs <- list.dirs(file.path(season_root,'.pending'),recursive=FALSE,full.names=TRUE)
  expect_true(any(grepl('-FAILED$',failed_dirs)))
  expect_false(any(file.exists(file.path(failed_dirs,'COMPLETED'))))
})
