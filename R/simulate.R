#' @export
# Simulated historical seasons (example data & generator)

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
  df <- tidyr::crossing(season = season_tbl$season, newWeek = weeks) %>%
    dplyr::left_join(season_tbl, by = "season") %>%
    dplyr::mutate(
      n   = round(runif(dplyr::n(), 600, 1500)),
      eta = a + b * eta_template(newWeek - tau),
      p   = plogis(eta),
      y   = rbinom(dplyr::n(), size = n, prob = p),
      neg = n - y
    ) %>%
    dplyr::select(season, newWeek, y, neg)
  df
}

# load example data shipped in inst/extdata
load_flu_hist <- function() {
  fp <- system.file("extdata", "flu_hist.csv", package = "flualign", mustWork = TRUE)
  utils::read.csv(fp, stringsAsFactors = TRUE)
}
