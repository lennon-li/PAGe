# Repaired-runtime stage evidence report

Generated `2026-09-08 18:37:50 UTC` from replay root `manuscript/results/publication-repair-20260908/replay/20260908T125939`. This is a diagnostic evidence report; it did not retrain, retune, promote, or alter any kit.

## M0 definition

The estimated onset is the saved `stages$m0$iWeek_hat_locked`. The declaration week is independently recomputed as the first saved M0 row with `ignite_ok_now == TRUE`; the script asserts equality with `ign_week_locked`. Delay is declaration week minus estimated onset. Onset error is estimated onset minus the archived retrospective reference label. The ten verified labels are retrospective algorithm-defined labels, not biological ground truth. The archived `2025-26 = 19` value is shown but remains uncertified because independent source/date/hash provenance is unresolved.

## M1 peak definition

The observed peak is the earliest `weekF` among exact ties for the maximum observed positivity (`y/N`). M1 peak estimates use the saved `m1_parameters` rows and the runtime-converted `peak_weekF`; `aligned_t_peak` and `iWeek_hat` are retained as coordinate evidence. `anchorWeek` is not stored in the replay table and is not reconstructed. `2025-26` is reported as partial/right-censored: its observed-to-date peak is descriptive only, and it contributes no certified full-season peak error. The reported lead-to-peak coordinate is `observed_peak_weekF - origin_weekF`, so it is negative for origins after the observed peak.

## M1-only comparison

The M1-only comparator is the saved `m1_p` from the same upstream fitted kit. It is a pipeline-component diagnostic, not a separately retuned standalone M1 model. Scores use exact `(season, origin_weekF, lead)` matches. Forecast availability is counted from the full ledger separately from score availability. NLL is trial-weighted within season, then aggregated as an equal-season mean; no inferential tests are used.

### Primary h2, t_since 0--12

| Model | scored seasons | score rows | equal-season NLL | pooled-trial NLL | equal-season MAE |
|---|---:|---:|---:|---:|---:|
| M1-only continuation (saved m1_p) | 11/11 | 138 | 0.460079 | 0.436736 | 0.050304 |
| PAGe repaired runtime | 11/11 | 138 | 0.462821 | 0.438180 | 0.054065 |

## Reproducibility

- Replay status: `complete_diagnostic_only`; replay elapsed seconds: 1734.805131.
- Stage-report elapsed seconds: 1.80617404.
- Source CSV SHA256: `fa8add1b253944df5d853a2fb0456d7ac368657e073da0d97f909be95ca59c54`.
- Private weekly comparison rows and per-origin M1 rows are under the gitignored `private/` directory; public tables contain aggregates, availability, hashes, and limitations only.
- Synthetic checks: all passed; see `synthetic_checks.csv`.

## Deliberate limitations

The replay is conditional on the completed frozen kits and repaired runtime;it is not a new upstream nested retuning analysis. Label provenance for`2025-26`, full-season peak status for `2025-26`, and the historical executedenvironment remain unresolved. Bounds in the replay are conditionalfitted-mean bands, not full predictive distributions.

