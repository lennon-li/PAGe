#!/usr/bin/env Rscript

source('PAGe/R/data_contract.R')
source('PAGe/R/season_calendar.R')
source('PAGe/R/getCurrentD.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')

campaign_path <- 'artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds'
historical_path <- '../PAGe/results/manuscript/all-season-holdout-prep-20260914-r2/prepared_data_all_seasons.rds'
orvt_path <- '../PAGe/results/audit/ontario_orvt_lab_testing_2024-25_2025-26.csv'
out_dir <- 'artifacts/m2-v2-flu-ab-geometry-v1'
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

stopifnot(file.exists(campaign_path), file.exists(historical_path), file.exists(orvt_path))
campaign <- readRDS(campaign_path)
historical <- readRDS(historical_path)
target_seasons <- sort(unique(as.character(campaign$season)))
expected_target <- c('2012-13','2013-14','2014-15','2016-17','2017-18','2018-19',
                     '2019-20','2022-23','2023-24','2024-25','2025-26')
if (!identical(target_seasons, expected_target)) {
  stop('Unexpected campaign season universe: ', paste(target_seasons, collapse=', '), call.=FALSE)
}

req_hist <- c('season','weekF','y','N','p','pos_flub','fluBPercentPositive')
miss_hist <- setdiff(req_hist, names(historical))
if (length(miss_hist)) stop('Historical prepared data missing: ', paste(miss_hist, collapse=', '), call.=FALSE)

# First ten redesign seasons use the manuscript-prepared historical source. Its
# A rows match the current campaign exactly, while carrying historical B counts.
legacy_seasons <- setdiff(target_seasons, '2025-26')
h0 <- historical[historical$season %in% legacy_seasons, req_hist, drop=FALSE]
c0 <- campaign[campaign$season %in% legacy_seasons, c('season','weekF','y','N','p'), drop=FALSE]
rec <- merge(c0, h0, by=c('season','weekF'), suffixes=c('_campaign','_historical'), all=TRUE)
if (anyNA(rec$y_campaign) || anyNA(rec$y_historical) ||
    any(rec$y_campaign != rec$y_historical) || any(rec$N_campaign != rec$N_historical) ||
    any(abs(rec$p_campaign - rec$p_historical) > 1e-12)) {
  stop('Historical A source does not exactly reconcile to the current campaign for legacy seasons.', call.=FALSE)
}

legacy <- merge(c0,
  h0[,c('season','weekF','pos_flub','fluBPercentPositive')],
  by=c('season','weekF'), all.x=TRUE, sort=FALSE)
if (anyNA(legacy$pos_flub)) stop('Missing historical B counts in target legacy seasons.', call.=FALSE)
legacy$y_A <- as.numeric(legacy$y)
legacy$N_A <- as.numeric(legacy$N)
legacy$p_A <- as.numeric(legacy$p)
legacy$y_B <- as.numeric(legacy$pos_flub)
legacy$N_B <- as.numeric(legacy$N)  # historical shared influenza-test denominator/proxy
legacy$p_B <- legacy$y_B / legacy$N_B
legacy$p_B_reported <- as.numeric(legacy$fluBPercentPositive) / 100
legacy$denominator_regime <- 'historical_shared_flu_test_proxy'
legacy$source_kind <- 'manuscript_prepared_historical'
legacy <- legacy[,c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','p_B_reported',
                    'denominator_regime','source_kind')]

# 2025-26 comes from the frozen ORVT audit feed, with type-specific denominators.
a25 <- getCurrentD(data=orvt_path, virus='Influenza A', season='2025-26', include_predecessor=FALSE)
b25 <- getCurrentD(data=orvt_path, virus='Influenza B', season='2025-26', include_predecessor=FALSE)
modern <- merge(
  a25[,c('weekF','N','y','p')], b25[,c('weekF','N','y','p')],
  by='weekF', suffixes=c('_A','_B'), all=TRUE, sort=TRUE
)
if (nrow(modern) != 53L || anyNA(modern)) stop('2025-26 ORVT A/B reconstruction is incomplete.', call.=FALSE)
modern$season <- '2025-26'
modern$p_B_reported <- modern$p_B
modern$denominator_regime <- 'orvt_type_specific'
modern$source_kind <- 'orvt_audit_feed'
modern <- modern[,c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','p_B_reported',
                    'denominator_regime','source_kind')]

