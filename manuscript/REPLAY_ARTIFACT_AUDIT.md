# Holdout replay artifact audit

Audit date: 2026-09-02. Archive searched on BCC under
`/mnt/nfsv4/Users/yeli/PAGe-artifacts/seasonal-archive-20260818`.

The intended valid-season set has 11 possible holdouts. The permanent
exclusions are 2011-12, 2015-16, 2020-21, and 2021-22. A replay is considered
strictly current-process evidence when its manifest records the governed
protocol `latest-governed-api; exchangeable-season nested LOSO`, its replay and
stage artifacts are complete, and its source commit is the current verified
checkout `95c1c9f3e084844aa6b5f96219290ca64b66e082`.

| Holdout | Selected archive run | Replay status | Bernoulli NLL | MAE | Predictions | Process/API provenance | Use in current pooled table |
|---|---|---:|---:|---:|---:|---|---|
| 2012-13 | `2012-13/runs/2012-13-current-api-20260901` | complete | 0.384700 | 0.045078 | 67 | **Verified current**; governed nested LOSO, commit `95c1c9f` | Yes |
| 2013-14 | `2013-14/runs/2013-14-current-api-20260901` | complete | 0.301311 | 0.038506 | 63 | **Verified current**; governed nested LOSO, commit `95c1c9f` | Yes |
| 2014-15 | `2014-15/runs/2014-15-latest-api-20260818` | complete | 0.419667 | 0.034020 | 65 | Conditional: same governed nested-LOSO protocol, older commit `d60d023` | Re-run for strict current set |
| 2016-17 | `2016-17/runs/bcc-2016-17-v5` | replay present | 0.397588 | 0.037387 | 65 | **Not verified**; no complete current manifest/run summary | Re-run |
| 2017-18 | `2017-18/runs/bcc-2017-18-v2` | complete | 0.338210 | 0.020193 | 63 | **Not verified**; legacy provenance fields absent | Re-run |
| 2018-19 | `2018-19/runs/2018-final2-expanded` | complete | 0.358949 | 0.026178 | 65 | **Not verified**; legacy provenance fields absent | Re-run |
| 2019-20 | `2019-20/runs/2019-20-latest-api-20260818-r2` | complete | 0.213926 | 0.021932 | 59 | Conditional: same governed nested-LOSO protocol, older commit `d60d023` | Re-run for strict current set |
| 2022-23 | — | not found | — | — | — | No replay artifact located | Run |
| 2023-24 | `2023-24/holdouts-and-docs-2023/exchangeable` | complete | 0.227502 | 0.021291 | 63 | **Not verified**; protocol is older `exchangeable-season-LOSO` | Re-run |
| 2024-25 | `2024-25/holdouts-and-docs-2024/exchangeable` | complete | 0.336849 | 0.028450 | 57 | **Not verified**; protocol is older `exchangeable-season-LOSO` | Re-run |
| 2025-26 | `2025-26/runs/2025-current-api-20260829-r3/2025-final-api` | complete | 0.557184 | 0.045163 | 17 | **Not verified**; manifest lacks source commit and uses non-nested protocol label | Re-run for strict current set |

## Interpretation

Only 2012-13 and 2013-14 are verified against the current exact process
signature and current source commit. The 2014-15 and 2019-20 runs use the same
governed nested-LOSO protocol but were produced from an older source commit;
they are useful audit references, not strict current-process rows. The other
completed replays have insufficient or older provenance. The 2025-26 replay is
also partial-season evidence (17 predictions) and should not be interpreted as
a full-season result.

The input checksum recorded by the verified 2012-13 and 2013-14 manifests is
`fa8add1b253944df5d853a2fb0456d7ac368657e073da0d97f909be95ca59c54`.

## Current-process refresh

The non-verified rows are being regenerated with the same installed PAGe
0.2.0 package and source commit. The controlled execution registry,
supervisors, run IDs, and final reconciliation destination are recorded in
[`HOLDOUT_EXECUTION.md`](HOLDOUT_EXECUTION.md). Until the strict finalizer
passes, the refreshed rows must be treated as pending rather than pooled.

## Final reconciliation

The refresh completed on 2026-09-03 with strict reconciliation passing for all
11 seasons: 10 training seasons per holdout, 0 pending, 0 missing, and 0
invalid. The canonical result files are
[`holdout_reconciliation.md`](../results/audit/holdout_reconciliation.md) and
[`holdout_reconciliation_principal.csv`](../results/audit/holdout_reconciliation_principal.csv).
All refreshed rows record source commit `95c1c9f3e084844aa6b5f96219290ca64b66e082`
and the authorized input checksum above. The 2025-26 row has 17 predictions
and remains partial-season evidence; it must be reported separately from any
full-season aggregate.
