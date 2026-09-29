#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

repo <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source("scripts/v3_shadow_ops_helpers_v1.R", local = .GlobalEnv)
source("2026/run_weekly_shadow_v2.R", local = .GlobalEnv)
.shadow_v2_source_package()
source("2026/run_weekly_shadow_v3_week12_v1.R", local = .GlobalEnv)

release_dir <- file.path(
  repo,
  "artifacts/v3-shadow-release-v3",
  "5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b"
)
panel_path <- file.path(
  repo,
  "artifacts/v3-live-2026-27-week11-deployment-v1/input/typed_ab_weekly.csv"
)
out_dir <- file.path(repo, "artifacts/v3-week8-11-walkforward-report-v1")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

opts <- .shadow_v3_parse_args(c("--season=2026-27", paste0("--release-dir=", release_dir)))
pf <- .shadow_v3_preflight(opts)
panel <- utils::read.csv(panel_path, stringsAsFactors = FALSE, check.names = FALSE)
panel <- panel[order(panel$weekF), , drop = FALSE]
.shadow_ops_validate_panel(panel, "2026-27", require_forecast_support = FALSE)

safe_scalar <- function(x, default = NA) {
  if (is.null(x) || length(x) < 1L) return(default)
  x[[1L]]
}

m1a_summary <- function(prefix, m0_result) {
  a_current <- data.frame(
    season = prefix$season,
    weekF = prefix$weekF,
    y = prefix$y_A,
    N = prefix$N_A,
    p = prefix$p_A,
    stringsAsFactors = FALSE
  )
  if (!is.finite(m0_result$iWeek_lockedF)) {
    return(list(state = "inactive_pre_ignition", peak_estimate = NA_real_, peak_passed_prob = NA_real_))
  }
  out <- tryCatch(
    run_m1_v2_timing(list(m1_v2 = pf$m1a), a_current, m0_result, verbose = FALSE),
    error = identity
  )
  if (inherits(out, "error")) {
    return(list(state = paste0("error:", conditionMessage(out)), peak_estimate = NA_real_, peak_passed_prob = NA_real_))
  }
  state <- safe_scalar(out$state, NA_character_)
  if (is.na(state) && is.data.frame(out$timing_df) && nrow(out$timing_df)) {
    cand <- intersect(c("state", "timing_state", "status"), names(out$timing_df))
    if (length(cand)) state <- as.character(out$timing_df[[cand[[1L]]]][nrow(out$timing_df)])
  }
  peak_est <- safe_scalar(out$peak_weekF, NA_real_)
  if (!is.finite(peak_est)) peak_est <- safe_scalar(out$peak_estimate, NA_real_)
  ppassed <- safe_scalar(out$prob_peak_passed, NA_real_)
  list(state = ifelse(is.na(state), "active_or_available", state), peak_estimate = as.numeric(peak_est), peak_passed_prob = as.numeric(ppassed))
}

rows <- list()
state_rows <- list()
k <- 0L
s <- 0L

