# Methods

> **Status (2026-09-16): DRAFT, describes the new cycle** — converts [`ANALYSIS_PROTOCOL_v2.0-draft.md`](drafts/ANALYSIS_PROTOCOL_v2.0-draft.md) (not yet frozen) into journal prose; supersedes the prior-cycle Methods draft. See [`drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md`](drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md) for what changed and why. `[FREEZE: ...]` tags below are unresolved protocol items, not typos.

This document is the canonical manuscript-facing Methods draft. It converts the decisions in [`ANALYSIS_PROTOCOL_v2.0-draft.md`](drafts/ANALYSIS_PROTOCOL_v2.0-draft.md) and the implemented PAGe contracts into journal prose. Result-dependent values belong in [`REPORTING_TEMPLATES.md`](REPORTING_TEMPLATES.md) and must be populated from the immutable analysis manifest, not typed from memory.

## Study design and objective

We evaluated PAGe (Phase-Aligned Gated Epidemic forecasting), a staged workflow for weekly respiratory-virus surveillance. The workflow targets three linked but separately evaluated outputs: epidemic ignition, the phase and peak of the partially observed seasonal curve, and one- and two-week-ahead positivity forecasts. PAGe was designed for prospective deployment and evaluated here through two co-primary descriptive blocks: an exchangeable-season outer leave-one-season-out (LOSO) evaluation with within-season walk-forward replay (Workflow A), and a chronological evaluation against the operational baseline. Workflow A intentionally trained earlier holdouts with later calendar seasons to evaluate transfer across the declared season set, while the chronological tier restricted training to prior seasons to match operational information boundaries.

The frozen primary forecast estimands are the observed two-week-ahead and one-week-ahead probabilistic accuracy of the assembled PAGe workflow. These are compared descriptively against the IRVRI legacy daily GAM on the chronological seasons, and against a calendar-week binomial generalized additive model (GAM) and other weekly comparators in the exchangeable-season design. We did not perform hypothesis tests, calculate p-values, or make a statistical-significance claim. Stage-level results, horizon one, phase strata, component ablations, label sensitivities, calibration, adoption-rule evidence, and runtime were secondary reporting targets.

## Surveillance data and data contract

For pathogen $v$, season $s$, and within-season week $t$, the input data contained $y_{vst}$ positive tests and $N_{vst}$ total tests. Weekly positivity was defined as

$$
p_{vst}=y_{vst}/N_{vst},
$$

when $N_{vst}>0$; weeks with zero total tests had missing positivity and were not scored. The canonical PAGe data frame contained `season`, `weekF`, `y`, `N`, `neg`, and `p`, where `neg = N - y`. The adapter also preserved unmapped source metadata, such as dates, jurisdiction, source identifiers, and data vintage.

Source-specific weekly data were converted through `prepare_page_data()` by explicitly naming the positive-count, total-count or negative-count, season, week, and optional season-start-year columns. The adapter did not fetch or aggregate observations. Inputs were required to contain exactly one row per season and week after any source-authorized aggregation. For calendar/MMWR weeks, `weekF` was computed from the declared season origin (`start_week = 27L` by default) and the number of weeks in the season derived from the MMWR calendar of the season start year, never from observed coverage, allowing 52- and 53-week seasons. Counts were required to be finite, non-negative whole numbers, with positive counts no greater than total counts. Duplicate keys, inconsistent redundant counts, impossible positivity values, and malformed season identifiers caused validation failure.

### Temporal resolution and legacy implementation

The primary application was Ontario influenza using the season universe fixed in the versioned Ontario season declaration. The evaluated PAGe pipeline used one observation per season-week. The calendar-GAM comparator used for the current comparison was constructed from the same weekly surveillance counts, with one- and two-week-ahead targets. 

The IRVRI legacy daily GAM comparator, however, was fitted using daily by-age influenza positive and testing counts. This model refitted a single daily series on the trailing 365 days of data at every origin, matching its operational deployment configuration. While daily observations provide finer resolution for within-week onset and reporting cycles, they are not directly comparable to the weekly estimand without explicit aggregation. A daily model must respect the observation-availability cutoff, model serial dependence, and aggregate daily predictions to the weekly target using target test volumes before comparison. The chronological tier evaluation compared these approaches while acknowledging the information set asymmetries. 

