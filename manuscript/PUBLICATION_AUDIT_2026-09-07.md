# Publication audit: PAGe

Audit date: 2026-09-07 (America/Toronto). Reviewer: Jax/Codex.

## Assessment

The project has a credible methods-and-software contribution, but the current
evidence bundle is not ready for submission. The strongest contribution is the
ordered operational chain: ignition detection, partial-season phase/peak
alignment, and short-horizon prediction with a frozen seasonal model. The
existing experiments establish executable seasonal replay, not comparative
benefit or calibrated predictive uncertainty.

This is one evidence-based technical/editorial audit, not five independent
reviews. The seasonal-forecast skill and academic-paper-reviewer criteria
informed it. The latter's referenced report templates were absent; this report
uses a finding/evidence/remedy structure. No models, results, season membership,
or manuscript primary definitions were changed.

## Scope and verification

Inspected the current working-tree implementation, stage contracts, scoring,
runtime, tuning runner, package metadata, CI definition, vignette, manuscript
plan, Methods, Results, protocols, skeleton, and literature synthesis. Read the
local BCC archive copies for all eleven principal runs, including prediction
CSVs, run manifests, and stage boundary reports. This did not verify live BCC
file equality or independently reproduce training.

- All eleven archived prediction tables reproduce the reported seasonal NLLs
  within 5e-13. There are 655 scored rows.
- Every inspected boundary report ends in `stop_bracketed`, `accept_null_drop`,
  or `stop_small_gain`; none contains `expand_required`. This verifies recorded
  dispositions, not the scientific adequacy of every search range.
- Ten seasons have 57–73 rows across both horizons; 2025–26 has 17.
- Targeted tests for stage contracts, fold integrity, label safety, correction
  specification, metrics, and data adaptation passed, with five emitted
  guard/deprecation warnings and one initially skipped private-data test.
- Repeating the adapter tests with
  `PAGE_ONTARIO_TEST_FILE=/home/yeli/FLU/flu_testing_data.csv` passed without a
  skipped Ontario comparison. No private observations are copied into this report.
- Package build, installation, examples, syntax, exports/documentation matching,
  and code checks passed locally. The broader check ended with 1 error, 2
  warnings, and 2 notes: 781 passing assertions, one socket-creation failure,
  six test warnings, and nine skips. The failed M1–M2 handoff test file passed
  when rerun with local sockets enabled, identifying the sandbox restriction
  rather than a reproduced handoff defect. The full check was not repeated.
  The two vignette warnings follow from disabling vignette building in this
  audit; notes concern the environment's D-Bus access and three Rd escaped
  LaTeX-special entries. Network dependency-index access was also restricted.
  PDF-manual and fully built/executed-vignette validation remain unverified.

Test logs: `/tmp/page-publication-audit-tests.log` and
`/tmp/page-publication-ontario-test.log`. Package log:
`/tmp/page-publication-package-check.log`.
The successful socket-enabled rerun is in `/tmp/page-publication-handoff-test.log`.

## Submission-blocking findings

### 1. The reported experiment does not match the manuscript primary analysis

Evidence: [Methods](METHODS.md:215), [protocol](ANALYSIS_PROTOCOL.md:32),
[runner](../scripts/run_manuscript_holdout.R:304),
[tuning score](../PAGe/R/m2_loso_eval.R:382), and
[replay scoring](../PAGe/R/evaluation_gates.R:676).

The manuscript specifies h2, origins from detected ignition through +12 weeks,
trial-weighted NLL within season, and a one-standard-error selection rule.
The runner explicitly selects M2 by `min_nll`. Its tuning evaluator averages
Bernoulli cross-entropy equally over weekly/horizon rows, while the final
replay scorer weights rows by target denominator. Final reported NLL combines
h1 and h2 over the available season, reaching +28 to +36 weeks in the ten
longer replays. M1 uses its own peak-loss selection and a 0.05-week minimum-gain
preference; M0 also has its own detector objective. A blanket h2/one-SE
description does not describe these stage-specific choices.

Remedy: document the executed stage-specific objectives and selection rules,
and explicitly reconcile them with the frozen protocol. Retain the existing
results as the executed analysis. Score h2/0–12 as a clearly identified
restriction of existing predictions. If protocol-compliant candidate selection
is required, recover inner predictions first; rerank/refit/replay where the
necessary scores exist, otherwise rerun affected tuning. Because outcomes have
already been viewed, do not silently amend the protocol or call a revised
analysis prospectively prespecified.

