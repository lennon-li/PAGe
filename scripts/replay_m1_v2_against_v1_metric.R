source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

campaign <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
current_truth <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors = FALSE)
current_m0 <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors = FALSE)

contract_dir <- '../PAGe/results/benchmark-contracts/m1/v1.0.0'
benchmark_dir <- '../PAGe/results/benchmark-evaluations/m1-v1.0.0/v16-cache-20260920'
origin_ledger <- read.csv(file.path(contract_dir, 'origin_ledger.csv'), stringsAsFactors = FALSE)
m0_ledger <- read.csv(file.path(contract_dir, 'm0_origin_ledger.csv'), stringsAsFactors = FALSE)
frozen_truth <- read.csv(file.path(contract_dir, 'peak_truth_ledger.csv'), stringsAsFactors = FALSE)
v1_scores <- read.csv(file.path(benchmark_dir, 'per_origin_scores.csv'), stringsAsFactors = FALSE)
v1_metrics <- read.csv(file.path(benchmark_dir, 'metric_results.csv'), stringsAsFactors = FALSE)

out_dir <- 'artifacts/m1-v2-package-replay-v1-metric'
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

metric_season_balanced_early_weighted <- function(df, error_col, season_col = 'season', weight_col = 'weight_early') {
  seasons <- sort(unique(df[[season_col]]))
  per <- vapply(seasons, function(s) {
    z <- df[df[[season_col]] == s, , drop = FALSE]
    sum(z[[weight_col]] * abs(z[[error_col]])) / sum(z[[weight_col]])
  }, numeric(1))
  list(value = mean(per), per_season = per)
}

# Assert the archived benchmark reproduces exactly before scoring the candidate.
v1_primary <- v1_scores[v1_scores$in_primary_prepeak, , drop = FALSE]
v1_check <- metric_season_balanced_early_weighted(v1_primary, 'error_integer')$value
v1_expected <- v1_metrics$value[v1_metrics$metric_id == 'primary_prepeak_integer_mae_season_balanced_early_weighted']
if (length(v1_expected) != 1L || abs(v1_check - v1_expected) > 1e-12) {
  stop('Frozen M1-v1 active metric failed exact reproduction.', call. = FALSE)
}

legacy_seasons <- as.character(frozen_truth$season)
primary <- origin_ledger[origin_ledger$in_primary_prepeak, , drop = FALSE]
primary <- merge(primary, m0_ledger[, c('season','origin_weekF','m0_locked_weekF')],
                 by = c('season','origin_weekF'), all.x = TRUE, sort = FALSE)
primary <- primary[order(match(primary$season, legacy_seasons), primary$origin_weekF), , drop = FALSE]
if (nrow(primary) != 92L || anyNA(primary$m0_locked_weekF)) stop('Frozen primary ledger mismatch.', call. = FALSE)

# ---- A. Exact frozen-contract benchmark replay: same 10-season universe ----
contract_rows <- list()
contract_libs <- list()
for (holdout in legacy_seasons) {
  train_seasons <- setdiff(legacy_seasons, holdout)
  train_data <- campaign[campaign$season %in% train_seasons, , drop = FALSE]
  train_truth <- current_truth[current_truth$season %in% train_seasons,
                               c('season','peak_week_decimal'), drop = FALSE]
  lib <- fit_m1_v2_library(train_data, train_truth, k = 8L, grid_step = .01, tau_step = .1)
  contract_libs[[holdout]] <- lib

  heldout_data <- campaign[campaign$season == holdout, , drop = FALSE]
  rows <- primary[primary$season == holdout, , drop = FALSE]
  A <- unique(rows$m0_locked_weekF)
  if (length(A) != 1L) stop('Frozen M0 lock is not constant within season ', holdout, '.', call. = FALSE)

  for (i in seq_len(nrow(rows))) {
    o <- rows$origin_weekF[[i]]
    fit <- m1_v2_peak_posterior(lib, heldout_data, activation_week = A,
                                origin_week = o, candidate_step = .1)
    s <- fit$summary[1,]
    contract_rows[[length(contract_rows) + 1L]] <- data.frame(
      origin_id = rows$origin_id[[i]], season = holdout, origin_weekF = o,
      m0_locked_weekF = A,
      prediction_mean_decimal = s$peak_mean,
      prediction_median_decimal = s$peak_median,
      prediction_map_decimal = s$peak_map,
      prediction_integer = round(s$peak_mean),
      q05 = s$peak_q05, q95 = s$peak_q95,
      stringsAsFactors = FALSE
    )
  }
}
contract_pred <- do.call(rbind, contract_rows)
contract_pred <- merge(contract_pred,
  frozen_truth[, c('season','peak_integer_weekF','peak_decimal_weekF')],
  by = 'season', all.x = TRUE, sort = FALSE)
contract_pred <- merge(contract_pred,
  current_truth[, c('season','peak_week_decimal')],
  by = 'season', all.x = TRUE, sort = FALSE)
