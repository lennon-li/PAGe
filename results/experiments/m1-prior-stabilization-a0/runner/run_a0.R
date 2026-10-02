#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(dplyr)
  library(tibble)
  library(purrr)
  library(tidyr)
  library(mgcv)
  library(gamm4)
  library(gratia)
})

root <- normalizePath(getwd(), mustWork = TRUE)
bundle <- file.path(root, "results/experiments/m1-prior-stabilization-a0")
dir.create(bundle, recursive = TRUE, showWarnings = FALSE)
for (d in c("outputs", "runtime", "validation")) dir.create(file.path(bundle, d), showWarnings = FALSE)
if (file.exists(file.path(bundle, "SHA256SUMS"))) stop("Refusing to overwrite sealed A0 bundle.", call. = FALSE)

baseline <- file.path(root, "results/experiments/m1-replay-baseline-v1.0.0")
source_root <- file.path(baseline, "inputs/source/PAGe/R")
refs <- readRDS(file.path(baseline, "inputs/frozen/frozen_references.rds"))
snapshot <- readRDS(file.path(baseline, "inputs/frozen/historical_snapshot.rds"))
origin <- fread(file.path(root, "results/benchmark-contracts/m1/v1.0.0/origin_ledger.csv"))
truth <- fread(file.path(root, "results/benchmark-contracts/m1/v1.0.0/peak_truth_ledger.csv"))
m0 <- fread(file.path(baseline, "inputs/frozen/m0_inputs.csv"))
base_align <- fread(file.path(baseline, "workers/A/runA/ledgers/alignment_ledger.csv"))
base_params <- fread(file.path(baseline, "workers/A/runA/ledgers/template_param_ledger.csv"))
base_weights <- fread(file.path(baseline, "workers/A/runA/ledgers/template_weight_ledger.csv"))
base_wf <- fread(file.path(root, "results/experiments/m1-walkforward-metric-audit/outputs/walkforward_origin_ledger.csv"))
fold_json <- fromJSON(file.path(baseline, "workers/A/runA/ledgers/fold_hyperparams.json"), simplifyVector = FALSE)

assert <- function(ok, msg) if (!isTRUE(ok)) stop(msg, call. = FALSE)
origin[, origin_id := paste(season, origin_weekF, sep = "@")]
m0[, origin_id := paste(season, origin_weekF, sep = "@")]
base_align[, origin_id := paste(season, origin_weekF, sep = "@")]
base_wf[, origin_id := paste(season, origin_weekF, sep = "@")]
assert(nrow(origin) == 334L, "Origin ledger is not 334 rows")
assert(nrow(base_align) == 334L, "Baseline alignment ledger is not 334 rows")

hyper_list <- lapply(fold_json, function(z) {
  h <- z$hyper
  h$TAU_BOUNDS <- as.numeric(unlist(h$TAU_BOUNDS))
  h$DELTA_BOUNDS <- as.numeric(unlist(h$DELTA_BOUNDS))
  h$WEEK_THRESHOLD_DELTA <- as.numeric(unlist(h$WEEK_THRESHOLD_DELTA))
  h$LAMBDA_DELTA <- as.numeric(unlist(h$LAMBDA_DELTA))
  h
})

variants <- data.table(
  variant_id = c("baseline", "delta_fixed_zero_positive_scale", "delta_ridge4_positive_scale", "delta_ridge16_positive_scale"),
  delta_mode = c("baseline", "fixed_zero", "gated", "gated"),
  lambda_multiplier = c(1, 1, 4, 16),
  positive_scale = c(FALSE, TRUE, TRUE, TRUE),
  stringsAsFactors = FALSE
)

source_variant <- function(positive_scale) {
  options(page_prior_multiplier = 1)
  fs <- sort(list.files(source_root, full.names = TRUE, pattern = "\\.R$"))
  fs <- fs[!grepl("retired\\.R$", fs)]
  for (f in fs) {
    txt <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    if (basename(f) == "m1_fit.R") {
      txt <- gsub("lam_eff <- lam_delta", "lam_eff <- lam_delta * getOption('page_prior_multiplier', 1)", txt, fixed = TRUE)
    }
    if (positive_scale && basename(f) == "align_forecast_pipeline_dilate.R") {
      txt <- gsub("a_hat <- coef(glm_hat)[1]\n    b_hat <- coef(glm_hat)[2]",
        "a_hat <- fit$a\n    b_hat <- fit$b", txt, fixed = TRUE)
      txt <- gsub("a_hat <- coef(glm_hat)[1]\n      b_hat <- coef(glm_hat)[2]",
        "a_hat <- fit$a\n      b_hat <- fit$b", txt, fixed = TRUE)
    }
    source(textConnection(txt), local = .GlobalEnv)
  }
}