### 2. The replay export cannot substantiate all three promised outputs

Evidence: [standardizer](../PAGe/R/evaluation_gates.R:758) and
[runtime return](../PAGe/R/pipeline_runtime.R:843).

Runtime emits M1 parameters/curves and M2 bounds. The replay wrapper retains a
reduced prediction table, a single ignition week/status, and summary metrics.
The raw-path standardizer drops interval bounds and removes nonfinite forecasts
and unavailable targets. The inspected replay diagnostics report intervals
`not_available`. The principal bundle therefore cannot establish origin-wise
peak error, interval performance, or complete forecast availability by itself.
Other tuning caches may contain useful information, but are not substitutes
for outer-holdout stage outputs.

Remedy: preserve the expected origin–target–horizon roster, failure codes,
detector decision week and estimated onset, M1 peak predictions, forecast bounds,
and the action that produced each final forecast. Replaying frozen kits should
recover many of these outputs without retraining. Report M0 error/delay/misses,
M1 peak error by lead-to-peak, and h1/h2 errors separately. Distinguish an
estimated earlier onset from the later date on which the detector declared it.

### 3. Post-peak override corrupts the recorded raw-GAM residual identity

Evidence: [runtime](../PAGe/R/pipeline_runtime.R:707) and
[frozen tuning evaluator](../PAGe/R/m2_loso_eval.R:348).

Both paths replace `pr$m2_p` with the M1 forecast before recording
`m2_eta_raw = qlogis(pr$m2_p) - bl`. After replacement, this is an M1-derived
quantity, not the uncorrected GAM predictor described in the Methods and code
comments. In addition, reconstructing an uncorrected predictor from a capped
probability can lose the original predictor even before the override.

Remedy: return and record the actual GAM linear predictor before bias,
probability caps, and M1 substitution. Keep the final published probability as
a separate field. Verify a deterministic post-peak transition example in both
paths. Quantify whether forecasts change: a permanently active M1 override may
mask the state error in published point forecasts, but does not validate the
stored correction state. Changed tuning scores can require renewed selection.

### 4. Existing bands are not a demonstrated full predictive distribution

Evidence: [M2 prediction](../PAGe/R/m2_training.R:149) constructs bounds from
`eta +/- 1.96 * se.fit`. Alignment spread is an M2 covariate.

These are conditional fitted-mean bands. They do not by construction account
for all observation variation, upstream estimation, selected parameters, online
correction uncertainty, or surveillance revisions. Giving spread to a GAM does
not itself propagate uncertainty into a predictive distribution.

