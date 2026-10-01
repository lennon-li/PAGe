# Audit of the M1 retune plan, Sections 1–2

Date: 2026-09-19  
Scope: objective and API only; no implementation review or changes  
Verdict: **do not start the compute sweep under the draft objective.**

The draft identifies the right defect, but its primary peak score is nearly
degenerate on the incumbent, its 50/50 scalarization is grid-dependent, and
its artifact schema is too coarse to guarantee re-scoring. Those are
pre-compute blockers, not matters to leave to sensitivity analysis.

## 1. Objective audit

### 1.1 Lead-time-at-lock is not suitable as the primary peak metric

The proposed score captures two valid ideas: a correct peak-location estimate
is more valuable when available earlier, and a transient correct estimate is
not a stable signal. The literal definition is nevertheless too brittle to
rank a large grid reliably.

The `for all origins w' in [w, P_s]` clause makes `lock(s)` the first origin
after the **last** tolerance violation before the peak. One estimate just over
the threshold at `P_s - 1` can erase an otherwise excellent early trajectory
and set the entire season to zero. Conversely, a spec that first becomes
accurate at `P_s - 1` and stays accurate for one update receives positive
credit. The score therefore measures the length of the final uninterrupted
run inside a hard band, not the total quality or actionability of the early
trajectory.

Specific cases behave as follows:

- A spec that is correct at the first eligible origin by luck but then leaves
  the band is properly rejected by the persistence clause. If it happens to
  remain in the band, the retrospective metric cannot distinguish luck from
  information. With only 11 seasons and a large grid, selection will actively
  find such lucky trajectories.
- A spec that locks late but tightly gets a small positive score if the lock is
  strictly pre-peak and zero at the peak. That part matches the principal's
  stated constraint.
- A spec that is accurate early and for nearly the whole rise, but misses the
  band once just before the peak, gets zero. This is a disproportionate
  penalty and is the main pathology of “holds all the way to the peak.”
- Missing or failed origins are undefined in the formula. If the code simply
  quantifies over rows that exist, a failed difficult origin vanishes and can
  improve the apparent lock. The expected origin grid must be explicit, and a
  missing estimate must break a lock or incur a prespecified penalty.
- Including the origin at `P_s` lets a nowcast made after observing the peak
  invalidate every genuinely prospective estimate before it. The persistence
  window should end at the last strictly pre-peak origin. Calls at or after the
  peak should receive no lead credit, as requested, rather than retroactively
  canceling all prior credit.

The non-differentiability is not itself a problem for grid search; gradients
are not being used. The flatness and ties are the problem. A direct calculation
using the frozen kit's forecast-available origin rows and Task B's peak targets
shows the severity:

| `tol_lock` | raw peak: mean lead / nonzero seasons | smoothed peak: mean lead / nonzero seasons |
|---:|---:|---:|
| 0.5 | 0.000 / 0 | 0.073 / 1 |
| 1.0 | **0.000 / 0** | **0.427 / 3** |
| 1.5 | 0.273 / 1 | 1.782 / 6 |
| 2.0 | 1.364 / 4 | 2.245 / 8 |
| 3.0 | 3.182 / 6 | 4.809 / 9 |

At the proposed one-week tolerance, every season scores zero against the raw
target. If many candidate specs do likewise, the nominal 50% peak component
has no effect and the sweep silently becomes forecast-only; tie-breaking will
come from the other component or row availability. The table also shows that
`tol_lock = 1` is not a harmless convention. Small changes alter both the mean
and the number of informative seasons dramatically.

The raw target is also unstable. In Task B, the absolute raw-versus-smoothed
peak shift averages 0.79 weeks and reaches 1.7 weeks. That is of the same order
as the entire one-week acceptance band. For the incumbent, changing only the
target moves mean lead from 0.000 to 0.427 weeks. A “sensitivity” that changes
which seasons contribute any signal is not secondary; it means the peak truth
definition is unresolved.

