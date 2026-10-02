# M2-v2 architecture proposal — 2026-09-23

Design-only. No code changed. Upstream input is the integrated M1-v2 handoff
(`m1-v2-to-m2-v1`, see [governed pipeline integration](m1-v2-governed-pipeline-integration-2026-09-23.md)
and [review disposition](m1-v2-integration-review-disposition-2026-09-23.md)).
Constraints from the [independent architecture audit](m1-m2-independent-architecture-audit-2026-09-22.md)
and the [amplitude/subtype hypothesis note](m2-amplitude-subtype-hypothesis-note-2026-09-22.md)
are treated as binding unless explicitly revised here.

## 0. Data-contract finding (blocks everything below)

The canonical surveillance schema (`season, weekF, y, N, p, neg`,
`PAGe/R/data_contract.R`) carries **one** positivity series. The realtime
adapter (`PAGe/R/realtime_sources.R`) hardcodes `pathogen = "fluA"` and reads
`pos_flua`/`test_flu`; the daily extract is a named list keyed by pathogen, so
a `"fluB"` sibling series almost certainly exists at the source but is not
wired through. Today's M2 forecasts influenza-A positivity only, matching the
hypothesis note's framing. **A/B separation is not a modeling choice we can
make on top of the current pipeline as-is — it requires a schema and adapter
extension first** (Phase 0 below). Whether a type-specific test denominator
(`N_A`, `N_B`) or only a shared `N` with a typed-positive split exists needs
verification against the raw source before Phase 1 design is frozen; this
changes the likelihood (independent binomials vs. a multinomial/compositional
split of one denominator).

## 1. A-vs-B curve family question

**Recommendation: hierarchical partial pooling of a shared canonical shape,
not separate models and not one pooled model.**

Rationale, extending the hypothesis note's finding from subtype to type:

- The note found an oracle same-subtype peak-aligned library *worsened* M1
  peak-time MAE relative to the pooled library, on 11 seasons where several
  are subtype-mixed or B-circulating. The same small-sample logic applies
  more strongly to A-vs-B: a full separate-model split roughly halves (or
  worse) the effective per-type season count.
- The note also found a real amplitude-scale relationship survives
  peak-height normalization only partially — i.e., there is signal, but it is
  a scale/amplitude effect, not a shape effect. This matches M1-v2's own
  finding that the peak-aligned shape becomes homogeneous within ~6 weeks of
  peak once amplitude is treated as a separately-regularized nuisance
  ([exploration findings](m1-v2-exploration-findings-2026-09-22.md)).

