#!/usr/bin/env Rscript

# Expanding-window C1/C2/C3 replay. Every outer target is scored from models,
# timing libraries, and family selection built only from chronologically prior
# seasons. This is a research artifact runner; it does not touch runtime code.

source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

input_dir <- 'artifacts/m2-v2-flu-ab-geometry-v1'
ab <- read.csv(file.path(input_dir, 'flu_ab_weekly_v1.csv'), stringsAsFactors=FALSE)
long <- read.csv(file.path(input_dir, 'flu_ab_long_v1.csv'), stringsAsFactors=FALSE)
shape <- read.csv(file.path(input_dir, 'peak_aligned_normalized_shape_grid.csv'), stringsAsFactors=FALSE)
geom <- read.csv(file.path(input_dir, 'type_geometry_k8.csv'), stringsAsFactors=FALSE)
ab$season <- as.character(ab$season)
long$season <- as.character(long$season)
shape$season <- as.character(shape$season)
geom$season <- as.character(geom$season)
seasons <- sort(unique(ab$season))
types <- c('A', 'B')
families <- c('C1', 'C2', 'C3')
min_prior <- 3L
out_dir <- 'artifacts/m2-v2-ab-curve-ratio-chronological-c123-v1'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

logit <- function(p) qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
stab <- function(y, n, c=.5) (y + c) / (n + 2 * c)

# Candidate-independent origin ledger for both types.
ledger_parts <- list()
for (tp in types) {
  rows <- list()
  for (s in seasons) {
    z <- ab[ab$season == s, ]
    z <- z[order(z$weekF), ]
    y <- z[[paste0('y_', tp)]]
    n <- z[[paste0('N_', tp)]]
    p <- z[[paste0('p_', tp)]]
    ps <- stab(y, n)
    l <- logit(ps)
    g1 <- c(NA_real_, diff(l))
    g2 <- c(NA_real_, NA_real_, (l[3:length(l)] - l[1:(length(l)-2)]) / 2)
    for (i in seq_len(nrow(z))) {
      if (z$weekF[i] < 13 || i < 3L) next
      for (h in 1:2) {
        j <- i + h
        if (j > nrow(z) || z$weekF[j] != z$weekF[i] + h) next
        rows[[length(rows) + 1L]] <- data.frame(
          season=s, type=tp, origin_week=z$weekF[i], target_week=z$weekF[j],
          horizon=h, y_target=y[j], N_target=n[j], p_target=p[j],
          p_star=ps[i], logit_current=l[i], growth1=g1[i], growth2=g2[i],
          stringsAsFactors=FALSE)
      }
    }
  }
  ledger_parts[[tp]] <- do.call(rbind, rows)
}
ledger <- do.call(rbind, ledger_parts)
ledger$horizon_f <- factor(paste0('h', ledger$horizon), levels=c('h1', 'h2'))
write.csv(ledger, file.path(out_dir, 'candidate_independent_ledger.csv'), row.names=FALSE)

fit_b1 <- function(tr) {
  tr$horizon_f <- factor(paste0('h', tr$horizon), levels=c('h1', 'h2'))
  tr$offset_logit <- tr$logit_current
  suppressWarnings(glm(cbind(y_target, N_target-y_target) ~ horizon_f + growth1 +
                         growth2 + offset(offset_logit), data=tr,
                       family=quasibinomial()))
}

one_ratio <- function(z, tau, h) {
  cur <- approx(z$tau, z$p_norm, xout=tau, rule=1)$y
  fut <- approx(z$tau, z$p_norm, xout=tau+h, rule=1)$y
  if (!is.finite(cur) || !is.finite(fut)) return(NA_real_)
  log(pmax(fut, .01) / pmax(cur, .01))
}

