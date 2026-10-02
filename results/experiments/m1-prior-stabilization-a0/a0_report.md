# A0 prior-stabilization evidence report

## Scope

This is an isolated, untuned sensitivity experiment. It does not modify
production M0/M1/M2 code, the benchmark contract, or sealed artifacts. All
variants use the frozen ten-season, 334-origin replay and weighted-mean peak
aggregation.

The tested changes were: fixed-zero delta with constrained positive scale,
and the existing delta prior multiplied by 4 or 16 with constrained positive
scale. No cell was selected or promoted.

## Coverage and review

Each variant produced 334/334 full-origin predictions and 92/92 primary
predictions, all finite, with no `pre_ignition` results. The fresh-process
review in `validation/review_a0.txt` passed. The sealed baseline replay
parity was independently checked against its peak ledger.

## Peak metrics

| variant | primary integer MAE | primary decimal MAE | decimal delta vs baseline | full integer MAE |
|---|---:|---:|---:|---:|
| baseline | 1.156121576654504 | 1.244463378226438 | 0 | 0.826347305389222 |
| delta fixed zero + positive scale | 1.156121576654504 | 1.244130309041240 | -0.000333069185191 | 0.826347305389222 |
| delta ridge ×4 + positive scale | 1.156121576654504 | 1.244130309041240 | -0.000333069185191 | 0.826347305389222 |
| delta ridge ×16 + positive scale | 1.156121576654504 | 1.244130309041240 | -0.000333069185191 | 0.826347305389222 |

All three candidate variants retained the baseline integer prediction at all
334 origins. Native continuous peaks changed at all 334 origins, but integer
rounding did not change at any origin. Decimal absolute error improved on 158
origins and worsened on 176 for the fixed-zero and ridge-16 variants; ridge-4
improved on 156 and worsened on 178.

## Stability evidence

The baseline serialized template parameters contain 30 non-positive-scale
rows among 3,006 template-origin fits, all concentrated in 2019-20 (7) and
2022-23 (23). The largest baseline template-peak step was 16.16 weeks in
2022-23; the largest candidate raw peak step was 4.34 weeks in that season.
The candidate raw peak step summaries remain close to baseline, so the priors
did not remove the underlying walk-forward movement mechanism.

## Interpretation

The constrained positive-scale construction removes the most direct structural
invalidity in the replay and produces a very small decimal improvement without
changing operational integer timing. Multiplying the delta prior beyond the
fixed-zero setting made no additional difference here. This is evidence that
positive scale is a useful stability safeguard, but not evidence that stronger
delta shrinkage solves M1’s instability. The remaining large movements are
therefore more consistent with a model/trajectory-state problem than with a
purely numerical rounding problem.

No production setting is recommended or promoted by A0. Any next experiment
should isolate alignment/state dynamics and retain this positive-scale rule as
an explicit candidate constraint, with final optimizer state serialized.
