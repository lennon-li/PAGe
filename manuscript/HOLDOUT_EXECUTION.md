# Governed holdout execution record

Created: 2026-09-02

This record tracks the manuscript evidence refresh. The principal universe is
the 11 exchangeable seasons declared in `ONTARIO_FLU_SEASON_DECLARATION.md`;
the fixed exclusions are 2011-12, 2015-16, 2020-21, and 2021-22. Each target
season is trained independently with the other 10 eligible seasons, using the
same installed PAGe 0.2.0 package and source checkout at commit
`95c1c9f3e084844aa6b5f96219290ca64b66e082`.

## Execution process

- Runner: `scripts/run_manuscript_holdout.R`
- Lifecycle: M0 tune/expand/validate/freeze → M1 tune/expand/validate/freeze →
  M2 tune/expand/validate/freeze → strict unseen replay
- Input: authorized `flu_testing_data.csv`; checksum recorded in each run
  manifest
- Machine: BCC, 16 cores, two concurrent 7-core jobs
- Main supervisor: `manuscript-batch-20260902-r3`
- Rescue supervisor: `manuscript-rescue-20260902-r4`
- Finalizer: `manuscript-results-20260902`

## Target run registry

| Holdout | Run ID | Execution state at record creation | Artifact location |
|---|---|---|---|
| 2012-13 | `2012-13-current-api-20260901` | complete, previously verified | archive season directory |
| 2013-14 | `2013-14-current-api-20260901` | complete, previously verified | archive season directory |
| 2014-15 | `2014-15-current-api-20260902-r4` | complete; 3.345 h | archive season directory |
| 2016-17 | `2016-17-current-api-20260902-r4` | complete; 3.786 h | archive season directory |
| 2017-18 | `2017-18-current-api-20260902-r3` | complete; 3.412 h | archive season directory |
| 2018-19 | `2018-19-current-api-20260902-r3` | complete; 3.416 h | archive season directory |
| 2019-20 | `2019-20-current-api-20260902-r3` | complete; 3.319 h | archive season directory |
| 2022-23 | `2022-23-current-api-20260902-r3` | complete; 3.678 h | archive season directory |
| 2023-24 | `2023-24-current-api-20260902-r3` | complete; 3.375 h | archive season directory |
| 2024-25 | `2024-25-current-api-20260902-r3` | complete; 3.352 h | archive season directory |
| 2025-26 | `2025-26-current-api-20260902-r3` | complete; 3.667 h; partial input coverage | archive season directory |

The finalizer writes `holdout_reconciliation.csv`,
`holdout_reconciliation_principal.csv`, `holdout_reconciliation_variants.csv`,
and `holdout_reconciliation.md` under the BCC manuscript-results directory
after both supervisors reach terminal completion. Legacy and historical
acceptance artifacts remain separate and are not silently pooled.

The finalizer passed strict reconciliation on 2026-09-03: 11 complete, 0
pending, 0 missing, and 0 invalid. The canonical local copies are
[`holdout_reconciliation.md`](../results/audit/holdout_reconciliation.md) and
[`holdout_reconciliation_principal.csv`](../results/audit/holdout_reconciliation_principal.csv).
The 2025-26 row remains explicitly partial-season evidence despite being
complete as a pipeline artifact.
