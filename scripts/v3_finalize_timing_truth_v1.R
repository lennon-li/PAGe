#!/usr/bin/env Rscript

options(stringsAsFactors=FALSE)

A_path <- 'artifacts/v3-joint-ab-ignition-review-v1/A_ignition_labels_v3.csv'
B_path <- 'artifacts/v3-a-rule-transfer-to-b-v1/B_timing_review_v1.csv'
P_path <- 'artifacts/v3-joint-ab-ignition-review-v1/peak_truth_v2_algorithm_ab.csv'
O_dir <- 'artifacts/v3-joint-timing-truth-v1'
dir.create(O_dir,recursive=TRUE,showWarnings=FALSE)

A <- read.csv(A_path,check.names=FALSE)
B <- read.csv(B_path,check.names=FALSE)
P <- read.csv(P_path,check.names=FALSE)

x <- Reduce(function(u,v) merge(u,v,by='season',all=TRUE,sort=FALSE),list(A,B,P))
ord <- A$season
x <- x[match(ord,x$season),]

# Explicitly suppress B peak where review says no B peak.
x$B_peak_weekF_reviewed <- ifelse(x$B_peak_status=='none',NA_real_,x$B_peak_weekF)
x$B_peak_fitted_p_reviewed <- ifelse(x$B_peak_status=='none',NA_real_,x$B_peak_fitted_p)

# Canonical source/status fields.
x$A_ignition_status <- 'reviewed'
x$A_peak_status <- 'v2_peak_algorithm'
x$B_ignition_source <- x$source.y
x$A_ignition_source <- x$source.x
x$A_peak_source <- x$peak_method
x$B_peak_source <- ifelse(x$B_peak_status=='none','none',x$peak_method)

truth <- x[,c(
  'season',
  'A_ignition_weekF','A_ignition_status','A_ignition_source',
  'B_ignition_weekF','B_ignition_status','B_ignition_source',
  'A_peak_weekF','A_peak_fitted_p','A_peak_status','A_peak_source',
  'B_peak_weekF_reviewed','B_peak_fitted_p_reviewed','B_peak_status','B_peak_source'
)]
write.csv(truth,file.path(O_dir,'timing_truth_v3_v1.csv'),row.names=FALSE)

# Geometry from reviewed timing truth.
g <- data.frame(
  season=truth$season,
  A_ignition=truth$A_ignition_weekF,
  B_ignition=truth$B_ignition_weekF,
  A_peak=truth$A_peak_weekF,
  B_peak=truth$B_peak_weekF_reviewed,
  A_peak_p=truth$A_peak_fitted_p,
  B_peak_p=truth$B_peak_fitted_p_reviewed,
  stringsAsFactors=FALSE
)
g$B_minus_A_ignition <- g$B_ignition-g$A_ignition
g$A_peak_minus_A_ignition <- g$A_peak-g$A_ignition
g$B_peak_minus_B_ignition <- g$B_peak-g$B_ignition
g$B_minus_A_peak <- g$B_peak-g$A_peak
g$B_ignition_minus_A_peak <- g$B_ignition-g$A_peak
g$B_over_A_peak_amplitude <- g$B_peak_p/g$A_peak_p

# Simple review flags only; do not alter truth automatically.
g$flag_B_late_ignition <- is.finite(g$B_ignition) & g$B_ignition >= 38
g$flag_B_short_ignition_to_peak <- is.finite(g$B_peak_minus_B_ignition) & g$B_peak_minus_B_ignition < 3
g$flag_B_weak_peak <- is.finite(g$B_peak_p) & g$B_peak_p < 0.02
g$flag_any_review <- g$flag_B_late_ignition | g$flag_B_short_ignition_to_peak | g$flag_B_weak_peak
write.csv(g,file.path(O_dir,'joint_timing_geometry_reviewed_v3_v1.csv'),row.names=FALSE)

summary <- data.frame(
  metric=c(
    'n_seasons',
    'n_B_ignition',
    'n_B_peak',
    'median_B_minus_A_ignition',
    'median_B_minus_A_peak',
    'median_B_peak_minus_B_ignition',
    'median_B_over_A_peak_amplitude',
    'n_flagged_for_review'
  ),
  value=c(
    nrow(g),
    sum(is.finite(g$B_ignition)),
    sum(is.finite(g$B_peak)),
    median(g$B_minus_A_ignition,na.rm=TRUE),
    median(g$B_minus_A_peak,na.rm=TRUE),
    median(g$B_peak_minus_B_ignition,na.rm=TRUE),
    median(g$B_over_A_peak_amplitude,na.rm=TRUE),
    sum(g$flag_any_review,na.rm=TRUE)
  )
)
write.csv(summary,file.path(O_dir,'summary_metrics.csv'),row.names=FALSE)

cat('Wrote timing truth and geometry to',O_dir,'\n')
cat('\nFlagged seasons:\n')
print(g[g$flag_any_review,c('season','B_ignition','B_peak','B_peak_minus_B_ignition','B_peak_p','flag_B_late_ignition','flag_B_short_ignition_to_peak','flag_B_weak_peak')],row.names=FALSE,digits=5)
cat('\nSummary:\n')
print(summary,row.names=FALSE,digits=5)