ab <- rbind(legacy, modern)
ab <- ab[order(match(ab$season,target_seasons),ab$weekF),]
rownames(ab) <- NULL
if (nrow(ab) != nrow(campaign)) stop('A/B reconstruction row count does not match campaign.', call.=FALSE)
if (anyDuplicated(ab[,c('season','weekF')])) stop('Duplicate season/week rows in A/B reconstruction.', call.=FALSE)
if (any(ab$y_A < 0 | ab$y_B < 0 | ab$N_A <= 0 | ab$N_B <= 0 |
        ab$y_A > ab$N_A | ab$y_B > ab$N_B)) stop('Invalid A/B counts.', call.=FALSE)

# Reconcile 2025-26 A with the current campaign exactly.
c25 <- campaign[campaign$season=='2025-26',c('weekF','y','N','p')]
z25 <- merge(c25,modern[,c('weekF','y_A','N_A','p_A')],by='weekF')
if (nrow(z25) != 53L || max(abs(z25$p-z25$p_A)) > 1e-12 ||
    any(z25$y != z25$y_A) || any(z25$N != z25$N_A)) {
  stop('2025-26 ORVT A does not exactly reconcile to campaign.', call.=FALSE)
}

# Quantify the historical rounded B percentage discrepancy.
legacy_b_rounding_max_abs <- max(abs(legacy$p_B - legacy$p_B_reported), na.rm=TRUE)

# ORVT 2024-25 overlap sensitivity: B counts should agree, but modern B denominator is type-specific.
a24 <- getCurrentD(data=orvt_path, virus='Influenza A', season='2024-25', include_predecessor=FALSE)
b24 <- getCurrentD(data=orvt_path, virus='Influenza B', season='2024-25', include_predecessor=FALSE)
h24 <- historical[historical$season=='2024-25',c('weekF','N','y','pos_flub','fluBPercentPositive')]
ov24 <- Reduce(function(x,y) merge(x,y,by='weekF'), list(
  h24,
  a24[,c('weekF','N','y','p')],
  b24[,c('weekF','N','y','p')]
))
names(ov24) <- c('weekF','N_historical','yA_historical','yB_historical','pB_reported_historical',
                 'N_A_orvt','yA_orvt','p_A_orvt','N_B_orvt','yB_orvt','p_B_orvt')
ov24$pB_reported_historical <- ov24$pB_reported_historical/100
ov24$A_denominator_diff <- ov24$N_A_orvt - ov24$N_historical
ov24$B_vs_A_denominator_diff_orvt <- ov24$N_B_orvt - ov24$N_A_orvt
ov24$B_count_diff <- ov24$yB_orvt - ov24$yB_historical
ov24$B_p_diff_reported_vs_orvt <- ov24$p_B_orvt - ov24$pB_reported_historical

# Long type-specific representation used for retrospective geometry.
long <- rbind(
  data.frame(season=ab$season,weekF=ab$weekF,type='A',y=ab$y_A,N=ab$N_A,p=ab$p_A,
             denominator_regime=ab$denominator_regime,stringsAsFactors=FALSE),
  data.frame(season=ab$season,weekF=ab$weekF,type='B',y=ab$y_B,N=ab$N_B,p=ab$p_B,
             denominator_regime=ab$denominator_regime,stringsAsFactors=FALSE)
)
long <- long[order(match(long$season,target_seasons),long$type,long$weekF),]

k_values <- c(5L,6L,8L,10L)
peak_sensitivity <- list()
fit_cache <- list()
for (s in target_seasons) for (tp in c('A','B')) {
  z <- long[long$season==s & long$type==tp,c('season','weekF','y','N','p')]
  for (k in k_values) {
    f <- retrospective_gam_peak_truth(z, season=s, k=k, grid_step=.01)
    peak_sensitivity[[length(peak_sensitivity)+1L]] <- data.frame(
      season=s,type=tp,k=k,peak_week_decimal=f$peak_week_decimal,
      peak_fitted_p=max(f$grid$fitted_p),stringsAsFactors=FALSE
    )
    if (k==8L) fit_cache[[paste(s,tp,sep='|')]] <- f
  }
}
peak_sensitivity <- do.call(rbind,peak_sensitivity)
peak_ranges <- do.call(rbind,lapply(split(peak_sensitivity,interaction(peak_sensitivity$season,peak_sensitivity$type,drop=TRUE)),function(z){
  data.frame(season=z$season[1],type=z$type[1],peak_low=min(z$peak_week_decimal),
             peak_high=max(z$peak_week_decimal),peak_range=max(z$peak_week_decimal)-min(z$peak_week_decimal),
             peak_ambiguous=(max(z$peak_week_decimal)-min(z$peak_week_decimal))>1,
             stringsAsFactors=FALSE)
}))

