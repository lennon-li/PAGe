# V3 M2-B shadow package record

Date: 2026-09-26
Status: frozen shadow-only candidate; prospective issuance begins at PAGe weekF >= 13

## Historical evidence

Final historical evidence:

- benchmark: `v3-m2-b-posterior-c2-chronological-v3`
- artifacts: `artifacts/v3-m2-b-posterior-c2-chronological-v3/`
- implementation: `scripts/v3_benchmark_m2_b_posterior_c2_chronological_v3.R`
- historical verdict: `eligible_for_v3_shadow_plus2`

B +2 historical result:

- B1 season-balanced MAE: `0.514552` percentage points
- posterior-C2 season-balanced MAE: `0.436010` percentage points
- relative improvement: `15.26%`
- timing-active improvement: `24.91%`
- timing-active seasons improved: `5/5`
- worst-season MAE improved: `1.172716 -> 0.763391` percentage points
- pooled target-test NLL improved: `0.0778858 -> 0.0776416`
- all seven predeclared acceptance criteria passed
- all thirteen final integrity checks passed

B +1 remains exact B1 by predeclared policy.

## Interpretation caveat

The M1-B passage posterior often accumulates at its causal lower support boundary.

At B +2:

- timing-active rows: `89`
- lower-bound-saturated rows (`mass >= 0.9`): `44`
- resetting those saturated rows to B1 reduces active improvement from `24.91%` to `8.33%`
- `4/5` active seasons still improve under that reset diagnostic

Therefore the historical gain is interpreted primarily as a causal post-peak/decline-phase correction, not proof of finely resolved B peak timing.

Lower-bound saturation is monitoring-only and never changes routing.

## Frozen package

Artifact:

`artifacts/m2-b-v3-shadow-v2/m2_b_v3_shadow_artifact.rds`

Artifact ID:

`b6ce1fc14145a16ef4739fad469979048680b972f7fe89fa361b5b32abda7789`

Serialized artifact SHA-256:

`983d97047c7c2c946d61d233692d8a9605ee7dd013ab9bcaeb6ea694ed4eb350`

Runtime helper:

`scripts/v3_m2_b_runtime_helpers_v2.R`

Builder:

`scripts/build_m2_b_v3_shadow_artifact_v2.R`

Runtime contract:

`docs/v3-m2-b-shadow-runtime-contract-2026-09-26.md`

Final historical disposition:

`docs/v3-m2-b-final-disposition-2026-09-26.md`

## Frozen routing

- `B +1 = exact B1`
- `B +2 = posterior C2` when causal M1-B timing is available
- otherwise `B +2 = exact B1`
- no hard M1-B passage decision
- no scalar M1-B timing calibration
- no A-conditioned M1-B timing
- unsupported shape-posterior mass contributes exact B1

## Season policy

B modeling:

- 2019-20 excluded as `pandemic_transition`
- 2018-19 included for B state training but excluded from B timing/shape training
- 2018-19 timing correction is zero in historical evaluation
- A 2019-20 shape remains allowed in the pooled A contribution under unchanged A policy

Full-history state fit contains ten B seasons excluding 2019-20.

Full-history M1-B / B-shape library contains nine seasons excluding 2018-19 and 2019-20.

## Package governance

The runtime validator enforces:

- artifact version/status and non-production state
- frozen season lists
- frozen M1-B v8 artifact/library hash
- fixed C2 weights `0.5/0.5`
- fixed blend `eta=0.5`
- lower-bound monitoring step `0.2` and saturation threshold `0.9`
- exact +1/+2 routing contract
- production and hard-passage prohibition
- final v3 benchmark version
- final disposition hash
- runtime helper/contract hashes

The weekly runner additionally verifies every row of the packaged `source_manifest.csv` before loading live data.

## Weekly runner

Runner:

`2026/run_weekly_m2_b_shadow_v3.R`

Default output root:

`results/weekly-m2-b-shadow-v3/`

The runner:

- archives the source vintage
- accepts live ORVT / OLIS fallback or an explicit typed-panel replay input
- audits revisions against the previous typed panel
- validates the entire M2-B package manifest before forecast execution
- refuses valid forecast issuance before PAGe weekF 13
- routes +1 to exact B1
- routes +2 through posterior C2 only when causal timing is available
- logs timing/fallback reason, activity week, supported mass, lower-bound mass/saturation, artifact IDs/hashes and source vintage

Historical note: under the superseded weekF13 issuance contract, the local 2026-27 weekF11 smoke run emitted `not_in_validated_window_before_weekF13`. The current canonical v3 policy starts at weekF12; see `docs/v3-week12-lower-bound-migration-2026-09-28.md` and `docs/v3-current-canonical-stack-2026-09-28.md`.

## Validation

Relevant combined contract suite:

- M1-B legacy shadow contract: `45/45`
- M1-B hardened v8 contract: `21/21`
- M2-B historical v1 contract: `72/72`
- M2-B validation-hardened v2 contract: `98/98`
- packaged M2-B v2 contract: `87/87`
- weekly M2-B v3 runner contract: `26/26`

Total: `349/349` assertions passed, with zero failures, warnings or skips.

Independent final package review: `APPROVE WITH CAVEATS`.

The remaining governance caveat is repository persistence: the v3 files are currently uncommitted. No Git commit/push was performed because commit authorization was not explicitly given.

## Prospective monitoring

Once weekF >= 13, score B +2 separately for:

1. all issued forecasts
2. timing-active forecasts
3. lower-bound-saturated forecasts (`mass >= 0.9`)
4. non-saturated timing-active forecasts
5. exact-B1 fallback forecasts
6. `m1_posterior_error:*` fallbacks separately from ordinary no-activity fallbacks

Do not retune from 2026-27 outcomes during the shadow period.