## Forecast targets and information boundary

The forecast origin was week $t$, and the target for horizon $h$ was the positive count and denominator at week $t+h$, with $h\in\{1,2\}$. At each origin, all predictors, transformations, alignment states, and correction states were constructed from information available no later than week $t$ using a strict walk-forward prefix rule enforced before aggregation. Final revised observations could define retrospective scoring targets, but they could not enter origin-time predictors. When origin-time data vintages could not be reconstructed, the analysis was labelled a final-data retrospective replay rather than actual prospective deployment.

Ignition and observed peak week were defined by the timing-v2 retrospective reference labels, each provided as a one-week interval. These are operational references, not independently validated biological ground truth. When a season is held out, its label is excluded from training and joined only after replay for scoring.

## PAGe workflow

PAGe was implemented as the ordered chain M0 $\rightarrow$ M1 $\rightarrow$ M2. The three stages were governed by explicit fit, validation, freeze, identity, and assembly contracts. A downstream stage could not be frozen or assembled with a missing or mismatched upstream identity.

### M0: prospective ignition detection

M0 detected the transition into the epidemic phase using a fractional timing mode. Its detector combined signals over an eligible within-season window and emitted a decimal ignition estimate with its one-week bracket. The training targets were positioned at label + 0.5. The detector's threshold and window parameters were tuned by inner LOSO to minimize a loss function defined as the symmetric absolute error on the fractional target plus a late-detection penalty `[FREEZE: penalty]`.

Misses were retained as missing with `detection_failed` accounting and were scored in tuning at the legacy `w_max` error, ensuring a miss never beat a late detection. The population-level classifier gate was disabled by default (`use_cls = FALSE`). During replay, M0 was applied repeatedly to the as-of data through the current week. Once the detector locked an ignition week, that value was used by downstream weekly processing.

### M1: partial-curve phase and peak alignment

M1 represented the observed partial curve in an epidemic-phase coordinate. A reference curve was estimated from eligible training seasons after M0-derived alignment and expressed on the logit scale. For each candidate historical template $g_j$, the observed curve was aligned using a fractional shift $\tau$, optional scale parameters $(a,b)$, and a dilation $\delta$:

$$
u_{stj}=\frac{t_{st}-\tau_{sj}}{1+\delta_{sj}},
\qquad
\operatorname{logit}(p_{st})\approx a_{sj}+b_{sj}g_j(u_{stj}).
$$

The alignment coordinate was a plain shift $\text{newWeek} = \text{weekF} - \text{iWeek} + \text{anchor}$ with no modulo wrapping or clamping. Shifted rows outside the template domain (1-52) were excluded from template fitting and online alignment support. Alignment was estimated using a denominator-aware binomial objective. The resulting templates were combined with a softmax ensemble based on alignment loss and a recent growth-rate similarity term. The ensemble produced a phase-aligned positivity trajectory and a peak estimate. Identical preprocessing was used in tuning and fitting.

M1 also produced `logit_spread`, the weighted standard deviation of template predictions on the logit scale. This quantity represented disagreement among alignment templates; it was an uncertainty covariate for M2 and was not interpreted as the complete predictive interval. For the primary analysis, M1 hyperparameters were fixed at `k_ref = 30` and `slope_weight = 16` and were not tuned in this cycle.

### M2: probabilistic positivity forecasting

M2 modelled the future positive and negative counts with a binomial GAM. The training response for horizon $h$ was

$$
(y_{s,t+h}, N_{s,t+h}-y_{s,t+h}),
$$

stacked across horizons and eligible seasons. The governed family `offset_subset_v1` applied terms to the M1 logit offset, structured schematically as:

