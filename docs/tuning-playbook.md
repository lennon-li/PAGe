# PAGe tuning playbook

This playbook supplements the guarded stage API. It describes how to design,
diagnose, expand, and stop a tuning search without weakening prospective
evaluation. It does not establish a current best configuration or verify any
historical private result.

## Core rule

A selected value should normally be bracketed by tested values on both sides.
If the winner is at the smallest or largest tested value, the search has not
shown a local optimum in that direction. Treat this as a request for one
controlled expansion in the next development round.

A boundary hit is not automatically a failure:

- `0` can be a meaningful null model, such as an optional M2 smooth being off.
- Probability, count, window, and basis-size parameters have valid limits.
- A simpler boundary value may be preferred by a predeclared one-standard-error
  rule.
- A flat response profile may show that additional expansion is not
  identifiable or practically useful.

Record why a boundary is accepted or expanded. Never silently promote a
boundary winner as though the search bracketed it.

## Holdout-safe tuning loop

1. Before looking at the prospective holdout, freeze the season selection,
   tuning metric, candidate axes, validity constraints, selection rule, and
   grid-size cap.
2. Run a coarse, scientifically plausible grid using identical walk-forward
   folds for every candidate. Save resumable checkpoints.
3. Pass the stage tuning validator. Do not interpret a ranking with incomplete
   folds, all-missing metrics, or a non-finite selected score.
4. Inspect the full response profile, per-season scores, worst season, and
   early/late or phase-specific errors—not only the overall mean.
5. For a winning boundary, add one valid level beyond that boundary using the
   adjacent observed spacing. Retain the current winner, incumbent, and nearest
   interior neighbors.
6. Prefer one-factor local neighbors first. Add targeted interactions only
   when results suggest that two parameters materially interact; avoid
   multiplying every axis into an uncontrolled Cartesian grid.
7. Re-evaluate all finalists on the same complete LOSO folds and apply the
   predeclared final rule: minimum NLL, one standard error, or Pareto.
8. Stop when the selected configuration is bracketed, or when a documented
   constraint/null value justifies the boundary, and performance is stable
   enough across folds for the intended decision.
9. Fit and freeze the selected stage. Only then may the downstream stage begin.
10. Keep the prospective holdout untouched. Changing the grid after viewing it
    starts a new development cycle.

## Boundary report

Preserve a small table with every tuning result:

| Field | Meaning |
|---|---|
| `parameter` | Tuned axis |
| `tested_min`, `tested_max` | Range actually evaluated |
| `selected_value` | Value chosen by the declared selection rule |
| `boundary` | `lower`, `upper`, `none`, or `fixed` |
| `proposed_next` | One new valid value, or `NA` |
| `decision` | `expand`, `accept_constraint`, `accept_null`, or `stop_flat` |
| `reason` | Scientific/statistical justification |

Fixed values are not boundary findings. Only axes with at least two distinct
tested values should be checked.

```r
search_axes <- names(Filter(
  function(x) is.numeric(x) && length(unique(x)) > 1L,
  as.list(tuning_grid)
))

boundary_report <- do.call(rbind, lapply(search_axes, function(parameter) {
  tested <- sort(unique(tuning_grid[[parameter]]))
  selected <- selected_config[[parameter]]
  data.frame(
    parameter = parameter,
    tested_min = tested[1L],
    tested_max = tested[length(tested)],
    selected_value = selected,
    boundary = if (isTRUE(all.equal(selected, tested[1L]))) {
      "lower"
    } else if (isTRUE(all.equal(selected, tested[length(tested)]))) {
      "upper"
    } else {
      "none"
    }
  )
}))
```

Complete `proposed_next`, `decision`, and `reason` explicitly rather than
letting code expand parameters outside their valid domains.

## M0: ignition tuning

Primary search axes include probability thresholds, consecutive-week and
summary counts, and allowable detection windows.

- Expand `p_thr`, `prev_thr`, and `p_sum_thr` by one adjacent probability step.
  Keep them inside their valid probability domains.
- Keep `n_consec`, `K_sum`, `N_req`, `w_min`, and `w_max` integer-valued and
  preserve their logical ordering and operational constraints.
- Do not select from mean absolute error alone. Inspect maximum error, missed
  detections, and early versus late errors by season.
- A boundary at an operationally fixed earliest/latest detection week can be
  accepted only when that constraint is intentional and documented.
- After expanding, rerun the same LOSO seasons and the same lexicographic
  scoring rule. Do not change labels or coordinate systems mid-search.

## M1: alignment tuning

The planned development grid crosses `k_ref = 20, 25, 30, 40, 50` with
`slope_weight = 8, 12, 16, 20, 30`, while other M1 values are fixed.

The `k_ref = 20` level is a strategic extension of the existing artifact
because the fresh M1 winner was `k_ref = 25` at the lower edge. It is a plan
for the next pre-holdout run, not a new result. The fresh slope-weight winner
was interior (`12`), so do not add `slope_weight = 4` unless a later complete
run again selects `8`.

- `k_ref` controls reference-curve flexibility. If `25` remains the lower-edge
  winner, a one-step extension using the adjacent spacing is `20`; if `50`
  wins, the corresponding extension is `60`.
