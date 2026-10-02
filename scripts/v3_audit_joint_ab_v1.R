#!/usr/bin/env Rscript

# PAGe v3 paired influenza A/B historical-data audit.
# Research-only: does not modify or consume governed v2 artifacts as outputs.

source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/season_calendar.R')
source('PAGe/R/retrospective_peak_truth.R')

hist_path <- 'hist2026-09-16.RData'
prepared_path <- '../PAGe/results/manuscript/all-season-holdout-prep-20260914-r2/prepared_data_all_seasons.rds'
a_ignition_path <- 'artifacts/expert-ignition-annotation-v2-pass1/expert_ignition_labels_v2_pass1.csv'
out_dir <- 'artifacts/v3-joint-ab-audit-v1'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

stopifnot(file.exists(hist_path), file.exists(prepared_path), file.exists(a_ignition_path))

sha256 <- function(path) digest::digest(file=path, algo='sha256')

target_seasons <- c(
  '2012-13','2013-14','2014-15','2016-17','2017-18','2018-19',
  '2019-20','2022-23','2023-24','2024-25','2025-26'
)

# -----------------------------------------------------------------------------
# 1. Audit copied September hist RData.
# -----------------------------------------------------------------------------
e <- new.env(parent=emptyenv())
load(hist_path, envir=e)
if (!identical(ls(e), 'r') || !is.list(e$r)) stop('Expected one top-level list object `r`.', call.=FALSE)
r <- e$r

inventory <- do.call(rbind, lapply(names(r), function(nm) {
  x <- r[[nm]]
  data.frame(
    object=nm,
    class=paste(class(x), collapse='/'),
    nrow=if(is.data.frame(x)) nrow(x) else NA_integer_,
    ncol=if(is.data.frame(x)) ncol(x) else NA_integer_,
    columns=if(is.data.frame(x)) paste(names(x), collapse='|') else NA_character_,
    date_min=if(is.data.frame(x) && 'date' %in% names(x)) as.character(min(as.Date(x$date),na.rm=TRUE)) else NA_character_,
    date_max=if(is.data.frame(x) && 'date' %in% names(x)) as.character(max(as.Date(x$date),na.rm=TRUE)) else NA_character_,
    age_levels=if(is.data.frame(x) && 'age.' %in% names(x)) paste(sort(unique(as.character(x$age.))),collapse='|') else NA_character_,
    stringsAsFactors=FALSE
  )
}))
write.csv(inventory,file.path(out_dir,'hist_object_inventory.csv'),row.names=FALSE)

for (nm in c('flu','fluA','fluB')) {
  req <- c('date','age.','pos','tests','prop','neg')
  if (!all(req %in% names(r[[nm]]))) stop('r$',nm,' missing required fields.',call.=FALSE)
}

aggregate_daily_type <- function(x, prefix) {
  x$date <- as.Date(x$date)
  z <- aggregate(cbind(pos,tests)~date,x,sum)
  names(z)[2:3] <- paste0(prefix,c('_pos','_tests'))
  z
}

A_daily <- aggregate_daily_type(r$fluA,'A')
B_daily <- aggregate_daily_type(r$fluB,'B')
F_daily <- aggregate_daily_type(r$flu,'flu')
daily <- Reduce(function(x,y) merge(x,y,by='date',all=TRUE),list(A_daily,B_daily,F_daily))
if (anyNA(daily)) stop('A/B/flu daily aggregate dates do not fully reconcile.',call.=FALSE)

cal <- page_season_calendar(daily$date,start_week=27L)
daily$season <- cal$season
daily$weekF <- cal$weekF

