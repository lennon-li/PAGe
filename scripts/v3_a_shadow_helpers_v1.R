# API-side A challenger helpers. Canonical v3 routing is never modified.

.PAGE_A_SHADOW_OPTIONS <- c('off','exp050_h2')
.PAGE_A_EXP050_PATH <- 'governance/v3_a_exp050_h2_shadow_v1.rds'

.page_a_shadow_validate_option <- function(x) {
  if (!is.character(x) || length(x)!=1L || is.na(x) || !x %in% .PAGE_A_SHADOW_OPTIONS)
    stop('Invalid A shadow option.',call.=FALSE)
  x
}

.page_a_shadow_load_exp050 <- local({
  cache <- NULL
  function(path=.PAGE_A_EXP050_PATH) {
    if(!is.null(cache)) return(cache)
    if(!file.exists(path)) stop('A EXP050 shadow artifact unavailable.',call.=FALSE)
    a <- readRDS(path)
    req <- c('version','status','production_eligible','canonical_release_id','scope','feature','fit','evidence','provenance','artifact_id')
    if(!identical(sort(names(a)),sort(req))) stop('A EXP050 shadow artifact schema invalid.',call.=FALSE)
    id <- a$artifact_id; a$artifact_id <- NULL
    if(!requireNamespace('digest',quietly=TRUE) || !identical(id,digest::digest(a,algo='sha256')))
      stop('A EXP050 shadow artifact identity mismatch.',call.=FALSE)
    a$artifact_id <- id
    if(!identical(a$version,'v3-a-exp050-h2-shadow-v1') || !identical(a$status,'experimental_shadow') || isTRUE(a$production_eligible))
      stop('A EXP050 shadow artifact status invalid.',call.=FALSE)
    if(!exists('.PAGE_V3_RELEASE_ID',inherits=TRUE) || !identical(a$canonical_release_id,.PAGE_V3_RELEASE_ID))
      stop('A EXP050 shadow artifact release binding mismatch.',call.=FALSE)
    co <- a$fit$coefficients
    if(!identical(names(co),c('(Intercept)','horizon_fh2','growth1','growth2','exp050')) || any(!is.finite(co)))
      stop('A EXP050 shadow coefficient payload invalid.',call.=FALSE)
    cache <<- a; cache
  }
})

.page_a_shadow_runtime_features <- function(panel,origin_week) {
  d <- as.data.frame(panel,stringsAsFactors=FALSE)
  if(!all(c('weekF','y_A','N_A') %in% names(d))) stop('Typed panel lacks A count columns.',call.=FALSE)
  d <- d[d$weekF<=as.integer(origin_week),,drop=FALSE]; d <- d[order(d$weekF),,drop=FALSE]
  if(anyDuplicated(d$weekF)) stop('Typed panel has duplicate weekF rows.',call.=FALSE)
  m <- stats::setNames(seq_len(nrow(d)),as.character(d$weekF)); w <- as.integer(origin_week)
  ids <- unname(m[as.character((w-4L):w)]); i1 <- unname(m[as.character(w-1L)]); i2 <- unname(m[as.character(w-2L)]); i <- unname(m[as.character(w)])
  if(anyNA(c(ids,i1,i2,i))) stop('A EXP050 shadow requires exact weeks t-4 through t.',call.=FALSE)
  if(any(!is.finite(d$N_A[ids])) || any(d$N_A[ids]<=0) || any(!is.finite(d$y_A[c(i,i1,i2)]))) stop('A EXP050 shadow received invalid counts.',call.=FALSE)
  ps <- (d$y_A+0.5)/(d$N_A+1); lg <- stats::qlogis(pmin(pmax(ps,1e-6),1-1e-6)); ln <- log(d$N_A)
  lv <- ln[ids]; ds <- c(lv[5]-lv[4],lv[4]-lv[3],lv[3]-lv[2],lv[2]-lv[1]); ww <- 0.5^(0:3)
  list(logit_current=lg[i],growth1=lg[i]-lg[i1],growth2=(lg[i]-lg[i2])/2,exp050=sum(ds*ww)/sum(ww),
       N_current=d$N_A[i],N_lag1=d$N_A[i1],N_lag2=d$N_A[i2],N_lag3=d$N_A[ids[2]],N_lag4=d$N_A[ids[1]])
}

