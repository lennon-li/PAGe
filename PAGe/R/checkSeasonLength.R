#' Compute in-season length for each season
#'
#' For each season in `dat`, finds the first week at which positivity
#' (`y / N`) crosses `thresh`, the first week after that where it drops
#' back below the threshold, and the gap between them. Used to validate
#' the threshold-based season definition against observed data.
#'
#' @param dat Data frame with one row per season-week. Must include columns
#'   `season`, `weekF`, `y`, and `N`.
#' @param thresh Positivity threshold on the probability scale
#'   (default `0.05`).
#' @param inclusive Logical; if `TRUE`, include both endpoints in the
#'   length count (default `FALSE`).
#'
#' @return A tibble with one row per season and columns `season`,
#'   `start_week`, `end_week`, and `season_length_weeks`.
#' @export
checkSeasonLength<-function(dat,thresh= 0.05,inclusive  = F) {


  dat |> mutate(p = y/N, week = weekF) |>
    arrange(season, week) |>
    group_by(season) |>
    summarise(
      start_week = {
        p_vec <- p
        w_vec <- week
        idx_start <- which(p_vec >= thresh)[1]
        if (is.na(idx_start)) {
          NA_integer_
        } else {
          w_vec[idx_start]
        }
      },
      end_week = {
        p_vec <- p
        w_vec <- week
        idx_start <- which(p_vec >= thresh)[1]
        if (is.na(idx_start)) {
          NA_integer_
        } else {
          # first week *at or after* start where it drops below threshold
          idx_after <- which(p_vec < thresh & seq_along(p_vec) >= idx_start)[1]
          if (is.na(idx_after)) {
            # never drops below again → use last observed week
            w_vec[length(w_vec)]
          } else {
            w_vec[idx_after]
          }
        }
      },
      season_length_weeks = {
        if (is.na(start_week) || is.na(end_week)) {
          NA_integer_
        } else if (inclusive) {
          as.integer(end_week - start_week + 1L)
        } else {
          as.integer(end_week - start_week)
        }
      },
      .groups = "drop"
    )
}