# Cache observed shape drift on a common grid. Inner family selection repeatedly
# scores overlapping training sets, so recomputing spline interpolation inside
# each candidate loop is needlessly expensive.
shape_tau_grid <- seq(-8, 8, by=.1)
shape_ratio_cache <- list()
for (s in seasons) for (tp in types) {
  z <- shape[shape$season == s & shape$type == tp, ]
  if (!nrow(z)) next
  for (h in 1:2) {
    shape_ratio_cache[[paste(s,tp,h,sep='|')]] <- vapply(shape_tau_grid, function(tau)
      one_ratio(z, tau, h), numeric(1))
  }
}

family_ratio <- function(train, tp, tau, h, fam) {
  pool <- shape[shape$season %in% train, ]
  typed <- pool[pool$type == tp, ]
  med_ratio <- function(dat) {
    ids <- unique(paste(dat$season, dat$type, sep='|'))
    vals <- vapply(ids, function(id) {
      z <- dat[paste(dat$season, dat$type, sep='|') == id, ]
      one_ratio(z, tau, h)
    }, numeric(1))
    vals <- vals[is.finite(vals)]
    if (length(vals)) median(vals) else NA_real_
  }
  lp <- med_ratio(pool)
  lt <- med_ratio(typed)
  switch(fam, C1=lp, C2=.5*lp + .5*lt, C3=lt)
}

blend_ratio <- function(base, current, lr, eta=.5) {
  if (!is.finite(lr)) return(base)
  p_shape <- pmin(pmax(current * exp(lr), 1e-6), 1-1e-6)
  plogis((1-eta) * logit(base) + eta * logit(p_shape))
}

# Causal B availability policy from the reviewed B timing prototype.
b_gate <- function(z, origin) {
  z <- z[z$weekF <= origin, , drop=FALSE]
  z <- z[order(z$weekF), , drop=FALSE]
  ix <- which(z$weekF == origin)
  if (length(ix) != 1L || origin < 18L) return(FALSE)
  from <- max(1L, ix - 3L)
  sum(z$y[from:ix], na.rm=TRUE) >= 40 && max(z$p[from:ix], na.rm=TRUE) >= .05
}

# A timing uses a prior-only M1-v2 curve library. Activation is the fixed
# causal start at week 13; the posterior receives only the target prefix.
make_library <- function(prior, tp) {
  train <- long[long$season %in% prior & long$type == tp,
                c('season','weekF','y','N','p')]
  truths <- geom[geom$type == tp & geom$season %in% prior,
                 c('season','peak_week_decimal')]
  if (length(unique(train$season)) < min_prior ||
      !setequal(unique(train$season), prior) || nrow(truths) != length(prior)) return(NULL)
  fit_m1_v2_library(train, truths, k=8L, grid_step=.01, tau_step=.1,
                    amplitude_grid=if (tp == 'A') seq(.08,.44,by=.02) else seq(.005,.25,by=.005))
}

timing_at_origin <- function(tp, season, origin, prior, lib) {
  if (is.null(lib)) return(list(available=FALSE, peak=NA_real_, width=NA_real_, reason='insufficient_prior_timing_library'))
  z <- long[long$season == season & long$type == tp, c('season','weekF','y','N','p')]
  z <- z[z$weekF <= origin, , drop=FALSE]
  if (tp == 'B' && !b_gate(long[long$season == season & long$type == 'B', ], origin))
    return(list(available=FALSE, peak=NA_real_, width=NA_real_, reason='reviewed_b_causal_gate_not_met'))
  ans <- tryCatch({
    pp <- m1_v2_passage_posterior(lib, z, activation_week=13,
                                   origin_week=origin, candidate_step=.2,
                                   max_future_weeks=12)
    post <- attr(pp, 'posterior')
    cdf <- cumsum(post$probability)
    list(available=TRUE, peak=sum(post$peak_week_decimal * post$probability),
         width=post$peak_week_decimal[which(cdf >= .95)[1]] -
           post$peak_week_decimal[which(cdf >= .05)[1]], reason='available')
  }, error=function(e) list(available=FALSE, peak=NA_real_, width=NA_real_,
                              reason=paste0('posterior_error:', conditionMessage(e))))
  ans
}

