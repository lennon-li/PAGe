# M2 adoption: fix plan, evidence plan, and "M2 does not clearly help" definition (DRAFT)

> **Status update (2026-09-18, later): the underlying 11-fold campaign this entire document analyzes is
> now known to be contaminated, not just in its own 2025-26 holdout as previously flagged.**
> ming-wonderwoman/Lennon found `data/flu_testing_data.csv` (sha `fa8add1b...`) truncates 2025-26 at
> weekF 28 of 53, and 2025-26 was an active **training** member (ignition present, decline missing) in
> all 10 non-2025-26 outer folds, not merely its own truncated holdout. A related code defect
> (`plan_training()` receiving `permanent_exclusions` instead of the validated season `selection`) is
> fixed and pushed (`77aed59`, `020f071`); the launchers now hard-require `PAGE_FLU_HIST_FILE` rather
> than silently defaulting. Consequence: every gain/p-value/spec-selection number in the Opus diagnostic
> below, and therefore every recommendation in this document, is **provisional pending a clean 11-fold
> re-run on complete data**. Do not cite this document's specific numbers as a settled finding. The
> methodological content (the fix recommendations in §1, the reporting-rule definition in §2, the
> evidence-plan structure in §3, including the circularity correction) is expected to still apply in
> shape to the clean re-run, but must be re-verified against it, not assumed to carry over. D-35 is
> void for the same reason (ming-wonderwoman's confirmatory run was also pinned to the truncated file)
> — do not close it on the current result.
>
> **Update (2026-09-18, same day, later still): the headline qualitative finding survives clean data.**
> Both production kits (the Asgard v2.0 build and the venkata v2.1 `w_min=8` build) were independently
> trained and gated on the full, complete ORVT feed (sha `516ce54f...`, 53 whole weeks of 2025-26), not
> the truncated campaign file — ming-wonderwoman verified the input hashes directly. Both independently
> reached `keep_m1`; the v2.1 clean run additionally failed the season-degradation check, which the
> contaminated 2022-23 fold's gate had not listed. This licenses one thing only: **"M2 as currently
> specified does not clear the adoption gate" is not an artifact of the 2025-26 truncation** — it holds
> on data that shares no contamination with the campaign. It does **not** license any per-fold gain,
> effect size, or count from the campaign table above, which remain exactly as provisional as stated
> above; the production tune is one pooled 11-season inner-LOSO decision, not eleven independent outer
> folds, and cannot substitute for the diagnostic's per-fold evidence. When the clean 11-fold re-run
> lands, the diagnostic must be re-run against it before any of those numbers are cited. Note also that
> ming-wonderwoman's three M2 correction fixes (production, unrelated to this plan's §1 fixes) were
> *motivated by* evidence from the possibly-contaminated campaign, even though their justification does
> not depend on that evidence (each is independently defensible on its own logic) — treat them as
> motivated-by, not confirmed-by, the campaign, and covered by their own regression tests regardless.
>
> **Correction (2026-09-18, later still): 2022-23 has its own, separate provenance defect, root-caused.**
> `2025/run_2025_cycle.R` loads PAGe via `devtools::load_all("PAGe")` from the repository working tree,
> not the installed library — so a run's actual code is whatever commit `PAGe-r6-run` is checked out to
> at execution time, independent of `R CMD INSTALL` state. `PAGe-r6-run` was at `9635cce` (ming-oracle's
> pull) when 2022-23's 19:01 UTC rerun executed, so that fold ran ming-wonderwoman's fix 3 in full
> (Jeffreys logit floor, symmetric clamp, degradation-aware selection) while the other ten folds ran
> `1e24ece`. This also retracts the earlier "independent reproduction" claim in channel #63: the killed
> `9635cce` run and its "confirmatory" `load_all`-based rerun were the same code executed twice, not two
> independent numerics paths agreeing — it shows only that identical code gives identical answers.
> ming-wonderwoman's furrr-hunk fix is still judged numerically inert on code inspection (it repackages
> task payloads without touching arithmetic, covered by `test-m1-walkforward-multi-globals.R`), but the
> empirical cross-validation claimed for it does not exist and must not be cited. Net effect: 2022-23 is
> doubly superseded (truncated 2025-26 in its own training data, and wrong-commit M2 numerics relative to
> the other ten folds) — resolved by the clean re-run either way, once it happens. A related governance
> gap worth carrying into that re-run: because `load_all()` makes a run's real code identity the working
> tree, not the installed package, no artifact from this campaign records which commit or dirty-tree
> state actually executed — provenance manifests need to capture that going forward.

