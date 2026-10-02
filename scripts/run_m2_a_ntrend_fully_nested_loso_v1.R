#!/usr/bin/env Rscript

# Fully nested LOSO evaluation of test-volume-history augmentations to the
# canonical M2-A A1 state model. Research/shadow only: does not alter v3.

panel_path <- Sys.getenv("PAGE_AB_PANEL", "artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv")
out_dir <- Sys.getenv("PAGE_OUT_DIR", "artifacts/m2-a-ntrend-fully-nested-loso-v1")
workers <- suppressWarnings(as.integer(Sys.getenv("PAGE_WORKERS", "4")))
if (!is.finite(workers) || workers < 1L) workers <- 1L
min_origin_week <- suppressWarnings(as.integer(Sys.getenv("PAGE_MIN_ORIGIN_WEEK", "13")))
if (!is.finite(min_origin_week) || min_origin_week < 5L) stop("PAGE_MIN_ORIGIN_WEEK must be an integer >= 5.", call. = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

clip <- function(p, eps = 1e-8) pmin(pmax(as.numeric(p), eps), 1 - eps)
logit <- function(p) stats::qlogis(clip(p, 1e-6))
stab <- function(y, N, c = 0.5) (y + c) / (N + 2 * c)

build_ledger <- function(ab) {
  req <- c("season", "weekF", "y_A", "N_A", "p_A", "denominator_regime")
  miss <- setdiff(req, names(ab))
  if (length(miss)) stop("Panel missing: ", paste(miss, collapse = ", "), call. = FALSE)
  rows <- list()
  for (s in sort(unique(as.character(ab$season)))) {
    z <- ab[ab$season == s, , drop = FALSE]
    z <- z[order(z$weekF), , drop = FALSE]
    if (anyDuplicated(z$weekF)) stop("Duplicate weekF in season ", s, call. = FALSE)
    if (any(!is.finite(z$N_A)) || any(z$N_A <= 0) || any(!is.finite(z$y_A)) ||
        any(z$y_A < 0) || any(z$y_A > z$N_A)) stop("Invalid counts in season ", s, call. = FALSE)
    m <- stats::setNames(seq_len(nrow(z)), as.character(z$weekF))
    i8 <- unname(m["8"])
    if (is.na(i8)) next
    ps <- stab(z$y_A, z$N_A)
    lp <- logit(ps)
    ln <- log(z$N_A)
    for (i in seq_len(nrow(z))) {
      w <- as.integer(z$weekF[i])
      if (w < min_origin_week) next
      ih <- unname(m[as.character((w - 4L):w)])
      if (anyNA(ih)) next
      i1 <- unname(m[as.character(w - 1L)])
      i2 <- unname(m[as.character(w - 2L)])
      if (anyNA(c(i1, i2))) next
      lv <- ln[ih]
      d1 <- lv[5] - lv[4]
      d2 <- lv[4] - lv[3]
      d3 <- lv[3] - lv[2]
      d4 <- lv[2] - lv[1]
      recent2 <- mean(c(d1, d2))
      older2 <- mean(c(d3, d4))
      expdl <- function(lambda) {
        ww <- lambda^(0:3)
        sum(c(d1, d2, d3, d4) * ww) / sum(ww)
      }
      for (h in 1:2) {
        j <- unname(m[as.character(w + h)])
        if (is.na(j)) next
        rows[[length(rows) + 1L]] <- data.frame(
          season = s,
          origin_week = w,
          target_week = w + h,
          horizon = h,
          y_target = as.numeric(z$y_A[j]),
          N_target = as.numeric(z$N_A[j]),
          p_target = as.numeric(z$y_A[j] / z$N_A[j]),
          p_star = ps[i],
          logit_current = lp[i],
          growth1 = lp[i] - lp[i1],
          growth2 = (lp[i] - lp[i2]) / 2,
          d1 = d1, d2 = d2, d3 = d3, d4 = d4,
          exp025 = expdl(0.25), exp050 = expdl(0.50),
          exp075 = expdl(0.75), exp100 = expdl(1.00),
          recent2 = recent2, older2 = older2,
          accel22 = recent2 - older2,
          rel8 = ln[i] - ln[i8],
          denominator_regime = as.character(z$denominator_regime[i]),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (!length(rows)) stop("No eligible common-history rows.", call. = FALSE)
  d <- do.call(rbind, rows)
  d$horizon_f <- factor(paste0("h", d$horizon), levels = c("h1", "h2"))
  d <- d[order(d$season, d$origin_week, d$horizon), , drop = FALSE]
  rownames(d) <- NULL
  d
}

candidate_grid <- data.frame(
  candidate = c(
    "OFF",
    "EXP025", "EXP050", "EXP075", "EXP100",
    "ACCEL22", "REL8",
    "DL2", "SPLIT22",
    "EXP050_X_G1"
  ),
  complexity = c(0L, 1L, 1L, 1L, 1L, 1L, 1L, 2L, 2L, 2L),
  risk_order = c(0L, 1L, 1L, 1L, 1L, 2L, 3L, 2L, 2L, 3L),
  stringsAsFactors = FALSE
)

candidate_terms <- list(
  OFF = character(),
  EXP025 = "exp025",
  EXP050 = "exp050",
  EXP075 = "exp075",
  EXP100 = "exp100",
  ACCEL22 = "accel22",
  REL8 = "rel8",
  DL2 = c("d1", "d2"),
  SPLIT22 = c("recent2", "older2"),
  EXP050_X_G1 = c("exp050", "exp050:growth1")
)

make_formula <- function(candidate) {
  tt <- candidate_terms[[candidate]]
  if (is.null(tt)) stop("Unknown candidate: ", candidate, call. = FALSE)
  rhs <- c("horizon_f", "growth1", "growth2", tt, "offset(logit_current)")
  stats::as.formula(paste(
    "cbind(y_target, N_target - y_target) ~",
    paste(rhs, collapse = " + ")
  ))
}

fit_candidate <- function(train, candidate) {
  train$horizon_f <- factor(paste0("h", train$horizon), levels = c("h1", "h2"))
  suppressWarnings(stats::glm(
    make_formula(candidate), data = train, family = stats::quasibinomial()
  ))
}

predict_candidate <- function(fit, newdata) {
  newdata$horizon_f <- factor(paste0("h", newdata$horizon), levels = c("h1", "h2"))
  clip(stats::predict(fit, newdata = newdata, type = "response"))
}

# Bernoulli cross-entropy per test. This is the binomial negative log-likelihood
# divided by N and prevents modern high-denominator rows from mechanically
# dominating model selection.
row_ce <- function(y, N, p) {
  p <- clip(p)
  -(y * log(p) + (N - y) * log(1 - p)) / N
}

score_validation <- function(validation, p, horizon) {
  z <- validation[validation$horizon == horizon, , drop = FALSE]
  pp <- p[validation$horizon == horizon]
  if (!nrow(z)) return(c(loss = NA_real_, mae_pp = NA_real_, brier = NA_real_))
  c(
    loss = mean(row_ce(z$y_target, z$N_target, pp)),
    mae_pp = 100 * mean(abs(pp - z$p_target)),
    brier = mean((pp - z$p_target)^2)
  )
}

select_paired_one_se <- function(fold_scores, score_table) {
  z <- score_table[is.finite(score_table$mean_loss), , drop = FALSE]
  if (!nrow(z)) stop("No valid inner candidate scores.", call. = FALSE)
  best <- z$candidate[which.min(z$mean_loss)]
  best_fold <- fold_scores[fold_scores$candidate == best, c("inner", "loss"), drop = FALSE]
  names(best_fold)[2L] <- "best_loss"
  paired <- lapply(z$candidate, function(candidate) {
    q <- fold_scores[fold_scores$candidate == candidate, c("inner", "loss"), drop = FALSE]
    names(q)[2L] <- "candidate_loss"
    q <- merge(q, best_fold, by = "inner", all = FALSE, sort = TRUE)
    delta <- q$candidate_loss - q$best_loss
    data.frame(
      candidate = candidate,
      paired_delta_vs_best = mean(delta),
      paired_se_vs_best = if (length(delta) > 1L) stats::sd(delta) / sqrt(length(delta)) else 0,
      stringsAsFactors = FALSE
    )
  })
  paired <- do.call(rbind, paired)
  z <- merge(z, paired, by = "candidate", all.x = TRUE, sort = FALSE)
  z$within_paired_one_se <- z$paired_delta_vs_best <= z$paired_se_vs_best + 1e-15
  eligible <- z[z$within_paired_one_se, , drop = FALSE]
  eligible <- eligible[order(
    eligible$complexity, eligible$risk_order,
    eligible$mean_loss, eligible$candidate
  ), , drop = FALSE]
  list(selected = eligible[1L, , drop = FALSE], scored = z, raw_best = best)
}

ab <- read.csv(panel_path, stringsAsFactors = FALSE)
ledger <- build_ledger(ab)
seasons <- sort(unique(ledger$season))
if (length(seasons) < 5L) stop("Nested LOSO requires at least five seasons.", call. = FALSE)
write.csv(ledger, file.path(out_dir, "candidate_independent_ledger.csv"), row.names = FALSE)
write.csv(candidate_grid, file.path(out_dir, "candidate_grid.csv"), row.names = FALSE)

# Provenance sufficient to rerun on BCC or another clean checkout.
prov <- data.frame(
  key = c("panel_path", "panel_md5", "n_seasons", "n_rows", "workers", "min_origin_week", "selection_rule", "selection_loss"),
  value = c(
    panel_path, unname(tools::md5sum(panel_path)), length(seasons), nrow(ledger), workers, min_origin_week,
    "inner LOSO paired one-SE vs raw best; complexity -> governance risk -> loss -> candidate",
    "season-balanced mean Bernoulli cross-entropy per test"
  ), stringsAsFactors = FALSE
)
write.csv(prov, file.path(out_dir, "provenance.csv"), row.names = FALSE)

inner_rows <- list()
selection_rows <- list()
outer_pred_rows <- list()

for (outer in seasons) {
  cat("outer ", outer, "\n", sep = "")
  outer_train_seasons <- setdiff(seasons, outer)

  # Each inner job fits every candidate once and predicts the inner-held-out
  # season. Candidate choice never sees the outer season.
  do_inner <- function(inner) {
    train_seasons <- setdiff(outer_train_seasons, inner)
    tr <- ledger[ledger$season %in% train_seasons, , drop = FALSE]
    va <- ledger[ledger$season == inner, , drop = FALSE]
    rr <- list()
    for (candidate in candidate_grid$candidate) {
      fit <- fit_candidate(tr, candidate)
      pv <- predict_candidate(fit, va)
      for (h in 1:2) {
        sc <- score_validation(va, pv, h)
        rr[[length(rr) + 1L]] <- data.frame(
          outer = outer, inner = inner, horizon = h, candidate = candidate,
          loss = unname(sc["loss"]), mae_pp = unname(sc["mae_pp"]),
          brier = unname(sc["brier"]), n_rows = sum(va$horizon == h),
          stringsAsFactors = FALSE
        )
      }
    }
    do.call(rbind, rr)
  }

  inner_list <- if (.Platform$OS.type != "windows" && workers > 1L) {
    parallel::mclapply(outer_train_seasons, do_inner, mc.cores = workers)
  } else {
    lapply(outer_train_seasons, do_inner)
  }
  inner <- do.call(rbind, inner_list)
  inner_rows[[outer]] <- inner

  selected <- list()
  for (h in 1:2) {
    hdat <- inner[inner$horizon == h, , drop = FALSE]
    sm <- do.call(rbind, lapply(candidate_grid$candidate, function(candidate) {
      q <- hdat[hdat$candidate == candidate, , drop = FALSE]
      g <- candidate_grid[candidate_grid$candidate == candidate, , drop = FALSE]
      data.frame(
        outer = outer, horizon = h, candidate = candidate,
        mean_loss = mean(q$loss),
        se_loss = stats::sd(q$loss) / sqrt(nrow(q)),
        mean_mae_pp = mean(q$mae_pp), mean_brier = mean(q$brier),
        n_inner_seasons = nrow(q), complexity = g$complexity,
        risk_order = g$risk_order, stringsAsFactors = FALSE
      )
    }))
    sel <- select_paired_one_se(hdat, sm)
    sm <- sel$scored
    pick <- sel$selected
    best_raw <- sm[sm$candidate == sel$raw_best, , drop = FALSE]
    pick$raw_best_candidate <- best_raw$candidate
    pick$raw_best_loss <- best_raw$mean_loss
    selected[[as.character(h)]] <- pick
    selection_rows[[paste(outer, h, sep = "__")]] <- transform(
      sm, selected = candidate == pick$candidate, raw_best = candidate == best_raw$candidate
    )
  }

  # Outer held-out predictions. Fit OFF plus only the candidate(s) selected
  # inside outer training data; the outer season is untouched until this point.
  tr <- ledger[ledger$season %in% outer_train_seasons, , drop = FALSE]
  te <- ledger[ledger$season == outer, , drop = FALSE]
  off_fit <- fit_candidate(tr, "OFF")
  off_pred <- predict_candidate(off_fit, te)
  te$pred_OFF <- off_pred
  te$pred_nested <- NA_real_
  te$pred_raw_best <- NA_real_
  te$selected_candidate <- NA_character_
  te$raw_best_candidate <- NA_character_
  for (h in 1:2) {
    pick <- selected[[as.character(h)]]
    candidate <- pick$candidate
    f <- if (candidate == "OFF") off_fit else fit_candidate(tr, candidate)
    ix <- which(te$horizon == h)
    te$pred_nested[ix] <- predict_candidate(f, te[ix, , drop = FALSE])
    raw_candidate <- pick$raw_best_candidate
    fr <- if (raw_candidate == "OFF") off_fit else fit_candidate(tr, raw_candidate)
    te$pred_raw_best[ix] <- predict_candidate(fr, te[ix, , drop = FALSE])
    te$selected_candidate[ix] <- candidate
    te$raw_best_candidate[ix] <- raw_candidate
  }
  outer_pred_rows[[outer]] <- te
}

inner_scores <- do.call(rbind, inner_rows)
selection_scores <- do.call(rbind, selection_rows)
outer <- do.call(rbind, outer_pred_rows)
rownames(inner_scores) <- rownames(selection_scores) <- rownames(outer) <- NULL

write.csv(inner_scores, file.path(out_dir, "inner_fold_scores.csv"), row.names = FALSE)
write.csv(selection_scores, file.path(out_dir, "inner_candidate_summaries.csv"), row.names = FALSE)
write.csv(outer, file.path(out_dir, "outer_predictions.csv"), row.names = FALSE)

outer$loss_OFF <- row_ce(outer$y_target, outer$N_target, outer$pred_OFF)
outer$loss_nested <- row_ce(outer$y_target, outer$N_target, outer$pred_nested)
outer$loss_raw_best <- row_ce(outer$y_target, outer$N_target, outer$pred_raw_best)
outer$ae_OFF_pp <- 100 * abs(outer$pred_OFF - outer$p_target)
outer$ae_nested_pp <- 100 * abs(outer$pred_nested - outer$p_target)
outer$ae_raw_best_pp <- 100 * abs(outer$pred_raw_best - outer$p_target)
outer$brier_OFF <- (outer$pred_OFF - outer$p_target)^2
outer$brier_nested <- (outer$pred_nested - outer$p_target)^2
outer$brier_raw_best <- (outer$pred_raw_best - outer$p_target)^2
write.csv(outer, file.path(out_dir, "outer_predictions_scored.csv"), row.names = FALSE)

per_season <- do.call(rbind, lapply(split(outer, list(outer$season, outer$horizon), drop = TRUE), function(z) {
  data.frame(
    season = z$season[1L], horizon = z$horizon[1L],
    selected_candidate = z$selected_candidate[1L],
    raw_best_candidate = z$raw_best_candidate[1L], n_rows = nrow(z),
    off_loss = mean(z$loss_OFF), nested_loss = mean(z$loss_nested),
    raw_best_loss = mean(z$loss_raw_best),
    off_mae_pp = mean(z$ae_OFF_pp), nested_mae_pp = mean(z$ae_nested_pp),
    raw_best_mae_pp = mean(z$ae_raw_best_pp),
    off_brier = mean(z$brier_OFF), nested_brier = mean(z$brier_nested),
    raw_best_brier = mean(z$brier_raw_best),
    stringsAsFactors = FALSE
  )
}))
rownames(per_season) <- NULL
write.csv(per_season, file.path(out_dir, "outer_per_season_metrics.csv"), row.names = FALSE)

summary_rows <- lapply(1:2, function(h) {
  z <- per_season[per_season$horizon == h, , drop = FALSE]
  data.frame(
    horizon = h, n_seasons = nrow(z),
    off_loss = mean(z$off_loss), nested_loss = mean(z$nested_loss),
    relative_loss_gain = 1 - mean(z$nested_loss) / mean(z$off_loss),
    raw_best_loss = mean(z$raw_best_loss),
    raw_best_relative_loss_gain = 1 - mean(z$raw_best_loss) / mean(z$off_loss),
    off_mae_pp = mean(z$off_mae_pp), nested_mae_pp = mean(z$nested_mae_pp),
    relative_mae_gain = 1 - mean(z$nested_mae_pp) / mean(z$off_mae_pp),
    raw_best_mae_pp = mean(z$raw_best_mae_pp),
    raw_best_relative_mae_gain = 1 - mean(z$raw_best_mae_pp) / mean(z$off_mae_pp),
    off_brier = mean(z$off_brier), nested_brier = mean(z$nested_brier),
    raw_best_brier = mean(z$raw_best_brier),
    seasons_loss_better = sum(z$nested_loss < z$off_loss),
    seasons_mae_better = sum(z$nested_mae_pp < z$off_mae_pp),
    off_selected = sum(z$selected_candidate == "OFF"),
    stringsAsFactors = FALSE
  )
})
summary <- do.call(rbind, summary_rows)
write.csv(summary, file.path(out_dir, "summary.csv"), row.names = FALSE)

selection_frequency <- as.data.frame(table(
  horizon = per_season$horizon,
  selected_candidate = per_season$selected_candidate
), stringsAsFactors = FALSE)
selection_frequency <- selection_frequency[selection_frequency$Freq > 0L, , drop = FALSE]
write.csv(selection_frequency, file.path(out_dir, "selection_frequency.csv"), row.names = FALSE)

regime <- do.call(rbind, lapply(split(outer, list(outer$denominator_regime, outer$horizon), drop = TRUE), function(z) {
  data.frame(
    denominator_regime = z$denominator_regime[1L], horizon = z$horizon[1L],
    n_seasons = length(unique(z$season)), n_rows = nrow(z),
    off_loss = mean(z$loss_OFF), nested_loss = mean(z$loss_nested),
    off_mae_pp = mean(z$ae_OFF_pp), nested_mae_pp = mean(z$ae_nested_pp),
    stringsAsFactors = FALSE
  )
}))
write.csv(regime, file.path(out_dir, "outer_by_denominator_regime.csv"), row.names = FALSE)

cat("\nFully nested N-trend LOSO summary\n")
print(summary, row.names = FALSE, digits = 6)
cat("\nSelection frequency\n")
print(selection_frequency, row.names = FALSE)
cat("\nPer-season outer results\n")
print(per_season, row.names = FALSE, digits = 6)
