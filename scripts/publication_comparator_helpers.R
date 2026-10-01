# Independent publication comparator helpers; no PAGe package imports.

pc_seasons <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18", "2018-19",
  "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
)
pc_exclusions <- c("2011-12", "2015-16", "2020-21", "2021-22")

pc_clip <- function(p) pmin(1 - 1e-12, pmax(1e-12, p))

pc_counts <- function(y, n) {
  if (!length(y) || length(y) != length(n) ||
    any(!is.finite(y) | !is.finite(n) | n <= 0 | y < 0 | y > n)) {
    stop("Invalid counts or missing targets")
  }
  invisible(TRUE)
}

pc_nll <- function(y, n, p) {
  pc_counts(y, n)
  if (length(p) != length(y) || any(!is.finite(p) | p < 0 | p > 1)) {
    stop("Invalid probabilities")
  }
  p <- pc_clip(p)
  sum(-y * log(p) - (n - y) * log1p(-p)) / sum(n)
}

pc_key <- function(season, week) paste(season, week, sep = ":")

pc_lookup <- function(d, season, week) {
  d[match(pc_key(season, week), pc_key(d$season, d$week)), , drop = FALSE]
}

pc_targets <- function(d, q) pc_lookup(d, q$season, q$origin + q$lead)

pc_training <- function(d, seasons, holdout) {
  if (any(seasons %in% c(holdout, pc_exclusions))) {
    stop("Forbidden held-out/excluded season in training")
  }
  if (!length(seasons) || !all(seasons %in% d$season)) {
    stop("Missing training seasons")
  }
  d[d$season %in% seasons, , drop = FALSE]
}

pc_features <- function(d, q) {
  current <- pc_lookup(d, q$season, q$origin)
  lagged <- pc_lookup(d, q$season, q$origin - 1L)
  if (anyNA(current$y) || anyNA(lagged$y)) stop("missing origin/lag")
  pc_counts(current$y, current$N)
  pc_counts(lagged$y, lagged$N)
  z <- qlogis(pc_clip(current$y / current$N))
  data.frame(
    horizon = factor(q$lead, levels = c(1L, 2L)),
    target_week = q$origin + q$lead, z = z,
    dz = z - qlogis(pc_clip(lagged$y / lagged$N))
  )
}

pc_pairs <- function(d) {
  q <- data.frame(season = rep(d$season, 2), origin = rep(d$week, 2),
    lead = rep(c(1L, 2L), each = nrow(d)))
  keys <- pc_key(d$season, d$week)
  keep <- pc_key(q$season, q$origin - 1L) %in% keys &
    pc_key(q$season, q$origin + q$lead) %in% keys
  q[keep, , drop = FALSE]
}

pc_persistence <- function(d, q) {
  x <- pc_lookup(d, q$season, q$origin)
  pc_counts(x$y, x$N)
  x$y / x$N
}

pc_naive <- function(train, q) {
  vapply(q$origin + q$lead, function(w) {
    x <- train[train$week == w, ]
    if (!nrow(x)) stop("Missing seasonal-naive support")
    pc_counts(x$y, x$N)
    (sum(x$y) + 0.5) / (sum(x$N) + 1)
  }, numeric(1))
}

pc_analogue <- function(train, current, q, k, window) {
  seasons <- sort(unique(train$season))
  vapply(seq_len(nrow(q)), function(i) {
    weeks <- seq.int(q$origin[i] - window + 1L, q$origin[i])
    x <- pc_lookup(current, q$season[i], weeks)
    pc_counts(x$y, x$N)
    z <- qlogis(pc_clip(x$y / x$N))
    target_week <- q$origin[i] + q$lead[i]
    distances <- vapply(seasons, function(s) {
      h <- pc_lookup(train, s, weeks)
      t <- pc_lookup(train, s, target_week)
      if (anyNA(h$y) || anyNA(t$y)) return(Inf)
      mean((qlogis(pc_clip(h$y / h$N)) - z)^2)
    }, numeric(1))
    available <- which(is.finite(distances))
    if (length(available) < k) stop("Insufficient analogue support")
    nearest <- order(distances, seasons)[seq_len(k)]
    t <- pc_lookup(train, seasons[nearest], target_week)
    sum(t$y) / sum(t$N)
  }, numeric(1))
}

