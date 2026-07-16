#' Simulate synthetic flu seasons for package examples
#'
#' Generates \code{S} synthetic influenza seasons from a Gaussian-bump
#' template with random per-season amplitude, intercept, and timing
#' (\code{tau}) variation. Counts are drawn from a Binomial distribution with
#' weekly \code{n} sampled uniformly from [600, 1500].
#'
#' @param S Integer number of seasons to simulate (default 10).
#' @param weeks Integer vector of within-season week indices to generate
#'   (default \code{1:52}).
#' @param seed Integer random seed for reproducibility (default 2025).
#'
#' @return A data frame with columns \code{season} (factor), \code{newWeek},
#'   \code{y} (positives), and \code{neg} (negatives).
#' @export
simulate_flu_seasons <- function(S = 10, weeks = 1:52, seed = 2025) {
  set.seed(seed)
  bump_fun <- function(t, mu = 36, sigma = 7) exp(-0.5 * ((t - mu)/sigma)^2)
  eta_template <- function(t) -3 + 5 * bump_fun(t)
  season_tbl <- tibble::tibble(
    season = factor(seq_len(S)),
    a = rnorm(S, mean = 0, sd = 0.5),
    b = rlnorm(S, meanlog = log(1), sdlog = 0.15),
    tau = rnorm(S, mean = 0, sd = 2)
  )
  df <- tidyr::crossing(season = season_tbl$season, newWeek = weeks) |>
    dplyr::left_join(season_tbl, by = "season") |>
    dplyr::mutate(
      n   = round(runif(dplyr::n(), 600, 1500)),
      eta = a + b * eta_template(newWeek - tau),
      p   = plogis(eta),
      y   = rbinom(dplyr::n(), size = n, prob = p),
      neg = n - y
    ) |>
    dplyr::select(season, newWeek, y, neg)
  df
}

#' Load historical influenza surveillance data
#'
#' Reads a user-supplied historical surveillance CSV. Resolution order is:
#' explicit \code{path}, the \code{PAGE_FLU_HIST_FILE} environment variable,
#' then a bundled \code{inst/extdata/flu_hist.csv} if a future distribution
#' provides one. PAGe does not currently distribute surveillance observations.
#'
#' @param path Optional path to a historical surveillance CSV.
#'
#' @return A data frame containing the CSV fields.
#' @seealso [prepare_surveillance_data()] for normalization and validation.
#' @export
load_flu_hist <- function(path = NULL) {
  fp <- path
  if (is.null(fp) || !length(fp) || !nzchar(fp[[1L]])) {
    fp <- Sys.getenv("PAGE_FLU_HIST_FILE", unset = "")
  }
  if (!length(fp) || !nzchar(fp[[1L]])) {
    fp <- system.file("extdata", "flu_hist.csv", package = "PAGe", mustWork = FALSE)
  }
  if (length(fp) != 1L || is.na(fp) || !nzchar(fp) || !file.exists(fp)) {
    stop(
      "Historical surveillance CSV not found. Supply `path` or set PAGE_FLU_HIST_FILE.",
      call. = FALSE
    )
  }
  utils::read.csv(fp, stringsAsFactors = TRUE)
}
