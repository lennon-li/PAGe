# M2 amplitude/subtype hypothesis note — 2026-09-22

This note records an exploratory finding for later M2 work. It is not an M1 runtime dependency.

## Finding

Historical influenza-A subtype dominance does not support splitting M1 into separate H1N1 and H3N2 peak-timing models. An oracle same-subtype peak-aligned library worsened M1 peak-time MAE relative to the pooled library.

However, subtype grouping showed a stronger relationship with epidemic amplitude than with ignition-to-peak timing:

- mean ignition-to-peak duration was essentially the same in H1N1- and H3N2-dominant groups;
- H3N2-dominant seasons in this small historical set had higher mean observed peak positivity and higher ignition-to-peak AUC;
- peak-height normalization substantially reduced some apparent subtype differences.

The sample is only 11 seasons and several seasons have mixed subtype or influenza-B circulation, so this is hypothesis-generating rather than a validated subtype effect.

## M2 implication

M2 forecasts numeric influenza-A positivity at +1/+2 weeks and therefore directly models amplitude. Later M2 work should test subtype information as a possible amplitude/variance modifier, preferably hierarchically or as a soft covariate rather than by fitting completely separate small-sample models.

Candidate questions for M2:

1. Does subtype dominance explain residual peak-height or trajectory-scale variation after phase is supplied by M1?
2. Does adding contemporaneously available subtype composition improve +1/+2 positivity forecasts under nested season-excluded evaluation?
3. Are H1N1/H3N2 effects stable after controlling for phase, current positivity, testing volume, and season-level amplitude?
4. Can subtype information improve variance/calibration without materially changing the central forecast?

Do not use retrospective eventual subtype dominance as a runtime feature unless it was actually available at that forecast origin. Historical eventual subtype labels may be used only for exploratory stratification or as training metadata when causal availability is respected.