names(contract_pred)[names(contract_pred) == 'peak_week_decimal'] <- 'current_peak_decimal'
contract_pred <- contract_pred[order(match(contract_pred$season, legacy_seasons), contract_pred$origin_weekF),]
contract_pred$weight_early <- exp(-(0.1 * (contract_pred$origin_weekF - contract_pred$m0_locked_weekF))^2)
contract_pred$error_integer_frozen <- contract_pred$prediction_integer - contract_pred$peak_integer_weekF
contract_pred$error_decimal_frozen_metric <- contract_pred$prediction_integer - contract_pred$peak_decimal_weekF
contract_pred$error_native_decimal_frozen <- contract_pred$prediction_mean_decimal - contract_pred$peak_decimal_weekF
contract_pred$current_peak_integer <- round(contract_pred$current_peak_decimal)
contract_pred$error_integer_current <- contract_pred$prediction_integer - contract_pred$current_peak_integer
contract_pred$error_decimal_current_metric <- contract_pred$prediction_integer - contract_pred$current_peak_decimal
contract_pred$error_native_decimal_current <- contract_pred$prediction_mean_decimal - contract_pred$current_peak_decimal
write.csv(contract_pred, file.path(out_dir, 'frozen_contract_per_origin.csv'), row.names = FALSE)

m1v2_active_frozen <- metric_season_balanced_early_weighted(contract_pred, 'error_integer_frozen')
m1v2_secondary_frozen <- metric_season_balanced_early_weighted(contract_pred, 'error_decimal_frozen_metric')
m1v2_native_decimal_frozen <- metric_season_balanced_early_weighted(contract_pred, 'error_native_decimal_frozen')
m1v2_active_current <- metric_season_balanced_early_weighted(contract_pred, 'error_integer_current')
m1v2_secondary_current <- metric_season_balanced_early_weighted(contract_pred, 'error_decimal_current_metric')
m1v2_native_decimal_current <- metric_season_balanced_early_weighted(contract_pred, 'error_native_decimal_current')

# Rescore frozen v1 predictions against current truth on the exact same 92 origins.
v1_current <- merge(v1_primary[, c('season','origin_weekF','prediction_peak_weekF','m0_locked_weekF')],
                    current_truth[, c('season','peak_week_decimal')], by='season', all.x=TRUE, sort=FALSE)
v1_current$weight_early <- exp(-(0.1*(v1_current$origin_weekF-v1_current$m0_locked_weekF))^2)
v1_current$current_peak_integer <- round(v1_current$peak_week_decimal)
v1_current$error_integer_current <- v1_current$prediction_peak_weekF-v1_current$current_peak_integer
v1_current$error_decimal_current <- v1_current$prediction_peak_weekF-v1_current$peak_week_decimal
v1_current_active <- metric_season_balanced_early_weighted(v1_current, 'error_integer_current')
v1_current_decimal <- metric_season_balanced_early_weighted(v1_current, 'error_decimal_current')

per_season_contract <- data.frame(
  season = legacy_seasons,
  v1_active_frozen = as.numeric(metric_season_balanced_early_weighted(v1_primary, 'error_integer')$per_season[legacy_seasons]),
  m1v2_active_frozen = as.numeric(m1v2_active_frozen$per_season[legacy_seasons]),
  v1_active_current_truth = as.numeric(v1_current_active$per_season[legacy_seasons]),
  m1v2_active_current_truth = as.numeric(m1v2_active_current$per_season[legacy_seasons]),
  stringsAsFactors = FALSE
)
write.csv(per_season_contract, file.path(out_dir, 'frozen_contract_per_season.csv'), row.names = FALSE)

