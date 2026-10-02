#' Expert decimal ignition annotation contract
#'
#' Expert input in the M1/M2 redesign is limited to latent ignition timing.
#' Retrospective peak truth is derived separately by a frozen GAM procedure.
#'
#' Integer week w represents [w, w + 1).
.expert_timing_schema_version <- "expert-ignition-annotation-v2"
.expert_timing_coordinate_version <- "page-continuous-week-v1"

#' Create one expert decimal ignition annotation
new_expert_ignition_annotation <- function(
    season,
    ignition_week_decimal,
    n_weeks = 52L,
    ignition_interval = NULL,
    annotator,
    annotation_version,
    annotated_at,
    data_snapshot_id,
    positivity_version,
    comment = NULL) {
  n_weeks <- .expert_timing_n_weeks(n_weeks)
  season <- .expert_timing_nonempty(season, "season")
  annotator <- .expert_timing_nonempty(annotator, "annotator")
  annotation_version <- .expert_timing_nonempty(annotation_version, "annotation_version")
  data_snapshot_id <- .expert_timing_nonempty(data_snapshot_id, "data_snapshot_id")
  positivity_version <- .expert_timing_nonempty(positivity_version, "positivity_version")
  annotated_at <- .expert_timing_timestamp(annotated_at)
  comment <- .expert_timing_optional_text(comment, "comment")
  ignition <- .expert_timing_point(ignition_week_decimal, "ignition_week_decimal", n_weeks)
  ignition_interval <- .expert_timing_interval(
    ignition_interval, "ignition_interval", n_weeks, point = ignition
  )

  structure(list(
    schema_version = .expert_timing_schema_version,
    coordinate_version = .expert_timing_coordinate_version,
    season = season,
    n_weeks = n_weeks,
    ignition_week_decimal = ignition,
    ignition_interval = ignition_interval,
    annotator = annotator,
    annotation_version = annotation_version,
    annotated_at = annotated_at,
    data_snapshot_id = data_snapshot_id,
    positivity_version = positivity_version,
    comment = comment
  ), class = "page_expert_ignition_annotation_v2")
}

#' Validate an expert ignition annotation
validate_expert_ignition_annotation <- function(x) {
  if (!inherits(x, "page_expert_ignition_annotation_v2")) {
    stop("`x` must be created by `new_expert_ignition_annotation()`.", call. = FALSE)
  }
  if (!identical(x$schema_version, .expert_timing_schema_version) ||
      !identical(x$coordinate_version, .expert_timing_coordinate_version)) {
    stop("Unsupported expert ignition annotation schema/coordinate version.", call. = FALSE)
  }
  invisible(new_expert_ignition_annotation(
    season = x$season,
    ignition_week_decimal = x$ignition_week_decimal,
    n_weeks = x$n_weeks,
    ignition_interval = x$ignition_interval,
    annotator = x$annotator,
    annotation_version = x$annotation_version,
    annotated_at = x$annotated_at,
    data_snapshot_id = x$data_snapshot_id,
    positivity_version = x$positivity_version,
    comment = x$comment
  ))
}

#' Compile expert ignition annotations to flat storage rows
compile_expert_ignition_annotations <- function(annotations) {
  if (inherits(annotations, "page_expert_ignition_annotation_v2")) annotations <- list(annotations)
  if (!is.list(annotations) || !length(annotations)) {
    stop("`annotations` must contain at least one expert ignition annotation.", call. = FALSE)
  }
  lapply(annotations, validate_expert_ignition_annotation)
  out <- do.call(rbind, lapply(annotations, function(x) data.frame(
    schema_version = x$schema_version,
    coordinate_version = x$coordinate_version,
    season = x$season,
    n_weeks = x$n_weeks,
    ignition_week_decimal = x$ignition_week_decimal,
    ignition_interval_low = .expert_interval_value(x$ignition_interval, 1L),
    ignition_interval_high = .expert_interval_value(x$ignition_interval, 2L),
    annotator = x$annotator,
    annotation_version = x$annotation_version,
    annotated_at = x$annotated_at,
    data_snapshot_id = x$data_snapshot_id,
    positivity_version = x$positivity_version,
    comment = if (is.null(x$comment)) NA_character_ else x$comment,
    stringsAsFactors = FALSE
  )))
  rownames(out) <- NULL
  out
}


