# Shared forecast-target availability contract.

.page_forecast_availability <- function(target_weekF, target_newWeek,
                                        nW_true = 52L, template_weeks = .page_template_weeks()) {
  target_weekF <- as.numeric(target_weekF)
  target_newWeek <- as.numeric(target_newWeek)
  nW_true <- rep(as.numeric(nW_true), length.out = length(target_weekF))
  in_season <- is.finite(target_weekF) & is.finite(nW_true) &
    target_weekF >= 1 & target_weekF <= nW_true
  in_support <- is.finite(target_newWeek) & target_newWeek >= 1 &
    target_newWeek <= as.numeric(template_weeks)
  available <- in_season & in_support
  reason <- rep(NA_character_, length(target_weekF))
  reason[!is.finite(target_weekF) | !is.finite(target_newWeek)] <-
    "alignment_unavailable"
  reason[!in_season & is.finite(target_weekF)] <- "out_of_season"
  reason[in_season & !in_support] <- "aligned_week_outside_template_support"
  data.frame(
    forecast_available = available,
    unavailable_reason = reason,
    target_in_season = in_season,
    aligned_in_support = in_support,
    stringsAsFactors = FALSE
  )
}

.page_nw_true <- function(data, season_col = "season", week_col = "weekF") {
  if (!is.data.frame(data) || !all(c(season_col, week_col) %in% names(data))) {
    stop("Forecast availability requires season and weekF columns.", call. = FALSE)
  }
  season <- as.character(data[[season_col]])
  supplied <- if ("nW_true" %in% names(data)) {
    suppressWarnings(as.numeric(data$nW_true))
  } else {
    rep(NA_real_, nrow(data))
  }
  out <- supplied
  for (s in unique(season)) {
    idx <- which(season == s)
    if (all(is.finite(supplied[idx]))) {
      out[idx] <- supplied[idx[1L]]
      next
    }
    derived <- tryCatch(.season_calendar_weeks(data[idx, , drop = FALSE]),
      error = function(e) rep(NA_integer_, length(idx))
    )
    value <- if (all(is.finite(derived))) {
      derived[1L]
    } else {
      observed <- suppressWarnings(as.numeric(data[[week_col]][idx]))
      max(observed[is.finite(observed)], 52, na.rm = TRUE)
    }
    out[idx] <- value
  }
  out
}

.page_forecast_row_key <- function(data) {
  paste(
    as.character(data$season), as.integer(data$eval_weekF),
    as.integer(data$target_weekF), as.integer(data$h),
    sep = "\r"
  )
}
