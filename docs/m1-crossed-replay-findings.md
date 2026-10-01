# M1 crossed replay findings — Stage 1 gate

Date: 2026-09-19. This is a reproduction result only. No package source was
changed, and Stages 2 and 3 were not run.

## Verdict

**FAIL — the candidate historical source tree does not reproduce the archived
v16 cache row-for-row.** Therefore it cannot be used to attribute the current
M1 regression to code versus data. The crossed 2×2 comparison is prohibited by
the replay brief's Stage 1 gate.

## Controlled inputs

- Source tree: detached `741bc73f351232571f3d540fe7449596f63e8413`, the last
  commit before the cache timestamp.
- Archived cache: `align_multi_cache.rds`, read only.
- M0 parameters: archived `stage1_tuning.rds`, read only.
- M1 configuration: `k_ref = 25`, `slope_weight = 8`, `slope_window = 6`,
  `multi_temperature = 0.25`, `template_shift = 0`,
  `align_rise_weight = 1`, `align_peak_decay = 0.3`,
  `align_trough_weight = 0.1`, `peak_weight_boost = 3`,
  `peak_weight_decay = 0.3`, `buffer_weeks = 5`, legacy timing.
- The manual-label vector was taken from the cache's per-season `iWeek_true`
  values, so it matches the artifact's recorded coordinate convention.

The recovered input was used in memory only and was not retained.

## Recovered-snapshot invariants

All required reconstruction checks passed:

- 4,689 embedded reference rows and 521 unique season-week keys.
- Each season appears in exactly nine reference folds.
- Repeated `y`, `N`, and date values agree at every repeated key.
- Replay fold membership agrees with the archive in all 10 of 10 folds.

## Row-level result

| Check | Result |
|---|---:|
| Archived parameter rows | 334 |
| Replay parameter rows | 337 |
| Joined rows | 334 |
| Archived rows missing from replay | 0 |
| Replay-only rows | 3 |
| Matching reference-fold memberships | 10 / 10 |

The replay has an NA-versus-finite mismatch in every required numeric
alignment field: `tau`, `delta`, `a`, `b`, `t_peak`, `t_peak_lo`,
`t_peak_hi`, and `peak_weekF`. `anchorWeek` is the sole numeric field that
matches exactly.

Required discrete-field mismatch counts over the 334 matched keys are:

- `peak_passed`: 196
- `fallback_reason`: 334
- `iWeek_hat`: 98
- `allow_scale`: 334
- `delta_on`: 334
- `n_train`, `iWeek_true`, and `n_obs`: 0

This is not a near-exact replay. It localizes the unresolved provenance problem
to source/configuration/runtime behavior before any code-versus-data attribution
can be made.

## Consequence

Do not run Stage 2, Stage 3, an M1 retune, or an M2 integration experiment from
this result. The next valid investigation is to identify the exact writer
environment or another source/configuration candidate that reproduces all 334
archived rows under the recovered snapshot; only then can a crossed comparison
separate code from data.
