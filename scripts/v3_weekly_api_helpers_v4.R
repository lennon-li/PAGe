# PAGe v3 weekly deployment API v4 -- transport-independent core.
# This file contains no forecasting/model code. It wraps and validates the
# authoritative weekly shadow transaction.

.PAGE_API_CONTRACT <- 'page-weekly-api-v4'
.PAGE_FORECAST_RELEASE_ID <- '5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b'
.PAGE_RUN_ID_RE <- '^wr_[0-9a-f]{32}$'
.PAGE_IDEM_RE <- '^[A-Za-z0-9._:-]{1,128}$'
.PAGE_SHA_RE <- '^[0-9a-f]{64}$'
.PAGE_ROUTE_ALLOWLIST <- c('exact_A1_state','exact_B1_state','posterior_C2','exact_B1_fallback')
.PAGE_SAFE_FAILURES <- c(
  api_not_ready='Service is not ready.',
  release_validation_failed='Governed release validation failed.',
  invalid_request='Request validation failed.',
  release_mismatch='Expected release does not match deployment release.',
  idempotency_conflict='Idempotency key was reused for a different request.',
  idempotency_blocked='Idempotency key is blocked pending operator review.',
  season_busy='An API-managed run is already active for this season.',
  worker_spawn_failed='Worker could not be started.',
  worker_timeout='Worker exceeded the configured runtime limit.',
  forecast_transaction_failed='Authoritative forecast transaction failed.',
  transaction_binding_failed='Worker output could not be bound to this API run.',
  transaction_validation_failed='Authoritative transaction validation failed.',
  worker_lost='Worker terminated before a valid transaction was published.',
  admission_interrupted='Admission was interrupted before worker handoff.',
  internal_error='Internal service error.'
)

`%||%` <- function(x,y) if (is.null(x) || !length(x)) y else x

.api_require_packages <- function(pkgs=c('jsonlite','digest','processx')) {
  bad <- pkgs[!vapply(pkgs,requireNamespace,quietly=TRUE,FUN.VALUE=logical(1))]
  if (length(bad)) stop('Missing required API package(s): ',paste(bad,collapse=', '),call.=FALSE)
  invisible(TRUE)
}

.api_sha256_text <- function(x) {
  .api_require_packages('digest')
  digest::digest(enc2utf8(paste0(x,collapse='')),algo='sha256',serialize=FALSE)
}

.api_sha256_file <- function(path) {
  .api_require_packages('digest')
  if (!file.exists(path)) stop('Missing file for SHA-256: ',path,call.=FALSE)
  digest::digest(file=path,algo='sha256',serialize=FALSE)
}

.api_now <- function() format(Sys.time(),'%Y-%m-%dT%H:%M:%SZ',tz='UTC')

.api_is_utc_timestamp <- function(x) {
  if (!is.character(x) || length(x)!=1L || is.na(x)) return(FALSE)
  formats <- c('%Y-%m-%dT%H:%M:%SZ','%Y%m%dT%H%M%SZ')
  for (fmt in formats) {
    z <- suppressWarnings(as.POSIXct(x,format=fmt,tz='UTC'))
    if (!is.na(z) && identical(format(z,fmt,tz='UTC'),x)) return(TRUE)
  }
  FALSE
}

.api_safe_code <- function(code) {
  code <- as.character(code %||% 'internal_error')[[1]]
  if (!code %in% names(.PAGE_SAFE_FAILURES)) code <- 'internal_error'
  code
}

.api_safe_failure <- function(code) {
  code <- .api_safe_code(code)
  list(code=code,message=unname(.PAGE_SAFE_FAILURES[[code]]))
}

.api_atomic_write_text <- function(text,path,immutable=FALSE) {
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE,mode='0700')
  text <- enc2utf8(paste0(text,collapse=''))
  if (immutable && file.exists(path)) {
    got <- paste(readLines(path,warn=FALSE,encoding='UTF-8'),collapse='\n')
    want <- sub('\n$','',text)
    if (!identical(got,want)) stop('Immutable file already exists with different content: ',path,call.=FALSE)
    return(invisible(path))
  }
  tmp <- tempfile(pattern=paste0('.',basename(path),'.'),tmpdir=dirname(path))
  con <- file(tmp,open='wb'); on.exit(try(close(con),silent=TRUE),add=TRUE)
  writeBin(charToRaw(text),con); close(con)
  Sys.chmod(tmp,mode='0600')
  if (!file.rename(tmp,path)) { unlink(tmp); stop('Atomic rename failed for ',path,call.=FALSE) }
  invisible(path)
}

.api_canonical_json <- function(x) {
  .api_require_packages('jsonlite')
  paste0(jsonlite::toJSON(x,auto_unbox=TRUE,null='null',digits=NA,pretty=FALSE,force=TRUE),'\n')
}

.api_atomic_write_json <- function(x,path,immutable=FALSE) .api_atomic_write_text(.api_canonical_json(x),path,immutable=immutable)

.api_read_json <- function(path) {
  .api_require_packages('jsonlite')
  if (!file.exists(path)) stop('Missing JSON file: ',path,call.=FALSE)
  jsonlite::fromJSON(path,simplifyVector=FALSE)
}

.api_parse_json_object_strict <- function(raw_text,allowed_keys) {
  .api_require_packages('jsonlite')
  if (length(raw_text)!=1L || !is.character(raw_text) || !nzchar(raw_text)) stop('Body must be a JSON object.',call.=FALSE)
  obj <- tryCatch(jsonlite::parse_json(raw_text,simplifyVector=FALSE),error=function(e) stop('Malformed JSON.',call.=FALSE))
  if (!is.list(obj) || is.null(names(obj))) stop('Body must be a JSON object.',call.=FALSE)
  nm <- names(obj)
  if (any(!nzchar(nm)) || anyDuplicated(nm)) stop('Duplicate or empty JSON keys are forbidden.',call.=FALSE)
  extra <- setdiff(nm,allowed_keys); missing <- setdiff(allowed_keys,nm)
  if (length(extra) || length(missing)) stop('Request keys do not match the v1 schema.',call.=FALSE)
  obj
}

.api_scalar_string <- function(x,name,max_nchar=256L) {
  if (!is.character(x) || length(x)!=1L || is.na(x) || !nzchar(x) || nchar(x,type='bytes')>max_nchar) stop(name,' must be a scalar string.',call.=FALSE)
  x
}

.api_validate_trigger_request <- function(body,config) {
  if (is.character(body)) body <- .api_parse_json_object_strict(body,c('season','expected_release_id'))
  if (!is.list(body) || !identical(sort(names(body)),sort(c('season','expected_release_id')))) stop('Invalid trigger request.',call.=FALSE)
  season <- .api_scalar_string(body$season,'season',7L)
  rel <- .api_scalar_string(body$expected_release_id,'expected_release_id',64L)
  if (!grepl('^[0-9]{4}-[0-9]{2}$',season)) stop('Invalid season format.',call.=FALSE)
  if (!identical(season,config$season)) stop('Requested season is not the configured deployment season.',call.=FALSE)
  if (!grepl(.PAGE_SHA_RE,rel) || !identical(rel,config$forecast_release_id)) stop('Release assertion does not match deployment release.',call.=FALSE)
  list(season=season,expected_release_id=rel)
}

.api_validate_idempotency_key <- function(key) {
  key <- .api_scalar_string(key,'Idempotency-Key',128L)
  if (!grepl(.PAGE_IDEM_RE,key)) stop('Invalid Idempotency-Key.',call.=FALSE)
  key
}

.api_request_digest <- function(req,source_mode) {
  payload <- paste0(
    'api_contract_version\t',.PAGE_API_CONTRACT,'\n',
    'season\t',req$season,'\n',
    'expected_release_id\t',req$expected_release_id,'\n',
    'source_mode\t',source_mode,'\n'
  )
  .api_sha256_text(payload)
}

.api_random_hex <- function(n_bytes=16L) {
  con <- file('/dev/urandom','rb',raw=TRUE); on.exit(close(con),add=TRUE)
  raw <- readBin(con,'raw',n=n_bytes)
  if (length(raw)!=n_bytes) stop('Could not obtain cryptographic random bytes.',call.=FALSE)
  paste(sprintf('%02x',as.integer(raw)),collapse='')
}

.api_new_run_id <- function() paste0('wr_',.api_random_hex(16L))

.api_validate_run_id <- function(run_id) {
  run_id <- .api_scalar_string(run_id,'run_id',35L)
  if (!grepl(.PAGE_RUN_ID_RE,run_id)) stop('Invalid run_id.',call.=FALSE)
  run_id
}

.api_path_under <- function(path,root,must_exist=FALSE) {
  root_n <- normalizePath(root,winslash='/',mustWork=TRUE)
  path_n <- normalizePath(path,winslash='/',mustWork=must_exist)
  identical(path_n,root_n) || startsWith(path_n,paste0(root_n,'/'))
}

.api_assert_regular_nonsymlink <- function(path,label='file',require_absolute=FALSE) {
  if (isTRUE(require_absolute) && (!is.character(path) || length(path)!=1L || !grepl('^/',path))) stop(label,' must be an absolute path.',call.=FALSE)
  if (!file.exists(path) || dir.exists(path) || nzchar(Sys.readlink(path))) stop(label,' must be a regular non-symlink file.',call.=FALSE)
  invisible(TRUE)
}

