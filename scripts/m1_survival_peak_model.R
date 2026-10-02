sp_basis <- function(x, effect = c("gate", "hazard"), protocol = sp_protocol()) {
  effect <- match.arg(effect)
  z <- splines::ns(as.numeric(x), knots = protocol$spline_knots,
    Boundary.knots = protocol$spline_bounds, intercept = FALSE)
  expected <- if (effect == "gate") protocol$gate_df else protocol$hazard_df
  if (ncol(z) != expected) stop("Fixed natural-spline basis does not have declared df.", call. = FALSE)
  z
}

sp_design <- function(data, effect = c("gate", "hazard"), protocol = sp_protocol()) {
  effect <- match.arg(effect)
  f <- as.matrix(data[, protocol$feature_names, drop = FALSE])
  if (!all(is.finite(f))) stop("Nonfinite frozen features.", call. = FALSE)
  b <- if (effect == "gate") sp_basis(data$t, "gate", protocol) else sp_basis(data$k, "hazard", protocol)
  cbind(`(Intercept)` = 1, b, f)
}

sp_link_inv <- function(eta, link) {
  if (link == "logit") return(stats::plogis(eta))
  if (link == "cloglog") return(-expm1(-exp(pmin(eta, 30))))
  stop("Unknown hazard link.", call. = FALSE)
}

sp_clip_prob <- function(p, structural = FALSE, protocol = sp_protocol()) {
  if (isTRUE(structural)) return(p)
  n <- sum(!is.finite(p) | p < protocol$probability_clip | p > 1 - protocol$probability_clip)
  list(prob = pmin(1 - protocol$probability_clip, pmax(protocol$probability_clip, p)), clipped = n)
}

sp_penalty_expansion <- function(selected_lambda, candidates, expanded = FALSE, protocol = sp_protocol()) {
  values <- sort(unique(as.numeric(candidates))); add <- numeric()
  if (!expanded && selected_lambda == min(protocol$lambda)) add <- min(protocol$lambda) / 10
  if (!expanded && selected_lambda == max(protocol$lambda)) add <- max(protocol$lambda) * 10
  all_values <- sort(unique(c(values, add)))
  list(candidates = all_values, expanded = expanded || length(add) > 0L,
       unresolved = (expanded || length(add) > 0L) &&
         (selected_lambda == min(protocol$lambda) / 10 || selected_lambda == max(protocol$lambda) * 10 ||
          selected_lambda == min(all_values) || selected_lambda == max(all_values)), added = add)
}

sp_fit_logistic <- function(X, y, season, lambda, link = "logit", protocol = sp_protocol(), equal_season_rows = TRUE, unit = NULL) {
  X <- as.matrix(X); y <- as.integer(y); season <- as.character(season)
  if (length(y) != nrow(X) || length(season) != length(y) || !length(y) || anyNA(y) || any(!y %in% 0:1))
    stop("Invalid binary fitting rows.", call. = FALSE)
  if (!is.finite(lambda) || lambda <= 0) stop("lambda must be positive.", call. = FALSE)
  if (is.null(unit)) unit <- seq_along(y)
  unit <- as.character(unit)
  if (length(unit) != length(y) || anyNA(unit) || any(!is.finite(X))) stop("Invalid fitting units or nonfinite design.", call. = FALSE)
  if (length(unique(y)) < 2L) {
    unit_mean <- tapply(y, paste(season, unit, sep = "\034"), mean)
    unit_season <- strsplit(names(unit_mean), "\034", fixed = TRUE)
    unit_tab <- data.frame(season = vapply(unit_season, `[[`, character(1), 1L), response = as.numeric(unit_mean))
    season_mean <- tapply(unit_tab$response, unit_tab$season, mean)
    # Jeffreys smoothing uses seasons as independent units, never person-weeks or landmarks.
    p <- (mean(season_mean) * length(season_mean) + 0.5) / (length(season_mean) + 1)
    return(list(kind = "jeffreys_intercept", probability = p, link = link, lambda = lambda,
      events = sum(y), rows = length(y), seasons = sort(unique(season)),
      effective_units = length(season_mean), effective_unit = "season"))
  }
  season_levels <- sort(unique(season))
  if (equal_season_rows) {
    key <- paste(season, unit, sep = "\034")
    unit_rows <- table(key)
    unique_units <- !duplicated(key)
    units_per_season <- table(season[unique_units])
    wi <- 1 / length(season_levels) /
      as.numeric(units_per_season[season]) /
      as.numeric(unit_rows[key])
  } else wi <- rep(1 / length(season_levels), length(season))
  penalty <- rep(lambda, ncol(X)); penalty[1L] <- 0
  objective <- function(beta) {
    eta <- as.vector(X %*% beta)
    p <- sp_link_inv(eta, link)
    p <- pmin(1 - 1e-12, pmax(1e-12, p))
    -sum(wi * (y * log(p) + (1 - y) * log1p(-p))) + 0.5 * sum(penalty * beta^2)
  }
  opt <- stats::optim(rep(0, ncol(X)), objective, method = "BFGS", control = list(maxit = 5000, reltol = 1e-11))
  if (opt$convergence != 0L || any(!is.finite(opt$par))) stop("Ridge logistic optimizer failed.", call. = FALSE)
  list(kind = "ridge", coef = opt$par, link = link, lambda = lambda, events = sum(y), rows = length(y),
    seasons = season_levels, objective = opt$value, convergence = opt$convergence)
}

