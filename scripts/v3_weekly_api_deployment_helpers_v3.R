# Content-addressed deployment identity for PAGe weekly API v3.

.api_dep_sha256 <- function(path) {
  if (!requireNamespace('digest',quietly=TRUE)) stop('digest is required.',call.=FALSE)
  digest::digest(file=path,algo='sha256',serialize=FALSE)
}

.api_dep_canonical_manifest <- function(m) {
  req <- c('role','path','sha256','size_bytes')
  if (!identical(names(m),req)) stop('API deployment manifest columns invalid.',call.=FALSE)
  if (anyNA(m) || anyDuplicated(m$path) || any(!grepl('^[A-Za-z0-9_.-]+$',m$role)) || any(!grepl('^[0-9a-f]{64}$',m$sha256))) stop('API deployment manifest invalid.',call.=FALSE)
  if (any(grepl('^/',m$path)) || any(grepl('(^|/)\\.\\.(/|$)',m$path))) stop('API deployment manifest paths must be repo-relative.',call.=FALSE)
  m <- m[order(m$role,m$path,method='radix'),,drop=FALSE]
  paste0(apply(m,1,function(r) paste(r,collapse='\t')),collapse='\n') |> paste0('\n')
}

.api_dep_canonical_config <- function(cfg) {
  if (is.data.frame(cfg)) {
    if (!identical(names(cfg),c('key','value')) || anyDuplicated(cfg$key)) stop('API effective config invalid.',call.=FALSE)
    kv <- setNames(as.character(cfg$value),as.character(cfg$key))
  } else kv <- cfg
  if (is.null(names(kv)) || anyDuplicated(names(kv)) || any(!nzchar(names(kv)))) stop('API effective config invalid.',call.=FALSE)
  kv <- kv[order(names(kv),method='radix')]
  paste0(paste0(names(kv),'\t',as.character(kv),collapse='\n'),'\n')
}

.api_dep_id <- function(m,cfg) {
  if (!requireNamespace('digest',quietly=TRUE)) stop('digest is required.',call.=FALSE)
  payload <- paste0(.api_dep_canonical_manifest(m),'--effective-config--\n',.api_dep_canonical_config(cfg))
  digest::digest(payload,algo='sha256',serialize=FALSE)
}

.api_dep_read_manifest <- function(path) {
  x <- utils::read.delim(path,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  names(x) <- c('role','path','sha256','size_bytes')
  x$size_bytes <- as.character(x$size_bytes)
  x
}

.api_deployment_validate <- function(deployment_dir,repo_root=getwd(),expected_id=NULL,validate_environment=TRUE,require_content_addressed_name=TRUE) {
  deployment_dir <- normalizePath(deployment_dir,winslash='/',mustWork=TRUE)
  repo_root <- normalizePath(repo_root,winslash='/',mustWork=TRUE)
  mp <- file.path(deployment_dir,'deployment_manifest.tsv'); ip <- file.path(deployment_dir,'deployment_id.txt'); cp <- file.path(deployment_dir,'effective_config.tsv')
  if (!file.exists(mp)||!file.exists(ip)||!file.exists(cp)) stop('API deployment directory is incomplete.',call.=FALSE)
  m <- .api_dep_read_manifest(mp)
  cfg_df <- utils::read.delim(cp,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  id <- .api_dep_id(m,cfg_df); recorded <- trimws(readLines(ip,warn=FALSE,n=1L))
  if (!identical(id,recorded) || (isTRUE(require_content_addressed_name) && !identical(basename(deployment_dir),id)) || (!is.null(expected_id)&&!identical(id,expected_id))) stop('API deployment ID mismatch.',call.=FALSE)
  for (i in seq_len(nrow(m))) {
    p <- file.path(repo_root,m$path[[i]])
    if (!file.exists(p)||dir.exists(p)||nzchar(Sys.readlink(p))) stop('Bound API source missing/non-regular: ',m$path[[i]],call.=FALSE)
    if (!identical(.api_dep_sha256(p),m$sha256[[i]])) stop('Bound API source hash drift: ',m$path[[i]],call.=FALSE)
    if (!identical(as.character(file.info(p)$size[[1]]),as.character(m$size_bytes[[i]]))) stop('Bound API source size drift: ',m$path[[i]],call.=FALSE)
  }
  cfg <- cfg_df
  if (!identical(names(cfg),c('key','value'))||anyDuplicated(cfg$key)) stop('API effective configuration invalid.',call.=FALSE)
  cfg <- setNames(as.character(cfg$value),as.character(cfg$key))
  if (!identical(cfg[['forecast_release_id']],'5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b')) stop('API deployment is bound to wrong forecast release.',call.=FALSE)
  if (!identical(cfg[['season']],'2026-27')) stop('API deployment season policy mismatch.',call.=FALSE)
  if (validate_environment) {
    env_path <- file.path(repo_root,'governance/v3_weekly_api_environment_v1.tsv')
    if (!exists('.api_validate_environment_manifest',mode='function')) stop('API core environment validator not loaded.',call.=FALSE)
    .api_validate_environment_manifest(env_path)
  }
  list(deployment_id=id,deployment_dir=deployment_dir,manifest=m,config=cfg)
}

.api_bootstrap_validate_with_sha256sum <- function(deployment_dir,repo_root=getwd()) {
  # Minimal trust-root validation used before sourcing API helpers. The deployment
  # manifest itself is immutable under a content-addressed directory; sha256sum
  # is used here so no R package helper must be sourced first.
  deployment_dir <- normalizePath(deployment_dir,winslash='/',mustWork=TRUE)
  repo_root <- normalizePath(repo_root,winslash='/',mustWork=TRUE)
  mp <- file.path(deployment_dir,'deployment_manifest.tsv')
  if (!file.exists(mp)) stop('Missing API deployment manifest.',call.=FALSE)
  m <- utils::read.delim(mp,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  needed <- c('scripts/v3_weekly_api_deployment_helpers_v3.R','scripts/v3_weekly_api_helpers_v3.R','scripts/v3_shadow_release_helpers_v1.R','scripts/v3_shadow_ops_helpers_v1.R','2026/run_weekly_shadow_release_v5.R')
  for (rel in needed) {
    row <- m[m$path==rel,,drop=FALSE]; if (nrow(row)!=1L) stop('API deployment does not bind bootstrap source: ',rel,call.=FALSE)
    p <- file.path(repo_root,rel)
    out <- system2('sha256sum',p,stdout=TRUE,stderr=TRUE)
    got <- strsplit(out[[1]],' +')[[1]][[1]]
    if (!identical(got,row$sha256[[1]])) stop('Bootstrap source hash drift: ',rel,call.=FALSE)
  }
  invisible(TRUE)
}