# k=8 geometry.
halfmax_geometry <- function(g, peak, amp) {
  pre <- g[g$weekF <= peak,]
  post <- g[g$weekF >= peak,]
  pre_start <- if (any(pre$fitted_p >= .5*amp)) min(pre$weekF[pre$fitted_p >= .5*amp]) else NA_real_
  post_end <- if (any(post$fitted_p >= .5*amp)) max(post$weekF[post$fitted_p >= .5*amp]) else NA_real_
  c(half_rise=peak-pre_start, half_decline=post_end-peak, half_width=post_end-pre_start)
}
geometry <- list()
shape_rows <- list()
tau_grid <- seq(-8,8,by=.25)
for (s in target_seasons) for (tp in c('A','B')) {
  f <- fit_cache[[paste(s,tp,sep='|')]]
  g <- f$grid
  peak <- f$peak_week_decimal
  amp <- max(g$fitted_p)
  hm <- halfmax_geometry(g,peak,amp)
  geometry[[length(geometry)+1L]] <- data.frame(
    season=s,type=tp,peak_week_decimal=peak,peak_amplitude=amp,
    half_rise=unname(hm['half_rise']),half_decline=unname(hm['half_decline']),
    half_width=unname(hm['half_width']),stringsAsFactors=FALSE
  )
  vals <- approx(g$weekF-peak,g$fitted_p/amp,xout=tau_grid,rule=1)$y
  shape_rows[[length(shape_rows)+1L]] <- data.frame(season=s,type=tp,tau=tau_grid,p_norm=vals)
}
geometry <- do.call(rbind,geometry)
shape_grid <- do.call(rbind,shape_rows)

Ageom <- geometry[geometry$type=='A',]
Bgeom <- geometry[geometry$type=='B',]
season_geometry <- merge(Ageom,Bgeom,by='season',suffixes=c('_A','_B'))
season_geometry$B_minus_A_peak <- season_geometry$peak_week_decimal_B-season_geometry$peak_week_decimal_A
season_geometry$peak_amplitude_ratio_B_over_A <- season_geometry$peak_amplitude_B/season_geometry$peak_amplitude_A
season_geometry$half_width_ratio_B_over_A <- season_geometry$half_width_B/season_geometry$half_width_A

shape_distance <- do.call(rbind,lapply(target_seasons,function(s){
  a <- shape_grid[shape_grid$season==s & shape_grid$type=='A',]
  b <- shape_grid[shape_grid$season==s & shape_grid$type=='B',]
  ok <- is.finite(a$p_norm) & is.finite(b$p_norm)
  data.frame(season=s,n_tau=sum(ok),
             normalized_shape_rmse=sqrt(mean((a$p_norm[ok]-b$p_norm[ok])^2)),
             normalized_shape_correlation=cor(a$p_norm[ok],b$p_norm[ok]),
             stringsAsFactors=FALSE)
}))
season_geometry <- merge(season_geometry,shape_distance,by='season',sort=FALSE)
season_geometry <- season_geometry[match(target_seasons,season_geometry$season),]

pooled_shape <- aggregate(p_norm~type+tau,shape_grid,median,na.rm=TRUE)
pa <- pooled_shape[pooled_shape$type=='A',]
pb <- pooled_shape[pooled_shape$type=='B',]
okp <- is.finite(pa$p_norm) & is.finite(pb$p_norm)
pooled_shape_rmse <- sqrt(mean((pa$p_norm[okp]-pb$p_norm[okp])^2))
pooled_shape_corr <- cor(pa$p_norm[okp],pb$p_norm[okp])

