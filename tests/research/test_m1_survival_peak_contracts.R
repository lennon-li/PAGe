#!/usr/bin/env Rscript

root <- normalizePath(".", mustWork = TRUE)
source_files <- file.path(root, "scripts", paste0("m1_survival_peak_",
  c("protocol", "features", "model", "evaluate", "nested"), ".R"))
for (path in c(source_files, file.path(root, "scripts/run_m1_survival_peak_nested_loso_v1.R"))) parse(path)
for (path in source_files) sys.source(path, envir = .GlobalEnv)

check <- function(name, expr) {
  tryCatch({ force(expr); cat("PASS:", name, "\n") }, error = function(e) {
    stop(sprintf("FAIL: %s: %s", name, conditionMessage(e)), call. = FALSE)
  })
}
must_fail <- function(expr, pattern = NULL) {
  err <- tryCatch({ force(expr); NULL }, error = identity)
  if (is.null(err)) stop("Expected operation to fail closed.", call. = FALSE)
  if (!is.null(pattern) && !grepl(pattern, conditionMessage(err), fixed = TRUE)) stop(conditionMessage(err), call. = FALSE)
  invisible(err)
}

protocol <- sp_protocol()
seasons <- protocol$principal_seasons
W <- setNames(rep(52L, length(seasons)), seasons)
W[["2019-20"]] <- 53L
calendar_meta <- data.frame(season = seasons, W = unname(W), source = "synthetic-test",
  source_hash = paste0("fixture-", seasons), authoritative = TRUE, stringsAsFactors = FALSE)
cal <- sp_calendar_from_metadata(calendar_meta, seasons)

check("all survival sources parse", {
  for (path in c(source_files, file.path(root, "scripts/run_m1_survival_peak_nested_loso_v1.R"))) parse(path)
})
check("historical mode is hard-disabled", {
  invocations <- list(list(args = "--historical", message = "requires explicit"),
    list(args = c("--historical", "--authorize-historical"), message = "hard-disabled"))
  for (invocation in invocations) {
    args <- invocation$args
    out <- suppressWarnings(system2("Rscript", c(file.path(root, "scripts/run_m1_survival_peak_nested_loso_v1.R"), args),
      stdout = TRUE, stderr = TRUE))
    status <- attr(out, "status")
    if (is.null(status) || status == 0L) stop("Historical invocation unexpectedly succeeded.")
    if (!any(grepl(invocation$message, out, fixed = TRUE))) stop("Historical invocation did not report the required authorization/hard-disable status.")
  }
})

obs <- do.call(rbind, lapply(seq_along(seasons), function(i) {
  weekF <- 10:16; N <- rep(40L, length(weekF))
  y <- pmin(N, pmax(0L, round(stats::plogis(-2 + weekF / 5 + i / 20) * N)))
  data.frame(season = seasons[i], weekF = weekF, y = y, N = N)
}))
labels <- data.frame(season = seasons, P = 18 + seq_along(seasons) %% 5 + .5,
  K = as.integer(floor(18 + seq_along(seasons) %% 5 + 1)), W = unname(cal[seasons]), mature = TRUE)
features <- sp_build_panel(obs, cal, protocol)

