# M1-v2 exploration findings — 2026-09-22

## Current truth and upstream state

- Expert input is decimal ignition only.
- Retrospective peak truth is `retrospective-gam-peak-v1-k8`.
- M0-v2 strict LOSO against the decimal ignition labels has MAE 0.366 weeks, max absolute error 0.911 weeks, and zero misses.
- Runtime M1 anchors on causal M0 detection `A`, not expert ignition `I*`.

## Peak-aligned historical shape

Completed historical seasons were smoothed with the restrained retrospective GAM and aligned by `tau = t - T*`.

The curves become materially more homogeneous inside roughly six weeks of peak. This supports a pooled peak-relative canonical shape as the primary M1 representation.

Derived AUC and AUC-change features are useful for exploratory interpretation, but direct M1 ablation shows they do not improve peak-time matching once recent positivity is present.

## Feature ablation

On 97 causal origins under season-excluded peak-aligned libraries:

- positivity only, current + previous week: MAE about 1.334 weeks;
- positivity with longer history: no improvement;
- adding 2-week or 3-week AUC: small deterioration;
- AUC-only: worse;
- scale-invariant ratios/growth only: much worse (best MAE about 3.83 weeks).

Conclusion: absolute positivity level carries real phase information. AUC should not be added to M1 merely because it is correlated with phase.

## Amplitude identifiability

Freely profiling season amplitude is not viable for early M1. It allows an implausibly small peak amplitude to make early low observations compatible with an artificially near peak; MAE increased to about 2.77 weeks.

A season-excluded historical peak-amplitude prior resolves much of this confounding. A strongly regularized amplitude nuisance (`b`) performs better than either free amplitude or no amplitude adjustment.

Best tested constant prior weight: 8, MAE about 1.253 weeks.

A slowly relaxing prior after M0 detection improves slightly further:

- overall 97-origin MAE: 1.245 weeks;
- 0-2 week true lead MAE: 0.764;
- 2-4 week lead MAE: 1.225;
- 4-6 week lead MAE: 1.583;
- >6 week lead MAE: 1.360.

On the 91 origins shared with frozen M1-v1 v16 and rescored against the new GAM peak truth:

- M1-v2 prototype MAE: 1.233 weeks;
- frozen v16 MAE: 1.354 weeks;
- M1-v2 RMSE: 1.515;
- frozen v16 RMSE: 1.702.

This is not yet a release benchmark. It is an exploratory common-ledger comparison.

## Remaining hard season

2023-24 remains the dominant M1-v2 failure (about 2.64 weeks MAE in the current prototype), while frozen v16 performs unusually well on that season. It is also the lowest-amplitude historical season and has smoothing-sensitive peak truth. This season should be diagnosed explicitly rather than addressed by global model complexity.

## Current preferred M1 direction

Keep M1 small:

1. pooled peak-aligned canonical shape;
2. direct candidate peak time `T`;
3. observed positivity/count likelihood;
4. positive season amplitude as a nuisance parameter with a season-excluded historical prior;
5. amplitude shrinkage strong immediately after M0 detection and relaxed gradually as causal observations accumulate;
6. no subtype hard split;
7. no AUC feature unless a future controlled ablation demonstrates incremental value;
8. explicit posterior uncertainty and separate peak-passage logic.

Next work should diagnose 2023-24 and then replace the current heuristic score with a formally specified likelihood/posterior under the same low-dimensional architecture.
