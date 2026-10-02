#' Build expert ignition review objects for all seasons
#' @export
review_expert_ignition_set <- function(data, seasons = NULL, existing_annotations = NULL, ...) {
  canonical <- prepare_surveillance_data(data)
  available <- sort(unique(as.character(canonical$season)))
  if (is.null(seasons)) seasons <- available
  missing <- setdiff(seasons, available)
  if (length(missing)) stop("Requested season(s) absent from data: ", paste(missing, collapse = ", "), call. = FALSE)
  ann <- .expert_ignitions_by_season(existing_annotations)
  out <- lapply(seasons, function(s) review_expert_ignition(canonical, season = s, existing_annotation = ann[[s]], ...))
  stats::setNames(out, seasons)
}

#' Create a blank ignition annotation sheet
#' @export
expert_ignition_annotation_sheet <- function(data, annotator, annotation_version, positivity_version) {
  canonical <- prepare_surveillance_data(data)
  annotator <- .expert_timing_nonempty(annotator, "annotator")
  annotation_version <- .expert_timing_nonempty(annotation_version, "annotation_version")
  positivity_version <- .expert_timing_nonempty(positivity_version, "positivity_version")
  seasons <- sort(unique(as.character(canonical$season)))
  data.frame(
    schema_version = .expert_timing_schema_version,
    coordinate_version = .expert_timing_coordinate_version,
    season = seasons,
    n_weeks = vapply(seasons, function(s) max(as.integer(canonical$weekF[canonical$season == s])), integer(1)),
    ignition_week_decimal = NA_real_,
    ignition_interval_low = NA_real_,
    ignition_interval_high = NA_real_,
    annotator = annotator,
    annotation_version = annotation_version,
    annotated_at = NA_character_,
    data_snapshot_id = vapply(seasons, function(s) digest::digest(canonical[canonical$season == s, ], algo = "sha256"), character(1)),
    positivity_version = positivity_version,
    comment = NA_character_, stringsAsFactors = FALSE
  )
}

.expert_ignitions_by_season <- function(x) {
  if (is.null(x)) return(list())
  if (inherits(x, "page_expert_ignition_annotation_v2")) x <- list(x)
  lapply(x, validate_expert_ignition_annotation)
  seasons <- vapply(x, function(a) a$season, character(1))
  if (anyDuplicated(seasons)) stop("Duplicate annotation seasons.", call. = FALSE)
  stats::setNames(x, seasons)
}
