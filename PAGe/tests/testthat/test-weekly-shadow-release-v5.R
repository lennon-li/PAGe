find_page_repo_root_week12_launcher <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'2026','run_weekly_shadow_release_v5.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

.latest_week12_release_dir <- function(repo) {
  root <- file.path(repo,'artifacts','v3-shadow-release-v3')
  if (!dir.exists(root)) return(NA_character_)
  d <- list.dirs(root,recursive=FALSE,full.names=TRUE)
  d <- d[file.exists(file.path(d,'release_id.txt'))]
  if (!length(d)) return(NA_character_)
  d[[order(file.info(d)$mtime,decreasing=TRUE)[1]]]
}

.make_week12_olis <- function(path,n_weeks=12L) {
  dates <- as.Date('2026-07-05') + 7*(0:(n_weeks-1L))
  r <- list(
    fluA=data.frame(date=dates,pos=round(seq(2,24,length.out=n_weeks)),tests=rep(1000,n_weeks)),
    fluB=data.frame(date=dates,pos=round(seq(1,6,length.out=n_weeks)),tests=rep(1000,n_weeks))
  )
  save(r,file=path)
}

test_that('authoritative weekF12 launcher produces four finite v2/v3 comparison rows', {
  repo <- find_page_repo_root_week12_launcher(); skip_if(is.na(repo),'PAGe repo unavailable')
  release_dir <- .latest_week12_release_dir(repo); skip_if(is.na(release_dir),'weekF12 release not built yet')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('2026/run_weekly_shadow_release_v5.R',local=environment())
  stale <- release_dir_stale_reason(release_dir); skip_if(!is.null(stale),stale)
  td <- tempfile('week12-release-'); dir.create(td)
  f <- file.path(td,'hist.RData'); .make_week12_olis(f,12L)
  res <- .shadow_release_main(c('--season=2026-27','--source=olis',paste0('--input=',f),paste0('--release-dir=',release_dir),paste0('--output-root=',file.path(td,'out'))))
  expect_identical(as.integer(res$origin_weekF),12L)
  expect_true(file.exists(file.path(res$run_dir,'COMPLETED')))
  cmp <- read.csv(file.path(res$run_dir,'v2_v3_comparison.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  expect_identical(nrow(cmp),4L)
  expect_true(all(is.finite(cmp$v2_forecast_pct)))
  expect_true(all(is.finite(cmp$v3_forecast_pct)))
  expect_true(all(cmp$release_id==res$release_id))
  expect_true(length(unique(cmp$effective_panel_sha256))==1L)
  expect_true(all(cmp$v3_route %in% c('exact_A1_state','exact_B1_state','exact_B1_fallback')))
})

test_that('authoritative weekF12 launcher refuses weekF11 source before child issuance', {
  repo <- find_page_repo_root_week12_launcher(); skip_if(is.na(repo),'PAGe repo unavailable')
  release_dir <- .latest_week12_release_dir(repo); skip_if(is.na(release_dir),'weekF12 release not built yet')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('2026/run_weekly_shadow_release_v5.R',local=environment())
  stale <- release_dir_stale_reason(release_dir); skip_if(!is.null(stale),stale)
  td <- tempfile('week11-release-'); dir.create(td)
  f <- file.path(td,'hist.RData'); .make_week12_olis(f,11L)
  out_root <- file.path(td,'out')
  expect_error(.shadow_release_main(c('--season=2026-27','--source=olis',paste0('--input=',f),paste0('--release-dir=',release_dir),paste0('--output-root=',out_root))),'origin weekF >= 12',fixed=TRUE)
  season_root <- file.path(out_root,'2026-27')
  publishable <- if (dir.exists(season_root)) setdiff(list.dirs(season_root,recursive=FALSE,full.names=FALSE),c('.pending','failures')) else character()
  expect_length(publishable,0L)
})
