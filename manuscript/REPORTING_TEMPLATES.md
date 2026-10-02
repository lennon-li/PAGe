> **Status (2026-09-15): updated for protocol v2.0 draft** — not frozen; see drafts/ANALYSIS_PROTOCOL_v2.0-draft.md.

# Manuscript reporting templates

Last updated: 2026-09-15

These templates are the canonical reporting layer for the PAGe manuscript.
Populate them from the immutable analysis directory and manifest. Do not type
results manually, add rows because a model performed well, or omit failures.
The templates intentionally contain no hypothesis-test fields: the protocol
requires descriptive reporting only.

## Reporting rules

1. Every numerical value must map to a file, checksum, and analysis ID.
2. Use one canonical prediction table for all model scores, strata, and
   horizons.
3. Report valid, unavailable, and failed forecasts with explicit status codes.
4. Keep historical acceptance evidence separate from the governed replay.
5. Claims are limited to Ontario influenza. RSV and other pathogens are out of
   scope for this cycle and are not reported.
6. Use `NR` for not reported because a field is not estimable, `NA` for a
   missing source value, and `FAIL` for a pipeline or model failure.
7. Do not add p-values, t-tests, confidence intervals, statistical-significance
   labels, or superiority claims unless the protocol is formally amended before
   outcome access.

## Analysis manifest

Save as `analysis_manifest.json` or an equivalent machine-readable record.

| Field | Required content |
|---|---|
| `analysis_id` | Immutable analysis identifier |
| `protocol_version` | Version and SHA-256 of the frozen protocol |
| `application` | `Ontario influenza` |
| `pathogen` | Exact pathogen label |
| `data_source` | Owner, table/file, retrieval method, and access class |
| `data_version` | Download/release date, revision or vintage identifier |
| `data_checksum` | SHA-256 or controlled-data locator |
| `included_seasons` | Ordered season labels in the analysis |
| `excluded_seasons` | Season label, exclusion reason, and whether prespecified |
| `outer_holdout_rule` | Exact outer-fold rule |
| `holdout_season` | Target season for a single-fold artifact, if applicable |
| `training_seasons` | Seasons used to construct that fold's kit |
| `package_version` | PAGe version or Git commit |
| `r_version` | R version |
| `dependency_lock` | Lockfile path and checksum |
| `random_seeds` | Stage and simulation seeds |
| `m0_identity` | Frozen M0 artifact identity |
| `m1_identity` | Frozen M1 artifact identity |
| `m2_identity` | Frozen M2 artifact identity |
| `kit_identity` | Assembled kit identity |
| `canonical_prediction_table` | Relative path and checksum |
| `runtime_record` | Relative path and checksum |
| `code_entry_points` | Functions/scripts used to build outputs |
| `data_permissions` | Publication/disclosure decision and record link |
| `ethics_status` | Ethics/REB determination or pending status |

## Table 1. Data, season support, and eligibility

| Application | Pathogen | Source/version | Seasons available | Pandemic seasons excluded | Full eligible seasons | Weeks expected/observed | Positive/total counts available | Missingness/revisions | Access and publication status | Eligibility decision |
|---|---|---|---|---|---|---|---|---|---|---|
| Ontario | Influenza | `{{source}}` | `{{seasons}}` | `{{seasons}}` | `{{n}}` | `{{coverage}}` | `{{yes/no}}` | `{{summary}}` | `{{status}}` | `{{pass/fail/pending}}` |

Footnote: A “full” season contains every expected surveillance week with a
valid Ontario influenza row under the declared season convention. Do
not promote an incomplete season to full by imputing missing outcomes.

## Table 2. Frozen model and stage registry

