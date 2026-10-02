# PAGe manuscript governance decisions

- Record version: 1.1
- Decision date: 2026-09-01
- Scope: Ontario influenza manuscript analysis
- Authority: project-lead instruction and repository evidence available before
  the new manuscript analysis

## Governing constraint

The Ontario influenza manuscript analysis must not add a season that is not
already used by the current governed influenza workflow. Increasing the season
count is not a reason to import, reconstruct, or newly admit historical or
future-season observations. The exact season membership is frozen in
[`ONTARIO_FLU_SEASON_DECLARATION.md`](ONTARIO_FLU_SEASON_DECLARATION.md).

This constraint was recorded before the new fully nested manuscript result
tables were opened. Changing it requires a new dated protocol cycle and cannot
be justified by model performance.

## Decision register

| ID | Decision | Status | Evidence and interpretation |
|---|---|---|---|
| G-01 | Use all 11 non-excluded influenza seasons as one exchangeable analysis set. | Closed | The available 15-season span minus the four fixed exclusions yields 11 valid seasons. No new season is admitted. |
| G-02 | Keep `2011-12`, `2015-16`, `2020-21`, and `2021-22` outside the principal exchangeable-season analysis. | Closed for analysis membership | These are the current governed workflow exclusions. `2015-16` may be reported only as separately labelled special diagnostic evidence; it is not pooled into the principal aggregate. |
| G-03 | Treat `2025-26` like every other valid season in the new rotating-holdout analysis. | Closed | It may be an outer holdout and, when another valid season is held out, it enters training on the same terms as the other 10 training seasons. Its earlier acceptance replay remains separately disclosed and prevents calling the new `2025-26` fold untouched confirmation. |
| G-04 | Do not expand the season universe through newly retrieved influenza data. | Closed | Direct project-lead instruction on 2026-09-01. |
| G-05 | Use origin-time data vintages when reconstructible; otherwise use one final-data snapshot consistently for every model and label the analysis a final-data retrospective replay. | Closed as analysis rule | No model receives a more favorable vintage. A final-data analysis must disclose that reporting-delay and revision effects are not fully reproduced and must include a sensitivity analysis if suitable vintage information exists within the authorized current data. |
| G-06 | Treat the historical `0.02` threshold as a relative operational promotion rule, not as the manuscript's scientific effect threshold. | Closed | The 2% relative-NLL gate entered package code in commit `feebaa0` on 2026-07-16, before the recorded 2025-26 acceptance replay on 2026-08-01. No source found documents a clinical or statistical rationale for choosing 2%. The manuscript primary interpretation therefore remains the effect estimate and season-level interval around zero. |
| G-07 | Do not release private Ontario rows in the public repository. | Closed | The public workflow uses synthetic inputs and disclosure-safe outputs; authorized private inputs are supplied by file path. |
| G-08 | Obtain written data-custodian authorization and disclosure limits before publishing Ontario results. | Pending external evidence | No authorization is inferred from repository access or from this planning instruction. |
| G-09 | Obtain and record the applicable ethics/REB determination before submission. | Pending external evidence | No determination is invented here. |

## Season-exclusion wording for the manuscript

The manuscript should describe the four excluded seasons as the prespecified
current-workflow exclusion set. It should not retrofit a detailed biological or
data-quality explanation that is absent from the evidence record. If the data
custodian supplies a documented reason for an individual exclusion, that reason
may be added without changing season membership.

`2015-16` is a special governed ignition/drop-test cycle in the project archive.
Its result may illustrate failure behavior, but it is not an exchangeable
principal fold and cannot increase the principal sample size. `2020-21` and
`2021-22` remain pandemic-era data-contract exclusions. `2011-12` remains the
historical data-contract exclusion used by the current pipeline.

All 11 remaining seasons have equal analytical status. Each is held out once;
the other 10 valid seasons are used for training and inner tuning. No valid
season is always reserved, down-weighted, or omitted from training because of
its calendar position.

## Historical promotion-gate provenance

The package function `check_promotion()` encodes:

- at least `0.02` relative Bernoulli-NLL improvement;
- no more than `0.05` relative horizon-MAE degradation; and
- no more than `0.10` relative phase-MAE degradation.

These are operational candidate-versus-incumbent release controls. They are
not the estimand or minimum important difference for the manuscript's
PAGe-versus-calendar-GAM comparison. The historical 2025-26 candidate failed
the NLL gate and was not promoted; that decision is preserved unchanged.

## Backfill and revision rule

For every scored origin, use the vintage available at that origin when the
authorized source permits reconstruction. If vintage reconstruction is not
possible:

1. freeze one authorized final-data snapshot before fitting;
2. use that same snapshot and row set for PAGe and every comparator;
3. prohibit revised target values from entering origin-time features;
4. identify the analysis as final-data retrospective replay; and
5. retain revision/backfill as a limitation rather than implying real-time
   prospective performance.

## Change control

Any proposal to add an influenza season, move one of the four exclusions into
the valid set, alter a frozen ignition label, or reinterpret the 2% promotion
gate as a scientific threshold requires a new protocol version before result
inspection. The existing analysis cannot be silently amended.

## Repository evidence consulted

- [`../PAGe/R/training_plan.R`](../PAGe/R/training_plan.R)
- [`../docs/pipeline_walkthrough.qmd`](../docs/pipeline_walkthrough.qmd)
- [`../docs/holdout_loso_workflow.qmd`](../docs/holdout_loso_workflow.qmd)
- [`../docs/baseline-evidence-inventory.md`](../docs/baseline-evidence-inventory.md)
- [`../docs/boundary-expansion-2026-08-01.md`](../docs/boundary-expansion-2026-08-01.md)
- [`../PAGe/R/evaluation_gates.R`](../PAGe/R/evaluation_gates.R)
- [`../scripts/fresh_run/00_shared.R`](../scripts/fresh_run/00_shared.R)
