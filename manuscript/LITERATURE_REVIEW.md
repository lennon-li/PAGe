# Literature review: staged seasonal respiratory-virus forecasting

Last updated: 2026-09-01

## Review question

What mathematical, statistical, and machine-learning approaches provide fair context or comparators for a prospective workflow that produces three linked outputs:

1. **Ignition:** the start of sustained epidemic activity.
2. **Phase and peak:** an updated epidemic-time coordinate and peak-week estimate from the partial curve observed so far.
3. **Forecast:** probabilistic one- and two-week-ahead positivity forecasts.

The dependency between these outputs is central. M1 is not a retrospective curve-registration exercise: it consumes only the partial season available after M0 and passes phase, peak, and alignment uncertainty to M2. M2 must be evaluated using the same information that would have been available at each forecast origin.

## Search and review protocol

- **Search date:** 2026-09-01.
- **Design:** targeted narrative review with two independent, read-only agent searches followed by parent citation reconciliation. It is not a PRISMA systematic review and does not support prevalence statements about the literature.
- **Independent tracks:** Argie (Google Gemini 3.1 Pro High) emphasized mathematical/mechanistic and statistical models; Liz (OpenAI GPT-5.6 Luna, high reasoning) emphasized machine learning, probabilistic forecasting, and operational evaluation.
- **Sources searched:** scholarly web search, PubMed/PMC, publisher and DOI pages, PMLR, arXiv for a foundational registration preprint, and official CDC/forecast-hub material.
- **Query families:** combinations of influenza or RSV with forecasting, onset, ignition, peak timing, phase, curve alignment, registration, analogue, SIR/SIRS, ensemble Kalman filter, empirical Bayes, GAM, Gaussian process, random forest, boosting, LSTM, ensemble, calibration, proper score, rolling origin, and data revision.
- **Inclusion:** methods or operational systems that inform at least one PAGe stage, its uncertainty/evaluation, or a fair comparator; respiratory-virus applications were prioritized.
- **Exclusion:** purely descriptive seasonality studies without a forecast or detection method; models whose only evaluation used random weekly splits when that design could not inform prospective seasonal validation; and papers without a stable citation locator.
- **Citation control:** the reviewers reported 21 and 32 checked sources, respectively. Their union was deduplicated, key claims were checked again against primary or official pages, and 26 sources were retained in the consolidated matrix. One agent-supplied DOI for the 2013--14 CDC influenza challenge was corrected from `10.1186/s12879-016-1802-3` to `10.1186/s12879-016-1669-x`. Agent bibliographic details were treated as leads rather than accepted automatically.
- **Local-data boundary:** neither reviewer accessed private surveillance observations, result artifacts, `data/`, or `results/`, and neither changed repository files.