summary_metrics <- data.frame(
  metric=c(
    'n_target_seasons','n_B_peak_later_by_gt1w','median_B_minus_A_peak_weeks','mean_B_minus_A_peak_weeks',
    'median_B_over_A_peak_amplitude_ratio','median_A_halfmax_width','median_B_halfmax_width',
    'median_within_season_normalized_shape_rmse','median_within_season_normalized_shape_correlation',
    'pooled_median_normalized_shape_rmse','pooled_median_normalized_shape_correlation',
    'n_A_peak_ambiguous_k_range_gt1','n_B_peak_ambiguous_k_range_gt1',
    'historical_B_reported_vs_count_ratio_max_abs','orvt_2024_A_B_denominator_max_abs_diff',
    'orvt_2024_historical_vs_orvt_B_count_max_abs_diff','orvt_2024_reported_vs_orvt_B_p_max_abs_diff'
  ),
  value=c(
    length(target_seasons),sum(season_geometry$B_minus_A_peak>1),median(season_geometry$B_minus_A_peak),
    mean(season_geometry$B_minus_A_peak),median(season_geometry$peak_amplitude_ratio_B_over_A),
    median(season_geometry$half_width_A,na.rm=TRUE),median(season_geometry$half_width_B,na.rm=TRUE),
    median(season_geometry$normalized_shape_rmse),median(season_geometry$normalized_shape_correlation),
    pooled_shape_rmse,pooled_shape_corr,
    sum(peak_ranges$type=='A' & peak_ranges$peak_ambiguous),sum(peak_ranges$type=='B' & peak_ranges$peak_ambiguous),
    legacy_b_rounding_max_abs,max(abs(ov24$N_A_orvt-ov24$N_B_orvt)),max(abs(ov24$B_count_diff)),
    max(abs(ov24$B_p_diff_reported_vs_orvt))
  ), stringsAsFactors=FALSE
)

source_manifest <- data.frame(
  source=c('campaign','historical_prepared','orvt_audit'),
  path=c(campaign_path,historical_path,orvt_path),
  sha256=c(digest::digest(file=campaign_path,algo='sha256'),
           digest::digest(file=historical_path,algo='sha256'),
           digest::digest(file=orvt_path,algo='sha256')),
  stringsAsFactors=FALSE
)

write.csv(ab,file.path(out_dir,'flu_ab_weekly_v1.csv'),row.names=FALSE)
write.csv(long,file.path(out_dir,'flu_ab_long_v1.csv'),row.names=FALSE)
write.csv(source_manifest,file.path(out_dir,'source_manifest.csv'),row.names=FALSE)
write.csv(ov24,file.path(out_dir,'orvt_2024_denominator_overlap_audit.csv'),row.names=FALSE)
write.csv(peak_sensitivity,file.path(out_dir,'peak_sensitivity_k5_k6_k8_k10.csv'),row.names=FALSE)
write.csv(peak_ranges,file.path(out_dir,'peak_sensitivity_ranges.csv'),row.names=FALSE)
write.csv(geometry,file.path(out_dir,'type_geometry_k8.csv'),row.names=FALSE)
write.csv(season_geometry,file.path(out_dir,'season_ab_geometry_k8.csv'),row.names=FALSE)
write.csv(shape_grid,file.path(out_dir,'peak_aligned_normalized_shape_grid.csv'),row.names=FALSE)
write.csv(pooled_shape,file.path(out_dir,'peak_aligned_normalized_shape_medians.csv'),row.names=FALSE)
write.csv(summary_metrics,file.path(out_dir,'summary_metrics.csv'),row.names=FALSE)
saveRDS(ab,file.path(out_dir,'flu_ab_weekly_v1.rds'))

cat('A/B reconstruction rows:',nrow(ab),' seasons:',length(target_seasons),'\n')
cat('Median B-A peak lag:',median(season_geometry$B_minus_A_peak),'weeks; B >1w later in',sum(season_geometry$B_minus_A_peak>1),'of',nrow(season_geometry),'seasons\n')
cat('Median B/A peak amplitude ratio:',median(season_geometry$peak_amplitude_ratio_B_over_A),'\n')
cat('Median within-season normalized shape correlation:',median(season_geometry$normalized_shape_correlation),'\n')
cat('Pooled normalized median-curve correlation:',pooled_shape_corr,'\n')
cat('A ambiguous peaks:',sum(peak_ranges$type=='A' & peak_ranges$peak_ambiguous),'; B ambiguous peaks:',sum(peak_ranges$type=='B' & peak_ranges$peak_ambiguous),'\n')
