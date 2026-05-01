#' Plot alignment results against history and reference curve
#'
#' Produces two plotly panels for a fitted alignment: one overlaying
#' historical-season curves with the current fit, and one overlaying the
#' reference curve on the current-season date axis. Intended for interactive
#' inspection of a single-season result.
#'
#' @param res List returned by the alignment pipeline; must contain
#'   `pred_df`, `last_obs`, `peak`, `tau`, and `delta`.
#' @param seasonIndex Optional integer length-2 vector giving the start and
#'   end `newWeek` of the in-season window to annotate.
#' @param peakInfo Optional list with a `flag_week` element; currently unused
#'   (retained for API parity).
#' @param currentSeason Data frame for the current season with columns
#'   `date`, `weekF`, `newWeek`, and `p` (observed positivity).
#'
#' @return A named list with `hist`, `ref` (both plotly objects), and `data`
#'   (the joined data frame used to draw them).
plotRes <-function(res,seasonIndex = NULL, peakInfo = NULL, currentSeason = NULL){
  
  # passdPeak = F
  # if(!is.null(peakInfo) && !is.na(peakInfo$flag_week)){
  #   res$pred_df = res$pred_df |>
  #     mutate(
  #            p_hat = ifelse(kind == "forecast", NA, p_hat),
  #            p_lo = ifelse(kind == "forecast", NA, p_lo),
  #            p_hi = ifelse(kind == "forecast", NA, p_hi))
  #   cat("Passed peak week:", peakInfo$flag_week, "\n")
  # 
  # }
  
  res$pred_df = res$pred_df |> left_join(currentSeason |> select(newWeek,p)) 

  
  p = as.list(c(hist = "hist", ref = "ref", data = "data") )
  
  
  p1 = ggplot() +
    geom_ribbon(
      data = subset(res$pred_df, kind == "forecast"),
      aes(x = newWeek, ymin = p_lo, ymax = p_hi),
      fill = "steelblue", alpha = 0.20
    ) +
    geom_line(
      data = subset(res$pred_df, kind == "forecast"),
      aes(x = newWeek, y = p_hat),
      color = "steelblue", linewidth = 1.2
    ) +
    geom_line(
      data = theD |> filter(weekF >8),
      aes(x = newWeek, y = fit, group = season),
      color = "grey70", linewidth = 0.6, alpha = 0.4
    ) +
    geom_line(
      data = subset(res$pred_df, kind == "observed"),
      aes(x = newWeek, y = p_hat),
      color = "tomato", size = 2
    ) +
    geom_point(
      data = res$pred_df,
      aes(x = newWeek, y = p)
    )+
    geom_vline(xintercept = res$last_obs, linetype = 2, color = "grey50") +
    { if (!any(is.na(res$peak$t_peak))) geom_vline(xintercept = res$peak$t_peak, color = "purple", linetype = 2) } +
    labs(
      title = sprintf("shift= %.2f weeks, dilation= %.3f",
                      res$tau, res$delta),
      subtitle = if (!any(is.na(res$peak$t_peak))) {
        sprintf("Peak ~ week %.1f ",
                res$peak$t_peak)
      } else "Peak CI unavailable yet (early/unstable δ).",
      x = "Week of year", y = "Percentage positivity)"
    ) +
  theme_minimal(base_size = 13)
  

  
  
  
xD = res$pred_df |> left_join(currentSeason |> select(date, newWeek = weekF)) |>
    add_column(season = season) |>     
    mutate( date = as.Date(date),
            start_year = as.integer(substr(season, 1, 4)),
            nW_true    = n_weeks_in_start_year(start_year),
            week = ((newWeek + startWeek - 2L) %% nW_true) + 1L,
            mmwr_year  = ifelse(week >= 35L, start_year, start_year + 1L),
            Rdate      = MMWRweek2Date(mmwr_year, week, 1L),
            date = as.Date(ifelse(is.na(date), Rdate, date)))|> 
    left_join(ref_df)
  
  p2= xD |> ggplot(aes(x = date, y = p_hat)) + geom_line()  +
             #geom_point(data = xD |> filter(kind=="observed")) +     
           #  geom_ribbon(aes(ymin = p_lo, ymax = p_hi), alpha = 0.20) +
             geom_line(aes(y= p_gamm), color = "steelblue") +
             geom_text(data = xD |> filter(newWeek %%2 ==0),aes(y = 0.1,x= date,label = newWeek), size = 3, angle = 90) + 
             geom_point(aes(x= date, y = p), color = "tomato")+
             ylab("Percentge Positivity") +xlab("Surveillance Week") +
               scale_x_date(
               breaks = xD$date,
               labels = xD$week
             ) + theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1))
  
  if(!is.null(seasonIndex)){
    
    start_week = seasonIndex[1] 
    end_week   = seasonIndex[2]
    p1 = p1+ annotate(
      "segment",
      x = start_week, xend = end_week,
      y = 0.05,     yend = 0.05,
      colour = "red", linetype = "dashed"
    ) + xlab(paste0("Week of Year (In season: ",start_week," to ", end_week,")"))
   
    
    start_date <- as.Date(xD |> filter(newWeek == start_week) |> summarise(min(date)) |> pull())
    end_date   <- as.Date(xD |> filter(newWeek == end_week)   |> summarise(max(date)) |> pull())
    
    start <- xD |> filter(newWeek == start_week) |> pull(week)
    end   <- xD |> filter(newWeek == end_week)   |> pull(week)
    
    p2 = p2+ annotate(
      "segment",
      x = start_date, xend = end_date,
      y = 0.05,     yend = 0.05,
      colour = "red", linetype = "dashed"
     ) + xlab(paste0("Surveillance Week (In season: ", start,"-", end,")"))
      
  }
  
  p$hist = ggplotly(p1)
  p$ref = ggplotly(p2)
  p$data = xD
 
  
  p
  
}
