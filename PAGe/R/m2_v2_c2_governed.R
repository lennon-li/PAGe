# Versioned governed M2-v2 C2 wrapper. This path is intentionally separate
# from the legacy M2 kit/runtime and remains opt-in.

#' Governed M2-v2 C2 contract
#'
#' Returns the immutable shadow-runtime contract for fixed C2 shrinkage, timing
#' handoffs, B-gate policy, denominator metadata, and output fields.
#' @return A versioned governed M2-v2 C2 contract list.
m2_v2_c2_governed_contract <- function() {
  list(
    artifact_schema = "page-m2-v2-c2-governed-v1",
    model_version = "m2-v2-c2-governed-v1",
    shrinkage = list(
      version = "c2-fixed-shrinkage-v1",
      type_pool_weight = 0.5,
      curve_blend_weight = 0.5
    ),
    timing_contract_ids = list(
      A = "m1-v2-to-m2-v1",
      B = "m1-v2-b-soft-timing-provisional-v1"
    ),
    b_gate_policy = list(
      version = "b-epidemic-gate-5pct-v1",
      status = "closed_pending_review",
      semantics = "causal_latch_after_first_qualifying_trailing_window",
      min_origin_week = 18L,
      trailing_weeks = 4L,
      min_trailing_positive_count = 40L,
      min_trailing_max_positivity = 0.05
    ),
    denominator_regime_metadata = list(
      levels = c("historical_shared_flu_test_proxy", "orvt_type_specific"),
      treatment = "retained_as_metadata; not harmonized; likelihood regime not finalized"
    ),
    output_contract = list(
      version = "m2-v2-c2-forecast-output-v1",
      required_columns = c(
        "season", "type", "horizon", "pred_baseline", "pred_c2",
        "pred_selected", "c2_applied", "fallback_reason", "model_artifact_id"
      ),
      probability_scale = "[0,1]"
    ),
    historical_timing_training = list(
      policy = "prior_only_season_excluded",
      required_evidence_field = "prior_seasons",
      target_season_must_be_absent = TRUE
    )
  )
}

.m2_v2_c2_governed_id <- function(x) {
  .m2_v2_c2_require_digest()
  payload <- list(
    contract = x$contract,
    research_fit_artifact_id = x$fit$artifact_id,
    training_seasons = sort(as.character(x$training_seasons)),
    provenance = x$provenance,
    training_evidence_id = x$training_evidence_id
  )
  paste0("m2v2g_", digest::digest(payload, algo = "sha256"))
}

new_m2_v2_c2_governed_artifact <- function(research_fit, provenance,
                                           training_evidence) {
  validate_m2_v2_c2_research_fit(research_fit)
  contract <- m2_v2_c2_governed_contract()
  if (!identical(research_fit$spec$type_pool_weight, contract$shrinkage$type_pool_weight) ||
    !identical(research_fit$spec$curve_blend_weight, contract$shrinkage$curve_blend_weight)) {
    stop("Research fit does not match the governed fixed-shrinkage contract.", call. = FALSE)
  }
  if (!is.list(provenance) || !length(provenance$source_hashes) ||
    is.null(provenance$training_data_sha256) || is.null(provenance$shape_data_sha256)) {
    stop("Governed artifact provenance requires source, training-data, and shape hashes.", call. = FALSE)
  }
  if (!is.data.frame(training_evidence) ||
    !all(c("season", "prior_seasons") %in% names(training_evidence))) {
    stop("training_evidence must contain season and prior_seasons.", call. = FALSE)
  }
  seasons <- as.character(training_evidence$season)
  priors <- as.character(training_evidence$prior_seasons)
  for (i in seq_along(seasons)) {
    prior <- if (is.na(priors[i]) || !nzchar(priors[i])) {
      character()
    } else {
      strsplit(priors[i], ";", fixed = TRUE)[[1L]]
    }
    if (seasons[i] %in% prior || any(!prior %in% research_fit$training_seasons)) {
      stop("Chronological evidence contains target-season leakage or non-training priors.", call. = FALSE)
    }
    if (length(prior) && any(prior >= seasons[i])) {
      stop("Chronological training priors must precede their target season.", call. = FALSE)
    }
  }
  out <- structure(list(
    contract = contract,
    fit = research_fit,
    training_seasons = research_fit$training_seasons,
    provenance = provenance,
    training_evidence_id = digest::digest(training_evidence, algo = "sha256"),
    artifact_id = NA_character_
  ), class = "page_m2_v2_c2_governed")
  out$artifact_id <- .m2_v2_c2_governed_id(out)
  validate_m2_v2_c2_governed_artifact(out)
  out
}

