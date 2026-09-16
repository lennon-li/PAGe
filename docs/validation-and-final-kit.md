# Outer evaluation and the final kit: procedure and purpose

Reference for PAGe package users and analysts. Status: draft 2026-09-15.
Lean manuscript version: `manuscript/drafts/validation-and-final-kit-methods-lean.md`.

PAGe produces two different things from the same training recipe:

| | A. Outer holdout evaluation | B. Final operational kit |
|---|---|---|
| Question | How well does the recipe forecast a season it has never seen? | What model do we run on the incoming season? |
| Training seasons | 10 of the 11 eligible seasons, 11 times | All 11 eligible seasons, once |
| Held-out season | One per run, replayed week by week after freezing | None |
| Output | 11 frozen kits + 11 unseen-season replays + metrics | 1 frozen, validated kit |
| Kits kept? | Evidence only; not deployed | Deployed for weekly use |
| Performance number | Yes (the manuscript estimate) | No own estimate; inherits A's estimate for the same recipe |
| API | `run_outer_fold(data, holdout = <season>)` | `train_outer_fold(data, holdout = NULL)` |

## 1. Terms

- **Eligible seasons (11):** 2012-13, 2013-14, 2014-15, 2016-17, 2017-18, 2018-19, 2019-20,
  2022-23, 2023-24, 2024-25, 2025-26. **Fixed exclusions:** 2011-12, 2015-16, 2020-21, 2021-22.
  Excluded seasons are never used for fitting, tuning, or evaluation.
- **Recipe:** the complete, fixed training procedure in Section 2: data contract, labels,
  timing mode, grids, weights, boundary rules, minimum-gain rules, the M2 adoption gate, and the
  fallback. The recipe is what the manuscript evaluates. Hyperparameter *values* are outputs of the
  recipe, not part of it.
- **Kit:** the frozen M0 + M1 + M2 artifact produced by one run of the recipe
  (`assemble_kit()`, validated by `validate_page_kit()`).
- **Inner holdout:** a training season temporarily held out while tuning. It is used only for
  selecting hyperparameters inside one run of the recipe.
- **Outer holdout:** a season kept completely outside one run of the recipe. It is touched only by
  the strict replay after the kit is frozen.
- **Walk-forward replay:** applying a frozen kit to a season one weekly origin at a time, using only
  data available at that origin. Weekly steps update the detector, alignment state and online
  correction; they never refit or retune.

## 2. The recipe (shared by A and B)

Given a set of training seasons `T`:

1. **Labels and timing.** Build timing-v2 labels for every season in `T` (reviewed ignition week and
   observed peak week, each as a one-week pair). The current cycle uses
   `timing_mode = "fractional"`: training targets are the label placed mid-week (label + 0.5), M0
   emits a decimal ignition estimate `iWeek_hatF` with its one-week bracket, and M1 uses fractional
   coordinates.
2. **M0 (ignition).** Tune the detector grid by leave-one-season-out within `T`. If a genuinely tuned
   value wins at a grid boundary, expand one valid step and retune (up to the round limit). Freeze.
3. **M1 (alignment).** With M0 frozen, tune `k_ref` x `slope_weight` (and other declared axes) by
   leave-one-season-out walk-forward within `T`, scoring peak-timing error (Weibull-weighted MAE in
   weeks). Selection (`select_m1_candidate()`, `m1_prefer_simpler = TRUE`): among reference-basis
   sizes `k_ref` whose best spec is within `m1_min_gain` (0.05 weeks) of the overall best, take the
   smallest `k_ref` that has a candidate not requiring boundary expansion, then its lowest-error
   spec. Expand boundaries as for M0. Freeze.
4. **M2 (forecast correction).** With M0 and M1 frozen, tune the M2 grid by leave-one-season-out
   within `T`, scoring log loss (NLL) with phase weights 0 (pre-ignition) / 2 (weeks 0-12 after
   ignition) / 1 (later), equal weight per week and per season. Expand boundaries. Freeze.
5. **M2 adoption gate.** Compare the tuned M2 against M1 on the inner leave-one-season-out rows.
   Use M2 only if the phase-weighted NLL gain is at least 0.0012 overall and 0.002 at horizon 2,
   the confidence bound is satisfied (0.95), and no season degrades
   (`max_season_degradation = 0`). Otherwise apply the **all-off fallback**: the M2 correction is
   switched off, so forecasts equal M1 ("keep M1").
6. **Assemble and validate** the kit, and save every tuning table, boundary report, gate decision,
   checkpoint, and identity.

Values above are the 2025-26 protocol (`2025/run_2025_ultimate.R`). Changing any of them changes
the recipe (see Section 5).

## 3. Workflow A: outer holdout evaluation (manuscript)

**Purpose:** an honest estimate of how the recipe performs on an unseen season, and how that varies
by season, horizon and phase.