The detailed evidence matrix is in [`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md).

## Consolidated findings

### Mathematical and mechanistic models

Compartmental SIR/SIRS models coupled to ensemble or particle filters are the strongest mathematical comparators. They estimate latent epidemic state and generate distributions over future trajectories, peak timing, and peak intensity. Influenza and RSV studies demonstrate that this can support in-season forecasting, including onset and peak targets. Their strengths are epidemiological structure and coherent trajectory uncertainty. Their weaknesses for the present application are sensitivity to structural assumptions, latent-state initialization, reporting models, and the mapping from transmission state to test positivity.

Mechanistic systems often infer onset and peak from one fitted latent trajectory. PAGe instead makes ignition an explicit guarded decision and estimates a partial-curve phase coordinate before the short-horizon forecast. A mechanistic comparator is scientifically valuable, but it must receive only forecast-origin data and must use a denominator-aware observation model if it is scored against weekly positive and total test counts.

Empirical-Bayes and historical-analogue models are the closest nonmechanistic competitors. They deform or select historical epidemic curves to forecast the current curve and can produce onset, duration, peak, and weekly trajectory distributions. They overlap substantially with PAGe's historical-template logic. This means the paper must not claim that template matching, time deformation, or joint peak/trajectory forecasting is new. The defensible distinction is PAGe's explicit three-stage handoff, partial-curve multi-template alignment, propagation of alignment uncertainty, and governed prospective-information lifecycle.

### Statistical models

Threshold and onset-detection methods, including ALERT-like rules and weather-assisted RSV onset models, show that epidemic start can be operationalized separately. They are appropriate references and potential M0 sensitivity comparators, but they generally do not turn the detected start into a continuously updated phase coordinate for a downstream probabilistic model.

Functional-data registration provides the formal phase-versus-amplitude language underlying M1. Classical registration and Fisher--Rao methods align entire curves through monotone time warps. Their usual retrospective/full-curve setting differs from PAGe's constrained online problem, where only the partial current curve is visible. The paper should therefore claim a prospective partial-curve use and sequential integration, not invention of curve alignment.

Calendar-week GAMs, lagged penalized regressions, autoregressive models, and Gaussian processes are credible short-horizon comparators. The calendar GAM directly tests whether PAGe's epidemic-time representation improves on calendar time. A low-dimensional lagged penalized binomial model tests whether recent history alone explains any benefit. Gaussian processes offer flexible trajectory forecasts with uncertainty and are a useful higher-complexity statistical comparator if computational cost is acceptable.

### Machine-learning and ensemble models

Random forests or gradient boosting can represent nonlinear lag relationships, but the unit of independent information is the season, not the weekly row. With roughly a decade of Ontario seasons, a single strongly regularized tree model is a sufficient ML stress test. Hyperparameters and feature construction must be repeated inside each season-held-out training fold.

LSTM and related deep models have demonstrated short-term influenza forecasting in larger or richer data settings. They are poor primary comparators here because Ontario supplies few independent seasons, despite many correlated weekly rows. Transformers, temporal convolutional networks, and large neural architectures should not be primary manuscript baselines unless external pretraining and a leakage-safe transfer design are prespecified. Their omission should be justified by effective sample size and fairness, not by assuming that they cannot forecast respiratory viruses.

Operational ensembles often improve robustness, and adaptive weighting or recalibration can improve probabilistic performance. These studies support PAGe's emphasis on calibration and online correction, but an ensemble of many external models is not a like-for-like comparator for a single-data-source Ontario package. Recalibration must be estimated from prior seasons or prior forecast origins without using future outcomes.

## What appears novel—and what does not

The targeted review did **not identify** a prior respiratory-virus system that explicitly implements and validates this exact prospective chain:

`ignition decision -> partial-curve phase/peak state with uncertainty -> denominator-aware h1/h2 forecast`

under season-held-out, walk-forward information boundaries with frozen stage identities and artifact provenance. This is a bounded finding from a targeted review, not proof that no such method exists.

Potentially defensible PAGe contributions are:

- treating ignition, peak/phase estimation, and near-term forecasting as separate targets with explicit dependencies;
- using constrained partial-curve multi-template alignment as an operational epidemic-time coordinate;
- passing alignment uncertainty to the downstream forecast rather than treating alignment as fixed preprocessing;
- evaluating every stage and the complete chain under the same prospective information boundary; and
- providing a governed package lifecycle that binds tuning, frozen identities, replay, and promotion evidence.

Established elements that must not be claimed as novel include epidemic thresholding, compartmental filtering, historical analogues, time warping/functional registration, GAM forecasting, Gaussian-process forecasting, adaptive ensembles, proper scoring, and walk-forward evaluation.

Unsupported claims to avoid include universal superiority, cross-pathogen validity before the Ontario RSV analysis, actual prospective deployment, or proof that PAGe's decomposition is uniquely optimal.

## Recommended comparator and ablation protocol

### Core set to freeze for Ontario influenza and reuse for Ontario RSV

1. **Persistence:** last observed positivity, with a prespecified predictive distribution.
2. **Seasonal naive:** historical distribution for the corresponding calendar week.
3. **Calendar-week binomial GAM:** the primary comparator; no M0 or M1 inputs.
4. **Lagged penalized binomial regression:** low-dimensional autoregressive statistical baseline.
5. **Historical-analogue continuation:** nearest prior partial curves selected using forecast-origin information only.
6. **One regularized tree model:** choose either gradient boosting or random forest before results are generated.
7. **Full PAGe.**

Required PAGe ablations are:

- remove ignition gating;
- remove M1 and use calendar week in place of aligned week;
- retain alignment but remove `logit_spread` or other alignment-uncertainty inputs;
- remove adaptive bias correction; and
- perturb ignition labels and evaluate a version using all M0-generated labels.

This reorganizes the earlier seven-item list into seven standalone models plus explicit component ablations and adds three literature-supported model families: lagged penalized regression, historical analogues, and one regularized tree. The final count should be frozen in the analysis protocol after implementation feasibility is checked; it should not continue growing in response to results.

### High-value optional comparators

- **Gaussian-process epidemic forecast:** preferred optional statistical model because it provides probabilistic trajectories and addresses timing variation.
- **Empirical-Bayes full-curve model:** the closest conceptual competitor and therefore the highest-value optional addition if a faithful implementation can be completed.
- **SIR/SIRS plus ensemble filtering:** the strongest mathematical comparator, conditional on a fair binomial observation model and a time-boxed implementation.
- **Endemic--epidemic autoregression:** optional only if the target and data structure can be matched without converting the study into a spatial-count analysis.

### Models not recommended as primary comparators

- multiple nearly redundant tree models;
- LSTM, transformer, or other high-capacity neural models trained on Ontario weekly rows as if those rows were independent;
- a forecast-hub ensemble whose target is hospital admissions or emergency-department visits rather than test positivity; or
- a mechanistic model scored on a different surveillance target without an explicit observation bridge.

## Stage-specific evaluation implied by the review

| Stage | Output | Primary stage measure | Essential secondary checks |
|---|---|---|---|
| M0 | Ignition week or no ignition | Absolute ignition-week error and miss/false-alarm rate | Label perturbation, detection delay, boundary cases |
| M1 | Aligned epidemic week, peak week, alignment uncertainty | Peak-week absolute error | Phase error, coverage/calibration of peak uncertainty, template mismatch |
| M2 | h1/h2 predictive distribution for positivity/counts | Binomial NLL at prespecified horizon | MAE, calibration, horizon/phase strata, worst season |
| Full chain | All three outputs at each origin | Primary PAGe-versus-calendar-GAM contrast | Component ablations, season-level uncertainty, runtime/failure rate |

All model fitting, tuning, recalibration, analogue selection, and feature engineering must be confined to the training seasons of each replay. Weekly observations within a season must not be treated as independent resampling units. The canonical prediction table should contain every forecast origin and bind stage/model identities, targets, predictions, scores, and runtime provenance.

## Risks and limitations

- The number of independent Ontario seasons may make model rankings imprecise; season-level intervals and worst-season behavior are more informative than pooled weekly standard errors.
- Novel or multi-wave seasons may have no adequate historical template. Simulations must include template-incompatible epidemics.
- Ignition definitions can dominate downstream performance. Manual and M0-derived label sensitivity is mandatory.
- Test positivity depends on denominator volume and testing policy. Every comparator should preserve or explicitly model positive and total counts.
- Surveillance revisions can create apparent forecast skill if final revised values leak into historical origins. The protocol must reconstruct vintage data where possible and disclose the limitation otherwise.
- Influenza and RSV targets may share a schema but differ biologically and operationally. Models must be retrained separately, and scores must not be pooled without a justified weighting model.

## Decision and next action

The literature-synthesis task is complete. Before any headline comparison is run, the scientific lead must approve the core comparator set, decide whether the empirical-Bayes or mechanistic comparator is feasible, and freeze all implementations and ablations in the versioned analysis protocol. The manuscript should then present PAGe primarily as a staged, interpretable epidemic-state and forecasting workflow, with predictive improvement treated as an empirical question.
