# M2-A test-volume history fully nested LOSO audit — 2026-09-29

## Scope

This is a research/shadow evaluation of whether causal test-volume history improves the canonical M2-A A1 positivity-state forecast. It does not modify canonical v3 routing or frozen model artifacts.

Runner:

`scripts/run_m2_a_ntrend_fully_nested_loso_v1.R`

Local reference evidence:

`artifacts/m2-a-ntrend-fully-nested-loso-v1/`

## Candidate families

All candidates augment the same pooled-horizon A1 structure:

`cbind(y_target, N_target-y_target) ~ horizon_f + growth1 + growth2 + N_history + offset(logit_current)`

Candidate grid:

- `OFF`: exact A1, no test-volume-history term.
- `EXP025`, `EXP050`, `EXP075`, `EXP100`: exponentially weighted distributed lag of the four consecutive weekly `log(N)` changes, with lambda 0.25, 0.50, 0.75, or 1.00.
- `ACCEL22`: mean of the most recent two log-volume changes minus mean of the preceding two.
- `REL8`: `log(N_t) - log(N_week8)`.
- `DL2`: unrestricted most-recent two log-volume changes (`d1 + d2`).
- `SPLIT22`: recent-two and older-two mean log-volume changes.
- `EXP050_X_G1`: `EXP050` plus its interaction with positivity growth `growth1`.

The grid intentionally excludes redundant endpoint/OLS/Almon variants after the preceding repeated-measures association study identified the above families as the scientifically distinct shortlist.

## Candidate-independent ledger

All candidate comparisons use identical rows. An origin is eligible only when:

- weekF >= 13;
- exact weeks `t-4, ..., t` exist;
- exact week 8 exists for `REL8`;
- exact target week `t+h` exists;
- all count data are valid.

The final ledger has:

- 11 seasons;
- 851 origin/target rows total;
- 431 +1 rows;
- 420 +2 rows.

Independent recomputation of `d1..d4`, all four exponential distributed-lag summaries, and `REL8` matched the frozen ledger to <= 4.9e-15. Every target-week alignment satisfied `target_week = origin_week + horizon`.

## Nested LOSO design

For each outer held-out season S:

1. Remove S completely.
2. For every remaining inner held-out season V:
   - fit every candidate on seasons excluding both S and V;
   - predict V;
   - compute +1 and +2 scores separately.
3. Candidate selection happens only from these inner-fold scores.
4. Refit the selected candidate on all outer-training seasons.
5. Predict outer season S for the first time.

The outer season therefore cannot influence feature-form selection, lambda selection, OFF/ON choice, coefficient fitting, or inner scoring.

The candidate model is fit jointly over +1 and +2 rows, retaining the canonical A1 pooled-horizon structure. Candidate selection and outer reporting are horizon-specific.

## Selection loss

Inner selection uses Bernoulli cross-entropy per test:

`-[y log(p_hat) + (N-y) log(1-p_hat)] / N`

Loss is averaged first within each inner held-out season and then equally across seasons. This prevents modern high-denominator seasons from dominating simply because more tests were performed.

MAE in percentage points and Brier error are retained as secondary metrics.

## OFF preference and paired one-SE rule

An initial implementation used the standard error of absolute season losses. That was rejected during audit because between-season difficulty dominated the SE (~0.015), while candidate differences were ~0.0003-0.0013.

The final selector uses a **paired one-SE rule** because all candidates score identical rows:

1. identify the raw inner candidate with minimum mean season-balanced loss;
2. for every candidate, calculate its loss difference from that raw winner in each inner held-out season;
3. calculate the mean and SE of those paired differences;
4. candidates whose mean excess loss is <= one paired SE are treated as indistinguishable from the raw winner;
5. among those, choose lowest complexity, then lower governance risk, then lower mean loss.

`OFF` has complexity zero. Thus test-volume history can be turned off by tuning whenever its inner gain is not sufficiently stable.

The runner additionally reports a fully nested `raw_best` policy (minimum inner loss without the paired one-SE simplicity preference) for sensitivity analysis. It is not the primary governed selector.

## Local reference results

### +1 week

Primary paired-one-SE selection:

- `OFF`: 10/11 outer folds
- `EXP025`: 1/11 outer folds

Outer season-balanced results:

- OFF loss: 0.209158
- nested loss: 0.209467 (0.15% worse)
- OFF MAE: 1.40724 pp
- nested MAE: 1.43661 pp (2.09% worse)