**Procedure.** For each eligible season `h` (11 runs, independent, parallelizable):

1. `T = eligible \ {h}` (10 seasons). The label for `h` is removed before tuning.
2. Run the recipe on `T` (Section 2). Each run chooses its own hyperparameters; different folds may
   choose different values.
3. Freeze the kit. Only now replay season `h` walk-forward with
   `replay_season_holdout(kit, data, season = h, kit_compatibility = "strict")`.
4. Save predictions (M1 and gate-applied M2 per origin/horizon), metrics, and all artifacts.
5. **Shadow M2 (being added).** If the gate kept M1, also replay the tuned-but-rejected M2 on `h`
   as a separate, output-only column. This never changes the fold's decision or metrics; it lets us
   see what M2 would have done out of sample.

**It answers:** unseen-season accuracy of the recipe; stability of selected hyperparameters across
folds; how often M2 is adopted; whether the adoption rule makes good decisions (Section 5).

**It does not:** produce the operational model (the 11 kits are evidence only), or choose
hyperparameter values for Workflow B.

**Notes.** This is exchangeable-season leave-one-season-out, not chronological: later seasons may
train a model evaluated on an earlier season. The 2025-26 season has partial observation coverage;
report it separately from full-season summaries. Missing or failed rows are counted, not dropped.

## 4. Workflow B: final operational kit (incoming season)

**Purpose:** the single model used for weekly forecasts in the incoming season.

**Procedure:**

1. `T = all 11 eligible seasons`.
2. Run the same recipe (Section 2) once. Its own inner leave-one-season-out tuning selects the
   hyperparameters; values are not copied from any outer fold.
3. Freeze, assemble and validate the kit (`train_outer_fold(holdout = NULL)`). There is no replay,
   because no season was held out.
4. Deploy: run weekly with the frozen kit. Keep the incumbent running in parallel until the
   candidate passes the operational release gates.

**It answers:** what to run now. **It does not:** measure its own accuracy. Its expected accuracy is
Workflow A's estimate for the same recipe.

**Launch rule for 2026-27:** do not launch until the 2025-26 gate run (r5) has completed and passed
`2025/validate_2025_ultimate.R`. The launcher enforces this (`2026/launch_2026_27_final_kit.sh`).

## 5. How A informs B without biasing the evidence

A tells us whether the recipe's rules work; B uses the recipe. Legitimate uses of A:

- **Adoption-rule check (M2 minimum gain).** Per fold, compare the inner gain (saved in
  `inner_gate_decision.rds`) with the outer gain of M2 over M1 on the unseen season (from the shadow
  replay when M1 was kept). Across folds, ask: does "M2 wins by >= 0.0012 in tuning" predict
  "M2 wins on a new season"? Compare three policies on the same rows: always M1, always M2, gate.
- **M1 minimum gain and simpler-spec preference:** the same inner-versus-outer check for M1 specs.
- **Stability:** if folds select very different values, the final kit's choices are less certain;
  report the spread.

Rules:

1. Fix the recipe before running A. Run A once for that recipe.
2. If A leads you to change a rule (for example, the minimum gain), that is a **new development
   cycle**. Record it as a dated deviation; do not present the old folds as confirming the new rule.
3. A threshold chosen by looking at the 11 folds cannot be scored on those same folds as if
   prespecified. Show such analyses as labelled sensitivity curves.
4. Eleven folds give direction ("M2 rarely helps out of sample"), not a precise optimal threshold.
5. For the current season, B uses the recipe as declared; A's findings inform the next recipe.

## 6. Order of work for 2026-27

1. r5 (2025-26 outer fold, new code) completes and validates: end-to-end check of the code.
2. Workflow B on all 11 seasons -> operational kit -> weekly runs (incumbent kept in parallel until
   release gates pass).
3. Workflow A for the remaining 10 folds with the same recipe and platform, including shadow M2.
4. Manuscript: A's results, rule checks (Section 5), comparators (calendar GAM), and a conditional
   RSV application.

This order is valid because the recipe is fixed before both; A evaluates exactly the recipe that
produced B's kit. If A reveals a problem, fix the recipe and retrain B; never edit the kit by hand.

## 7. Reproducibility requirements (both workflows)

- One platform per analysis: record BLAS/LAPACK, OS, CPU, R and package versions. Identical code on
  different BLAS libraries gave small score differences (up to 0.011 weeks of M1 error).
  Set `OPENBLAS_NUM_THREADS=1` for forked workers.
- Run-local package library with source and installed-package hashes checked before launch.
- Fresh run ID per attempt; never overwrite or mix checkpoints from different code or protocol.
- Detached launch (`setsid`) from a host shell, never from inside an agent sandbox; an identity
  watchdog (PID + start time + command) records status and a terminal packet.
- Keep every artifact: protocol, labels, grids, tuning tables, boundary reports, gate decisions,
  kits, replays, predictions, platform manifest.
