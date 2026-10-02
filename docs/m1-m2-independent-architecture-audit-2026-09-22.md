# Independent architecture audit — PAGe M1/M2 redesign

Audit date: 2026-09-22. Reviewer: Liz. Scope: architecture and validation design, with targeted inspection of existing implementation contracts; no model fitting or production changes.

**Verdict: support the direction; request contract revisions before statistical implementation and performance claims.** Direct peak-time inference, restrained shape complexity, explicit sequential state, separate passage confirmation, and a compact M1-to-M2 interface are good choices. The particular smoother, posterior family, and M2 learner can remain open. The data, validation, and state contracts cannot.

Primary source: [September 21 redesign plan](m1-v2-plan-2026-09-21.md), SHA-256 `f546b9423c6bde4264815b00a71f3b1e0efe26276bcd0a13a9104d10bc1ae41a`. Line references below refer to this snapshot. Earlier plans are contextual evidence, not assumed to govern the new cycle. Earlier audit verdicts were not used to construct these findings.

Priority P1 means resolve before the affected modeling/evaluation stage. P2 means resolve before the interface or release is frozen. Findings describe omissions or ambiguities in a preimplementation plan, except where existing code is explicitly cited.

## 1. P1 — Outer LOSO does not specify the selection and stacking exclusions

**Evidence:** lines 439–445, 506–516, 684–695, and 737–745 require outer LOSO and causal test-season features, but do not define inner model selection or the generation of M2 training features. Lines 170–253 and 776 invite choices from all-season geometry and LOSO evidence.