select_family <- function(prior) {
  if (length(prior) < 4L) return(list(family=NA_character_, scores=NULL,
                                      reason='inner_lopo_requires_four_prior_seasons'))
  score_rows <- list()
  for (v in prior) {
    fit_seasons <- setdiff(prior, v)
    if (length(fit_seasons) < min_prior) stop('Inner curve fit violates minimum prior seasons.')
    for (tp in types) for (h in 1:2) {
      vz <- shape[shape$season == v & shape$type == tp, ]
      taus <- vz$tau[vz$tau >= -8 & vz$tau <= 8-h]
      actual <- vapply(taus, function(tau) one_ratio(vz, tau, h), numeric(1))
      pool_keys <- as.vector(outer(fit_seasons, types, function(s,t) paste(s,t,h,sep='|')))
      typed_keys <- paste(fit_seasons, tp, h, sep='|')
      pool_mat <- do.call(rbind, shape_ratio_cache[pool_keys])
      typed_mat <- do.call(rbind, shape_ratio_cache[typed_keys])
      lp <- apply(pool_mat, 2, median, na.rm=TRUE)
      lt <- apply(typed_mat, 2, median, na.rm=TRUE)
      for (fam in families) {
        curve <- switch(fam, C1=lp, C2=.5*lp+.5*lt, C3=lt)
        estimate <- approx(shape_tau_grid, curve, xout=taus, rule=1)$y
        errors <- estimate-actual
        errors <- errors[is.finite(errors)]
        score_rows[[length(score_rows)+1L]] <- data.frame(
          target_season=NA_character_, validation_season=v, family=fam, type=tp,
          horizon=h, rmse_log_ratio=if(length(errors)) sqrt(mean(errors^2)) else NA_real_,
          n_tau=length(errors), stringsAsFactors=FALSE)
      }
    }
  }
  scores <- do.call(rbind, score_rows)
  agg <- aggregate(rmse_log_ratio ~ family, scores, mean, na.rm=TRUE)
  if (!nrow(agg) || any(!is.finite(agg$rmse_log_ratio)))
    return(list(family=NA_character_, scores=scores, reason='inner_scores_unavailable'))
  best <- agg$family[order(agg$rmse_log_ratio, match(agg$family, families))][1]
  list(family=best, scores=scores, reason='selected_by_prior_only_inner_lopo')
}

