#' Interactively review and label seasonal ignition weeks
#'
#' Presents each requested season using [review_expert_ignition()] and records
#' one decimal ignition week per season. In an interactive R session, the plot
#' is printed before prompting with [readline()]. For reproducible pipelines,
#' supply a named numeric `ignition_weeks` vector and no prompt is used.
#'
#' Decimal week coordinates follow PAGe's continuous-week convention: integer
#' week `w` denotes the interval `[w, w + 1)`. The returned expert annotation
#' preserves the decimal value; `manual_labels` uses `floor()` to project that
#' value onto the existing integer M0/M1 training contract.
#'
#' @param data Multi-season surveillance data accepted by
#'   [prepare_surveillance_data()].
#' @param ignition_weeks Optional named numeric vector of decimal ignition weekF
#'   values. Names must be season labels.
#' @param seasons Optional character vector selecting seasons to review. Defaults
#'   to every season in `data`.
#' @param annotator Non-empty annotator identifier. Defaults to the current OS
#'   user when available.
#' @param annotation_version Version string stored with every expert annotation.
#' @param positivity_version Version string describing the positivity definition.
#' @param interactive Logical. When `TRUE` and `ignition_weeks` is absent, print
#'   each review plot and prompt for the decimal ignition week.
#' @param show_counts Include positive/test counts in plot hover text.
#' @param comments Optional named character vector of per-season comments.
#'
#' @return A `page_ignition_label_set` containing expert annotations, their flat
#'   table, integer training labels, reviews, and provenance.
#' @export
page_label_ignitions <- function(
    data,
    ignition_weeks = NULL,
    seasons = NULL,
    annotator = NULL,
    annotation_version = "expert-ignition-v1",
    positivity_version = "positivity-v1",
    interactive = base::interactive(),
    show_counts = TRUE,
    comments = NULL) {
  canonical <- prepare_surveillance_data(data)
  if (!nrow(canonical)) stop("`data` contains no surveillance rows.", call. = FALSE)
  available <- sort(unique(as.character(canonical$season)))
  if (is.null(seasons)) {
    seasons <- available
  } else {
    seasons <- unique(trimws(as.character(seasons)))
    if (!length(seasons) || any(!nzchar(seasons))) {
      stop("`seasons` must contain non-empty season identifiers.", call. = FALSE)
    }
    missing <- setdiff(seasons, available)
    if (length(missing)) {
      stop("Requested season(s) are absent from `data`: ", paste(missing, collapse = ", "), call. = FALSE)
    }
  }

  if (is.null(annotator)) annotator <- unname(Sys.info()[["user"]])
  if (is.null(annotator) || length(annotator) != 1L || is.na(annotator) ||
      !nzchar(trimws(as.character(annotator)))) {
    stop("`annotator` must be one non-empty string.", call. = FALSE)
  }
  annotator <- trimws(as.character(annotator))

  supplied <- !is.null(ignition_weeks)
  if (supplied) {
    if (!is.numeric(ignition_weeks) || is.null(names(ignition_weeks)) ||
        anyNA(names(ignition_weeks)) || any(!nzchar(names(ignition_weeks))) ||
        anyDuplicated(names(ignition_weeks))) {
      stop("`ignition_weeks` must be a uniquely named numeric vector.", call. = FALSE)
    }
    missing <- setdiff(seasons, names(ignition_weeks))
    if (length(missing)) {
      stop("Missing ignition week(s) for: ", paste(missing, collapse = ", "), call. = FALSE)
    }
  } else if (!isTRUE(interactive)) {
    stop("Supply `ignition_weeks` when `interactive = FALSE`.", call. = FALSE)
  }

  if (!is.null(comments)) {
    if (!is.character(comments) || is.null(names(comments)) || anyDuplicated(names(comments))) {
      stop("`comments` must be a named character vector when supplied.", call. = FALSE)
    }
  }

  annotations <- vector("list", length(seasons))
  reviews <- vector("list", length(seasons))
  names(annotations) <- names(reviews) <- seasons

  for (s in seasons) {
    review <- review_expert_ignition(canonical, season = s, show_counts = show_counts)
    reviews[[s]] <- review
    if (supplied) {
      ignition <- as.numeric(ignition_weeks[[s]])
    } else {
      print(review$plot)
      answer <- readline(paste0("Ignition weekF for ", s, " (decimal, e.g. 18.5): "))
      ignition <- suppressWarnings(as.numeric(trimws(answer)))
      if (length(ignition) != 1L || !is.finite(ignition)) {
        stop("A finite decimal ignition week is required for season `", s, "`.", call. = FALSE)
      }
    }
    comment <- if (!is.null(comments) && s %in% names(comments) &&
      !is.na(comments[[s]]) && nzchar(trimws(comments[[s]]))) comments[[s]] else NULL
    annotations[[s]] <- finalize_expert_ignition_review(
      review,
      ignition_week_decimal = ignition,
      annotator = annotator,
      annotation_version = annotation_version,
      positivity_version = positivity_version,
      comment = comment
    )
  }

  table <- compile_expert_ignition_annotations(annotations)
  manual_labels <- stats::setNames(
    as.integer(floor(table$ignition_week_decimal)),
    as.character(table$season)
  )
  structure(
    list(
      annotations = annotations,
      table = table,
      manual_labels = manual_labels,
      reviews = reviews,
      provenance = list(
        method = "page_label_ignitions",
        interactive = !supplied && isTRUE(interactive),
        data_sha256 = digest::digest(canonical, algo = "sha256"),
        created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      )
    ),
    class = "page_ignition_label_set"
  )
}