pc_grid <- function(model) {
  if (model == "calendar") {
    g <- expand.grid(k_week = c(6L, 8L, 10L), k_signal = c(4L, 6L, 8L))
    g$id <- sprintf("week%02d_signal%02d", g$k_week, g$k_signal)
    # Two horizon-specific cyclic and four signal smooths.
    g$complexity <- 2 * (g$k_week - 2) + 4 * (g$k_signal - 1)
  } else if (model == "analogue") {
    g <- expand.grid(k = c(1L, 3L, 5L), window = c(4L, 6L, 8L))
    g$id <- sprintf("k%02d_window%02d", g$k, g$window)
    # More neighbours is smoother; shorter input window breaks complexity ties.
    g$complexity <- (5L - g$k) * 10L + g$window
  } else {
    stop("Unknown comparator")
  }
  g[order(g$complexity, g$id), , drop = FALSE]
}

pc_fit_calendar <- function(train, config) {
  q <- pc_pairs(train)
  x <- pc_features(train, q)
  target <- pc_targets(train, q)
  pc_counts(target$y, target$N)
  x$y <- target$y
  x$N <- target$N
  formula <- stats::as.formula(sprintf(paste0(
    "cbind(y, N-y) ~ horizon + ",
    "s(target_week, bs='cc', k=%d, by=horizon) + ",
    "s(z, bs='tp', k=%d, by=horizon) + ",
    "s(dz, bs='tp', k=%d, by=horizon)"
  ), config$k_week, config$k_signal, config$k_signal))
  fit <- mgcv::gam(formula, data = x, family = stats::binomial(),
    method = "REML", knots = list(target_week = c(0.5, 53.5)))
  if (!isTRUE(fit$converged)) stop("Calendar GAM did not converge")
  fit
}

pc_predict_calendar <- function(fit, d, q) {
  as.numeric(stats::predict(fit, newdata = pc_features(d, q), type = "response"))
}

pc_select <- function(grid, scores) {
  if (nrow(scores) != nrow(grid) || ncol(scores) < 2L ||
    any(!is.finite(scores))) stop("Inner scores must be complete and finite")
  means <- rowMeans(scores)
  best <- order(means, grid$complexity, grid$id)[1L]
  se <- stats::sd(scores[best, ]) / sqrt(ncol(scores))
  threshold <- means[best] + se
  eligible <- which(means <= threshold + 1e-14)
  chosen <- eligible[order(grid$complexity[eligible], grid$id[eligible])[1L]]
  list(id = grid$id[chosen], index = chosen, best_id = grid$id[best],
    best_index = best, threshold = threshold, se = se,
    mean_nll = means[chosen], minimum_nll = means[best])
}

pc_tune <- function(d, seasons, holdout, windows, model, grid = pc_grid(model)) {
  # Physically remove the outer target before any inner fit or selection.
  outer_train <- pc_training(d, seasons, holdout)
  scores <- matrix(NA_real_, nrow(grid), length(seasons),
    dimnames = list(grid$id, seasons))
  for (j in seq_along(seasons)) {
    s <- seasons[j]
    train <- pc_training(outer_train, setdiff(seasons, s), c(holdout, s))
    q <- windows[windows$season == s & windows$lead == 2L, , drop = FALSE]
    if (!nrow(q)) stop("Missing inner h2 evaluation rows")
    targets <- pc_targets(outer_train, q)
    for (i in seq_len(nrow(grid))) {
      if (model == "calendar") {
        fit <- pc_fit_calendar(train, grid[i, ])
        p <- pc_predict_calendar(fit, outer_train, q)
      } else {
        p <- pc_analogue(train, outer_train, q, grid$k[i], grid$window[i])
      }
      scores[i, j] <- pc_nll(targets$y, targets$N, p)
    }
  }
  list(selection = pc_select(grid, scores), scores = scores, grid = grid)
}

pc_read_data <- function(path) {
  raw <- utils::read.csv(path, stringsAsFactors = FALSE)
  if (!setequal(unique(raw$season), c(pc_seasons, pc_exclusions))) {
    stop("Input season universe mismatch")
  }
  n_weeks <- 52L + as.integer(MMWRweek::MMWRweek(
    as.Date(paste0(raw$seasonstart, "-12-31")))$MMWRweek == 53L)
  d <- data.frame(season = raw$season,
    week = ((raw$week - 27L) %% n_weeks) + 1L,
    y = raw$pos_flua, N = raw$test_flu)
  if (anyDuplicated(pc_key(d$season, d$week))) stop("Duplicate season-week")
  pc_counts(d$y, d$N)
  d <- d[d$season %in% pc_seasons, ]
  d[order(d$season, d$week), ]
}
