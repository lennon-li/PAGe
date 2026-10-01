---
title: "Daily-data extensions for PAGe"
---

This note records the design options for using daily surveillance observations while preserving the current PAGe weekly forecast target.

## Objective

The current pipeline has one row per season-week and produces one- and two-week-ahead weekly positivity forecasts:

`daily observations (future work) -> M0 ignition -> M1 alignment -> M2 weekly forecast`

The first daily-data experiment should answer whether finer observations improve prospective weekly forecasts. It should therefore keep the target, forecast cutoffs, holdout seasons, and primary weighted metrics comparable with the current weekly system.

## Data contract

Daily input should contain one row per `season + date`, with:

- `date` and `season`;
- positive tests `y_day` and total tests `N_day`;
- source and reporting metadata when available;
- an availability timestamp or archived data vintage, when available;
- derived epidemiological week, day-of-week, and within-season day index.

Daily positivity is `y_day / N_day`. A seven-day pooled signal must be calculated as

\[
p_{7,d} = \frac{\sum_{j=d-6}^{d} y_j}{\sum_{j=d-6}^{d} N_j},
\]

rather than as the unweighted mean of seven daily percentages. A centered moving average is prohibited in prospective features because it uses future observations.

## Option A: weekly baseline

Aggregate daily counts into Sunday-to-Saturday surveillance weeks and run the existing weekly M0, M1, and M2 implementation. This is the control condition. It also verifies that daily-to-weekly aggregation reproduces the existing public weekly file where the two sources overlap.

## Option B: seven-day pooled signal with daily M0/M1 and weekly forecasts

Run M0 and M1 once per day, using the trailing seven-day pooled positivity and daily-derived trend features. Issue M2 forecasts at the normal weekly cutoff and retain weekly one- and two-week targets.

At each day `d`:

1. Calculate `roll7_y`, `roll7_N`, and `p_roll7` from days `d-6:d`.
2. Apply M0 gates to `p_roll7`, its logit-scale slope, persistence, and cumulative burden.
3. If ignition is detected, retain a continuous `iDay_hat` and its corresponding epidemiological week.
4. Give M1 all daily observations through `d`, align the partial trajectory, and update the peak-day estimate and uncertainty.
5. At the weekly cutoff, pass the latest M0/M1 state and daily-derived M2 features to a matching trained and frozen M2 candidate.
6. Forecast the next complete week and the following complete week.

This option attenuates weekday reporting variation and updates within the week, but it still requires changes because the current contracts and runtime assume integer weekly indices. The overlapping rolling windows are correlated, so they are features or detection signals; they must not be treated as independent binomial observations in model fitting. They also create dependence in persistence gates, alignment scores, and uncertainty calculations.

## Option C: raw daily observations with smoothed features

Fit daily M0/M1 models to the daily counts, but calculate noisy derivatives and EMA features from a causal smoother such as the seven-day pooled signal. M2 can remain weekly at first.

This preserves the exact timing of daily changes and permits a daily ignition date, but requires explicit treatment of day-of-week effects, reporting delays, missing days, serial correlation, and source changes.

## Option D: multiple causal windows

Use several pooled signals, initially 7-day and 14-day:

- `p_roll7` for rapid changes;
- `p_roll14` for persistent movement;
- the change in each signal for level and trend features.

Three-, seven-, fourteen-, and twenty-one-day windows may be compared in a bounded pre-holdout grid, but seven separate windows should not be added automatically. Each extra window is another tuned feature and increases overfitting risk.

## Option E: daily latent-state model

Model an unobserved daily epidemic state and treat observed positives as noisy binomial measurements. M0 detects a transition in the latent state, M1 aligns latent epidemic curves, and M2 forecasts the latent state or daily positivity before aggregating it to weekly positivity.

This is the most principled option for noisy daily reporting, but it is a new statistical model rather than a frequency conversion. It should follow the simpler causal rolling-signal experiment.

## M0 design

Daily M0 should use a causal seven-day pooled signal, not raw single-day positivity. Candidate daily persistence rules must be retuned by leave-one-season-out evaluation. Weekly ignition labels cannot support precise day-level claims; if only weekly labels exist, score daily detection as interval-censored within the labelled week or evaluate the mapped `iWeek_hat`.

The output should include both:

- `iDay_hat`, the first day satisfying the locked rule;
- `iWeek_hat`, the epidemiological week containing that day.

## M1 design

M1 should align on a continuous within-season time coordinate:

\[
t^a_{s,d} = t^f_{s,d} - \hat{iDay}_s + t^{anchor}.
\]

The implementation can measure this coordinate in days or fractional weeks. Fractional weeks are preferable initially because the current reference and M2 feature space are expressed in weeks. The daily reference must be tuned with enough smoothness to avoid fitting reporting-day noise. A day-of-week adjustment or causal seven-day signal should be included.

## M2 design

The first M2 experiment should retain weekly targets. A daily-derived feature must be trained and frozen as part of a matching M2 candidate; supplying a new feature to the existing frozen incumbent does not activate a GAM term that was omitted from its specification. At the weekly cutoff, M2 may use:

