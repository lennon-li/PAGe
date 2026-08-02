# PAGe workflow status map

Last reconciled: 2026-08-01. This map makes the discoverable entry points
explicit without deleting historical research. Status describes intended use
and separately identifies local private-data evidence. Reported historical M2
LOSO remains conditional on globally selected M0/M1 settings; it is not fully
nested validation. A local frozen acceptance replay was completed for
`2025-26` under run ID `boundary-expansion-20260801T150000Z`; the candidate
failed the locked NLL gate, while horizon and phase gates passed. Its ignored
private/audit evidence is under `results/user-test/` and `results/audit/`.
No post-promotion refit or registry promotion occurred.

## Operational workflow

| Entry point or family | Status | Use and safe replacement |
|---|---|---|
| Guarded stage API: `validate_season_selection()`, `tune_*()`, `validate_*_tuning()`, `fit_*()`, `freeze_*()`, `assemble_kit()` | canonical | Preferred low-level training interface. It enforces explicit disjoint season sets, validated tuning results, frozen upstream dependencies, matching artifact identities, and guarded kit assembly. M0, then M1, then M2 must pass before proceeding. |
| `docs/tuning-playbook.md` | canonical | Grid-design and expansion guidance: boundary reports, adjacent-step expansion, valid null/constraint boundaries, stage-specific parameter tips, stopping rules, and the prohibition on post-holdout tuning. |
| `docs/long-job-supervision.md` | canonical | Long jobs use a detached zero-token watchdog and compact status records. AI involvement is limited to launch/preflight, detected exceptions, and bounded terminal review unless the user explicitly approves a monitoring cadence and token budget. |
| High-level package API: `load_flu_hist()`, `prepare_surveillance_data()`, `train_pipeline()`, `run_pipeline()`, `run_prospective_pipeline()`, `replay_season_holdout()`, `check_promotion()`, `verify_promotion_evidence()` | canonical compatibility | `train_pipeline()` now composes the guarded stage lifecycle for refresh and retune, including explicit season selection, validation gates, frozen upstream identities, and governed M2 racing full evaluation. It preserves the compatibility result shape. Supply authorized surveillance data through an explicit `load_flu_hist(path)` argument or `PAGE_FLU_HIST_FILE`; observations are not bundled. A bare promotion report cannot release a holdout. |
| Legacy stage builders: `build_m0()`, `build_m1()`, `build_m2()`, `train_m2()` | compatibility | Retained for existing callers and as underlying statistical implementations. New stage-controlled workflows should call the guarded tune/validate/fit/freeze API instead. |

The canonical `build_m2()` path enforces fold-specific label isolation:
`manual_labels_train` excludes the held-out season and
`manual_labels_test = NULL`. Checkpoints made with a held-out label available
to evaluation are not valid prospective evidence and must be recomputed.
| Frozen runtime: `run_pipeline(..., mode = "frozen")` and `run_prospective_pipeline(..., mode = "frozen")` | canonical | Canonical deployment behavior: a pre-trained/frozen kit with online updates. |
| `scripts/acceptance/replay_2025_26.R` | canonical | Manual, opt-in confirmatory replay and decision-evidence entry point. It requires authorized data plus candidate and incumbent kits, verifies both excluded `2025-26`, and writes private replay/bundle files separately from aggregate audit evidence. Canonical kit identity is strict by default; only a legacy incumbent may use the explicit compatibility option. The local boundary-expansion replay completed with a failed NLL gate; evidence is preserved but does not authorize refit or promotion. |
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