.api_proc_start_token <- function(pid=Sys.getpid()) {
  p <- paste0('/proc/',as.integer(pid),'/stat')
  if (!file.exists(p)) return(NA_character_)
  z <- strsplit(readLines(p,warn=FALSE,n=1L),' +')[[1]]
  if (length(z)<22L) return(NA_character_)
  z[[22L]]
}

.api_pid_owner_state <- function(pid,start_token) {
  pid_txt <- as.character(pid %||% '')
  tok <- as.character(start_token %||% '')
  if (length(pid_txt)!=1L || !grepl('^[1-9][0-9]*$',pid_txt) || length(tok)!=1L || !grepl('^[0-9]+$',tok)) return('unverifiable')
  pid_i <- suppressWarnings(as.integer(pid_txt)); if (is.na(pid_i) || pid_i < 1L) return('unverifiable')
  proc_dir <- paste0('/proc/',pid_i)
  if (!dir.exists(proc_dir)) return('dead')
  actual <- .api_proc_start_token(pid_i)
  if (is.na(actual) || !nzchar(actual) || !grepl('^[0-9]+$',actual)) return('unverifiable')
  if (identical(actual,tok)) 'match' else 'reused'
}
.api_pid_alive_with_token <- function(pid,start_token) identical(.api_pid_owner_state(pid,start_token),'match')

.api_mount_unescape <- function(x) {
  x <- gsub('\\040',' ',x,fixed=TRUE)
  x <- gsub('\\011','\t',x,fixed=TRUE)
  x <- gsub('\\012','\n',x,fixed=TRUE)
  gsub('\\134','\\',x,fixed=TRUE)
}

.api_mount_records <- function() {
  f <- '/proc/self/mountinfo'
  if (!file.exists(f)) return(data.frame(mountpoint=character(),fstype=character(),source=character(),stringsAsFactors=FALSE))
  rows <- lapply(readLines(f,warn=FALSE),function(line) {
    parts <- strsplit(line,' - ',fixed=TRUE)[[1]]
    if (length(parts)!=2L) return(NULL)
    pre <- strsplit(parts[[1]],' ',fixed=TRUE)[[1]]
    post <- strsplit(parts[[2]],' ',fixed=TRUE)[[1]]
    if (length(pre)<5L || length(post)<2L) return(NULL)
    data.frame(mountpoint=.api_mount_unescape(pre[[5L]]),fstype=.api_mount_unescape(post[[1L]]),source=.api_mount_unescape(post[[2L]]),stringsAsFactors=FALSE)
  })
  rows <- Filter(Negate(is.null),rows)
  if (!length(rows)) return(data.frame(mountpoint=character(),fstype=character(),source=character(),stringsAsFactors=FALSE))
  do.call(rbind,rows)
}

.api_mount_record <- function(path) {
  p <- normalizePath(path,winslash='/',mustWork=TRUE)
  r <- .api_mount_records()
  hit <- r[r$mountpoint==p,,drop=FALSE]
  if (nrow(hit)!=1L) return(NULL)
  hit[1,,drop=FALSE]
}

.api_mountpoints <- function() .api_mount_records()$mountpoint

.api_fs_device <- function(path) {
  out <- tryCatch(system2('stat',c('-c','%d',normalizePath(path,mustWork=TRUE)),stdout=TRUE,stderr=FALSE),error=function(e) character())
  if (length(out)!=1L || !grepl('^[0-9]+$',out)) return(NA_character_)
  out[[1]]
}

.api_validate_storage <- function(config,strict_mount=TRUE) {
  for (x in c('artifact_mount','job_root','output_root')) {
    p <- config[[x]]; if (is.null(p) || !nzchar(p)) stop('Missing storage config: ',x,call.=FALSE)
    if (!grepl('^/',p)) stop(x,' must be absolute.',call.=FALSE)
    if (nzchar(Sys.readlink(p))) stop(x,' may not be a symlink.',call.=FALSE)
  }
  if (!dir.exists(config$artifact_mount)) stop('Artifact mount does not exist.',call.=FALSE)
  if (strict_mount) {
    rec <- .api_mount_record(config$artifact_mount)
    if (is.null(rec)) stop('Configured artifact root is not an active mountpoint.',call.=FALSE)
    if (is.null(config$artifact_fs_type) || !nzchar(config$artifact_fs_type) || !identical(rec$fstype[[1]],config$artifact_fs_type)) stop('Artifact mount filesystem type does not match governed deployment identity.',call.=FALSE)
    if (is.null(config$artifact_mount_source) || !nzchar(config$artifact_mount_source) || !identical(rec$source[[1]],config$artifact_mount_source)) stop('Artifact mount source does not match governed deployment identity.',call.=FALSE)
  }
  current_user <- unname(Sys.info()[['user']])
  for (p in c(config$job_root,config$output_root)) {
    if (!dir.exists(p)) dir.create(p,recursive=TRUE,mode='0700',showWarnings=FALSE)
    if (!.api_path_under(p,config$artifact_mount,TRUE)) stop('Job/output root must be under artifact mount.',call.=FALSE)
    if (file.access(p,2)!=0L) stop('Job/output root is not writable.',call.=FALSE)
    if (strict_mount) {
      fi <- file.info(p)
      if (!identical(fi$uname[[1]],current_user)) stop('Job/output root must be owned by the running service account.',call.=FALSE)
      if (bitwAnd(as.integer(fi$mode[[1]]),strtoi('077',base=8L))!=0L) stop('Job/output root must not grant group/other permissions.',call.=FALSE)
    }
  }
  d <- unique(c(.api_fs_device(config$artifact_mount),.api_fs_device(config$job_root),.api_fs_device(config$output_root)))
  d <- d[!is.na(d)]; if (length(d)>1L) stop('Artifact/job/output roots are not on one filesystem.',call.=FALSE)
  invisible(TRUE)
}

.api_validate_storage_atomic_semantics <- function(config) {
  .api_validate_storage(config,strict_mount=FALSE)
  root <- config$job_root; probe <- file.path(root,paste0('.api-storage-probe-',.api_random_hex(6L)))
  if (!dir.create(probe,mode='0700',showWarnings=FALSE)) stop('Could not create storage probe directory.',call.=FALSE)
  on.exit(unlink(probe,recursive=TRUE,force=TRUE),add=TRUE)
  a <- file.path(probe,'a.tmp'); b <- file.path(probe,'b.json'); .api_atomic_write_text('{\"probe\":true}\n',a)
  if (!file.rename(a,b) || !file.exists(b) || file.exists(a)) stop('Storage does not satisfy atomic file rename semantics.',call.=FALSE)
  lock <- file.path(probe,'lock.dir'); if(!dir.create(lock,mode='0700',showWarnings=FALSE))stop('Storage lock-directory creation failed.',call.=FALSE)
  q <- file.path(probe,'lock.quarantine'); if(!file.rename(lock,q)||!dir.exists(q)||dir.exists(lock))stop('Storage directory rename/quarantine semantics failed.',call.=FALSE)
  invisible(TRUE)
}

.api_read_token_file <- function(path) {
  .api_assert_regular_nonsymlink(path,'Token file')
  fi <- file.info(path)
  mode <- as.integer(fi$mode[[1]])
  if (bitwAnd(mode,strtoi('077',base=8L))!=0L) stop('Token file has group/other permissions.',call.=FALSE)
  current_user <- unname(Sys.info()[['user']])
  if (!fi$uname[[1]] %in% c('root',current_user)) stop('Token file must be owned by root or the running service account.',call.=FALSE)
  con <- file(path,'rb'); on.exit(close(con),add=TRUE); raw <- readBin(con,'raw',n=4096L)
  txt <- rawToChar(raw)
  txt <- sub('\r?\n$','',txt,perl=TRUE)
  if (grepl('[[:space:][:cntrl:]]',txt,perl=TRUE) || !grepl('^[0-9a-fA-F]{64}$',txt)) stop('Token file must contain exactly one 64-hex token plus optional terminal newline.',call.=FALSE)
  tolower(txt)
}

.api_constant_time_equal <- function(a,b) {
  if (!is.character(a)||!is.character(b)||length(a)!=1L||length(b)!=1L) return(FALSE)
  ra <- charToRaw(a); rb <- charToRaw(b)
  if (length(ra)!=length(rb)) return(FALSE)
  acc <- 0L; for (i in seq_along(ra)) acc <- bitwOr(acc,bitwXor(as.integer(ra[[i]]),as.integer(rb[[i]])))
  identical(acc,0L)
}

.api_validate_bearer <- function(header,token) {
  if (is.null(header)||length(header)!=1L||!grepl('^Bearer [0-9A-Fa-f]{64}$',header)) return(FALSE)
  .api_constant_time_equal(tolower(sub('^Bearer ','',header)),tolower(token))
}

.api_job_dir <- function(config,run_id) file.path(config$job_root,'jobs',.api_validate_run_id(run_id))
.api_state_path <- function(config,run_id) file.path(.api_job_dir(config,run_id),'state.json')
.api_request_path <- function(config,run_id) file.path(.api_job_dir(config,run_id),'request.json')
.api_worker_result_path <- function(config,run_id) file.path(.api_job_dir(config,run_id),'worker_result.json')

.api_init_store <- function(config) {
  for (p in c(file.path(config$job_root,'jobs'),file.path(config$job_root,'jobs','quarantine'),file.path(config$job_root,'idempotency'),file.path(config$job_root,'idempotency','quarantine'),file.path(config$job_root,'locks'),file.path(config$job_root,'locks','quarantine'))) dir.create(p,recursive=TRUE,mode='0700',showWarnings=FALSE)
  invisible(TRUE)
}