- the M1 aligned template at the future weekly target;
- current daily or seven-day EMA state;
- recent change in that state;
- current seven-day testing volume;
- M1 alignment spread and peak status.

The observed target remains the pooled weekly positivity:

\[
p_{s,w} = \frac{\sum_{d \in w} y_{s,d}}{\sum_{d \in w} N_{s,d}}.
\]

Daily EMA and bias-correction parameters cannot be copied directly from the weekly model. For example, weekly `alpha_state = 0.20` has the approximate daily equivalent `1 - (1 - 0.20)^(1/7) = 0.0314`, which is only a starting value and must be retuned. If forecasts remain weekly, the bias corrector should update once when each weekly target becomes available, rather than updating repeatedly from overlapping daily summaries of the same outcome.

## Full daily forecasting extension

After the weekly-target experiment, a full daily version could issue predictions for days `d+1` through `d+14`. Those daily predictions would be aggregated to each target week for comparison with the weekly model. If future testing volume is unknown, weekly aggregation requires either equal weighting of predicted daily probabilities or a training-season estimate of future daily testing volume; future observed denominators cannot be used at forecast time.

## Leakage controls

Every daily snapshot must satisfy:

- features at day `d` use only observations dated through `d`;
- the data vintage or publication cutoff at `d` is respected, so later backfilled values cannot enter an earlier snapshot;
- rolling windows are trailing, never centered;
- M1 reference curves exclude the holdout season;
- future target counts are retained only for scoring, never feature construction;
- daily-to-weekly aggregation uses complete target-week observations only after the target closes;
- daily labels unavailable at day resolution are not treated as exact day-level truth.
- missing days and zero-test days have explicit handling; zero tests do not become zero positivity.

## Evaluation plan

For each holdout season, preserve artifacts for:

1. weekly baseline;
2. seven-day pooled M0/M1 with weekly M2;
3. raw-daily or smoothed-daily variants selected before the holdout;
4. daily predictions and the corresponding weekly aggregation.

Use the existing weekly one- and two-week-ahead metrics for the primary comparison. Apply at least twice the weight to ignition-to-peak forecasts compared with post-peak forecasts. Report equal-origin and test-count-weighted summaries separately; the binomial likelihood already uses test counts during model fitting, so test-count weighting should not silently dominate the evaluation metric.

## Astra review and revised recommendation

Astra reviewed this plan against the current PAGe contracts and runtime. The main corrections are:

- A trailing seven-day pooled level at the end of a complete Sunday-to-Saturday week equals the completed weekly positivity by construction. Its level alone therefore cannot demonstrate a daily-data improvement at the existing weekly cutoff.
- Daily observations need availability timestamps or archived vintages. Observation dates alone do not prove that the values were available prospectively, especially when surveillance data are revised.
- The existing contract requires one row per `season + weekF`, and current reference/runtime code coerces aligned time to integer weeks. A full daily M0/M1 implementation needs a separate daily contract and continuous-time alignment path.
- The current frozen M2 model reconstructs weekly EMA and volume features internally. A daily-derived M2 term must be included in a newly trained candidate with matching training and replay feature construction.
- Equal-weighting daily predicted probabilities does not generally reproduce pooled weekly positivity when future daily test volume is unknown.

The preferred first experiment is therefore a smaller hybrid:

1. Reconcile daily and weekly counts, dates, source changes, missingness, and data vintages.
2. Build the weekly baseline by aggregating daily counts and run the existing weekly M0, M1, and M2 pipeline.
3. Keep weekly M0 and M1 fixed and add one prespecified causal daily trajectory feature to a newly trained M2 candidate.
4. Issue both models at identical weekly cutoffs and evaluate the same weekly targets across every holdout season.
5. Only after this test, evaluate daily M0/M1 or a full daily M2 model.

This isolates the incremental information in the daily trajectory before changing all three stages at once.

## Recommended sequence

1. Validate daily-to-weekly aggregation against the public weekly data and archived vintages.
2. Compare the reconstructed weekly baseline with the existing weekly-data baseline.
3. Train one daily-derived M2 candidate while retaining weekly M0/M1 and weekly issuance.
4. Add a 14-day feature only if the prespecified seven-day trajectory feature leaves a clear unresolved trend signal.
5. Test daily M0/M1 as a separate experiment with daily ignition and peak timing metrics.
6. Consider a latent-state model only if the simpler options improve timing but remain unstable under reporting noise.

The decision rule should be based on season-level walk-forward evidence: daily enhancement must improve or meet the weekly baseline under the phase-weighted primary metric, without materially worsening horizon, calibration, or ignition/peak timing.

## Current data readiness

The current local inventory does not yet contain daily surveillance counts. `allweeks.csv` is a daily calendar and epidemiological-week lookup with 4,018 dates, but it has no positive-test or total-test fields. `flu_testing_data.csv` and `Influenza_OLIS.csv` are weekly aggregate files. The aggregation validation and daily-model experiments therefore cannot begin until an authorized daily file containing at least date, positive counts, and total tests is located or supplied. The calendar file can be used as the date/week scaffold once that source is available.
