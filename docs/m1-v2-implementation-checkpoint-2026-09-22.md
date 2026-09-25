# M1-v2 implementation checkpoint — 2026-09-22

## Runtime target

Current implementation target:

`m1-v2-lowrank-peak-anchored-v1`

Core structure:

- direct continuous peak-time inference;
- peak-relative historical smoothing with the frozen retrospective GAM truth procedure;
- peak-height normalization;
- one low-rank historical shape component;
- analytic/numerical constraint that every admissible shape deformation retains its maximum at relative time zero;
- positive amplitude nuisance integrated out on a finite grid;
- count-aware sampling variance;
- season-excluded historical fitting;
- release-time origin semantics.

M1-F and M1-C remain separate tasks but share one historical library.

## Release-time origin semantics

Weekly observation `w` summarizes `[w, w + 1)`.

Runtime origin `w` means the completed aggregate `weekF = w` is available. Therefore:

- causal data prefix: `weekF <= w`;
- continuous as-of boundary: `w + 1`;
- a peak is strictly future only when `T* > w + 1`;
- first origin whose completed interval can contain the peak: `ceiling(T*) - 1`.

The governing timing annotation contract has been amended accordingly.

## M1-F exploratory validation

Release-consistent constrained prototype:

`artifacts/m1-v2-lowrank-posterior-v10-release-consistent/`

Across all 11 seasons on the strict-future-at-release ledger:

- 86 origins;
- posterior mean MAE: 1.169 weeks;
- posterior mean RMSE: 1.485 weeks;
- MAP MAE: 1.217 weeks;
- nominal 90% point-truth coverage: 75.6%.

On the 81 strict-future origins shared with frozen M1-v1 v16 (10 legacy seasons), both rescored against the new k=8 retrospective GAM peak truth:

- M1-v2 posterior mean MAE: 1.093 weeks;
- frozen v16 MAE: 1.375 weeks;
- M1-v2 RMSE: 1.397 weeks;
- frozen v16 RMSE: 1.724 weeks.

This is an exploratory common-ledger comparison, not yet a release benchmark.

The constrained model is preferred over the slightly more accurate unconstrained v8 because unconstrained extreme PC coefficients could move the shape maximum away from tau=0 and reintroduce timing/shape confounding.

## Uncertainty interpretation

On the prior v8 strict-future ledger, stable retrospective-peak seasons had approximately nominal point-truth coverage, while undercoverage was concentrated in seasons where the retrospective GAM peak itself moved substantially across k=5/6/8/10.

The retrospective peak-sensitivity range remains a diagnostic band, not a formal confidence interval. Model posterior uncertainty and retrospective target measurement sensitivity must remain separate.

Do not globally inflate M1 intervals solely to cover smoothing-sensitive k=8 point targets.

## M1-C passage

Constrained passage prototype:

`artifacts/m1-c-passage-lowrank-v4-constrained/`

Passage posterior uses the peak-relative library extended through peak +3 and evaluates:

`P(T* <= origin + 1 | data through origin)`.

The preferred rule family is hybrid:

1. high passage posterior + immediate observed decline; OR
2. lower passage posterior + two consecutive declines + material drop from the post-activation running maximum.

Operational safety contract:

- high-posterior threshold must be >=0.95;
- false-early confirmation is prioritized over confirmation delay in selection.

With high-threshold candidates restricted to >=0.95, strict LOSO exploratory evaluation gives:

- false-early confirmations: 0/11;
- confirmed by peak+2: 10/11;
- one peak+3 confirmation (2012-13);
- mean confirmation delay: 1.18 weeks;
- median delay: 1 week.

A fixed descriptive policy (`high=0.95`, `low=0.10`, `drop=0.05`, `min_post_A=4`) happens to confirm all 11 by peak+2 with zero early locks on these same seasons, but that is not an unbiased validation result and must not be reported as such. Governed selection must remain nested/cross-fitted.

## Package API added

`PAGe/R/m1_v2.R`

Exports:

- `fit_m1_v2_library()`
- `m1_v2_peak_posterior()`
- `m1_v2_passage_posterior()`
- `m1_v2_passage_decision()`

Important guards/contracts:

- training seasons and supplied peak truth must match exactly;
- peak truth must be generated from the same configured retrospective smoother used to construct the library;
- inference refuses a current season present in the training library;
- future M1-F candidates begin after the release boundary `origin + 1`;
- passage posterior is evaluated at the release boundary;
- aggressive passage thresholds below 0.9 are rejected by the API.

## Verification

Focused direct-source test file:

`PAGe/tests/testthat/test-m1-v2.R`

Result:

- 22 passed;
- 0 failed;
- 0 warnings from the test assertions.

Repository-wide syntax check:

- 74 R files parsed successfully.

Real campaign smoke test:

- held out 2024-25;
- training library fit on the other 10 seasons;
- causal M0 activation used;
- at origin 29, M1-F returned posterior mean peak ~30.81 with 90% interval ~30.05–32.95;
- separate M1-C posterior returned passage probability ~0.386 at the release boundary.

Roxygen could not complete because of the known local dependency mismatch (`ns_registry_env()` defunct), after writing `NAMESPACE`. Required M1-v2 exports were then verified/added surgically. Full package-level test/check remains blocked by that local environment issue; direct-source tests and parse checks are passing.

## Next engineering step

Do not add more M1 predictors.

Next work should:

1. reproduce the full strict LOSO M1-F/M1-C evaluation through the package API rather than exploratory scripts;
2. cache season-excluded libraries by training-set/truth/data/code hash;
3. formalize the runtime state object (`active`, `passage_confirmed`, etc.);
4. add M1 output fields required by M2 (`peak_mean`, interval width, probability within +1/+2/+3, passage probability, locked peak state);
5. only after package-level replay matches the exploratory benchmark, integrate M1-v2 into the governed outer LOSO pipeline.