sp_predict_logistic <- function(fit, X) {
  if (identical(fit$kind, "jeffreys_intercept")) return(rep(fit$probability, nrow(X)))
  as.vector(sp_link_inv(as.vector(as.matrix(X) %*% fit$coef), fit$link))
}

sp_hazard_risk_rows <- function(landmarks) {
  x <- as.data.frame(landmarks, stringsAsFactors = FALSE)
  if (!all(c("season", "t", "K", "W") %in% names(x))) stop("Landmarks require season,t,K,W.", call. = FALSE)
  if (any(x$K < 1 | x$K > x$W | x$t < 1 | x$t > x$W)) stop("Invalid risk support.", call. = FALSE)
  rows <- list()
  for (i in seq_len(nrow(x))) if (x$K[i] > x$t[i]) {
    # A landmark exits the risk set at its event; no post-event rows are contributed.
    ks <- seq.int(x$t[i] + 1L, x$K[i]); rows[[length(rows) + 1L]] <- data.frame(
      season = as.character(x$season[i]), t = as.integer(x$t[i]), K = as.integer(x$K[i]),
      W = as.integer(x$W[i]), k = as.integer(ks), event = as.integer(ks == x$K[i]), stringsAsFactors = FALSE)
  }
  if (!length(rows)) return(data.frame(season=character(), t=integer(), K=integer(), W=integer(), k=integer(), event=integer()))
  do.call(rbind, rows)
}

sp_labels_for_training <- function(features, labels) {
  lab <- as.data.frame(labels, stringsAsFactors = FALSE)
  if (!all(c("season", "K", "W") %in% names(lab)) || anyDuplicated(lab$season)) stop("Training labels require unique season,K,W.", call. = FALSE)
  if (any(!is.finite(lab$K) | lab$K!=as.integer(lab$K) | !is.finite(lab$W) | lab$W!=as.integer(lab$W) |
      !lab$W%in%c(52L,53L) | lab$K<1L | lab$K>lab$W)) stop("Training peak labels are outside integer calendar support.",call.=FALSE)
  if ("mature"%in%names(lab) && any(!lab$mature)) stop("Immature seasonal maxima cannot train the peak model.",call.=FALSE)
  if (anyDuplicated(features[c("season","weekF")])) stop("Duplicate feature season/origin rows.",call.=FALSE)
  if (any(!features$season %in% lab$season)) stop("Feature season lacks allowed label.", call. = FALSE)
  z <- lab[match(features$season, lab$season), c("season", "K", "W"), drop = FALSE]
  cbind(features, K = z$K, W = z$W)
}

sp_fit_components <- function(features, labels, lambda, link = "logit", protocol = sp_protocol()) {
  d <- sp_labels_for_training(features, labels)
  gate_X <- sp_design(transform(d, t = weekF), "gate", protocol)
  gate <- sp_fit_logistic(gate_X, as.integer(d$K <= d$weekF), d$season, lambda, "logit", protocol)
  rr <- sp_hazard_risk_rows(data.frame(season=d$season,t=d$weekF,K=d$K,W=d$W))
  # K=W is represented by the structural terminal hazard, never a fitted event coefficient.
  if (nrow(rr)) rr <- rr[rr$k < rr$W, , drop=FALSE]
  if (nrow(rr)) {
    ix <- match(paste(rr$season, rr$t), paste(d$season, d$weekF))
    hzdata <- cbind(rr, d[ix, protocol$feature_names, drop=FALSE])
    hzdata$landmark_id <- paste(hzdata$season, hzdata$t, sep = "\034")
    hz <- sp_fit_logistic(sp_design(hzdata, "hazard", protocol), hzdata$event, hzdata$season, lambda, link, protocol,
                          equal_season_rows=TRUE, unit=hzdata$landmark_id)
  } else hz <- list(kind="jeffreys_intercept", probability=0.5/(length(unique(d$season))+1), link=link, lambda=lambda,
                    events=0L, rows=0L, seasons=sort(unique(d$season)), effective_units=length(unique(d$season)), effective_unit="season")
  list(gate=gate,hazard=hz,lambda=lambda,link=link,training_seasons=sort(unique(d$season)),prior=sp_past_prior(labels))
}