weekly_hist <- aggregate(
  cbind(A_pos,A_tests,B_pos,B_tests,flu_pos,flu_tests)~season+weekF,
  daily,sum
)
day_count <- aggregate(date~season+weekF,daily,function(x) length(unique(x)))
names(day_count)[3] <- 'n_days'
weekly_hist <- merge(weekly_hist,day_count,by=c('season','weekF'),sort=TRUE)
weekly_hist <- weekly_hist[order(weekly_hist$season,weekly_hist$weekF),]
weekly_hist$A_B_den_equal <- weekly_hist$A_tests==weekly_hist$B_tests
weekly_hist$flu_pos_equals_A_plus_B <- weekly_hist$flu_pos==(weekly_hist$A_pos+weekly_hist$B_pos)
weekly_hist$flu_tests_equals_max_AB <- weekly_hist$flu_tests==pmax(weekly_hist$A_tests,weekly_hist$B_tests)

coverage <- do.call(rbind,lapply(target_seasons,function(s){
  q <- weekly_hist[weekly_hist$season==s,]
  if(!nrow(q)) return(data.frame(
    season=s,n_weeks=0L,weekF_min=NA_integer_,weekF_max=NA_integer_,
    all_weeks_present=FALSE,all_weeks_7_days=FALSE,zero_test_weeks_A=NA_integer_,zero_test_weeks_B=NA_integer_,
    A_B_den_equal_weeks=NA_integer_,max_abs_A_B_den_diff=NA_real_,
    stringsAsFactors=FALSE))
  nW <- unique(page_season_calendar(mmwr_year=as.integer(substr(s,1,4)),week=27L)$nW_true)
  expected <- seq_len(nW)
  data.frame(
    season=s,n_weeks=nrow(q),weekF_min=min(q$weekF),weekF_max=max(q$weekF),
    all_weeks_present=identical(sort(q$weekF),expected),
    all_weeks_7_days=all(q$n_days==7L),
    zero_test_weeks_A=sum(q$A_tests<=0),zero_test_weeks_B=sum(q$B_tests<=0),
    A_B_den_equal_weeks=sum(q$A_B_den_equal),
    max_abs_A_B_den_diff=max(abs(q$A_tests-q$B_tests)),
    stringsAsFactors=FALSE
  )
}))
write.csv(coverage,file.path(out_dir,'hist_target_season_coverage.csv'),row.names=FALSE)

# Age-stratum completeness in the copied source.
age_audit <- do.call(rbind,lapply(c('fluA','fluB'),function(nm){
  x <- r[[nm]]
  x$date <- as.Date(x$date)
  n_age <- aggregate(age.~date,x,function(z) length(unique(z)))
  data.frame(
    type=if(nm=='fluA') 'A' else 'B',
    date_min=as.character(min(x$date)),date_max=as.character(max(x$date)),
    n_dates=length(unique(x$date)),age_levels=paste(sort(unique(as.character(x$age.))),collapse='|'),
    min_age_strata_per_date=min(n_age$age.),max_age_strata_per_date=max(n_age$age.),
    zero_test_age_days=sum(x$tests<=0),stringsAsFactors=FALSE
  )
}))
write.csv(age_audit,file.path(out_dir,'hist_age_strata_audit.csv'),row.names=FALSE)

# -----------------------------------------------------------------------------
# 2. Build canonical target-season weekly A/B panel.
#    Fully covered September hist seasons use direct type-specific denominators.
#    Earlier/incomplete seasons retain the full manuscript-prepared shared proxy.
# -----------------------------------------------------------------------------
prepared <- readRDS(prepared_path)
req_prep <- c('season','weekF','y','N','p','pos_flub','fluBPercentPositive')
if (!all(req_prep %in% names(prepared))) stop('Prepared historical source schema changed.',call.=FALSE)

full_hist_seasons <- coverage$season[
  coverage$all_weeks_present & coverage$all_weeks_7_days &
  coverage$zero_test_weeks_A==0 & coverage$zero_test_weeks_B==0
]
# Do not silently add non-target pandemic seasons; target universe remains frozen for this audit.
full_hist_seasons <- intersect(target_seasons,full_hist_seasons)

