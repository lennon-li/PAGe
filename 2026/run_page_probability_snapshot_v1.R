#!/usr/bin/env Rscript
options(stringsAsFactors=FALSE)

.parse_args <- function(args) {
  out <- list(transaction_dir=NULL,job_dir=NULL,expected_release_id=NULL)
  for (a in args) {
    if (!grepl('^--[^=]+=',a)) stop('Arguments must use --key=value.',call.=FALSE)
    k <- gsub('-','_',sub('^--([^=]+)=.*$','\\1',a)); v <- sub('^--[^=]+=','',a)
    if (!k %in% names(out)) stop('Unknown argument.',call.=FALSE)
    out[[k]] <- v
  }
  if (any(vapply(out,is.null,logical(1)))) stop('--transaction-dir, --job-dir, and --expected-release-id are required.',call.=FALSE)
  out
}

.read_kv <- function(path) {
  x <- utils::read.delim(path,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  if (!identical(names(x),c('key','value')) || anyDuplicated(x$key)) stop('Transaction receipt schema invalid.',call.=FALSE)
  setNames(as.character(x$value),as.character(x$key))
}

.main <- function(args=commandArgs(trailingOnly=TRUE)) {
  opt <- .parse_args(args)
  if (!file.exists('PAGe/DESCRIPTION')) stop('Run from PAGe repository root.',call.=FALSE)
  tx <- normalizePath(opt$transaction_dir,winslash='/',mustWork=TRUE)
  job <- normalizePath(opt$job_dir,winslash='/',mustWork=TRUE)
  receipt <- .read_kv(file.path(tx,'source_transaction.tsv'))
  if (!identical(receipt[['status']],'COMPLETE') || !identical(receipt[['release_id']],opt$expected_release_id)) stop('Transaction/release identity mismatch.',call.=FALSE)
  season <- as.character(receipt[['season']]); origin <- suppressWarnings(as.integer(receipt[['origin_weekF']]))
  if (is.na(origin) || origin < 1L) stop('Invalid transaction origin.',call.=FALSE)
  panel <- utils::read.csv(file.path(tx,'typed_ab_weekly.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  cmp <- utils::read.csv(file.path(tx,'v2_v3_comparison.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  if (nrow(cmp)!=4L || !setequal(paste(cmp$type,cmp$horizon),c('A 1','A 2','B 1','B 2'))) stop('Comparison ledger invalid.',call.=FALSE)

  files <- sort(list.files('PAGe/R',pattern='[.]R$',full.names=TRUE))
  for (f in files) sys.source(f,envir=.GlobalEnv)
  sys.source('scripts/v3_probability_helpers_v1.R',envir=.GlobalEnv)
  fc <- page_forecast(panel,season=season,origin_weekF=origin)
  if (!identical(fc$release_id,opt$expected_release_id) || !isTRUE(fc$issued)) stop('Package-native v3 probability runtime identity mismatch.',call.=FALSE)
  pp <- fc$forecasts[,c('type','horizon','forecast','route'),drop=FALSE]
  z <- merge(cmp[,c('type','horizon','v3_forecast_pct','v3_route')],pp,by=c('type','horizon'),all=TRUE,sort=FALSE)
  if (nrow(z)!=4L || anyNA(z) || any(abs(z$v3_forecast_pct/100-z$forecast)>1e-12) || any(z$v3_route!=z$route)) stop('Package-native v3 probability runtime does not match issued transaction forecasts.',call.=FALSE)

  snapshot <- .page_v3_probability_snapshot(fc)
  if (!identical(snapshot$release_id,opt$expected_release_id) || !identical(snapshot$season,season) || !identical(snapshot$origin_weekF,origin)) stop('Probability snapshot identity mismatch.',call.=FALSE)
  if (!requireNamespace('digest',quietly=TRUE)) stop('digest package unavailable.',call.=FALSE)
  final <- file.path(job,'probability_snapshot.rds')
  sha_final <- file.path(job,'probability_snapshot.sha256')
  if (file.exists(final) || file.exists(sha_final)) stop('Probability snapshot output already exists.',call.=FALSE)
  tmp <- tempfile('.probability_snapshot.',tmpdir=job,fileext='.rds')
  on.exit(unlink(tmp),add=TRUE)
  saveRDS(snapshot,tmp,version=3)
  sha <- digest::digest(file=tmp,algo='sha256',serialize=FALSE)
  if (!file.rename(tmp,final)) stop('Could not atomically publish probability snapshot.',call.=FALSE)
  writeLines(sha,sha_final,useBytes=TRUE)
  Sys.chmod(c(final,sha_final),mode='0600')
  cat('probability_snapshot_sha256=',sha,'\n',sep='')
  invisible(list(path=final,sha256=sha))
}

if (sys.nframe()==0L) .main(commandArgs(trailingOnly=TRUE))
