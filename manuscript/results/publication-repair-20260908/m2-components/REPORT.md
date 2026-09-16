# M2 predictor effects and online-correction diagnosis

Date: 2026-09-08. Status: executed locally, diagnostic only. No fitting,
tuning, kit changes, promotion, or hypothesis tests were performed.

## Evidence and verification

The definitive tables are in `verified/`; the root CSV files preserve the
initial diagnostic execution. Both executions give identical scores. The
script is `scripts/publication_m2_component_audit.R`. Reproduce into a new,
non-existing directory by sourcing it and calling
`audit_m2_components(output = "<new-output-directory>")` from the repo root.

Inputs are the eleven registered frozen kits, authorized Ontario influenza
counts, and repaired replay `20260908T125939`. The input hash is in
`verified/metadata.json`. Reconstructed raw GAM links match saved links
exactly; the median-reference season adjustment matches the runtime helper
at the first and last origin of every season exactly; reconstructed final
predictions match all saved M2 rows to at most 5.6e-17 probability units.

Primary scores use the same 138 available h2 targets, origins 0--12 weeks
after the locked declaration, with count-weighted NLL/MAE within each season
and equal-season means. Ten seasons contribute 13 targets each; partial
2025-26 contributes eight. Secondary h1 uses its own available matched rows.

## Component ablations

Except for M1-only and raw GAM, all variants retain the identical fitted GAM,
probability cap, and M1-derived post-peak switch. Online states can be
decomposed without retraining because their residual updates use the saved
raw GAM links, not adjusted predictions. M1 and the switch do not depend on
M2's corrected output.

| Variant | h1 NLL | h2 NLL | h2 MAE (percentage points) |
|---|---:|---:|---:|
| M1 only | 0.443750 | 0.460079 | 5.0304 |
| Raw GAM, no cap/switch/online correction | 0.443892 | 0.458218 | 4.4964 |
| GAM + existing switch, neither online correction | 0.444544 | 0.459408 | 4.6820 |
| Horizon-specific bias only | 0.444213 | 0.459447 | 4.7064 |
| Season-level shift only | 0.446877 | 0.461665 | 5.2579 |
| Both online corrections: current pipeline | 0.447485 | 0.462821 | 5.4065 |

The season-level shift is the principal aggregate problem. Added alone to
the no-online variant, it worsens NLL by 0.002333 at h1 and 0.002256 at h2.
Horizon bias alone improves h1 NLL by 0.000331, but worsens h2 by 0.000039.
These are descriptive differences, not inferential statements. The raw-GAM
comparison also indicates that the hard post-peak switch needs its own review.

## Why the season-level shift is problematic

M1 already refits a logit intercept against each observed prefix, including
when amplitude scaling is disabled; when enabled it also estimates a slope.
See `PAGe/R/align_forecast_pipeline_dilate.R:83` and the prefix construction
in `PAGe/R/pipeline_bridge.R:110`.

The M2 online season estimator receives raw observations without the fitted
GAM's actual forecast covariates. It substitutes training medians for missing
numeric features and the first lead, h1. In these eleven kits, its reference
prediction is therefore constant within season. The implemented shift is:

\[
 r_t = \frac{\sum_{u=i_t}^{t}\{\operatorname{logit}(y_u/N_u)-c_{h1}\}}
 {n_t+1},
\]

where the observations use the runtime's probability clipping, `i_t` is the
current M1 ignition estimate, and `c_h1` is the GAM at training-median
predictors with the historical season effect excluded. This is not an error
against the actual historical forecasts at their corresponding targets.
It can interpret progression through the epidemic as a season-level error.
See `PAGe/R/m2_training.R:806`.

A second, horizon-specific correction uses actual matured raw-GAM forecast
errors. Adding the two corrections does not separate their roles; it can
duplicate adjustments. The empirical ablation establishes harm from the
current combination, but does not prove that M1 self-alignment explains all
of it. Adaptive horizon-bias updates can reach 0.7 even with base alpha zero.

## Predictor effect sizes

All eleven kits use a smooth M1 predictor, not an offset. The following
describes the fitted raw GAM on the primary h2 rows, before correction and
switching. Each effect span is the within-season 90th minus 10th percentile
of the term's fitted log-odds contribution, summarized by the median across
kits where that term is present. It is not a coefficient, causal effect,
or permutation importance.

| Predictor term | Kits containing term | Median contribution span (log-odds) |
|---|---:|---:|
| M1 forecast logit | 11 | 0.8104 |
| Recent positivity EMA | 11 | 0.2623 |
| EMA minus M1 logit | 5 | 0.3265 |
| M1 ensemble spread | 9 | 0.1324 |

Finite differences of the full raw GAM give a median across season-specific
median sensitivities of **0.5641** logit units per unit of supplied M1 logit.
The corresponding seasonal medians range from **0.1090 to 1.1394**. This
calculation holds EMA/spread fixed and consistently updates
`z_resid = z_ema - logit_f_eff`; it excludes online corrections, switching,
and the feature-clamp derivative. Direct M1-smooth derivatives are separately
stored in `verified/slopes.csv`. Correlated features make attribution
unstable, so these sensitivities do not by themselves prove overfitting.

## Recommendations

1. Retire the current median-reference season adjustment from the next
   development candidate. Retain immutable historical kits/results.
2. Start the new candidate without either online adjustment. Retain
   horizon-bias-only as an explicit comparator, given its small mixed effects.
3. Test M1 as a fixed logit offset with a strongly regularized M2 correction:
   `logit(p_final) = logit(p_M1) + g_h(prefix features)`. Fit to positive/total
   counts with a binomial loss, not Gaussian regression on raw percentages.
   Include the zero-correction/M1-only candidate. Penalize the correction,
   including any freely estimated calibration intercept, toward zero.
4. This is residual correction, not necessarily an iterative boosting
   algorithm. If using formal gradient boosting, initialize its margin with
   the M1 logit and fit binomial-loss gradients with training-only stopping.
5. Do not just change `template_mode`: runtime currently clamps the M1
   logit to a training feature range. A baseline offset should preserve M1
   (apart from a documented numerical epsilon), including at extremes.
   Features involving M1 can still alter overall sensitivity despite a
   fixed offset coefficient; control their flexibility explicitly.
6. Use season-cross-fitted, within-season prefix-safe M1 predictions for
   training the correction, and match the tuning score/window to reporting.
   Freeze the selected correction once per target season. Evaluate the
   post-peak switch separately. All work prompted by these observed holdouts
   must be labelled a new development/sensitivity analysis, not untouched
   prospective confirmation.

No offset-based model has been fitted in this diagnostic, so its superiority
is not established. M1-only has the lowest h1 NLL among the listed variants;
raw GAM has the lowest h2 NLL. There is no universally best variant here.

References: [mgcv prediction/term decomposition](https://stat.ethz.ch/R-manual/R-patched/library/mgcv/html/predict.gam.html),
[mgcv offset model example](https://stat.ethz.ch/R-manual/R-patched/library/mgcv/html/gam.models.html),
[mboost gradient-boosting tutorial](https://stat.ethz.ch/CRAN/web/packages/mboost/vignettes/mboost_tutorial.pdf).