So: **one shared low-rank peak-relative shape family (reuse the M1-v2
library's shape, do not refit a second shape from scratch), with type
entering only as a partial-pooled amplitude/level effect**, shrunk toward the
pooled estimate by an amount selected under nested LOSO rather than fixed a
priori. Full separation (a distinct shape per type) and full pooling (type
ignored) are both kept as ablation bookends (A1, A0 below), not the default.

**A-subtype (H1N1/H3N2) is a different axis from A-vs-B and must not be
conflated with it.** Per the hypothesis note, subtype dominance is
hypothesis-generating only (11 seasons, mixed/co-circulating years) and
already failed as a hard split for M1. Recommendation: subtype enters, if at
all, as a single heavily-penalized soft covariate on the flu-A amplitude/
variance term — never as a branch, mixture-component selector, or separate
model — and only as an ablation arm (A4), not a default-on feature.

## 2. Causal availability — what "subtype/dominance" features are legal

Two different things get called "subtype information" and only one is legal
as a runtime feature:

| Signal | Available at forecast origin? | Use |
|---|---|---|
| Contemporaneous type share (fraction of typed specimens that are A vs B, this week) | Yes, if lab typing turnaround is fast enough — **must be verified against real typing latency before use**, not assumed | Legal M2 feature (A3) |
| Contemporaneous A-subtype share among typed-A specimens, this week | Yes, same latency caveat | Legal M2 feature (A4), A-stream only |
| Eventual/final-season subtype or type dominance label | No — only known in retrospect | **Never** a runtime feature; historical-only for priors |

Any "current-season dominant subtype" feature is retrospective leakage unless
it is reconstructed causally (as-of-origin, from typed counts accumulated so
far), exactly as M0/M1-v2 already distinguish expert ignition `I*` from
causal detection `A`. Apply the same discipline here.

## 3. Model family

**Primary candidate (A2): type-indexed extension of the existing frozen M2
GAM**, not a new model class. Existing M2 is a binomial-GAM offset model on
the saved M1 forecast (`manuscript/M2_MODEL_PROPOSAL.md`):

```
Y_{s,type,t+h} | N_{s,type,t+h}, p ~ Binomial(N_{s,type,t+h}, p)
logit(p) = logit(M1v2_offset_{s,type,t,h})
           + a_h
           + f_h(z_{s,type,t})                      # shared-by-type smooth
           + u_{type} + v_{s,type}                    # partial-pooled type effect
```

- `a_h`, `f_h` stay shared across A/B (small n forbids per-type smooths).
- `u_type` is a fixed or lightly-penalized type offset (A vs B systematic
  amplitude difference).
- `v_{s,type}` is a partial-pooled (ridge/random-effect) season×type term,
  shrinkage strength selected in nested LOSO — this is the mechanism that
  lets a data-rich type borrow less from the pooled estimate than a
  data-sparse one, instead of a fixed pooling decision.
- Binomial likelihood only if a type-specific denominator `N_type` exists
  (Phase 0 finding); otherwise a compositional/multinomial likelihood over
  (A-positive, B-positive, negative) given shared `N` is the correct
  alternative, not two independent binomials against a shared `N`.

**Alternative (deferred, not primary): full hierarchical Bayesian
state-space** with shared latent curve and type random effects (e.g. via a
package like brms/INLA rather than mgcv). More natural uncertainty
propagation and partial pooling, but adds a modeling-language dependency and
is harder to audit under the existing governed `tune_*/validate_*/fit_*/
freeze_*` contract. Recommend only if A2's random-effect shrinkage proves
insufficient in ablation — not a Phase-1 default. This keeps dependencies
lean, consistent with prior project guidance on this repo.

## 4. Training targets

Two numeric +1/+2-week-ahead positivity targets (flu A, flu B), each at both
horizons — four target series, sharing model structure per §3, not four
independent models. Do not derive B by subtracting a combined-flu forecast
minus an A forecast; fit each type's own counts directly (or the joint
compositional likelihood if a shared denominator forces it). A
difference-of-forecasts approach propagates both models' error into a
target nobody optimized for.

## 5. Features

**From M1 (per type, once Phase 0/1 make M1 type-aware — see §9):**
`calibrated_peak_mean`, `weeks_elapsed_since_activation`,
`weeks_to_calibrated_peak`, `prob_peak_passed`, `prob_peak_within_{1,2,3}w`,
`locked_peak_week`/`locked_at_origin`, `calibrated_peak_q05/q95` and
`interval_width_90` (uncertainty — see §6, not just the point mean).

**Current-season, per type:** EMA logit level `z_type` and adjacent growth
`d_type` (reuse the existing M2 definitions in `M2_MODEL_PROPOSAL.md`,
computed only over observed adjacent weeks, no interpolation), test volume
`N_type`, phase `u = t - T_decl,type` using the type's own causal M0/M1
declaration.

**Cross-type (A3):** contemporaneous type share, subject to the latency
verification in §2.

**A-only (A4):** contemporaneous A-subtype share, single penalized term,
flu-A stream only.

All features must be reconstructible from the row's own excluded-season
upstream artifacts under the nested scheme in §7 — no feature may be computed
from an upstream model that saw the row's season.

## 6. Uncertainty propagation from M1

Current M2 (`M2_MODEL_PROPOSAL.md`) uses only the saved M1 **point** forecast
as a fixed offset and ignores M1's uncertainty entirely. M1-v2 now exposes a
real posterior (raw/calibrated q05/q95, `interval_width_90`, a candidate
probability grid). M2-v2 should not discard that. Two escalating options,
tested as an orthogonal ablation axis (A5) rather than baked into the primary
candidate:

1. **Cheap:** add `interval_width_90` (and/or `calibrated_mean_is_future`) as
   an M2 feature/dispersion modifier, so M2 can down-weight or widen its own
   interval when M1 is uncertain, without changing the point-forecast offset
   mechanism.
2. **Full:** integrate M2's training loss over M1's posterior (Monte Carlo or
   moment-matched draws from the calibrated grid) instead of conditioning on
   the point mean, so M2's fitted coefficients reflect M1 uncertainty rather
   than treating it as known-true.

