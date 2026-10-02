find_page_repo_root_v3_governance <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'scripts','v3_shadow_ops_helpers_v1.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

test_that('pure typed-panel validator rejects repairable-looking invalid inputs', {
  repo <- find_page_repo_root_v3_governance(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_shadow_ops_helpers_v1.R',local=environment())
  x <- read.csv('artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv',check.names=FALSE)
  z <- x[x$season=='2025-26' & x$weekF<=20,c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')]
  z$season <- '2026-27'
  expect_true(.shadow_ops_validate_panel(z,'2026-27'))
  bad <- z; bad$p_A[3] <- bad$p_A[3]+.001
  expect_error(.shadow_ops_validate_panel(bad,'2026-27'),'A proportions do not match y/N',fixed=TRUE)
  bad <- z[-5,,drop=FALSE]
  expect_error(.shadow_ops_validate_panel(bad,'2026-27'),'weekF coverage must be contiguous',fixed=TRUE)
  bad <- z[c(2,1,3:nrow(z)),]
  expect_error(.shadow_ops_validate_panel(bad,'2026-27'),'rows must be sorted',fixed=TRUE)
})

test_that('v2 default OLIS ingestion and typed-panel replay are identical', {
  repo <- find_page_repo_root_v3_governance(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('2026/run_weekly_shadow_v2.R',local=environment())
  td <- tempfile('v2-golden-'); dir.create(td)
  f <- file.path(td,'hist.RData')
  dates <- as.Date('2026-07-05') + 7*(0:14)
  r <- list(
    fluA=data.frame(date=dates,pos=round(seq(2,30,length.out=15)),tests=rep(1000,15)),
    fluB=data.frame(date=dates,pos=round(seq(1,8,length.out=15)),tests=rep(1000,15)))
  save(r,file=f)
  raw <- .shadow_v2_main(c('--season=2026-27','--source=olis',paste0('--input=',f),paste0('--output-root=',file.path(td,'raw'))))
  typed_path <- file.path(td,'typed.csv'); write.csv(raw$panel,typed_path,row.names=FALSE)
  typed <- .shadow_v2_main(c('--season=2026-27',paste0('--typed-panel=',typed_path),paste0('--output-root=',file.path(td,'typed'))))
  expect_identical(raw$provenance$effective_panel_sha256,typed$provenance$effective_panel_sha256)
  expect_equal(raw$m2$predictions$pred_selected,typed$m2$predictions$pred_selected,tolerance=0)
  expect_identical(raw$m1$status,typed$m1$status)
})