#' @method print page_ignition_label_set
#' @export
print.page_ignition_label_set <- function(x, ...) {
  cat("<PAGe ignition labels>\n")
  cat("  seasons: ", length(x$manual_labels), "\n", sep = "")
  if (length(x$manual_labels)) {
    cat("  integer training labels: ",
        paste0(names(x$manual_labels), "=", x$manual_labels, collapse = ", "), "\n", sep = "")
  }
  invisible(x)
}

.page_normalize_ignition_labels <- function(labels) {
  if (inherits(labels, "page_ignition_label_set")) return(labels)
  annotations <- if (inherits(labels, "page_expert_ignition_annotation_v2")) {
    list(labels)
  } else if (is.list(labels) && length(labels) &&
             all(vapply(labels, inherits, logical(1L), what = "page_expert_ignition_annotation_v2"))) {
    unname(labels)
  } else {
    stop("`labels` must come from `page_label_ignitions()` or contain expert ignition annotations.", call. = FALSE)
  }
  table <- compile_expert_ignition_annotations(annotations)
  if (anyDuplicated(table$season)) stop("Expert annotations contain duplicate seasons.", call. = FALSE)
  manual_labels <- stats::setNames(as.integer(floor(table$ignition_week_decimal)), table$season)
  structure(
    list(
      annotations = annotations,
      table = table,
      manual_labels = manual_labels,
      reviews = NULL,
      provenance = list(method = "expert_annotation_import")
    ),
    class = "page_ignition_label_set"
  )
}