#' Validate a governed M2-v2 C2 artifact
#'
#' @param x Object produced by the governed M2-v2 C2 artifact builder.
#' @return `x` invisibly when contract and deterministic identity checks pass.
validate_m2_v2_c2_governed_artifact <- function(x) {
  if (!inherits(x, "page_m2_v2_c2_governed") ||
    !identical(x$contract, m2_v2_c2_governed_contract())) {
    stop("Unsupported or mutated governed M2-v2 C2 contract.", call. = FALSE)
  }
  validate_m2_v2_c2_research_fit(x$fit)
  if (!identical(x$training_seasons, x$fit$training_seasons)) {
    stop("Governed M2-v2 C2 training-season identity mismatch.", call. = FALSE)
  }
  expected_id <- .m2_v2_c2_governed_id(x)
  if (!identical(x$artifact_id, expected_id)) {
    stop("Governed M2-v2 C2 artifact identity mismatch: ", x$artifact_id,
      " != ", expected_id,
      call. = FALSE
    )
  }
  invisible(x)
}

#' Bind a reviewed B timing gate decision document
#'
#' The JSON decision record must contain `status = "reviewed_open"`, the exact
#' gate policy version, a nonempty `review_id`, and `decision = "open"`.
#' @param review_path Path to the immutable JSON review decision.
#' @return A hash-bound B gate review object.
new_m2_v2_b_gate_review <- function(review_path) {
  .m2_v2_c2_require_digest()
  if (!is.character(review_path) || length(review_path) != 1L ||
    is.na(review_path) || !file.exists(review_path) ||
    !requireNamespace("jsonlite", quietly = TRUE)) {
    stop("B gate review requires an existing JSON decision document.", call. = FALSE)
  }
  decision <- jsonlite::fromJSON(review_path, simplifyVector = FALSE)
  if (!identical(decision$status, "reviewed_open") ||
    !identical(decision$decision, "open") ||
    !identical(decision$policy_version, m2_v2_c2_governed_contract()$b_gate_policy$version) ||
    !is.character(decision$review_id) || length(decision$review_id) != 1L ||
    is.na(decision$review_id) || !nzchar(decision$review_id)) {
    stop("B gate review document does not authorize the artifact's exact policy version.", call. = FALSE)
  }
  structure(
    list(
      status = decision$status,
      version = decision$policy_version,
      review_id = decision$review_id,
      review_path = normalizePath(review_path, winslash = "/", mustWork = TRUE),
      review_sha256 = digest::digest(file = review_path, algo = "sha256")
    ),
    class = "page_m2_v2_b_gate_review"
  )
}

#' Run the governed M2-v2 C2 forecast path
#'
#' A timing failure abstains to the fitted type baseline. B +1 is always B1.
#' B +2 remains B1 until a review object explicitly opens the artifact's exact
#' causal gate version. This function does not alter run_prospective_pipeline().
#' @param artifact Validated governed M2-v2 C2 artifact.
#' @param weekly_data Three or more typed weekly rows used by the research runtime adapter.
#' @param origin_week Current week in season-relative coordinates.
#' @param a_handoff Optional governed A M1 timing handoff.
#' @param b_handoff Optional type-B soft-timing handoff.
#' @param b_gate_review Optional reviewed gate opening from new_m2_v2_b_gate_review().
#' @return Governed output contract with prediction rows and provenance.
run_m2_v2_c2_governed_runtime <- function(artifact, weekly_data, origin_week,
                                          a_handoff = NULL, b_handoff = NULL,
                                          b_gate_review = NULL) {
  validate_m2_v2_c2_governed_artifact(artifact)
  review_valid <- inherits(b_gate_review, "page_m2_v2_b_gate_review") &&
    file.exists(b_gate_review$review_path) &&
    identical(
      digest::digest(file = b_gate_review$review_path, algo = "sha256"),
      b_gate_review$review_sha256
    )
  gate_open <- review_valid &&
    identical(b_gate_review$status, "reviewed_open") &&
    identical(b_gate_review$version, artifact$contract$b_gate_policy$version) &&
    nzchar(b_gate_review$review_id)
  result <- run_m2_v2_c2_research_runtime(
    artifact$fit, weekly_data, origin_week, a_handoff, b_handoff
  )
  if (!gate_open) {
    i <- result$predictions$type == "B" & result$predictions$horizon == 2L
    result$predictions$pred_selected[i] <- result$predictions$pred_baseline[i]
    result$predictions$pred_c2[i] <- result$predictions$pred_baseline[i]
    result$predictions$c2_applied[i] <- FALSE
    result$predictions$timing_used[i] <- FALSE
    result$predictions$fallback_reason[i] <- "b_gate_closed_pending_review"
  }
  result$predictions$model_artifact_id <- artifact$artifact_id
  result$predictions$governed_model_version <- artifact$contract$model_version
  result$predictions$shrinkage_version <- artifact$contract$shrinkage$version
  result$predictions$b_gate_review_id <- if (gate_open) b_gate_review$review_id else NA_character_
  required <- artifact$contract$output_contract$required_columns
  if (!all(required %in% names(result$predictions)) ||
    any(!is.finite(result$predictions$pred_selected)) ||
    any(result$predictions$pred_selected < 0 | result$predictions$pred_selected > 1)) {
    stop("Governed M2-v2 output contract validation failed.", call. = FALSE)
  }
  result$status <- "governed_m2_v2_c2_shadow"
  result$model_artifact_id <- artifact$artifact_id
  result$b_gate_review <- if (gate_open) b_gate_review else NULL
  result
}