.api_read_state <- function(config,run_id) .api_read_json(.api_state_path(config,run_id))
.api_write_state <- function(config,run_id,state) .api_atomic_write_json(state,.api_state_path(config,run_id),immutable=FALSE)

.api_public_state <- function(state) {
  s <- as.character(state$state %||% 'failed')
  if (s %in% c('accepted_pending','starting')) 'accepted' else if (s %in% c('running','succeeded','failed')) s else 'failed'
}

.api_job_projection <- function(config,run_id) {
  st <- .api_read_state(config,run_id); req <- .api_read_json(.api_request_path(config,run_id))
  out <- list(run_id=run_id,season=req$season,release_id=req$expected_release_id,created_utc=req$created_utc,status=.api_public_state(st))
  for (k in c('started_utc','finished_utc','origin_weekF','effective_panel_sha256','transaction_id','worker_exit_code','failure_code','failure_message')) if (!is.null(st[[k]])) out[[k]] <- st[[k]]
  out
}

.api_idem_hash <- function(key) .api_sha256_text(paste0('page-weekly-api-idempotency-v1\n',.api_validate_idempotency_key(key)))
.api_idem_path <- function(config,key_hash) file.path(config$job_root,'idempotency',paste0(key_hash,'.json'))
.api_idem_block_path <- function(config,key_hash) file.path(config$job_root,'idempotency','quarantine',paste0(key_hash,'.blocked.json'))
.api_blocked_idempotency <- function(config,key_hash) file.exists(.api_idem_block_path(config,key_hash))
.api_quarantine_idempotency <- function(config,path,label='corrupt') {
  qd <- file.path(config$job_root,'idempotency','quarantine'); dir.create(qd,recursive=TRUE,mode='0700',showWarnings=FALSE)
  key_hash <- sub('[.]json$','',basename(path))
  if (!.api_is_sha(key_hash)) stop('Cannot quarantine idempotency reservation with invalid key hash filename.',call.=FALSE)
  block <- .api_idem_block_path(config,key_hash)
  if (!file.exists(block)) .api_atomic_write_json(list(key_hash=key_hash,status='blocked',reason=label,blocked_utc=.api_now()),block,immutable=TRUE)
  q <- file.path(qd,paste0(basename(path),'-',label,'-',format(Sys.time(),'%Y%m%dT%H%M%SZ',tz='UTC'),'-',.api_random_hex(4L)))
  if (file.exists(path) && !file.rename(path,q)) stop('Could not quarantine idempotency reservation.',call.=FALSE)
  q
}
.api_read_idempotency_strict <- function(config,path) {
  x <- tryCatch(.api_read_json(path),error=identity)
  expected_key_hash <- sub('[.]json$','',basename(path))
  valid <- !inherits(x,'error') && !is.null(x$key_hash) && !is.null(x$request_digest) && !is.null(x$run_id) &&
    .api_is_sha(as.character(x$key_hash)) && identical(as.character(x$key_hash),expected_key_hash) &&
    .api_is_sha(as.character(x$request_digest)) && grepl(.PAGE_RUN_ID_RE,as.character(x$run_id))
  if (!valid) {
    .api_quarantine_idempotency(config,path,'invalid')
    stop('Idempotency reservation is corrupt and was quarantined/blocked.',call.=FALSE)
  }
  x
}

.api_validate_immutable_request_lineage <- function(config,run_id) {
  req <- .api_read_json(.api_request_path(config,run_id))
  required <- c('run_id','api_contract_version','season','expected_release_id','source_mode','key_hash','request_digest','created_utc','service_instance_id')
  if (!is.list(req) || !setequal(names(req),required) || length(req)!=length(required)) stop('Immutable request schema is incomplete or unexpected.',call.=FALSE)
  if (!identical(as.character(req$run_id),run_id) || !identical(as.character(req$api_contract_version),.PAGE_API_CONTRACT)) stop('Immutable request identity mismatch.',call.=FALSE)
  if (!identical(as.character(req$season),config$season) || !identical(as.character(req$expected_release_id),config$forecast_release_id) || !identical(as.character(req$source_mode),config$source_mode)) stop('Immutable request deployment binding mismatch.',call.=FALSE)
  if (!.api_is_sha(as.character(req$key_hash)) || !.api_is_sha(as.character(req$request_digest)) || !.api_is_utc_timestamp(as.character(req$created_utc)) || !nzchar(as.character(req$service_instance_id))) stop('Immutable request lineage field invalid.',call.=FALSE)
  recomputed <- .api_request_digest(list(season=as.character(req$season),expected_release_id=as.character(req$expected_release_id)),as.character(req$source_mode))
  if (!identical(recomputed,as.character(req$request_digest))) stop('Immutable request digest does not recompute.',call.=FALSE)
  req
}
.api_ensure_idempotency_from_request <- function(config,run_id) {
  req <- .api_validate_immutable_request_lineage(config,run_id)
  kh <- as.character(req$key_hash); rd <- as.character(req$request_digest)
  if (.api_blocked_idempotency(config,kh)) stop('Idempotency key is blocked pending operator review.',call.=FALSE)
  ip <- .api_idem_path(config,kh)
  if (!file.exists(ip)) {
    .api_atomic_write_json(list(key_hash=kh,request_digest=rd,run_id=run_id),ip,immutable=TRUE)
    return(invisible(TRUE))
  }
  old <- .api_read_idempotency_strict(config,ip)
  if (!identical(as.character(old$request_digest),rd) || !identical(as.character(old$run_id),run_id)) {
    .api_quarantine_idempotency(config,ip,'mismatch')
    stop('Idempotency reservation conflicts with immutable request and was quarantined/blocked.',call.=FALSE)
  }
  invisible(TRUE)
}
.api_season_lock <- function(config) file.path(config$job_root,'locks',paste0('season-',config$season,'.lock'))
.api_admission_lock <- function(config) file.path(config$job_root,'locks','admission.lock')

.api_acquire_admission <- function(config,service_instance_id) {
  lock <- .api_admission_lock(config)
  owner <- list(service_instance_id=service_instance_id,pid=Sys.getpid(),start_token=.api_proc_start_token(),created_utc=.api_now())
  if (dir.create(lock,showWarnings=FALSE,mode='0700')) { .api_atomic_write_json(owner,file.path(lock,'owner.json')); return(TRUE) }
  op <- file.path(lock,'owner.json')
  if (!file.exists(op)) stop('Admission lock has no valid owner receipt; operator quarantine required.',call.=FALSE)
  old <- tryCatch(.api_read_json(op),error=function(e) NULL)
  if (is.null(old)||is.null(old$service_instance_id)||is.null(old$pid)||is.null(old$start_token)) stop('Admission lock owner is corrupt; operator quarantine required.',call.=FALSE)
  if (identical(as.character(old$service_instance_id),service_instance_id)) return(FALSE)
  owner_state <- .api_pid_owner_state(old$pid,old$start_token)
  if (identical(owner_state,'match')) stop('Admission lock belongs to a live prior process; refusing recovery.',call.=FALSE)
  if (identical(owner_state,'unverifiable')) stop('Admission lock ownership cannot be verified; operator quarantine required.',call.=FALSE)
  q <- file.path(config$job_root,'locks','quarantine',paste0('admission-',format(Sys.time(),'%Y%m%dT%H%M%SZ',tz='UTC'),'-',.api_random_hex(4L)))
  if (!file.rename(lock,q)) stop('Could not quarantine stale admission lock.',call.=FALSE)
  if (!dir.create(lock,showWarnings=FALSE,mode='0700')) stop('Could not acquire admission lock after stale-lock quarantine.',call.=FALSE)
  .api_atomic_write_json(owner,file.path(lock,'owner.json')); TRUE
}

.api_release_admission <- function(config,service_instance_id) {
  lock <- .api_admission_lock(config); if (!dir.exists(lock)) return(invisible(TRUE))
  owner <- tryCatch(.api_read_json(file.path(lock,'owner.json')),error=function(e) NULL)
  if (is.null(owner)||!identical(as.character(owner$service_instance_id),service_instance_id)) stop('Admission lock ownership mismatch.',call.=FALSE)
  unlink(lock,recursive=TRUE,force=TRUE); invisible(TRUE)
}

.api_nonterminal_runs <- function(config) {
  ids <- list.dirs(file.path(config$job_root,'jobs'),recursive=FALSE,full.names=FALSE)
  ids <- setdiff(ids,'quarantine')
  keep <- vapply(ids,function(id) {
    st <- .api_read_state(config,id)
    state <- as.character(st$state %||% '')
    if (!state %in% c('accepted_pending','starting','running','succeeded','failed')) stop('Unreadable or invalid durable job state blocks lock reconciliation: ',id,call.=FALSE)
    state %in% c('accepted_pending','starting','running')
  },logical(1))
  ids[keep]
}
.api_reconcile_season_lock_locked <- function(config) {
  p <- .api_season_lock(config); if (!dir.exists(p)) return(NULL)
  owner <- tryCatch(.api_read_json(file.path(p,'owner.json')),error=function(e)NULL)
  active <- .api_nonterminal_runs(config)
  if (!is.null(owner) && !is.null(owner$run_id) && grepl(.PAGE_RUN_ID_RE,as.character(owner$run_id))) {
    rid <- as.character(owner$run_id)
    if (rid %in% active) return(rid)
    if (length(active)) stop('Season lock owner is stale but another nonterminal API job exists; refusing recovery.',call.=FALSE)
  } else if (length(active)) stop('Season lock owner is invalid while nonterminal API work exists; refusing recovery.',call.=FALSE)
  q <- file.path(config$job_root,'locks','quarantine',paste0('season-',format(Sys.time(),'%Y%m%dT%H%M%SZ',tz='UTC'),'-',.api_random_hex(4L)))
  if (!file.rename(p,q)) stop('Could not quarantine stale season lock.',call.=FALSE)
  NULL
}