# Internal compatibility contract for historical expert annotations that
# recorded both ignition and retrospective peak timing. The public v3 workflow
# asks experts for ignition only; these helpers remain internal.
.expert_full_timing_schema_version <- "expert-timing-annotation-v1"

new_expert_timing_annotation <- function(
    season,
    ignition_week_decimal,
    peak_week_decimal,
    n_weeks = 52L,
    ignition_interval = NULL,
    peak_interval = NULL,
    peak_status = "point",
    annotator,
    annotation_version,
    annotated_at,
    data_snapshot_id,
    positivity_version,
    comment = NULL) {
  n_weeks <- .expert_timing_n_weeks(n_weeks)
  season <- .expert_timing_nonempty(season, "season")
  annotator <- .expert_timing_nonempty(annotator, "annotator")
  annotation_version <- .expert_timing_nonempty(annotation_version, "annotation_version")
  data_snapshot_id <- .expert_timing_nonempty(data_snapshot_id, "data_snapshot_id")
  positivity_version <- .expert_timing_nonempty(positivity_version, "positivity_version")
  annotated_at <- .expert_timing_timestamp(annotated_at)
  comment <- .expert_timing_optional_text(comment, "comment")
  ignition <- .expert_timing_point(ignition_week_decimal, "ignition_week_decimal", n_weeks)
  ignition_interval <- .expert_timing_interval(
    ignition_interval, "ignition_interval", n_weeks, point = ignition
  )

  peak_status <- .expert_timing_nonempty(peak_status, "peak_status")
  allowed_peak_status <- c("point", "uncertain", "plateau", "unlabelable")
  if (!peak_status %in% allowed_peak_status) {
    stop("`peak_status` must be one of: ", paste(allowed_peak_status, collapse = ", "), ".", call. = FALSE)
  }

  peak_missing <- length(peak_week_decimal) == 1L &&
    is.numeric(peak_week_decimal) && is.na(peak_week_decimal)
  if (peak_missing) {
    if (!identical(peak_status, "unlabelable")) {
      stop("A missing `peak_week_decimal` requires `peak_status = 'unlabelable'`.", call. = FALSE)
    }
    if (is.null(comment)) {
      stop("An unlabelable peak requires a non-empty `comment` documenting the reason.", call. = FALSE)
    }
    if (!is.null(peak_interval)) {
      stop("`peak_interval` must be NULL when the peak is unlabelable.", call. = FALSE)
    }
    peak <- NA_real_
  } else {
    peak <- .expert_timing_point(peak_week_decimal, "peak_week_decimal", n_weeks)
    if (ignition >= peak) {
      stop("Expert ignition timing must be strictly before peak timing.", call. = FALSE)
    }
    peak_interval <- .expert_timing_interval(
      peak_interval, "peak_interval", n_weeks, point = peak
    )
  }

  structure(list(
    schema_version = .expert_full_timing_schema_version,
    coordinate_version = .expert_timing_coordinate_version,
    season = season,
    n_weeks = n_weeks,
    ignition_week_decimal = ignition,
    ignition_interval = ignition_interval,
    peak_week_decimal = peak,
    peak_interval = peak_interval,
    peak_status = peak_status,
    annotator = annotator,
    annotation_version = annotation_version,
    annotated_at = annotated_at,
    data_snapshot_id = data_snapshot_id,
    positivity_version = positivity_version,
    comment = comment
  ), class = "page_expert_timing_annotation_v1")
}