canonical_parts <- list()
for (s in target_seasons) {
  if (s %in% full_hist_seasons) {
    q <- weekly_hist[weekly_hist$season==s,]
    z <- data.frame(
      season=s,weekF=q$weekF,
      y_A=q$A_pos,N_A=q$A_tests,p_A=q$A_pos/q$A_tests,
      y_B=q$B_pos,N_B=q$B_tests,p_B=q$B_pos/q$B_tests,
      denominator_regime='hist_type_specific',
      source_kind='hist2026_09_16_daily_age_aggregate',
      source_vintage='2026-09-16',
      stringsAsFactors=FALSE
    )
  } else {
    q <- prepared[prepared$season==s,]
    if (!nrow(q)) stop('No prepared historical rows for target season ',s,call.=FALSE)
    z <- data.frame(
      season=s,weekF=q$weekF,
      y_A=as.numeric(q$y),N_A=as.numeric(q$N),p_A=as.numeric(q$p),
      y_B=as.numeric(q$pos_flub),N_B=as.numeric(q$N),p_B=as.numeric(q$pos_flub)/as.numeric(q$N),
      denominator_regime='historical_shared_flu_test_proxy',
      source_kind='manuscript_prepared_historical',
      source_vintage='all-season-holdout-prep-20260914-r2',
      stringsAsFactors=FALSE
    )
  }
  canonical_parts[[s]] <- z
}
canonical <- do.call(rbind,canonical_parts)
canonical <- canonical[order(match(canonical$season,target_seasons),canonical$weekF),]
rownames(canonical) <- NULL

if (anyDuplicated(canonical[,c('season','weekF')])) stop('Duplicate canonical season/week rows.',call.=FALSE)
if (anyNA(canonical)) stop('Canonical panel contains NA values.',call.=FALSE)
if (any(canonical$y_A<0 | canonical$y_B<0 | canonical$N_A<=0 | canonical$N_B<=0 |
        canonical$y_A>canonical$N_A | canonical$y_B>canonical$N_B)) stop('Invalid canonical counts.',call.=FALSE)

season_source <- do.call(rbind,lapply(target_seasons,function(s){
  q <- canonical[canonical$season==s,]
  nW <- max(q$weekF)
  data.frame(
    season=s,n_weeks=nrow(q),weekF_min=min(q$weekF),weekF_max=max(q$weekF),
    missing_week_count=length(setdiff(seq_len(nW),q$weekF)),
    denominator_regime=unique(q$denominator_regime),source_kind=unique(q$source_kind),
    A_B_den_equal_weeks=sum(q$N_A==q$N_B),
    max_abs_A_B_den_diff=max(abs(q$N_A-q$N_B)),
    stringsAsFactors=FALSE
  )
}))
write.csv(season_source,file.path(out_dir,'season_source_audit.csv'),row.names=FALSE)

long <- rbind(
  data.frame(season=canonical$season,weekF=canonical$weekF,type='A',y=canonical$y_A,N=canonical$N_A,p=canonical$p_A,
             denominator_regime=canonical$denominator_regime,source_kind=canonical$source_kind,stringsAsFactors=FALSE),
  data.frame(season=canonical$season,weekF=canonical$weekF,type='B',y=canonical$y_B,N=canonical$N_B,p=canonical$p_B,
             denominator_regime=canonical$denominator_regime,source_kind=canonical$source_kind,stringsAsFactors=FALSE)
)
long <- long[order(match(long$season,target_seasons),long$type,long$weekF),]

write.csv(canonical,file.path(out_dir,'canonical_ab_weekly_v3.csv'),row.names=FALSE)
write.csv(long,file.path(out_dir,'canonical_ab_long_v3.csv'),row.names=FALSE)
saveRDS(canonical,file.path(out_dir,'canonical_ab_weekly_v3.rds'))