An argmax of a noisy weekly series is particularly indefensible for a plateau.
It selects one week from an epidemiologically equivalent set, and the result
depends on noise and tie-breaking. The plan should define a peak interval
`I_s = [P_s^-, P_s^+]` from a prespecified smoother and plateau rule, then
score `d_s(w)`, the distance from the estimated peak to that interval. The
principal must also decide whether “peak” means plateau onset, midpoint, or
maximum; for early warning, plateau onset is the coherent zero-lead boundary.
The smoother, basis/penalty, and plateau rule must be fixed without reference
to candidate performance.

A better primary form is a bounded, continuous, lead-weighted accuracy score:

```text
k_s(w) = exp{-d_s(w)^2 / (2*kappa^2)}
S_s = sum_{w < P_s^-} (P_s^- - w) * k_s(w)
      / sum_{w < P_s^-} (P_s^- - w)
peak_score = mean_s S_s
```

This gives no credit at or after plateau onset, rewards the same accuracy more
when it occurs earlier, penalizes every oscillating origin, and does not let one
near-peak miss annihilate a season. `kappa` is still a scale choice, but it can
be tied to a declared one-week meaningful error and audited over a short fixed
range. If persistence is operationally essential, replace `k_s(w)` by the
geometric mean over a fixed two- or three-origin confirmation window. Do not
require correctness over an arbitrarily long remainder of the season. Retain
the hard lock curve at several tolerances as a diagnostic, not as the primary
selection metric.

### 1.2 The forecast component is underspecified and can reward failure

Pooling all origin-by-horizon rows gives longer seasons and horizons with
better availability more influence than shorter or harder ones, while the
peak component weights seasons equally. “50/50” between components is not
meaningful when their sampling units differ. Compute MAE within each
season-by-horizon cell, average horizons equally within season, then average
the 11 seasons equally. Report the pooled number only as a descriptive
secondary metric.

“Over all origins with a forecast” is unsafe. A spec can improve MAE by failing
on difficult origins. Scoring must start from a complete expected key set
`season × origin × horizon`; missing predictions and non-convergence must be
visible in the denominator and handled by a fixed failure rule. The current
phrase “more than a small fraction” is not a rule and must be replaced by an
exact threshold before the sweep.

Finally, percentage-point MAE is not obviously the loss implied by the stated
defect. M2 consumes `m1_logit` as a coefficient-1 offset, so unit-gain
propagation occurs on the logit scale, while the governed M2 evaluation uses
Bernoulli NLL. A pp-MAE objective may be defensible as the public-health point
loss, but the plan must say why. At minimum, logit error and Bernoulli NLL
should be retained as prespecified guardrails; otherwise M1 can improve pp MAE
while the offset pathology remains.

### 1.3 Sweep-relative z-scores are disqualifying as the selection objective

For ranking, the proposed objective is equivalent to

```text
0.5 * peak_score / sd_grid(peak_score)
- 0.5 * forecast_mae / sd_grid(forecast_mae)
```

up to constants. Adding irrelevant bad specs changes the two grid standard
deviations and therefore changes the effective exchange rate between one week
of peak performance and one percentage point of forecast error. A candidate
can beat another candidate, then lose to it after unrelated rows are appended
to the grid. That violates independence from grid composition and makes the
result irreproducible under required boundary expansion.

The proposed stability check is insufficient. Range normalization is also
grid- and outlier-dependent. “Peak within tolerance of best, then forecast” is
a lexicographic/constrained rule, not a 50/50 rule, and its feasible set still
depends on the observed best. Agreement among these three on one grid does not
remove their shared dependence on that grid, nor does disagreement define a
decision.

Use fixed, preregistered anchors instead. One direct formulation is

```text
J = 0.5 * (peak_score - peak_incumbent) / Delta_peak
  - 0.5 * (forecast_mae - mae_incumbent) / Delta_mae
```