| Model/stage | Family | Forecast input or target | Tuned inside outer fold | Fit cadence | Frozen specification ID | Upstream identity | Output |
|---|---|---|---|---|---|---|---|
| PAGe (M0/M1/M2 recipe) | Governed pipeline | Weekly partial curve plus frozen M0/M1/M2 stages | No; fixed recipe, hyperparameters from inner LOSO | One training run per target season; weekly state update | `{{kit_id}}` | `{{m0_id; m1_id}}` | Phase, peak, h1/h2 probabilities and intervals |
| M0 | Ignition detector | As-of positivity, counts, classifier and gate signals | `{{yes/no}}` | Once per target season | `{{id}}` | `{{id/none}}` | Ignition week and audit signals |
| M1 | Template alignment/ensemble | Partial curve and frozen templates | `{{yes/no}}` | Once per target season; weekly state update | `{{id}}` | `{{m0_id}}` | Phase, peak, aligned curve, spread |
| M2 | Binomial GAM | M1 state, observed state, horizon, counts | `{{yes/no}}` | Once per target season; weekly prediction | `{{id}}` | `{{m0_id; m1_id}}` | h1/h2 probabilities and intervals |
| M1 only | Internal reference | Partial curve and frozen templates | `{{yes/no}}` | Once per target season; weekly state update | `{{id}}` | `{{m0_id}}` | h1/h2 probabilities |
| IRVRI legacy daily GAM | Operational baseline | Daily by-age positives and tests | None; production settings | Refit at every origin on trailing 365 days | `{{id}}` | `none` | h1/h2 probabilities |
| Calendar-week GAM | Statistical comparator (secondary) | Calendar week and generic observed state | `{{yes/no}}` | Once per fold | `{{id}}` | `none` | h1/h2 probabilities |
| IRVRI mvgam (one specification) | Statistical time-series comparator | Weekly PAGe input | `{{yes/no}}` | Refit at every origin | `{{spec}}` | `none` | h1/h2 probabilities |
| Persistence | Baseline | Current observed positivity | None | Weekly | `fixed` | `none` | h1/h2 probabilities |
| Seasonal naive | Baseline | Historical target-week positivity | Prespecified smoothing only | Once per fold | `fixed` | `training seasons` | h1/h2 probabilities |

## Table 3. Stage-level outcomes

| Application | Pathogen | Season | M0 reference week | M0 detected week | Signed error | Absolute error | M0 status | M1 observed peak | M1 predicted peak | Peak error | Weighted peak error | Peak interval coverage | M1 status |
|---|---|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---|
| `{{application}}` | `{{pathogen}}` | `{{season}}` | `{{i_true}}` | `{{i_hat}}` | `{{error}}` | `{{abs_error}}` | `{{status}}` | `{{peak_true}}` | `{{peak_hat}}` | `{{error}}` | `{{weighted_error}}` | `{{coverage}}` | `{{status}}` |

Required summary rows: mean absolute ignition error, median absolute ignition
error, miss rate, mean and median weighted peak error, unweighted peak MAE,
and the number of eligible origins. Do not label operational reference labels
as biological truth.

## Table 4. Primary forecast comparison

The primary score is the phase-weighted Bernoulli cross-entropy
(Section 5.1 of the protocol), aggregated with equal weight per season.
Both horizons are scored. All summaries are descriptive. The table has two
blocks.

### Table 4a. Operational baseline (PAGe vs legacy daily GAM)

Chronological seasons only (`{{Tier 1 / Tier 1+2}}`), common rows.

| Application | Pathogen | Season | Tier | Origins | PAGe score | Legacy GAM score | Δ = PAGe − Legacy GAM | PAGe minus comparator direction | Weights version | Status | Kit identity |
|---|---|---|---:|---:|---:|---:|---:|---|---|---|---|
| `{{application}}` | `{{pathogen}}` | `{{season}}` | `{{tier}}` | `{{n_origins}}` | `{{L_page}}` | `{{L_legacy}}` | `{{delta}}` | `{{lower/higher/equal}}` | `{{weights_version}}` | `{{ok/fail}}` | `{{kit_id}}` |