# Vintage overlap audit: quantify how the September direct source differs from the
# older prepared source wherever both are available. This is descriptive only.
overlap <- merge(
  prepared[prepared$season %in% target_seasons,c('season','weekF','y','N','pos_flub')],
  weekly_hist[weekly_hist$season %in% target_seasons,c('season','weekF','A_pos','A_tests','B_pos','B_tests')],
  by=c('season','weekF'),all=FALSE,sort=TRUE
)
overlap$d_y_A <- overlap$A_pos-overlap$y
overlap$d_N_A <- overlap$A_tests-overlap$N
overlap$d_y_B <- overlap$B_pos-overlap$pos_flub
overlap$d_N_B_vs_shared <- overlap$B_tests-overlap$N
write.csv(overlap,file.path(out_dir,'source_overlap_revision_audit.csv'),row.names=FALSE)

overlap_summary <- do.call(rbind,lapply(split(overlap,overlap$season),function(q){
  data.frame(
    season=q$season[1],n_overlap=nrow(q),
    exact_A_pos=sum(q$d_y_A==0),max_abs_A_pos_delta=max(abs(q$d_y_A)),sum_A_pos_delta=sum(q$d_y_A),
    exact_A_den=sum(q$d_N_A==0),max_abs_A_den_delta=max(abs(q$d_N_A)),sum_A_den_delta=sum(q$d_N_A),
    exact_B_pos=sum(q$d_y_B==0),max_abs_B_pos_delta=max(abs(q$d_y_B)),sum_B_pos_delta=sum(q$d_y_B),
    exact_B_den_vs_shared=sum(q$d_N_B_vs_shared==0),max_abs_B_den_vs_shared=max(abs(q$d_N_B_vs_shared)),
    stringsAsFactors=FALSE
  )
}))
write.csv(overlap_summary,file.path(out_dir,'source_overlap_revision_summary.csv'),row.names=FALSE)

# Candidate reporting discontinuities: local weekly denominator spikes/drops.
discontinuity_rows <- list()
for (s in target_seasons) for (tp in c('A','B')) {
  q <- canonical[canonical$season==s,]
  N <- if(tp=='A') q$N_A else q$N_B
  if(length(N)<3) next
  for(i in 2:(length(N)-1L)) {
    local_ref <- sqrt(N[i-1L]*N[i+1L])
    ratio <- N[i]/local_ref
    if(is.finite(ratio) && (ratio<0.5 || ratio>2)) {
      discontinuity_rows[[length(discontinuity_rows)+1L]] <- data.frame(
        season=s,type=tp,weekF=q$weekF[i],N_prev=N[i-1L],N=N[i],N_next=N[i+1L],
        ratio_to_adjacent_geomean=ratio,stringsAsFactors=FALSE
      )
    }
  }
}
discontinuities <- if(length(discontinuity_rows)) do.call(rbind,discontinuity_rows) else data.frame(
  season=character(),type=character(),weekF=integer(),N_prev=numeric(),N=numeric(),N_next=numeric(),ratio_to_adjacent_geomean=numeric()
)
write.csv(discontinuities,file.path(out_dir,'candidate_reporting_discontinuities.csv'),row.names=FALSE)

# -----------------------------------------------------------------------------
# 3. Retrospective A/B timing geometry on the canonical panel.
# -----------------------------------------------------------------------------
a_ign <- read.csv(a_ignition_path,stringsAsFactors=FALSE)
a_ign <- a_ign[a_ign$season %in% target_seasons,c('season','ignition_week_decimal')]
if(nrow(a_ign)!=length(target_seasons)) stop('A ignition labels incomplete.',call.=FALSE)

