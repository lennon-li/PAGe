# Liz task: stage evidence and M1-only comparison

Subagent: Liz
Model Provider: OpenAI
Model: gpt-5.6-luna
Reasoning Effort: high
Access Service: second Codex entitlement, /home/yeli/.codex-liz
Runtime / CLI: liz exec
Permission Level: 1
Interaction Mode: AUTONOMOUS
Authorization: MAY MODIFY FILES WITHIN SCOPE
Project root: /home/yeli/repos/PAGe
Base: agent/page-governance-audit @ 9122c8e229e27aad4a03fc4858c82e7d2d9ae0e8
Step budget: 60 tool calls, cooperative (CLI has no verified step-limit flag).
Stop and hand off on budget exhaustion. No helpers. Wall time limit 40 minutes.

Objective: produce reproducible outer-holdout ignition/peak reporting tables and
an M1-only forecast comparison using the completed repaired-runtime replay.
This is an implementation and statistical-correctness task. User explicitly
requested Liz. Parent Jax reviews output. Use high effort for metric definitions.

Allowed write paths:
- scripts/publication_stage_report.R
- manuscript/results/publication-repair-20260908/stage-report/ (new outputs,
  .gitignore for private rows, tests, README/report and handoff)
- /tmp/page-liz-* scratch paths
Read-only context: PAGe/R, manuscript protocols, existing scripts/results,
/home/yeli/PAGe-bcc-artifacts and /home/yeli/FLU/flu_testing_data.csv.
Out of scope: package edits, existing source/result edits, new data or seasons,
retraining/reselection, comparator tuning, git fetch/sync/commit/push/branch/PR,
deploy, secrets, shared memory edits and other projects. Existing dirty tree
and divergent branch are known: work on current source in disjoint new paths.
Do not stop merely because the branch is divergent. No hypothesis testing.

Known context (use it, avoid broad rediscovery):
- manuscript/PUBLICATION_AUDIT_2026-09-07.md findings 2 and 6 define the work.
- Repaired frozen-kit replays completed all 11 seasons, 655 scored rows.
  Root: manuscript/results/publication-repair-20260908/replay/20260908T125939/
  summary.json, manifest.json, status.json; private/<season>.rds contains
  predictions, forecast_ledger, stages$m0, stages$m1_parameters,
  stages$m1_curves, stages$m2_predictions (includes m1_p,m1_lo,m1_hi per origin/h).
- The M1-only comparator is those saved m1_p forecasts, from the same fitted
  upstream kit. Label it explicitly as pipeline-component diagnostic, not a
  separately retuned standalone M1 model.
- Registry: results/audit/holdout_reconciliation_principal.csv. Replace its
  /mnt/nfsv4/Users/yeli/PAGe-artifacts prefix with /home/yeli/PAGe-bcc-artifacts.
  artifacts/run_manifest.rds includes manual_labels and training/exclusion sets.
- Existing data source SHA256:
  fa8add1b253944df5d853a2fb0456d7ac368657e073da0d97f909be95ca59c54.
- 11 eligible seasons: 2012-13,2013-14,2014-15,2016-17,2017-18,2018-19,
  2019-20,2022-23,2023-24,2024-25,2025-26 (partial). Exclusions fixed:
  2011-12,2015-16,2020-21,2021-22. 10 training / 1 holdout. Training once per season.
- scripts/publication_replay.R has metrics and ledger validation;
  scripts/publication_comparator_helpers.R has raw-data season-week mapping.
  Sourcing these does not execute CLI mains. Four-comparator results live in
  comparators/season_scores.csv and summary.json; avoid combined CSV duplicates.
- 2025-26 manual ignition label 19 appears in manifests, but independently
  verified source/date/hash provenance remains unresolved. Do not invent it.
- Bounds are conditional fitted-mean bands, not full predictive distributions.

Guidance depth: steps; precise evidence definitions need explicit review.
1. Inspect saved schema and direct detector/alignment definitions. Separate
   estimated ignition onset from first declaration week; if a field is absent,
   mark unavailable rather than reconstructing unsupported values.
2. Build per-season M0 table: archived reference-label value/provenance status,
   estimated onset, declaration week, onset error, delay (clearly defined),
   misses and support flags. Declaration availability must be demonstrated.
3. Build M1 peak errors by origin and lead-to-observed-peak. Define observed
   peak with a reproducible tie rule; partial 2025-26 cannot certify a full-season
   peak. Report it separately/censored. Inspect phase/week coordinates.
   Include availability/failures and denominators, not only successful rows.
4. Compare saved M1-only vs repaired PAGe on exact matched keys, h2 0:12 primary,
   h1 0:12 secondary and full-season supplementary. Trial-weighted NLL within
   season then equal-season means. Separate forecast availability from scores.
   Include descriptive per-season deltas. No p-values or inferential claims.
5. Retain private weekly rows in gitignored private/. Public summary tables
   should use aggregate errors/availability, hashes and explicit limitations.
   Save elapsed runtime and source/input RDS hashes; do not copy private data
   into repo-tracked outputs. Add minimal meaningful synthetic checks for key
   uniqueness, horizon/target matching, peak ties/censoring and denominator
   weighting. Style new R code with cache disabled. Run report and tests.
6. Write concise handoff with files, commands, checks, exact model/route,
   call count if available, conclusions and remaining uncertainty.

Acceptance: all 11 seasons represented; no duplicates or silently lost failures;
stable scoring definitions; partial season visibly handled; runnable script;
origin/declaration distinction and label uncertainty explicit; parent can
independently recompute one season. Stop on inaccessible inputs or ambiguous
coordinates that cannot be resolved from direct source evidence.
