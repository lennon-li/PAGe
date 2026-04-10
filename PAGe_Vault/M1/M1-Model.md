# M1 Model

## Purpose

M1 aligns the current season's partial epidemic curve to historical templates so the system can estimate current phase, peak timing, and a short trajectory backbone for M2.

## Inputs

- Current-season post-ignition data
- Locked ignition week from M0
- Historical aligned seasons used to build the reference/template set

## Core idea

After ignition, the current season is mapped into aligned-week space and compared to historical templates. PAGe does not rely on a single population template. Instead, it aligns to multiple per-season templates and ensembles them using fit quality.

## Alignment parameterization

The alignment model uses a four-parameter dilation family:

- `tau`: shift in aligned time
- `delta`: dilation or contraction
- `a`
- `b`

These parameters map the observed partial curve onto a candidate historical template. Early in the season, identifiability guards keep the model stable by delaying activation of more flexible parameters.

## Reference representation

Historical seasons are first aligned to a common anchor week using known ignition labels. A factor-smooth GAM is then used to produce per-season template curves. This gives M1 access to:

- a population-level reference backbone
- per-season template curves for multi-template matching

## Ensemble logic

For each evaluation week:

1. Align the current partial curve to each candidate template
2. Score each template by alignment NLL
3. Convert scores to ensemble weights using a softmax temperature
4. Blend template forecasts into an ensemble forecast and peak estimate

This lets the pipeline recognize whether the current season behaves more like a steep or gradual historical season.

## Peak handling

M1 continuously updates peak timing until the peak is considered passed. Once `peak_passed == TRUE`, alignment freezes so the descending limb does not distort the estimated peak.

## Tuned behavior

The documented tuned configuration is:

- `k_ref = 25`
- `temperature = 0.25`
- `shift = 0`

Reported primary tuning metric:

- Weibull-weighted peak MAE around 1.169 weeks in LOSO walk-forward evaluation

## Output to M2

M1 emits alignment-derived covariates including:

- `newWeek`
- `tau`
- `delta`
- peak timing estimates
- template-based trajectory features such as effective template positivity on the logit scale

## References

- `docs/pipeline_overview.qmd`
- `docs/estimateRef.qmd`
- `docs/loso_walkforward.qmd`
- `docs/peak_detection_tuning.qmd`
- [[M1-Implementation]]
- [[M2-Model]]
