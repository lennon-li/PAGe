# PAGe workflow status map

Last reconciled: 2026-07-28. This map makes the discoverable entry points
explicit without deleting historical research. Status describes intended use,
not evidence that a private-data run completed. In particular, reported
historical M2 LOSO is conditional on globally selected M0/M1 settings; it is
not fully nested validation. Untouched 2025-26 is the intended confirmatory
evaluation. No completed replay, acceptance decision, post-promotion refit, or
registry promotion is preserved in this repository.

## Operational workflow

| Entry point or family | Status | Use and safe replacement |
|---|---|---|
| High-level package API: `load_flu_hist()`, `prepare_surveillance_data()`, `train_pipeline()`, `run_pipeline()`, `run_prospective_pipeline()`, `replay_season_holdout()`, `check_promotion()`, `verify_promotion_evidence()` | canonical | The supported interface. Supply authorized surveillance data through an explicit `load_flu_hist(path)` argument or `PAGE_FLU_HIST_FILE`; observations are not bundled. Use `simulate_flu_seasons()` for public synthetic examples. A bare promotion report cannot release a holdout. |
| Frozen runtime: `run_pipeline(..., mode = "frozen")` and `run_prospective_pipeline(..., mode = "frozen")` | canonical | Canonical deployment behavior: a pre-trained/frozen kit with online updates. |
| `scripts/acceptance/replay_2025_26.R` | canonical | Manual, opt-in confirmatory replay and decision-evidence entry point. It requires authorized data plus candidate and incumbent kits, verifies both excluded `2025-26`, and writes private replay/bundle files separately from aggregate audit evidence. Canonical kit identity is strict by default; only a legacy incumbent may use the explicit compatibility option. Reusing a run ID fails. Its execution and any real-data output are unverified. |
| `season2526/run_retrain_venkata.R` | canonical | Post-acceptance fixed-spec refresh only. It requires the passing decision bundle, its manifest, the exact candidate and incumbent kits, and authorized data, then constructs artifact-bound verified evidence. Use `--preflight-only` first. Private model output and disclosure-safe manifests are separate and never overwritten. No completed real-data refit is preserved here. |
| `scripts/promotion/promote_post_refit.R` | canonical | Final immutable registration step. It validates the complete acceptance-to-refit hash chain and kit identities, supports `--preflight-only`, writes a private promoted kit and separate disclosure-safe deployment manifest, and refuses destination collisions. No completed promotion is preserved here. |
| `load_promoted_kit()` | canonical | Verified deployment loader. It requires explicit immutable kit and deployment-manifest paths, checks their SHA-256/spec/training-season binding, and has no mutable `current` discovery path. |
| `mode = "weekly_refit"`, `nested_loso_m2_eval_weekly_refit()`, and older weekly-refit explanations | research-only | Compatibility/comparison behavior, not the validated production path. Use frozen mode for deployment; retain weekly refit only when explicitly studying compatibility behavior. |

## Historical and research workflows

| Entry point or family | Status | Why / safe replacement |
|---|---|---|
| `scripts/fresh_run/00_shared.R` and stages `01_m0.R` through `07_compare.R` | research-only | Preserved historical/research workflow. It loads private local files and has no promotion chain. Use the high-level API and governed release workflow for new production work. |
| `scripts/fresh_run/04e_m2_loso_v16.R`, `04f_m2_loso_v16_expand.R`, and `05b_m2_production_v16.R` | research-only | v16 research and kit-building history. Private result artifacts are absent, and the builder does not itself establish a promoted immutable production artifact. Use `train_pipeline()` followed by the governed release workflow. |
| `scripts/fresh_run/04h_m2_loso_v17_adaptive_ba.R`, `04k_m2_loso_v18_spread.R`, `03b_m1_kappa_sweep.R`, and other experiment-specific fresh-run stages | research-only | Retained for hypotheses and comparisons; they are not deployment instructions. Use the canonical API for production work. |
| `scripts/run_nested_loso_v14.R`, `run_nested_loso_v14b.R`, and `_rebuild_m2_production_v14.R` | superseded | Historical v14 search/build path. Do not rebuild a kit from it; use the canonical API and governed release workflow. |
| `scripts/run_nested_loso_v15.R`, `run_nested_loso_v15_postfix*.R`, `_rebuild_m2_production_v15*.R`, and `scripts/fresh_run/05_m2_production.R` | superseded | Historical v15/v15-postfix builders and evaluation paths. Do not treat their saved filenames or reported metrics as current deployment evidence. Use the canonical API and governed release workflow. |
| Other root tuning, diagnostic, and `run_nested_loso_v2`--`v13*` scripts | superseded | Historical investigation scripts, retained for provenance. Use the high-level API unless reproducing a specifically scoped research result. |
| Root `task.md` | superseded | Historical M0 tuning task record, now clearly labelled. It is not an implementation plan or source of current parameters. |

## Governed release workflow

The canonical sequence is frozen candidate/incumbent acceptance excluding
`2025-26`, immutable decision evidence, fixed-spec refresh including `2025-26`,
then immutable registry publication and verified loading. The exact operator
commands and private/audit boundaries are in
[`deployment-workflow.qmd`](deployment-workflow.qmd).

Retuning is a pre-acceptance development activity. Any change made after
viewing the holdout starts a new development cycle and cannot inherit the
previous decision. By contrast, the post-acceptance refresh retains the
accepted configuration and only releases the holdout into its training data.

`season2526/reproduce_retrain.qmd` describes the acceptance-to-refresh
subsequence. Its pre-existing rendered HTML is stale and is not evidence that a
private-data run completed.

## Rendered documentation

The checked-in `docs/*.html` files are generated snapshots, not canonical
instructions. Their source QMD/Markdown and this status map govern current use.
Some HTML predates the audit and may retain retired numbers or weekly-refit
language. Do not re-render them until their sources and verified private-data
evidence have been reconciled. In particular, generated HTML does not establish
that a private-data replay, refit, or numeric result occurred.

## Classification limits

This map intentionally does not choose between conflicting M1 peak-MAE values
or reported M2 NLL values. Those require the corresponding private artifacts,
provenance, and reproducible result summaries.