$$
\begin{aligned}
\operatorname{logit}(p_{s,t+h}) ={}& \alpha_h+b_s
 + f_{h}(\operatorname{logit} f^{\mathrm{eff}}_{s,t+h})
 + q_h(\operatorname{newWeek}_{s,t+h})\\
 &+ e_h(z_{s,t})+r_h(z_{s,t}-\operatorname{logit}f^{\mathrm{eff}}_{s,t+h})
 + v_h(\log N_{s,t})\\
 &+ d_h(\Delta z_{s,t})+u_h(\operatorname{logit\_spread}_{s,t}).
\end{aligned}
$$

Optional peak-relative terms (time since M1 peak estimate, peak-passed indicator) were configured `[FREEZE: included or not]`. The frozen GAM forecast was optionally adjusted on the logit scale using an online bias corrector included as a grid value (`bias_alpha` in `[FREEZE]`, trigger 2 same-sign weeks, logit cap `[FREEZE]`). The correction state was updated recursively using the stored state from earlier forecast residuals, using only observations available by the current origin. 

Before peak substitution, M2 bounds were constructed from `eta +/- 1.96 * se.fit` and transformed to the probability scale. These are conditional fitted-mean bands, not a full predictive distribution, and do not fully propagate observation variation or uncertainty.

## Seasonal training cadence

For each target season, the complete training workflow was run once. The workflow selected training seasons, tuned M0, validated and froze M0, estimated M1 using the matching frozen M0, and tuned, fitted, and froze M2 using the matching M0/M1 identity chain. The result was one immutable seasonal kit. The same kit was reused for all weekly origins in the target season. Weekly M0 detection, M1 alignment, M2 prediction, and online residual correction were state updates rather than retraining. 

## Validation and replay design

We used a three-level nested seasonal walk-forward design. The unit of separation was the influenza season, and the information boundary was also enforced within each season: a forecast made at origin week $t$ could use only observations available through week $t$.

### Level 1: candidate fitting within an outer fold

Within a given outer fold, one of the 10 outer-training seasons was designated the inner gate season $s$. A candidate stage specification was fitted using the remaining seasons and replayed week by week on $s$. This level answered the local fitting question: when a candidate is learned without $s$, how well does it transfer to $s$ without using $s$'s future observations? It produced the season-specific walk-forward losses needed for tuning and revealed candidate failures, unstable fits, and boundary-winning hyperparameters.

### Level 2: fully nested inner gate and hyperparameter selection

The package enforced a fully nested inner gate (`gate_nesting = "full"`), correcting a leakage limitation of the prior cycle in which M2 tuning reused upstream M0/M1 hyperparameters selected on the outer training set rather than reselecting them inside every inner fold. For each inner gate season $s$, every tuned upstream axis (M0; M1 is fixed this cycle) and the full M2 selection were re-run on the data excluding $s$. Furthermore, rows of $s$ used M1 fitted without $s$, and training rows of every other season $r$ used M1 fitted without both $r$ and $s$. Nothing fitted or selected on $s$ entered the correction evaluated on $s$.

Each candidate stage specification's phase-weighted scores across the 10 inner holdouts were averaged with equal season weight and used to select hyperparameters, expand grids when a non-null winning value lay on a searchable boundary, and apply the prespecified M2-versus-M1 adoption gate (below). After all choices were fixed, the selected M0/M1/M2 procedure was fitted to all 10 outer-training seasons to create one frozen kit for the outer holdout. This level answered the model-selection question: which configuration should be deployed to the outer-held-out season, and is the estimated gain from M2 large and consistent enough to justify using it instead of M1? No score from the outer-held-out season entered these choices.

### Level 3 / Workflow A: exchangeable outer evaluation

Each of the 11 seasons was held out once, in turn; the recipe above ran on the other 10, and the held-out season was replayed walk-forward with the resulting frozen kit. When the adoption gate selected M1, the tuned M2 was also replayed as a shadow column that never altered the fold's decision or reported forecast, allowing evaluation of M2's counterfactual performance in every fold, not only where it was adopted. All 11 principal seasons were complete (including the complete 53-week 2025-26 season).

