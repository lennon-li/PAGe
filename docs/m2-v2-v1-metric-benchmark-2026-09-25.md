# M2-v2 versus legacy M2 benchmark contract — 2026-09-25

## Purpose

Freeze the legacy M2 comparator before governed M2-v2 integration. This avoids later claims that mix different ledgers, targets, weights, type streams, or scoring semantics.

## Immutable legacy artifact

Source final kit:

`../PAGe/results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/`

Frozen artifact:

`artifacts/m2_frozen.rds`

Artifact identity:

`m2_c1e467afffdadff25087be357fa42d231c3632d776e639bffafb9173ae1e3c54`

Legacy family:

`offset_subset_v1`

Governed final specification:

`h1:i0_kz0_ku0_kd0|h2:i0_kz0_ku0_kd0`

That is the all-off/null subset at both horizons. Raw candidate rows with lower aggregate NLL exist in the tuning summary, but the governed boundary/selection result froze the null subset; benchmark claims must use the frozen artifact, not cherry-pick another raw candidate.

## Legacy cross-fitted metrics

Evaluation label: `cross-fitted`

Scoring contract: `page_v2`

Score scale: `equal_week`

Season-balanced means over the 11 governed A seasons:

| Horizon | Bernoulli NLL | MAE probability | MAE percentage points |
|---|---:|---:|---:|
| +1 | 0.42916948 | 0.08204497 | 8.2045 pp |
| +2 | 0.43299484 | 0.09216948 | 9.2169 pp |

Test-count-weighted sensitivity from the same frozen all-off rows:

| Horizon | Bernoulli NLL | MAE probability | MAE percentage points |
|---|---:|---:|---:|
| +1 | 0.49557389 | 0.08936697 | 8.9367 pp |
| +2 | 0.49644519 | 0.10186708 | 10.1867 pp |

## Comparison restrictions

These numbers are **not directly comparable** to the current M2-v2 chronological C2 metrics without an explicit matched-ledger rescore.

Reasons:

1. Legacy M2 is an Influenza-A stream only; M2-v2 now has separate A and B contracts.
2. Legacy M2 uses its own post-ignition/cross-fitted availability ledger and `page_v2` weighting.
3. Current M2-v2 research evaluation uses a candidate-independent weekly ledger, type-specific state/growth baselines, and separate timing availability/fallback semantics.
4. Historical B denominator measurement differs from modern ORVT and did not exist in the legacy M2 contract.

Therefore:

- do not claim M2-v2 beats legacy M2 from the raw values above;
- do not blend A and B when comparing to legacy M2;
- any direct improvement claim requires rescoring legacy M2 predictions on the exact same A-only M2-v2 evaluation rows and metric definition, or rescoring M2-v2 on the frozen legacy A ledger with identical weights;
- retain the artifact identity and scoring contract in any comparison table.

## Current role

This note freezes the immutable legacy reference. The primary scientific evidence for M2-v2 architecture remains strict exchangeable LOSO plus prior-seasons-only chronological replay against the matched state/growth baseline. A legacy matched-ledger comparison is a separate evaluation task.


## Matched-ledger update — 2026-09-25

A direct A-only target-ledger matched comparison has now been completed; see `docs/m2-v2-legacy-matched-a-benchmark-2026-09-25.md` and `artifacts/m2-v2-legacy-matched-a-v1/`.

Primary scope: 10 historical seasons whose stored target y/N counts are identical between the frozen legacy final kit and current M2-v2 reconstruction, intersected on exact `season + origin_week + target_week + horizon` keys. There are 294 +1 rows and 284 +2 rows.

Season-balanced MAE on that matched target ledger:

- +1: frozen legacy M2 **8.4087 pp**, M2-v2 state/growth baseline **1.7757 pp**, fixed C2 **1.5435 pp**;
- +2: frozen legacy M2 **9.2056 pp**, M2-v2 state/growth baseline **2.4124 pp**, fixed C2 **2.1531 pp**.

Fixed C2 is better than frozen legacy in 10/10 seasons at each horizon (exact sign-test p = 0.001953). Median season-level MAE reductions are approximately 2.12 pp (+1) and 2.13 pp (+2).

The mean relative legacy-to-C2 gain is inflated by a large legacy 2013-14 failure. Excluding that season, fixed C2 still improves mean MAE by ~65.5% at +1 and ~59.9% at +2, with all remaining 9/9 seasons better.

This comparison is **target-ledger matched but not fully training-vintage matched**: exchangeable M2-v2 outer fits can use the later revised 2025-26 training snapshot, while the frozen September 18 legacy kit used an earlier 2025-26 snapshot. The first 10 seasons' scored target counts themselves are identical.

The comparison also shows that most of the legacy-to-v2 improvement comes from the new current-state/growth baseline; fixed C2 adds a further ~13.1% (+1) and ~10.8% (+2) MAE improvement over that new baseline on the same matched rows. Do not attribute the full legacy-to-C2 gain to C2 alone.