**Risk:** within-season prefixing is insufficient if the historical shape, prior, preprocessing, or selected hyperparameters already used that season's full trajectory or labels. Selecting model families/rank from outer results also turns those results into development evidence. This risk applies to annotation-derived shape models as much as to the legacy templates. Selection and evaluation need separate boundaries; see [Cawley and Talbot's model-selection study](https://www.jmlr.org/beta/papers/v11/cawley10a.html).

**Required revision:** write an exclusion table. Let `o` be the outer test season, `v` an inner validation season, and `r` an M2 training-row season:

| Purpose | Seasons excluded from upstream fitting |
|---|---|
| Outer test features for `o` | `o` |
| M2 training features for `r`, within outer fold `o` | `o, r` |
| Inner validation features for `v` | `o, v` |
| M2 training features for `r`, while validating on `v` | `o, v, r` |

At each evaluation boundary, select every tuned upstream component without that evaluation season. For strict out-of-fold training features, the row season must also be absent from upstream selection, or the resulting approximation must be explicitly labelled. Apply these rules to M0 selection, ignition priors, curve/rank/normalization fitting, passage thresholds, M2 selection, and interval calibration. Labels remain available for training targets and evaluation, never as oracle runtime features.

This preserves an existing project safeguard: [nested upstream selection](../PAGe/R/nested_season_evaluation.R#L330) and [pair-excluded references](../PAGe/R/nested_season_evaluation.R#L223) already implement related exclusions. Conversely, the legacy [M2 row builder](../PAGe/R/m2_subset_correction.R#L1048) can substitute manual ignition truth; it must not silently become the new causal feature factory.

Freeze a small candidate-selection procedure before evaluating it. All-season descriptive exploration is legitimate, but its influence on the chosen architecture must be disclosed; nesting cannot retroactively erase that exposure. Cache by complete training/exclusion set, data/label hashes, specification, and code identity.

**Acceptance check:** provenance assertions at every fit and feature row; changing an excluded season's labels cannot change the upstream model or features for that fold.

## 2. P1 — The proposed ignition-duration baseline mixes two clocks

**Evidence:** lines 55–60 correctly distinguish expert ignition from detection. Lines 178, 271–275, and 526–529 nevertheless propose a duration derived from expert ignition while leaving the prediction formula's `ignition` unspecified.

Write `I*` for expert ignition, `A` for detected origin, and `D = T* − I*`. Substituting `A` into `I* + D` adds the detection error `A − I*` to the baseline. For example, expert ignition 10, detection 12, and duration 8 imply peak 18; the substituted baseline predicts 20. This discrepancy exists even with a perfectly known duration.

**Required revision:** start with the empirical distribution of `T* − A`, where historical `A` values come from excluded-season causal M0 replay. Preserve negative remaining durations when M0 detects after the peak. Alternatively, model latent ignition jointly with detection delay and integrate that uncertainty. Record the M0 identity with the prior; changing M0 changes the relevant distribution.

Handle missed ignition explicitly. The duration among successfully detected seasons is conditional on detection and does not measure end-to-end performance in missed seasons. Any ignition-relative M2 feature must use the same causal clock in training and deployment.

**Acceptance check:** delayed, early, post-peak, and absent detection cases; no held-out expert ignition in runtime state or feature construction.

## 3. P1 — Annotation needs a coordinate and uncertainty contract before tooling

**Evidence:** lines 109–164 require decimal expert labels but defer ambiguity support; lines 139–144 call the axis “epidemiological week.” PAGe's [calendar contract](season-calendar.md#L3) uses July-start `weekF`, while its [continuous timing convention](../PAGe/R/timing_coordinates_v2.R#L3) represents week `w` as `[w,w+1)`. Existing [label normalization](../PAGe/R/timing_labels_v2.R#L16) rejects noninteger labels and expands single weeks to pairs.

**Risk:** MMWR week, season week, weekly interval start, and weekly midpoint are different coordinates. Their conflation can introduce a systematic timing shift. A numeric decimal also does not establish the accuracy of a latent within-week event inferred from weekly aggregates. Agreement between annotators alone does not establish a lower bound on error against the unknown biological peak.

**Required revision:** store authoritative continuous season time plus calendar identity and date mapping; display season and MMWR/date axes explicitly. Declare when an origin occurs relative to weekly aggregation and release. Use one canonical positivity definition and data-snapshot hash in the annotation interface.

Retain the expert decimal point without silently regenerating it, but also support an ambiguity interval/status from the outset. Define “primary peak” for plateaus and multiple waves, allow unlabelable/censored cases, and blind annotation to model predictions. The [September 19 plan](../../PAGe/docs/m1-retune-plan-2026-09-19.md#L215) documents plateaus and competing peaks, so this is an existing data concern. That plan's interpolation rule need not be retained.

Introduce an explicitly versioned decimal-label schema and adapter; do not pass new labels through legacy integer normalization. Score point-label error as agreement with the declared reference, with sensitivity to ambiguous labels. Do not describe it as verified sub-week biological accuracy.

**Acceptance check:** decimal round trips, 52/53-week calendars, year rollover, plateau/multiwave labels, and explicit rejection of incompatible legacy schemas. Annotation tooling can proceed once these choices are documented.

## 4. P1 — Candidate-dependent activation and stopping can bias reported accuracy

**Evidence:** lines 449 and 506–514 evaluate after detection and until passage; lines 479–483 list passage diagnostics but no joint selection rule. Lines 500–502 leave M2 scoring unspecified.

**Risk:** if “until passage” means the candidate's own confirmation, early locking removes subsequent difficult origins. If it means reference peak passage, say so. Late or missed M0 detection can similarly shrink the evaluated set. A candidate with absolute errors `[0,4,4]` has MAE 2.67; stopping after the first origin yields reported MAE 0 if dropped origins disappear. Separate passage diagnostics do not prevent selecting that candidate on MAE.

**Required revision:** predeclare a candidate-independent evaluation ledger and a missing/abstention policy. Reference truth may define evaluation windows, never runtime cutoffs. Report both conditional forecast accuracy and end-to-end service coverage, including delayed/missed activation and false early passage. Score passage against the same declared primary-peak target used for forecasting.

For M2, state whether phase refers to origin or target week; define how decimal peak +1/+2 maps to integer forecast targets. Freeze season aggregation, horizon weights, phase weights, minimum meaningful improvement, and acceptable coverage/degradation before selection. Retain unavailable rows with reasons and distinguish unavailable forecasts from unobserved outcomes. Rescore the sealed comparator on the same truth and eligible rows; the cited integer MAE is not directly comparable to a new decimal score.

**Acceptance check:** premature lock, missing forecasts, and missed ignition cannot improve the declared joint selection result solely by removing rows. Show per-season paired results and all denominators.

## 5. P1 — Sequential inference needs an information-consumption rule

**Evidence:** lines 271–281 promise updating a prior; lines 574–598 specify serializable state but not what each transition consumes. The illustrative state also includes evaluation-only truth at line 584.

**Risk:** multiplying last week's posterior by a likelihood for the entire observed prefix counts old data again and produces artificial certainty. Serializing that result merely reproduces the mistake. Duplicate deliveries and revised observations create the same class of problem.

**Required revision:** choose either an incremental conditional update

`p(state | y[1:t]) ∝ p(y[t] | state, y[1:t−1]) p(state | y[1:t−1])`

or recomputation from the original prior and the complete prefix. The state must retain sufficient nuisance/history information for the chosen update. The initialization prior and update likelihood must also account for any overlapping observations used by M0/detection-conditioned initialization.

Define duplicate, missing, out-of-order, and revised-week behavior. Keep reference labels in a separate evaluation object. State should include consumed observation identities, as-of cutoff, data revision identity, state schema, model bundle identity, and RNG state where needed. If M2 adapts online, only matured outcomes may update it, with horizon-specific accounting.

**Acceptance check:** uninterrupted and save/resume replay agree; duplicate ingestion is idempotent or rejected; suffix changes cannot alter an earlier forecast; incremental inference agrees with the corresponding batch posterior in a tractable example.

## 6. P1 — Naming a parameter “peak time” does not anchor the curve's peak

**Evidence:** lines 259–306 propose direct `T_peak*` and low-rank shape deviations; lines 413–425 define a posterior-averaged curve feature and then anchor it to a locked peak.

**Risk:** an unconstrained smoother or fPCA deviation can move its maximum away from relative time zero. A direction resembling the curve derivative can exchange shape change with time shift, recreating the intended-to-be-removed timing ambiguity. Positive amplitude alone does not fix this. Marginalizing only peak time also need not capture uncertainty in amplitude, width, baseline, or learned shape.

**Required revision:** define whether zero is a constrained primary maximum, a plateau interval, or an expert event anchor that need not equal the fitted maximum. Constrain or diagnose timing-confounded shape directions. Do not impose an arbitrary unique maximum on a clinically defined plateau.

Specify the observation/link scale and weekly aggregation model or approximation. If `g` is logit-scale, `E[logistic(g)]` and `logistic(E[g])` are distinct features. Define `curve_mean` and `curve_sd` precisely, including which nuisance uncertainties are integrated. Curve-level uncertainty is not an observed-percentage prediction interval; M2 must account for residual/observation uncertainty separately.

Locking the public operational decision must not silently set statistical timing uncertainty to zero. Retain a frozen posterior or an explicit approximation with calibration checks. Decide whether internal phase inference can continue after public lock, and version that behavior for M2 training.

**Acceptance check:** shape perturbations cannot silently redefine the declared peak; multimodal timing beliefs and lock transitions yield defined, bounded +1/+2 features without unexplained uncertainty collapse.

## 7. P2 — LOSO, chronological replay, and prospective evidence need separate claims

**Evidence:** lines 439 and 693 mandate outer LOSO, while the product is real-time forecasting. Existing project guidance requires prospective walk-forward behavior. The [current manuscript draft](../../PAGe/manuscript/drafts/ANALYSIS_PROTOCOL_v2.0-draft.md#L107) distinguishes exchangeable-season LOSO from prior-seasons-only evaluation; it also records final-data replay and prior exposure at lines 15–35 and 73–75.

**Required revision:** preserve LOSO as an exchangeable-season assessment and add an expanding-window, prior-seasons-only assessment for chronological transfer. Within-season prefixing does not prevent a model trained on later seasons from using future-season information. Prior-only training is the forecasting evaluation boundary described by [Hyndman and Athanasopoulos](https://otexts.com/fpp3/tscv.html).

Record availability timestamps/data vintages where available. Otherwise label results as retrospective final-data replay. New labels and a new branch do not make previously studied historical seasons untouched evidence. Reserve prospective claims for outcomes collected after the recipe is frozen.

This is a reporting/design requirement, not an assertion that LOSO is unusable. The newer manuscript draft says all 11 seasons are complete; older partial-2025-26 notes are not evidence that today's input is still truncated. Pin and verify the actual input snapshot before applying either assertion.

## 8. P2 — Freeze the dependency and failure contracts earlier

**Evidence:** line 407 says M1/M2 run “concurrently,” whereas lines 511–513 require M1 features before M2. Phase 6 freezes the interface only after several modeling stages. Lines 716–727 omit origin/target identity, scales, availability, and model provenance.

**Required revision:** clarify that both stages are active during the same episode, with a sequential dependency at each origin. Define the schema before modeling, even if optional fields remain experimental:

`observations(as_of) → M0 state → M1 posterior/passage state → features(origin,horizon) → M2 forecast`

Feature rows need season/episode, origin and target time, horizon, coordinate and scale identifiers, availability/reason, feature schema version, and upstream bundle identity. Distinguish pre-ignition, active, passage-confirmed, insufficient-data, and season-ended states. Specify the fallback when M1 inference fails and the target-out-of-season behavior.

Preserve governed stage identities and strict kit compatibility. Keep annotation truth, offline learned artifacts, mutable episode state, and immutable forecast ledgers separate. A model swap should require a defined state reset/migration. The optional common-curve model can be shared by M1/M2 through one fitted-artifact identity without making M2 the owner of official peak timing.

**Acceptance check:** wrong-bundle features and unsupported schemas fail explicitly; fallback is visible in the ledger; M2 cannot consume last week's M1 features under the current origin.

## Recommended sequence

1. Amend the plan with the annotation/time contract, exclusion table, scoring ledger, and evidence labels. These decisions precede model selection.
2. Implement decimal annotation storage and an empty causal replay/feature ledger with the invariants above. Obtain/version expert labels as already planned.
3. Establish detected-origin duration and no-M1 M2 baselines. Use historical geometry to motivate a small declared candidate set, with development exposure recorded.
4. Add a regularized curve only if it improves the declared timing and +1/+2 objectives under the agreed selection procedure. Keep model-family choices open until then.
5. Validate passage, M2 feature ablations, fallback behavior, calibration, and chronological transfer before assembling a release candidate. Compare the frozen comparator without modifying its artifacts.

Do not add fPCA, a hierarchy, or free width merely because they are listed. Equally, do not require M1 and M2 to improve on identical metrics: preserve separate timing and numeric objectives with a predeclared joint acceptance rule.

## Verification and limits

- **Executed locally:** inspected the full redesign plan, relevant calendar/label helpers, nested feature-generation code, and selected earlier protocol sections. Confirmed legacy decimal rejection by source inspection; did not execute the R helper.
- **Executed locally:** small deterministic arithmetic counterexamples reproduced a two-week ignition-anchor shift and scoring-window bias. A conjugate normal example also showed duplicate-prefix updating changes posterior variance from `1/3` to `1/4` after two unit-variance observations under a unit-variance prior. These demonstrate the risks; they are not PAGe performance tests.
- **NOT verified:** historical reported MAEs/EDF, private data completeness, sealed comparator artifact identity, empirical superiority of any proposed model, calibration, or package test status. No package tests or historical training runs were needed for this document-only audit.
- The legacy checkout has pre-existing modifications. Its HEAD is `fd6a4e59437936550220d8c048046c8a361f9778`. The copied `PAGe-m1-v2/.git` points to unavailable `/workspace/PAGe/.git/worktrees/PAGe-m1-v2`; therefore the redesign worktree's branch/cleanliness cannot be verified here. This does not prevent document review, but reproducible implementation needs functioning worktree metadata.
- Only this audit file was created. The redesign plan, package code, legacy checkout, production state, and sealed artifacts were not modified. No commit or push was performed.