make_hyper <- function(season, variant_name) {
  h <- hyper_list[[season]]
  v <- variants[variants$variant_id == variant_name, ]
  if (v$delta_mode == "fixed_zero") h$WEEK_THRESHOLD_DELTA <- 1e9
  h$LAMBDA_DELTA <- h$LAMBDA_DELTA * v$lambda_multiplier
  h
}

base_pred <- base_wf[, .(variant_id = "baseline", origin_id, season, origin_weekF,
  m1_peak_raw, m1_peak_integer,
  m0_locked_weekF = m0_detected_ignition_weekF)]
fwrite(base_pred, file.path(bundle, "outputs/baseline_predictions.csv"))

run_variant <- function(vrow) {
  v <- vrow$variant_id
  if (v == "baseline") return(list(pred = base_pred, params = base_params[, .(variant_id = v, origin_id, season, origin_weekF, template_name, tau, delta, a, b, nll, fallback_reason, t_peak, allow_scale, delta_on)], status = NULL))
  source_variant(vrow$positive_scale)
  options(page_prior_multiplier = vrow$lambda_multiplier)
  tasks <- lapply(seq_len(nrow(origin)), function(i) {
    s <- origin$season[i]; o <- as.integer(origin$origin_weekF[i]); key <- origin$origin_id[i]
    ref <- refs[[s]]
    mi <- m0[origin_id == key]
    cur <- snapshot[snapshot$season == s & snapshot$weekF <= o, , drop = FALSE]
    current <- cur
    list(i = i, key = key, season = s, origin_weekF = o, ref = ref, current = current,
      hyper = make_hyper(s, v), allow_scale = as.logical(base_align[origin_id == key]$allow_scale),
      ignition = list(ign_week_locked = as.integer(mi$m0_locked_weekF),
        iWeek_hat_locked = as.integer(mi$historical_cache_iWeek_hat)))
  })
  one <- function(task) {
    warns <- character()
    ap <- tryCatch(withCallingHandlers(
      run_alignment_prospective_multi(
        currentSeason = task$current, ref = task$ref, hyper = task$hyper,
        ign_out = task$ignition, use_ci = TRUE, buffer_weeks = 5L,
        allow_scale = task$allow_scale, level = 0.95, min_obs = 4L,
        curvature_ratio = 1, trough_weight = 0.1, rise_weight = 1,
        peak_decay = 0.3, temperature = 0.25, top_k = NULL, blend_alpha = 1,
        slope_weight = 8, slope_window = 6L, dynamic_temp = FALSE,
        dynamic_temp_pivot = 10L),
      warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") }),
      error = function(e) e)
    if (inherits(ap, "error")) return(list(error = conditionMessage(ap), key = task$key))
    raw <- as.numeric(ap$t_peak) - as.numeric(task$ref$anchorWeek) + as.numeric(task$ignition$iWeek_hat_locked)
    param_rows <- if (length(ap$per_template)) {
      rbindlist(lapply(seq_along(ap$per_template), function(j) {
        z <- ap$per_template[[j]]; nm <- ap$template_names[j]
        data.table(variant_id = v, origin_id = task$key, season = task$season,
          origin_weekF = task$origin_weekF, template_name = nm,
          tau = z$tau, delta = z$delta, a = z$a, b = z$b, nll = z$nll,
          fallback_reason = z$fallback_reason, t_peak = z$peak$t_peak,
          allow_scale = z$allow_scale, delta_on = z$delta_on,
          optimizer_status = NA_integer_, warning_count = length(warns))
      }), fill = TRUE)
    } else data.table()
    list(error = FALSE, pred = data.table(variant_id = v, origin_id = task$key,
      season = task$season, origin_weekF = task$origin_weekF,
      m1_peak_raw = raw, m1_peak_integer = round(raw), m0_locked_weekF = task$ignition$ign_week_locked,
      state = ap$state, fallback_reason = ap$fallback_reason, delta_on = ap$delta_on,
      allow_scale = ap$allow_scale, warning_count = length(warns)), params = param_rows)
  }
  ans <- parallel::mclapply(tasks, one, mc.cores = min(10L, parallel::detectCores()))
  bad <- vapply(ans, function(z) isTRUE(z$error), logical(1))
  assert(!any(bad), sprintf("Variant %s failed at %s: %s", v, ans[[which(bad)[1]]]$key, ans[[which(bad)[1]]]$error))
  list(pred = rbindlist(lapply(ans, `[[`, "pred"), fill = TRUE),
    params = rbindlist(lapply(ans, `[[`, "params"), fill = TRUE),
    status = data.table(variant_id = v, origins = length(ans), warnings = sum(vapply(ans, function(z) z$pred$warning_count, numeric(1)))))
}

all_pred <- list(base_pred)
all_param <- list(base_params[, .(variant_id = "baseline", origin_id, season, origin_weekF, template_name, tau, delta, a, b, nll, fallback_reason, t_peak, allow_scale, delta_on)])
run_status <- list()
for (i in 2:nrow(variants)) {
  z <- run_variant(variants[i])
  all_pred[[length(all_pred) + 1L]] <- z$pred
  all_param[[length(all_param) + 1L]] <- z$params
  run_status[[length(run_status) + 1L]] <- z$status
}
pred <- rbindlist(all_pred, fill = TRUE)
params <- rbindlist(all_param, fill = TRUE)
setorder(pred, variant_id, season, origin_weekF)
setorder(params, variant_id, season, origin_weekF, template_name)

pred <- merge(pred, origin[, .(origin_id, in_primary_prepeak, in_full_season_diagnostic)], by = "origin_id", all.x = TRUE)
pred <- merge(pred, truth[, .(season, peak_integer_weekF, peak_decimal_weekF)], by = "season", all.x = TRUE)
pred <- merge(pred, m0[, .(origin_id, m0_locked_weekF)], by = "origin_id", suffixes = c("", "_m0"), all.x = TRUE)
pred[, integer_signed_error := m1_peak_integer - peak_integer_weekF]
pred[, integer_abs_error := abs(integer_signed_error)]
pred[, decimal_signed_error := m1_peak_raw - peak_decimal_weekF]
pred[, decimal_abs_error := abs(decimal_signed_error)]
pred[, raw_time_weight := exp(-(0.1 * (origin_weekF - m0_locked_weekF))^2)]
pred[, within_season_normalized_weight := fifelse(in_primary_prepeak,
  raw_time_weight / sum(raw_time_weight[in_primary_prepeak]), NA_real_), by = .(variant_id, season)]

score_variant <- function(x) {
  p <- x[in_primary_prepeak == TRUE]
  ss <- p[, .(
    weighted_integer_mae = sum(within_season_normalized_weight * integer_abs_error),
    weighted_decimal_mae = sum(within_season_normalized_weight * decimal_abs_error),
    unweighted_integer_mae = mean(integer_abs_error),
    unweighted_decimal_mae = mean(decimal_abs_error),
    weighted_integer_bias = sum(within_season_normalized_weight * integer_signed_error),
    weighted_decimal_bias = sum(within_season_normalized_weight * decimal_signed_error)
  ), by = .(variant_id, season)]
  data.table(variant_id = unique(x$variant_id),
    primary_integer_mae = mean(ss$weighted_integer_mae),
    primary_decimal_mae = mean(ss$weighted_decimal_mae),
    primary_integer_unweighted_mae = mean(ss$unweighted_integer_mae),
    primary_decimal_unweighted_mae = mean(ss$unweighted_decimal_mae),
    pooled_integer_mae = sum(p$raw_time_weight * p$integer_abs_error) / sum(p$raw_time_weight),
    pooled_decimal_mae = sum(p$raw_time_weight * p$decimal_abs_error) / sum(p$raw_time_weight),
    full_integer_mae = mean(x[in_full_season_diagnostic == TRUE, integer_abs_error]),
    n_primary = nrow(p), n_full = nrow(x))
}
metrics <- rbindlist(lapply(split(pred, pred$variant_id), score_variant), fill = TRUE)
baseline_metrics <- metrics[variant_id == "baseline"]
comparison <- metrics[variant_id != "baseline"]
comparison[, `:=`(primary_integer_mae_baseline = baseline_metrics$primary_integer_mae,
  primary_decimal_mae_baseline = baseline_metrics$primary_decimal_mae,
  delta_primary_integer = primary_integer_mae - baseline_metrics$primary_integer_mae,
  delta_primary_decimal = primary_decimal_mae - baseline_metrics$primary_decimal_mae)]

diffs <- pred[variant_id != "baseline"]
base_err <- pred[variant_id == "baseline", .(origin_id, baseline_integer_abs = integer_abs_error, baseline_decimal_abs = decimal_abs_error)]
diffs <- merge(diffs, base_err, by = "origin_id", all.x = TRUE)
change_summary <- diffs[, .(
  integer_improved = sum(integer_abs_error < baseline_integer_abs),
  integer_worsened = sum(integer_abs_error > baseline_integer_abs),
  integer_unchanged = sum(integer_abs_error == baseline_integer_abs),
  decimal_improved = sum(decimal_abs_error < baseline_decimal_abs),
  decimal_worsened = sum(decimal_abs_error > baseline_decimal_abs),
  decimal_unchanged = sum(decimal_abs_error == baseline_decimal_abs),
  peak_raw_max_step = max(abs(m1_peak_raw - shift(m1_peak_raw)), na.rm = TRUE),
  peak_raw_p90_step = quantile(abs(m1_peak_raw - shift(m1_peak_raw)), .9, na.rm = TRUE, names = FALSE)
), by = variant_id]

param_diag <- params[, {
  setorder(.SD, origin_weekF)
  .(template_rows = .N, nonpositive_b = sum(is.finite(b) & b <= 0),
    fallback_rows = sum(!is.na(fallback_reason) & fallback_reason != ""),
    delta_on_rows = sum(delta_on %in% TRUE),
    max_abs_tau_step = max(abs(tau - shift(tau)), na.rm = TRUE),
    p90_abs_tau_step = quantile(abs(tau - shift(tau)), .9, na.rm = TRUE, names = FALSE),
    max_abs_tpeak_step = max(abs(t_peak - shift(t_peak)), na.rm = TRUE),
    p90_abs_tpeak_step = quantile(abs(t_peak - shift(t_peak)), .9, na.rm = TRUE, names = FALSE),
    b_min = min(b, na.rm = TRUE), b_max = max(b, na.rm = TRUE))
}, by = .(variant_id, season, template_name)]
param_season <- param_diag[, .(template_rows = sum(template_rows), nonpositive_b = sum(nonpositive_b),
  fallback_rows = sum(fallback_rows), delta_on_rows = sum(delta_on_rows),
  max_abs_tau_step = max(max_abs_tau_step), p90_abs_tau_step = quantile(p90_abs_tau_step, .9, names = FALSE),
  max_abs_tpeak_step = max(max_abs_tpeak_step), p90_abs_tpeak_step = quantile(p90_abs_tpeak_step, .9, names = FALSE),
  b_min = min(b_min), b_max = max(b_max)), by = .(variant_id, season)]

fwrite(pred, file.path(bundle, "outputs/predictions.csv"))
fwrite(params, file.path(bundle, "outputs/template_parameters.csv"))
fwrite(metrics, file.path(bundle, "outputs/metrics.csv"))
fwrite(comparison, file.path(bundle, "outputs/comparison_to_baseline.csv"))
fwrite(change_summary, file.path(bundle, "outputs/origin_change_summary.csv"))
fwrite(param_diag, file.path(bundle, "outputs/parameter_diagnostics_by_template.csv"))
fwrite(param_season, file.path(bundle, "outputs/parameter_diagnostics_by_season.csv"))
fwrite(rbindlist(run_status, fill = TRUE), file.path(bundle, "outputs/run_status.csv"))

spec <- list(
  experiment = "m1-prior-stabilization-a0",
  variants = variants,
  baseline_id = "m1-replay-baseline-v1.0.0",
  unchanged = c("M0", "template universe", "slope_weight=8", "temperature=0.25", "weighted-mean peak", "rounding", "origins"),
  positive_scale_rule = "Use constrained fit_tau_delta a,b values for final curve/peak; no unconstrained post-fit b replacement",
  delta_prior_rule = "fixed zero or frozen LAMBDA_DELTA multiplied by 4/16",
  selection = "none; evidence-only comparison",
  no_production_changes = TRUE
)
writeLines(toJSON(spec, pretty = TRUE, auto_unbox = TRUE), file.path(bundle, "execution_spec.json"))
writeLines(capture.output(sessionInfo()), file.path(bundle, "runtime/session_info.txt"))
writeLines(c("External worker routes: Liz app-server filesystem failure; Wei OpenCode log filesystem failure on initial and repaired retry; Claude API/DNS EAI_AGAIN.",
  "Parent executed the bounded experiment locally under the no-implementation-capable-route exception.",
  "No production M0/M1/M2 code or sealed bundle was modified."), file.path(bundle, "runtime/delegation_record.txt"))
writeLines(c("baseline parity is inherited from sealed m1-replay-baseline-v1.0.0 and checked against its origin ledger;",
  "variant runners use the same frozen references, snapshot, M0 inputs, folds, coordinate grid, and contract origins;",
  "primary weights = exp(-(0.1 * (origin_weekF - m0_locked_weekF))^2), normalized within season."),
  file.path(bundle, "validation/validation_notes.txt"))
cat("A0 complete\n")