for (origin in 8:11) {
  prefix <- panel[panel$weekF <= origin, , drop = FALSE]
  current <- prefix[prefix$weekF == origin, , drop = FALSE]

  a_current <- data.frame(
    season = prefix$season,
    weekF = prefix$weekF,
    y = prefix$y_A,
    N = prefix$N_A,
    p = prefix$p_A,
    stringsAsFactors = FALSE
  )
  m0_det <- detectIgnitionBySeason_M0v2_timing(
    a_current,
    pf$m0$best_params,
    verbose = FALSE,
    iWeek = FALSE,
    validate_support = FALSE
  )
  by <- m0_det$by_season[1L, , drop = FALSE]
  m0_ignited <- !isTRUE(by$detection_failed)
  m0_result <- list(
    ign_out = m0_det,
    iWeek_locked = if (m0_ignited) as.numeric(by$iWeek_hat) else NA_real_,
    iWeek_lockedF = if (m0_ignited) as.numeric(by$iWeek_hatF) else NA_real_,
    overridden = FALSE
  )
  m1a <- m1a_summary(prefix, m0_result)

  b_current <- data.frame(
    season = prefix$season,
    weekF = prefix$weekF,
    y = prefix$y_B,
    N = prefix$N_B,
    p = prefix$p_B,
    stringsAsFactors = FALSE
  )
  b_norm <- .m2b_normalize_current(b_current)
  b_activity <- .m2b_causal_activity(pf$m2b, b_norm, origin)
  b_activity_week <- if (isTRUE(b_activity$available)) as.numeric(b_activity$activity_week) else NA_real_
  m1b_state <- if (isTRUE(b_activity$available)) "active_timing_event" else "inactive_no_timing_event"

  a_runtime <- run_m2_v2_c2_governed_runtime(
    pf$m2a, prefix, origin,
    a_handoff = NULL, b_handoff = NULL, b_gate_review = NULL
  )
  ap <- a_runtime$predictions

  b_features <- .m2b_state_features(b_norm, origin)
  b1_h1 <- .m2b_state_predict(pf$m2b, b_features, 1L)
  b1_h2 <- .m2b_state_predict(pf$m2b, b_features, 2L)

  b_h2 <- b1_h2
  b_h2_route <- "exact_B1_fallback"
  b_timing_available <- FALSE
  b_prob_peak_passed <- NA_real_
  if (isTRUE(b_activity$available)) {
    mix <- m2_b_v3_shadow_forecast(
      pf$m2b,
      current_data = b_norm,
      activity_week = b_activity$activity_week,
      origin_week = origin,
      horizon = 2L
    )
    b_h2 <- as.numeric(mix$forecast)
    b_h2_route <- as.character(mix$route)
    b_timing_available <- identical(mix$route, "posterior_C2")
    b_prob_peak_passed <- safe_scalar(mix$diagnostics$prob_peak_passed, NA_real_)
  }

  s <- s + 1L
  state_rows[[s]] <- data.frame(
    season = "2026-27",
    origin_weekF = origin,
    week_start_date = current$week_start_date,
    week_end_date = current$week_end_date,
    A_observed_pct = 100 * current$p_A,
    B_observed_pct = 100 * current$p_B,
    M0_A_ignited = m0_ignited,
    M0_A_ignition_weekF = if (m0_ignited) as.numeric(by$iWeek_hatF) else NA_real_,
    M1_A_state = m1a$state,
    M1_A_peak_weekF = m1a$peak_estimate,
    M1_A_prob_peak_passed = m1a$peak_passed_prob,
    M1_B_state = m1b_state,
    M1_B_activity_weekF = b_activity_week,
    M1_B_reason = as.character(b_activity$reason),
    stringsAsFactors = FALSE
  )

  forecasts <- data.frame(
    type = c("A", "A", "B", "B"),
    horizon = c(1L, 2L, 1L, 2L),
    forecast_pct = c(
      100 * ap$pred_selected[ap$type == "A" & ap$horizon == 1L],
      100 * ap$pred_selected[ap$type == "A" & ap$horizon == 2L],
      100 * b1_h1,
      100 * b_h2
    ),
    route = c(
      "exact_A1_state_diagnostic",
      "exact_A1_state_diagnostic",
      "exact_B1_state_diagnostic",
      paste0(b_h2_route, "_diagnostic")
    ),
    timing_available = c(FALSE, FALSE, FALSE, b_timing_available),
    prob_peak_passed = c(NA_real_, NA_real_, NA_real_, b_prob_peak_passed),
    stringsAsFactors = FALSE
  )

  for (j in seq_len(nrow(forecasts))) {
    typ <- forecasts$type[[j]]
    h <- forecasts$horizon[[j]]
    target_week <- origin + h
    target <- panel[panel$weekF == target_week, , drop = FALSE]
    obs <- if (nrow(target)) 100 * target[[paste0("p_", typ)]][[1L]] else NA_real_
    k <- k + 1L
    rows[[k]] <- data.frame(
      season = "2026-27",
      origin_weekF = origin,
      origin_week_end = current$week_end_date,
      type = typ,
      horizon = h,
      target_weekF = target_week,
      forecast_pct = forecasts$forecast_pct[[j]],
      route = forecasts$route[[j]],
      timing_available = forecasts$timing_available[[j]],
      prob_peak_passed = forecasts$prob_peak_passed[[j]],
      observed_target_pct = obs,
      error_pp = if (is.finite(obs)) forecasts$forecast_pct[[j]] - obs else NA_real_,
      abs_error_pp = if (is.finite(obs)) abs(forecasts$forecast_pct[[j]] - obs) else NA_real_,
      governed_issued = FALSE,
      governance_note = "Pre-weekF12 walk-forward diagnostic; not an issued v3 forecast.",
      stringsAsFactors = FALSE
    )
  }
}

state_df <- do.call(rbind, state_rows)
forecast_df <- do.call(rbind, rows)

utils::write.csv(state_df, file.path(out_dir, "m0_m1_state_week8_11.csv"), row.names = FALSE, na = "")
utils::write.csv(forecast_df, file.path(out_dir, "m2_walkforward_week8_11.csv"), row.names = FALSE, na = "")

scored <- forecast_df[is.finite(forecast_df$abs_error_pp), , drop = FALSE]
score_df <- if (nrow(scored)) {
  groups <- split(scored, interaction(scored$type, scored$horizon, drop = TRUE))
  do.call(rbind, lapply(groups, function(z) {
    data.frame(
      type = z$type[[1L]],
      horizon = z$horizon[[1L]],
      MAE_pp = mean(z$abs_error_pp),
      n_scored = nrow(z),
      stringsAsFactors = FALSE
    )
  }))
} else data.frame()
utils::write.csv(score_df, file.path(out_dir, "m2_score_to_date_week8_11.csv"), row.names = FALSE, na = "")

meta <- data.frame(
  key = c("season", "origins", "latest_weekF", "latest_week_end", "forecast_release_id", "panel_sha256", "effective_panel_sha256", "governed_min_origin_week", "report_status"),
  value = c(
    "2026-27", "8,9,10,11", max(panel$weekF), as.character(panel$week_end_date[which.max(panel$weekF)]),
    basename(release_dir),
    digest::digest(file = panel_path, algo = "sha256", serialize = FALSE),
    .shadow_ops_effective_panel_sha256(panel, "2026-27"),
    "12",
    "diagnostic_walkforward_pre_issuance"
  ),
  stringsAsFactors = FALSE
)
write.table(meta, file.path(out_dir, "report_metadata.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)

cat("Wrote walk-forward report data to: ", normalizePath(out_dir, winslash = "/", mustWork = TRUE), "\n", sep = "")
print(state_df, row.names = FALSE)
print(forecast_df[, c("origin_weekF", "type", "horizon", "forecast_pct", "observed_target_pct", "abs_error_pp", "route")], row.names = FALSE)
if (nrow(score_df)) print(score_df, row.names = FALSE)
