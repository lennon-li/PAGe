library(tidyverse)
library(mgcv)
library(gamm4)
library(gratia)
library(ggplot2)
library(plotly)
library(kableExtra)
library(purrr)
library(glue)
library(quartabs)
library(htmltools)
library(data.table)
library(ISOweek)
library(MMWRweek)
library(openxlsx2)
#source("helpers.R")

startWeek = 27 ##week number to start the surveillance season
season = "2025-26"
grid = data.frame(weekF = seq(1,52, by = 1)) ## grid for predictions
min_window = 10 ## minimum time window to the start/end of the data for ignition point detection
df = 10 ## degrees of freedom for the GAM smoothing

#####season ignition parameters
p_thresh = 0.01 #at least 1% to reach ignition
k = 0.002 # min slope for ignition at least 0.1% increase in positivity




###OLIS

dfT <- read_xlsx("Influenza A weekly total tests by surveillance week in Ontario.xlsx", 
                sheet = 1,start_row = 3) %>% rename(week = 1, N = 2, season = 3) 

dfP <- read_xlsx("Influenza A weekly total positive tests by surveillance week in Ontario.xlsx", 
                 sheet = 1, start_row = 3) %>% rename(week = 1, y = 2, season = 3) 


## iphis
theDs = read.csv("positive.csv") %>% left_join(read.csv("test.csv")) %>% setNames(c("week","y","season","N")) %>% 
  mutate(y = as.integer(gsub(",", "", y)), N = as.integer(gsub(",", "", N)),  neg = N-y, season = as.factor(season)) %>%  
  filter(!season %in% c("2022-23", "2023-24"))


theDD = dfT %>% left_join(dfP) %>% 
  mutate(neg = N -y,
         week = as.integer(week),
         season = as.factor(season)) %>% 
  dplyr::select(names(theDs))



theD = rbind(theDs, theDD %>% filter(season %in% c("2022-23", "2023-24", "2024-25"))) %>%
  mutate(season =  droplevels(season)) %>%
  group_by(season) %>% 
  mutate( p = y/N,
          start_year = as.integer(substr(season, 1, 4)),
          mmwr_year  = ifelse(week >= 35L, start_year, start_year + 1L),
          Rdate      = MMWRweek2Date(mmwr_year, week, 1L),
          nW_true    = n_weeks_in_start_year(start_year),
          weekS      = ((week - 35L) %% nW_true) + 1L,
          weekF      = ((week - startWeek) %% nW_true) + 1L,
          cYear      = as.factor(lubridate::year(Rdate))
  )  %>%  ungroup() %>% arrange(season, weekS, Rdate) %>% rename(date = Rdate)






#current "season", with around 8 weeks from last season
currentSeason = theDD %>% filter(season %in% c("2024-25", "2025-26")) %>%
  mutate(season =  droplevels(season)) %>%
  group_by(season) %>% 
  mutate( p = y/N,
          start_year = as.integer(substr(season, 1, 4)),
          mmwr_year  = ifelse(week >= 35L, start_year, start_year + 1L),
          Rdate      = MMWRweek2Date(mmwr_year, week, 1L),
          nW_true    = n_weeks_in_start_year(start_year),
          weekS      = ((week - 35L) %% nW_true) + 1L,
          weekF      = ((week - startWeek) %% nW_true) + 1L,
          cYear      = as.factor(lubridate::year(Rdate))
  )  %>%  ungroup() %>% arrange(season, weekS, Rdate) %>% 
  filter(week >= startWeek, Rdate > as.Date("2025-06-20")) %>% rename(date = Rdate)



####fit gams for each season for derivative calculations
gam_fit <- pred <- d1 <- d2 <-as.list(unique(theD$season)) %>% setNames(unique(theD$season)) # create empty list for gam fits
predD = theD %>%  add_column(fit = NA, se.fit = NA)

for (s in unique(theD$season)) {
  gam_fit[[s]] <- gam(cbind(y, neg) ~ s(weekF, k = df, bs = "ps"), data = predD %>% filter(season == s), family = "binomial", method = "REML")
  pred[[s]] <- predict(gam_fit[[s]], newdata = predD%>% filter(season == s), type = "response", se.fit = T)
  predD$fit[predD$season == s] = pred[[s]]$fit
  predD$se.fit[predD$season == s] = pred[[s]]$se.fit
  
  d1[[s]] <- gratia::derivatives(gam_fit[[s]], intervel = "simultaneous", order = 1, data = predD %>% filter(season ==s)) %>% select(.derivative, .lower_ci, .upper_ci) %>% rename(d1 = .derivative, d1.lower = .lower_ci, d1.upper = .upper_ci)
  
  d2[[s]] <- gratia::derivatives(gam_fit[[s]], intervel = "simultaneous", order = 2, data =  predD %>% filter(season ==s)) %>% select(.derivative, .lower_ci, .upper_ci) %>% rename(d2 = .derivative, d2.lower = .lower_ci, d2.upper = .upper_ci)
  
}

