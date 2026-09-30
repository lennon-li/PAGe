#!/usr/bin/env Rscript

out_artifact <- "artifacts/v3-probability-calibrator-v1"
out_bundle <- "governance/v3_probability_calibrator_v1.rds"
dir.create(out_artifact, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(out_bundle), recursive = TRUE, showWarnings = FALSE)

release_id <- "5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b"
eps <- 1e-6
stab <- function(y, N) (y + 0.5) / (N + 1)
logit <- function(p) qlogis(pmin(pmax(p, eps), 1 - eps))

A_path <- "artifacts/m2-v2-c2-governed-chronological-v1/predictions.csv"
B_path <- "artifacts/v3-m2-b-posterior-c2-chronological-v2/per_origin_predictions.csv"
A <- read.csv(A_path, stringsAsFactors = FALSE)
B <- read.csv(B_path, stringsAsFactors = FALSE)
A <- A[A$type == "A", , drop = FALSE]

make_pool <- function(d, p_col, type, h) {
  z <- d[d$horizon == h, , drop = FALSE]
  p <- as.numeric(z[[p_col]])
  valid <- is.finite(p) & p > eps & p < 1 - eps & is.finite(z$y_target) &
    is.finite(z$N_target) & z$N_target > 0 & z$y_target >= 0 & z$y_target <= z$N_target
  z <- z[valid, , drop = FALSE]; p <- p[valid]
  if (length(unique(z$season)) < 3L) stop("Insufficient seasons for ", type, " h", h)
  outcome <- stab(z$y_target, z$N_target)
  residual <- logit(outcome) - logit(p)
  season_n <- table(z$season)
  n_seasons <- length(season_n)
  weight <- 1 / (n_seasons * as.numeric(season_n[as.character(z$season)]))
  out <- data.frame(
    season = as.character(z$season), origin_week = as.integer(z$origin_week),
    target_week = as.integer(if ("target_week" %in% names(z)) z$target_week else z$origin_week + h),
    horizon = as.integer(h), type = type, point_forecast = p,
    y_target = as.numeric(z$y_target), N_target = as.numeric(z$N_target),
    calibration_outcome = outcome, residual = residual, weight = weight,
    stringsAsFactors = FALSE
  )
  if (anyDuplicated(out[c("season", "origin_week", "horizon")])) stop("Duplicate calibration rows")
  if (any(out$target_week != out$origin_week + h)) stop("Calibration target alignment failure")
  if (abs(sum(out$weight) - 1) > 1e-12) stop("Calibration weights do not sum to one")
  out
}

pools <- list(
  A_h1 = make_pool(A, "runtime_pred_base", "A", 1L),
  A_h2 = make_pool(A, "runtime_pred_base", "A", 2L),
  B_h1 = make_pool(B, "pred_B1", "B", 1L),
  B_h2 = make_pool(B, "pred_B2_posterior", "B", 2L)
)

artifact <- list(
  version = "v3-probability-calibrator-v1",
  release_id = release_id,
  status = "experimental",
  method = "exact_season_balanced_logit_residual_atoms",
  eps = eps,
  target_semantics = "Jeffreys-smoothed observed positivity (y+0.5)/(N+1)",
  pools = pools,
  provenance = list(
    A_source = A_path,
    B_source = B_path,
    A_source_sha256 = digest::digest(file = A_path, algo = "sha256", serialize = FALSE),
    B_source_sha256 = digest::digest(file = B_path, algo = "sha256", serialize = FALSE),
    A_predictor = "canonical_v3_A_exact_A1_state_runtime_pred_base",
    B_h1_predictor = "canonical_v3_B_exact_B1_state",
    B_h2_predictor = "canonical_v3_B_posterior_C2_with_B1_fallback",
    weighting = "equal season mass; equal origin mass within season",
    construction = "chronological OOS forecast residuals only"
  )
)
artifact$calibrator_id <- digest::digest(artifact, algo = "sha256")
saveRDS(artifact, file.path(out_artifact, "v3_probability_calibrator.rds"), version = 3)
saveRDS(artifact, out_bundle, version = 3)

# Chronological validation: for each target season, use strictly earlier residual seasons.
weighted_quantile <- function(x, w, probs) {
  o <- order(x); x <- x[o]; w <- w[o] / sum(w[o]); cs <- cumsum(w); cs[length(cs)] <- 1
  vapply(probs, function(p) x[which(cs >= p)[1L]], numeric(1L))
}
validate_pool <- function(pool) {
  seasons <- sort(unique(pool$season))
  rows <- list()
  for (s in seasons) {
    prior <- seasons[as.integer(substr(seasons, 1, 4)) < as.integer(substr(s, 1, 4))]
    if (length(prior) < 3L) next
    cal <- pool[pool$season %in% prior, , drop = FALSE]
    test <- pool[pool$season == s, , drop = FALSE]
    sn <- table(cal$season); wcal <- 1 / (length(sn) * as.numeric(sn[as.character(cal$season)]))
    for (i in seq_len(nrow(test))) {
      atoms <- plogis(logit(test$point_forecast[i]) + cal$residual)
      qs <- weighted_quantile(atoms, wcal, c(.05, .25, .5, .75, .95))
      y <- test$calibration_outcome[i]
      rows[[length(rows)+1L]] <- data.frame(
        season=s, origin_week=test$origin_week[i], horizon=test$horizon[i], type=test$type[i],
        y=y, q05=qs[1],q25=qs[2],q50=qs[3],q75=qs[4],q95=qs[5],
        cover50=y>=qs[2] & y<=qs[4], cover90=y>=qs[1] & y<=qs[5],
        pit=sum(wcal[atoms <= y]), stringsAsFactors=FALSE)
    }
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}
val <- do.call(rbind, lapply(pools, validate_pool))
write.csv(val, file.path(out_artifact, "chronological_validation_rows.csv"), row.names=FALSE)
if (nrow(val)) {
  summary <- aggregate(cbind(cover50, cover90, pit) ~ type + horizon, val, mean)
  summary$n_rows <- as.integer(table(interaction(val$type,val$horizon,drop=TRUE))[interaction(summary$type,summary$horizon,drop=TRUE)])
  write.csv(summary, file.path(out_artifact, "chronological_validation_summary.csv"), row.names=FALSE)
  print(summary, row.names=FALSE)
}

inventory <- do.call(rbind, lapply(names(pools), function(k) {
  z <- pools[[k]]
  data.frame(pool=k, n_rows=nrow(z), n_seasons=length(unique(z$season)),
             min_season=min(z$season), max_season=max(z$season), weight_sum=sum(z$weight), stringsAsFactors=FALSE)
}))
write.csv(inventory, file.path(out_artifact, "pool_inventory.csv"), row.names=FALSE)
writeLines(c(
  paste0("calibrator_id\t", artifact$calibrator_id),
  paste0("release_id\t", artifact$release_id),
  paste0("bundle_sha256\t", digest::digest(file=out_bundle,algo="sha256",serialize=FALSE))
), file.path(out_artifact, "identity.tsv"))
cat("calibrator_id=", artifact$calibrator_id, "\n", sep="")
print(inventory, row.names=FALSE)
