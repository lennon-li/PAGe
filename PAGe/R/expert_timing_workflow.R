#' Review one season for expert decimal ignition annotation
#'
#' Creates a Plotly review without assigning truth. Peak truth is derived
#' separately by the retrospective GAM procedure.
review_expert_ignition <- function(data,
                                   season = NULL,
                                   existing_annotation = NULL,
                                   weekF_start = NULL,
                                   weekF_end = NULL,
                                   show_counts = TRUE) {
  if (!is.data.frame(data)) stop("`data` must be a data frame.", call. = FALSE)
  canonical <- prepare_surveillance_data(data, season = if ("season" %in% names(data)) NULL else season)
  if (!is.null(season)) {
    season <- trimws(as.character(season))
    canonical <- canonical[canonical$season == season, , drop = FALSE]
    if (!nrow(canonical)) stop("Requested `season` is not present in `data`.", call. = FALSE)
  }
  seasons <- unique(canonical$season)
  if (length(seasons) != 1L) stop("`review_expert_ignition()` requires exactly one season.", call. = FALSE)
  canonical <- canonical[order(canonical$weekF), , drop = FALSE]
  bounds <- range(canonical$weekF, na.rm = TRUE)
  weekF_start <- if (is.null(weekF_start)) bounds[1L] else as.numeric(weekF_start)
  weekF_end <- if (is.null(weekF_end)) bounds[2L] else as.numeric(weekF_end)
  display <- canonical[canonical$weekF >= weekF_start & canonical$weekF <= weekF_end, , drop = FALSE]
  if (!nrow(display)) stop("Requested display window contains no observations.", call. = FALSE)

  if (!is.null(existing_annotation)) {
    validate_expert_ignition_annotation(existing_annotation)
    if (!identical(existing_annotation$season, seasons[[1L]])) stop("Existing annotation season does not match.", call. = FALSE)
  }

  hover <- paste0("season: ", display$season, "<br>weekF: ", display$weekF,
                  "<br>positivity: ", scales::percent(display$p, accuracy = 0.1))
  if (show_counts) hover <- paste0(hover, "<br>positive: ", display$y, "<br>tested: ", display$N)
  fig <- plotly::plot_ly(display, x = ~weekF, y = ~p, type = "scatter", mode = "lines+markers",
                         text = hover, hoverinfo = "text", name = "Observed positivity")
  shapes <- list(); annotations <- list()
  if (!is.null(existing_annotation)) {
    shapes <- list(list(type = "line", x0 = existing_annotation$ignition_week_decimal,
                        x1 = existing_annotation$ignition_week_decimal, y0 = 0, y1 = 1,
                        yref = "paper", line = list(color = "#1f77b4", dash = "dash", width = 2)))
    annotations <- list(list(x = existing_annotation$ignition_week_decimal, y = 1, yref = "paper",
                             text = "Ignition", showarrow = FALSE, yanchor = "bottom",
                             font = list(color = "#1f77b4")))
  }
  fig <- plotly::layout(fig,
    title = list(text = paste0("Expert ignition review: ", seasons[[1L]])),
    xaxis = list(title = "Continuous week coordinate (integer ticks = week starts)"),
    yaxis = list(title = "Positivity", tickformat = ".1%"), hovermode = "closest",
    shapes = shapes, annotations = annotations)

  observed_peak_idx <- which.max(ifelse(is.finite(display$p), display$p, -Inf))
  structure(list(
    season = seasons[[1L]], data = display, plot = fig,
    summary = data.frame(
      season = seasons[[1L]],
      first_weekF = min(display$weekF),
      last_weekF = max(display$weekF),
      observed_peak_weekF = display$weekF[observed_peak_idx],
      observed_peak_p = display$p[observed_peak_idx],
      stringsAsFactors = FALSE
    ),
    provenance = list(method = "review_expert_ignition",
                      data_snapshot_id = digest::digest(canonical, algo = "sha256"),
                      season = seasons[[1L]], coordinate_version = .expert_timing_coordinate_version,
                      created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  ), class = "page_expert_ignition_review_v2")
}

#' Finalize numeric expert ignition after review
finalize_expert_ignition_review <- function(review,
                                            ignition_week_decimal,
                                            annotator,
                                            annotation_version,
                                            positivity_version,
                                            ignition_interval = NULL,
                                            comment = NULL,
                                            annotated_at = Sys.time()) {
  if (!inherits(review, "page_expert_ignition_review_v2")) stop("`review` must come from `review_expert_ignition()`.", call. = FALSE)
  new_expert_ignition_annotation(
    season = review$season,
    ignition_week_decimal = ignition_week_decimal,
    n_weeks = max(as.integer(review$data$weekF), na.rm = TRUE),
    ignition_interval = ignition_interval,
    annotator = annotator,
    annotation_version = annotation_version,
    annotated_at = annotated_at,
    data_snapshot_id = review$provenance$data_snapshot_id,
    positivity_version = positivity_version,
    comment = comment
  )
}

#' Save versioned expert ignition annotations
write_expert_ignition_annotations <- function(annotations, path, overwrite = FALSE) {
  if (file.exists(path) && !overwrite) stop("Refusing to overwrite existing annotation release.", call. = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(compile_expert_ignition_annotations(annotations), path, row.names = FALSE, na = "")
  invisible(normalizePath(path, winslash = "/", mustWork = TRUE))
}
