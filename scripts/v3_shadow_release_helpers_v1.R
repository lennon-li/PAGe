# Content-addressed release helpers for PAGe v3 shadow governance.
# Release identity is the SHA-256 of the canonical manifest payload itself.

.v3_release_sha256 <- function(path) {
  if (!requireNamespace('digest',quietly=TRUE)) stop('Package `digest` is required.',call.=FALSE)
  if (!file.exists(path)) stop('Release-bound file missing: ',path,call.=FALSE)
  digest::digest(file=path,algo='sha256',serialize=FALSE)
}

.v3_release_byte_key <- function(x) {
  vapply(enc2utf8(as.character(x)),function(s) paste(sprintf('%02x',as.integer(charToRaw(s))),collapse=''),character(1))
}

.v3_release_order <- function(role,path) {
  order(.v3_release_byte_key(role),.v3_release_byte_key(path),method='radix')
}

.v3_release_repo_rel <- function(path) {
  p <- gsub('\\\\','/',as.character(path))
  if (grepl('^/',p) || grepl('^[A-Za-z]:/',p) || grepl('(^|/)[.][.](/|$)',p)) stop('Release path must be repo-relative without `..`: ',p,call.=FALSE)
  if (startsWith(p,'./')) substring(p,3L) else p
}

.v3_release_manifest_frame <- function(role,path) {
  if (length(role)!=length(path) || !length(role)) stop('Release manifest role/path vectors are invalid.',call.=FALSE)
  path <- vapply(path,.v3_release_repo_rel,character(1))
  if (any(!nzchar(role)) || any(!nzchar(path))) stop('Release manifest roles/paths must be non-empty.',call.=FALSE)
  key <- paste(role,path,sep='\t')
  if (anyDuplicated(key)) stop('Duplicate release manifest role/path entry.',call.=FALSE)
  for (p in path) {
    if (!file.exists(p)) stop('Release input missing: ',p,call.=FALSE)
    link <- Sys.readlink(p)
    if (nzchar(link)) stop('Symlink is not allowed as a release-bound input: ',p,call.=FALSE)
  }
  out <- data.frame(
    role=as.character(role),
    path=path,
    sha256=vapply(path,.v3_release_sha256,character(1)),
    size_bytes=as.numeric(file.info(path)$size),
    stringsAsFactors=FALSE
  )
  out[.v3_release_order(out$role,out$path),,drop=FALSE]
}

.v3_release_canonical_payload <- function(manifest) {
  required <- c('role','path','sha256','size_bytes')
  if (!is.data.frame(manifest) || !all(required %in% names(manifest)) || !nrow(manifest)) stop('Release manifest schema mismatch.',call.=FALSE)
  manifest <- manifest[,required,drop=FALSE]
  manifest$role <- as.character(manifest$role)
  manifest$path <- vapply(manifest$path,.v3_release_repo_rel,character(1))
  manifest$sha256 <- as.character(manifest$sha256)
  if (is.character(manifest$size_bytes)) {
    size_text <- manifest$size_bytes
    if (any(!grepl('^(0|[1-9][0-9]*)$',size_text))) stop('Release manifest size_bytes must be canonical non-negative decimal integers.',call.=FALSE)
  } else {
    size_num <- as.numeric(manifest$size_bytes)
    if (any(!is.finite(size_num)) || any(size_num<0) || any(abs(size_num-round(size_num))>0)) stop('Release manifest size_bytes must be non-negative integers.',call.=FALSE)
    size_text <- sprintf('%.0f',size_num)
  }
  if (anyDuplicated(paste(manifest$role,manifest$path,sep='\t'))) stop('Duplicate release manifest role/path entry.',call.=FALSE)
  if (any(!grepl('^[0-9a-f]{64}$',manifest$sha256))) stop('Release manifest hash field invalid.',call.=FALSE)
  manifest$size_text <- size_text
  manifest <- manifest[.v3_release_order(manifest$role,manifest$path),,drop=FALSE]
  rows <- paste(manifest$role,manifest$path,manifest$sha256,manifest$size_text,sep='\t')
  paste0(paste(rows,collapse='\n'),'\n')
}

.v3_release_id_from_manifest <- function(manifest) {
  if (!requireNamespace('digest',quietly=TRUE)) stop('Package `digest` is required.',call.=FALSE)
  digest::digest(.v3_release_canonical_payload(manifest),algo='sha256',serialize=FALSE)
}