check("future observations cannot alter prefix features", {
  a <- sp_build_features(obs, seasons[1], 13L, cal[[seasons[1]]], protocol)
  poisoned <- obs; ix <- poisoned$season == seasons[1] & poisoned$weekF > 13L
  poisoned$y[ix] <- 0; poisoned$N[ix] <- 0
  b <- sp_build_features(poisoned, seasons[1], 13L, cal[[seasons[1]]], protocol)
  stopifnot(identical(a, b))
})
check("nonfinite features and invalid counts fail closed", {
  bad <- features[1, ]; bad$level <- Inf
  must_fail(sp_apply_feature_scaler(bad, list(center = setNames(rep(0, 4), protocol$feature_names),
    scale = setNames(rep(1, 4), protocol$feature_names), zero_variance = setNames(rep(FALSE, 4), protocol$feature_names))))
  bad_obs <- obs; bad_obs$N[1] <- 0
  must_fail(sp_build_features(bad_obs, bad_obs$season[1], 13L, cal[[bad_obs$season[1]]], protocol), "Counts")
})
check("nested role exclusions and cardinalities", {
  fold <- sp_fold_index(protocol); sp_assert_fold_index(fold, protocol)
  stopifnot(identical(as.integer(table(factor(fold$fold_role,
    levels = c("outer", "inner_validation", "inner_training_row", "outer_training_row")))), c(11L, 110L, 990L, 110L)))
})
check("K/P poison in an excluded evaluated season cannot affect predictions", {
  eval_season <- seasons[11]
  allowed <- seasons[1:10]
  train_features <- features[features$season %in% allowed, , drop = FALSE]
  train_labels <- labels[labels$season %in% allowed, , drop = FALSE]
  scale <- sp_scale_features(train_features, train_features, allowed, protocol)
  fit <- sp_fit_components(scale$train, train_labels, 1, "logit", protocol)
  eval_feature <- sp_apply_feature_scaler(features[features$season == eval_season, , drop = FALSE], scale$scaler, protocol)
  pred_a <- sp_predict_features(list(fit = fit, scaler = scale$scaler), features[features$season == eval_season, , drop = FALSE], calendar_meta, protocol)
  poison <- labels; poison$K[poison$season == eval_season] <- 50L; poison$P[poison$season == eval_season] <- 49.5
  train_labels_poisoned <- poison[poison$season %in% allowed, , drop = FALSE]
  fit_b <- sp_fit_components(scale$train, train_labels_poisoned, 1, "logit", protocol)
  pred_b <- sp_predict_features(list(fit = fit_b, scaler = scale$scaler), features[features$season == eval_season, , drop = FALSE], calendar_meta, protocol)
  stopifnot(identical(pred_a$pmf, pred_b$pmf), identical(pred_a$peak_weekF_origin, pred_b$peak_weekF_origin))
  invisible(eval_feature)
})
check("risk rows exclude K<=t and contain one event", {
  rr <- sp_hazard_risk_rows(data.frame(season = c("a", "b", "c"), t = c(4L, 4L, 4L), K = c(3L, 4L, 7L), W = 8L))
  stopifnot(setequal(unique(rr$season), "c"), identical(rr$k, 5:7), sum(rr$event) == 1L, tail(rr$event, 1L) == 1L)
})
check("hazard likelihood is invariant to duplicating person-weeks within a landmark", {
  X <- cbind(`(Intercept)` = 1,
    x = c(-1.0, -0.5, 0.25, 0.75, -0.8, 0.2, 0.9))
  y <- c(0L, 0L, 1L, 0L, 1L, 0L, 1L)
  season <- c(rep("s1", 5), rep("s2", 2))
  unit <- c(rep("s1_l1", 3), rep("s1_l2", 2), rep("s2_l1", 2))
  fit_a <- sp_fit_logistic(X, y, season, lambda = 1, unit = unit)

  dup <- which(unit == "s1_l1")
  Xb <- rbind(X, X[dup, , drop = FALSE])
  yb <- c(y, y[dup])
  sb <- c(season, season[dup])
  ub <- c(unit, unit[dup])
  fit_b <- sp_fit_logistic(Xb, yb, sb, lambda = 1, unit = ub)
  stopifnot(max(abs(fit_a$coef - fit_b$coef)) <= 1e-10)
})
check("future and mixture PMFs are finite, nonnegative, and mass-conserving", {
  qplus <- sp_future_pmf(c(.2, .4, .6)); stopifnot(length(qplus) == 3L, abs(sum(qplus) - 1) <= 1e-10, all(is.finite(qplus)), all(qplus >= 0))
  qminus <- sp_past_pmf(sp_past_prior(labels[1:10, , drop = FALSE]), 13L, 52L)
  pmf <- sp_mix_pmf(.35, 1:13, qminus, 14:52, sp_future_pmf(rep(.1, 39L)))
  sp_validate_pmf(pmf); stopifnot(all(pmf >= 0), abs(sum(pmf) - 1) <= 1e-10)
})
check("penalty boundary expands once then fails closed if still selected", {
  grid <- protocol$lambda
  first <- sp_penalty_expansion(min(grid), grid, FALSE, protocol)
  stopifnot(first$expanded, !first$unresolved, identical(first$candidates, c(.01, .1, 1, 10)))
  second <- sp_penalty_expansion(.01, first$candidates, TRUE, protocol)
  stopifnot(second$unresolved)
  fake_select <- sp_select_and_fit
  on.exit(assign("sp_select_and_fit", fake_select, envir = .GlobalEnv), add = TRUE)
  assign("sp_select_and_fit", function(...) list(boundary_unresolved = TRUE), envir = .GlobalEnv)
  must_fail(sp_fit_allowed(features[features$season %in% seasons[1:2], ], labels[labels$season %in% seasons[1:2], ], seasons[1:2],
    protocol, data.frame(lambda = 1, link = "logit"), calendar_meta), "expanded edge")
})
check("prediction artifact is written before SEALED_COMPLETE and seal verifies", {
  dir <- tempfile("survival-seal-"); on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  pred <- data.frame(season = "synthetic", origin = 13L, pmf = I(list(setNames(c(.4, .6), c("13", "14")))),
    peak_weekF_origin = 14L)
  manifest <- list(source = "test")
  sealed <- sp_seal_predictions(pred, dir, manifest)
  stopifnot(file.exists(file.path(dir, "sealed_peak_predictions.rds")), file.exists(file.path(dir, "SEALED_COMPLETE.rds")),
    sealed$status == "SEALED_COMPLETE")
  sp_verify_seal(dir, manifest)
  must_fail(sp_seal_predictions(transform(pred, K = 14L), tempfile("survival-poison-")), "Truth-derived")
})
check("serial/parallel equivalence is not applicable: no parallel path exists", {
  source_text <- paste(vapply(source_files, function(f) paste(readLines(f, warn = FALSE), collapse = "\n"), character(1)), collapse = "\n")
  stopifnot(!grepl("parallel::|future::|foreach::|mclapply|parLapply", source_text))
})

cat("PASS: focused M1 survival-peak contract suite\n")