.api_create_season_lock <- function(config,run_id,service_instance_id) {
  p <- .api_season_lock(config)
  if (!dir.create(p,showWarnings=FALSE,mode='0700')) return(FALSE)
  .api_atomic_write_json(list(run_id=run_id,service_instance_id=service_instance_id,created_utc=.api_now()),file.path(p,'owner.json')); TRUE
}

.api_release_season_lock <- function(config,run_id=NULL) {
  p <- .api_season_lock(config); if (!dir.exists(p)) return(invisible(TRUE))
  if (!is.null(run_id)) {
    o <- tryCatch(.api_read_json(file.path(p,'owner.json')),error=function(e) NULL)
    if (!is.null(o$run_id) && !identical(as.character(o$run_id),run_id)) return(invisible(FALSE))
  }
  unlink(p,recursive=TRUE,force=TRUE); invisible(TRUE)
}

.api_external_worker_config <- function(config) list(
  repo_root=config$repo_root, api_deployment_dir=config$api_deployment_dir,
  job_root=config$job_root, season=config$season,
  forecast_release_dir=config$forecast_release_dir,
  forecast_release_id=config$forecast_release_id, output_root=config$output_root,
  source_mode=config$source_mode, olis_fallback=config$olis_fallback %||% NULL,
  rscript=config$rscript, max_runtime_seconds=config$max_runtime_seconds,
  transaction_schema=config$transaction_schema
)

.api_admit <- function(config,req,idempotency_key,service_instance_id,spawn_fun) {
  .api_init_store(config)
  if (!.api_acquire_admission(config,service_instance_id)) stop('Admission is busy.',call.=FALSE)
  on.exit(try(.api_release_admission(config,service_instance_id),silent=TRUE),add=TRUE)
  key_hash <- .api_idem_hash(idempotency_key); digest <- .api_request_digest(req,config$source_mode)
  ip <- .api_idem_path(config,key_hash)
  if (.api_blocked_idempotency(config,key_hash)) stop('Idempotency key is blocked pending operator review.',call.=FALSE)
  if (file.exists(ip)) {
    old <- .api_read_idempotency_strict(config,ip)
    if (!identical(as.character(old$request_digest),digest)) return(list(status='conflict',run_id=old$run_id))
    return(list(status='existing',run_id=old$run_id))
  }
  active_lock_run <- .api_reconcile_season_lock_locked(config)
  if (!is.null(active_lock_run)) return(list(status='busy',run_id=active_lock_run))
  run_id <- .api_new_run_id(); jd <- .api_job_dir(config,run_id)
  if (!dir.create(jd,recursive=FALSE,showWarnings=FALSE,mode='0700')) stop('Could not create job directory.',call.=FALSE)
  request <- list(run_id=run_id,api_contract_version=.PAGE_API_CONTRACT,season=req$season,expected_release_id=req$expected_release_id,source_mode=config$source_mode,key_hash=key_hash,request_digest=digest,created_utc=.api_now(),service_instance_id=service_instance_id)
  .api_atomic_write_json(request,.api_request_path(config,run_id),immutable=TRUE)
  .api_write_state(config,run_id,list(state='accepted_pending',updated_utc=.api_now(),service_instance_id=service_instance_id))
  if (!.api_create_season_lock(config,run_id,service_instance_id)) stop('Could not create season lock.',call.=FALSE)
  .api_atomic_write_json(list(key_hash=key_hash,request_digest=digest,run_id=run_id),ip,immutable=TRUE)
  .api_atomic_write_json(.api_external_worker_config(config),file.path(jd,'worker_config.json'),immutable=TRUE)
  .api_write_state(config,run_id,list(state='starting',updated_utc=.api_now(),service_instance_id=service_instance_id))
  spawned <- tryCatch(spawn_fun(run_id),error=identity)
  if (inherits(spawned,'error')) {
    fail <- .api_safe_failure('worker_spawn_failed')
    .api_write_state(config,run_id,list(state='failed',updated_utc=.api_now(),finished_utc=.api_now(),service_instance_id=service_instance_id,failure_code=fail$code,failure_message=fail$message))
    .api_release_season_lock(config,run_id)
    return(list(status='failed',run_id=run_id,error=spawned))
  }
  meta <- list(state='running',updated_utc=.api_now(),started_utc=.api_now(),service_instance_id=service_instance_id,pid=spawned$pid %||% NA_integer_,worker_start_token=spawned$start_token %||% NA_character_)
  .api_write_state(config,run_id,meta)
  list(status='accepted',run_id=run_id,process=spawned$process %||% NULL)
}