# ---- B. Current 11-season extension using the same metric formula ----
all_seasons <- as.character(current_truth$season)
ext_rows <- list()
for (holdout in all_seasons) {
  train_seasons <- setdiff(all_seasons, holdout)
  train_data <- campaign[campaign$season %in% train_seasons, , drop = FALSE]
  train_truth <- current_truth[current_truth$season %in% train_seasons,
                               c('season','peak_week_decimal'), drop = FALSE]
  lib <- fit_m1_v2_library(train_data, train_truth, k = 8L, grid_step = .01, tau_step = .1)
  heldout_data <- campaign[campaign$season == holdout, , drop = FALSE]
  m0row <- current_m0[current_m0$season == holdout, , drop = FALSE]
  trow <- current_truth[current_truth$season == holdout, , drop = FALSE]
  if (nrow(m0row) != 1L || nrow(trow) != 1L) stop('Current fold metadata mismatch for ', holdout, '.', call. = FALSE)
  start_origin <- as.integer(m0row$iWeek_hat)
  peak_integer <- round(trow$peak_week_decimal)
  origins <- seq(start_origin, peak_integer, by = 1L)
  for (o in origins) {
    fit <- m1_v2_peak_posterior(lib, heldout_data, activation_week = m0row$iWeek_hatF,
                                origin_week = o, candidate_step = .1)
    s <- fit$summary[1,]
    ext_rows[[length(ext_rows)+1L]] <- data.frame(
      season=holdout, origin_weekF=o,
      m0_integer=start_origin, m0_decimal=m0row$iWeek_hatF,
      truth_peak_decimal=trow$peak_week_decimal, truth_peak_integer=peak_integer,
      prediction_mean_decimal=s$peak_mean,
      prediction_integer=round(s$peak_mean),
      q05=s$peak_q05, q95=s$peak_q95,
      stringsAsFactors=FALSE
    )
  }
}
ext <- do.call(rbind, ext_rows)
ext$weight_early <- exp(-(0.1*(ext$origin_weekF-ext$m0_integer))^2)
ext$error_integer <- ext$prediction_integer-ext$truth_peak_integer
ext$error_decimal_metric <- ext$prediction_integer-ext$truth_peak_decimal
ext$error_native_decimal <- ext$prediction_mean_decimal-ext$truth_peak_decimal
write.csv(ext, file.path(out_dir, 'current_11season_extension_per_origin.csv'), row.names = FALSE)
ext_active <- metric_season_balanced_early_weighted(ext, 'error_integer')
ext_decimal <- metric_season_balanced_early_weighted(ext, 'error_decimal_metric')
ext_native <- metric_season_balanced_early_weighted(ext, 'error_native_decimal')

per_season_ext <- data.frame(
  season = names(ext_active$per_season),
  primary_origin_count = as.integer(table(ext$season)[names(ext_active$per_season)]),
  integer_early_weighted_mae = as.numeric(ext_active$per_season),
  decimal_metric_early_weighted_mae = as.numeric(ext_decimal$per_season[names(ext_active$per_season)]),
  native_decimal_early_weighted_mae = as.numeric(ext_native$per_season[names(ext_active$per_season)]),
  stringsAsFactors=FALSE
)
write.csv(per_season_ext, file.path(out_dir, 'current_11season_extension_per_season.csv'), row.names = FALSE)

summary <- data.frame(
  comparison = c(
    'frozen_v1_benchmark_active',
    'm1v2_frozen_contract_active',
    'frozen_v1_benchmark_secondary_decimal',
    'm1v2_frozen_contract_secondary_decimal',
    'm1v2_frozen_contract_native_decimal',
    'frozen_v1_rescored_current_truth_active',
    'm1v2_current_truth_same_92_active',
    'frozen_v1_rescored_current_truth_decimal',
    'm1v2_current_truth_same_92_decimal_metric',
    'm1v2_current_truth_same_92_native_decimal',
    'm1v2_current_11season_extension_active',
    'm1v2_current_11season_extension_decimal_metric',
    'm1v2_current_11season_extension_native_decimal'
  ),
  value = c(
    v1_expected,
    m1v2_active_frozen$value,
    v1_metrics$value[v1_metrics$metric_id=='secondary_prepeak_decimal_mae_season_balanced_early_weighted'],
    m1v2_secondary_frozen$value,
    m1v2_native_decimal_frozen$value,
    v1_current_active$value,
    m1v2_active_current$value,
    v1_current_decimal$value,
    m1v2_secondary_current$value,
    m1v2_native_decimal_current$value,
    ext_active$value,
    ext_decimal$value,
    ext_native$value
  ),
  scoring_origins = c(92,92,92,92,92,92,92,92,92,92,nrow(ext),nrow(ext),nrow(ext)),
  stringsAsFactors = FALSE
)
write.csv(summary, file.path(out_dir, 'metric_summary.csv'), row.names = FALSE)

cat('FROZEN CONTRACT ACTIVE METRIC\n')
cat('M1-v1 benchmark:', format(v1_expected, digits=8), '\n')
cat('M1-v2:', format(m1v2_active_frozen$value, digits=8), '\n')
cat('delta:', format(m1v2_active_frozen$value-v1_expected, digits=8), '\n')
cat('relative change:', format((m1v2_active_frozen$value/v1_expected-1)*100, digits=5), '%\n')
cat('\nSAME 92 ORIGINS, CURRENT TRUTH\n')
cat('v1 rescored active:', format(v1_current_active$value,digits=8), '\n')
cat('m1-v2 active:', format(m1v2_active_current$value,digits=8), '\n')
cat('\nCURRENT 11-SEASON EXTENSION\n')
cat('origins:', nrow(ext), '\n')
cat('active integer metric:', format(ext_active$value,digits=8), '\n')
cat('secondary decimal metric:', format(ext_decimal$value,digits=8), '\n')
cat('native decimal metric:', format(ext_native$value,digits=8), '\n')
cat('\nPER-SEASON FROZEN CONTRACT\n')
print(per_season_contract,row.names=FALSE,digits=4)
cat('\nPER-SEASON 11-SEASON EXTENSION\n')
print(per_season_ext,row.names=FALSE,digits=4)
