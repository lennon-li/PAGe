nh_logit <- function(p, eps = 1e-6) {
  stats::qlogis(pmin(1 - eps, pmax(eps, as.numeric(p))))
}

nh_assert_unique_week_keys <- function(data) {
  key <- paste(as.character(data$season), as.integer(data$weekF), sep = "\r")
  if (anyDuplicated(key)) {
    stop("Duplicate (season, weekF) keys are not allowed.", call. = FALSE)
  }
  invisible(TRUE)
}

nh_raw_ledger <- function(data, protocol = nh_protocol()) {
  required <- c("season", "weekF", "y", "N")
  missing <- setdiff(required, names(data))
  if (length(missing)) {
    stop("Raw ledger data missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  week_raw <- suppressWarnings(as.numeric(data$weekF))
  if (any(!is.finite(week_raw)) || any(week_raw != as.integer(week_raw))) {
    stop("Raw ledger weekF values must be finite integers.", call. = FALSE)
  }
  data$season <- as.character(data$season)
  data$weekF <- as.integer(week_raw)
  if (anyNA(data$season) || any(!nzchar(data$season)) || anyNA(data$weekF)) {
    stop("Raw ledger season/weekF keys must be non-missing and integer-valued.", call. = FALSE)
  }
  data <- data[data$season %in% protocol$principal_seasons, , drop = FALSE]
  nh_assert_unique_week_keys(data)
  missing_seasons <- setdiff(protocol$principal_seasons, unique(data$season))
  if (length(missing_seasons)) {
    stop("Raw ledger is missing principal season(s): ", paste(missing_seasons, collapse = ", "), call. = FALSE)
  }
  out <- list()
  for (s in protocol$principal_seasons) {
    ds <- data[data$season == s, , drop = FALSE]
    weeks <- sort(unique(as.integer(ds$weekF)))
    for (origin in weeks[weeks >= protocol$min_origin_weekF]) {
      for (h in protocol$horizons) {
        target <- origin + h
        needed <- origin - protocol$required_history_offsets
        source_weeks <- sort(unique(c(needed, protocol$required_anchor_weekF)))
        source_present <- source_weeks %in% weeks
        target_present <- target %in% weeks
        history_complete <- all(needed %in% weeks)
        week8_present <- protocol$required_anchor_weekF %in% weeks
        forecast_eligible <- history_complete && week8_present
        if (target_present) {
          obs <- ds[match(target, ds$weekF), , drop = FALSE]
          y_target <- as.numeric(obs$y)
          N_target <- as.numeric(obs$N)
        } else {
          y_target <- NA_real_
          N_target <- NA_real_
        }
        target_valid <- target_present && is.finite(y_target) && is.finite(N_target) &&
          N_target > 0 && y_target >= 0 && y_target <= N_target
        row <- data.frame(
          row_season = s,
          origin_weekF = origin,
          horizon = h,
          target_weekF = target,
          required_source_weeks = paste(source_weeks, collapse = "|"),
          history_complete = history_complete,
          week8_present = week8_present,
          target_present = target_present,
          target_valid = target_valid,
          forecast_eligible = forecast_eligible,
          common_eligible = forecast_eligible,
          target_scoreable = target_valid,
          common_scoreable = forecast_eligible && target_valid,
          dropped_reason = if (forecast_eligible) NA_character_ else paste(source_weeks[!source_present], collapse = "|"),
          scoreability_reason = if (target_valid) NA_character_ else if (!target_present) "missing_target" else "invalid_target",
          y_target = y_target,
          N_target = N_target,
          stringsAsFactors = FALSE
        )
        out[[length(out) + 1L]] <- row
      }
    }
  }
  if (!length(out)) {
    stop("Raw ledger produced no scheduled forecasts for the declared principal seasons.", call. = FALSE)
  }
  ans <- do.call(rbind, out)
  ans$row_key <- paste(ans$row_season, ans$origin_weekF, ans$horizon, sep = "|")
  ans
}

nh_exp_change <- function(dv, lambda) {
  w <- lambda^(0:3)
  sum(dv * w) / sum(w)
}

nh_add_n_features <- function(rows, raw_data, protocol = nh_protocol(), require_common = TRUE) {
  rows <- as.data.frame(rows)
  if (!nrow(rows)) {
    return(rows)
  }
  raw <- as.data.frame(raw_data)
  nh_assert_unique_week_keys(raw)
  key <- paste(raw$season, raw$weekF, sep = "\r")
  out <- rows
  add_cols <- c(
    "n_d1", "n_d2", "n_d3", "n_d4", "n_exp025", "n_exp050",
    "n_exp075", "n_exp100", "n_recent2", "n_older2", "n_accel22",
    "n_rel8", "growth1", "n_exp050_x_growth1"
  )
  for (nm in add_cols) out[[nm]] <- NA_real_
  out$n_feature_status <- "missing"
  out$n_feature_reason <- NA_character_
  for (i in seq_len(nrow(out))) {
    s <- as.character(out$row_season[i] %||% out$season[i])
    origin <- as.integer(out$origin_weekF[i] %||% out$eval_weekF[i])
    weeks <- c(origin - 4L, origin - 3L, origin - 2L, origin - 1L, origin, 8L)
    idx <- match(paste(s, weeks, sep = "\r"), key)
    if (any(is.na(idx))) {
      out$n_feature_reason[i] <- "missing_required_keyed_week"
      next
    }
    src <- raw[idx, , drop = FALSE]
    if (any(!is.finite(src$N)) || any(src$N <= 0) ||
      any(!is.finite(src$y)) || any(src$y < 0) || any(src$y > src$N)) {
      out$n_feature_reason[i] <- "invalid_required_y_or_N"
      next
    }
    n_hist <- as.numeric(src$N[1:5])
    l <- log(n_hist)
    dv <- c(l[5] - l[4], l[4] - l[3], l[3] - l[2], l[2] - l[1])
    recent2 <- mean(dv[1:2])
    older2 <- mean(dv[3:4])
    p_now <- (src$y[5] + 0.5) / (src$N[5] + 1)
    p_prev <- (src$y[4] + 0.5) / (src$N[4] + 1)
    g1 <- stats::qlogis(p_now) - stats::qlogis(p_prev)
    out$n_d1[i] <- dv[1L]
    out$n_d2[i] <- dv[2L]
    out$n_d3[i] <- dv[3L]
    out$n_d4[i] <- dv[4L]
    out$n_exp025[i] <- nh_exp_change(dv, 0.25)
    out$n_exp050[i] <- nh_exp_change(dv, 0.50)
    out$n_exp075[i] <- nh_exp_change(dv, 0.75)
    out$n_exp100[i] <- nh_exp_change(dv, 1.00)
    out$n_recent2[i] <- recent2
    out$n_older2[i] <- older2
    out$n_accel22[i] <- recent2 - older2
    out$n_rel8[i] <- log(src$N[5]) - log(src$N[6])
    out$growth1[i] <- g1
    out$n_exp050_x_growth1[i] <- out$n_exp050[i] * g1
    out$n_feature_status[i] <- "ok"
  }
  if (isTRUE(require_common)) {
    out <- out[out$n_feature_status == "ok", , drop = FALSE]
  }
  rownames(out) <- NULL
  out
}

nh_validate_common_ledger <- function(rows) {
  required <- c("row_season", "origin_weekF", "horizon", "target_weekF")
  missing <- setdiff(required, names(rows))
  if (length(missing)) {
    stop("Common ledger missing key column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  key <- paste(rows$row_season, rows$origin_weekF, rows$horizon, sep = "\r")
  if (anyDuplicated(key)) {
    stop("Common ledger has duplicate forecast keys.", call. = FALSE)
  }
  if (!all(rows$origin_weekF >= 13L)) {
    stop("Common ledger contains origin weekF < 13.", call. = FALSE)
  }
  invisible(TRUE)
}

nh_validate_stage_b_fields <- function(rows) {
  required <- c("m1_p_hat", "peak_weekF_origin", "peak_weekF_lo", "peak_weekF_hi")
  missing <- setdiff(required, names(rows))
  if (length(missing)) {
    stop("Stage B requires causal M1 peak/CI field(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  width <- as.numeric(rows$peak_weekF_hi) - as.numeric(rows$peak_weekF_lo)
  bad <- !is.finite(rows$m1_p_hat) |
    !is.finite(rows$peak_weekF_origin) |
    !is.finite(rows$peak_weekF_lo) |
    !is.finite(rows$peak_weekF_hi) |
    !is.finite(width) | width < 0
  if (any(bad)) {
    stop("Stage B causal peak/CI fields are missing or invalid.", call. = FALSE)
  }
  invisible(TRUE)
}

nh_reconstruct_features <- function(row, raw_data) {
  z <- nh_add_n_features(row, raw_data, require_common = TRUE)
  z[1L, c(
    "n_d1", "n_d2", "n_d3", "n_d4", "n_exp025", "n_exp050",
    "n_exp075", "n_exp100", "n_accel22", "n_rel8", "growth1"
  ), drop = FALSE]
}

nh_make_synthetic_panel <- function(seasons = c("s1", "s2", "s3", "s4"), weeks = 8:22) {
  out <- list()
  for (si in seq_along(seasons)) {
    for (w in weeks) {
      n <- 100 + si * 7 + w
      p <- pmin(0.8, pmax(0.02, 0.04 + 0.025 * (w - min(weeks)) + si * 0.002))
      out[[length(out) + 1L]] <- data.frame(
        season = seasons[si],
        weekF = w,
        y = round(n * p),
        N = n,
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, out)
}