.api_read_tsv_kv_exact <- function(path,required_keys) {
  x <- utils::read.delim(path,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  if (!identical(names(x),c('key','value')) || anyDuplicated(x$key) || !setequal(x$key,required_keys) || nrow(x)!=length(required_keys)) stop('Parent transaction receipt schema mismatch.',call.=FALSE)
  setNames(as.character(x$value),as.character(x$key))
}

.api_safe_relative <- function(x) is.character(x)&&length(x)==1L&&nzchar(x)&&!grepl('^/',x)&&!grepl('(^|/)\\.\\.(/|$)',x)&&!grepl('[[:cntrl:]]',x)
.api_is_sha <- function(x) is.character(x)&&length(x)==1L&&grepl(.PAGE_SHA_RE,x)

.api_transaction_schema <- function(path) {
  x <- utils::read.csv(path,stringsAsFactors=FALSE,check.names=FALSE)
  if (!all(c('surface','name','type','required','disclose','rule') %in% names(x)) || anyDuplicated(paste(x$surface,x$name))) stop('Invalid API transaction schema.',call.=FALSE)
  x
}

.api_find_published_transaction <- function(config,run_id) {
  root <- file.path(config$output_root,'api-runs',.api_validate_run_id(run_id),config$season)
  if (!dir.exists(root)) stop('API run output season directory does not exist.',call.=FALSE)
  ds <- list.dirs(root,recursive=FALSE,full.names=TRUE)
  bn <- basename(ds); ds <- ds[bn!='.pending' & bn!='failures' & !grepl('-FAILED$',bn)]
  valid <- ds[file.exists(file.path(ds,'COMPLETED'))]
  if (length(valid)!=1L) stop('Expected exactly one published transaction for API run.',call.=FALSE)
  valid[[1]]
}


.api_monitoring_scalar <- function(x,label,allow_null=TRUE,probability=FALSE,integer=FALSE) {
  if (length(x)!=1L || is.na(x)) {
    if (allow_null) return(NULL)
    stop('Monitoring field missing: ',label,call.=FALSE)
  }
  z <- suppressWarnings(as.numeric(x))
  if (!is.finite(z)) stop('Monitoring field is non-finite: ',label,call.=FALSE)
  if (probability && (z < 0 || z > 1)) stop('Monitoring probability outside [0,1]: ',label,call.=FALSE)
  if (integer && abs(z-round(z)) > 1e-10) stop('Monitoring integer field is non-integral: ',label,call.=FALSE)
  if (integer) as.integer(round(z)) else as.numeric(z)
}

.api_monitoring_read_kv <- function(path,label) {
  .api_assert_regular_nonsymlink(path,label)
  x <- utils::read.delim(path,sep='\t',stringsAsFactors=FALSE,check.names=FALSE,colClasses='character')
  if (!identical(names(x),c('key','value')) || anyDuplicated(x$key) || any(!nzchar(x$key))) stop(label,' schema invalid.',call.=FALSE)
  setNames(as.character(x$value),as.character(x$key))
}

.api_monitoring_child_dir <- function(tx_dir,rel) {
  if (!.api_safe_relative(rel)) stop('Unsafe v3 child run reference.',call.=FALSE)
  if (grepl('(^|/)\\.\\.(/|$)',rel)) stop('Unsafe v3 child traversal.',call.=FALSE)
  cand <- file.path(tx_dir,rel)
  if (!dir.exists(cand) || nzchar(Sys.readlink(cand))) stop('V3 child run directory missing or symlinked.',call.=FALSE)
  tx_n <- normalizePath(tx_dir,winslash='/',mustWork=TRUE)
  ch_n <- normalizePath(cand,winslash='/',mustWork=TRUE)
  if (!startsWith(paste0(ch_n,'/'),paste0(tx_n,'/'))) stop('V3 child run escapes transaction root.',call.=FALSE)
  ch_n
}

.api_monitoring_projection <- function(tx_dir, receipt, cmp, config) {
  child <- .api_monitoring_child_dir(tx_dir, receipt[['v3_child_run']])
  files <- c(
    m0 = 'm0_a_detection.csv',
    signals = 'm0_a_signals.csv',
    m1 = 'm1_a_timing.csv',
    combined = 'combined_predictions.csv',
    provenance = 'provenance.tsv',
    status = 'status.tsv'
  )
  paths <- file.path(child, unname(files))
  names(paths) <- names(files)
  for (nm in setdiff(names(paths), 'm1')) {
    .api_assert_regular_nonsymlink(paths[[nm]], paste0('Monitoring ', nm, ' file'))
  }
  m1_link <- Sys.readlink(paths[['m1']])
  if (!is.na(m1_link) && nzchar(m1_link)) stop('Monitoring m1 file must be a regular non-symlink file.', call.=FALSE)
  if (file.exists(paths[['m1']])) .api_assert_regular_nonsymlink(paths[['m1']], 'Monitoring m1 file')

  child_provenance <- .api_monitoring_read_kv(paths[['provenance']], 'Child provenance')
  provenance_keys <- c('season', 'origin_weekF', 'effective_panel_sha256', 'release_id', 'production_eligible')
  if (!all(provenance_keys %in% names(child_provenance))) {
    stop('Child provenance missing required identity fields.', call. = FALSE)
  }
  origin <- suppressWarnings(as.integer(receipt[['origin_weekF']]))
  if (!identical(child_provenance[['season']], receipt[['season']]) ||
      !identical(child_provenance[['release_id']], receipt[['release_id']]) ||
      !identical(child_provenance[['effective_panel_sha256']], receipt[['effective_panel_sha256']]) ||
      !identical(suppressWarnings(as.integer(child_provenance[['origin_weekF']])), origin) ||
      !identical(child_provenance[['production_eligible']], 'FALSE')) {
    stop('Child provenance identity mismatch.', call. = FALSE)
  }
  child_status <- .api_monitoring_read_kv(paths[['status']], 'Child status')
  status_keys <- c('season', 'origin_weekF', 'in_validated_window', 'production_eligible')
  if (!all(status_keys %in% names(child_status)) ||
      !identical(child_status[['season']], receipt[['season']]) ||
      !identical(suppressWarnings(as.integer(child_status[['origin_weekF']])), origin) ||
      !identical(child_status[['in_validated_window']], 'TRUE') ||
      !identical(child_status[['production_eligible']], 'FALSE')) {
    stop('Child status identity mismatch.', call. = FALSE)
  }

  predictions <- utils::read.csv(paths[['combined']], stringsAsFactors = FALSE, check.names = FALSE)
  prediction_columns <- c(
    'season', 'origin_weekF', 'type', 'horizon', 'forecast', 'forecast_pct',
    'state_baseline', 'state_baseline_pct', 'route', 'timing_available',
    'timing_reason', 'activity_week', 'prob_peak_passed', 'posterior_mean_peak',
    'supported_mass', 'lower_bound_mass', 'lower_bound_saturated',
    'model_version', 'artifact_id', 'production_eligible'
  )
  if (!identical(names(predictions), prediction_columns) || nrow(predictions) != 4L) {
    stop('Child combined prediction schema/key-set mismatch.', call. = FALSE)
  }
  if (!is.logical(predictions$timing_available) || anyNA(predictions$timing_available) ||
      !is.logical(predictions$lower_bound_saturated) || anyNA(predictions$lower_bound_saturated) ||
      !is.logical(predictions$production_eligible) || anyNA(predictions$production_eligible) ||
      !is.character(predictions$timing_reason) || anyNA(predictions$timing_reason) ||
      !is.character(predictions$route) || anyNA(predictions$route) ||
      !is.character(predictions$model_version) || anyNA(predictions$model_version) ||
      !is.character(predictions$artifact_id) || anyNA(predictions$artifact_id)) {
    stop('Child combined prediction column type mismatch.', call. = FALSE)
  }
  row_key <- paste(predictions$type, predictions$horizon)
  expected_key <- c('A 1', 'A 2', 'B 1', 'B 2')
  if (anyDuplicated(row_key) || !setequal(row_key, expected_key) ||
      anyNA(predictions$season) || anyNA(predictions$origin_weekF) ||
      any(predictions$season != receipt[['season']]) || any(predictions$origin_weekF != origin) ||
      any(predictions$production_eligible != FALSE)) {
    stop('Child combined prediction identity mismatch.', call. = FALSE)
  }
  pred <- predictions[match(expected_key, row_key), , drop = FALSE]
  parent_order <- match(expected_key, paste(cmp$type, cmp$horizon))
  if (anyNA(parent_order)) stop('Child/parent mismatch.', call. = FALSE)
  parent_cmp <- cmp[parent_order, , drop = FALSE]
  if (any(abs(pred$forecast_pct - parent_cmp$v3_forecast_pct) > 1e-10) ||
      any(as.character(pred$route) != as.character(parent_cmp$v3_route))) {
    stop('Child/parent mismatch.', call. = FALSE)
  }

  detection <- utils::read.csv(paths[['m0']], stringsAsFactors = FALSE, check.names = FALSE)
  # The governed runner currently emits its two-element bracket as unquoted
  # c(lo, hi), which is not valid CSV. Accept only that exact legacy encoding
  # after requiring a one-row file; all other malformed rows remain rejected.
  if (ncol(detection) != 8L || nrow(detection) != 1L ||
      !identical(as.character(detection$season[[1L]]), receipt[['season']]) ||
      !is.logical(detection$detection_failed)) {
    raw_detection <- readLines(paths[['m0']], warn = FALSE, encoding = 'UTF-8')
    if (length(raw_detection) != 2L) stop('M0 detection file malformed.', call. = FALSE)
    bracket_match <- gregexpr(',c\\((?:-?[0-9]+|NA), (?:-?[0-9]+|NA)\\),', raw_detection[[2L]], perl = TRUE)
    bracket_hits <- regmatches(raw_detection[[2L]], bracket_match)[[1L]]
    if (length(bracket_hits) != 1L) stop('M0 detection file malformed.', call. = FALSE)
    normalized_row <- sub(',c\\(((?:-?[0-9]+|NA)), ((?:-?[0-9]+|NA))\\),', ',"c(\\1, \\2)",', raw_detection[[2L]], perl = TRUE)
    detection <- utils::read.csv(
      text = paste(raw_detection[[1L]], normalized_row, sep = '\n'),
      stringsAsFactors = FALSE, check.names = FALSE
    )
  }
  detection_columns <- c(
    'season', 'iWeek_hat', 'detection_failed', 'iWeek_hatF', 'iWeek_bracket',
    'iWeek_bracket_lo', 'iWeek_bracket_hi', 'iWeek_fraction_method'
  )
  if (!identical(names(detection), detection_columns) || nrow(detection) != 1L ||
      !identical(as.character(detection$season[[1L]]), receipt[['season']]) ||
      !is.logical(detection$detection_failed) || is.na(detection$detection_failed[[1L]])) {
    stop('M0 detection schema/identity mismatch.', call. = FALSE)
  }
  failed <- detection$detection_failed[[1L]]
  detector_values <- c('iWeek_hat', 'iWeek_hatF', 'iWeek_bracket_lo', 'iWeek_bracket_hi')
  detector_nums <- vapply(detection[detector_values], function(x) suppressWarnings(as.numeric(x[[1L]])), numeric(1))
  if (failed) {
    if (any(is.finite(detector_nums))) {
      stop('M0 failed detection contains finite ignition values.', call. = FALSE)
    }
  } else if (any(!is.finite(detector_nums)) ||
             any(abs(detector_nums[c('iWeek_hat', 'iWeek_bracket_lo', 'iWeek_bracket_hi')] -
                     round(detector_nums[c('iWeek_hat', 'iWeek_bracket_lo', 'iWeek_bracket_hi')])) > 1e-10) ||
             detector_nums[['iWeek_hatF']] < detector_nums[['iWeek_bracket_lo']] ||
             detector_nums[['iWeek_hatF']] > detector_nums[['iWeek_bracket_hi']] ||
             detector_nums[['iWeek_bracket_lo']] > detector_nums[['iWeek_bracket_hi']] ||
             !is.character(detection$iWeek_bracket[[1L]]) ||
             !is.character(detection$iWeek_fraction_method[[1L]]) ||
             !nzchar(detection$iWeek_fraction_method[[1L]])) {
    stop('M0 successful detection values invalid.', call. = FALSE)
  }
  ignited <- !failed && detector_nums[['iWeek_hatF']] <= origin

  signals <- utils::read.csv(paths[['signals']], stringsAsFactors = FALSE, check.names = FALSE)
  signal_columns <- c('season','weekF','y','N','p','cum_y','cum_N','prev','p0','p_sumK','raw_p_prev','raw_N_prev','raw_dp','raw_diff_se','raw_drop_z','raw_step_stable','cond_raw_nondec','cond_raw_stable','p_sm','dp','inc','cond_inc','cond_win','cond_cls','cond_sum','cond_p','cond_prev','n_hit','ignite_ok','iWeek_hat','detection_failed','ignite_flag','iWeek_hatF')
  if (!identical(names(signals), signal_columns) || !nrow(signals) || any(signals$season != receipt[['season']]) ||
      anyDuplicated(signals$weekF) || any(signals$weekF < 1L) || max(signals$weekF) != origin || !all(diff(signals$weekF) > 0)) {
    stop('M0 signals identity mismatch.', call. = FALSE)
  }
  last_signal <- signals[nrow(signals), , drop = FALSE]
  sig_failed <- isTRUE(last_signal$detection_failed[[1L]])
  sig_iweek <- suppressWarnings(as.numeric(last_signal$iWeek_hat[[1L]]))
  sig_iweekf <- suppressWarnings(as.numeric(last_signal$iWeek_hatF[[1L]]))
  if (!identical(sig_failed, failed) ||
      (!failed && (!is.finite(sig_iweek) || !is.finite(sig_iweekf) || abs(sig_iweek-detector_nums[['iWeek_hat']]) > 1e-10 || abs(sig_iweekf-detector_nums[['iWeek_hatF']]) > 1e-10)) ||
      (failed && (is.finite(sig_iweek) || is.finite(sig_iweekf))) ||
      !identical(isTRUE(last_signal$ignite_flag[[1L]]), ignited)) {
    stop('M0 detection state inconsistent with signal history.', call. = FALSE)
  }

  m0 <- list(
    ignited = ignited,
    ignition_weekF = if (!failed) .api_monitoring_scalar(detector_nums[['iWeek_hatF']], 'A ignition_weekF', FALSE) else NULL,
    ignition_week = if (!failed) .api_monitoring_scalar(detector_nums[['iWeek_hat']], 'A ignition_week', FALSE, integer = TRUE) else NULL,
    eligible_from_weekF = 12L,
    bracket_lo = if (!failed) .api_monitoring_scalar(detector_nums[['iWeek_bracket_lo']], 'A bracket_lo', FALSE, integer = TRUE) else NULL,
    bracket_hi = if (!failed) .api_monitoring_scalar(detector_nums[['iWeek_bracket_hi']], 'A bracket_hi', FALSE, integer = TRUE) else NULL,
    fraction_method = if (!failed) as.character(detection$iWeek_fraction_method[[1L]]) else NULL
  )

  if (!file.exists(paths[['m1']])) {
    if (ignited) stop('M1 timing file missing after M0 ignition.', call.=FALSE)
    m1 <- list(
      available = FALSE, state = 'inactive_pre_ignition',
      weeks_elapsed_since_activation = NULL, weeks_to_peak = NULL,
      raw_peak_mean_weekF = NULL, peak_mean_weekF = NULL,
      peak_q05_weekF = NULL, peak_q95_weekF = NULL, interval_width_90 = NULL,
      prob_peak_passed = NULL, prob_peak_within_1w = NULL,
      prob_peak_within_2w = NULL, prob_peak_within_3w = NULL,
      peak_passed = NULL, locked_peak_weekF = NULL
    )
  } else {
    timing <- utils::read.csv(paths[['m1']], stringsAsFactors = FALSE, check.names = FALSE)
    timing_columns <- c(
      'season', 'origin_week', 'asof_boundary', 'state', 'weeks_elapsed_since_activation',
      'weeks_to_calibrated_peak', 'raw_peak_mean', 'calibrated_peak_mean',
      'calibrated_mean_is_future', 'raw_peak_q05', 'raw_peak_q95',
      'calibrated_peak_q05', 'calibrated_peak_q95', 'peak_q05', 'peak_q95',
      'interval_width_90', 'prob_peak_passed', 'prob_peak_within_1w',
      'prob_peak_within_2w', 'prob_peak_within_3w', 'passage_peak_mean_raw',
      'passage_peak_mean_calibrated', 'peak_passed', 'locked_peak_week',
      'locked_at_origin', 'error'
    )
    if (!identical(names(timing), timing_columns) || nrow(timing) != 1L ||
        !identical(as.character(timing$season[[1L]]), receipt[['season']]) ||
        !identical(suppressWarnings(as.integer(timing$origin_week[[1L]])), origin)) {
      stop('M1 timing schema/identity mismatch.', call. = FALSE)
    }
    state <- as.character(timing$state[[1L]])
    if (is.na(state) || !nzchar(state) || (!ignited && identical(state, 'active')) ||
        (identical(state, 'active') && !ignited)) {
      stop('M1 state inconsistent with M0 ignition.', call. = FALSE)
    }
    active <- identical(state, 'active')
    if (ignited && !active) stop('M1 timing is not active after M0 ignition.', call.=FALSE)
    m1_fields <- c(
      'weeks_elapsed_since_activation', 'weeks_to_calibrated_peak', 'raw_peak_mean',
      'calibrated_peak_mean', 'calibrated_peak_q05', 'calibrated_peak_q95',
      'interval_width_90', 'prob_peak_passed', 'prob_peak_within_1w',
      'prob_peak_within_2w', 'prob_peak_within_3w'
    )
    m1_values <- lapply(m1_fields, function(nm) .api_monitoring_scalar(
      timing[[nm]][[1L]], paste0('A ', nm), allow_null = !active,
      probability = startsWith(nm, 'prob_')
    ))
    names(m1_values) <- m1_fields
    if (active) {
      if (!is.logical(timing$peak_passed) || is.na(timing$peak_passed[[1L]]) ||
          is.na(m1_values$calibrated_peak_q05) || is.na(m1_values$calibrated_peak_q95) ||
          m1_values$calibrated_peak_q05 > m1_values$calibrated_peak_q95 ||
          m1_values$interval_width_90 < 0 ||
          m1_values$calibrated_peak_mean < m1_values$calibrated_peak_q05 - 1e-8 ||
          m1_values$calibrated_peak_mean > m1_values$calibrated_peak_q95 + 1e-8 ||
          detector_nums[['iWeek_hatF']] > origin) {
        stop('Active M1 timing values invalid.', call. = FALSE)
      }
    }
    optional_timing <- function(name) .api_monitoring_scalar(timing[[name]][[1L]], paste0('A ', name), allow_null = TRUE)
    m1 <- list(
      available = active,
      state = state,
      weeks_elapsed_since_activation = m1_values$weeks_elapsed_since_activation,
      weeks_to_peak = m1_values$weeks_to_calibrated_peak,
      raw_peak_mean_weekF = m1_values$raw_peak_mean,
      peak_mean_weekF = m1_values$calibrated_peak_mean,
      peak_q05_weekF = m1_values$calibrated_peak_q05,
      peak_q95_weekF = m1_values$calibrated_peak_q95,
      interval_width_90 = m1_values$interval_width_90,
      prob_peak_passed = m1_values$prob_peak_passed,
      prob_peak_within_1w = m1_values$prob_peak_within_1w,
      prob_peak_within_2w = m1_values$prob_peak_within_2w,
      prob_peak_within_3w = m1_values$prob_peak_within_3w,
      peak_passed = if (!is.na(timing$peak_passed[[1L]])) isTRUE(timing$peak_passed[[1L]]) else NULL,
      locked_peak_weekF = optional_timing('locked_peak_week')
    )
  }

  b1 <- pred[pred$type == 'B' & pred$horizon == 1L, , drop = FALSE]
  b2 <- pred[pred$type == 'B' & pred$horizon == 2L, , drop = FALSE]
  if (nrow(b1) != 1L || nrow(b2) != 1L ||
      isTRUE(b1$timing_available[[1L]]) ||
      !identical(b1$season[[1L]], b2$season[[1L]]) ||
      !identical(b1$origin_weekF[[1L]], b2$origin_weekF[[1L]]) ||
      !identical(b1$model_version[[1L]], b2$model_version[[1L]]) ||
      !identical(b1$artifact_id[[1L]], b2$artifact_id[[1L]])) {
    stop('B timing projection rows invalid.', call. = FALSE)
  }
  b_available <- isTRUE(b2$timing_available[[1L]])
  b_route <- as.character(b2$route[[1L]])
  if (b_available && (!identical(b_route, 'posterior_C2') ||
      !is.finite(b2$posterior_mean_peak[[1L]]) || !is.finite(b2$prob_peak_passed[[1L]]) ||
      b2$prob_peak_passed[[1L]] < 0 || b2$prob_peak_passed[[1L]] > 1)) {
    stop('B available timing requires posterior_C2 and finite posterior fields.', call. = FALSE)
  }
  b_m1 <- list(
    available = b_available,
    timing_reason = as.character(b2$timing_reason[[1L]]),
    activity_weekF = .api_monitoring_scalar(b2$activity_week[[1L]], 'B activity_week', TRUE),
    prob_peak_passed = .api_monitoring_scalar(b2$prob_peak_passed[[1L]], 'B prob_peak_passed', TRUE, probability = TRUE),
    peak_mean_weekF = .api_monitoring_scalar(b2$posterior_mean_peak[[1L]], 'B posterior_mean_peak', TRUE),
    supported_mass = .api_monitoring_scalar(b2$supported_mass[[1L]], 'B supported_mass', FALSE, probability = TRUE),
    lower_bound_mass = .api_monitoring_scalar(b2$lower_bound_mass[[1L]], 'B lower_bound_mass', FALSE, probability = TRUE),
    lower_bound_saturated = isTRUE(b2$lower_bound_saturated[[1L]]),
    model_version = as.character(b2$model_version[[1L]]),
    route = b_route
  )
  monitoring <- list(
    origin_weekF = origin,
    release_id = receipt[['release_id']],
    child_run = basename(receipt[['v3_child_run']]),
    A = list(m0 = m0, m1 = m1),
    B = list(m1 = b_m1)
  )
  hashes <- list(
    m0_detection = .api_sha256_file(paths[['m0']]),
    signals = .api_sha256_file(paths[['signals']]),
    m1a = if (file.exists(paths[['m1']])) .api_sha256_file(paths[['m1']]) else NULL,
    combined = .api_sha256_file(paths[['combined']]),
    provenance = .api_sha256_file(paths[['provenance']]),
    status = .api_sha256_file(paths[['status']])
  )
  list(monitoring = monitoring, file_sha256 = hashes)
}
.api_validate_and_project_transaction <- function(config,run_id,persist=TRUE) {
  schema <- .api_transaction_schema(config$transaction_schema)
  tx_dir <- .api_find_published_transaction(config,run_id)
  completed_path <- file.path(tx_dir,'COMPLETED')
  completed_size <- file.info(completed_path)$size
  if (is.na(completed_size) || completed_size < 1) stop('COMPLETED marker missing/empty.',call.=FALSE)
  con <- file(completed_path,'rb'); completed_raw <- readBin(con,'raw',n=completed_size); close(con)
  completed_expected <- charToRaw(enc2utf8(paste0('COMPLETE\n',config$forecast_release_id,'\n')))
  if (!identical(completed_raw,completed_expected)) stop('COMPLETED marker bytes mismatch.',call.=FALSE)
  parent_keys <- schema$name[schema$surface=='parent_receipt']
  receipt <- .api_read_tsv_kv_exact(file.path(tx_dir,'source_transaction.tsv'),parent_keys)
  if (!identical(receipt[['status']],'COMPLETE') || !identical(receipt[['season']],config$season) || !identical(receipt[['release_id']],config$forecast_release_id)) stop('Parent transaction identity mismatch.',call.=FALSE)
  if (!.api_is_utc_timestamp(receipt[['run_utc']])) stop('Parent run_utc is invalid.',call.=FALSE)
  if (!is.character(receipt[['source_original']]) || length(receipt[['source_original']])!=1L || !nzchar(receipt[['source_original']]) || grepl('[[:cntrl:]]',receipt[['source_original']])) stop('Parent source_original is invalid.',call.=FALSE)
  sha_keys <- c('release_id','release_manifest_sha256','raw_source_sha256','supplied_typed_panel_sha256','effective_panel_sha256')
  if (!all(vapply(receipt[sha_keys],.api_is_sha,logical(1)))) stop('Parent transaction SHA field invalid.',call.=FALSE)
  if (!receipt[['source_mode']] %in% c('orvt','olis')) stop('Unexpected source mode.',call.=FALSE)
  if (!.api_safe_relative(receipt[['v2_child_run']]) || !.api_safe_relative(receipt[['v3_child_run']]) || !.api_safe_relative(receipt[['raw_source_archived']])) stop('Unsafe relative reference in parent receipt.',call.=FALSE)
  origin <- suppressWarnings(as.integer(receipt[['origin_weekF']])); if (is.na(origin) || origin < 1L || as.character(origin)!=receipt[['origin_weekF']]) stop('Invalid origin_weekF.',call.=FALSE)
  cmp <- utils::read.csv(file.path(tx_dir,'v2_v3_comparison.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  cols <- schema$name[schema$surface=='comparison']
  if (!identical(names(cmp),cols) || nrow(cmp)!=4L) stop('Comparison schema/row-count mismatch.',call.=FALSE)
  if (!is.character(cmp$season) || !is.integer(cmp$origin_weekF) || !is.character(cmp$type) || !is.integer(cmp$horizon) ||
      !is.character(cmp$v3_route) || !is.character(cmp$release_id) || !is.character(cmp$effective_panel_sha256)) stop('Comparison column type mismatch.',call.=FALSE)
  nums <- c('v2_forecast_pct','v3_forecast_pct','delta_v3_minus_v2_pp')
  if (!all(vapply(cmp[nums],is.numeric,logical(1)))) stop('Comparison numeric column type mismatch.',call.=FALSE)
  if (anyNA(cmp) || anyDuplicated(paste(cmp$type,cmp$horizon)) || !setequal(paste(cmp$type,cmp$horizon),c('A 1','A 2','B 1','B 2'))) stop('Comparison key-set mismatch.',call.=FALSE)
  if (any(cmp$origin_weekF < 1L) || any(cmp$origin_weekF!=origin) || any(cmp$season!=config$season) || any(cmp$release_id!=config$forecast_release_id) || any(cmp$effective_panel_sha256!=receipt[['effective_panel_sha256']])) stop('Comparison identity mismatch.',call.=FALSE)
  if (!all(vapply(cmp[nums],function(z) all(is.finite(z)),logical(1)))) stop('Comparison has non-finite forecast values.',call.=FALSE)
  if (!all(cmp$type %in% c('A','B')) || !all(cmp$horizon %in% c(1L,2L)) || !all(cmp$v3_route %in% .PAGE_ROUTE_ALLOWLIST)) stop('Comparison enum value outside allowlist.',call.=FALSE)
  if (any(abs(cmp$delta_v3_minus_v2_pp - (cmp$v3_forecast_pct-cmp$v2_forecast_pct)) > 1e-10)) stop('Comparison delta is inconsistent.',call.=FALSE)
  manifest_sha <- .api_sha256_file(file.path(config$forecast_release_dir,'release_manifest.tsv'))
  if (!identical(receipt[['release_manifest_sha256']],manifest_sha)) stop('Release manifest SHA mismatch.',call.=FALSE)
  tx_id <- basename(tx_dir)
  ref <- list(transaction_id=tx_id,season=config$season,origin_weekF=origin,release_id=config$forecast_release_id,effective_panel_sha256=receipt[['effective_panel_sha256']])
  forecasts <- lapply(seq_len(nrow(cmp)),function(i) list(type=cmp$type[[i]],horizon=as.integer(cmp$horizon[[i]]),v2_pct=as.numeric(cmp$v2_forecast_pct[[i]]),v3_pct=as.numeric(cmp$v3_forecast_pct[[i]]),delta_pp=as.numeric(cmp$delta_v3_minus_v2_pp[[i]]),v3_route=cmp$v3_route[[i]]))
  mon <- .api_monitoring_projection(tx_dir,receipt,cmp,config)
  result <- list(run_id=run_id,season=config$season,origin_weekF=origin,release_id=config$forecast_release_id,effective_panel_sha256=receipt[['effective_panel_sha256']],monitoring=mon$monitoring,forecasts=forecasts)
  provenance <- list(run_id=run_id,season=config$season,origin_weekF=origin,release_id=config$forecast_release_id,release_manifest_sha256=manifest_sha,source_mode=receipt[['source_mode']],raw_source_sha256=receipt[['raw_source_sha256']],supplied_typed_panel_sha256=receipt[['supplied_typed_panel_sha256']],effective_panel_sha256=receipt[['effective_panel_sha256']],transaction_id=tx_id,v2_child_run=basename(receipt[['v2_child_run']]),v3_child_run=basename(receipt[['v3_child_run']]),monitoring_file_sha256=mon$file_sha256,api_contract_version=.PAGE_API_CONTRACT)
  if (persist) {
    jd <- .api_job_dir(config,run_id)
    .api_atomic_write_json(ref,file.path(jd,'transaction_ref.json'),immutable=TRUE)
    .api_atomic_write_json(result,file.path(jd,'result.json'),immutable=TRUE)
    .api_atomic_write_json(provenance,file.path(jd,'provenance.json'),immutable=TRUE)
  }
  list(transaction_ref=ref,result=result,provenance=provenance)
}

.api_reconcile_job <- function(config,run_id,current_instance_id,process_registry=NULL) {
  st <- .api_read_state(config,run_id); s <- as.character(st$state)
  if (s %in% c('succeeded','failed')) { if(!is.null(process_registry)&&exists(run_id,envir=process_registry,inherits=FALSE)) rm(list=run_id,envir=process_registry); .api_release_season_lock(config,run_id); return(.api_job_projection(config,run_id)) }
  wr <- .api_worker_result_path(config,run_id)
  if (file.exists(wr)) {
    w <- .api_read_json(wr)
    if (identical(w$status,'succeeded')) {
      proj <- tryCatch(.api_validate_and_project_transaction(config,run_id,TRUE),error=identity)
      if (!inherits(proj,'error')) {
        .api_write_state(config,run_id,list(state='succeeded',updated_utc=.api_now(),finished_utc=.api_now(),service_instance_id=current_instance_id,worker_exit_code=0L,origin_weekF=proj$result$origin_weekF,effective_panel_sha256=proj$result$effective_panel_sha256,transaction_id=proj$transaction_ref$transaction_id)); .api_release_season_lock(config,run_id); return(.api_job_projection(config,run_id))
      }
      w <- list(status='failed',failure_code='transaction_validation_failed')
    }
    if (identical(w$status,'failed')) {
      f <- .api_safe_failure(w$failure_code %||% 'forecast_transaction_failed')
      .api_write_state(config,run_id,list(state='failed',updated_utc=.api_now(),finished_utc=.api_now(),service_instance_id=current_instance_id,worker_exit_code=w$exit_code %||% NA_integer_,failure_code=f$code,failure_message=f$message)); .api_release_season_lock(config,run_id); return(.api_job_projection(config,run_id))
    }
  }
  # Recovery may discover a completed transaction even if worker_result was not published.
  proj <- tryCatch(.api_validate_and_project_transaction(config,run_id,TRUE),error=function(e) NULL)
  if (!is.null(proj)) {
    .api_write_state(config,run_id,list(state='succeeded',updated_utc=.api_now(),finished_utc=.api_now(),service_instance_id=current_instance_id,worker_exit_code=0L,origin_weekF=proj$result$origin_weekF,effective_panel_sha256=proj$result$effective_panel_sha256,transaction_id=proj$transaction_ref$transaction_id)); .api_release_season_lock(config,run_id); return(.api_job_projection(config,run_id))
  }
  if (s=='accepted_pending' && !identical(as.character(st$service_instance_id),current_instance_id)) {
    idem_ok <- tryCatch({ .api_ensure_idempotency_from_request(config,run_id); TRUE },error=function(e) FALSE)
    if (!idem_ok) {
      raw_req <- tryCatch(.api_read_json(.api_request_path(config,run_id)),error=function(e) NULL)
      kh <- if (is.list(raw_req) && !is.null(raw_req$key_hash)) as.character(raw_req$key_hash) else ''
      if (.api_is_sha(kh) && !.api_blocked_idempotency(config,kh)) {
        try(.api_quarantine_idempotency(config,.api_idem_path(config,kh),'invalid-request-lineage'),silent=TRUE)
      }
    }
    f <- .api_safe_failure(if (idem_ok) 'admission_interrupted' else 'idempotency_blocked')
    .api_write_state(config,run_id,list(state='failed',updated_utc=.api_now(),finished_utc=.api_now(),service_instance_id=current_instance_id,failure_code=f$code,failure_message=f$message)); .api_release_season_lock(config,run_id)
  } else if (s %in% c('starting','running') && identical(as.character(st$service_instance_id),current_instance_id)) {
    proc <- if (!is.null(process_registry) && exists(run_id,envir=process_registry,inherits=FALSE)) get(run_id,envir=process_registry,inherits=FALSE) else NULL
    alive <- !is.null(proc) && isTRUE(tryCatch(proc$is_alive(),error=function(e) FALSE))
    if (alive && !is.null(st$started_utc)) {
      started <- suppressWarnings(as.POSIXct(as.character(st$started_utc),format='%Y-%m-%dT%H:%M:%SZ',tz='UTC'))
      elapsed <- if(is.na(started)) NA_real_ else as.numeric(difftime(Sys.time(),started,units='secs'))
      if (is.finite(elapsed) && elapsed > as.numeric(config$max_runtime_seconds)+60) {
        try(proc$kill_tree(),silent=TRUE)
        f <- .api_safe_failure('worker_timeout'); .api_write_state(config,run_id,list(state='failed',updated_utc=.api_now(),finished_utc=.api_now(),service_instance_id=current_instance_id,failure_code=f$code,failure_message=f$message)); .api_release_season_lock(config,run_id); if(exists(run_id,envir=process_registry,inherits=FALSE))rm(list=run_id,envir=process_registry); return(.api_job_projection(config,run_id))
      }
    }
    if (!alive) {
      f <- .api_safe_failure('worker_lost'); .api_write_state(config,run_id,list(state='failed',updated_utc=.api_now(),finished_utc=.api_now(),service_instance_id=current_instance_id,failure_code=f$code,failure_message=f$message)); .api_release_season_lock(config,run_id); if(!is.null(process_registry)&&exists(run_id,envir=process_registry,inherits=FALSE))rm(list=run_id,envir=process_registry)
    }
  } else if (s %in% c('starting','running') && !identical(as.character(st$service_instance_id),current_instance_id)) {
    f <- .api_safe_failure('worker_lost'); .api_write_state(config,run_id,list(state='failed',updated_utc=.api_now(),finished_utc=.api_now(),service_instance_id=current_instance_id,failure_code=f$code,failure_message=f$message)); .api_release_season_lock(config,run_id)
  }
  .api_job_projection(config,run_id)
}

.api_quarantine_job_dir <- function(config,run_id,reason='invalid') {
  if (!is.character(run_id) || length(run_id)!=1L || is.na(run_id) || !nzchar(run_id) || !identical(basename(run_id),run_id) || run_id %in% c('.','..','quarantine')) stop('Unsafe job directory name cannot be quarantined automatically.',call.=FALSE)
  jobs_root <- normalizePath(file.path(config$job_root,'jobs'),winslash='/',mustWork=TRUE)
  src <- file.path(jobs_root,run_id)
  if (!dir.exists(src)) return(invisible(NULL))
  if (nzchar(Sys.readlink(src))) stop('Symlinked malformed job directory requires operator review.',call.=FALSE)
  src_n <- normalizePath(src,winslash='/',mustWork=TRUE)
  if (!startsWith(src_n,paste0(jobs_root,'/'))) stop('Malformed job directory escapes jobs root.',call.=FALSE)
  qroot <- file.path(jobs_root,'quarantine'); dir.create(qroot,recursive=TRUE,mode='0700',showWarnings=FALSE)
  tag <- if (grepl(.PAGE_RUN_ID_RE,run_id)) run_id else paste0('invalid-',substr(.api_sha256_text(run_id),1L,16L))
  dest <- file.path(qroot,paste0(tag,'-',reason,'-',format(Sys.time(),'%Y%m%dT%H%M%SZ',tz='UTC'),'-',.api_random_hex(4L)))
  if (!file.rename(src,dest)) stop('Could not quarantine malformed job directory.',call.=FALSE)
  invisible(dest)
}

.api_reconcile_all <- function(config,current_instance_id,process_registry=NULL) {
  .api_init_store(config)
  jobs <- list.dirs(file.path(config$job_root,'jobs'),recursive=FALSE,full.names=FALSE)
  jobs <- setdiff(jobs,'quarantine')
  out <- lapply(jobs,function(id) tryCatch(.api_reconcile_job(config,id,current_instance_id,process_registry=process_registry),error=function(e) {
    .api_quarantine_job_dir(config,id,'reconcile-invalid')
    list(run_id=id,status='quarantined',failure_code='internal_error')
  }))
  invisible(out)
}

.api_validate_environment_manifest <- function(path) {
  x <- utils::read.delim(path,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  if (!all(c('component','version','location','role') %in% names(x)) || anyDuplicated(x$component)) stop('Invalid API environment manifest.',call.=FALSE)
  r <- x[x$component=='R',,drop=FALSE]; if (nrow(r)!=1L || !identical(as.character(getRversion()),r$version[[1]]) || !identical(normalizePath(R.home(),winslash='/',mustWork=TRUE),normalizePath(r$location[[1]],winslash='/',mustWork=TRUE))) stop('API R runtime mismatch.',call.=FALSE)
  pk <- x[x$component!='R',,drop=FALSE]
  for (i in seq_len(nrow(pk))) {
    p <- pk$component[[i]]; if (!requireNamespace(p,quietly=TRUE)) stop('Missing API runtime package: ',p,call.=FALSE)
    if (!identical(as.character(utils::packageVersion(p)),pk$version[[i]])) stop('API package version mismatch: ',p,call.=FALSE)
    if (!identical(normalizePath(find.package(p),winslash='/',mustWork=TRUE),normalizePath(pk$location[[i]],winslash='/',mustWork=TRUE))) stop('API package location mismatch: ',p,call.=FALSE)
  }
  invisible(TRUE)
}

.api_load_config_from_env <- function(repo_root=getwd(),strict_storage=TRUE) {
  get <- function(k,default=NULL,required=FALSE) { v<-Sys.getenv(k,unset=''); if (!nzchar(v)) v<-default; if (required && (is.null(v)||!nzchar(v))) stop('Missing required environment variable ',k,call.=FALSE); v }
  cfg <- list(
    repo_root=normalizePath(repo_root,winslash='/',mustWork=TRUE),
    bind_host=get('PAGE_API_BIND_HOST','127.0.0.1'), port=as.integer(get('PAGE_API_PORT','8088')),
    token_file=get('PAGE_API_TOKEN_FILE',required=TRUE), api_deployment_dir=get('PAGE_API_DEPLOYMENT_DIR',required=TRUE),
    forecast_release_dir=get('PAGE_RELEASE_DIR',required=TRUE), forecast_release_id=.PAGE_FORECAST_RELEASE_ID,
    artifact_mount=get('PAGE_ARTIFACT_MOUNT',required=TRUE), artifact_fs_type=get('PAGE_ARTIFACT_FS_TYPE',required=strict_storage), artifact_mount_source=get('PAGE_ARTIFACT_MOUNT_SOURCE',required=strict_storage), job_root=get('PAGE_JOB_ROOT',required=TRUE), output_root=get('PAGE_OUTPUT_ROOT',required=TRUE),
    source_mode=get('PAGE_SOURCE_MODE','auto'), season=get('PAGE_SEASON',required=TRUE), olis_fallback=get('PAGE_OLIS_FALLBACK',NULL),
    rscript=get('PAGE_RSCRIPT',Sys.which('Rscript')), max_runtime_seconds=as.integer(get('PAGE_MAX_RUNTIME_SECONDS','1800')),
    transaction_schema=file.path(normalizePath(repo_root,winslash='/',mustWork=TRUE),'governance/v3_weekly_api_transaction_schema_v1.csv'),
    api_environment=file.path(normalizePath(repo_root,winslash='/',mustWork=TRUE),'governance/v3_weekly_api_environment_v1.tsv')
  )
  if (!cfg$bind_host %in% c('127.0.0.1','::1')) stop('API listener must be loopback-only.',call.=FALSE)
  if (is.na(cfg$port)||cfg$port<1L||cfg$port>65535L) stop('Invalid API port.',call.=FALSE)
  if (!cfg$source_mode %in% c('auto','orvt','olis')) stop('Invalid configured source mode.',call.=FALSE)
  if (!grepl('^[0-9]{4}-[0-9]{2}$',cfg$season)) stop('Invalid configured season.',call.=FALSE)
  if (!identical(cfg$season,'2026-27')) stop('API v1 policy is pinned to deployment season 2026-27.',call.=FALSE)
  .api_assert_regular_nonsymlink(cfg$rscript,'Rscript'); .api_assert_regular_nonsymlink(cfg$token_file,'Token file')
  .api_validate_environment_manifest(cfg$api_environment)
  .api_validate_storage(cfg,strict_mount=strict_storage)
  cfg
}
