# Commit plan, 2026-09-15 working tree (189 paths)

Branch `agent/page-governance-audit`, already 11 commits ahead of origin before this session.
Nothing is committed until Lennon approves each batch. Batches are ordered so the tree builds and tests
pass after every one; each batch is staged by explicit path (never `git add -A`).

Preconditions for batch 1-3: Liz APPROVE (or APPROVE WITH NOTES accepted by Lennon), full installed
`test_dir` 0 failures on the exact staged tree, both runner `--preflight` green, builder `--dry-run` green.

## Batch 0 - hygiene (no code)
Add to `.gitignore`: `output/`, `r-lib/`, `.playwright-cli/`, `.page_terminal_watch.sh`,
`.page_watchdog_runtime.sh`, `abstracts.txt`, `articles.txt`, `semanticscholar.txt` (21 MB + 2.6 MB + 2.7 MB of
build/scratch output that must never enter history). Verify `git status` no longer lists them.

## Batch 1 - package core, new cycle (the reviewed work)
`PAGe/R/*.R` (season_calendar, forecast_contracts, scoring_weights, training_audit, parallel_backend,
m0_*, m1_*, m2_*, nested_season_evaluation, pipeline_*, evaluation_gates, stage_contracts, getCurrentD),
`PAGe/NAMESPACE`, `PAGe/man/*.Rd`, `PAGe/tests/testthat/*`.
Message: July-start seasons + no wraparound, Phase 1 correctness fixes, fully nested M2 gate
(`gate_nesting`), page-v2 scoring weights, M1-guided M2 terms, forecast-availability contract.

## Batch 2 - runners and operational scripts
`2025/run_2025_ultimate.R`, `2025/launch_2025_ultimate.sh`, `2025/watch_2025_ultimate.sh`, `2026/**`
(runner, weekly forecast runner, launcher, watchdog), `scripts/build_flu_hist_orvt.R`,
`scripts/equivalence_probe.R` (if present), `scripts/run_m1_reproduction_venkata.R`,
`scripts/launch_m1_reproduction_venkata.sh`, `scripts/watch_m1_reproduction.sh`.
Message: explicit new-cycle recipe (M1 fixed 30/16, M2 192 specs, gate_nesting full), weekly operations,
ORVT builder.

## Batch 3 - docs for the new cycle
`docs/season-calendar.md`, `docs/m2-fix-plan-2026-09-15.md`, `docs/orvt-data-update.md`,
`docs/weekly-operations-2026-27.md`, `docs/final-kit-2026-27-runbook.md`, `docs/validation-and-final-kit.md`,
`docs/tuning-playbook.md`, `docs/workflow-status.md`, `docs/stage-api-map.md`, `docs/commit-plan-2026-09-15.md`,
`CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`.

## Batch 4 - manuscript (ming-oracle's scope)
`manuscript/**` including the new drafts and Wei's status banners. Commit only after ming-oracle confirms the
batch contents in the collab channel; it owns these files.

## Batch 5 - older season scripts and audit leftovers (pre-session work)
`2016/`, `2017/`, `2018/*`, `2019/`, `2022/`, `2025/run_2025_cycle.R`, `2025/replay_2025_26.R`,
`2025/launch_2025.sh`, `2025/watch_2025.sh`, remaining `scripts/*`, `results/audit/holdout_reconciliation_20260902.md`,
`docs/*` not in batch 3, `PAGe/README.md`.
These predate this session; review each file briefly before staging, or leave uncommitted if unclear.

## Rules
- Stage by explicit path; `git status` after each batch; never `git add -A`.
- Never commit `/home/yeli/FLU` data, raw surveillance rows, run artifacts under `results/` (except
  `results/audit/*.md`), or installed libraries.
- Push only after Lennon approves; branch stays `agent/page-governance-audit`, no PR without approval.
