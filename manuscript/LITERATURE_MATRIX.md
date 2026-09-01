# PAGe literature evidence matrix

Last updated: 2026-09-01

Legend: **I** = ignition/onset; **P** = peak timing or intensity; **F** = short-horizon or trajectory forecast. “Prospective” means forecasts were produced operationally or with a forecast-origin information boundary reported by the source; it does not imply PAGe-equivalent artifact governance.

| Source | Family and setting | Targets | Uncertainty/evaluation | Relevance to PAGe |
|---|---|---|---|---|
| [Shaman & Karspeck, *Forecasting seasonal outbreaks of influenza* (2012)](https://doi.org/10.1073/pnas.1208772109) | SIRS + ensemble adjustment Kalman filter; US influenza | P, F | Ensemble forecast; retrospective seasonal forecasts | Core mechanistic comparator; latent trajectory supplies peak and future path. |
| [Brooks et al., *Flexible Modeling of Epidemics with an Empirical Bayes Framework* (2015)](https://doi.org/10.1371/journal.pcbi.1004382) | Semiparametric empirical Bayes; US ILI | I, P, F | Full posterior epidemic curves; historical CV and prospective 2013--14 forecasts | Closest conceptual competitor: deformed historical curves jointly predict onset, duration, peak, and trajectory. |
| [Yang et al., *Forecasting Influenza Epidemics in Hong Kong* (2015)](https://doi.org/10.1371/journal.pcbi.1004383) | SIR + ensemble/particle filtering; subtropical influenza | P, F | Ensemble uncertainty; retrospective forecasts of 44 strain epidemics | Shows mechanistic filters can handle irregular timing and peak targets. |
| [Reis & Shaman, *Retrospective Parameter Estimation and Forecast of RSV in the United States* (2016)](https://doi.org/10.1371/journal.pcbi.1005133) | SIR + EAKF; regional RSV test data | I, P, F | Ensemble forecasts; ten years of retrospective epidemics | Direct Ontario RSV context and high-value mechanistic comparator. |
| [Reis et al., *Superensemble forecast of RSV outbreaks* (2019)](https://doi.org/10.1016/j.epidem.2018.07.001) | Bayesian model-averaged mechanistic/statistical systems; US RSV | I, P, F | Probabilistic superensemble; retrospective national/regional/state evaluation | Demonstrates one system can forecast onset, peak, and epidemic path, but not PAGe's explicit staged handoff. |
| [Viboud et al., *Prediction of the Spread of Influenza Epidemics by the Method of Analogues* (2003)](https://doi.org/10.1093/aje/kwg239) | Historical vector matching; France influenza | P, F | Retrospective analogue forecasts | Foundational direct comparator for partial-curve historical matching. |
| [Biggerstaff et al., *Results from the CDC Predict the 2013--2014 Influenza Season Challenge* (2016)](https://doi.org/10.1186/s12879-016-1669-x) | Multi-model challenge; US ILI | I, P, F | Weekly probabilistic forecasts and log-score evaluation | Establishes onset, peak, and short-term targets as operationally meaningful. |
| [Reich et al., *A collaborative multiyear, multimodel assessment of seasonal influenza forecasting* (2019)](https://doi.org/10.1073/pnas.1812594116) | Mechanistic/statistical/ML multi-model comparison; US influenza | I, P, F | Real-time forecasts, historical baseline, probabilistic scoring | Supports standardized baselines, ensembles, and multiseason evaluation. |
| [Birrell et al., *Forecasting the 2017/2018 seasonal influenza epidemic in England using multiple dynamic transmission models* (2020)](https://doi.org/10.1186/s12889-020-8455-9) | Dynamic transmission and synthesis models; England influenza | P, F | Credible intervals; real-time weekly exercise | Shows early-season uncertainty and the value of multiple surveillance/structural views. |
| [Zimmer & Yaesoubi, *Influenza Forecasting Framework based on Gaussian Processes* (2020)](https://proceedings.mlr.press/v119/zimmer20a.html) | Gaussian process; US ILI | P, F | Probabilistic forecasts; retrospective seven-season comparison | Preferred optional flexible statistical comparator with uncertainty. |
| [Amendolara et al., *LSTM-based recurrent neural network provides effective short term flu forecasting* (2023)](https://doi.org/10.1186/s12889-023-16720-6) | LSTM with surveillance/climate/population data; US influenza | F | Held-out forecasting and point-error metrics | Demonstrates ML relevance but also motivates effective-season sample-size caution. |
| [Tsang et al., *An adaptive weight ensemble approach to forecast influenza activity in an irregular seasonality context* (2024)](https://doi.org/10.1038/s41467-024-52504-1) | Statistical/ML/DL adaptive ensemble; Hong Kong influenza | P, F | 0--8-week forecasts; RMSE and WIS; post-COVID test period | Supports phase-stratified evaluation, adaptive combination, and uncertainty scoring. |
| [McAndrew & Reich, *Adaptively stacking ensembles for influenza forecasting* (2021)](https://doi.org/10.1002/sim.9219) | Dynamic stacking; US influenza | I, P, F | Probabilistic ensemble with week-updated weights | Relevant to online adaptation and revision-aware implementation. |
| [Rumack et al., *Recalibrating probabilistic forecasts of epidemics* (2022)](https://doi.org/10.1371/journal.pcbi.1010771) | PIT-based recalibration; FluSight forecasts | I, P, F | Proper scores and calibration using prior forecast errors | Supports prespecified, training-only recalibration checks for M2. |
| [Reich et al., *Triggering Interventions for Influenza: The ALERT Algorithm* (2015)](https://doi.org/10.1093/cid/ciu749) | Threshold-based outbreak trigger; hospital influenza | I | Retrospective threshold assessment | Direct M0 context; operational onset trigger without downstream phase alignment. |
| [Walton et al., *Predicting the start week of RSV outbreaks using real time weather variables* (2010)](https://doi.org/10.1186/1472-6947-10-68) | Regression/weather onset model; RSV | I | Historical validation of start-week prediction | RSV-specific ignition comparator or sensitivity reference. |
| [Ramsay & Li, *Curve registration* (1998)](https://doi.org/10.1111/1467-9868.00129) | Functional-data monotone time warping | P/phase | Methodological examples; not an epidemic forecast | Establishes registration and phase/amplitude separation as prior art. |
| [Wang et al., *Functional Data Analysis* (2016)](https://doi.org/10.1146/annurev-statistics-041715-033624) | Review of functional-data methods | P/phase | Methodological review | Provides terminology and assumptions for M1; alignment itself is not novel. |
| [Srivastava et al., *Registration of Functional Data Using Fisher--Rao Metric* (2011)](https://arxiv.org/abs/1103.3817) | Geometric phase/amplitude registration | P/phase | Simulations and non-epidemic applications; preprint locator | Alternative alignment formalism and a sensitivity-analysis direction. |
| [Gneiting & Raftery, *Strictly Proper Scoring Rules, Prediction, and Estimation* (2007)](https://doi.org/10.1198/016214506000001437) | Probabilistic forecast evaluation | All probabilistic targets | Theory of log, quadratic, CRPS, and interval scores | Grounds NLL/proper-score selection and honest uncertainty evaluation. |
| [Bracher et al., *Evaluating epidemic forecasts in an interval format* (2021)](https://doi.org/10.1371/journal.pcbi.1008618) | Epidemic forecast evaluation | F | Weighted interval score, sharpness, and coverage | Supports secondary WIS when forecasts are represented by quantiles/intervals. |
| [Reich et al., *The Zoltar forecast archive* (2021)](https://doi.org/10.1038/s41597-021-00839-5) | Forecast data standardization and provenance | I, P, F | Standard formats, storage, scoring, retrieval | Supports immutable canonical prediction tables and machine-readable provenance. |
| [Lazer et al., *The Parable of Google Flu: Traps in Big Data Analysis* (2014)](https://doi.org/10.1126/science.1248506) | Digital epidemiology critique | F | Analysis of drift and algorithm/data failures | Supports revision, drift, and surveillance-process safeguards. |
| [CDC FluSight](https://www.cdc.gov/flu-forecasting/) | Official operational influenza forecasting | F; historically I/P targets | Multi-model probabilistic forecasts, baselines, ensembles | Operational standard; current hospitalization targets differ from Ontario positivity. |
| [CDC RSV Ensemble Forecasts](https://www.cdc.gov/cfa-modeling-and-forecasting/rsv-data-vis/index.html) | Official RSV forecast hub/ensemble | F | Quantile intervals for near-term ED visits and admissions | Current RSV operational context; target mismatch precludes direct score comparison. |
| [Gneiting et al., *Probabilistic Forecasts, Calibration and Sharpness* (2007)](https://doi.org/10.1111/j.1467-9868.2007.00587.x) | Probabilistic forecast diagnostics | All probabilistic targets | Calibration, sharpness, prequential evaluation | Supports reporting calibration together with proper scores. |

## Comparator mapping

| PAGe question | Strongest literature-supported test |
|---|---|
| Is ignition gating useful? | No-gate ablation; ALERT-like threshold sensitivity; label perturbation. |
| Is aligned epidemic time better than calendar time? | Calendar-week binomial GAM; lagged penalized model; no-M1 ablation. |
| Is historical template matching itself enough? | Prospective historical-analogue continuation and, if feasible, empirical-Bayes full-curve model. |
| Does alignment uncertainty matter? | Remove `logit_spread`/alignment uncertainty while retaining the aligned phase. |
| Does PAGe beat a flexible probabilistic model? | Gaussian-process comparator. |
| Does a nonlinear ML learner explain the gain? | One nested-tuned regularized RF or gradient-boosting model. |
| Is epidemiological structure needed? | Optional SIR/SIRS + ensemble-filter comparator with a binomial observation bridge. |
| Is online correction responsible for gains? | Remove adaptive bias correction; assess training-only recalibration separately. |

## Evidence status

All entries have a DOI or stable primary/official locator. The matrix records methodological relevance, not a claim that each paper used PAGe-equivalent targets, positivity denominators, or leakage controls. Exact comparator specifications remain to be frozen in the manuscript analysis protocol.
