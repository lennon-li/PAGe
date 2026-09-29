#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

if (!requireNamespace('digest', quietly = TRUE)) stop('Package `digest` is required.')

A_LABELS <- 'artifacts/v3-joint-ab-ignition-review-v1/A_ignition_labels_v3.csv'
B_ACTIVITY <- 'artifacts/v3-a-rule-transfer-to-b-v1/B_window8_40_detection.rds'
PEAKS <- 'artifacts/v3-joint-ab-ignition-review-v1/peak_truth_v2_algorithm_ab.csv'
PANEL <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
POLICY_SOURCE <- 'governance/v3_b_season_policy_v1.csv'
GENERATOR_SCRIPT <- 'scripts/v3_build_timing_contract_v3.R'

OUT <- 'artifacts/v3-joint-timing-contract-v3'
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

inputs <- c(A_LABELS, B_ACTIVITY, PEAKS, PANEL, POLICY_SOURCE)
if (!all(file.exists(inputs))) stop('Missing v3 timing-contract input(s).')

sha256_file <- function(path) digest::digest(file = path, algo = 'sha256', serialize = FALSE)

A <- read.csv(A_LABELS, check.names = FALSE)
B <- readRDS(B_ACTIVITY)$by_season
P <- read.csv(PEAKS, check.names = FALSE)
panel <- read.csv(PANEL, check.names = FALSE)
pol <- read.csv(POLICY_SOURCE, check.names = FALSE)

# Schema validation for inputs
required_panel <- c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')
if (!all(required_panel %in% names(panel))) stop('Canonical panel schema mismatch.')
if (anyDuplicated(panel[c('season','weekF')])) stop('Canonical panel has duplicate season/weekF keys.')
if (anyNA(panel[required_panel])) stop('Canonical panel has missing required values.')

required_policy <- c('season','M1_B_peak_eligible','M1_B_training_eligible','M1_B_scoring_eligible','M2_B_state_eligible','M2_B_scoring_eligible','M2_B_timing_eligible','exclusion_reason','review_status')
if (!all(required_policy %in% names(pol))) stop('Policy source schema mismatch.')

seasons <- unique(as.character(panel$season))
A$season <- as.character(A$season)
B$season <- as.character(B$season)
P$season <- as.character(P$season)
pol$season <- as.character(pol$season)

# Strict exhaustive and unique season validation
if (anyDuplicated(pol$season) > 0L) stop('Policy source has duplicate seasons.')
if (anyDuplicated(A$season) > 0L) stop('A labels input has duplicate seasons.')
if (anyDuplicated(B$season) > 0L) stop('B activity input has duplicate seasons.')
if (anyDuplicated(P$season) > 0L) stop('Peak truth input has duplicate seasons.')

if (!setequal(seasons, A$season) || length(A$season) != length(seasons) ||
    !setequal(seasons, B$season) || length(B$season) != length(seasons) ||
    !setequal(seasons, P$season) || length(P$season) != length(seasons) ||
    !setequal(seasons, pol$season) || length(pol$season) != length(seasons)) {
  stop('Inputs and policy do not cover the exact exhaustive canonical season set.')
}

# Ensure boolean fields in policy are strict logical TRUE/FALSE strings
pol_bool_cols <- c('M1_B_peak_eligible','M1_B_training_eligible','M1_B_scoring_eligible','M2_B_state_eligible','M2_B_scoring_eligible','M2_B_timing_eligible')
for (col in pol_bool_cols) {
  raw_vals <- as.character(pol[[col]])
  if (!all(raw_vals %in% c('TRUE', 'FALSE'))) {
    stop('Policy column ', col, ' contains values other than strict TRUE/FALSE: ', paste(unique(setdiff(raw_vals, c('TRUE', 'FALSE'))), collapse=', '))
  }
  pol[[col]] <- (raw_vals == 'TRUE')
}

# Allowed review statuses and exclusion-reason invariants
allowed_statuses <- c('reviewed_eligible', 'reviewed_no_timing_event', 'reviewed_pandemic_transition')
if (!all(pol$review_status %in% allowed_statuses)) {
  stop('Policy review_status contains invalid status: ', paste(unique(setdiff(pol$review_status, allowed_statuses)), collapse=', '))
}