sp_past_prior <- function(labels, pseudocount = 0.5) {
  z <- as.data.frame(labels); if (!all(c("K", "W") %in% names(z)) || !nrow(z)) stop("Prior requires allowed K,W labels.", call. = FALSE)
  maxW <- 53L; counts <- tabulate(as.integer(z$K), nbins=maxW) + pseudocount
  list(counts=counts, maxW=maxW, pseudocount=pseudocount, seasons=sort(as.character(z$season)))
}

sp_past_pmf <- function(prior, t, W) {
  if (t < 1L || W < t || W > prior$maxW) stop("Invalid past support.", call. = FALSE)
  z <- prior$counts[seq_len(t)]; z / sum(z)
}

sp_future_pmf <- function(hazard_prob) {
  h <- as.numeric(hazard_prob)
  if (!length(h) || any(!is.finite(h)) || any(h < 0 | h > 1)) stop("Invalid hazard probabilities.", call. = FALSE)
  h[length(h)] <- 1
  if (length(h) == 1L) return(1)
  logsurv <- c(0, cumsum(log1p(-pmin(h[-length(h)], 1 - 1e-16))))
  q <- exp(logsurv) * h
  if (abs(sum(q) - 1) > 1e-10) stop("Future PMF failed mass conservation.", call. = FALSE)
  q
}

sp_mix_pmf <- function(pi, past_support, q_minus, future_support, q_plus) {
  if (length(pi)!=1L || !is.finite(pi) || pi<0 || pi>1 || length(past_support)!=length(q_minus) || length(future_support)!=length(q_plus))
    stop("Invalid mixture components.",call.=FALSE)
  if (!all(is.finite(q_minus)) || !all(is.finite(q_plus)) || any(q_minus < 0) || any(q_plus < 0) ||
      any(!is.finite(past_support)) || any(!is.finite(future_support)) ||
      any(past_support>=future_support[1L]) || any(diff(past_support)!=1L) || any(diff(future_support)!=1L))
    stop("Mixture supports must be ordered contiguous and disjoint.",call.=FALSE)
  if (abs(sum(q_minus)-1)>1e-10 || abs(sum(q_plus)-1)>1e-10) stop("Conditional components must each normalize.",call.=FALSE)
  p <- c(pi*q_minus,(1-pi)*q_plus); names(p)<-as.character(c(past_support,future_support))
  if (abs(sum(p)-1)>1e-10) stop("Mixture failed normalization.",call.=FALSE)
  p
}

sp_predict_distribution <- function(fit, feature, W, protocol = sp_protocol()) {
  t <- as.integer(feature$weekF)
  if (length(W) != 1L || !is.finite(W) || W != as.integer(W) || !W %in% c(52L, 53L) ||
      (!is.null(feature$W) && as.integer(feature$W) != as.integer(W))) stop("Prediction calendar metadata mismatch.", call. = FALSE)
  if (t < protocol$min_origin || t > W) stop("Prediction origin outside calendar metadata.", call. = FALSE)
  if (t == W) {
    past <- sp_past_pmf(fit$prior, t, W); names(past) <- as.character(seq_len(t))
    return(list(pmf = past, pi = 1, q_minus = past, q_plus = numeric(), clipping = list(gate = 0L, hazard = 0L)))
  }
  gd <- transform(feature, t = weekF)
  p_raw <- sp_predict_logistic(fit$gate, sp_design(gd, "gate", protocol))
  pc <- sp_clip_prob(p_raw, protocol = protocol); pi <- pc$prob[1L]
  past <- sp_past_pmf(fit$prior, t, W); ks <- seq.int(t + 1L, W)
  hd <- data.frame(k = ks, as.list(feature[1, protocol$feature_names, drop = FALSE]), check.names = FALSE)
  hp_raw <- sp_predict_logistic(fit$hazard, sp_design(hd, "hazard", protocol))
  hc <- sp_clip_prob(hp_raw, protocol = protocol); hp <- hc$prob; hp[length(hp)] <- 1
  future <- sp_future_pmf(hp)
  pmf <- sp_mix_pmf(pi, seq_len(t), past, ks, future); names(pmf) <- as.character(c(seq_len(t), ks))
  if (abs(sum(pmf) - 1) > protocol$normalization_tolerance) stop("Mixture PMF normalization failure.", call. = FALSE)
  list(pmf = pmf, pi = pi, q_minus = setNames(past, as.character(seq_len(t))), q_plus = setNames(future, as.character(ks)),
       clipping = list(gate = pc$clipped, hazard = hc$clipped))
}

