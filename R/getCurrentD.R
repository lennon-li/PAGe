
#' Fetch and tidy current-season PHO respiratory surveillance data
#'
#' Downloads (or reads a local copy of) the Public Health Ontario lab-testing
#' CSV, filters to one virus and the requested season plus its predecessor,
#' aggregates weekly totals across all PHUs, and returns a tidy data frame
#' ready for the M0/M1/M2 pipeline.
#'
#' @param data URL or local file path to the PHO lab-testing CSV. Defaults to
#'   the 2024-25 / 2025-26 ORVT public feed.
#' @param startWeek Integer MMWR week used as the epidemic-year origin for
#'   computing \code{weekF} (default 27L, early July).
#' @param lastWeek Integer or \code{NA}. When non-\code{NA}, rows with MMWR
#'   \code{week > lastWeek} are dropped before returning.
#' @param virus Character string matching the \code{Virus} column of the CSV
#'   (default \code{"Influenza A"}).
#' @param season Character season identifier in \code{"YYYY-YY"} format
#'   (default \code{"2025-26"}).
#'
#' @return A data frame with one row per MMWR week containing: \code{season},
#'   \code{week}, \code{N} (total tests), \code{y} (positives), \code{neg},
#'   \code{p} (positivity), \code{weekS}, \code{weekF}, \code{cYear},
#'   \code{newWeek}, and \code{date}.
#' @export
getCurrentD <- function(data= "https://ws1.publichealthontario.ca/appdata/powerbi/ORVT/ORVT_Lab_Testing_Data_2024-25_2025-26.csv", 
                        startWeek = 27L, 
                        lastWeek = NA,
                        virus = "Influenza A",
                        season = "2025-26") {
  
  n_weeks_in_start_year <- function(start_year) {
    52L + as.integer(MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
  }
  
  years <- strsplit(season, "-", fixed = TRUE)[[1]]
  start_year <- as.integer(years[1]) - 1
  end_year   <- as.integer(paste0(substr(years[1], 1, 2), years[2])) - 1
  
  prev_season <- paste0(
    start_year,
    "-",
    substr(end_year, 3, 4)
  )
  
  # Also produce the date "YYYY-06-20" where YYYY is end_year
  date <- sprintf("%d-06-23", end_year)
  


  currentD<- read.csv(data) |> select(week = Surveillance.week, 
                          season = Surveillance.period, 
                         N = Total...of.tests, 
                         y = X..of.positive.tests,
                         PHU = Public.health.unit,
                         Virus) |> 
        filter(.data$Virus == .env$virus) |>
        group_by(season, week) |> summarise( N = sum(N), y = sum(y)) |> 
        ungroup() |> filter(.data$season %in% c(.env$season, prev_season)) |>
        group_by(season) |> 
        mutate( neg = N-y,
                p = y/N,
                start_year = as.integer(substr(season, 1, 4)),
                mmwr_year  = ifelse(week >= 35L, start_year, start_year + 1L),
                Rdate      = MMWRweek2Date(mmwr_year, week, 1L),
                nW_true    = n_weeks_in_start_year(start_year),
                weekS      = ((week - 35L) %% nW_true) + 1L,
                weekF      = ((week - startWeek) %% nW_true) + 1L,
                cYear      = as.factor(format(Rdate, "%Y")),
                newWeek    = weekF
        )  |>  ungroup() |> arrange(season, weekS, Rdate) |> 
        filter(Rdate > date) |> rename(date = Rdate)
        
  if(!is.na(lastWeek)){
    currentD = currentD |> filter(week <= lastWeek)
  }
  
  
  currentD
}