.v3_release_write_manifest <- function(manifest,path) {
  payload <- .v3_release_canonical_payload(manifest)
  writeChar(payload,path,eos=NULL,useBytes=TRUE)
  invisible(path)
}

.v3_release_read_manifest <- function(path) {
  if (!file.exists(path)) stop('Release manifest is missing: ',path,call.=FALSE)
  x <- utils::read.delim(path,header=FALSE,sep='\t',quote='',comment.char='',stringsAsFactors=FALSE,
                         col.names=c('role','path','sha256','size_bytes'),check.names=FALSE,
                         colClasses=rep('character',4L))
  canonical <- .v3_release_canonical_payload(x)
  on_disk <- paste0(readLines(path,warn=FALSE),collapse='\n')
  on_disk <- paste0(on_disk,'\n')
  if (!identical(on_disk,canonical)) stop('Release manifest is not in canonical serialization/order.',call.=FALSE)
  x$size_bytes <- as.numeric(x$size_bytes)
  x[.v3_release_order(x$role,x$path),,drop=FALSE]
}

.v3_release_validate_environment <- function(path) {
  if (!file.exists(path)) stop('Runtime environment specification missing: ',path,call.=FALSE)
  x <- utils::read.delim(path,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  if (!identical(names(x),c('component','version')) || anyDuplicated(x$component)) stop('Runtime environment specification is malformed.',call.=FALSE)
  expected_r <- x$version[x$component=='R']
  if (length(expected_r)!=1L || !identical(as.character(getRversion()),expected_r)) stop('Runtime R version differs from release specification.',call.=FALSE)
  for (pkg in setdiff(x$component,'R')) {
    if (!requireNamespace(pkg,quietly=TRUE)) stop('Required runtime package is unavailable: ',pkg,call.=FALSE)
    actual <- as.character(utils::packageVersion(pkg))
    expected <- x$version[x$component==pkg]
    if (length(expected)!=1L || !identical(actual,expected)) stop('Runtime package version mismatch for ',pkg,': expected ',expected,', got ',actual,call.=FALSE)
  }
  invisible(TRUE)
}

.v3_release_validate <- function(release_dir,expected_id=NULL,verify_files=TRUE) {
  release_dir <- normalizePath(release_dir,winslash='/',mustWork=TRUE)
  manifest_path <- file.path(release_dir,'release_manifest.tsv')
  id_path <- file.path(release_dir,'release_id.txt')
  if (!file.exists(manifest_path) || !file.exists(id_path)) stop('Release directory lacks release_manifest.tsv/release_id.txt.',call.=FALSE)
  manifest <- .v3_release_read_manifest(manifest_path)
  release_id <- .v3_release_id_from_manifest(manifest)
  recorded <- trimws(readLines(id_path,warn=FALSE,n=1L))
  if (!identical(recorded,release_id)) stop('Release ID does not match canonical manifest payload.',call.=FALSE)
  if (!is.null(expected_id) && !identical(as.character(expected_id),release_id)) stop('Release ID differs from expected ID.',call.=FALSE)

  if (isTRUE(verify_files)) {
    for (i in seq_len(nrow(manifest))) {
      p <- manifest$path[[i]]
      if (!file.exists(p)) stop('Release dependency missing: ',p,call.=FALSE)
      if (nzchar(Sys.readlink(p))) stop('Release dependency became a symlink: ',p,call.=FALSE)
      if (!identical(.v3_release_sha256(p),manifest$sha256[[i]])) stop('Release dependency hash mismatch: ',p,call.=FALSE)
      if (!identical(as.numeric(file.info(p)$size),as.numeric(manifest$size_bytes[[i]]))) stop('Release dependency size mismatch: ',p,call.=FALSE)
    }
  }

  env_paths <- as.character(manifest$path[manifest$role=='runtime_environment'])
  if (length(env_paths)!=1L) stop('Release must bind exactly one runtime_environment specification.',call.=FALSE)
  .v3_release_validate_environment(env_paths[[1]])

  bound_pkg <- sort(as.character(manifest$path[manifest$role=='runtime_package_source']))
  current_pkg <- sort(gsub('\\\\','/',list.files('PAGe/R',pattern='[.]R$',full.names=TRUE)))
  if (!identical(bound_pkg,current_pkg)) {
    stop('Release runtime package-source set differs from current PAGe/R/*.R closure.',call.=FALSE)
  }
  list(release_id=release_id,release_dir=release_dir,manifest=manifest)
}
