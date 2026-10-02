# Legacy, v2, and v3 comparison plan

Date: 2026-09-28  
Scope: shadow evidence comparison only

## Valid comparison designs

1. **M0/M1 legacy versus v2:** compare only common-ledger evidence already present in the repository/artifact archive. Use identical target definitions, season eligibility, horizons, and scoring rows. Record unavailable common rows rather than imputing or changing denominators.
2. **Authoritative v2 versus v3:** run both through `2026/run_weekly_shadow_release_v5.R` using the same source snapshot, effective typed panel, season, origin weekF12 or later, and common target definitions. Preserve the parent transaction's source and panel hashes. The API v3 release is `5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b`.
3. **Legacy versus v3:** compare only targets that can be reconstructed on the same target definition and ledger. If target, horizon, eligibility, or scoring rows differ, report separate results without a pooled metric.

## Existing components and evidence

- Canonical v2/v3 transaction runner: `2026/run_weekly_shadow_release_v5.R`.
- Canonical API v3 worker: `2026/run_page_weekly_api_worker_v3.R`.
- Release verification and transaction helpers: `scripts/v3_shadow_release_helpers_v1.R`, `scripts/v3_shadow_ops_helpers_v1.R`.
- Current release: `artifacts/v3-shadow-release-v3/5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b/`.
- Current model evidence: M1-B chronological benchmark under `artifacts/v3-m1-b-*chronological*`; M2-A evidence under `artifacts/v3-m2-a-posterior-c2-chronological-v1/`; M2-B evidence under `artifacts/v3-m2-b-posterior-c2-chronological-v3/`.
- Current prospective report: `docs/v3_week8_11_walkforward_2026_27.html` and source `.qmd`.
- The transaction's `v2_v3_comparison.csv` and `source_transaction.tsv` are authoritative for a weekly same-source/same-panel comparison. Preserve their schema and hashes.
- Prior v1/v2 release directories, weekly smoke outputs, and M0/M1 ledgers are historical evidence only; use their exact artifacts when a common ledger exists. Do not substitute API integration fixtures for forecast evaluation evidence.


## Existing matched legacy/v2 evidence

- **M1 timing:** `artifacts/m1-v2-lowrank-posterior-v10-release-consistent/common_ledger_vs_legacy_v16_strict_future_release.csv` contains 81 matched origin/truth rows across 10 seasons. On that matched ledger, v2 mean absolute peak error is about **1.093 weeks** versus **1.375 weeks** for legacy (difference about -0.283 weeks). Treat this as an M1 timing result only.
- **M2 A-only:** `artifacts/m2-v2-legacy-matched-a-v1/` and `docs/m2-v2-legacy-matched-a-benchmark-2026-09-25.md` provide the direct matched-target-ledger legacy/v2 benchmark. The primary 10-season comparison uses identical target counts, but training vintages are not perfectly identical; preserve that caveat.
- **M0:** no common-ledger legacy/v2 M0 performance artifact has been verified in this audit. Do not publish a legacy-v2 M0 performance claim until target truth, eligible origins, and scoring rows are matched explicitly.

## Comparison matrix

| Stage | Legacy ↔ v2 | v2 ↔ v3 | Legacy ↔ v3 |
|---|---|---|---|
| M0 | Not yet supported by a verified common ledger | M0-A is frozen/shared, so compare state/ignition identity rather than claim a new v3 gain | Only after a matched legacy ledger is built |
| M1-A | Use the common-ledger legacy/v2 timing artifacts | M1-A is frozen/shared in v3 | Use common-ledger legacy/v2 result as context; v3 adds no new A timing model |
| M1-B | No direct legacy-A/B timing equivalence claim | Compare v3 B timing on its own governed B eligibility/truth contract | Not directly comparable unless a common B timing truth/ledger is reconstructed |
| M2-A | Use `m2-v2-legacy-matched-a-v1` with its vintage caveat | Authoritative launcher v5; v3 A equals exact A1 by design | Do not infer a three-way paired result unless all rows share the same target ledger |
| M2-B | No supported matched legacy benchmark identified | Authoritative launcher v5 on one source/panel | Not directly comparable without a matched B target ledger |

## Metrics and reporting rules

Do not compare metrics across different horizons, target definitions, origin weeks, eligibility masks, observation ledgers, or source panels. Do not infer improvement from the transaction's four forecasts alone. Report per-target and per-horizon paired rows, common-row count, exclusions, source/panel/release identities, and scoring rule. Do not pool incomparable scores or describe shadow comparisons as promotion evidence.
