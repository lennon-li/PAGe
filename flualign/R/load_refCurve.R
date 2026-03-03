#' Load all flualign example objects
#'
#' Loads all objects stored in the bundled ref_curve.RData file
#' into the specified environment (default: caller).
#'
#' @param envir environment to load into. Defaults to parent.frame().
#' @export
load_refCurve <- function(envir = parent.frame()) {
  f <- system.file("extdata", "ref_curve.RData", package = "flualign")
  if (f == "") stop("ref_curve.RData not found in flualign")
  load(f, envir = envir)
}