Report M2's final predictive interval as M1 phase-uncertainty-implied
variance combined with M2's own binomial/residual dispersion, not residual
dispersion alone — otherwise intervals will be systematically too narrow
early in a season when M1's phase uncertainty is largest.

## 7. Nested LOSO evaluation

Adopt the audit's exclusion table exactly (§1 of the audit), extended with a
`type` dimension on the M2 training-row axis:

| Purpose | Excluded from upstream fitting |
|---|---|
| Outer test season `o` | `o` (both types) |
| M2 training row for season `r`, type `k`, within outer fold `o` | `o, r` |
| Inner validation season `v` | `o, v` |
| M2 training row for `r,k` while validating on `v` | `o, v, r` |

A season's exclusion is per-season, not per-type — excluding season `o`
excludes both its A and B rows from upstream fitting, since the shared shape
and `a_h`/`f_h` terms are fit across types. Cache and freeze artifacts by
complete exclusion set + type + data/label hash, per the audit's acceptance
check.

Report scores **separately** for flu A, flu B, and each horizon — never a
single blended metric, since it can hide one type's failure behind the
other's larger sample. Add the audit's P2 requirement: an expanding-window,
prior-seasons-only chronological evaluation alongside exchangeable-season
LOSO, since real deployment is forecasting forward, not season-exchangeable
replay.

## 8. Failure states