The primary conservative selector therefore does **not** support adding test-volume history to +1.

The fully nested raw-best sensitivity policy chose `EXP050` in 10/11 folds and `DL2` in 1/11. Its aggregate +1 MAE was 1.33417 pp versus 1.40724 pp for OFF, a 5.19% relative improvement. Its loss improved only 0.17%. This suggests a potentially useful +1 signal whose uncertainty is still too large for the conservative OFF-preference rule.

### +2 weeks

Primary paired-one-SE selection:

- `EXP050`: 8/11 outer folds
- `EXP025`: 3/11 outer folds
- `OFF`: 0/11 outer folds

Outer season-balanced results:

- OFF loss: 0.217294
- nested loss: 0.216514 (0.36% improvement)
- OFF MAE: 2.07731 pp
- nested MAE: 2.04516 pp (1.55% improvement)
- loss better in 8/11 outer seasons
- MAE better in 6/11 outer seasons

The fully nested raw-best policy improved +2 MAE to 2.02295 pp, a 2.62% relative improvement, and loss by 0.37%.

The +2 result is therefore more stable than +1 in model-selection terms: every outer training set selected a one-coefficient exponentially weighted recent-volume feature under the paired-one-SE rule. However, the magnitude of outer MAE improvement is modest and is not promotion-grade by the prior >=5% style threshold.

## Interpretation

The association study showed strong conditional associations for recent test-volume growth. Fully nested LOSO substantially tempers that result.

The robust forecasting signal, if any, appears to be:

- short-memory rather than long-memory;
- exponentially weighted rather than requiring multiple free lag coefficients;
- more stable for +2 than +1;
- modest in outer predictive magnitude.

This is consistent with the behavioral-feedback hypothesis but does not yet justify altering canonical v3.

## Reproducibility audit

The full runner was executed with `PAGE_WORKERS=4` and again with `PAGE_WORKERS=1` into a separate directory.

The following files were byte-identical across runs:

- `summary.csv`
- `selection_frequency.csv`
- `outer_per_season_metrics.csv`
- `outer_predictions_scored.csv`
- `inner_candidate_summaries.csv`

Reference SHA-256 values from the final local run include:

- `summary.csv`: `321b178ecf4f58fd8127d1061c4a424794ed1833c1c18016c4dd3d0cae420476`
- `selection_frequency.csv`: `9825b667223f35506bd872afb7e76df4557c83121e1fa2c9e369f46cf8a4b788`
- `outer_per_season_metrics.csv`: `5d1535088c92306503241f40d9cba942c4462ee8818f5def820d12dc4b5e4ff5`
- `outer_predictions_scored.csv`: `35cae52fc222959fffa92d67a777fffa3c7794cf36b56a6911dfdcc408557912`
- `inner_candidate_summaries.csv`: `c8e49766f91cc2a122d0dc620493768d37f4e99fde522b84606f96babe8096f8`

These hashes correspond to the paired-one-SE/raw-best final runner outputs.

## BCC execution status

The statistical implementation and reference run are complete on Asgard. This chat session's active AgentPorter connector exposes only the Asgard `repos` workspace. The separate BCC AgentPorter endpoint described in `m3/docs/BCCGPT_SETUP.md` is not available as a callable tool in this session, so no BCC execution is claimed.

Once the runner is present in the BCC PAGe checkout, the equivalent BCC command is:

```bash
cd /home/yeli/repos/PAGe
PAGE_WORKERS=8 \
PAGE_AB_PANEL=artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv \
PAGE_OUT_DIR=artifacts/m2-a-ntrend-fully-nested-loso-v1-bcc \
Rscript --vanilla scripts/run_m2_a_ntrend_fully_nested_loso_v1.R
```

Then compare the BCC `summary.csv`, `selection_frequency.csv`, outer predictions, and inner summaries against the local reference outputs. Exact equality is expected if the input panel bytes and R numerical environment are equivalent; otherwise numerical differences should be investigated rather than assumed benign.

## Disposition

**Nested LOSO design: accepted after paired-SE correction.**

**+1 N-history augmentation: not supported by the conservative nested selector.**

**+2 exponential recent-volume augmentation: supported as a shadow research candidate, but effect size is too modest for canonical promotion.**

Canonical v3 remains unchanged.
