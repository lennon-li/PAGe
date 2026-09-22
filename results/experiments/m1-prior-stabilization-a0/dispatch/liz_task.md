# Bounded task: M1 prior-stabilization experiment A0

## Role

You are the implementation worker. Work only in `/home/yeli/repos/PAGe`.
Create an isolated read-only experiment; do not modify production `PAGe/R`, M0,
M2, the benchmark contract, or any sealed bundle.

## Objective

Test whether the observed M1 instability is reduced by stronger, explicitly
predeclared alignment priors/constraints. This is not a tuning search and must
not promote a candidate.

## Immutable inputs

- `results/experiments/m1-replay-baseline-v1.0.0`
- `results/releases/m1-release-v1.0.0`
- `results/experiments/m1-dynamic-error-decomposition-d1`
- the baseline's serialized inputs and source snapshot

Verify their manifests before execution.

## Required variants

Run exactly these four variants on the same 334 origins, folds, M0 inputs,
templates, coordinates, and scoring contract:

1. `baseline`: reproduce the sealed baseline exactly.
2. `delta_fixed_zero_positive_scale`: keep `delta = 0`; fit `b` under the
   existing positive optimizer bound and use the constrained fitted `b` for
   the final curve/peak rather than an unconstrained post-fit GLM replacement.
3. `delta_ridge4_positive_scale`: preserve the current delta gate but multiply
   the frozen `LAMBDA_DELTA` by 4; use the constrained positive-scale fit for
   the final curve/peak.
4. `delta_ridge16_positive_scale`: same as variant 3 with multiplier 16.

Do not search beyond these four variants. Do not alter `tau` bounds, M0,
template set, slope weighting, temperature, peak aggregation, rounding, or
origin eligibility. Do not use truth to choose a variant.

## Implementation constraints

- Use an experimental runner under this bundle only.
- Preserve all baseline output fields and add variant identifiers.
- Keep the baseline exact; if it cannot reproduce the published baseline,
  stop and report the first divergence.
- Do not silently clip or discard fits. Record optimizer status, objective,
  termination, bounds, parameter values, fallback, and warnings for every
  template-origin fit.
- For positive-scale variants, make the final reported `b` mathematically
  consistent with the constrained fit. Record the exact objective and
  parameterization.

## Required outputs

For every variant and origin/template where applicable:

- `tau`, `delta`, `a`, `b`, `t_peak`, weights, native and rounded peaks;
- optimizer status, maxeval status, objective, fallback, and warnings;
- all 334 origins and the 92 primary origins;
- per-season and per-origin peak metrics;
- parameter step/jump diagnostics;
- negative/non-positive scale counts;
- state/fallback counts;
- baseline parity and variant comparisons.

Compare each variant with the sealed baseline using the identical contract:

- primary integer and decimal MAE;
- companion metrics;
- improved/worsened/unchanged origins;
- per-season effects;
- maximum and 90th-percentile parameter/peak movements;
- optimizer status distributions;
- negative-scale and fallback counts.

Do not claim a winner. End with evidence only and note whether instability is
reduced, unchanged, or increased.

## Bundle

Write only under:

`results/experiments/m1-prior-stabilization-a0`

Include runner, execution specification, all ledgers, metrics, manifests,
session information, and SHA-256 sums. Leave the bundle writable until the
parent verifies it. Do not commit, push, publish, or modify production code.

## Acceptance

The parent will independently verify baseline parity, exact variant definitions,
coverage, leakage safety, metric calculations, and hashes. Worker output is
evidence only.