sp_select_and_fit <- function(features, labels, protocol = sp_protocol(),
                              candidates = expand.grid(lambda = protocol$lambda, link = protocol$links),
                              calendar_metadata = NULL) {
  seasons <- sort(unique(as.character(labels$season)))
  if (length(seasons) < 2L) stop("LOSO tuning requires at least two allowed seasons.", call. = FALSE)
  if (is.null(calendar_metadata)) stop("Model selection requires independent calendar metadata.", call. = FALSE)
  calendar <- sp_calendar_from_metadata(calendar_metadata)
  if (!all(seasons %in% names(calendar))) stop("Selection calendar does not cover allowed seasons.", call. = FALSE)
  candidates <- unique(data.frame(lambda = as.numeric(candidates$lambda), link = as.character(candidates$link), stringsAsFactors = FALSE))
  if (!nrow(candidates) || any(!is.finite(candidates$lambda) | candidates$lambda <= 0) || any(!candidates$link %in% protocol$links)) stop("Invalid candidate grid.", call. = FALSE)
  score_grid <- function(grid) {
    rows <- list()
    for (j in seq_len(nrow(grid))) {
      cand <- grid[j, ]; season_loss <- setNames(rep(NA_real_, length(seasons)), seasons)
      for (s in seasons) {
        tr_s <- setdiff(seasons, s); tr_lab <- labels[labels$season %in% tr_s, , drop = FALSE]
        tr_f <- features[features$season %in% tr_s, , drop = FALSE]
        ev_lab <- labels[labels$season == s, , drop = FALSE]; ev_f <- features[features$season == s, , drop = FALSE]
        scaled <- sp_scale_features(tr_f, ev_f, tr_s, protocol)
        mod <- sp_fit_components(scaled$train, tr_lab, cand$lambda, cand$link, protocol)
        W <- unname(calendar[[s]])
        losses <- vapply(seq_len(nrow(ev_f)), function(i) {
          dist <- sp_predict_distribution(mod, scaled$predict[i, , drop = FALSE], W, protocol)
          -log(max(dist$pmf[as.character(ev_lab$K[1L])], protocol$probability_clip))
        }, numeric(1))
        season_loss[s] <- mean(losses)
      }
      rows[[j]] <- data.frame(lambda = cand$lambda, link = cand$link, season = seasons, loss = season_loss, stringsAsFactors = FALSE)
    }
    do.call(rbind, rows)
  }
  score <- score_grid(candidates); expanded <- FALSE
  select_grid <- function(score) {
    means <- aggregate(loss ~ lambda + link, score, mean)
    means <- means[order(means$loss, -means$lambda, match(means$link, protocol$links)), , drop = FALSE]
    best <- means[1L, , drop = FALSE]; best_rows <- score[score$lambda == best$lambda & score$link == best$link, , drop = FALSE]
    acceptable <- vapply(seq_len(nrow(means)), function(i) {
      z <- merge(best_rows, score[score$lambda == means$lambda[i] & score$link == means$link[i], , drop = FALSE],
                 by = "season", suffixes = c(".best", ".candidate"))
      d <- z$loss.candidate - z$loss.best
      mean(d) <= stats::sd(d) / sqrt(length(d)) + 1e-12
    }, logical(1))
    elig <- means[acceptable, , drop = FALSE]
    elig[order(-elig$lambda, match(elig$link, protocol$links), elig$loss), , drop = FALSE][1L, , drop = FALSE]
  }
  selected <- select_grid(score); plan <- sp_penalty_expansion(selected$lambda, candidates$lambda, expanded, protocol)
  if (length(plan$added)) {
    expanded <- TRUE
    candidates <- unique(rbind(candidates, data.frame(lambda = rep(plan$added, each = length(protocol$links)),
      link = rep(protocol$links, times = length(plan$added)), stringsAsFactors = FALSE)))
    score <- score_grid(candidates); selected <- select_grid(score)
    plan <- sp_penalty_expansion(selected$lambda, candidates$lambda, TRUE, protocol)
  }
  unresolved <- isTRUE(plan$unresolved)
  scaled <- sp_scale_features(features, features, seasons, protocol)
  fit <- sp_fit_components(scaled$train, labels, selected$lambda, selected$link, protocol)
  list(fit = fit, scaler = scaled$scaler, selected = selected, scores = score,
       allowed_seasons = seasons, boundary_expanded = expanded, boundary_unresolved = unresolved)
}