#' Label ignition, train PAGe, and return a deployable frozen kit
#'
#' This convenience workflow deliberately reuses [train_pipeline()] rather than
#' implementing a separate trainer. If labels are absent, it first calls
#' [page_label_ignitions()]. Only expert ignition timing is requested; this
#' wrapper does not fabricate peak labels. The current training pipeline is
#' therefore invoked with its legacy integer timing interface, while the full
#' decimal expert annotations remain attached for provenance.
#'
#' @param data Multi-season surveillance data.
#' @param labels Optional `page_ignition_label_set` or expert annotation list.
#' @param ignition_weeks Optional reproducible named decimal ignition vector used
#'   when `labels` is absent.
#' @param mode Training mode passed to [train_pipeline()].
#' @param annotator,interactive Passed to [page_label_ignitions()].
#' @param prospective_holdout Optional season kept out of fitting. `NULL` trains
#'   on all otherwise eligible seasons; a prospective holdout is recommended for
#'   governed model development.
#' @param exclude Seasons excluded from training.
#' @param n_cores,checkpoint_dir,verbose Passed to [train_pipeline()].
#' @param ... Additional named arguments passed to [train_pipeline()].
#'
#' @return A `page_training_workflow` with labels, training result, and frozen kit.
page_train_workflow <- function(
    data,
    labels = NULL,
    ignition_weeks = NULL,
    mode = c("refresh", "retune"),
    annotator = NULL,
    interactive = base::interactive(),
    prospective_holdout = NULL,
    exclude = character(),
    n_cores = max(1L, parallel::detectCores() - 1L),
    checkpoint_dir = NULL,
    verbose = TRUE,
    ...) {
  mode <- match.arg(mode)
  canonical <- prepare_surveillance_data(data)
  if (!nrow(canonical)) stop("`data` contains no surveillance rows.", call. = FALSE)

  all_seasons <- sort(unique(as.character(canonical$season)))
  holdout <- if (!is.null(prospective_holdout) && prospective_holdout %in% all_seasons) {
    as.character(prospective_holdout)
  } else character()
  trainable <- setdiff(all_seasons, unique(c(as.character(exclude), holdout)))
  if (!length(trainable)) {
    stop("No trainable seasons remain after `exclude` and `prospective_holdout`.", call. = FALSE)
  }

  label_set <- if (is.null(labels)) {
    page_label_ignitions(
      canonical,
      ignition_weeks = ignition_weeks,
      seasons = trainable,
      annotator = annotator,
      interactive = interactive
    )
  } else {
    if (!is.null(ignition_weeks)) stop("Supply either `labels` or `ignition_weeks`, not both.", call. = FALSE)
    .page_normalize_ignition_labels(labels)
  }

  missing_labels <- setdiff(trainable, names(label_set$manual_labels))
  if (length(missing_labels)) {
    stop("Ignition labels are required for every trainable season. Missing: ",
         paste(missing_labels, collapse = ", "), call. = FALSE)
  }
  training_labels <- label_set$manual_labels[names(label_set$manual_labels) %in% trainable]
  training_labels <- training_labels[match(trainable, names(training_labels))]

  training <- train_pipeline(
    allD = canonical,
    mode = mode,
    exclude = exclude,
    prospective_holdout = prospective_holdout,
    n_cores = n_cores,
    checkpoint_dir = checkpoint_dir,
    verbose = verbose,
    manual_labels = training_labels,
    timing_mode = "legacy",
    ...
  )
  if (is.null(training$kit)) stop("Training completed without a deployment kit.", call. = FALSE)
  structure(
    list(
      labels = label_set,
      training_result = training,
      kit = training$kit,
      provenance = list(
        method = "page_train_workflow",
        mode = mode,
        data_sha256 = digest::digest(canonical, algo = "sha256"),
        created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      )
    ),
    class = "page_training_workflow"
  )
}

#' @method print page_training_workflow
#' @export
print.page_training_workflow <- function(x, ...) {
  cat("<PAGe training workflow>\n")
  cat("  mode: ", x$training_result$mode %||% "unknown", "\n", sep = "")
  cat("  labeled seasons: ", length(x$labels$manual_labels), "\n", sep = "")
  cat("  deployment kit: ", if (is.null(x$kit)) "absent" else "ready", "\n", sep = "")
  invisible(x)
}

#' Save a validated frozen PAGe deployment kit
#'
#' @param x A `page_training_workflow`, `page_training_result`, or PAGe kit.
#' @param path Destination `.rds` path.
#' @param overwrite Allow replacing an existing file.
#' @return Normalized saved path, invisibly.
#' @export
page_save_kit <- function(x, path, overwrite = FALSE) {
  kit <- if (inherits(x, "page_training_workflow")) x$kit else if (inherits(x, "page_training_result")) x$kit else x
  kit <- validate_page_kit(kit, mode = "frozen")
  if (file.exists(path) && !isTRUE(overwrite)) stop("Refusing to overwrite existing kit: ", path, call. = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = paste0(".", basename(path), "."), tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(kit, tmp)
  if (file.exists(path) && isTRUE(overwrite)) unlink(path)
  if (!file.rename(tmp, path)) stop("Could not atomically publish PAGe kit to `", path, "`.", call. = FALSE)
  invisible(normalizePath(path, winslash = "/", mustWork = TRUE))
}

#' Load and validate a frozen PAGe deployment kit
#'
#' @param path Saved kit `.rds` path.
#' @return A validated frozen PAGe kit.
#' @export
page_load_kit <- function(path) {
  if (!file.exists(path) || dir.exists(path)) stop("PAGe kit file does not exist: ", path, call. = FALSE)
  validate_page_kit(readRDS(path), mode = "frozen")
}
