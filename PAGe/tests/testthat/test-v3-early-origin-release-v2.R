find_page_repo_root_early_release <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'2026','run_weekly_shadow_release_v4.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

.latest_early_release <- function(repo) {
  root <- file.path(repo,'artifacts','v3-shadow-release-v2')
  if (!dir.exists(root)) return(NA_character_)
  dirs <- list.dirs(root,recursive=FALSE,full.names=TRUE)
  dirs <- dirs[!grepl('/[.]pending-',dirs)]
  if (!length(dirs)) return(NA_character_)
  source(file.path(repo,'scripts','v3_shadow_release_helpers_v1.R'),local=TRUE)
  ok <- vapply(dirs,function(d) {
    tryCatch({ .v3_release_validate(d); TRUE },error=function(e) FALSE)
  },logical(1))
  dirs <- dirs[ok]
  if (!length(dirs)) return(NA_character_)
  dirs[[length(dirs)]]
}

test_that('early-origin authoritative transaction hashes the serialized typed panel and publishes weekF11', {
  repo <- find_page_repo_root_early_release(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  release_dir <- .latest_early_release(repo); skip_if(is.na(release_dir),'current early-origin release unavailable')
  source('2026/run_weekly_shadow_release_v4.R',local=environment())

  td <- tempfile('early-release-tx-'); dir.create(td)
  f <- file.path(td,'hist.RData')
  dates <- as.Date('2026-07-05') + 7*(0:10)
  r <- list(
    fluA=data.frame(date=dates,pos=c(2,3,4,5,8,12,18,26,38,62,115),tests=c(rep(4000,10),6599)),
    fluB=data.frame(date=dates,pos=c(0,0,1,0,1,1,1,2,1,2,2),tests=c(rep(4000,10),6530)))
  save(r,file=f)

  res <- .shadow_release_main(c('--season=2026-27','--source=olis',paste0('--input=',f),paste0('--release-dir=',release_dir),paste0('--output-root=',file.path(td,'out'))))
  expect_identical(res$origin_weekF,11L)
  expect_true(file.exists(file.path(res$run_dir,'COMPLETED')))
  cmp <- read.csv(file.path(res$run_dir,'v2_v3_comparison.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  expect_identical(nrow(cmp),4L)
  expect_true(all(is.finite(cmp$v3_forecast_pct)))
  expect_true(all(cmp$release_id==res$release_id))
  expect_identical(length(unique(cmp$effective_panel_sha256)),1L)

  tx <- .shadow_release_read_tsv(file.path(res$run_dir,'source_transaction.tsv'))
  typed <- read.csv(file.path(res$run_dir,'typed_ab_weekly.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  expected_eff <- .shadow_ops_effective_panel_sha256(typed,'2026-27')
  expect_identical(unname(tx[['effective_panel_sha256']]),expected_eff)

  v2_prov <- list.files(file.path(res$run_dir,'v2'),pattern='provenance[.]tsv$',recursive=TRUE,full.names=TRUE)
  v3_prov <- list.files(file.path(res$run_dir,'v3'),pattern='provenance[.]tsv$',recursive=TRUE,full.names=TRUE)
  expect_identical(length(v2_prov),1L); expect_identical(length(v3_prov),1L)
  p2 <- .shadow_release_read_tsv(v2_prov); p3 <- .shadow_release_read_tsv(v3_prov)
  expect_identical(unname(p2[['effective_panel_sha256']]),expected_eff)
  expect_identical(unname(p3[['effective_panel_sha256']]),expected_eff)
  expect_identical(unname(p2[['supplied_typed_panel_sha256']]),unname(tx[['supplied_typed_panel_sha256']]))
  expect_identical(unname(p3[['supplied_typed_panel_sha256']]),unname(tx[['supplied_typed_panel_sha256']]))
})
