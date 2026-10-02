# M2-v2 fixed-C2 research artifact checkpoint — 2026-09-25

## Status

**Research artifact accepted. Production runtime remains unchanged.**

Current artifact identity:

`m2v2_3069b9f8cdbd3cec8f23ac3a07ba52abb0a9fc3d10191de00555bb95c8d3f624`

Data identity:

`86a7749b5fc54588a9b8444e8120d5a80725d98ce1cbc6fa372d5858395d67ee`

Shape identity:

`ab79f92bb0d68ed5d9716b9748a817ab8a1aec67124758b5cac7ced24f402568`

Files:

- fitted RDS: `artifacts/m2-v2-c2-research-v1/m2_v2_c2_research_fit.rds`;
- JSON contract/evidence bundle: `artifacts/m2-v2-c2-research-v1/m2_v2_c2_research_v1.json`;
- source manifest: `artifacts/m2-v2-c2-research-v1/source_manifest.csv`;
- standard checksum files: `m2_v2_c2_research_fit.rds.sha256` and `m2_v2_c2_research_v1.json.sha256`.

Current file hashes:

- fitted RDS SHA-256: `d0bfeebd968fdd349e985eaa81ca78ca8a589a2f024c380a8d23f4bc3dd5e793`;
- JSON SHA-256: `4053f211c4d8b8cb43489d6243aebb4acac091207af7e8f8513778d646551945`.

A no-change rebuild reproduced the artifact ID, RDS hash, and JSON hash exactly.

## Frozen research contracts

Family: **fixed C2**. No runtime C1/C2/C3 selector.

Separate fixed weights:

- pooled/type-specific log-drift weight: `type_pool_weight = 0.5`;
- state-baseline/curve forecast logit blend: `curve_blend_weight = 0.5`.

A timing contract:

`m1-v2-to-m2-v1`

B timing contract:

`m1-v2-b-soft-timing-provisional-v1`

B gate policy:

`b-epidemic-gate-5pct-v1` — research provisional.

Denominator regimes are preserved exactly as:

- `historical_shared_flu_test_proxy`;
- `orvt_type_specific`.

They remain provenance/measurement-regime metadata; the production observation likelihood is not finalized.

## Research routing contract

- A +1/+2: type-A state/growth baseline plus fixed-C2 correction only with valid governed A timing.
- B +1: exact B1 baseline.
- B +2: exact B1 unless valid B soft timing exists and the B activity gate is active; then fixed C2 may be applied.
- Timing unavailable/failed, contract mismatch, inactive B gate, or missing curve support: exact type-specific baseline fallback with an explicit reason.
- A timing presented as B timing or vice versa: hard error; cross-type timing substitution is forbidden.

## Identity/provenance contract

The RDS binds:

- research model/spec version;
- fixed-C2 weights and routing policy;
- real upstream timing-contract versions;
- B gate policy/version;
- explicit 11-season training universe;
- per-type baseline coefficients;
- denominator-regime metadata;
- canonical training `data_id`;
- canonical peak-shape `shape_id`;
- SHA-256 hashes of all provenance inputs.

Input row order is canonicalized before fitting/identity calculation. Tests verify row-order invariance.

The final source manifest contains **27 inputs**, including:

- implementation/schema/builder;
- chronological fixed-C2 script and evidence;
- reviewed design and current PASS review;
- A/B geometry sources;
- B baseline/timing evidence;
- immutable legacy benchmark contract;
- direct matched A-only legacy comparison script and evidence.

All 27 source hashes were rechecked after the final build with zero stale entries.

## Validation

Parent verification:

- all 75 package R files parse;
- M1-v2 core: 48 assertions pass;
- M1-v2 B amplitude support: 8 pass;
- M1-v2 pipeline integration: 32 pass;
- M2-v2 C2 research packaging: 33 pass;
- total focused assertions: **121**, zero test warnings/failures;
- JSON Draft 2020-12 schema validation passes;
- RDS artifact identity validation passes after serialization roundtrip;
- standard JSON/RDS checksum verification passes;
- saved-fit routing exercised on real ledger rows: A correction active, B +1 exact baseline, B +2 gated correction active, invalid upstream contract exact fallback.

Independent OpenCode read-only audit: **PASS**, no must-fix item.

## Scientific evidence bound into the artifact

### Prior-seasons-only chronological fixed C2

Season-balanced MAE versus the matched state/growth baseline:

- A +1: 0.96325 → **0.95137 pp** (1.23% gain; 4 seasons better / 2 worse);
- A +2: 1.83805 → **1.71398 pp** (6.75%; 6/6 timing-active seasons better);
- B +1: 0.32536 → **0.32536 pp** (exact baseline);
- B +2: 0.54092 → **0.48838 pp** (9.71%; 2/2 timing-active seasons better).

Among correction-active rows/seasons:

- A +1: ~2.5% MAE gain, mixed robustness;
- A +2: ~10.4%, 6/6 better;
- B +2: ~32.2%, 2/2 better.

A +1 remains the primary robustness watchpoint.

### Frozen legacy M2 matched A-only comparison

Primary matched target ledger: 10 historical seasons with identical stored target counts; 294 +1 rows and 284 +2 rows.

Season-balanced MAE:

- +1: frozen legacy 8.4087 pp; new state/growth baseline 1.7757 pp; fixed C2 **1.5435 pp**;
- +2: frozen legacy 9.2056 pp; new state/growth baseline 2.4124 pp; fixed C2 **2.1531 pp**.

Fixed C2 beats frozen legacy in 10/10 seasons at each horizon (exact sign-test p = 0.001953). Median season-level MAE reduction is ~2.1 pp at both horizons.

The mean relative legacy gain is inflated by a 2013-14 legacy blow-up. Excluding that season, all remaining 9/9 seasons still improve and relative mean MAE gains remain ~65.5% (+1) and ~59.9% (+2).

Most legacy-to-v2 improvement is attributable to the new current-state/growth architecture; fixed C2 adds ~13.1% (+1) and ~10.8% (+2) over that new baseline on the matched exchangeable rows.

This is a target-ledger matched exchangeable comparison, not a fully training-vintage-matched comparison: 2025-26 was revised after the legacy final kit.

## Remaining blockers before production wiring

1. Finalize the denominator/measurement-regime observation likelihood and uncertainty treatment.
2. Stabilize/freeze the B timing-gate policy and B soft-timing contract.
3. Decide the production policy for the A +1 robustness-sensitive branch (retain C2, add a causal guard, or baseline fallback under a predeclared condition) using training-only evidence.
4. Build a runtime handoff adapter that consumes the governed A `m1-v2-to-m2-v1` handoff and an explicitly governed B timing state without allowing type substitution.
5. Run a governed prospective/shadow replay of the packaged RDS through that adapter before any `run_prospective_pipeline()` integration.

Legacy M2 remains untouched and production behavior is unchanged.
