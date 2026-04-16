
# PAGe

Minimal package to align a partially observed flu season to a learned reference curve
(using shift `tau` and optional dilation `delta`), and forecast the remainder with
sensible prediction intervals and peak timing.

## Install

```r
devtools::install_local("PAGe_0.1.0.zip")  # or unzip folder and install
```

## Quick start

```r
library(PAGe)

flu_hist <- load_flu_hist()
fit_reference_gam(flu_hist)  # sets g_ref_fun/g_ref_safe/g_ref_mu_se

hyper <- learn_alignment_hyperparams(flu_hist, g_ref_fun)

# take one season early weeks
set.seed(1)
s <- sample(levels(flu_hist$season), 1)
currentD <- subset(flu_hist, season == s & newWeek <= 20, c("newWeek","y","neg"))

res <- align_forecast_pipeline_dilate(currentD, g_ref_fun, hyper, level = 0.95)

plot_forecast(res, history = flu_hist)
```
