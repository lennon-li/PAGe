#!/usr/bin/env Rscript
# Conditional M2 development comparison: archived M0/M1 are never fitted.
source("scripts/publication_m2_offset_two_seasons.R")
output <- Sys.getenv("PAGE_M2_COMPARISON_OUTPUT", file.path(root,
  "manuscript/results/publication-repair-20260908/m2-simplified-20260908"))
if (dir.exists(output)) stop("Output already exists: ", output)
dir.create(file.path(output, "private"), recursive = TRUE)
writeLines("*", file.path(output, "private/.gitignore"))
started <- Sys.time()
target_seasons <- as.character(registry$season[registry$status == "complete" & registry$exchangeable])
stopifnot(length(target_seasons) == 11L, !anyDuplicated(target_seasons))
authorized <- read_authorized_data(input_path)
candidates <- c("m1", "offset_intercept", "offset_smooth")
write_json <- function(x, name) jsonlite::write_json(x, file.path(output, name),
  auto_unbox = TRUE, pretty = TRUE, digits = 16, null = "null")
write_json(list(status = "running", candidates = candidates,
  k_z = 3, k_sp = 0, gamma = 1.4, intercept_penalty = "REML estimated ridge",
  training_weight = "equal total trial weight per season",
  runtime = "native Codex in-session worker",
  external_worker_or_service = FALSE,
  selection = "minimum equal-season inner NLL separately by horizon; exact ties prefer simpler model",
  validation_window = "origin t_since 0 through 12",
  feature_clamping = "fit range recomputed from each inner training split; outer target clamped to full outer-training range",
  limitations = "Conditional on archived M0/M1 and historical M2 EMA settings; M1 features are not newly season-cross-fitted. Previously inspected outer seasons are development data.",
  no_m1_refit = TRUE, no_online_correction = TRUE, no_post_peak_switch = TRUE,
  seasons = target_seasons), "protocol.json")

fit_candidate <- function(d, candidate) {
  if (candidate == "m1") return(NULL)
  fit_started <- Sys.time()
  z_range <- range(d$z_ema)
  fit <- fit_m2_offset_correction(d,
    k_z = if (candidate == "offset_smooth") 3L else 0L,
    penalize_intercepts = TRUE, season_balance = TRUE)
  fit$z_range <- z_range
  fit$elapsed_seconds <- as.numeric(difftime(Sys.time(), fit_started, units = "secs"))
  fit
}
predict_candidate <- function(fit, d) {
  if (is.null(fit)) return(plogis(d$logit_f_eff))
  d$z_ema <- pmin(fit$z_range[2], pmax(fit$z_range[1], d$z_ema))
  predict_m2_offset_correction(fit, d)$p_hat
}
score <- function(d, p, season, variant, h) {
  d$prediction <- p
  ans <- score_variant(d, "prediction", season, h)
  stopifnot(ans$rows > 0, is.finite(ans$nll), is.finite(ans$mae))
  ans$variant <- variant
  ans
}
training_data <- function(bundle) {
  kit <- bundle$kit
  d <- prep_stage2_joint(kit$hist_data, kit$m2_production$spec,
    template_df = kit$template_df, leads = 1:2,
    alpha_state = kit$m2_production$spec$alpha_state,
    m1_preds = kit$m1_train_preds, feature_ranges = NULL, verbose = FALSE)
  d <- d[d$post_ign %in% TRUE, ]
  d$season <- as.character(d$season)
  d$h <- as.integer(sub("h", "", d$lead))
  # Never silently train an offset on fallback static-template predictions.
  m <- kit$m1_train_preds
  key <- paste(m$season, m$eval_weekF, m$h)
  stopifnot(!anyDuplicated(key))
  idx <- match(paste(d$season, d$weekF, d$h), key)
  keep <- !is.na(idx) & is.finite(m$m1_p_hat[idx])
  dropped <- sum(!keep)
  d <- d[keep, ]
  stopifnot(max(abs(d$logit_f_eff - logit_stable(m$m1_p_hat[idx[keep]]))) < 1e-12,
    !bundle$season %in% d$season,
    setequal(unique(d$season), kit$m2_production$training_seasons),
    length(unique(d$season)) == 10L)
  attr(d, "dropped_missing_m1") <- dropped
  d
}
target_data <- function(bundle) {
  m <- as.data.frame(bundle$replay$stages$m2_predictions)
  d <- data.frame(season = bundle$season, eval_week = m$eval_week,
    target_weekF = m$target_weekF, h = m$h, m1 = m$m1_p,
    current_raw_m2 = plogis(m$m2_eta_raw), current_complete_m2 = m$m2_p)
  d$t_since <- d$eval_week - bundle$replay$ignition_week
  obs <- authorized[authorized$season == bundle$season, ]
  z <- logit_stable(obs$y / obs$N)
  alpha <- bundle$kit$m2_production$spec$alpha_state
  ema <- as.numeric(stats::filter(alpha * z, filter = 1-alpha,
    method = "recursive", init = z[1]))
  d$z_ema <- ema[match(d$eval_week, obs$weekF)]
  d$y_lead <- obs$y[match(d$target_weekF, obs$weekF)]
  d$N_lead <- obs$N[match(d$target_weekF, obs$weekF)]
  d <- d[d$t_since >= 0 & d$t_since <= 12 & is.finite(d$y_lead) &
    is.finite(d$N_lead) & d$N_lead > 0, ]
  d$logit_f_eff <- logit_stable(d$m1)
  d$lead <- factor(paste0("h", d$h), levels = c("h1", "h2"))
  stopifnot(all(d$target_weekF == d$eval_week + d$h),
    all(is.finite(as.matrix(d[c("m1", "current_raw_m2", "z_ema")]))))
  d
}

