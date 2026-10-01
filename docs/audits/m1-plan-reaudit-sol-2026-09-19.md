# Confirm-only re-audit of the M1 retune plan, rev 2

Date: 2026-09-19  
Scope: the seven previously required changes and new material in §§1.1, 1.2,
1.6.1, and 1.7 only  
Verdict: **not yet fit to hand to an implementer.**

## 1. Status of the seven required changes

1. **PARTIALLY ADDRESSED.** Rev 2 replaces hard lock with a continuous,
   season-balanced, strictly pre-peak score and retains lock curves only as
   diagnostics. However, raw linear lead weights create a new near-degeneracy
   risk by giving most weight to the least identifiable early origins.

2. **PARTIALLY ADDRESSED.** The truth hierarchy, decimal scale, expected-key
   concept, 5% disqualification threshold, and zero credit for missing peak
   estimates are specified. The parabolic fallback lacks important guards,
   `kappa` remains open, and forecast rows missing within the allowed 5% still
   have no prescribed contribution to forecast MAE.

3. **PARTIALLY ADDRESSED.** The grid-dependent scaling is correctly replaced
   by a fixed-anchor formula, but `Delta_peak` and `Delta_mae` are still open;
   until they are frozen, there is no executable preregistered 50/50 rule.

4. **PARTIALLY ADDRESSED.** Location and passage are now explicitly separate,
   and the passage configuration is declared part of the spec. The buffer
   inconsistency, false-alarm ceiling, maximum early firing, persistence, and
   decline rule remain unresolved, so the exact gate is still only mentioned,
   not specified.

5. **ADDRESSED.** Gate A now requires provenance-bound, keyed row-level
   reproduction, exact denominators, failure visibility, full passage
   trajectories, coordinate checks, and LOSO isolation.

6. **ADDRESSED.** Rev 2 separates the origin ledger, derived metrics, and
   ranking, and gives cache reuse a full fit identity distinct from the
   objective identity. Because Stage 3 proposes template voting, the stated
   per-template estimates and weights must be treated as required fields, not
   an optional future extension.

7. **PARTIALLY ADDRESSED.** Season-level nested selection, paired effects,
   winner stability, and worst-season degradation are required. The plan must
   say explicitly that each outer split reruns the entire data-adaptive staged
   procedure—including stage sizing, grid refinement, and boundary decisions—
   rather than merely selecting from a candidate set designed using all 11
   seasons.

## 2. Audit of new material

### §1.1 Peak truth

Three-point parabolic interpolation is a sound local sub-week estimator only
for finite, equally spaced consecutive weeks around a single isolated maximum.
The guards do not cover missing/nonconsecutive neighbours, a noisy spike, or a
locally concave shoulder on a bimodal curve. It also cannot decide which mode
is epidemiologically intended; an ambiguous bimodal season without a label
needs human adjudication, not automatic interpolation.

The tie rule is internally inconsistent. Choosing the earliest tied argmax and
then interpolating can return the midpoint of a two-week plateau (`delta =
0.5`), not the earliest week. A tie must either force `P_s = w_0` or be given an
explicit midpoint rule. For a true central argmax with both neighbours no
higher, `|delta| <= 0.5` already follows algebraically; if clipping would be
needed, falling back to `w_0` is safer than manufacturing a boundary vertex.

Where label and fallback disagree sharply, Rev 2 silently uses the label. The
label should remain primary—especially for multi-wave seasons—but the plan
must compute and retain the fallback for every labelled season and require a
pre-sweep, provenance-recorded review of large discrepancies for coordinate or
entry error. It must not automatically average or switch truths after seeing
candidate performance.

### §1.2 Peak score

Yes, the proposed weighting can reproduce degeneracy in a different form. If
eligible leads are 1 through `L`, the farthest half receives about 75% of the
denominator. With `L = 12`, if only the final four origins contain usable peak
information, even perfect estimates there contribute only
`(1+2+3+4)/(1+...+12) = 0.128`; errors of several weeks at earlier origins have
Gaussian kernels effectively at zero when `kappa = 1`. This compresses scores,
weakens their anchored contribution, and can make differences depend on a few
lucky early estimates.

Fix it by declaring an operationally actionable lookback `H` before examining
candidates, scoring only post-ignition origins with `0 < P_s-w <= H`, and using
a bounded lead bonus, for example

```text
q(l) = 1 + rho*l/H,  0 < l <= H
S_s  = sum q(l) k_s(w) / sum q(l)
```

with fixed `rho` (for example 1, limiting the earliest-to-latest weight ratio
to 2). Expected missing origins remain in the denominator with `k = 0`.
Choose `H` and `rho` from the operational use case, not pilot rankings; report
lead-stratified accuracy separately.

### §1.7 Gate B

Gate B would catch a literally constant all-zero pilot, but it is not
sufficient. “Non-trivial” and “near-constant” have no thresholds; one lucky
corner can create spread while most specs and seasons remain at the floor; a
small pilot can miss full-grid saturation; and aggregate spread can be driven
by one season or one origin.

The requirement that 50/50 weighting change the ranking relative to either
component is itself wrong: when peak and forecast components agree, a sound
combined objective should preserve their ranking. Replace it with prespecified
quantitative checks relative to `Delta_peak`, per-season floor/ceiling and
concentration checks, an effective-weight-by-lead report, and sentinel tests
whose expected ordering is known (early-accurate, late-only, wrong, and missing
trajectories). Demonstrate two-component influence only on pilot pairs that
actually trade peak against forecast performance.

### §1.6.1 Structural clamp and monitored count

Separating a 50% deployment safety rail from a soft 40% quality signal is
defensible; the two thresholds serve different purposes. It is incomplete
unless the ledger stores raw and clamped predictions and clamp activations,
the 40% rate is computed against the fixed expected denominator, and the plan
states whether the exact M2 offset is raw or clamped in every fit/evaluation/
runtime path.

Do not score only the clamped forecast: clipping a pathological 98% prediction
to 50% makes its MAE look better and hides severity. Score the raw prediction
or apply an explicit clamp-activation penalty, while evaluating the clamped
value separately as the operational output.

## 3. New defects introduced in rev 2

Yes:

- the unbounded linear lead weighting can make the replacement peak score
  dominated by hopeless early origins;
- earliest-argmax tie handling conflicts with subsequent interpolation;
- Gate B's mandatory rank-change test is logically invalid; and
- post-clamp scoring, if implemented from the present wording, would reward
  extreme forecasts by truncating their errors.

## Blocking items

1. Replace the raw lead weighting with a fixed actionable window and bounded
   lead bonus, then make Gate B quantitative and sentinel-based.
2. Complete the fallback rules for ties, consecutive finite neighbours, and
   ambiguous bimodal/shoulder cases; add pre-sweep review of large
   label/fallback discrepancies.
3. Freeze `kappa`, both utility anchors, the complete passage rule and its two
   limits, and the scoring penalty for forecast rows missing within the 5%
   allowance.
4. Specify raw-versus-clamped scoring, storage, and M2-offset semantics.
5. State that the outer season assessment repeats the full adaptive staged
   selection process inside each training split.
