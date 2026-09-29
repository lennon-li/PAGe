#' Verified PAGe version-comparison metrics
#'
#' Returns the compact evidence table used by the PAGe version-comparison
#' vignette. Rows are deliberately scoped to matched or chronological ledgers
#' that support the stated comparison. Missing values mean that a version was
#' not independently scored on that exact ledger; PAGe does not fill such cells
#' by assuming cross-version equivalence.
#'
#' @return A data frame containing comparison scope, component, horizon, metric,
#'   v1/legacy, v2, v3 values, relative gains, evidence path, and caveat.
#' @export
page_version_metrics <- function() {
  path <- system.file("extdata", "page-version-comparison.csv", package = "PAGe")
  if (!nzchar(path) || !file.exists(path)) {
    roots <- unique(c(".", "..", "../..", "../../..", "../../../.."))
    candidates <- unique(c(
      file.path(roots, "PAGe", "inst", "extdata", "page-version-comparison.csv"),
      file.path(roots, "inst", "extdata", "page-version-comparison.csv")
    ))
    hit <- candidates[file.exists(candidates)]
    if (!length(hit)) stop("Bundled PAGe version-comparison evidence is missing.", call. = FALSE)
    path <- hit[[1L]]
  }
  out <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE, na.strings = c("NA", ""))
  required <- c(
    "comparison_scope", "component", "horizon", "metric", "unit", "n_rows",
    "n_seasons", "v1_legacy", "v2", "v3", "v3_relationship",
    "relative_gain_v1_to_v2", "relative_gain_v2_to_v3", "evidence_path", "caveat"
  )
  if (!identical(names(out), required) || !nrow(out)) {
    stop("Bundled PAGe version-comparison evidence has an invalid schema.", call. = FALSE)
  }
  out
}