.page_a_shadow_predict_exp050_h2 <- function(panel,origin_week,canonical_h2_pct) {
  a <- .page_a_shadow_load_exp050()
  if (as.integer(origin_week) < as.integer(a$feature$min_origin_week)) stop('A EXP050 shadow is outside validated origin support.',call.=FALSE)
  f <- .page_a_shadow_runtime_features(panel,origin_week); b <- a$fit$coefficients
  eta <- f$logit_current + b[['(Intercept)']] + b[['horizon_fh2']] + b[['growth1']]*f$growth1 + b[['growth2']]*f$growth2 + b[['exp050']]*f$exp050
  p <- as.numeric(stats::plogis(eta)); if(!is.finite(p) || p<=0 || p>=1) stop('A EXP050 shadow prediction invalid.',call.=FALSE)
  list(
    option='exp050_h2',status='experimental_shadow',type='A',horizon=2L,
    canonical_route='exact_A1_state',canonical_forecast_pct=as.numeric(canonical_h2_pct),
    challenger_route='shadow_A1form_EXP050_h2',challenger_forecast_pct=100*p,
    delta_challenger_minus_canonical_pp=100*p-as.numeric(canonical_h2_pct),
    feature=list(exp050=as.numeric(f$exp050),growth1=as.numeric(f$growth1),growth2=as.numeric(f$growth2),N_current=as.numeric(f$N_current),N_lag1=as.numeric(f$N_lag1),N_lag2=as.numeric(f$N_lag2),N_lag3=as.numeric(f$N_lag3),N_lag4=as.numeric(f$N_lag4)),
    artifact=list(version=a$version,artifact_id=a$artifact_id,training_seasons=a$fit$training_seasons,evidence=a$evidence),
    canonical_unchanged=TRUE
  )
}

.page_a_shadow_snapshot <- function(transaction_dir,option) {
  option <- .page_a_shadow_validate_option(option)
  receipt_path <- file.path(transaction_dir,'source_transaction.tsv'); cmp_path <- file.path(transaction_dir,'v2_v3_comparison.csv'); panel_path <- file.path(transaction_dir,'typed_ab_weekly.csv')
  for(p in c(receipt_path,cmp_path,panel_path)) if(!file.exists(p)) stop('A shadow transaction input missing: ',basename(p),call.=FALSE)
  r <- utils::read.delim(receipt_path,sep='\t',stringsAsFactors=FALSE,check.names=FALSE); receipt <- stats::setNames(as.character(r$value),as.character(r$key))
  cmp <- utils::read.csv(cmp_path,stringsAsFactors=FALSE,check.names=FALSE); panel <- utils::read.csv(panel_path,stringsAsFactors=FALSE,check.names=FALSE)
  origin <- as.integer(receipt[['origin_weekF']]); season <- as.character(receipt[['season']]); release_id <- as.character(receipt[['release_id']])
  if(!identical(release_id,.PAGE_V3_RELEASE_ID)) stop('A shadow transaction release mismatch.',call.=FALSE)
  a2 <- cmp[cmp$type=='A' & cmp$horizon==2L,,drop=FALSE]
  if(nrow(a2)!=1L || !identical(as.character(a2$v3_route[[1L]]),'exact_A1_state') || !is.finite(a2$v3_forecast_pct[[1L]])) stop('Canonical A+2 transaction row invalid.',call.=FALSE)
  challenger <- if(option=='off') NULL else .page_a_shadow_predict_exp050_h2(panel,origin,a2$v3_forecast_pct[[1L]])
  list(schema_version='page-v3-a-shadow-snapshot-v1',status=if(option=='off') 'off' else 'experimental_shadow',option=option,
       season=season,origin_weekF=origin,release_id=release_id,canonical_unchanged=TRUE,challenger=challenger)
}
