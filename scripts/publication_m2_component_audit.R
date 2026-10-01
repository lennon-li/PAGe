#!/usr/bin/env Rscript
# Diagnostic decomposition of frozen M2 artifacts; never fits or tunes models.
suppressPackageStartupMessages(library(mgcv))
source("scripts/publication_comparator_helpers.R")
source("PAGe/R/m2_training.R")
source("PAGe/R/correction_spec.R")
source("PAGe/R/pipeline_runtime.R")

audit_m2_components <- function(output = NULL) {
  root <- "manuscript/results/publication-repair-20260908"
  replay_root <- file.path(root, "replay/20260908T125939/private")
  if (is.null(output)) output <- file.path(root, "m2-components")
  stopifnot(!dir.exists(output))
  input <- "/home/yeli/FLU/flu_testing_data.csv"
  registry <- utils::read.csv("results/audit/holdout_reconciliation_principal.csv")
  input_hash <- digest::digest(file = input, algo = "sha256")
  stopifnot(all(registry$input_sha256 == input_hash))
  observations <- pc_read_data(input)
  names(observations)[names(observations) == "week"] <- "weekF"
  scores <- effects <- slopes <- checks <- list()
  started <- Sys.time()

  for (i in seq_len(nrow(registry))) {
    season <- registry$season[i]
    archive <- sub("/mnt/nfsv4/Users/yeli/PAGe-artifacts",
      "/home/yeli/PAGe-bcc-artifacts", registry$run_dir[i], fixed = TRUE)
    kit <- readRDS(file.path(archive, "artifacts/candidate_pre_holdout.rds"))
    replay <- readRDS(file.path(replay_root, paste0(season, ".rds")))
    fit <- kit$m2_production$fit
    spec <- kit$best_spec
    ranges <- kit$m2_production$feature_ranges
    # These restrictions make the median-reference RE decomposition exact.
    stopifnot(spec$T == "S", spec$k_w == 0, spec$k_s == 0,
      spec$k_n == 0, spec$k_de == 0)
    exclude <- spec$exclude_newseason
    stopifnot("s(season)" %in% exclude)
    m2 <- replay$stages$m2_predictions
    m2 <- m2[order(m2$eval_week, m2$h), ]
    stopifnot(!anyDuplicated(paste(m2$eval_week, m2$h)))
    ap <- replay$stages$m1_parameters
    ap <- ap[match(m2$eval_week, ap$eval_week), ]
    stopifnot(!anyNA(ap$eval_week))
    obs <- observations[observations$season == season, ]
    obs$p_now <- obs$y / obs$N
    obs$z_now <- qlogis(pmin(1 - 1e-6, pmax(1e-6, obs$p_now)))
    ema <- as.numeric(stats::filter(spec$alpha_state * obs$z_now,
      filter = 1 - spec$alpha_state, method = "recursive",
      init = obs$z_now[1]))

    nd <- fit$model[rep(1L, nrow(m2)), -1L, drop = FALSE]
    nd$lead <- factor(paste0("h", m2$h), levels = levels(fit$model$lead))
    nd$season <- factor(levels(fit$model$season)[1],
      levels = levels(fit$model$season))
    nd$logit_f_eff <- pmin(ranges$logit_f_eff[2],
      pmax(ranges$logit_f_eff[1],
        qlogis(pmin(1 - 1e-6, pmax(1e-6, m2$m1_p)))))
    nd$z_ema <- pmin(ranges$z_ema[2], pmax(ranges$z_ema[1],
      ema[match(m2$eval_week, obs$weekF)]))
    nd$z_resid <- nd$z_ema - nd$logit_f_eff
    nd$logit_spread <- vapply(seq_len(nrow(m2)), function(j) {
      curve <- replay$stages$m1_curves
      curve <- curve[curve$eval_week == m2$eval_week[j], ]
      .approx_unique(curve$newWeek, curve$logit_spread,
        m2$target_weekF[j] - ap$iWeek_hat[j] + kit$ref$anchorWeek)
    }, numeric(1))
    eta <- as.numeric(predict(fit, nd, type = "link", exclude = exclude))
    eta_error <- max(abs(eta - m2$m2_eta_raw))
    stopifnot(is.finite(eta_error), eta_error < 1e-9)

    # The runtime fills all active numeric GAM predictors with training medians
    # when estimating its online season shift from raw observations.
    reference <- fit$model[1, -1L, drop = FALSE]
    for (name in names(reference)) {
      column <- fit$model[[name]]
      if (is.numeric(column)) reference[[name]] <- stats::median(column)
      if (is.factor(column)) {
        reference[[name]] <- factor(levels(column)[1], levels = levels(column))
      }
    }
    eta_reference <- as.numeric(predict(fit, reference,
      type = "link", exclude = exclude))
    re_shift <- vapply(seq_len(nrow(m2)), function(j) {
      keep <- obs$weekF <= m2$eval_week[j] & obs$weekF >= ap$iWeek_hat[j]
      if (!any(keep)) keep <- obs$weekF <= m2$eval_week[j]
      sum(obs$z_now[keep] - eta_reference) / (sum(keep) + 1)
    }, numeric(1))
    re_error <- max(vapply(unique(c(1L, nrow(m2))), function(j) {
      prefix <- obs[obs$weekF <= m2$eval_week[j], ]
      post <- prefix[prefix$weekF >= ap$iWeek_hat[j], ]
      if (!nrow(post)) post <- prefix
      abs(estimate_season_re_online(fit, post, exclude) - re_shift[j])
    }, numeric(1)))
    stopifnot(re_error < 1e-9)

    correction <- .resolve_correction_spec(spec)
    states <- list(.new_bias_correction_state(), .new_bias_correction_state())
    bias <- numeric(nrow(m2))
    peak_seen <- FALSE
    for (week in unique(m2$eval_week)) {
      now <- which(m2$eval_week == week)
      if (isTRUE(ap$peak_passed[now[1]]) && !peak_seen) {
        states <- list(.new_bias_correction_state(), .new_bias_correction_state())
        peak_seen <- TRUE
      }
      due <- which(m2$eval_week < week & m2$target_weekF == week)
      z_observed <- obs$z_now[match(week, obs$weekF)]
      for (j in due) {
        h <- m2$h[j]
        states[[h]] <- .update_bias_correction(states[[h]],
          z_observed - eta[j], correction)$state
      }
      bias[now] <- vapply(m2$h[now], function(h) {
        states[[h]]$level + h * states[[h]]$trend
      }, numeric(1))
    }
    cap <- make_soft_cap_fn(fit)
    gate <- function(p) {
      ifelse(m2$forecast_action == "post_peak_m1", m2$m1_p, cap(p))
    }
    variants <- data.frame(
      m1 = m2$m1_p,
      raw_gam = plogis(eta),
      no_online = gate(plogis(eta)),
      season_shift_only = gate(plogis(eta + re_shift)),
      horizon_bias_only = gate(plogis(eta + bias)),
      both_online = gate(plogis(eta + re_shift + bias))
    )
    final_error <- max(abs(variants$both_online - m2$m2_p))
    stopifnot(is.finite(final_error), final_error < 1e-9)

    ledger <- replay$forecast_ledger
    ledger <- ledger[match(paste(m2$eval_week, m2$h),
      paste(ledger$weekF, ledger$lead)), ]
    stopifnot(all(ledger$target_weekF == m2$target_weekF))
    terms <- predict(fit, nd, type = "terms", exclude = exclude)
    # Tiny conditional perturbations preserve the derived-residual identity.
    step <- 1e-4
    upper <- lower <- nd
    upper$logit_f_eff <- nd$logit_f_eff + step
    lower$logit_f_eff <- nd$logit_f_eff - step
    direct_m1_slope <- (predict(fit, upper, type = "link", exclude = exclude) -
      predict(fit, lower, type = "link", exclude = exclude)) / (2 * step)
    upper$z_resid <- upper$z_ema - upper$logit_f_eff
    lower$z_resid <- lower$z_ema - lower$logit_f_eff
    m1_slope <- (predict(fit, upper, type = "link", exclude = exclude) -
      predict(fit, lower, type = "link", exclude = exclude)) / (2 * step)

    for (h in 1:2) {
      primary <- ledger$scorable & is.finite(ledger$t_since) &
        ledger$t_since >= 0 & ledger$t_since <= 12 & m2$h == h
      primary[is.na(primary)] <- FALSE
      for (variant in names(variants)) {
        p <- variants[[variant]][primary]
        y <- ledger$y_lead[primary]
        n <- ledger$N_lead[primary]
        scores[[length(scores) + 1L]] <- data.frame(
          season, horizon = h, variant, rows = length(p),
          nll = pc_nll(y, n, p), mae = sum(n * abs(p - y / n)) / sum(n)
        )
      }
      for (variable in c("logit_f_eff", "z_ema", "z_resid", "logit_spread")) {
        columns <- grep(paste0("s(", variable, ")"),
          colnames(terms), fixed = TRUE)
        contribution <- if (length(columns)) {
          rowSums(terms[primary, columns, drop = FALSE])
        } else rep(0, sum(primary))
        effects[[length(effects) + 1L]] <- data.frame(
          season, horizon = h, variable, present = length(columns) > 0,
          span_10_90_logit = unname(diff(quantile(contribution, c(0.1, 0.9))))
        )
      }
      slopes[[length(slopes) + 1L]] <- data.frame(
        season, horizon = h, median_m1_logit_slope = median(m1_slope[primary]),
        median_direct_m1_slope = median(direct_m1_slope[primary]),
        slope_p10 = unname(quantile(m1_slope[primary], 0.1)),
        slope_p90 = unname(quantile(m1_slope[primary], 0.9)),
        median_season_shift = median(re_shift[primary]),
        median_horizon_bias = median(bias[primary])
      )
    }
    checks[[i]] <- data.frame(season, eta_error, re_error, final_error)
    message("Verified ", season, ": raw GAM, online shift, final output")
  }
  scores <- do.call(rbind, scores)
  effects <- do.call(rbind, effects)
  slopes <- do.call(rbind, slopes)
  checks <- do.call(rbind, checks)
  aggregate <- stats::aggregate(cbind(nll, mae) ~ horizon + variant, scores, mean)
  dir.create(output, recursive = TRUE)
  for (name in c("scores", "effects", "slopes", "checks", "aggregate")) {
    utils::write.csv(get(name), file.path(output, paste0(name, ".csv")),
      row.names = FALSE)
  }
  jsonlite::write_json(list(
    status = "diagnostic_only", training_calls = 0, tuning_calls = 0,
    input_sha256 = input_hash, replay_root = replay_root,
    script_sha256 = digest::digest(file = "scripts/publication_m2_component_audit.R",
      algo = "sha256"), elapsed_seconds = as.numeric(difftime(
        Sys.time(), started, units = "secs")),
    score_definition = "h1/h2 origins 0:12 after declaration; trial-weight within, equal-season across",
    effect_definition = "Within-season 10th-to-90th percentile smooth contribution span in log-odds; not causal importance",
    slope_definition = "d raw GAM logit / d supplied M1 logit, holding EMA/spread fixed and updating z_resid; no online adjustment or cap derivative",
    limitations = "Post-holdout diagnostic; correlated predictors; no offset fit evaluated; 2025-26 partial"
  ), file.path(output, "metadata.json"), pretty = TRUE, auto_unbox = TRUE)
  print(aggregate, row.names = FALSE)
  print(slopes[slopes$horizon == 2, ], row.names = FALSE)
  print(stats::aggregate(span_10_90_logit ~ horizon + variable, effects, median),
    row.names = FALSE)
}

if (sys.nframe() == 0L) audit_m2_components()