- Status: **DRAFT, SUPERSEDED INPUT**. Not frozen. Written by ming-oracle, 2026-09-18, from the Opus
  diagnostic of the 11-fold outer campaign (all 11 folds rejected M2; see channel #64 and the deviations
  register) — that campaign's training data is now known contaminated (see banner above).
- Purpose: (1) name the production-code fixes needed before any re-run; (2) define, precisely and in
  advance, what "M2 does not clearly help" means for this manuscript, so the definition is not
  chosen after seeing results; (3) lay out how to give M2 a fair, well-resolved descriptive comparison
  using evidence the campaign already collected.
- Scope split: items marked **[PRODUCTION]** are ming-wonderwoman/Liz's to implement on the current
  in-progress code (not this document's author's to touch); items marked **[MANUSCRIPT]** are this
  session's to draft/decide; items marked **[JOINT]** need both sides.

## 0. What the diagnostic actually found (one paragraph, for context)

M2 was nominally better than M1 in 10 of 11 folds (never worse), but the per-fold gains were small
relative to the between-season spread — the effect is consistent in direction but small relative to
between-season noise, and the design as run cannot resolve it at n=9-11 seasons. On top of that: (a) the GAM's fitting weights never included the
phase weight used for scoring/selection, so M2 was optimized for a different objective than it was
judged on; (b) `max_season_degradation = 0` is applied twice once ming-wonderwoman's fix 3 (`9d9cfcd`)
lands (once filtering the tuner's candidate set, again at the gate) — **correction, 2026-09-18: the
original diagnostic claimed this double-application had already collapsed 2022-23's candidate set to
the trivial null spec in the campaign itself. That specific claim is false, and the reason is now fully
traced (see the status banner's second correction below): `2025/run_2025_cycle.R` loads PAGe via
`devtools::load_all()` from the repository working tree, not the installed library, so 2022-23's 19:01
UTC rerun executed whatever commit `PAGe-r6-run` was checked out to at that moment (`9635cce`, which
does contain fix 3) regardless of what had been `R CMD INSTALL`ed. The other ten folds ran under `1e24ece`
via the same mechanism. 2022-23 is therefore not just a data-contamination outlier but a separate,
wrong-commit-numerics outlier from the other ten.** The design argument for un-doubling the rule (item
1.2 below) stands on its own regardless of this; the 2022-23 anecdote does not support it and must not
be cited as if it did; (c) the manuscript's advertised practical floors
(0.0012 / 0.002) were never actually binding anywhere — the gate's decision-threshold uncertainty term
(the `t_{0.95, n-1} * SD / sqrt(n)` term in the gate rule) dominated by 4-20x in every fold, so
reporting those floors as "the" criterion is misleading as currently framed.

## 1. [PRODUCTION] Fixes needed before any re-run

1.1. **Fit/score objective mismatch.** `m2_subset_correction.R:443`, `.fit_weight` must include the
     phase weight (`weight_page_v2`, already computed and attached at line ~1192) as well as the
     season-trial-count balance it already has. Today the GAM is fit on trial-count weights alone while
     spec selection and the gate score on 0/2/3/1 phase weights — a real train/score skew, not a stylistic
     nit.

     **Empirical backing (ming-wonderwoman, 2026-09-18, `30939d0`, `scripts/experiment_phase_fit_weight.R`,
     `results/experiments/phase-fit-weight/`):** out-of-sample leave-one-season-out comparison of the two
     `.fit_weight` arms (season-balance-only vs. + phase weight), byte-identical code apart from the one
     weight line, all 206 specs, 627 available rows, 11 seasons. Phase-weighted arm has lower mean
     out-of-sample weighted NLL (0.43406 vs. 0.44248; mean paired difference -0.00842) and wins in 1904 of
     2255 spec x season comparisons (84.4%), and in 10 of 11 seasons (only 2013-14 favours the unweighted
     arm, +0.0017). All-off sanity holds exactly (max |difference| = 0), confirming the patch touches only
     the weight and nothing else. This was run as a safety check, not as the basis for adopting the fix —
     the adoption argument for 1.1 stays decision-theoretic (fit the loss the spec is graded on), not "we
     tried it and it scored better."

     **Design point the safety check surfaced, to build into 1.4:** the phase-weighted arm's mean
     predictive standard error on the link scale is about 9% tighter (0.01575 vs. 0.01734) — the expected
     consequence of weighting some rows up to 3x, which inflates the GAM's apparent effective sample size
     for REML's uncertainty estimate. The accuracy gain is real and the tightening is modest, but `m2_lo`/
     `m2_hi` become somewhat optimistic after this fix. This is a genuine cost of 1.1, not a reason to
     reject it, but it must be checked, not assumed away — see 1.4.

1.2. **Double-applied zero-degradation rule.** `max_season_degradation = 0` is checked twice:
     `m2_subset_correction.R:1476-1477` (`robust <- ... worst_excess <= 0`, filtering the tuner's own
     candidate set down before the gate runs) and again in `m2_baseline_decision.R` at the gate itself.
     Remove it from the tuner's *selection* step (`robust`/`candidate_idx` narrowing) — report it as a
     diagnostic column on every candidate (keep `worst_season_excess_vs_all_off` reported per candidate;
     that column is what the filter was actually for, and the gate still needs the information even
     though it should not be pruning on it), but do not use it to prune candidates before the gate sees
     them. Keep the zero-degradation check at the gate only, where it belongs as the adoption criterion.
     (ming-wonderwoman, 2026-09-18: no objection to this direction, even though it partially reverses her
     own fix 3.) Fixing
     1.2 alone does not make the gate satisfiable — and, per §2.3 below, no choice of tolerance fixes
     this either. The problem is the rule's *form* (a worst-case statistic across 9-11 noisy seasons),
     not its threshold. See §2.3 for the replacement proposal (a sign-consistency test for form, with the
     operational tolerance a separate, later decision).

1.3. **Reduce the tuning grid size a priori — the correct, non-circular fix for selection optimism.**
     The diagnostic found the ~650-700-spec grid produces severe selection optimism (in most folds only
     0-7% of specs beat the trivial all-off spec on raw score, so the "winner" is close to a best-of-650
     draw from noise). The right fix for this is structural, decided *before* looking at any new results:
     shrink the M2 grid to a small, theoretically-justified set of specs (order 5-15, not ~650) chosen on
     substantive grounds — e.g. bounded basis dimensions per term, a small number of `intercept`/`k_z`/
     `k_u`/`k_d` combinations motivated by the pipeline's own design, not by which phases showed signal in
     this campaign. This directly lowers the variance of the max-over-specs statistic the gate's t-test is
     implicitly fighting. `[DECISION]` exact grid to Lennon/production; the constraint is that it must be
     fixed without reference to this campaign's phase-localized findings (see 3.2's circularity note).

1.4. **Equivalence tests required for all three fixes** (this repo's stated discipline): confirm the
     all-off spec is still bit-for-bit identical to M1 after 1.1 (weighting the fit shouldn't touch the
     identity contract, but verify it); **add an interval-coverage check for 1.1 specifically** (per the
     9%-tighter predictive-SE finding above) — do not let `m2_lo`/`m2_hi` coverage ride on the untested
     assumption that the phase weight doesn't distort it, check it directly; confirm 1.2 doesn't change
     any *already-adopted* kit's decision anywhere else in the codebase (there are none in this cycle, but
     check the prior-cycle acceptance path isn't shared code that would be silently affected); confirm
     1.3's smaller grid still contains the all-off spec as a candidate.

1.5. **One diagnostic fold only**, not a full campaign, to confirm the fixes behave as expected before
     touching the outer holdouts again: re-run one fold's inner tuning (2022-23 is a reasonable choice,
     but it carries no special evidential weight here now that the earlier "collapse to all-off" claim
     for it has been retracted — any fold works) and confirm a non-trivial spec now survives to the gate.
     Do not re-tune against any outer holdout at this stage.

## 2. [MANUSCRIPT] Defining "M2 does not clearly help" — decide this now, before re-running anything

This must be a pre-registered reporting rule, not a post-hoc description chosen to fit whatever the
re-run produces. Proposed three-way outcome, replacing the current binary adopt/reject framing for
*reporting* purposes (the adoption gate itself can stay binary for deployment; the manuscript's
description of the *evidence* should not be):

- **Improves**: point estimate of mean gain (see 3.1 for the correct pooling unit) is positive, its
  magnitude is large relative to the observed between-season spread (SD, full range, and
  leave-one-season-out means), and it clears the declared practical floor.
- **Harms**: point estimate is negative and its magnitude is large relative to that observed
  between-season spread.
- **Inconclusive / not clearly different from no effect** ("does not clearly help", the precise claim
  this manuscript can make): the point estimate's magnitude is small relative to the observed
  between-season spread. This is explicitly *not* the same claim as "M2 has no effect" — it means the
  observed effect, if any, is smaller than the resolution of this design.

> **Open tension (needs a Lennon decision):** the improves/harms/inconclusive wording above is
> descriptive, but sorting a point estimate into "large relative to spread" versus "small relative to
> spread" still functions as a rule that decides whether the observed effect is distinguishable from
> noise. A purely descriptive report can state the estimate, SD, range, and leave-one-season-out means
> and stop there, assigning no bucket at all. This document cannot resolve that tension on its own:
> either the three-way rule stays, understood as a reporting convention built on a descriptive
> comparison rather than a hypothesis test, or the manuscript drops the buckets and reports only the
> descriptive quantities. Flagged deliberately rather than papered over.

Required companion disclosure whenever "inconclusive" is reported: the observed point estimate stated
next to the observed between-season SD and range, so a reader can see the effect's size relative to the
amount of season-to-season variation actually seen. This directly operationalizes the diagnostic's
finding that each fold's observed effect size is small relative to that fold's own seasonal noise. No
alpha level, power target, or minimum-detectable-effect quantity is invoked: the comparison is
descriptive (observed effect versus observed spread), not a test.

`[DECISION]` Practical floor for the "improves" bucket: keep 0.0012 overall / 0.002 h2 (D-10's values)
as the practical floor, but state explicitly in METHODS.md that these floors were checked and found
non-binding relative to the observed between-season variability in every fold of the campaign that
motivated this framing — i.e., say so, rather than let a reader assume they did the work.

**Magnitude context, corrected (ming-wonderwoman, 2026-09-18, two messages — the first overstated this,
the second corrects it):** the -0.0084 mean weighted NLL figure is a mean-over-specs figure and reads as
more transformative than it is. Ranked on robustness instead (same experiment, 205 corrected specs, 11
seasons): the single best-by-mean spec improves only 3 of 11 seasons (its mean is carried by two seasons,
degrading the other eight); **zero of 205 specs are never worse than all-off** (what the gate's
zero-degradation rule actually requires); the best *median* per-season gain across specs is only 0.0044.
So 1.1 is a real, genuine fix — it makes M2's fit demonstrably better out-of-sample (§1.1's main entry
above) — and it still does not make M2 adoptable under the current gate. This is independent, clean-data
confirmation of the diagnostic's "effectively unsatisfiable" characterization, now traced to a specific
mechanism (§2.3). State plainly wherever 1.1 is described: it fixes a real defect without resolving the
adoption question, and the manuscript must not let "we found and fixed a real bug in the fit objective"
read as "and therefore M2 should be adopted."

### 2.3. The zero-degradation rule's *form*, not its threshold, is the problem (ming-wonderwoman, 2026-09-18)

This corrects 1.2's earlier framing ("relax the tolerance to a declared small positive number") — that
framing assumed the rule just needs a bigger number. It does not. `max_season_degradation`'s statistic is
the **minimum** gain over 9-11 seasons — the noisiest order statistic available — and at this sample size
it is dominated by whichever single season happened to draw badly, regardless of the true effect.

Evidence: the pooled between-season SD of the per-season gain, on the clean v2.1 frame, is 0.0698 — the
gains under discussion (0.002-0.02) are 3-30x smaller than this noise. Simulating an M2 that is genuinely
better in *every* season by a fixed true gain, drawing 11 seasons with that SD, gives the probability the
worst-case rule actually passes:

| true gain | P(min >= 0) | P(min >= -0.005) | P(min >= -0.02) |
|---|---|---|---|
| 0.005 | 0.001 | 0.001 | 0.006 |
| 0.010 | 0.002 | 0.003 | 0.010 |
| 0.020 | 0.005 | 0.008 | 0.025 |
| 0.050 | 0.051 | 0.069 | 0.150 |
| 0.100 | 0.424 | 0.477 | 0.622 |

A model that is truly better everywhere by 0.01 (already larger than anything observed) passes the
current rule about 1 time in 500. Loosening the tolerance to 0.005 or 0.02 barely moves this — you would
need a true gain near 0.10, more than 20x the best median gain observed, for even a coin-flip pass rate.
"Pick a bigger tolerance" does not rescue this criterion; the rule's *shape* needs to change. Caveat on
the simulation: it assumes i.i.d. normal per-season gains with constant SD, while real gains are likely
correlated and heteroscedastic across seasons — the gap between the observed effect sizes and the ~0.10
needed is wide enough that the conclusion is expected to survive this simplification, but the exact
probabilities above should not be quoted as precise.

Consequence for how "M2 does not clear the adoption gate" should be read: a criterion a genuinely correct
model fails on more than 99.8% of random draws is not principally measuring model quality — it is close
to measuring whether 11 noisy seasons all happened to land positive. The 0/205 robustness result above,
and every "keep_m1" decision in this document and the campaign, should be read as evidence about *the
rule*, at least as much as evidence about M2.

**Proposed replacement, splitting the decision by its actual source:**

- **Form (a statistical question — what's estimable at n=11):** worst-case/minimum is not; central
  tendency with the gate's existing uncertainty-aware threshold is (this is already what section 2's
  improves/harms/inconclusive comparison uses). **Sign consistency** — better than M1 in at least k of n
  seasons — is a second, low-variance, interpretable statistic worth adding: 9-of-11 seasons corresponds
  to a two-sided sign-test p of roughly 0.03 under a no-effect null, a bar a genuinely better model can
  clear and a genuinely neutral one mostly cannot. It also discriminates on the actual data: 10 of 205
  specs already improve at least 6 of 11 seasons under the corrected (1.1) weighting.
- **Threshold (an operational question — Lennon's and epidemiology's, not a statistical one):** in
  forecast units, the best robustness-ranked spec moves weighted MAE from 8.66 to 8.40 percentage points
  of positivity, helping 8 of 11 seasons, with its single worst regression (+0.43 points, 2023-24) traded
  against its best gain (-1.08 points, 2025-26). Whether that trade is acceptable in a severe season is a
  judgment call about operational behavior, not something a statistic can settle.

A worst-case guard can still exist as a backstop, but if kept it should be set at an operationally
meaningful magnitude, not zero — zero is not a strict version of the rule, it is a different, effectively
unpassable rule. `[DECISION]` Lennon picks the form (sign-consistency test, central-tendency-only, or
some combination) and, separately, any backstop threshold — **the form must be fixed and recorded in the
protocol before the clean re-run, and must not be set by looking at any outer-fold result: that is the
same circularity as §1.3's grid, and more consequential, because this is the headline adoption
criterion, not a secondary sensitivity.**

## 3. [MANUSCRIPT/JOINT] Giving M2 a fair, well-resolved descriptive comparison

3.1. **Use the shadow-M2 outer-holdout predictions as the primary evidence, not the fold-level inner-tuning
     gain estimates.** The diagnostic's caution against pooling was specifically about pooling the
     *inner* fold-level gain estimates, because those 11 folds share 8-9 of their 10 training seasons —
     not distinct units. That caution does **not** apply to the actual outer-holdout replay: each of
     the 11 held-out seasons is genuinely distinct, and the shadow M2 column (already collected in every
     fold, including the 10 where the gate kept M1) gives 11 distinct per-season M1-vs-shadow-M2
     comparisons on data none of those folds' own tuning ever touched. This is exactly what protocol
     s5.5's "adoption-rule evidence" was already designed to produce — it is the correct, valid unit for
     the descriptive contrast in section 2, not the inner gain estimates the diagnostic flagged as
     confounded by uncorrected selection over ~650 specs. `[MANUSCRIPT]` compute and report this
     pooled outer-holdout estimate (mean shadow-M2-vs-M1 gain across the 11 held-out seasons, paired by
     season, reported alongside its observed season-to-season SD, range, and leave-one-season-out means)
     as the manuscript's actual "does M2 help" evidence, separately from each fold's own adoption
     decision.

3.2. **Correction (independent Gemini review, 2026-09-18): the phase-restricted spec is NOT
     pre-registered, and this document must stop calling it that.** The original draft of this section
     proposed a decline+turning-only M2 spec as a "pre-registered" restricted family. The reviewer is
     right to call that out: the decline/turning signal was identified *by looking at the phase-stratified
     results of these exact 11 outer folds*. Deciding, after seeing that, to restrict the next re-run to
     those same phases on those same seasons is post-hoc spec selection wearing pre-registration's
     clothes — the data have already been observed. This is a real methodological error in the original
     plan, not a stylistic nit; do not carry the "pre-registered" language into METHODS.md or
     ANALYSIS_PROTOCOL_v2.0-draft.md.

     What survives: a decline+turning-restricted M2 variant is still worth running, but only as an
     **explicitly exploratory, hypothesis-generating sensitivity analysis**, reported as such, with the
     circularity stated plainly in the manuscript text (e.g. "this restricted spec was chosen by
     inspecting the phase pattern of the primary campaign's results and is therefore not an independent
     evaluation; a genuinely pre-registered version would require this restriction to be fixed *before*
     seeing a new campaign's data — the earliest a real evaluation of it could exist is a subsequent,
     still-unseen cycle"). It must never be presented as, or substituted for, the primary evidence in
     3.1's pooled estimate, and it cannot license an "improves" verdict under section 2's three-way rule
     — at most it can inform future pre-registration for a cycle that has not yet generated data.

3.3. **The primary, non-circular fix for selection optimism is 1.3 (shrink the grid a priori), not a
     phase-restricted spec chosen from this campaign's results.** Report 3.2's exploratory variant
     separately from, and clearly subordinate to, both the 3.1 primary evidence and any result from the
     smaller, substantively-justified grid in 1.3 run on a future cycle.

## 4. Sequencing

1. [PRODUCTION] Land fixes 1.1-1.3, with their own equivalence tests, on ming-wonderwoman's current code.
2. [PRODUCTION] Run 1.4's single diagnostic fold (2022-23) to confirm the fixes behave as expected.
3. [MANUSCRIPT] Freeze the 2.1-2.3 reporting rule and the observed-effect-versus-observed-spread
   disclosure in `ANALYSIS_PROTOCOL_v2.0-draft.md`
   *before* step 4, so it is pre-registered rather than chosen after seeing new numbers.
4. [JOINT] Decide whether the fixes alone justify a fresh 11-fold campaign, or whether to bundle it with
   the restricted-spec variant (3.2) in one pass, once ming-wonderwoman's current production work lands
   ("the new code" per Lennon, 2026-09-18) — not before.
5. [MANUSCRIPT] Compute the 3.1 pooled outer-holdout estimate from whichever campaign becomes final,
   report per the 2.1-2.3 rule, and record the restricted-spec result per 3.3.

## Open decisions for Lennon

- `[DECISION]` §1.2's diagnostic-only-at-tuner / gate-only-enforcement split is implemented (no objection
  from ming-wonderwoman). Separately and more importantly per §2.3: pick the adoption gate's *form*
  (sign-consistency test, central-tendency-only, or a combination — not a worst-case/minimum statistic,
  which is statistically unusable at n=11 regardless of threshold) and, independently, any backstop
  degradation tolerance — fixed before the clean re-run, not set by looking at any outer-fold result.
- `[DECISION]` Confirm the three-way improves/harms/inconclusive reporting rule (section 2) and the
  observed-effect-versus-observed-spread disclosure requirement before any new numbers exist — and
  resolve the open tension noted in section 2 (whether the three-way buckets are a purely descriptive
  reporting convention or still function as a rule that decides whether an effect is distinguishable
  from noise; if the latter, the manuscript should instead report only the descriptive quantities).
- `[DECISION]` Bundle the restricted-spec variant (3.2) into the same re-run as the bug fixes, or treat
  it as a later, separate sensitivity pass.