### Table 4b. Workflow A (11-fold PAGe with paired contrasts)

Exchangeable-season LOSO; PAGe vs each comparator on identical rows.

| Application | Pathogen | Season | Holdout fold | Comparator | Origins | PAGe score | Comparator score | Δ = PAGe − Comparator | PAGe minus comparator direction | Weights version | Status | Kit identity |
|---|---|---|---|---|---:|---:|---:|---:|---|---|---|---|
| `{{application}}` | `{{pathogen}}` | `{{season}}` | `{{fold}}` | `{{comparator}}` | `{{n_origins}}` | `{{L_page}}` | `{{L_comparator}}` | `{{delta}}` | `{{lower/higher/equal}}` | `{{weights_version}}` | `{{ok/fail}}` | `{{kit_id}}` |

Comparators in Table 4b: calendar-week GAM, IRVRI mvgam one specification
(`{{spec}}`), persistence, seasonal naive.

Text template:

> Across the eligible seasonal replays, the equal-season mean difference in
> the phase-weighted Bernoulli cross-entropy (weights version
> `{{weights_version}}`) was **{{delta_mean}}** (median **{{delta_median}}**;
> observed range **{{min}}** to **{{max}}**). Negative values indicate lower
> observed cross-entropy for PAGe. The season-specific contrasts were
> **{{consistent/mixed}}**, with the largest positive contrast in
> **{{season}}**. These summaries are descriptive and do not constitute a
> statistical test.

The historical horizon-two, origins-ignition-to-+12, trial-weighted
comparison is retained only as the **registered v1.4 sensitivity line** on
new-cycle rows (Section 5.4 of the protocol); it is not the primary
comparison.

## Table 5. Descriptive primary summary and influence

| Application | Pathogen | Horizon | Comparator | Weights version | Seasons included | Equal-season mean Δ | Median Δ | SD | IQR | Minimum | Maximum | Leave-one-season-out range | Worst season | Summary status |
|---|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| `{{application}}` | `{{pathogen}}` | `{{h}}` | `{{comparator}}` | `{{weights_version}}` | `{{S}}` | `{{mean}}` | `{{median}}` | `{{sd}}` | `{{iqr}}` | `{{min}}` | `{{max}}` | `{{loo_min}} to {{loo_max}}` | `{{season}}` | `{{status}}` |

Allowed comparators: legacy daily GAM (Table 4a), calendar-week GAM, IRVRI
mvgam one specification (`{{spec}}`), persistence, seasonal naive (Table 4b).

Required interpretation fields: number and proportion of seasons favouring
PAGe, number of failures, whether the conclusion changes after leaving out
each season, and a plain-language description of between-season variation.

## Table 6. Secondary forecast metrics

| Application | Pathogen | Model | Horizon | Phase stratum | Origins | Trial-weighted NLL | Week-weighted NLL | Brier | RMSE | MAE | Calibration intercept | Calibration slope | Interval coverage | Interval score | Status |
|---|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `{{application}}` | `{{pathogen}}` | `{{model}}` | `{{h}}` | `{{phase}}` | `{{n}}` | `{{nll_trial}}` | `{{nll_week}}` | `{{brier}}` | `{{rmse}}` | `{{mae}}` | `{{intercept}}` | `{{slope}}` | `{{coverage}}` | `{{interval_score}}` | `{{status}}` |

Use `pre_ignition`, `rise`, `turning`, and `decline` as the standard phase
labels (protocol v2.0 Section 2 scoring weights; pre-ignition rows are
unscored). The phase strata are evaluation labels derived from final
observations and must never appear in origin-time feature construction.

## Table 7. Ablation and label-sensitivity results

