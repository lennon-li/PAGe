# M1-v2 stability and passage findings — 2026-09-22

## Runtime origin semantics

The redesign now makes the release-time convention explicit:

- weekly observation `w` aggregates continuous interval `[w, w + 1)`;
- runtime origin labelled `w` is immediately after the completed `weekF = w` aggregate is available;
- the causal prefix is exactly `weekF <= w`;
- the continuous as-of boundary is therefore `w + 1`;
- a latent peak `T*` is strictly future at origin `w` only if `T* > w + 1`;
- the first weekly origin whose completed interval can contain/reach the latent peak is `ceiling(T*) - 1`.

This convention changes evaluation semantics, not the continuous truth coordinate.

## M1-F strict-future evaluation

Current model: `m1-v2-lowrank-posterior-v8`.

Architecture:

- direct candidate peak time `T`;
- pooled peak-aligned canonical curve;
- one training-only low-rank shape component;
- positive season amplitude nuisance;
- marginalization over amplitude and one shape coefficient;
- season-excluded historical shape library;
- count-aware sampling variance.

On origins where the peak is still strictly future at release (`T* > origin + 1`):

- 86 origins across all 11 seasons;
- posterior mean MAE: 1.178 weeks;
- posterior mean RMSE: 1.499 weeks;
- MAP MAE: 1.261 weeks.

On the 81 strictly-future origins shared with frozen M1-v1 v16 (10 legacy seasons), both rescored against the new retrospective GAM peak truth:

- M1-v2 posterior mean MAE: 1.128 weeks;
- M1-v1 v16 MAE: 1.375 weeks;
- M1-v2 RMSE: 1.449 weeks;
- M1-v1 v16 RMSE: 1.724 weeks.

This is an exploratory common-ledger comparison, not a release benchmark.

## Sequential stability

Across the 11 seasons:

- mean absolute week-to-week change in posterior mean peak estimate: 0.528 weeks;
- 6/11 seasons have at least one jump >1 week;
- only 1/11 seasons has a jump >2 weeks;
- mean first 90% interval width: 6.61 weeks;
- mean last pre-peak interval width: 1.43 weeks;
- interval width narrows on most sequential updates for every season.

The model is therefore generally stable while retaining the ability to move when new data are informative.

## Uncertainty and retrospective truth ambiguity

On the strict-future ledger:

- overall nominal 90% point-truth coverage: 76.7%;
- stable retrospective-peak seasons: 90.7% point coverage;
- smoothing-ambiguous retrospective-peak seasons: 53.1% point coverage.

The retrospective sensitivity range is a diagnostic range, not a formal CI. Nevertheless, posterior 90% intervals overlap that sensitivity range in:

- 94.2% of all strict-future origins;
- 96.9% of strict-future origins from smoothing-ambiguous seasons.

Conclusion: do not globally inflate M1 intervals merely to cover an arbitrarily precise `k=8` target in seasons where the retrospective measurement procedure itself moves by 1–3 weeks. Preserve model uncertainty and peak-measurement sensitivity as separate quantities.

## M1-C passage confirmation

M1-C is separate from M1-F and uses a candidate-independent ledger through truth peak +2.

A posterior-only passage rule was not safe enough. It could declare passage early in the complex 2018-19 season.

The better exploratory rule family is hybrid:

1. high posterior probability that the peak is already passed plus an immediate causal decline; OR
2. moderate passage probability plus sustained decline from the running maximum.

Rule selection is strict LOSO. Training selection prioritizes:

1. false-early confirmations;
2. magnitude of early confirmation;
3. misses by peak+2;
4. confirmation delay.

Current LOSO hybrid result under release-time truth semantics:

- false-early confirmations: 0/11;
- confirmed by peak+2: 9/11;
- misses by peak+2: 2/11;
- median confirmation delay: 1 week;
- mean delay: 1.36 weeks.

The two late cases are 2012-13 and 2024-25, both confirming at peak+3.

No claim should be made yet that the hybrid threshold is final. Passage thresholds must remain nested/cross-fitted in governed evaluation.

## Current M1 direction

Keep M1-F fixed while formalizing implementation around the v8 architecture. Do not add more ad hoc predictors.

Next engineering work:

- convert the exploratory low-rank posterior into package code with explicit state/output contracts;
- preserve the release-time origin semantics in all ledgers;
- expose posterior mean/median/MAP, interval, probability peak within +1/+2/+3, and status;
- implement M1-C as a separate passage module using the hybrid posterior-plus-decline evidence;
- ensure passage stopping never changes the evaluation ledger;
- keep retrospective peak-sensitivity diagnostics separate from runtime posterior uncertainty.
