#!/usr/bin/env Rscript
options(stringsAsFactors=FALSE)

PANEL_PATH <- 'artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv'
NESTED_SUMMARY <- 'artifacts/m2-a-ntrend-fully-nested-loso-wmin12-v1/summary.csv'
NESTED_SELECTION <- 'artifacts/m2-a-ntrend-fully-nested-loso-wmin12-v1/selection_frequency.csv'
OUT <- 'governance/v3_a_exp050_h2_shadow_v1.rds'
RELEASE_ID <- '5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b'

sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
clip <- function(p,eps=1e-6) pmin(pmax(as.numeric(p),eps),1-eps)
stab <- function(y,N) (y+0.5)/(N+1)

build_ledger <- function(ab) {
  req <- c('season','weekF','y_A','N_A','denominator_regime')
  miss <- setdiff(req,names(ab)); if(length(miss)) stop('Historical panel missing: ',paste(miss,collapse=', '),call.=FALSE)
  rows <- list()
  for(s in sort(unique(as.character(ab$season)))) {
    z <- ab[ab$season==s,,drop=FALSE]; z <- z[order(z$weekF),,drop=FALSE]
    if(anyDuplicated(z$weekF)) stop('Duplicate weekF in ',s,call.=FALSE)
    m <- stats::setNames(seq_len(nrow(z)),as.character(z$weekF))
    ps <- stab(z$y_A,z$N_A); lg <- stats::qlogis(clip(ps)); ln <- log(z$N_A)
    for(i in seq_len(nrow(z))) {
      w <- as.integer(z$weekF[i]); if(w<12L) next
      hist <- unname(m[as.character((w-4L):w)])
      i1 <- unname(m[as.character(w-1L)]); i2 <- unname(m[as.character(w-2L)])
      if(anyNA(c(hist,i1,i2))) next
      lv <- ln[hist]; ds <- c(lv[5]-lv[4],lv[4]-lv[3],lv[3]-lv[2],lv[2]-lv[1])
      ww <- 0.5^(0:3); exp050 <- sum(ds*ww)/sum(ww)
      for(h in 1:2) {
        j <- unname(m[as.character(w+h)]); if(is.na(j)) next
        rows[[length(rows)+1L]] <- data.frame(
          season=s,origin_week=w,horizon=h,y_target=as.numeric(z$y_A[j]),N_target=as.numeric(z$N_A[j]),
          logit_current=lg[i],growth1=lg[i]-lg[i1],growth2=(lg[i]-lg[i2])/2,exp050=exp050,
          denominator_regime=as.character(z$denominator_regime[i]),stringsAsFactors=FALSE)
      }
    }
  }
  d <- do.call(rbind,rows); d$horizon_f <- factor(paste0('h',d$horizon),levels=c('h1','h2')); d
}

if(!requireNamespace('digest',quietly=TRUE)) stop('digest required.',call.=FALSE)
for(p in c(PANEL_PATH,NESTED_SUMMARY,NESTED_SELECTION)) if(!file.exists(p)) stop('Required evidence missing: ',p,call.=FALSE)

ab <- read.csv(PANEL_PATH,stringsAsFactors=FALSE,check.names=FALSE)
ledger <- build_ledger(ab)
fit <- suppressWarnings(stats::glm(
  cbind(y_target,N_target-y_target) ~ horizon_f + growth1 + growth2 + exp050 + offset(logit_current),
  data=ledger,family=stats::quasibinomial()))
co <- stats::coef(fit)
required <- c('(Intercept)','horizon_fh2','growth1','growth2','exp050')
if(!identical(names(co),required) || any(!is.finite(co))) stop('EXP050 shadow fit coefficient payload invalid.',call.=FALSE)

nested_summary <- read.csv(NESTED_SUMMARY,stringsAsFactors=FALSE)
nested_selection <- read.csv(NESTED_SELECTION,stringsAsFactors=FALSE)
h2 <- nested_summary[nested_summary$horizon==2L,,drop=FALSE]
if(nrow(h2)!=1L) stop('Nested +2 summary evidence missing.',call.=FALSE)
sel_h2 <- nested_selection[nested_selection$horizon==2L,,drop=FALSE]
if(!nrow(sel_h2) || sum(sel_h2$Freq)<=0L) stop('Nested +2 selection evidence missing.',call.=FALSE)

artifact <- list(
  version='v3-a-exp050-h2-shadow-v1',status='experimental_shadow',production_eligible=FALSE,
  canonical_release_id=RELEASE_ID,
  scope=list(type='A',horizons=2L,canonical_route_unchanged=TRUE,request_option='exp050_h2'),
  feature=list(
    transform='log_N',
    increments=c('d1=log(N_t)-log(N_t-1)','d2=log(N_t-1)-log(N_t-2)','d3=log(N_t-2)-log(N_t-3)','d4=log(N_t-3)-log(N_t-4)'),
    exp050='(d1 + 0.5*d2 + 0.25*d3 + 0.125*d4) / 1.875',
    exact_history=TRUE,min_origin_week=12L),
  fit=list(
    family='quasibinomial_logit',
    formula='cbind(y_target,N_target-y_target) ~ horizon_f + growth1 + growth2 + exp050 + offset(logit_current)',
    coefficients=co,dispersion=unname(summary(fit)$dispersion),n_rows=nrow(ledger),n_seasons=length(unique(ledger$season)),
    training_seasons=sort(unique(as.character(ledger$season)))),
  evidence=list(
    nested_design='fully_nested_fixed_A1_form_LOSO_with_paired_one_SE_wmin12',
    plus2_off_mae_pp=as.numeric(h2$off_mae_pp),plus2_nested_mae_pp=as.numeric(h2$nested_mae_pp),
    plus2_relative_mae_gain=as.numeric(h2$relative_mae_gain),
    plus2_selection_frequency=sel_h2[,c('selected_candidate','Freq'),drop=FALSE],
    disposition='shadow_only_modest_outer_gain'),
  provenance=list(
    training_panel=PANEL_PATH,training_panel_sha256=sha256_file(PANEL_PATH),
    nested_summary=NESTED_SUMMARY,nested_summary_sha256=sha256_file(NESTED_SUMMARY),
    nested_selection=NESTED_SELECTION,nested_selection_sha256=sha256_file(NESTED_SELECTION),
    builder='scripts/build_v3_a_exp050_shadow_v1.R')
)
artifact$artifact_id <- digest::digest(artifact,algo='sha256')
dir.create(dirname(OUT),recursive=TRUE,showWarnings=FALSE)
saveRDS(artifact,OUT,version=3)
cat('artifact=',OUT,'\nartifact_id=',artifact$artifact_id,'\nsha256=',sha256_file(OUT),'\n',sep='')
cat('coefficients\n'); print(co,digits=12)
cat('evidence\n'); print(artifact$evidence)