| Application | Pathogen | Variant | Difference from full PAGe | Horizon | Equal-season mean NLL | Median NLL | Seasons favouring full PAGe | Worst season | Interpretation | Status |
|---|---|---|---:|---:|---:|---:|---:|---|---|---|
| `{{application}}` | `{{pathogen}}` | No ignition gate | `{{value}}` | 2 | `{{mean}}` | `{{median}}` | `{{n}}` | `{{season}}` | `{{text}}` | `{{status}}` |
| `{{application}}` | `{{pathogen}}` | No M1 alignment | `{{value}}` | 2 | `{{mean}}` | `{{median}}` | `{{n}}` | `{{season}}` | `{{text}}` | `{{status}}` |
| `{{application}}` | `{{pathogen}}` | No alignment uncertainty | `{{value}}` | 2 | `{{mean}}` | `{{median}}` | `{{n}}` | `{{season}}` | `{{text}}` | `{{status}}` |
| `{{application}}` | `{{pathogen}}` | No adaptive correction | `{{value}}` | 2 | `{{mean}}` | `{{median}}` | `{{n}}` | `{{season}}` | `{{text}}` | `{{status}}` |
| `{{application}}` | `{{pathogen}}` | Ignition labels −1 week | `{{value}}` | 2 | `{{mean}}` | `{{median}}` | `{{n}}` | `{{season}}` | `{{text}}` | `{{status}}` |
| `{{application}}` | `{{pathogen}}` | Ignition labels +1 week | `{{value}}` | 2 | `{{mean}}` | `{{median}}` | `{{n}}` | `{{season}}` | `{{text}}` | `{{status}}` |
| `{{application}}` | `{{pathogen}}` | Fold-specific M0 labels | `{{value}}` | 2 | `{{mean}}` | `{{median}}` | `{{n}}` | `{{season}}` | `{{text}}` | `{{status}}` |

## Table 8. Runtime and operational behavior

| Application | Pathogen | Fold/season | M0 training time | M1 training time | M2 training time | Total seasonal-kit time | Weekly M0 latency | Weekly M1 latency | Weekly M2 latency | Forecast availability | Model failures | Warnings | Runtime artifact |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `{{application}}` | `{{pathogen}}` | `{{season}}` | `{{time}}` | `{{time}}` | `{{time}}` | `{{time}}` | `{{time}}` | `{{time}}` | `{{time}}` | `{{percent}}` | `{{n}}` | `{{n}}` | `{{path}}` |

Report training time separately from weekly state-update and forecast latency.
Training is expected once per target season; repeated weekly model fitting is
not the canonical cadence.

## Table 9. Historical acceptance replay

This table is mandatory only if the historical acceptance artifact is retained.
It must not be merged into Table 4.

| Artifact lineage | Season | Candidate identity | Holdout status at time of decision | NLL gate | Horizon gate | Phase gate | Decision | Why separate from governed replay | Artifact checksum |
|---|---|---|---|---|---|---|---|---|---|
| Historical acceptance | 2025–26 | `{{candidate}}` | `{{status}}` | `{{pass/fail}}` | `{{pass/fail}}` | `{{pass/fail}}` | `{{decision}}` | Different lineage; previously examined | `{{sha256}}` |

Text template:

> The historical 2025–26 acceptance replay was retained as a separate lineage
> record. It was not used to tune the governed analysis reported in Table 4,
> and its operational gate was not treated as a scientific minimum-important
> difference.

## Table 10. Adoption-rule evidence

Per Workflow A fold. Inner gains are the gate season's phase-weighted M1-minus-M2
scores from fully nested inner tuning; the outer gain is the held-out fold's M1
minus M2 difference (the M2 shadow column when the gate keeps M1). Policy scores
are computed on identical rows.

| Application | Pathogen | Season | Inner gain overall | Inner gain h2 | Outer (shadow) gain | Gate decision | Always-M1 score | Always-M2 score | Gate policy score | Weights version | Status |
|---|---|---|---:|---:|---:|---|---:|---:|---:|---|---|
| `{{application}}` | `{{pathogen}}` | `{{season}}` | `{{inner_gain}}` | `{{inner_gain_h2}}` | `{{outer_gain}}` | `{{M1/M2}}` | `{{score_m1}}` | `{{score_m2}}` | `{{score_gate}}` | `{{weights_version}}` | `{{status}}` |

