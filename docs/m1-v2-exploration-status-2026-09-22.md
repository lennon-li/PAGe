# M1-v2 exploration status — 2026-09-22

## Governing separation

M1 remains a peak-timing model. M2 remains the +1/+2 amplitude/positivity forecasting model.

The literature/subtype exploration suggests influenza A subtype is more relevant to amplitude than to ignition-to-peak timing in the current 11-season sample. This should be retained as an M2 hypothesis, not used as a hard M1 split.

## M2-relevant subtype finding

Season-level dominant-A subtype metadata was assembled from PHAC/PHO surveillance. In the current sample:

- H1N1- and H3N2-dominant seasons have almost identical mean ignition-to-peak duration (~8.78 vs ~8.77 weeks).
- H3N2-dominant seasons have higher mean observed peak positivity and higher ignition-to-peak AUC.
- Hard subtype-specific M1 libraries worsen LOSO peak-time inference.

Therefore subtype may be useful later as a soft amplitude/variance modifier for M2, but not as a separate M1 timing model.

## Current M1 truth/runtime contracts

- ignition truth: expert decimal ignition;
- runtime anchor: causal strict-LOSO M0-v2 detection A;
- peak truth: retrospective GAM peak (`retrospective-gam-peak-v1-k8`);
- M1 target: direct continuous peak time T;
- training shape coordinates: peak-relative tau = t - T*;
- held-out season is excluded from canonical-shape construction.

## Peak-aligned shape findings

Peak alignment substantially reduces between-season dispersion in the final ~6 weeks before peak. Smoothed positivity, local AUC, and AUC-change all show structured peak-relative behavior.

However, causal LOSO ablation shows that local AUC does not add independent timing information once recent positivity is present:

- positivity only, 3-week window: MAE ~1.337 weeks;
- positivity + 2-week AUC: ~1.394;
- positivity + 3-week AUC: ~1.420;
- positivity + both AUC features: ~1.444.

Thus AUC remains useful for biological exploration and M2 amplitude/shape work, but is not currently justified in M1 timing likelihood.

## Amplitude experiments

Two attempts to remove absolute amplitude from M1 were unsuccessful:

1. free profiled amplitude per candidate peak: MAE ~2.77 weeks;
2. scale-free AUC/positivity ratios: MAE ~3.46 weeks.

The free-amplitude model degenerates early by explaining low early positivity as an implausibly low epidemic peak. Absolute positivity therefore contains genuine phase information for M1.

A hard subtype split also worsened M1 (oracle subtype library ~1.57 vs pooled ~1.41 weeks).

## Current best M1 prototype

Current best structure:

- pooled leave-one-season-out peak-aligned canonical curve;
- logit-smoothed historical positivity shape;
- observed runtime `y/N` remains unsmoothed;
- empirical-logit observation;
- observation variance = historical between-season logit-shape variance + binomial sampling variance;
- last 2 causal observed weeks;
- candidate peak grid; direct MAP over peak time.

Across 97 causal origins:

- MAP MAE ~1.327 weeks;
- posterior median MAE ~1.305 weeks.

On 91 origins shared with frozen legacy M1-v16 (10 seasons), rescored against the new GAM peak truth:

- M1-v2 count-aware logit MAE ~1.319 weeks;
- legacy M1-v16 rescored MAE ~1.336 weeks.

This is a near tie/slight v2 improvement, with a much simpler and more identifiable architecture.

## Residual problem

2023-24 is the clearest pooled-shape failure (v2 MAE ~2.5 weeks on its causal origins). Equal-mixture matching over all fixed historical peak-aligned templates did not solve it and worsened overall MAE to ~1.42 weeks; 2023-24 worsened further.

This argues against restoring flexible historical-template matching.

## Uncertainty

The raw count-aware likelihood is overconfident:

- nominal 90% interval coverage ~70%;
- mean 90% width ~3.63 weeks.

Season-excluded likelihood tempering selected mostly power 0.3 and produced:

- cross-fitted nominal-90 coverage ~87.6%;
- mean 90% width ~7.38 weeks.

This improves calibration but is too diffuse for an ideal operational posterior. Uncertainty calibration therefore remains an open M1 task.

## Current direction

Keep M1 simple and pooled. Do not add subtype, AUC, free amplitude, or unrestricted template matching unless future evidence reverses the current LOSO results.

Next work should focus on a constrained low-dimensional shape-deviation model or another identifiable explanation for the 2023-24-type residual heterogeneity, while preserving direct peak-time inference and nested season exclusion.
