# Validation and final model (lean Methods draft)

Draft 2026-09-15. Detailed reference: `docs/validation-and-final-kit.md`.

## Training procedure

For a given set of training seasons, the training procedure tuned and froze
the three stages in order. M0 detector settings, M1 alignment settings, and M2
forecast-correction settings were each selected by leave-one-season-out
evaluation within the training seasons, with within-season walk-forward
prediction. A selected value at a grid boundary triggered expansion by one
valid step before freezing. For M1, the smallest reference-curve basis
dimension whose best specification was within 0.05 weeks of the lowest
peak-timing error, and which did not require boundary expansion, was selected.
M2 was adopted only if its
phase-weighted log-loss gain over M1 was at least 0.0012 overall and 0.002 at
the two-week horizon, met a 0.95 confidence bound, and did not degrade any
season; otherwise the M2 correction was switched off and forecasts equalled M1.
Phase weights were 0 before ignition, 2 for weeks 0-12 after ignition and 1
thereafter, with equal weight per week and per season. The procedure, including
all grids, rules, and weights, was fixed before evaluation.

## Outer evaluation

Each of the 11 eligible seasons was held out in turn. The training procedure
was applied to the remaining 10 seasons, the resulting model was frozen, and
the held-out season was then forecast week by week using only data available
at each origin, without refitting. Each fold selected its own settings. This
leave-one-season-out design estimates performance on an unseen season; it is
exchangeable rather than chronological. When the adoption rule retained M1,
the tuned M2 candidate was also forecast on the held-out season as a separate
output, which did not affect the fold's decision or reported forecasts. These
paired forecasts were used to assess whether gains observed during tuning
carried over to unseen seasons.

## Final operational model

The operational model for the 2026-27 season was obtained by applying the same
training procedure once to all 11 eligible seasons. Its settings were selected
by that run's own leave-one-season-out tuning rather than taken from any outer
fold. The frozen model was applied weekly without refitting. Because no season
was withheld, its expected performance is the outer-evaluation estimate for the
same procedure.

## Procedure changes

Analyses of the outer folds, such as the relationship between tuning-stage and
held-out gains, informed future versions of the procedure only. Any change made
after outer results were available was recorded as a dated deviation, treated
as a new development cycle, and not presented as confirmation.

<!-- Pending: shadow M2 replay implementation (in progress); outer-cycle
completion; platform statement; label-sensitivity analysis. -->