Required summary row: number of folds where always-M2 beats always-M1, number of
harmed seasons under the gate, and the selected hyperparameters and boundary
expansions per fold.

## Table 11. Deviations summary

One row per entry in the deviations register
(`drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md`). Placeholders only; the
register is the source of truth for dates, records, and reasons.

| ID | Change | Affects |
|---|---|---|
| `{{id}}` | `{{change}}` | `{{affects}}` |

Note: prior-cycle and new-cycle results are never pooled (register
"Consequences for reporting"); the registered v1.4 primary line is carried
forward only as a labelled sensitivity.

## Figure specifications

| Figure | Purpose | Required data fields | Required annotation | Artifact input |
|---|---|---|---|---|
| Figure 1 | M0→M1→M2 workflow and information boundary | Stage IDs, cadence, origin/target timing | One kit trained once; weekly state updates | `figure_01_workflow.csv` |
| Figure 2 | Representative phase/peak alignment | Observed partial curve, templates, aligned peak, spread | Origin cutoff and no-future-information boundary | `figure_02_alignment.csv` |
| Figure 3 | Outer-fold and weekly replay design | Training seasons, held-out season, origins, targets | Inner tuning before outer holdout evaluation | `figure_03_validation_timeline.csv` |
| Figure 4 | Primary season-specific contrast | Season, design block, comparator, PAGe score, comparator score, Δ, weights version | Equal-season summary and observed range | `figure_04_primary_contrast.csv` |
| Figure 5 | Simulation operating conditions | Scenario, metric, status | Conditional placement in main text | `figure_05_simulation.csv` |

## Canonical prediction-table schema

Every scored row should contain the following fields, even when a field is
`NA` or a failure code is present. The row keys are `season`,
`origin_week_start_date`, `origin_weekF`, `h`, `target_week_start_date`, and
`target_weekF`.

```text
analysis_id, application, pathogen,
season, origin_week_start_date, origin_weekF, h,
target_week_start_date, target_weekF,
training_seasons, y, N, observed_p, predicted_p,
interval_low, interval_high,
model_id, configuration_id, kit_identity, timing_mode, weights_version,
phase, gate_decision, is_shadow, forecast_available, unavailable_reason,
fit_status, exposed_season_flag, data_input, runtime,
m0_identity, m1_identity, m2_identity,
data_vintage, score_ce, score_brier, score_rmse, score_mae,
failure_code, warning_code, source_checksum
```

`data_input` is `weekly` or `daily`. Rows with `forecast_available = false`
carry an `unavailable_reason` code and are counted, never dropped.

## Final manuscript quality gate

- [ ] Methods matches the frozen protocol version and implemented package.
- [ ] Every included season and exclusion has a dated declaration.
- [ ] Pandemic seasons are explicitly identified and not silently treated as
  exchangeable.
- [ ] Every model and ablation has a frozen identity and tuning record.
- [ ] Full PAGe is distinguished from the no-M1 attribution diagnostic.
- [ ] Historical acceptance evidence is separated from governed replay.
- [ ] No p-values, t-tests, significance labels, or unsupported superiority
  claims appear.
- [ ] Every result row is traceable to the canonical prediction table.
- [ ] Runtime separates one-time seasonal training from weekly latency.
- [ ] Claims are limited to Ontario influenza; no RSV or other-pathogen results
  are reported.
- [ ] The exposed 2025-26 fold is labelled in every table.
- [ ] The registered v1.4 primary line is labelled as a sensitivity, not the
  primary result.
- [ ] Data availability, privacy, ethics, funding, conflicts, and AI-use
  statements are complete.
- [ ] Current journal requirements are rechecked immediately before submission.