predD = predD %>% mutate(binom.se = sqrt(fit*(1 - fit) / N),
                         total.se = sqrt(binom.se^2 + se.fit^2),
                         low = fit - 1.96*total.se,
                         high = fit + 1.96*total.se) %>% mutate(low = ifelse(low<0, 0, low), 
                                                                season = as.factor(as.character(season)))

ggplotly(ggplot(predD, aes(x = weekF, y = p, group = season, color = season)) + geom_point() +
           xlab("Week") + 
           geom_line(aes(y = fit), linewidth = 1) +
           geom_ribbon(aes(x = weekF, ymin = low, ymax = high), alpha = 0.2) +
           ylab("Proportion of positive tests") )



### Derivatives
allD <- pmap(
  .l = list(split(predD, predD$season), d1,d2),
  .f = bind_cols
) %>% lapply( \(x) {
  x %>% mutate(d1_resp = fit * (1 - fit) * d1, 
               d2_resp = fit * (1 - fit) * d2+ fit * (1 - fit) * (1 - 2*fit) * d1^2,
               d1_lo_resp = fit * (1 - fit) * d1.lower,
               d1_up_resp = fit * (1 - fit) * d1.upper,
               d2_lo_resp = fit * (1 - fit) * d2.lower +fit * (1 - fit) * (1 - 2*fit) * (d1.lower^2),
               d2_up_resp = fit * (1 - fit) * d2.upper + fit * (1 - fit) * (1 - 2*fit) * (d1.upper^2),
               slope_rank  = rank(desc(d1_resp)),
               acc_rank = rank(desc(d2_resp)),
               signs1 = sign(d1_resp),
               signs2 = sign(d2_resp),
               concaveDown = c(NA,(signs2[-1] == -1 & signs2[-length(signs2)] == 1)), #this is the first negative after the zero crossing
               concaveUp = c(NA,(signs2[-1] == 1 & signs2[-length(signs2)] == -1)),
               increase = c(NA,(signs1[-1] == -1 & signs1[-length(signs1)] == 1)), 
               decrease = c(NA,(signs1[-1] == 1 & signs1[-length(signs1)] == -1)))%>% select(-c(signs1, signs2)) 
  
})  %>% lapply(flagIgnition)  



theD = allD %>% rbindlist() %>% arrange(season, weekF)  %>% mutate(anchorWeek = median(iWeek),offset = iWeek- anchorWeek, newWeek = ((weekF - offset - 1) %% 52) + 1)


#fit a common trend GAM
grid = data.frame(newWeek = seq(1,52, by = 1)) 
mod2 <- gamm4(
  cbind(y, neg) ~ 
    s(newWeek,k=df),      # one global smooth
  random = ~(1 | season),
  data   = theD,
  family = binomial(),
  method = "REML"
)

pred = predict(mod2$gam, newdata = grid %>% add_column(season = "fit"), type = "response", se.fit = T)

predD = grid %>% add_column(N = tapply(theD$N, theD$newWeek, median),
                            fit = pred$fit,
                            se.fit = pred$se.fit,
                            binom.se = sqrt(fit*(1 - fit) / N),
                            total.se = sqrt(binom.se^2 + pred$se.fit^2),
                            low = pred$fit - 1.96*total.se,
                            high = pred$fit + 1.96*total.se,
                            p = 0) %>% mutate(low = ifelse(low<0, 0, low), season = "fit")

ggplotly(ggplot(theD, aes(x = newWeek, y = p, group = season, color = season)) + 
           geom_point(alpha = 0.5)  + geom_line(alpha = 0.5)+
           xlab("Week aligned") + 
           geom_line(data = predD, aes(x = newWeek, y = fit), color = "black", linewidth = 1.5) +
           geom_ribbon(data = predD, aes(x = newWeek, ymin = low, ymax = high), alpha = 0.2) +
           geom_vline(xintercept = theD$anchorWeek[1], linetype = "dashed") +
           ylab("Proportion of positive tests") + ggtitle("GAM fit with common trend"))

##############################This is the final estimated reference curve
weeks = 1:52
grid <- tibble(newWeek = weeks)
g_ref_fun <- (function(gam_obj, grid) {
  eta_hat <- drop(predict(gam_obj, newdata = grid, type = "link"))
  splinefun(grid$newWeek, eta_hat, method = "natural")  # rule=2 extrapolates
})(mod2$gam, grid)

ref_df <- tibble(
  newWeek = weeks,
  p_gamm  = plogis(g_ref_fun(weeks))
)

ggplotly(ggplot() +
           geom_line(data = ref_df, aes(newWeek, p_gamm), color = "steelblue") +
           labs(title = "Estimated reference curve",
                x = "Week", y = "Probability") + theme_minimal(12))

g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1), 52))

# 3) Mean & SE from the fitted GAM at arbitrary u
g_ref_mu_se <- (function(gam_obj) {
  function(u) {
    nd <- data.frame(newWeek = u)
    pr <- predict(gam_obj, newdata = nd, type = "link", se.fit = TRUE)
    list(mu = drop(pr$fit), se = drop(pr$se.fit))
  }
})(mod2$gam)


#=========================================================learn about shifts and streches
hyper <- learn_alignment_hyperparams(theD %>% mutate(newWeek = weekF), g_ref_fun)

save.image("ref_curve.RData")

