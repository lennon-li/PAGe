# N-history Stage-A cache assembly hardening — 2026-10-02

## Context

The strict full nested LOSO experiment previously progressed through the sealed upstream/ledger gates but did not reach decisive outer scoring because the Stage-A score-cache assembly path failed downstream. The large failed BCC run artifacts are not available in the current Asgard session, so this change does not claim to reproduce the original exception byte-for-byte.

The current runner already validated each score-group checkpoint for schema, requested spec-ID coverage, duplicate `(validation_season, horizon, spec_id)` rows, pair identity, and N-option identity. That left one important class of partial-cache corruption undetected: a checkpoint could contain every requested `spec_id` while silently missing one or more validation-season/horizon rows for only a subset of specs.

Such a checkpoint is individually non-empty and appears to cover every requested spec, but it is not rectangular. The failure would surface only later during Stage-A/B selection or after multiple groups were assembled.

## Change

`run_m2_nhistory_full_nested_loso_v2.R` now enforces two additional fail-closed invariants.

### Per-group rectangular coverage

Within each `(pair_key, n_option)` score-group cache, every requested specification must have the same set of `(validation_season, horizon)` rows.

A truncated spec-specific checkpoint now fails immediately with:

`Score-group cache has non-rectangular validation/horizon coverage ...`

### Cross-group assembled-layer validation

After all valid score-group caches are loaded and row-bound, the assembled score layer must satisfy:

1. exact requested `(pair_key, n_option, spec_id)` coverage;
2. no duplicate `(pair_key, n_option, spec_id, validation_season, horizon)` rows;
3. rectangular validation/horizon coverage within every assembled `(pair_key, n_option)` group.

The assembled layer is validated before `stage_a_scores.rds` or later Stage-B/selection artifacts are written.

## Regression coverage

The built-in `--mode=self-test-score-cache` now additionally verifies that:

- a complete two-spec/two-horizon cache passes;
- a cache retaining both spec IDs but missing one horizon for one spec fails;
- a valid multi-group assembled layer passes;
- a duplicated assembled score row fails.

The existing parallel-worker fail-closed self-test remains unchanged.

On Asgard after the change:

- `--mode=self-test-score-cache`: PASS
- `--mode=self-test-selection`: PASS
- Gate 1 devcheck: PASS, 30 checks
- Gate 2 bounded smoke devcheck: PASS
- Gate 2 strict pair exclusion: PASS
- Gate 2 strict triple exclusion: PASS
- Gate 2 real-future invariance: PASS
- Gate 2 all-off identity: PASS
- Gate 2 outcome-free prediction: PASS
- Gate 2 score-cache self-test: PASS
- Gate 2 maximum serial/parallel prediction delta: 0

Devcheck source hash: `58541c7f5ffb863cfd740caf1f1c31e4ba2a8c7e5c16a683571d686ff8431e3b`  
Devcheck protocol hash: `fbe6fd6c6a8c27486e97d557e5c16c79543d7e2a6f817c290c40b49023a6edf1`

## Governance

No production PAGe runtime, model artifact, public API, or deployment route is changed.

The strict full nested LOSO runner still requires clean-source Gate 0 evidence and explicit `PAGE_FULL_LOSO=YES` authorization before the full run. The new source cannot legitimately regenerate Gate 0–5 evidence until these research changes are committed, so no full-run result or N-history performance claim is made here.

The next governed step is to commit the research patch, regenerate Gates 0–2 against the new source hash, execute Gate 3, and resume the full nested LOSO experiment using the hardened Stage-A cache boundary.