Remedy: label current intervals according to what they estimate. Before making
predictive-coverage claims, define the target distribution and a fold-trained
uncertainty procedure, assess overdispersion, and report coverage, width, and
interval score. Quantile forecasts can use WIS; this recommendation follows
the [scoringutils definition](https://epiforecasts.io/scoringutils/reference/wis.html).
If this is deferred, narrow the paper to point/mean forecasting and avoid
claiming validated probabilistic trajectory forecasts.

### 5. A shared commit does not yet identify the complete executed workflow

Evidence: [execution record](HOLDOUT_EXECUTION.md:5) and the eleven
`run_manifest.rds` files. All record nonempty `repo_status`. Inspected examples
list untracked `2012/`, `2013/`, and, in later runs, the manuscript runner and
reconciliation/finalizer scripts. This does not prove differing installed
package code, but those entry points are not captured by the shared commit.
The run manifests record input hash and commit, but not an installed-package
hash, dependency lock, session information, seed, or protocol hash.

Remedy: recover and hash the executed scripts and installed package/source
bundle; attach environment and seed records where recoverable. Make missing
historical provenance explicit. Build a clean release snapshot and compare it
with the execution snapshot. The current tree has untracked package source,
including the generic adapter, and modified exports; a fresh clone of HEAD
does not reproduce this working tree. The branch is also locally divergent
from its remote-tracking reference. Resolve this before naming a release.

### 6. Comparative and attribution evidence remains missing

Evidence: [Results](RESULTS.md:69) explicitly lists outstanding comparator,
ablation, label-sensitivity, and simulation results.

Absolute NLL is not enough to show practical forecast value; season prevalence
also affects cross-entropy. The evidence cannot yet establish that alignment,
ignition gating, or the GAM adds value relative to recent observations or
historical curves. The strongest alternative explanation is that template
continuation and the post-peak M1 substitution account for much of performance.

Remedy: prioritize calendar GAM (the primary comparator), persistence,
historical analogue, and M1-only continuation, followed by the other frozen
comparators. Preserve the declared statistical and regularized-ML comparisons.
Run the planned ablations; include post-peak substitution and online season
effect as explicit algorithm components. Use identical eligible rows and
report availability separately, so restricting to successful PAGe origins
does not hide the cost of missed or delayed ignition. Report paired seasonal
differences descriptively; no t-tests, p-values, or significance claims are
needed or recommended.

## Additional mathematical and statistical improvements

1. Write the implemented M1 objective explicitly, including test-count
   weighting, phase weights, penalties, admissible warp constraints, and scale
   identifiability gates. Its ensemble has weights proportional to
   `exp(-(loss_j-min_loss)/temperature) * exp(-slope_weight*abs(slope_gap_j))`.
   Explain loss normalization and the effect of surveillance volume on these
   weights. These are algorithmic weights, not established posterior probabilities.
2. Describe shift, dilation, and amplitude identifiability on short rising limbs.
   Use existing constraints as part of the method; assess flat, late, asymmetric,
   multi-peak, low-denominator, and missing-week seasons in simulations.
   Publish failure behavior rather than only successful examples.
3. Call the evaluation exchangeable-season outer LOSO with within-season
   walk-forward predictions. Later calendar seasons intentionally train earlier
   holdouts. This supports transfer across the declared season set, not a claim
   that all training data were historically available at each calendar date.
   Keep the user's four exclusions and 10-training/1-holdout design.
4. Distinguish honest outer holdout evaluation from fully retuning the upstream
   pipeline inside every inner fold. `build_m2()` takes M0/M1 choices selected on
   the outer training set and rebuilds inner reference fits with those fixed
   choices. Do not describe its internal scores as independent end-to-end
   nested validation. This alone does not invalidate an untouched outer fold.
5. Clarify the field called Brier score. In
   [diagnostics](../PAGe/R/evaluation_gates.R:206), `(p_hat-p_obs)^2` is squared
   error of aggregate positivity. Individual Bernoulli Brier score is
   `p_obs*(1-p_hat)^2 + (1-p_obs)*p_hat^2`, adding `p_obs*(1-p_obs)`.
   The distinction affects absolute scores, though paired model differences
   on identical rows retain the same ordering. Rename or compute explicitly.
6. Resolve the 2025–26 ignition-label provenance: the
   [label protocol](IGNITION_LABEL_PROTOCOL.md:44) says the vector is incomplete,
   while the runner supplies `2025-26 = 19L`. Verify its source/date/hash and
   actual fold-filtered use; the mismatch is not itself proof of label leakage.
   Run the already planned +/-1-week and M0-derived-label sensitivities.
7. Report 2025–26's partial support both as a target and as a training member of
   the other folds. Equal treatment of eligible seasons does not imply equal
   observation coverage. Do not add new data or drop this season silently.
8. Verify prefix invariance: appending unseen future observations must not
   change any already-issued forecast or detection decision. Add this to
   parity checks between the tuning evaluator and deployment runtime.

## Diagnostic rescoring of the existing frozen-kit predictions

These are trial-weighted h2 scores for `0 <= t_since <= 12`. They demonstrate
the reporting mismatch; they do not repair candidate selection, establish
comparator benefit, or replace the registered Results. No model was retrained.

| Season | h2 rows | Restricted NLL | Restricted MAE |
|---|---:|---:|---:|
| 2012-13 | 13 | 0.559506 | 0.078304 |
| 2013-14 | 13 | 0.478357 | 0.069322 |
| 2014-15 | 13 | 0.578380 | 0.055388 |
| 2016-17 | 13 | 0.522664 | 0.066608 |
| 2017-18 | 13 | 0.385750 | 0.025562 |
| 2018-19 | 13 | 0.406286 | 0.032896 |
| 2019-20 | 13 | 0.410884 | 0.041293 |
| 2022-23 | 13 | 0.341348 | 0.046958 |
| 2023-24 | 13 | 0.350616 | 0.045718 |
| 2024-25 | 13 | 0.472426 | 0.047497 |
| 2025-26 (partial) | 8 | 0.585022 | 0.085408 |

## Package publication recommendations

The package has useful foundations: MIT licensing, exported lifecycle APIs,
strict stage identities, synthetic workflow tests, CI, and a generic data-frame
adapter that passes the authorized Ontario comparison. Preserve these.

- Produce a versioned, clean source tarball with a dependency/environment
  record and a citation file. Hash the installed package used by workers.
- Make the first vignette runnable with synthetic data. The current
  [intro](../PAGe/vignettes/intro.Rmd:12) disables evaluation globally, starts
  from a private-data path, and incorrectly says `train_pipeline()` has not
  been refactored to compose stage contracts.
- Explain that the generic adapter supports binomial count/denominator
  surveillance, not arbitrary continuous outcomes or every disease measurement.
  Pathogen-specific season origin, labels, and tuning must be specified.
- Consolidate core score calculation and correction-state logic to reduce
  drift between training and runtime. Preserve documented compatibility paths.
- Evaluate which plotting/UI dependencies can become optional after inspecting
  actual calls. Avoid adding new model frameworks until the primary workflow
  and comparator results are reproducible.
- Expand CI to meaningful R/platform coverage for an intended public release,
  and exercise one installed-package synthetic end-to-end workflow. An
  unevaluated vignette and mocked lifecycle tests are not full user validation.

## Manuscript structure and positioning

Keep *Epidemics* as the working target, contingent on comparative and stage-level
evidence. This audit could not retrieve the live publisher author guide, so it
does not assert current word limits or submission requirements. Use the
[EPIFORGE reporting guideline](https://journals.plos.org/plosmedicine/article?id=10.1371/journal.pmed.1003793)
to map claims to study goals, data, model details, evaluation, and generalizability.

The existing skeleton already follows the three stages, but the 7,500–8,400-word
plan risks letting governance mechanics dominate the scientific argument.
Recommended main-text sequence:

1. Introduction: the operational problem and the gap between calendar time and
   epidemic phase; acknowledge prior curve-deformation and analogue work.
2. Data and targets: positivity, origin information, ignition/peak definitions,
   excluded seasons, partial coverage, and final-data vintage limitations.
3. Method: one pipeline figure, concise M0/M1/M2 equations, and two algorithms
   distinguishing once-per-season training from weekly state updates.
4. Evaluation: outer folds, stage-specific tuning, shared scoring window,
   comparators, ablations, metrics, and failure accounting.
5. Results: data/availability, ignition, peak, h2 comparator results, h1 and
   ablations, then failures and runtime. Include RSV only after its data and
   independent pathogen-specific results are validated.
6. Discussion: where phase alignment helps, where it fails, uncertainty and
   surveillance limitations, and portability after retraining.
7. Software/data availability: minimal public API example, release identifier,
   controlled-data access, and reproducibility instructions.

Move exhaustive grid histories, identity schemas, legacy promotion rules,
software API catalogues, and expanded simulation specifications to supplements.
Maintain a claim-to-artifact map for each table and figure. Describe novelty as
the evaluated integration of the stages; the literature synthesis itself
correctly notes that time warping, historical templates, and peak forecasting
are not new inventions.

## Recommended execution order

| Priority | Deliverable | Retraining required? | Completion evidence |
|---|---|---|---|
| P0 | Reconcile protocol versus executed experiment | No for audit; possibly for selection | Dated deviation record and exact score/selection specification |
| P0 | Recover source/package/script provenance | Usually no | Hash-bound execution snapshot and clean candidate release |
| P0 | Repair raw-predictor logging and lossless replay export | Replay required; tuning impact must be measured | Deterministic regression and runtime/evaluator parity checks |
| P1 | Canonical stage-level and h2 tables | Usually frozen-kit replay/rescoring | One expected-row ledger, predictions, landmarks, failures, and manifest |
| P1 | Primary comparator and attribution experiments | Comparator/ablation training required | Same folds/rows, descriptive contrasts, all failures retained |
| P1 | Label sensitivity and uncertainty validation | Depends on component changed | Sensitivity runs and correctly defined interval diagnostics |
| P2 | Focused simulations and conditional RSV application | Yes | New evidence with explicit data-generating/source contracts |
| P2 | Runnable package examples and final manuscript assembly | No seasonal retraining | Clean package checks, rendered example, EPIFORGE crosswalk |

The immediate next work should be P0 reconciliation and implementation repair,
followed by replay export and comparator analysis. More prose or a larger model
search will not resolve the current evidence mismatches.
