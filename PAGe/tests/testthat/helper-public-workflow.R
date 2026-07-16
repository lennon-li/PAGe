workflow_surveillance <- function(season = "2025-26", weekF = seq_along(season)) {
  data.frame(
    season = season,
    weekF = weekF,
    y = seq_along(season),
    N = rep(100L, length(season)),
    marker = letters[seq_along(season)]
  )
}

workflow_kit <- function(current_season = NULL) {
  fit <- structure(
    list(model = data.frame(
      logit_f_eff = 0,
      z_ema = 0,
      lead = factor(c(1L, 2L))
    )),
    class = "gam"
  )
  kit <- list(
    ref = list(anchorWeek = 20L),
    hyper = list(scale = 1),
    M1_PARAMS = list(
      temperature = 0.25, rise_weight = 1, trough_weight = 0.1,
      peak_decay = 0.3, slope_weight = 8, slope_window = 6L,
      dynamic_temp = FALSE, dynamic_temp_pivot = 10L
    ),
    m0_params = list(p_thr = 0.005),
    m2_production = list(fit = fit),
    best_spec = list(k_f = 4L, k_n = 0L, k_de = 0L, k_r = 0L, k_sp = 0L)
  )
  if (!is.null(current_season)) kit$current_season <- current_season
  kit
}