Extend M1-v2's per-origin states (`pre_ignition, active, future_only,
passage_only, passage_confirmed, unavailable`) with a `type` dimension — A
active while B is pre-ignition (or vice versa, or absent that season) is an
**expected joint state**, not a failure. Genuine failure states to define
explicitly:

- `type_denominator_unavailable` — no type-specific test count this week.
- `type_composition_stale` — typing lag exceeds the causal-availability bound
  from §2; fall back to A2 without A3/A4 features rather than using stale data.
- `insufficient_type_training_rows` — a season/type has too few historical
  rows to support its `v_{s,type}` term; fall back to the pooled (`u_type`
  only, `v` dropped) estimate rather than forcing a fit, with the fallback
  recorded in the ledger.
- `upstream_type_unavailable` — M1 has no type-aware output for this type
  (e.g. before Phase 1 extension for B); M2 must not silently substitute the
  other type's forecast.

## 9. Runtime contract

Extend the `m1-v2-to-m2-v1` handoff with a `type` field and require the M2-v2
handoff (version it `m2-v2-v1`) to carry: origin/target week identity,
horizon, `type`, feature-schema version, upstream (M0/M1/M2) bundle identity
per type, and an explicit availability/reason code per §8. Do not require a
duplicated M0/M1 stage per type by default — Phase 1 (below) proposes
extending the *existing* shared M1-v2 timing stage with a type covariate on
its amplitude nuisance rather than standing up a parallel M1-B pipeline,
consistent with keeping the shape shared (§1) and the audit's dependency-
contract requirement (§8 of the audit) that a model swap need an explicit
state reset.

## 10. Ablation plan (predeclared, staged)

| Arm | Description |
|---|---|
| A0 | Pooled — type ignored (reference floor, ≈ current M2 behavior for the pooled series) |
| A1 | Fully separate per-type models (upper-bound/overfit check) |
| A2 | **Primary** — shared shape, partial-pooled type amplitude (`u_type + v_{s,type}`) |
| A3 | A2 + contemporaneous type-share feature |
| A4 | A3 + A-subtype soft covariate, flu-A stream only |
| A5 | A2/A3 + M1 uncertainty propagation (§6), tested independently of A3/A4 |

Selection rule mirrors the existing M2 proposal: nested-LOSO NLL per
horizon per type, equal season weighting, simplest-model tie-break, rule
frozen before any outer-holdout look, per the audit's P1 finding on
selection/stacking exclusions. Disclose any pre-freeze exploratory exposure.

## 11. History vs. current season

- **From historical peak-aligned curves:** the shared canonical shape (reuse
  M1-v2's library, do not refit) and a historical type-level amplitude prior
  (mean/variance of peak height by type), mirroring M1-v2's own successful
  amplitude-nuisance-prior treatment. Any historical subtype-amplitude
  relationship enters only as a weak, shrunk prior component, never a hard
  rule, per the hypothesis note.
- **From current-season data:** phase (`u`, declaration/passage state),
  level (`z`), growth (`d`), contemporaneous type/subtype share — everything
  causal-only, nothing retrospective.

## 12. Identifiability and small-sample robustness

n ≈ 11 seasons, and flu B (and mixed-circulation years) will have fewer
usable seasons than that. Concretely:

- Never fit a free per-type shape at this n (§1).
- Shrinkage strength for `v_{s,type}` is selected under nested LOSO, not
  fixed a priori beyond a weak default — mirrors M1-v2's own finding that a
  season-excluded historical prior with validated shrinkage beat both free
  and absent amplitude terms.
- Subtype covariate restricted to one low-df penalized term, ablation-only.
- All model-family choices frozen before outer holdout is viewed (audit P1).
- Any season/type cell below a minimum-row threshold reports
  `insufficient_type_training_rows` (§8) rather than a forced fit; publish
  per-type/per-season row counts alongside every result.

## 13. Recommendation and phased plan

**Recommendation:** A2 (shared shape, partial-pooled type amplitude) as the
default M2-v2 family, built as a type-indexed extension of the existing M2
GAM rather than a new model class; A3–A5 as disclosed, predeclared ablations;
A1's full-separation and the full hierarchical Bayesian alternative (§3)
stay out of the default path given current sample size.

1. **Phase 0 — data contract.** Verify raw type-specific denominators
   (`N_A`/`N_B` vs. shared `N`) and typing latency against the actual source
   (daily RData `fluB` key / historical CSV columns); extend
   `data_contract.R`/`realtime_sources.R` with a `type` field and matching
   acceptance tests. This gates everything else and may change §3's
   likelihood choice.
2. **Phase 1 — type-aware M1.** Extend the existing M1-v2 timing stage with
   a type covariate on its amplitude nuisance (not a duplicated M1-B stage);
   verify flu-B seasons have enough ignition/passage signal for the existing
   M0/M1-C machinery before assuming parity with flu-A timing.
3. **Phase 2 — M2-v2 A2.** Implement the type-indexed GAM extension inside
   the existing `tune_m2/validate_m2_tuning/fit_m2/freeze_m2` contract, with
   the §7 nested exclusion table and per-type/per-horizon reporting.
4. **Phase 3 — ablation ladder.** Run A0–A5 under the frozen predeclared
   rule; add the chronological expanding-window check; report per-type
   results and row counts.
5. **Phase 4 — freeze and integrate.** Extend the `m2-v2-v1` runtime handoff
   and failure-state handling (§8–9); update `run_m2()`/`run_prospective_pipeline()`
   the same way M1-v2 was integrated as an additive, non-breaking stage.

## 14. Alternatives and risks

- **Full hierarchical Bayesian alternative (§3):** better uncertainty
  propagation in principle, worse auditability and a new dependency at this
  project's current maturity; revisit only if A2's shrinkage is
  demonstrably insufficient.
- **Risk — flu B sparsity:** some historical seasons had suppressed/near-zero
  B circulation (or pandemic-era disruption); `v_{s,type}` for B may be
  unstable at any shrinkage. Mitigate via the `insufficient_type_training_rows`
  fallback (§8), not by forcing a fit.
- **Risk — typing latency:** contemporaneous type/subtype share (A3/A4) is
  only legal if typing turnaround is fast enough to be origin-available;
  this is unverified here and must be checked against the real source before
  A3/A4 are implemented, or they silently become leaky features.
- **Risk — subtype over-fitting:** the hypothesis note is explicit that its
  subtype-amplitude finding is not validated; keep A4 as a disclosed
  ablation arm only, never a default-on feature.
- **Risk — scope creep into a parallel M1-B stage:** duplicating M0/M1 per
  type multiplies the audit's P1 exclusion/selection burden. The amplitude-
  covariate extension in Phase 1 is deliberately the minimal-invasive option;
  a full parallel stage should require an explicit decision, not a default.

## Next human decision

Confirm Phase 0's likelihood question (independent per-type binomial vs.
shared-denominator compositional) once the raw source columns are checked,
and confirm whether flu-B-specific M0/M1 timing work is in scope for this
cycle or deferred behind the pooled-shape/type-amplitude approach in Phase 1.