- `slope_weight` is nonnegative. If `8` remains the lower-edge winner, the
  adjacent spacing suggests testing `4`. `0` is a meaningful no-slope-weight
  candidate and should be tested only as an intentional null comparison.
- For `multi_temperature`, positive values near zero make template weighting
  increasingly sharp. Expand carefully—often multiplicatively—and inspect
  weight concentration and fold instability.
- Change integer `slope_window` locally, usually by one or two weeks, rather
  than crossing many window values with every other axis immediately.
- Preserve the manual-label coordinate system and require exact `anchorWeek`
  consistency. A lower MAE is not usable if coordinates drift.
- Record the exact named label vector with every M1 tuning result. By default,
  `tune_m1()` inherits M0 labels and applies the historical one-week M1
  coordinate offset. When reproducing a historical search that used a
  different label vector, pass the unshifted M0-coordinate vector explicitly
  through `manual_labels`; do not silently substitute it for the labels used
  to fit M0 or the production reference.
- Inspect per-season alignment and peak errors. An overall improvement driven
  by one season is weak evidence for added complexity.

The historical `slope_weight = 8` result remains a conflicting artifact rather
than the current fresh selection; it is therefore recorded but not expanded in
the planned grid below. This distinction prevents an unverified historical
boundary from silently changing the next search.

## M2: forecast tuning

M2 has more axes and can produce a very large Cartesian grid. Prefer the
bounded planner:

```r
next_grid <- plan_m2_grid(
  previous_results = prior_m2_results,
  max_finalists = 6L,
  max_specs = 64L
)
```

`plan_m2_grid()` retains the coded v16 incumbent and diverse prior finalists.
For each prior winning boundary, it proposes one valid value beyond the edge
using adjacent observed spacing, adds nearest local neighbors, deduplicates
canonical specification identities, and respects `max_specs`.
The no-history initial plan includes `k_e = 0` alongside positive EMA-basis
neighbors, so the drop/null comparison is available even before prior results
are supplied.

- Treat `k_f`, `k_e`, and optional smooth basis dimensions as small integer
  complexity controls. Increase one step at a time and inspect effective
  degrees of freedom, convergence, and fold stability.
- For optional dimensions such as `k_r`, `k_de`, and `k_sp`, `0` means the
  smooth is off. For the EMA smooth, `k_e = 0` is the explicit drop/null
  comparison and `k_e = 1` is invalid; the supported smooth sizes are `0` or
  at least `2`. Never extrapolate to negative basis sizes or accept `k_e = 2`
  as a bracketed optimum without testing the drop candidate.
- Expand `alpha_state` locally inside its valid decay domain. The planner uses
  `0.05` as its default step when prior spacing is unavailable.
- Do not tune a deployment-time correction parameter merely because it is
  available in a specification. If LOSO cannot identify it, keep it fixed and
  evaluate the canonical runtime correction consistently.
- Preserve stable `spec_id` values, the full candidate grid, provenance, and
  fold scores. Never compare grids whose candidate identities or folds are
  ambiguous.
- In every LOSO fold, remove the held-out season from
  `manual_labels_train` and set `manual_labels_test = NULL`. This forces the
  held-out season through prospective ignition detection. Passing one shared
  label vector to both sides leaks held-out timing and invalidates the M2
  checkpoint; it cannot be repaired by re-ranking cached scores.
- A more complex boundary winner should not be preferred automatically. Apply
  the declared `min_nll`, `one_se`, or `pareto` rule after complete LOSO.

## When to stop expanding

Stop the search when at least one of these documented conditions holds:

- the selected value is interior on every material search axis;
- a boundary is a valid null or hard scientific/operational constraint;
- the response is effectively flat relative to fold uncertainty or a declared
  practical-improvement threshold;
- the one-standard-error rule selects the simpler candidate;
- repeated local expansion does not change the selected configuration; or
- the predeclared computational cap is reached, in which case report the
  unresolved boundary rather than claiming a bracketed optimum.

Grid expansion is model development, not confirmation. Once the candidate is
frozen and the holdout is opened, the grid is closed.

## Existing-artifact boundary decisions (2026-08-01)

The corrected user-test artifact was inspected without rerunning its 1,484-row
M2 grid or any M1 grid. The recorded fresh selections and controlled next
comparisons are:

| Stage/axis | Recorded selection | Edge | Planned comparison | Decision |
|---|---:|---|---:|---|
| M1 `k_ref` | 25 | lower | 20 | expand once |
| M1 `slope_weight` | 12 | interior | — | no expansion |
| M2 `k_e` | 2 | lower non-null edge | 0 | explicit EMA-smooth drop |
| M2 `k_sp` | 8 | upper | 10 | expand once |
| M2 `bias_alpha` | 0.05 | lower | 0 | explicit correction-off null |

The `k_e = 0` and `bias_alpha = 0` rows are null comparisons, not claims that
the corresponding positive-parameter optima are bracketed. The boundary-only
pre-holdout run selected `bias_alpha = 0` as the M2 candidate; `k_ref = 20`
did not improve M1, and the `k_e = 0` and `k_sp = 10` candidates did not
improve M2. A subsequent frozen `2025-26` replay failed the NLL promotion gate
(`0.000048` improvement versus the required `0.02`), although horizon and
phase gates passed. The incumbent is retained. Do not retune against this
holdout result; any further search is a new pre-holdout development cycle.