This level answered the generalization question: how does the complete training, tuning, boundary-expansion, and M2-adoption procedure perform when transferred to an unseen season? The 11 outer replays yielded paired season-specific metrics for M1, M2, and the shadow column, whose equal-season aggregate quantified average gain, the frequency and magnitude of improvement or harm, horizon- and phase-specific performance, and whether the minimum-gain fallback protected against harmful M2 deployments. The 11 fitted kits were validation artifacts, not an ensemble for deployment. After the analysis procedure was fixed, one final kit (Workflow B) was fitted using all 11 seasons for deployment to 2026-27 (see Real-time application, below).

### Chronological evaluation (Tier 1 and Tier 2)

The IRVRI legacy GAM cannot use exchangeable future seasons as it is refitted on the trailing 365 days. It was compared only on seasons where PAGe was also trained exclusively on earlier seasons. This applied to Tier 1 (`2025-26`) and Tier 2 (`2022-23`, `2023-24`, `2024-25`), each using an additional PAGe kit trained on an expanding window of all earlier principal seasons. 

### Adoption gate and scoring weights

Scoring weights for M2 tuning, the adoption gate, and primary scoring were determined by the observed peak phase: pre-ignition received a weight of 0; the rise phase (ignition to peak-2) a weight of 2; the turning window (peak-1 to peak+3) a weight of 3; and the decline phase (after peak+3) a weight of 1.

M2 was adopted only if the mean phase-weighted gain (M1 score minus M2 score) was at least $\max(\text{floor}, t_{0.95, n - 1} \times \text{SD} / \sqrt{n})$, overall (floor $0.0012$) and for each horizon (h2 floor $0.002$; h1 floor `[FREEZE: min_gain_by_horizon for h1]`), and no season degraded (`max_season_degradation = 0`). Otherwise, forecasts equalled M1. The 0.95 bound was a decision threshold only and is not reported as inference `[FREEZE: confirm]`.

## Real-time application, 2026-27

Distinct from the retrospective validation designs, the manuscript reports a real-time prospective block for the 2026-27 season. Here, training and evaluation were separated in time rather than by an outer holdout: the final operational kit (Workflow B) was trained once on all 11 eligible seasons and frozen before the season started. This block has no counterfactual (the model was live, not held out) and is reported as operational evidence, not as validation. 

Every weekly forecast was written to an append-only log with forecast timestamp, data-vintage timestamp, input checksum, and kit identity before the target week's data existed. The real-time block reports the season up to the latest data available at submission, stating the analysis date, and transparently retaining operational outcomes such as missed weeks, pipeline errors, and late data.

## Comparators and ablations

The prespecified core comparison contained the operational baseline IRVRI legacy daily GAM, a calendar-week binomial GAM, one specification from the IRVRI `mvgam` model family (`mod2AR`, a Bayesian multivariate autoregressive GAM), persistence, a FluSight-style baseline, a seasonal naive forecast, M1 only, and full PAGe.

The IRVRI legacy daily GAM was fitted on daily by-age surveillance data, refitted at every origin on the trailing 365 days, using 14-day knots, summer thinning, and three strata. 

The IRVRI mvgam `mod2AR` comparator was restricted to the four chronological seasons with prior-only training history. Chain length and warmup were fixed `[FREEZE: chains, warmup, samples]` after a pilot on a non-scored season `[FREEZE: pilot season]`. Fits were required to pass a diagnostics gate (R-hat < 1.01, effective sample size $\ge$ `[FREEZE: ESS threshold]`), with one prespecified longer rerun `[FREEZE: fallback lengths]` on failure; recurring failures were recorded as unavailable.

Four structural ablations were examined: no M1 alignment in Workflow A, and (in simulation only) no ignition gate and no alignment uncertainty. A prespecified sensitivity recipe for M1 (`k_ref = 20`, `slope_weight = 12`) was run separately on the four chronological seasons (2022-23 to 2025-26) and reported in the supplement.

## Outcomes and descriptive scoring

For model $m$ and season $s$, the primary score was the phase-weighted weekly Bernoulli cross-entropy. Let $q_{s,t}=y_{s,t+h}/N_{s,t+h}$ denote observed positivity and $w_{s,t}$ denote the phase weights defined above. Then