where the incumbent values are immutable and `Delta_peak` and `Delta_mae` are
meaningful improvement scales fixed before the sweep. The continuous peak
score above is already bounded; alternatively both components can be mapped to
[0, 1] using fixed “good” and “unacceptable” anchors. Either approach makes
50/50 an explicit utility judgment and guarantees that adding grid rows cannot
change the ordering of already-scored specs. Report a Pareto plot and alternate
fixed anchors as sensitivity analyses, but select under one preregistered rule.

### 1.4 Peak location and `peak_passed` are separable outcomes, but not independent

The code answers this precisely. `align_multi_template()` computes the reported
peak location as the weighted mean of per-template peak weeks, while its upper
bound is the 97.5% weighted quantile of those same peak weeks using the same
weights (`m1_multi_template.R:288–301`). `peak_status_from_align()` then sets
`peak_passed = (last_obs >= upper_quantile + buffer)`
(`m1_peak_status.R:46–53`). Thus:

- Optimizing location accuracy does **not necessarily** cause earlier false
  passage. The mean can become more accurate while the upper tail stays put or
  widens, and reducing both bias and spread can improve both outcomes.
- They are not independent. Every grid axis that changes per-template peaks or
  ensemble weights can change both the mean and upper quantile. A small weight
  change can also move a weighted quantile discontinuously. Optimizing only the
  mean provides no guarantee about the gate.
- “Early location detection” means estimating the correct calendar peak at an
  earlier origin. It does not mean estimating an earlier peak date. The draft
  should state this explicitly because confusing the two would indeed create a
  self-contradictory objective.

The interval called a CI is an across-template weighted interval, not a
demonstrated calibrated 95% uncertainty interval for peak time. It does not,
in this calculation, incorporate the full uncertainty of each alignment.
Using its upper bound as a safety gate and then imposing “no false fire at any
origin” is therefore brittle. Task B's 7/11 early fires are evidence of that
brittleness, not merely a bad threshold value.

The two tasks should remain separate in the artifact and evaluation: tune and
score peak-location trajectories, then calibrate a declared passage rule using
the upper-tail trajectory plus buffer/persistence/decline evidence. The gate
configuration must be part of the spec. This matters because the runtime
helper defaults to `buffer_weeks = 0`, while the current high-level `tune_m1()`
call passes `buffer_weeks = 5`; “peak_passed” is not reproducible without
recording which rule was used.

The draft's absolute constraint—one early `TRUE` disqualifies the entire
spec—may leave no useful feasible grid and will be highly selection-sensitive
on 11 seasons. If zero early passage is a genuine safety requirement, enforce
it by construction with a conservative, latched sequential rule and validate
that rule separately. Do not expect location hyperparameters alone to satisfy
it accidentally. If it is not an absolute safety requirement, preregister a
season-level false-alarm rate and maximum-early-weeks constraint rather than
the current all-or-nothing sample rule.

The 40% implausibility rule has the same issue. A true safety ceiling should be
enforced structurally at prediction time and audited, not used only as a
sample-dependent grid filter. A ceiling relative to a season's running maximum
would be time-varying and can be badly restrictive early; it is not an
acceptable substitute for a fixed domain-informed ceiling.

### 1.5 The reproduction check is necessary but far too weak

Four aggregate numbers can all match under a wrong season join, a horizon
off-by-one, compensating row drops, or duplicated rows. Stage 0 should require
the following before any sweep:

1. Bind the check to hashes of the frozen prediction artifact, surveillance
   snapshot, fold/season declaration, M0 artifact, and code provenance.
2. Assert the complete expected key set before filtering: season, origin,
   target week, and horizon. Verify `target_weekF = origin_weekF + h`, unique
   keys, the first and last origin per season, and exact row counts at each
   gate (requested, emitted, truth-available, forecast-available).
3. Compare the new harness row-for-row with the frozen ledger on keys,
   availability, unavailable reason, point forecast, continuous peak estimate,
   peak bounds, state, and passage flag. Aggregates are secondary.
