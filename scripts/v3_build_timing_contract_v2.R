#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

if (!requireNamespace('digest', quietly = TRUE)) stop('Package `digest` is required.')

A_LABELS <- 'artifacts/v3-joint-ab-ignition-review-v1/A_ignition_labels_v3.csv'
B_ACTIVITY <- 'artifacts/v3-a-rule-transfer-to-b-v1/B_window8_40_detection.rds'
PEAKS <- 'artifacts/v3-joint-ab-ignition-review-v1/peak_truth_v2_algorithm_ab.csv'
PANEL <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
OUT <- 'artifacts/v3-joint-timing-contract-v2'
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

inputs <- c(A_LABELS, B_ACTIVITY, PEAKS, PANEL)
if (!all(file.exists(inputs))) stop('Missing v3 timing-contract input(s).')

sha256_file <- function(path) digest::digest(file = path, algo = 'sha256', serialize = FALSE)

A <- read.csv(A_LABELS, check.names = FALSE)
B <- readRDS(B_ACTIVITY)$by_season
P <- read.csv(PEAKS, check.names = FALSE)
panel <- read.csv(PANEL, check.names = FALSE)

required_panel <- c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')
if (!all(required_panel %in% names(panel))) stop('Canonical panel schema mismatch.')
if (anyDuplicated(panel[c('season','weekF')])) stop('Canonical panel has duplicate season/weekF keys.')
if (anyNA(panel[required_panel])) stop('Canonical panel has missing required values.')

seasons <- unique(as.character(panel$season))
A$season <- as.character(A$season)
B$season <- as.character(B$season)
P$season <- as.character(P$season)
if (!setequal(seasons, A$season) || !setequal(seasons, B$season) || !setequal(seasons, P$season)) {
  stop('Timing inputs do not cover the same season set as the canonical panel.')
}

# B activity is an operational/exploratory marker, never gold ignition truth.
b_activity <- data.frame(
  season = B$season,
  B_activity_weekF = as.numeric(B$iWeek_hatF),
  B_activity_integer = as.numeric(B$iWeek_hat),
  B_activity_detected = !as.logical(B$detection_failed),
  B_activity_status = ifelse(as.logical(B$detection_failed), 'no_meaningful_activity', 'exploratory_transferred_A_rule'),
  B_activity_source = 'A_rule_transfer_w8_40',
  stringsAsFactors = FALSE
)

x <- Reduce(function(u,v) merge(u,v,by='season',all=TRUE,sort=FALSE), list(
  A[,c('season','A_ignition_weekF','source')],
  b_activity,
  P[,c('season','A_peak_weekF','A_peak_fitted_p','B_peak_weekF','B_peak_fitted_p','peak_method','grid_step')]
))
x <- x[match(seasons, x$season),]
names(x)[names(x) == 'source'] <- 'A_ignition_source'

# Explicit reviewed no-event policy: if the operational B activity detector never
# fires, do not force a retrospective B timing target for v3 M1-B training/scoring.
x$B_peak_status <- ifelse(x$B_activity_detected, 'retrospective_peak_truth', 'no_meaningful_peak')
x$B_peak_weekF_reviewed <- ifelse(x$B_activity_detected, x$B_peak_weekF, NA_real_)
x$B_peak_fitted_p_reviewed <- ifelse(x$B_activity_detected, x$B_peak_fitted_p, NA_real_)

truth <- data.frame(
  season = x$season,
  A_ignition_weekF = x$A_ignition_weekF,
  A_ignition_status = 'reviewed_truth',
  A_ignition_source = x$A_ignition_source,
  A_peak_weekF = x$A_peak_weekF,
  A_peak_fitted_p = x$A_peak_fitted_p,
  A_peak_status = 'retrospective_peak_truth',
  A_peak_source = x$peak_method,
  B_activity_weekF = x$B_activity_weekF,
  B_activity_integer = x$B_activity_integer,
  B_activity_detected = x$B_activity_detected,
  B_activity_status = x$B_activity_status,
  B_activity_source = x$B_activity_source,
  B_peak_weekF = x$B_peak_weekF_reviewed,
  B_peak_fitted_p = x$B_peak_fitted_p_reviewed,
  B_peak_status = x$B_peak_status,
  B_peak_source = ifelse(x$B_activity_detected, x$peak_method, 'none'),
  stringsAsFactors = FALSE
)

