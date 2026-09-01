# Structural scan of comparable *Epidemics* articles

Last updated: 2026-09-01

## Purpose and limits

This targeted scan supports the structure of the PAGe manuscript. It is not a
systematic review and does not replace the scientific synthesis in
[`LITERATURE_REVIEW.md`](LITERATURE_REVIEW.md) or the source matrix in
[`LITERATURE_MATRIX.md`](LITERATURE_MATRIX.md).

Argie screened eight *Epidemics* articles spanning mechanistic, statistical,
machine-learning, ensemble, probabilistic, and operational forecasting. The
parent review then verified every title, year, DOI, and journal record against
official ScienceDirect pages. Seven records were inspected through official
metadata, abstracts, highlights, and indexed article text; the 2020 reporting
review was also checked through its open full text. Consequently, detailed
claims about universal section order are not warranted. The patterns below are
design guidance, not journal rules.

None of the eight records is a dedicated software or package article. The scan
therefore does not establish the appropriate placement or length of PAGe's
software section; that remains a manuscript design decision.

## Verified article set

| Article | Year | DOI and official record | Relevance to PAGe | Evidence depth |
|---|---:|---|---|---|
| *Enhancing Influenza-Like Illness forecasting: An ensemble approach combining mathematical and deep learning models amidst the COVID-19 pandemic* | 2026 | [10.1016/j.epidem.2026.100901](https://doi.org/10.1016/j.epidem.2026.100901) | Hybrid mechanistic/ML forecasts, uncertainty, age-stratified evaluation | Official open-access record, highlights, structured abstract, availability statement |
| *Forecasting seasonal influenza epidemics with physics-informed neural networks* | 2026 | [10.1016/j.epidem.2026.100919](https://doi.org/10.1016/j.epidem.2026.100919) | Seasonal influenza, mechanistic/ML hybrid, trained-once design, probabilistic forecasts | Official open-access record, highlights, abstract, availability statement |
| *An optimized geo-hierarchical ensemble model to forecast hospitalizations from respiratory viruses in the United States* | 2025 | [10.1016/j.epidem.2025.100869](https://doi.org/10.1016/j.epidem.2025.100869) | Multi-pathogen respiratory-virus forecasting, ensembles, historical evaluation | Official open-access record, highlights, abstract, availability statement |
| *Random Forest of epidemiological models for Influenza forecasting* | 2025 | [10.1016/j.epidem.2025.100862](https://doi.org/10.1016/j.epidem.2025.100862) | Mechanistic predictors combined by ML, rolling evaluation, real-time versus retrospective evidence | Official open-access article text and section indexing |
| *Does spatial information improve forecasting of influenza-like illness?* | 2025 | [10.1016/j.epidem.2025.100820](https://doi.org/10.1016/j.epidem.2025.100820) | Statistical baselines, point and probabilistic evaluation, within- and between-season heterogeneity | Official open-access record, highlights, abstract |
| *Identification and evaluation of epidemic prediction and forecasting reporting guidelines: A systematic review and a call for action* | 2020 | [10.1016/j.epidem.2020.100400](https://doi.org/10.1016/j.epidem.2020.100400) | Forecast-reporting transparency and operational interpretation | Official open-access record and PMC full text |
| *Real-time forecasting of epidemic trajectories using computational dynamic ensembles* | 2020 (online 2019) | [10.1016/j.epidem.2019.100379](https://doi.org/10.1016/j.epidem.2019.100379) | Sequential forecasting, dynamic ensembles, horizons and uncertainty | Official open-access record, highlights, abstract, indexed article text |
| *Complementing the power of deep learning with statistical model fusion: Probabilistic forecasting of influenza in Dallas County, Texas, USA* | 2019 | [10.1016/j.epidem.2019.05.004](https://doi.org/10.1016/j.epidem.2019.05.004) | One- and two-week influenza forecasts, statistical/ML comparison, probabilistic fusion | Official open-access record, highlights, abstract |

## Structural patterns retained for PAGe

1. **A method-forward structure is normal.** Comparable papers use an
   Introduction followed by substantial model, training, data, and evaluation
   sections. They do not all use identical top-level headings.
2. **The information boundary belongs in Methods.** Rolling or sequential
   forecast papers explain what is available at each origin, how models are
   trained, and how retrospective evaluation emulates deployment.
3. **Hybrid methods are decomposed before they are evaluated.** Mechanistic,
   statistical, and ML components are defined separately, then integration and
   training cadence are described explicitly.
4. **Results follow the scientific targets.** Horizon, epidemic phase, peak or
   trajectory target, prospective/retrospective status, and season-specific
   heterogeneity are more informative organizers than algorithm internals.
5. **Comparators and uncertainty are central.** The closest articles report
   conventional statistical or challenge baselines and use horizon-specific
   error or proper probabilistic scores.
6. **Operational evidence is separated from retrospective evidence.** Real-time
   deployment, rolling replay, and retrospective model revision must not be
   conflated.
7. **Display economy is a PAGe planning choice.** The scan supports common
   display roles such as workflows, trajectories, and performance comparisons,
   but it did not count every article's figures and tables. The one-argument-
   per-display rule and the four-figure/three-table target come from independent
   review, not from a measured journal requirement.
8. **Reproducibility is visible.** Recent articles expose data/code availability,
   implementation details, or automated workflow information rather than
   treating software as an unreported accessory.
9. **Operational limitations are required for PAGe.** Surveillance lags,
   revisions, changing epidemic regimes, calibration, and operational public
   health utility should be interpreted before broad generalization. This is a
   reporting judgment supported by the forecasting-guideline record, not a
   universal section-order finding from the eight-article set.

## Implications for the PAGe paper

- Keep the paper centered on the linked operational targets:
  `ignition -> phase/peak -> h1/h2 forecast`.
- Give M0, M1, M2, seasonal training, weekly state updating, and the
  prospective-information boundary their own Methods subsections.
- Organize empirical Results by the claims being tested: data/kit audit, M0,
  M1, primary h2 comparison, secondary h1/phase results, ablations, failure
  cases, and Ontario RSV portability after pathogen-specific retraining.
- Use the independently reviewed four-figure/three-table planning target unless
  the final journal-format audit supports a different display set.
- Draft against [`SKELETON.md`](SKELETON.md); keep all unsupported numerical
  claims visibly marked until the canonical result set is frozen.

## Verification and delegation audit

- **Delegated reviewer:** Argie
- **Route:** Google AI Pro, Gemini 3.1 Pro High, Antigravity CLI (`agy`)
- **Mode:** Read-only literature and repository scan
- **Repository files inspected:** `PLAN.md`, `ANALYSIS_PROTOCOL.md`,
  `LITERATURE_REVIEW.md`, `LITERATURE_MATRIX.md`, `TODO.md`, and `REVIEW_LOG.md`
- **External evidence reported by Argie:** Crossref REST API, Semantic Scholar
  Graph API, ScienceDirect/DOI records, and PubMed Central
- **Reported tool use:** eight local-file views, four web searches, and three
  read-only API-query commands
- **Repository changes by Argie:** None. An attempted write to an internal
  Antigravity directory was denied because the packet authorized read-only work.
- **Parent verification:** All eight DOI/title/journal records were rechecked
  against official ScienceDirect results. The structural synthesis was narrowed
  where article-level full-text evidence was incomplete.

The official record for the physics-informed neural-network article supports
its trained-once description. It is contextual evidence only and is not the
justification for PAGe's independently frozen once-per-season cadence.