validate_expert_timing_annotation <- function(x) {
  if (!inherits(x, "page_expert_timing_annotation_v1")) {
    stop("`x` must be created by `new_expert_timing_annotation()`.", call. = FALSE)
  }
  if (!identical(x$schema_version, .expert_full_timing_schema_version) ||
      !identical(x$coordinate_version, .expert_timing_coordinate_version)) {
    stop("Unsupported expert timing annotation schema/coordinate version.", call. = FALSE)
  }
  invisible(new_expert_timing_annotation(
    season = x$season,
    ignition_week_decimal = x$ignition_week_decimal,
    peak_week_decimal = x$peak_week_decimal,
    n_weeks = x$n_weeks,
    ignition_interval = x$ignition_interval,
    peak_interval = x$peak_interval,
    peak_status = x$peak_status,
    annotator = x$annotator,
    annotation_version = x$annotation_version,
    annotated_at = x$annotated_at,
    data_snapshot_id = x$data_snapshot_id,
    positivity_version = x$positivity_version,
    comment = x$comment
  ))
}

compile_expert_timing_annotations <- function(annotations) {
  if (inherits(annotations, "page_expert_timing_annotation_v1")) annotations <- list(annotations)
  if (!is.list(annotations) || !length(annotations)) {
    stop("`annotations` must contain at least one expert timing annotation.", call. = FALSE)
  }
  lapply(annotations, validate_expert_timing_annotation)
  out <- do.call(rbind, lapply(annotations, function(x) data.frame(
    schema_version = x$schema_version,
    coordinate_version = x$coordinate_version,
    season = x$season,
    n_weeks = x$n_weeks,
    ignition_week_decimal = x$ignition_week_decimal,
    ignition_interval_low = .expert_interval_value(x$ignition_interval, 1L),
    ignition_interval_high = .expert_interval_value(x$ignition_interval, 2L),
    peak_week_decimal = x$peak_week_decimal,
    peak_interval_low = .expert_interval_value(x$peak_interval, 1L),
    peak_interval_high = .expert_interval_value(x$peak_interval, 2L),
    peak_status = x$peak_status,
    annotator = x$annotator,
    annotation_version = x$annotation_version,
    annotated_at = x$annotated_at,
    data_snapshot_id = x$data_snapshot_id,
    positivity_version = x$positivity_version,
    comment = if (is.null(x$comment)) NA_character_ else x$comment,
    stringsAsFactors = FALSE
  )))
  rownames(out) <- NULL
  out
}

.expert_timing_n_weeks <- function(x) {
  if (length(x) != 1L || is.logical(x) || !is.numeric(x) || !is.finite(x) || x != floor(x) || x < 2) {
    stop("`n_weeks` must be one integer of at least 2.", call. = FALSE)
  }
  as.integer(x)
}
.expert_timing_nonempty <- function(x, name) {
  if (length(x) != 1L || is.na(x) || !is.character(x) || !nzchar(trimws(x))) {
    stop("`", name, "` must be one non-empty string.", call. = FALSE)
  }
  trimws(x)
}
.expert_timing_optional_text <- function(x, name) if (is.null(x)) NULL else .expert_timing_nonempty(x, name)
.expert_timing_point <- function(x, name, n_weeks) {
  if (length(x) != 1L || is.logical(x) || !is.numeric(x) || is.na(x) || !is.finite(x) || x < 1 || x >= n_weeks + 1) {
    stop("`", name, "` must be one finite value in [1, n_weeks + 1).", call. = FALSE)
  }
  as.numeric(x)
}
.expert_timing_interval <- function(x, name, n_weeks, point) {
  if (is.null(x)) return(NULL)
  if (!is.numeric(x) || length(x) != 2L || anyNA(x) || any(!is.finite(x)) || x[1L] > x[2L] || x[1L] < 1 || x[2L] >= n_weeks + 1) {
    stop("`", name, "` must be an ordered two-value interval within [1, n_weeks + 1).", call. = FALSE)
  }
  if (point < x[1L] || point > x[2L]) stop("`", name, "` must contain its point estimate.", call. = FALSE)
  as.numeric(x)
}
.expert_timing_timestamp <- function(x) {
  if (inherits(x, "POSIXt")) return(format(as.POSIXct(x, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  .expert_timing_nonempty(x, "annotated_at")
}
.expert_interval_value <- function(x, index) if (is.null(x)) NA_real_ else x[[index]]
