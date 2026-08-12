# Pipeline overview

> **Caution**
>
> This article describes the coded pipeline and historical research
> results. It does not prove that a private-data acceptance run,
> fixed-spec refresh, or immutable promotion completed. Use
> `docs/deployment-workflow.qmd` in the repository for the governed
> release sequence.

PAGe produces prospective one- and two-week-ahead forecasts of
respiratory-virus positivity. Within each issue week, M0 detects
ignition, M1 aligns the partial epidemic curve to historical templates,
and M2 consumes the alignment state in a binomial GAM.

## Prospective contract

Historical M2 evaluation uses walk-forward LOSO folds with fold-specific
M1 features. M0 and M1 hyperparameters were selected globally before
that M2 evaluation, so the recorded analysis is conditional rather than
fully nested over every modelling decision. M1 runs before M2 each week
so M2 sees only contemporaneously available alignment covariates.

## Coded incumbent configuration

The current v16-corrected incumbent uses `k_f=4`, `k_e=2`,
`alpha_state=0.20`, `k_sp=8`, `k_r=0`, `k_de=0`, `delta=0`, `Kr=1`,
`bias_alpha=0.05`, and `bias_beta=0`. Historical notes record a private
nested-LOSO result, but its source artifact is absent and no immutable
promoted kit is preserved here. The frozen path updates the Holt
correction and post-ignition online season effect; weekly refitting is
compatibility behavior.

## Training governance

The guarded stage lifecycle is:

``` text
validate_season_selection
  -> tune_m0 -> validate_m0_tuning -> fit_m0 -> freeze_m0
  -> tune_m1 -> validate_m1_tuning -> fit_m1 -> freeze_m1
  -> tune_m2 -> validate_m2_tuning -> fit_m2 -> freeze_m2
  -> assemble_kit -> validate_page_kit
```

Every downstream stage requires frozen, selection-matched upstream
identities.

`train_pipeline(mode="refresh")` remains a compatibility orchestrator
that refits the locked specification. `mode="retune"` builds an adaptive
grid from compatible prior results, keeps the incumbent and diverse
finalists, adds neighbors, and expands reached boundaries. Minimum NLL
is the default selection rule; one-standard-error and Pareto selection
are explicit alternatives. Optional staged racing eliminates only clear
losers and always evaluates survivors with full nested LOSO.
[`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
now composes the guarded lifecycle for both refresh and retune while
preserving its compatibility result shape. Use the explicit stage calls
when a manual cycle must stop and be inspected at each gate.

After each tuning round, inspect whether the selected value is at a
tested minimum or maximum. Normally expand a winning edge by one
adjacent valid step, retain the winner/incumbent/local neighbors, and
rerun the same complete folds. Do not explode every axis factorially. A
boundary can be accepted when it is a documented null or hard
constraint; otherwise report it as unresolved rather than claiming a
bracketed optimum. All grid expansion precedes holdout review.

The 2025-26 season is replayed as an unseen holdout. It may enter
training for 2026-27 only after promotion demonstrates at least 2% NLL
improvement, no more than 5% horizon-MAE degradation, and no more than
10% phase-MAE degradation.