outer <- inner <- selected <- timing <- provenance <- list()
for (season in target_seasons) {
  fold_start <- Sys.time()
  bundle <- read_kit(season)
  d <- training_data(bundle)
  inner_rows <- list()
  inner_fit_seconds <- 0
  for (validation in sort(unique(d$season))) {
    tr <- d[d$season != validation, ]
    va <- d[d$season == validation & d$t_since >= 0 & d$t_since <= 12, ]
    stopifnot(!validation %in% tr$season, !season %in% tr$season)
    for (candidate in candidates) {
      f <- fit_candidate(tr, candidate)
      p <- predict_candidate(f, va)
      for (h in 1:2) {
        r <- score(va, p, validation, candidate, h)
        r$outer_season <- season
        r$fit_warnings <- if (is.null(f)) "" else paste(f$warnings, collapse = " | ")
        inner_rows[[length(inner_rows)+1L]] <- r
      }
      if (!is.null(f)) inner_fit_seconds <- inner_fit_seconds + f$elapsed_seconds
    }
  }
  cv <- do.call(rbind, inner_rows)
  inner[[season]] <- cv
  ranks <- aggregate(cbind(nll, mae) ~ horizon + variant, cv, mean)
  ranks$complexity <- match(ranks$variant, candidates)
  ranks <- ranks[order(ranks$horizon, ranks$nll, ranks$complexity), ]
  choice <- ranks[!duplicated(ranks$horizon), ]
  choice$season <- season
  selected[[season]] <- choice
  target <- target_data(bundle)
  fits <- setNames(lapply(candidates[-1], function(x) fit_candidate(d, x)), candidates[-1])
  for (candidate in names(fits)) target[[candidate]] <- predict_candidate(fits[[candidate]], target)
  target$selected_m2 <- vapply(seq_len(nrow(target)), function(i) {
    target[[choice$variant[match(target$h[i], choice$horizon)]]][i]
  }, numeric(1))
  variants <- c(candidates, "current_raw_m2", "current_complete_m2", "selected_m2")
  outer[[season]] <- do.call(rbind, lapply(variants, function(v) {
    do.call(rbind, lapply(1:2, function(h) score(target, target[[v]], season, v, h)))
  }))
  saveRDS(list(predictions = target, fits = fits, selection = choice,
    training_seasons = unique(d$season), conditional_inner_scores = cv),
    file.path(output, "private", paste0(season, ".rds")))
  timing[[season]] <- data.frame(season = season, training_rows = nrow(d),
    dropped_missing_m1 = attr(d, "dropped_missing_m1"),
    elapsed_seconds = as.numeric(difftime(Sys.time(), fold_start, units = "secs")),
    inner_fit_seconds = inner_fit_seconds,
    outer_fit_seconds = sum(vapply(fits, function(x) x$elapsed_seconds, numeric(1))),
    intercept_edf = sum(fits$offset_intercept$fit$edf[grepl("^lead", names(fits$offset_intercept$fit$edf))]),
    smooth_edf = sum(fits$offset_smooth$fit$edf[grepl("^s\\(", names(fits$offset_smooth$fit$edf))]),
    warnings = paste(unique(unlist(lapply(fits, function(x) x$warnings))), collapse = " | "))
  provenance[[season]] <- list(kit = sha256(bundle$kit_path), replay = sha256(bundle$replay_path))
  write_json(list(status = "running", completed = length(outer), total = 11,
    last_season = season), "status.json")
  message(season, ": complete")
}
scores <- do.call(rbind, outer)
agg <- aggregate(cbind(nll, mae) ~ horizon + variant, scores, mean)
agg <- agg[order(agg$horizon, agg$nll), ]
for (name in c("outer", "inner", "selected", "timing")) {
  utils::write.csv(do.call(rbind, get(name)), file.path(output, paste0(name, ".csv")), row.names = FALSE)
}
utils::write.csv(agg, file.path(output, "aggregate.csv"), row.names = FALSE)
write_json(list(status = "complete_diagnostic_only", completed = length(outer),
  elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
  input_sha256 = sha256(input_path), registry_sha256 = sha256(registry_path),
  artifacts = provenance,
  source_sha256 = setNames(lapply(c("PAGe/R/m2_offset_prototype.R",
    "PAGe/R/m2_training.R", "scripts/publication_m2_offset_two_seasons.R",
    "scripts/publication_m2_simplified.R"), sha256), c("offset", "training", "helpers", "runner")),
  session = capture.output(sessionInfo())), "status.json")
print(agg, row.names = FALSE)