ks <- c(5L,6L,8L,10L)
fit_rows <- list(); fit_cache <- list()
for(s in target_seasons) for(tp in c('A','B')) {
  z <- long[long$season==s & long$type==tp,c('season','weekF','y','N','p')]
  for(k in ks) {
    f <- retrospective_gam_peak_truth(z,season=s,k=k,grid_step=.01)
    fit_rows[[length(fit_rows)+1L]] <- data.frame(
      season=s,type=tp,k=k,peak_week_decimal=f$peak_week_decimal,
      peak_amplitude=max(f$grid$fitted_p),stringsAsFactors=FALSE
    )
    if(k==8L) fit_cache[[paste(s,tp,sep='|')]] <- f
  }
}
peak_sensitivity <- do.call(rbind,fit_rows)
write.csv(peak_sensitivity,file.path(out_dir,'peak_sensitivity_k5_k6_k8_k10.csv'),row.names=FALSE)

# Transfer A expert ignition to an excursion fraction, then use the median A
# fraction as a provisional B retrospective onset marker, matching prior B research.
excursion_fraction <- function(f,I){
  g <- f$grid; pre <- g[g$weekF<=f$peak_week_decimal,]
  base <- as.numeric(quantile(pre$fitted_p,.05))
  amp <- max(pre$fitted_p)
  pI <- approx(g$weekF,g$fitted_p,xout=I,rule=2)$y
  (pI-base)/(amp-base)
}
a_frac <- do.call(rbind,lapply(target_seasons,function(s){
  I <- a_ign$ignition_week_decimal[a_ign$season==s]
  f <- fit_cache[[paste(s,'A',sep='|')]]
  data.frame(season=s,A_expert_ignition=I,A_excursion_fraction=excursion_fraction(f,I),stringsAsFactors=FALSE)
}))
transfer_fraction <- median(a_frac$A_excursion_fraction,na.rm=TRUE)

last_upward_crossing_fit <- function(f,fraction){
  g <- f$grid; pre <- g[g$weekF<=f$peak_week_decimal,]
  base <- as.numeric(quantile(pre$fitted_p,.05))
  amp <- max(pre$fitted_p)
  thr <- base+fraction*(amp-base)
  above <- pre$fitted_p>=thr
  crossings <- which(above & c(TRUE,!head(above,-1L)))
  if(length(crossings)) pre$weekF[max(crossings)] else NA_real_
}

geom_rows <- list()
for(s in target_seasons){
  fa <- fit_cache[[paste(s,'A',sep='|')]]; fb <- fit_cache[[paste(s,'B',sep='|')]]
  Ia <- a_ign$ignition_week_decimal[a_ign$season==s]
  Ib <- last_upward_crossing_fit(fb,transfer_fraction)
  Pa <- fa$peak_week_decimal; Pb <- fb$peak_week_decimal
  ga <- fa$grid; gb <- fb$grid
  common <- merge(ga[,c('weekF','fitted_p')],gb[,c('weekF','fitted_p')],by='weekF',suffixes=c('_A','_B'))
  activity_max <- max(common$fitted_p_A+common$fitted_p_B)
  active <- common$weekF>=min(Ia,Ib) & common$weekF<=max(Pa,Pb)+8 &
            (common$fitted_p_A+common$fitted_p_B)>=0.10*activity_max
  q <- common[active,]
  bdom <- q$fitted_p_B>q$fitted_p_A
  first_dom <- NA_real_
  if(nrow(q)>=2){
    sustained <- bdom & c(tail(bdom,-1L),FALSE)
    if(any(sustained)) first_dom <- q$weekF[which(sustained)[1L]]
  }
  A_at_BI <- approx(ga$weekF,ga$fitted_p,xout=Ib,rule=2)$y
  A_amp <- max(ga$fitted_p); B_amp <- max(gb$fitted_p)
  geom_rows[[length(geom_rows)+1L]] <- data.frame(
    season=s,
    A_ignition=Ia,B_ignition_provisional=Ib,B_minus_A_ignition=Ib-Ia,
    A_peak=Pa,B_peak=Pb,B_minus_A_peak=Pb-Pa,
    B_ignition_minus_A_peak=Ib-Pa,
    A_fraction_of_peak_at_B_ignition=A_at_BI/A_amp,
    A_peak_amplitude=A_amp,B_peak_amplitude=B_amp,B_over_A_peak_amplitude=B_amp/A_amp,
    first_sustained_B_dominance_week=first_dom,
    B_dominance_minus_A_peak=first_dom-Pa,
    stringsAsFactors=FALSE
  )
}
geometry <- do.call(rbind,geom_rows)
write.csv(a_frac,file.path(out_dir,'a_ignition_excursion_fraction.csv'),row.names=FALSE)
write.csv(geometry,file.path(out_dir,'joint_timing_geometry_v3.csv'),row.names=FALSE)