4. Reproduce per-season × horizon MAE and denominators, not only 9.35 pp;
   reproduce the identities of all 49 rows above 40%, not only their count.
   Include the known maximum forecast and its row key.
5. Reproduce the full origin-by-origin `peak_passed` sequence and peak-bound
   trajectory, not only first-fire week. This catches un-passing and coordinate
   errors such as the 2013-14 oscillation.
6. Verify raw and smoothed peak targets independently, including tie handling,
   smoothing settings, and the plateau rule. Assert the MMWR/`weekF` conversion,
   M1 `newWeek` conversion, `anchorWeek`, and fractional-versus-rounded timing
   mode.
7. Materialize a row with a status for every attempted origin. Assert that
   optimizer failures, non-finite alignments, template fallbacks, and missing
   targets are counted by reason and never removed by `na.rm = TRUE` before
   denominators are fixed.
8. Confirm LOSO isolation: the held-out season must not enter its reference
   templates, learned alignment hyperparameters, ignition labels, or any
   data-derived normalization.

Without these checks, matching §1.5 is evidence that the final summaries agree,
not that the harness is correct.

### 1.6 Selection optimism on 11 seasons is not addressed

The effective sample size for selection is 11 seasons, not 635 forecast rows.
A large grid will select favorable season-specific noise. The proposed peak
score makes this worse: hard thresholds produce many ties and sudden rank
changes, while hard “any-row” constraints make feasibility hinge on single
origins. Repeatedly changing the objective, expanding boundaries, sizing later
stages from earlier results, and refining around the observed winner compounds
the adaptivity. Stability across three scalarizations on the same 11 seasons
does not measure selection optimism.

At minimum, the plan must add all of the following:

- Treat season as the resampling unit. Report paired candidate-minus-incumbent
  results by season, not row-level uncertainty.
- Run an outer season-level selection assessment: for each held-out season,
  select the spec using only the other seasons and score the selected spec on
  the held-out one. Ordinary LOSO model fitting is not enough because the
  hyperparameter winner currently sees all LOSO fold scores.
- Report leave-one-season-out winner stability, selection frequencies, and
  worst-season degradation. Use a one-standard-error or simplest-on-a-plateau
  rule rather than the raw maximum when performance is indistinguishable.
- Predeclare the grid, objective anchors, tie-breaker, missingness rule, and
  boundary-expansion rule. Any post-result change begins a new development
  cycle.
- Preserve the untouched prospective holdout for one final locked comparison;
  do not use it to repair this objective.

The earlier result that 0/205 M2 specs dominated a trivial baseline in every
season argues for modeling heterogeneity and limiting worst-season harm, not
for searching harder until one spec happens to dominate all 11. Add a
predeclared degradation cap and show the full distribution of paired seasonal
effects. No unbiased performance claim should come from the same 11-season
sweep that selected the winner.

## 2. API and artifact audit

The principle—retain enough expensive output to re-score without refitting—is
sound. The proposed decomposition does not yet implement that principle. It
confuses three different objects:

1. an origin-level prediction/event ledger;
2. derived metric tables at season/horizon/spec levels; and
3. a ranking produced by one objective specification.

“One row per spec × season × horizon” cannot also be “per-row predictions.” It
has no origin key, cannot reconstruct a lock trajectory or a first-fire event,
and cannot expose a dropped origin. `m1_objective()` returning one named vector
also conflicts with retaining season- and horizon-level metrics. Use an
artifact bundle with normalized tables rather than one overloaded tidy table.

The irreducible origin-level ledger needs, at minimum:

- stable keys: spec identity, outer fold/held-out season, season, origin
  `weekF`, target `weekF`, horizon, and expected-row indicator;
- forecast outputs: probability and logit point forecasts, interval bounds,
  logit spread, and the exact value supplied as M2's offset;
- peak outputs at every origin: continuous point estimate, lower/upper bound,
  raw alignment-scale values, passage threshold, `peak_passed`, state, and
  timing/rounding mode;