# Contract invariants.
if (any(!is.finite(truth$A_ignition_weekF)) || any(!is.finite(truth$A_peak_weekF))) stop('A timing truth must be finite.')
if (any(truth$A_ignition_weekF >= truth$A_peak_weekF)) stop('A ignition must precede A peak.')
if (any(is.finite(truth$B_peak_weekF) != truth$B_activity_detected)) stop('B peak presence must match reviewed B activity status.')
idxB <- which(truth$B_activity_detected)
if (any(truth$B_activity_weekF[idxB] >= truth$B_peak_weekF[idxB])) stop('Detected B activity marker must precede B peak.')
if (!identical(truth$B_activity_status[truth$season == '2018-19'], 'no_meaningful_activity')) stop('2018-19 B no-event review was not preserved.')
if (abs(truth$B_activity_weekF[truth$season == '2017-18'] - 23.9642295842807) > 1e-10) stop('2017-18 B activity marker must remain detector estimate 23.9642295842807.')

write.csv(truth, file.path(OUT, 'timing_contract_v3.csv'), row.names = FALSE)

geometry <- data.frame(
  season = truth$season,
  A_ignition = truth$A_ignition_weekF,
  A_peak = truth$A_peak_weekF,
  B_activity = truth$B_activity_weekF,
  B_peak = truth$B_peak_weekF,
  B_minus_A_activity = truth$B_activity_weekF - truth$A_ignition_weekF,
  B_minus_A_peak = truth$B_peak_weekF - truth$A_peak_weekF,
  B_activity_minus_A_peak = truth$B_activity_weekF - truth$A_peak_weekF,
  B_activity_to_peak = truth$B_peak_weekF - truth$B_activity_weekF,
  B_over_A_peak_amplitude = truth$B_peak_fitted_p / truth$A_peak_fitted_p,
  stringsAsFactors = FALSE
)
write.csv(geometry, file.path(OUT, 'timing_geometry_v3.csv'), row.names = FALSE)

regimes <- unique(panel[c('season','denominator_regime')])
regimes <- regimes[order(match(regimes$season,seasons)),]
write.csv(regimes, file.path(OUT, 'season_observation_regimes.csv'), row.names = FALSE)

manifest <- data.frame(
  role = c('A_reviewed_ignition','B_activity_detector','AB_peak_truth','canonical_panel'),
  path = inputs,
  sha256 = vapply(inputs, sha256_file, character(1)),
  stringsAsFactors = FALSE
)
write.csv(manifest, file.path(OUT, 'source_manifest.csv'), row.names = FALSE)

contract_meta <- data.frame(
  key = c('contract_version','B_activity_semantics','A_window','B_window','peak_algorithm','n_seasons','n_B_timing_seasons','timing_contract_sha256'),
  value = c(
    'v3-timing-contract-v2',
    'exploratory_activity_marker_not_gold_ignition',
    '12-26',
    '8-40',
    'retrospective-gam-peak-v1-k8',
    nrow(truth),
    sum(truth$B_activity_detected),
    sha256_file(file.path(OUT,'timing_contract_v3.csv'))
  ),
  stringsAsFactors = FALSE
)
write.csv(contract_meta, file.path(OUT, 'contract_metadata.csv'), row.names = FALSE)

cat('Wrote reproducible v3 timing contract:', OUT, '\n')
cat('Seasons:', nrow(truth), '| B timing seasons:', sum(truth$B_activity_detected), '\n')
cat('2017-18 B activity:', format(truth$B_activity_weekF[truth$season=='2017-18'], digits=10), '\n')
cat('2018-19 B status:', truth$B_activity_status[truth$season=='2018-19'], '\n')
