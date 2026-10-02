sp_build_features <- function(observations, season, t, W, protocol = sp_protocol()) {
  x <- as.data.frame(observations, stringsAsFactors = FALSE)
  need <- c("season", "weekF", "y", "N")
  if (!all(need %in% names(x))) stop("Observations require season, weekF, y, N.", call. = FALSE)
  x <- x[as.character(x$season) == as.character(season), , drop = FALSE]
  if (anyDuplicated(x$weekF)) stop("Duplicate season/weekF keys.", call. = FALSE)
  if (length(W) != 1L || !is.finite(W) || W != as.integer(W) || W < 1L || W > 53L)
    stop("W must be an explicit integer calendar length.", call. = FALSE)
  if (length(t) != 1L || t != as.integer(t) || t < protocol$min_origin || t > W)
    stop("Origin outside scheduled calendar domain.", call. = FALSE)
  if (!t %in% x$weekF) stop("Scheduled origin week is unobserved.", call. = FALSE)
  if (any(!is.finite(x$weekF) | x$weekF != as.integer(x$weekF) | x$weekF < 1L | x$weekF > W))
    stop("Observed weekF outside explicit calendar domain.", call. = FALSE)
  # Future rows are intentionally removed before inspecting their outcomes/counts.
  x <- x[x$weekF <= t, , drop = FALSE]
  missing <- is.na(x$y) | is.na(x$N)
  if (any(is.nan(x$y) | is.nan(x$N) | is.infinite(x$y) | is.infinite(x$N))) stop("Counts must be finite when observed.",call.=FALSE)
  bad <- !missing & (x$N <= 0 | x$y < 0 | x$y > x$N)
  if (any(bad)) stop("Counts must be finite with N > 0 and 0 <= y <= N.", call. = FALSE)
  x <- x[!missing,,drop=FALSE]
  if (nrow(x) < 4L) stop("At least four valid prefix weeks are required.", call. = FALSE)
  xi <- x$weekF %in% (t - 3L):t
  if (sum(xi) != 4L || !all((t - 3L):t %in% x$weekF))
    stop("Slope requires contiguous calendar weeks t-3..t.", call. = FALSE)
  L <- log((x$y + 0.5) / (x$N - x$y + 0.5))
  ord <- order(x$weekF); x <- x[ord, , drop = FALSE]; L <- L[ord]
  cur <- match(t, x$weekF); prev <- match(t - 3L, x$weekF)
  top <- which(L == max(L)); peak_week <- min(x$weekF[top])
  data.frame(season = as.character(season), weekF = as.integer(t), W = as.integer(W),
    level = L[cur], slope3 = (L[cur] - L[prev]) / 3,
    weeks_since_max = as.integer(t - peak_week), drawdown = L[cur] - max(L),
    valid_prefix_weeks = nrow(x), stringsAsFactors = FALSE)
}

sp_build_panel <- function(observations, calendars, protocol = sp_protocol()) {
  sp_validate_calendar(calendars)
  x <- as.data.frame(observations, stringsAsFactors = FALSE)
  if (anyDuplicated(x[c("season", "weekF")])) stop("Duplicate season/weekF keys.", call. = FALSE)
  rows <- list()
  for (s in intersect(names(calendars), unique(as.character(x$season)))) {
    W <- unname(calendars[[s]])
    origins <- sort(unique(x$weekF[x$season == s & x$weekF >= protocol$min_origin & x$weekF <= W]))
    for (t in origins) rows[[length(rows) + 1L]] <- sp_build_features(x, s, t, W, protocol)
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

sp_build_origin_ledgers <- function(observations, calendars, protocol = sp_protocol()) {
  sp_validate_calendar(calendars)
  x <- as.data.frame(observations, stringsAsFactors = FALSE)
  scheduled <- eligible <- unavailable <- list()
  for (s in names(calendars)) for (t in seq.int(protocol$min_origin, calendars[[s]])) {
    key <- data.frame(season = s, origin = as.integer(t), W = as.integer(calendars[[s]]), stringsAsFactors = FALSE)
    scheduled[[length(scheduled) + 1L]] <- key
    reason <- NULL; feature <- tryCatch(sp_build_features(x, s, t, calendars[[s]], protocol), error = function(e) {
      reason <<- conditionMessage(e); NULL
    })
    if (is.null(feature)) unavailable[[length(unavailable) + 1L]] <- transform(key, reason = reason)
    else {
      eligible[[length(eligible) + 1L]] <- key
    }
  }
  bind <- function(z) if (length(z)) do.call(rbind, z) else data.frame()
  list(scheduled = bind(scheduled), eligible = bind(eligible), unavailable = bind(unavailable))
}

sp_scale_features <- function(train, predict, allowed_seasons, protocol = sp_protocol()) {
  tr <- as.data.frame(train); pr <- as.data.frame(predict); cols <- protocol$feature_names
  if (!all(c("season", cols) %in% names(tr)) || !all(cols %in% names(pr))) stop("Missing feature columns.", call. = FALSE)
  if (!setequal(unique(as.character(tr$season)), as.character(allowed_seasons))) stop("Scaler seasons do not equal allowed set.", call. = FALSE)
  if (!all(is.finite(as.matrix(tr[, cols, drop = FALSE]))) || !all(is.finite(as.matrix(pr[, cols, drop = FALSE]))))
    stop("Feature matrix contains NA, NaN, or Inf before scaling.", call. = FALSE)
  season_n <- table(tr$season); weights <- 1 / as.numeric(season_n[tr$season]); weights <- weights / sum(weights)
  center <- vapply(cols, function(nm) sum(tr[[nm]] * weights), numeric(1))
  scale <- vapply(cols, function(nm) sqrt(sum(weights * (tr[[nm]] - center[[nm]])^2)), numeric(1))
  zero <- scale == 0
  scale[zero] <- 1
  scaler <- list(center=center,scale=scale,zero_variance=setNames(zero,cols),allowed_seasons=sort(as.character(allowed_seasons)))
  list(train = sp_apply_feature_scaler(tr,scaler,protocol), predict = sp_apply_feature_scaler(pr,scaler,protocol),
    center = center, scale = scale, zero_variance = setNames(zero, cols),
    allowed_seasons = sort(as.character(allowed_seasons)),scaler=scaler)
}

sp_apply_feature_scaler <- function(data, scaler, protocol=sp_protocol()) {
  d <- as.data.frame(data); cols <- protocol$feature_names
  if (!all(cols%in%names(d))) stop("Missing raw feature columns for scaling.",call.=FALSE)
  if (!all(is.finite(as.matrix(d[, cols, drop = FALSE])))) stop("Feature matrix contains NA, NaN, or Inf before scaling.", call. = FALSE)
  for (nm in cols) d[[nm]] <- if (isTRUE(scaler$zero_variance[[nm]])) 0 else (d[[nm]]-scaler$center[[nm]])/scaler$scale[[nm]]
  d
}
