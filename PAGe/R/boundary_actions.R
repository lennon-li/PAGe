# Structured boundary decisions for governed tuning workflows.

#' Build the next action for a tuning result
#'
#' Combines the raw optimizer result, governed candidate selection, boundary
#' reports, and (when needed) the next resumable grid. This is read-only and
#' does not score or mutate the supplied tuning object.
#'
#' @param tuning A `page_m0_tuning`, `page_m1_tuning`, or `page_m2_tuning` result.
#' @param stage One of `"M0"`, `"M1"`, or `"M2"`.
#' @param hard_caps M1 hard-cap policy. Defaults to `default_m1_hard_caps()`.
#' @param selection_method M2 selection rule.
#' @param steps Optional adjacent expansion steps passed to
#'   `expand_tuning_grid()`.
#' @param max_specs Optional expanded-grid row cap.
#'
#' @return A `page_boundary_action_plan` containing raw/final selections,
#'   reports, unresolved axes, and `next_grid` (or `NULL` when settled).
#' @export
boundary_action_plan <- function(
  tuning,
  stage = c("M0", "M1", "M2"),
  hard_caps = NULL,
  selection_method = c("min_nll", "one_se", "pareto"),
  steps = NULL,
  max_specs = NULL
) {
  stage <- toupper(match.arg(stage))
  selection_method <- match.arg(selection_method)
  if (!is.list(tuning)) {
    stop("`tuning` must be a stage tuning result.", call. = FALSE)
  }
  if (stage == "M1") {
    hard_caps <- .normalize_m1_hard_caps(hard_caps %||% tuning$hard_caps %||%
      default_m1_hard_caps())
  }
  if (stage == "M2" && inherits(tuning, "page_m2_subset_tuning")) {
    report <- inspect_tuning_boundaries(
      tuning,
      stage = "M2", warn = FALSE,
      hard_caps = hard_caps,
      min_nll_gain = tuning$min_nll_gain %||% NULL
    )
    unresolved <- report[report$decision == "expand_required", , drop = FALSE]
    next_grid <- NULL
    if (nrow(unresolved)) {
      next_grid <- expand_tuning_grid(
        tuning,
        stage = "M2", steps = steps, max_specs = max_specs
      )
    }
    return(structure(
      list(
        stage = "M2",
        raw_selected = tuning$selected_config,
        final_selected = tuning$selected_config,
        selection = list(
          method = "complete_inner_nll",
          selected_spec = tuning$selected_config,
          selected_spec_id = tuning$best_spec_id
        ),
        selection_reason = paste0(
          "offset_subset_v1 per-horizon complete inner NLL selection; ",
          "selection_method `", selection_method, "` does not apply"
        ),
        raw_boundary_report = report,
        final_boundary_report = report,
        unresolved = unresolved,
        next_grid = next_grid,
        settled = !nrow(unresolved),
        next_call = if (nrow(unresolved)) {
          "Rerun tune_m2() with `next_grid` and the same checkpoint_dir."
        } else {
          "Freeze the governed M2 result and proceed downstream."
        }
      ),
      class = "page_boundary_action_plan"
    ))
  }
  raw <- switch(stage,
    M0 = tuning$best_params %||% tuning$tuning$best_params,
    M1 = tuning$best %||% tuning$best_params,
    M2 = tuning$best_spec %||% tuning$best
  )
  if (is.null(raw)) {
    stop(stage, " tuning is missing its raw selected configuration.", call. = FALSE)
  }
  # M2 `best_spec` is intentionally a rich list (it may contain formulas and
  # model objects).  Boundary inspection only needs the scalar grid row, so
  # recover that row by spec id instead of coercing the rich list.
  if (stage == "M2" && is.data.frame(tuning$grid) &&
    !is.null(tuning$best_spec_id) && "spec_id" %in% names(tuning$grid)) {
    hit <- which(as.character(tuning$grid$spec_id) ==
      as.character(tuning$best_spec_id))[1L]
    if (is.finite(hit)) raw <- tuning$grid[hit, , drop = FALSE]
  }
  raw <- if (is.data.frame(raw)) raw[1L, , drop = FALSE] else as.data.frame(raw)

  final <- raw
  reason <- "raw optimizer selection"
  selection <- NULL
  if (stage == "M1") {
    selection <- select_m1_candidate(
      tuning,
      hard_caps = hard_caps, prefer_simpler = TRUE
    )
    final <- selection$selected[1L, , drop = FALSE]
    reason <- if (isTRUE(selection$backed_off)) {
      "practical-gain backoff selected the simplest boundary-safe candidate"
    } else {
      "raw M1 winner passed the governed selection rule"
    }
  } else if (stage == "M2") {
    selection <- select_m2_candidate(tuning, method = selection_method)
    final <- selection$selected_spec
    if (is.data.frame(tuning$grid) && !is.null(selection$selected_spec_id) &&
      "spec_id" %in% names(tuning$grid)) {
      hit <- which(as.character(tuning$grid$spec_id) ==
        as.character(selection$selected_spec_id))[1L]
      if (is.finite(hit)) final <- tuning$grid[hit, , drop = FALSE]
    }
    reason <- paste0("M2 selection method: ", selection_method)
  }

  raw_probe <- tuning
  final_probe <- tuning
  if (stage == "M0") {
    raw_probe$best_params <- raw
    final_probe$best_params <- final
  } else if (stage == "M1") {
    raw_probe$best <- raw
    final_probe$best <- final
  } else {
    final_probe$best_spec <- final
    final_probe$best_spec_id <- selection$selected_spec_id
  }
  raw_report <- inspect_tuning_boundaries(
    raw_probe,
    stage = stage,
    warn = FALSE,
    null_axes = if (stage == "M0") c("p_thr", "prev_thr", "p_sum_thr") else NULL,
    hard_caps = if (stage == "M1") hard_caps else NULL,
    min_nll_gain = if (stage == "M2") tuning$min_nll_gain %||% NULL else NULL
  )
  final_report <- inspect_tuning_boundaries(
    final_probe,
    stage = stage,
    warn = FALSE,
    null_axes = if (stage == "M0") c("p_thr", "prev_thr", "p_sum_thr") else NULL,
    hard_caps = if (stage == "M1") hard_caps else NULL,
    min_nll_gain = if (stage == "M2") tuning$min_nll_gain %||% NULL else NULL
  )
  unresolved <- final_report[final_report$decision == "expand_required", , drop = FALSE]
  next_grid <- NULL
  if (nrow(unresolved)) {
    next_grid <- expand_tuning_grid(
      final_probe,
      stage = stage,
      steps = steps,
      max_specs = max_specs
    )
  }
  structure(
    list(
      stage = stage,
      raw_selected = raw,
      final_selected = final,
      selection = selection,
      selection_reason = reason,
      raw_boundary_report = raw_report,
      final_boundary_report = final_report,
      unresolved = unresolved,
      next_grid = next_grid,
      settled = !nrow(unresolved),
      next_call = if (nrow(unresolved)) {
        paste0("Rerun tune_", tolower(stage), "() with `next_grid` and the same checkpoint_dir.")
      } else {
        paste0("Freeze the governed ", stage, " result and proceed downstream.")
      }
    ),
    class = "page_boundary_action_plan"
  )
}

#' @export
print.page_boundary_action_plan <- function(x, ...) {
  cat("PAGe Boundary Action Plan\n")
  cat("Stage: ", x$stage, "\n", sep = "")
  cat("Status: ", if (x$settled) "settled" else "expansion required", "\n", sep = "")
  cat("Reason: ", x$selection_reason, "\n", sep = "")
  if (nrow(x$unresolved)) {
    cat("Unresolved axes: ", paste(x$unresolved$parameter, collapse = ", "), "\n", sep = "")
  }
  cat("Next: ", x$next_call, "\n", sep = "")
  invisible(x)
}