pred_rows <- list(); selections <- list(); family_scores <- list(); availability <- list()
for (oi in seq_along(seasons)) {
  target <- seasons[oi]
  prior <- if (oi > 1L) seasons[seq_len(oi-1L)] else character()
  cat('outer', target, 'prior=', length(prior), '\n')
  if (length(prior) < min_prior) {
    availability[[target]] <- data.frame(season=target, type=types, n_prior=length(prior),
      forecast_available=FALSE, timing_A_available=NA_real_, timing_B_available=NA_real_,
      family_available=FALSE, reason='fewer_than_three_prior_seasons', stringsAsFactors=FALSE)
    next
  }
  family <- select_family(prior)
  if (!is.null(family$scores)) {
    family$scores$target_season <- target
    family_scores[[target]] <- family$scores
  }
  selections[[target]] <- data.frame(season=target, n_prior=length(prior),
    selected_family=family$family, family_selection_reason=family$reason,
    stringsAsFactors=FALSE)

  fit_by_type <- setNames(vector('list', length(types)), types)
  lib_by_type <- setNames(vector('list', length(types)), types)
  for (tp in types) {
    tr <- ledger[ledger$season %in% prior & ledger$type == tp, ]
    te <- ledger[ledger$season == target & ledger$type == tp, ]
    fit <- fit_b1(tr)
    te$horizon_f <- factor(paste0('h', te$horizon), levels=c('h1','h2'))
    te$offset_logit <- te$logit_current
    te$pred_b1 <- as.numeric(predict(fit, newdata=te, type='response'))
    te$pred_C1 <- te$pred_C2 <- te$pred_C3 <- te$pred_b1
    lib <- make_library(prior, tp)
    timing_rows <- list()
    for (origin in unique(te$origin_week)) {
      tm <- timing_at_origin(tp, target, origin, prior, lib)
      timing_rows[[as.character(origin)]] <- data.frame(season=target, type=tp,
        origin_week=origin, timing_available=tm$available, timing_peak=tm$peak,
        timing_width=tm$width, timing_reason=tm$reason, stringsAsFactors=FALSE)
      if (!tm$available) next
      horizon_use <- if (tp == 'B') 2L else 1:2
      use <- which(te$origin_week == origin & te$horizon %in% horizon_use)
      if (!length(use)) next
      for (h in horizon_use) {
        ix <- use[te$horizon[use] == h]
        tau <- origin - tm$peak
        for (fam in families) {
          lr <- family_ratio(prior, tp, tau, h, fam)
          te[[paste0('pred_', fam)]][ix] <- vapply(ix, function(j)
            blend_ratio(te$pred_b1[j], te$p_star[j], lr), numeric(1))
        }
      }
    }
    timing <- do.call(rbind, timing_rows)
    te <- merge(te, timing, by=c('season','type','origin_week'), all.x=TRUE, sort=FALSE)
    te$timing_available[is.na(te$timing_available)] <- FALSE
    # B +1 is contractually identical to B1; unavailable timing also remains B1.
    te$pred_C1[!te$timing_available | (te$type == 'B' & te$horizon == 1L)] <-
      te$pred_b1[!te$timing_available | (te$type == 'B' & te$horizon == 1L)]
    te$pred_C2[!te$timing_available | (te$type == 'B' & te$horizon == 1L)] <-
      te$pred_b1[!te$timing_available | (te$type == 'B' & te$horizon == 1L)]
    te$pred_C3[!te$timing_available | (te$type == 'B' & te$horizon == 1L)] <-
      te$pred_b1[!te$timing_available | (te$type == 'B' & te$horizon == 1L)]
    te$selected_family <- family$family
    te$prior_seasons <- paste(prior, collapse=';')
    te$pred_selected <- te$pred_b1
    if (!is.na(family$family)) te$pred_selected <- te[[paste0('pred_', family$family)]]
    pred_rows[[paste(target,tp,sep='|')]] <- te
    availability[[paste(target,tp,sep='|')]] <- data.frame(
      season=target, type=tp, n_prior=length(prior), forecast_available=TRUE,
      timing_A_available=if(tp=='A') mean(te$timing_available) else NA_real_,
      timing_B_available=if(tp=='B') mean(te$timing_available) else NA_real_,
      family_available=!is.na(family$family), reason=family$reason, stringsAsFactors=FALSE)
  }
}

pred <- do.call(rbind, pred_rows)
rownames(pred) <- NULL
pred$abs_b1 <- abs(pred$pred_b1 - pred$p_target)
pred$sq_b1 <- (pred$pred_b1 - pred$p_target)^2
pred$nll_b1 <- -(pred$y_target*log(pmin(pmax(pred$pred_b1,1e-8),1-1e-8)) +
  (pred$N_target-pred$y_target)*log1p(-pmin(pmax(pred$pred_b1,1e-8),1-1e-8))) / pred$N_target
for (m in c('C1','C2','C3','selected')) {
  p <- pmin(pmax(pred[[paste0('pred_',m)]], 1e-8), 1-1e-8)
  pred[[paste0('abs_',m)]] <- abs(p-pred$p_target)
  pred[[paste0('sq_',m)]] <- (p-pred$p_target)^2
  pred[[paste0('nll_',m)]] <- -(pred$y_target*log(p) +
    (pred$N_target-pred$y_target)*log1p(-p)) / pred$N_target
}
write.csv(pred, file.path(out_dir, 'chronological_predictions.csv'), row.names=FALSE)