summary_metrics <- data.frame(
  metric=c(
    'n_target_seasons','n_hist_type_specific_seasons','n_historical_shared_proxy_seasons',
    'B_provisional_ignition_later_than_A_n','median_B_minus_A_ignition_weeks',
    'B_peak_later_than_A_n','median_B_minus_A_peak_weeks',
    'B_ignition_after_A_peak_n','median_B_ignition_minus_A_peak_weeks',
    'median_A_fraction_of_peak_at_B_ignition','B_sustained_dominance_observed_n',
    'median_B_dominance_minus_A_peak_weeks','median_B_over_A_peak_amplitude',
    'provisional_B_transfer_excursion_fraction','candidate_reporting_discontinuities_n'
  ),
  value=c(
    nrow(season_source),sum(season_source$denominator_regime=='hist_type_specific'),
    sum(season_source$denominator_regime=='historical_shared_flu_test_proxy'),
    sum(geometry$B_minus_A_ignition>0,na.rm=TRUE),median(geometry$B_minus_A_ignition,na.rm=TRUE),
    sum(geometry$B_minus_A_peak>0,na.rm=TRUE),median(geometry$B_minus_A_peak,na.rm=TRUE),
    sum(geometry$B_ignition_minus_A_peak>0,na.rm=TRUE),median(geometry$B_ignition_minus_A_peak,na.rm=TRUE),
    median(geometry$A_fraction_of_peak_at_B_ignition,na.rm=TRUE),
    sum(is.finite(geometry$first_sustained_B_dominance_week)),
    median(geometry$B_dominance_minus_A_peak,na.rm=TRUE),
    median(geometry$B_over_A_peak_amplitude,na.rm=TRUE),transfer_fraction,nrow(discontinuities)
  ),stringsAsFactors=FALSE
)
write.csv(summary_metrics,file.path(out_dir,'summary_metrics.csv'),row.names=FALSE)

source_manifest <- data.frame(
  source=c('hist_snapshot','prepared_historical','A_expert_ignition_labels'),
  path=c(hist_path,prepared_path,a_ignition_path),
  sha256=c(sha256(hist_path),sha256(prepared_path),sha256(a_ignition_path)),
  stringsAsFactors=FALSE
)
write.csv(source_manifest,file.path(out_dir,'source_manifest.csv'),row.names=FALSE)

cat('v3 canonical rows:',nrow(canonical),' seasons:',length(unique(canonical$season)),'\n')
cat('type-specific seasons:',paste(full_hist_seasons,collapse=', '),'\n')
cat('shared-proxy seasons:',paste(setdiff(target_seasons,full_hist_seasons),collapse=', '),'\n')
cat('B provisional ignition later than A:',sum(geometry$B_minus_A_ignition>0,na.rm=TRUE),'/',nrow(geometry),'\n')
cat('median B-A ignition lag:',median(geometry$B_minus_A_ignition,na.rm=TRUE),'weeks\n')
cat('B peak later than A:',sum(geometry$B_minus_A_peak>0,na.rm=TRUE),'/',nrow(geometry),'\n')
cat('median B-A peak lag:',median(geometry$B_minus_A_peak,na.rm=TRUE),'weeks\n')
cat('B ignition after A peak:',sum(geometry$B_ignition_minus_A_peak>0,na.rm=TRUE),'/',nrow(geometry),'\n')
cat('candidate denominator discontinuities:',nrow(discontinuities),'\n')
