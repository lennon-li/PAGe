# Post-peak GAM forecast without further alignment

After the peak has been detected, stop aligning to the common template
and instead fit a smooth GAM directly to the observed season, optionally
using the template as a covariate. This produces a continuous curve
through the last observed week and a smooth forecast to max_newWeek.

## Usage

``` r
forecast_post_peak_gam(
  currentSeason,
  g_ref_fun = NULL,
  max_newWeek = 53,
  k_smooth = 8,
  use_weights = TRUE,
  level = 0.95
)
```

## Arguments

- currentSeason:

  Data frame with at least columns: newWeek (sequential index), y, neg.

- g_ref_fun:

  Optional function(u) giving template on the LINK scale for week index
  u (e.g. from make_g_ref_fun). If NULL, the template is not used as a
  covariate.

- max_newWeek:

  Integer, maximum newWeek to forecast to (e.g. 52 or 53). Default:
  max(currentSeason\$newWeek).

- k_smooth:

  Basis dimension for s(newWeek) in the GAM.

- use_weights:

  Logical; if TRUE, use n = y + neg as binomial weights.

- level:

  Confidence level for pointwise intervals.

## Value

A list with components similar to align_forecast_pipeline_dilate(): tau,
delta, a, b, allow_scale, delta_on, pred_df, last_obs, V_ab, V_td, peak,
fallback_reason. The alignment-specific slots are mostly NA.