per <- do.call(rbind, lapply(split(pred, list(pred$season,pred$type,pred$horizon), drop=TRUE), function(z) {
  out <- data.frame(season=z$season[1], type=z$type[1], horizon=z$horizon[1],
    n=nrow(z), selected_family=z$selected_family[1],
    timing_availability=mean(z$timing_available), b1_mae_pp=100*mean(z$abs_b1),
    b1_rmse_pp=100*sqrt(mean(z$sq_b1)), b1_nll=mean(z$nll_b1),
    selected_mae_pp=100*mean(z$abs_selected), selected_rmse_pp=100*sqrt(mean(z$sq_selected)),
    selected_nll=mean(z$nll_selected))
  for (m in c('C1','C2','C3')) {
    out[[paste0(m,'_mae_pp')]] <- 100*mean(z[[paste0('abs_',m)]])
    out[[paste0(m,'_rmse_pp')]] <- 100*sqrt(mean(z[[paste0('sq_',m)]]))
    out[[paste0(m,'_nll')]] <- mean(z[[paste0('nll_',m)]])
  }
  out
}))
rownames(per) <- NULL
write.csv(per, file.path(out_dir, 'per_season_metrics.csv'), row.names=FALSE)
summary <- do.call(rbind, lapply(split(per, list(per$type,per$horizon), drop=TRUE), function(z) {
  data.frame(type=z$type[1], horizon=z$horizon[1], n_seasons=nrow(z),
    mean_timing_availability=mean(z$timing_availability),
    b1_mae_pp=mean(z$b1_mae_pp), selected_mae_pp=mean(z$selected_mae_pp),
    relative_mae_gain=1-mean(z$selected_mae_pp)/mean(z$b1_mae_pp),
    b1_rmse_pp=mean(z$b1_rmse_pp), selected_rmse_pp=mean(z$selected_rmse_pp),
    b1_nll=mean(z$b1_nll), selected_nll=mean(z$selected_nll),
    seasons_selected_better=sum(z$selected_mae_pp < z$b1_mae_pp))
}))
rownames(summary) <- NULL
write.csv(summary, file.path(out_dir, 'summary.csv'), row.names=FALSE)
write.csv(do.call(rbind, selections), file.path(out_dir, 'family_selection.csv'), row.names=FALSE)
if (length(family_scores)) write.csv(do.call(rbind, family_scores),
  file.path(out_dir, 'inner_family_scores.csv'), row.names=FALSE)
avail <- do.call(rbind, availability)
rownames(avail) <- NULL
write.csv(avail, file.path(out_dir, 'availability.csv'), row.names=FALSE)

script_arg <- grep('^--file=', commandArgs(trailingOnly=FALSE), value=TRUE)
script_path <- if (length(script_arg)) sub('^--file=', '', script_arg[1]) else
  'scripts/run_m2_ab_curve_ratio_chronological_c123_v1.R'
manifest <- c(
  paste0('script_sha256=', digest::digest(file=script_path, algo='sha256')),
  paste0('ab_sha256=', digest::digest(ab, algo='sha256')),
  paste0('long_sha256=', digest::digest(long, algo='sha256')),
  paste0('shape_sha256=', digest::digest(shape, algo='sha256')),
  paste0('geometry_sha256=', digest::digest(geom, algo='sha256')),
  paste0('season_order=', paste(seasons, collapse=';')),
  paste0('minimum_prior_seasons=', min_prior),
  'A_timing=prior-only M1-v2 library; fixed causal activation week 13; target prefix only',
  'B_timing=prior-only M1-v2 library; reviewed causal gate week>=18, trailing-4 positives>=40, max positivity>=0.05',
  'B_horizon_1=exact B1 by construction',
  'timing_unavailable=exact B1 by construction',
  'family_selection=inner leave-one-prior-season-out, equal-weight type x horizon x validation-season RMSE on log ratios',
  'no later-season nested replay artifacts read'
)
writeLines(manifest, file.path(out_dir, 'provenance.txt'))
cat('\nChronological selected-family summary\n'); print(summary, row.names=FALSE, digits=5)
cat('\nFamily selections\n'); print(do.call(rbind, selections), row.names=FALSE)
cat('\nAvailability\n'); print(avail, row.names=FALSE)
