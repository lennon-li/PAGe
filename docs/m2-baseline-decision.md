# M2 baseline decision guide

`decide_m2_vs_m1()` is the data-agnostic adoption gate for one model that will
be deployed to a future season. It compares matched walk-forward forecasts
against M1, treats the all-off M2 configuration as an exact M1 fallback, and
returns both the decision and the evidence used to make it.

The decision score is calculated in three steps:

1. Calculate Bernoulli NLL for M1 and M2 on each matched forecast row.
2. Summarize rows within each season and horizon, optionally applying phase
   weights and a denominator such as test volume.
3. Average the resulting season scores equally and require the M2 gain to
   exceed both the practical gain floor and the one-sided season-level
   uncertainty allowance.

The API does not assume influenza, a particular source schema, or the labels
`season`, `week`, and `Virus`. Map arbitrary source columns with
`prepare_page_data()` before training, and map arbitrary forecast columns when
calling the decision function.

```r
decision <- decide_m2_vs_m1(
  forecasts = replay_forecasts,
  outcome_col = "observed_positivity",
  m1_col = "m1_prediction",
  m2_col = "m2_prediction",
  season_col = "season_id",
  origin_col = "origin_week",
  target_col = "target_week",
  horizon_col = "lead",
  phase_col = "forecast_phase",
  phase_weights = c(early = 2, late = 1),
  horizon_weights = c(`1` = 1, `2` = 1),
  min_gain = 0,
  min_gain_by_horizon = c(`2` = 0),
  confidence = 0.95,
  max_season_degradation = 0
)

if (decision$decision == "keep_m1") {
  # Select the all-off M2 candidate, which is exactly M1.
}
```

The phase and horizon settings are policy inputs, not pathogen-specific code.
For the current influenza development cycle, the proposed provisional policy
was a two-to-one early versus later phase weight, with a combined practical
NLL floor of 0.0012 and a two-week horizon floor of 0.0020. Those values must
be recalibrated from the complete end-to-end replay for each new analysis;
they are not defaults for RSV or another pathogen.

The full analysis for any pathogen should preserve separate artifacts for
source preparation, M0/M1 tuning, M2 tuning, every holdout replay, weighted
metrics, boundary audits, and the final decision object. The sequence is:

1. Map the source data with `prepare_page_data()` and record the mapping.
2. Declare disjoint training, excluded, and prospective holdout seasons.
3. Tune and freeze M0, then M1, then M2 without using the holdout outcomes.
4. Replay every available holdout season with M1 and each M2 finalist.
5. Run `decide_m2_vs_m1()` on the complete replay table.
6. Fit one final model on the permitted historical seasons only. If the gate
   fails, use the all-off M2 configuration and deploy M1.

For RSV, the same sequence applies after an RSV historical table and
pathogen-specific ignition labels or a validated label-generation rule are
provided. The current influenza manual-label defaults must not be reused for
RSV. A future RSV run should therefore record its own season declarations,
labels, phase definition, weights, grids, and artifact hashes.
