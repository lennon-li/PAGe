#!/usr/bin/env Rscript
options(stringsAsFactors=FALSE)

.parse_args <- function(args) {
  out <- list(transaction_dir=NULL,job_dir=NULL,expected_release_id=NULL,option='off')
  for(a in args) {
    if(!grepl('^--[^=]+=',a)) stop('Arguments must use --key=value.',call.=FALSE)
    k <- gsub('-','_',sub('^--([^=]+)=.*$','\\1',a)); v <- sub('^--[^=]+=','',a)
    if(!k %in% names(out)) stop('Unknown argument: ',k,call.=FALSE); out[[k]] <- v
  }
  if(any(vapply(out[c('transaction_dir','job_dir','expected_release_id')],is.null,logical(1)))) stop('transaction-dir, job-dir, expected-release-id required.',call.=FALSE)
  out
}

.atomic_save_rds <- function(x,path) {
  dir.create(dirname(path),recursive=TRUE,mode='0700',showWarnings=FALSE)
  tmp <- tempfile(pattern=paste0('.',basename(path),'.'),tmpdir=dirname(path)); saveRDS(x,tmp,version=3); Sys.chmod(tmp,'0600')
  if(!file.rename(tmp,path)) { unlink(tmp); stop('Atomic RDS publish failed.',call.=FALSE) }
}

.main <- function(args=commandArgs(trailingOnly=TRUE)) {
  opt <- .parse_args(args); setwd(normalizePath('.',winslash='/',mustWork=TRUE))
  for(f in sort(list.files('PAGe/R',pattern='[.]R$',full.names=TRUE))) sys.source(f,envir=.GlobalEnv)
  sys.source('scripts/v3_a_shadow_helpers_v1.R',envir=.GlobalEnv)
  if(!identical(opt$expected_release_id,.PAGE_V3_RELEASE_ID)) stop('Unexpected release ID.',call.=FALSE)
  snap <- .page_a_shadow_snapshot(normalizePath(opt$transaction_dir,winslash='/',mustWork=TRUE),opt$option)
  if(!identical(snap$release_id,opt$expected_release_id)) stop('Snapshot release mismatch.',call.=FALSE)
  path <- file.path(opt$job_dir,'a_shadow_snapshot.rds'); .atomic_save_rds(snap,path)
  if(!requireNamespace('digest',quietly=TRUE)) stop('digest required.',call.=FALSE)
  sha <- digest::digest(file=path,algo='sha256',serialize=FALSE)
  writeLines(sha,file.path(opt$job_dir,'a_shadow_snapshot.sha256'),useBytes=TRUE)
  cat('a_shadow_option=',snap$option,' status=',snap$status,' sha256=',sha,'\n',sep='')
  if(!is.null(snap$challenger)) print(as.data.frame(snap$challenger[c('type','horizon','canonical_forecast_pct','challenger_forecast_pct','delta_challenger_minus_canonical_pp')]),row.names=FALSE)
  invisible(TRUE)
}

if(sys.nframe()==0L) .main(commandArgs(trailingOnly=TRUE))