for (i in seq_len(nrow(pol))) {
  row <- pol[i, ]
  s <- row$season
  if (s == '2018-19') {
    if (row$review_status != 'reviewed_no_timing_event' || row$exclusion_reason != 'no_meaningful_B_activity_or_peak') {
      stop('2018-19 review_status or exclusion_reason violates invariant.')
    }
  } else if (s == '2019-20') {
    if (row$review_status != 'reviewed_pandemic_transition' || row$exclusion_reason != 'pandemic_transition') {
      stop('2019-20 review_status or exclusion_reason violates invariant.')
    }
  } else {
    if (row$review_status != 'reviewed_eligible') {
      stop('Eligible season ', s, ' review_status violates invariant: ', row$review_status)
    }
    if (!is.na(row$exclusion_reason) && nzchar(trimws(row$exclusion_reason))) {
      stop('Eligible season ', s, ' must not have exclusion_reason.')
    }
  }
}

# Policy specific invariants:
# 2018-19: M1_B_peak_eligible=F, M1_B_training_eligible=F, M2_B_state_eligible=T, M2_B_timing_eligible=F
pol_2018 <- pol[pol$season == '2018-19', ]
if (nrow(pol_2018) != 1L || pol_2018$M1_B_peak_eligible || pol_2018$M1_B_training_eligible || pol_2018$M1_B_scoring_eligible || !pol_2018$M2_B_state_eligible || !pol_2018$M2_B_scoring_eligible || pol_2018$M2_B_timing_eligible) {
  stop('2018-19 policy values violate specification.')
}

# 2019-20: pandemic-transition exclusion; all B modeling/scoring false
pol_2019 <- pol[pol$season == '2019-20', ]
if (nrow(pol_2019) != 1L || pol_2019$M1_B_peak_eligible || pol_2019$M1_B_training_eligible || pol_2019$M1_B_scoring_eligible || pol_2019$M2_B_state_eligible || pol_2019$M2_B_scoring_eligible || pol_2019$M2_B_timing_eligible) {
  stop('2019-20 policy values violate specification.')
}

# Construct timing truth
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

# Contract invariants
if (any(!is.finite(truth$A_ignition_weekF)) || any(!is.finite(truth$A_peak_weekF))) stop('A timing truth must be finite.')
if (any(truth$A_ignition_weekF >= truth$A_peak_weekF)) stop('A ignition must precede A peak.')
if (any(is.finite(truth$B_peak_weekF) != truth$B_activity_detected)) stop('B peak presence must match reviewed B activity status.')
idxB <- which(truth$B_activity_detected)
if (any(truth$B_activity_weekF[idxB] >= truth$B_peak_weekF[idxB])) stop('Detected B activity marker must precede B peak.')
if (!identical(truth$B_activity_status[truth$season == '2018-19'], 'no_meaningful_activity')) stop('2018-19 B no-event review was not preserved.')
if (abs(truth$B_activity_weekF[truth$season == '2017-18'] - 23.9642295842807) > 1e-10) stop('2017-18 B activity marker must remain detector estimate 23.9642295842807.')

# Build modeling eligibility v3 from canonical seasons + policy source
# Explicit fields covering M1 and M2 training/scoring/timing eligibility
pol_ordered <- pol[match(seasons, pol$season), ]
eligibility <- data.frame(
  season = pol_ordered$season,
  M1_A_eligible = TRUE,
  M1_B_peak_eligible = pol_ordered$M1_B_peak_eligible,
  M1_B_training_eligible = pol_ordered$M1_B_training_eligible,
  M1_B_scoring_eligible = pol_ordered$M1_B_scoring_eligible,
  M2_B_state_eligible = pol_ordered$M2_B_state_eligible,
  M2_B_scoring_eligible = pol_ordered$M2_B_scoring_eligible,
  M2_B_timing_eligible = pol_ordered$M2_B_timing_eligible,
  exclusion_reason = pol_ordered$exclusion_reason,
  review_status = pol_ordered$review_status,
  stringsAsFactors = FALSE
)

