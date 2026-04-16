# dat: data.frame with one row per season-week
# thresh    : threshold on *probability scale* (e.g. 0.05 for 5%)
# inclusive : if TRUE, count weeks from start to end inclusive

require(dplyr)
#' @export
checkSeasonLength<-function(dat,thresh= 0.05,inclusive  = F) {


  dat %>% mutate(p = y/N, week = weekF) %>%
    arrange(season, week) %>%
    group_by(season) %>%
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