$$
L_{s,m}=\frac{\sum_{t\in\mathcal W_s}w_{s,t}\left[-q_{s,t}\log(\hat p_{s,t+h,m}) -(1-q_{s,t})\log(1-\hat p_{s,t+h,m})\right]} {\sum_{t\in\mathcal W_s}w_{s,t}}.
$$

Predictions were clipped to `[1e-12, 1 - 1e-12]`. The per-season score was the weighted mean over available forecast weeks, averaged equally across seasons. 

Two co-primary descriptive blocks are reported: 
1. **Operational baseline:** The season-equal mean of $L(\text{PAGe}) - L(\text{legacy GAM})$ on the four chronological seasons, with every season's value shown.
2. **Recipe performance:** Workflow A season-equal PAGe score across 11 folds, with paired contrasts against the calendar GAM, persistence, seasonal naive, FluSight-style baseline, and M1 only.

### Probabilistic scores and adoption-rule evidence

Secondary probabilistic summaries included the weighted interval score (WIS) on the positivity scale, and empirical coverage of the central 50% and 95% intervals. For PAGe, M1, the calendar GAM, and seasonal naive, the predictive distribution was $\operatorname{Binomial}(N_{\text{target}}, \hat{p}) / N_{\text{target}}$ conditional on the realized target test count, which ignores parameter uncertainty and is labelled as such. The legacy GAM and mvgam used their posterior predictive draws.

To assess the gate's season-by-season choice against track-record consistency, adoption-rule evidence reported inner-versus-outer gain, and the always-M1, always-M2, and gate-selected policy scores per fold.

Secondary strata were early (`t_since = 0-3`) versus established (`4-12`) weeks post-ignition, and pre-peak versus post-peak, using final-data peak labels only to define evaluation strata, never as forecast inputs. A test-count-weighted phase score, formed by multiplying each phase weight by the number of target tests, was reported as a sensitivity analysis; test count was not part of the primary weighting rule.

Stage-level results were reported alongside the forecast comparison. M0 was summarized by absolute and signed ignition-week error on the fractional target, miss rate, and false-alarm or detection-delay measures. M1 was summarized by season-equal, within-season-normalized weighted peak-week MAE, with weights $\exp[-(0.1d)^2]$ where $d$ is weeks before the observed peak; unweighted MAE and peak-interval coverage were secondary.

All models in a contrast were scored on identical rows. An unavailable forecast was kept with reason codes, never imputed. A season without a valid paired score was retained as a pipeline failure, shown in every table, and excluded from the mean with the count stated.

## Missing observations, revisions, and privacy

No outcome was imputed for scoring. Any feature-state treatment for a missing lag was fixed or learned within the outer training fold and was accompanied by an audit flag. Duplicate season-week observations were resolved before the adapter using a documented source aggregation. When reconstructible, analyses used origin-time data vintages; otherwise a common final-data snapshot was used and the retrospective limitation was disclosed. Missing rows, unavailable forecasts, warnings, and failures remained in the canonical audit table.

Private surveillance observations were not committed to the public repository. Public replication materials consisted of the PAGe package, synthetic data, simulation code, analysis code, and disclosure-safe aggregate outputs. Any Ontario data release or aggregate display remained subject to the data custodian's authorization, access terms, and applicable ethics determination.

## Software and reproducibility

The analysis was implemented in R using PAGe. The final analysis manifest must record the package version, Git commit, dependency lock, R and operating-system versions, random seeds, source/data-vintage metadata, protocol checksum, stage and kit identities, file checksums, runtime, and code used to create every table and figure. A shared commit alone does not identify the complete executed workflow; final tables and figures must be generated from one canonical prediction table under a single analysis ID.

All validation runs used the `page_compute_options()` preset `"exact"`; its result-identical options (fold-level caching, zero-weight prediction skipping) were validated by equivalence test, while the `"fast"` preset (racing, `bam(discrete = TRUE)`) is documented as a package feature only and carries no validation evidence of its own. Runs could span Asgard and BCC local hosts only after a recorded cross-host equivalence check `[FREEZE: hosts and equivalence evidence]`; SciNet (Trillium) was used for weekly-data runs only, never for the daily legacy-GAM input.