# Invariant: finite timing truth satisfies component-specific invariants
# Inactive 2018-19 has no finite B peak
if (is.finite(truth$B_peak_weekF[truth$season == '2018-19'])) stop('2018-19 must not have finite B peak.')
# Eligible M1-B seasons must have finite B peak
m1_b_train_seasons <- eligibility$season[eligibility$M1_B_training_eligible]
if (!all(is.finite(truth$B_peak_weekF[match(m1_b_train_seasons, truth$season)]))) {
  stop('All M1-B training eligible seasons must have finite B peak truth.')
}
# 2019-20 must be ineligible in policy registry
if (eligibility$M1_B_training_eligible[eligibility$season == '2019-20'] || eligibility$M1_B_scoring_eligible[eligibility$season == '2019-20'] ||
    eligibility$M2_B_state_eligible[eligibility$season == '2019-20'] || eligibility$M2_B_scoring_eligible[eligibility$season == '2019-20']) {
  stop('2019-20 must be ineligible.')
}

# Write files
TIMING_CSV <- file.path(OUT, 'timing_contract_v3.csv')
ELIG_CSV <- file.path(OUT, 'modeling_eligibility_v3.csv')
GEOM_CSV <- file.path(OUT, 'timing_geometry_v3.csv')
REGIMES_CSV <- file.path(OUT, 'season_observation_regimes.csv')
MANIFEST_CSV <- file.path(OUT, 'source_manifest.csv')
META_CSV <- file.path(OUT, 'contract_metadata.csv')

write.csv(truth, TIMING_CSV, row.names = FALSE)
write.csv(eligibility, ELIG_CSV, row.names = FALSE)

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
write.csv(geometry, GEOM_CSV, row.names = FALSE)

regimes <- unique(panel[c('season','denominator_regime')])
regimes <- regimes[order(match(regimes$season,seasons)),]
write.csv(regimes, REGIMES_CSV, row.names = FALSE)

contract_meta <- data.frame(
  key = c(
    'contract_version',
    'B_activity_semantics',
    'A_window',
    'B_window',
    'peak_algorithm',
    'n_seasons',
    'n_B_timing_seasons',
    'timing_contract_sha256',
    'modeling_eligibility_sha256',
    'policy_source_sha256'
  ),
  value = c(
    'v3-timing-contract-v3',
    'exploratory_activity_marker_not_gold_ignition',
    '12-26',
    '8-40',
    'retrospective-gam-peak-v1-k8',
    nrow(truth),
    sum(truth$B_activity_detected),
    sha256_file(TIMING_CSV),
    sha256_file(ELIG_CSV),
    sha256_file(POLICY_SOURCE)
  ),
  stringsAsFactors = FALSE
)
write.csv(contract_meta, META_CSV, row.names = FALSE)

# Source manifest binds generator, inputs, and generated outputs (excluding source_manifest.csv itself)
manifest_entries <- rbind(
  data.frame(
    role = 'generator_script',
    path = GENERATOR_SCRIPT,
    sha256 = sha256_file(GENERATOR_SCRIPT),
    stringsAsFactors = FALSE
  ),
  data.frame(
    role = c('A_reviewed_ignition','B_activity_detector','AB_peak_truth','canonical_panel','B_season_policy_source'),
    path = inputs,
    sha256 = vapply(inputs, sha256_file, character(1)),
    stringsAsFactors = FALSE
  ),
  data.frame(
    role = c('timing_contract_v3','modeling_eligibility_v3','timing_geometry_v3','season_observation_regimes','contract_metadata'),
    path = c(TIMING_CSV, ELIG_CSV, GEOM_CSV, REGIMES_CSV, META_CSV),
    sha256 = c(
      sha256_file(TIMING_CSV),
      sha256_file(ELIG_CSV),
      sha256_file(GEOM_CSV),
      sha256_file(REGIMES_CSV),
      sha256_file(META_CSV)
    ),
    stringsAsFactors = FALSE
  )
)
write.csv(manifest_entries, MANIFEST_CSV, row.names = FALSE)

cat('Wrote reproducible v3 timing contract v3:', OUT, '\n')
cat('Seasons:', nrow(truth), '| B timing seasons:', sum(truth$B_activity_detected), '\n')
cat('2017-18 B activity:', format(truth$B_activity_weekF[truth$season=='2017-18'], digits=10), '\n')
cat('2018-19 B status:', truth$B_activity_status[truth$season=='2018-19'], '\n')