- truth: target counts `y` and `N`, target positivity, raw peak, smoothed peak,
  plateau interval, and truth-definition version;
- availability and failures: attempted/emitted/scorable flags, reason code,
  optimizer convergence code, objective value, fallback use, number/identity
  of valid templates, and non-finite diagnostics;
- alignment diagnostics needed by declared constraints: `tau`, `delta`, `a`,
  `b`, `delta_on`, ignition estimate/lock, `anchorWeek`, and coordinate system.

If later metrics may use template voting or upper-bound stability—as Section 3
already proposes—per-row ensemble predictions are still insufficient. Store
per-template peak estimates and weights, or explicitly declare those future
metrics to require recomputation. Likewise, a new metric involving a different
forecast horizon or a forecast not emitted in the original run cannot be
recovered from the ledger. “Adding a metric later requires no refit” is true
only for functions of fields and supports already stored.

A parameter-only spec hash does **not** detect changed code. Safe reuse needs a
run identity containing at least:

- canonical parameter serialization and spec ID;
- source/package commit or source-tree hash and artifact schema version;
- data snapshot hash and season/fold declarations;
- upstream M0 identity, reference-template identity, learned-hyperparameter
  identity, manual-label identity, and preprocessing/calendar version;
- all fixed behavioral arguments, including CI level, passage buffer,
  persistence rule, timing mode, forecast horizons, and RNG scheme;
- dependency/runtime versions when they can affect numerical fits.

Cache lookup must use the full fit identity. Objective version belongs to the
derived metric/ranking identity, not the fit identity. A spec can be safely
re-scored under a new objective but cannot be safely reused after a behavioral
code or upstream-artifact change merely because its grid parameters match.
The current codebase's checkpoint identity already hashes data and fixed
arguments; the new design should strengthen that pattern, not replace it with
a weaker spec hash.

`seed_from = prior_sweep` also needs separation into two operations. Appending
new, explicitly declared grid rows and reusing exact compatible fits is sound.
Automatically narrowing around the prior winner is not sound after changing
the objective: the newly rescored winner may differ, and a local refinement
can miss remote Pareto-optimal regions. Grid planning must consume the newly
ranked full sweep, preserve the incumbent and diverse finalists, record
boundary decisions, and never imply that re-scoring old rows evaluates new
rows for free.

`m1_score()` should take an immutable `objective_spec` containing fixed anchors,
aggregation levels, constraints, missingness penalties, tie-breakers, and
metric versions. Its output should retain every candidate with explicit
eligibility reasons and per-season components. It should never silently drop
failed specs or choose among tied zero peak scores by input order.

## Required changes before authorizing the sweep

1. Replace lead-at-hard-lock as the primary peak score with a continuous,
   season-balanced, strictly pre-peak score; retain lock curves as diagnostics.
2. Freeze the peak/plateau truth definition, one-week scale interpretation,
   expected origin grid, and missingness rule.
3. Replace sweep-relative z/range scaling with one fixed anchored 50/50 utility.
4. Separate location scoring from passage-rule calibration and specify the
   exact gate configuration and false-alarm requirement.
5. Strengthen Stage 0 to row-level keyed reproduction with provenance and
   failure-denominator checks.
6. Define the origin ledger, derived metrics, ranking artifact, and full cache
   identity separately.
7. Add season-level nested selection assessment and winner-stability reporting.

Until these are fixed, a multi-day sweep would produce a precisely computed
answer to an unstable question.

## Sections 3–5 (brief)

The staged causal sequence is reasonable as hypothesis work, but each
data-dependent stage and grid refinement consumes the same 11 seasons and thus
increases adaptivity; it must sit inside the selection protocol above. Stage 3
should not use the flawed §1.1 score to choose a passage gate, and Stage 5's
post-peak routing cannot be judged without re-evaluating/retraining M2. The two
open Stage 0 inputs (`tol_lock` and implausibility ceiling) are genuine blockers,
not values that can remain “interim” when the sweep starts.
