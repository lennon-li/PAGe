# BCC runbook — strict full nested LOSO ± N

This directory is an isolated research runner. It does **not** modify canonical v3, the weekly API route, model registries, or production artifacts.

## Scientific route

`research_m1_offset_subset_nhistory`

Arm A is the ordinary full M1-offset subset M2 procedure. Arm B is the same procedure with optional N-history. This is separate from the canonical exact-A1 experiment and from the prospective A1+EXP050 shadow.

The locked design authority is:

`artifacts/m2-a-full-ntrend-nested-loso-v1/liz_astra_nested_loso_design.md`

The independent review that blocked the old procedure should also travel with the bundle when available.

## Required source checkout

The runner expects a sibling or explicitly named PAGe source tree. The locally validated source was:

- branch: `agent/m1-v2-from-first-principles`
- HEAD: `cbac85797da92a08fd445d38380a4d85d64a3f1a`

The currently pushed parent `6c64ce8361c5d14250205ffb1280d6ed0d8e1c4d` is also acceptable for this experiment: `PAGe/R/**` and `2026/run_weekly_shadow_release_v5.R` are unchanged between `6c64ce8` and `cbac857`; the latter commit only adds the separate probability API-side work. Gate 0 records the actual BCC source identity and hashes before fitting.

Set `PAGE_NHISTORY_CODE_ROOT` only if the canonical checkout is not the launcher root. Set `PAGE_NHISTORY_AUTHORITY_ROOT` to the directory containing the locked authority artifacts.

The canonical code checkout and authority-artifact location are intentionally decoupled. The four authority files are Git-ignored, so `bcc-source-overlay/` supplies them with SHA-256 checks. The launcher installs missing copies or verifies existing copies under `PAGE_NHISTORY_AUTHORITY_ROOT` and refuses to overwrite a mismatch. Gate 0 separately hashes the current code checkout and every authority before any full search.

## What is implemented

The controller enforces:

- 11 principal seasons and four predeclared exclusions;
- strict singleton/pair/triple upstream exclusions;
- local M0 selection and M1 reference/hyperparameter rebuild within each legal allowed set;
- no evaluated-row manual timing labels in feature construction;
- causal origin-time M1 peak/CI fields for stage B;
- exact keyed t-4..t, week-8 and target requirements;
- identical common ledgers across OFF and all N candidates;
- the 192-row ordinary M2 stage-A grid and 10 N options;
- unordered-pair sharing of deterministic stage-A training sets (105,600 initial fits instead of 211,200);
- adaptive stage B from the top two stage-A bases per outer/N option;
- ordinary phase-weighted M2 selection and separate equal-week/equal-season N selection;
- the paired one-SE N selector with OFF simplicity preference;
- the all-off M1 robustness comparator and explicit fallback;
- two bounded ordinary-axis boundary rounds for k_z/k_u/k_d using the predeclared practical-gain caps;
- immutable checkpoint keys, atomic RDS writes, resume validation and source/protocol/input hashes;
- outer feature ledgers with y/N truth physically removed before prediction;
- all outer predictions sealed before outer truth is joined for scoring;
- read-only canonical v3 source protection hashes.

Stage-B `k_tau` is a fixed finalist axis `{0,3,4,5}`. It is not adaptively expanded because the governed practical-gain cap contract names the ordinary subset axes k_z/k_u/k_d (plus the structural intercept), not k_tau.

## BCC prerequisites

R packages checked by the launcher:

`digest`, `jsonlite`, `mgcv`, `gamm4`, `future`, `furrr`

Every numerical library is forced to one thread per R worker:

```bash
OMP_NUM_THREADS=1
OPENBLAS_NUM_THREADS=1
MKL_NUM_THREADS=1
VECLIB_MAXIMUM_THREADS=1
NUMEXPR_NUM_THREADS=1
```

The launcher defaults to 32 workers. It first caps to the visible scheduler CPU allocation (`SLURM_CPUS_PER_TASK`, `SLURM_CPUS_ON_NODE`, or `PBS_NP`), then caps so that at most 65% of the smallest visible memory allocation (Slurm, cgroup, or physical RAM) is budgeted assuming `PAGE_MIN_MB_PER_WORKER=1200` MB. Override that memory estimate only after measuring the BCC smoke.

Recommended first BCC allocation: 32–48 CPU cores with at least ~64–96 GB RAM. If the node is larger and the smoke shows comfortable memory use, `PAGE_WORKERS=64` is supported.

## Commands

From the canonical `PAGe` checkout on `dev/n-history`:

```bash
export PAGE_NHISTORY_CODE_ROOT=/path/to/PAGe PAGE_NHISTORY_AUTHORITY_ROOT=/path/to/page-authorities
export PAGE_WORKERS=48
bash scripts/launch_m2_nhistory_bcc_v2.sh prepare
```

`prepare` reruns Gate 0, Gate 1, Gate 2 and the dry-run plan on the BCC node. It launches no Gate-3/full search.

Then build every strict upstream cache and immutable ledger:

```bash
export PAGE_NHISTORY_CODE_ROOT=/path/to/PAGe PAGE_NHISTORY_AUTHORITY_ROOT=/path/to/page-authorities
export PAGE_WORKERS=48
bash scripts/launch_m2_nhistory_bcc_v2.sh gate3
```

Gate 3 is resumable. Expected completed counts are 231 upstream artifacts, 616 replay contexts, 55 pair ledgers and 11 outer ledgers.

To launch the complete search after Gate 3 passes:

```bash
export PAGE_NHISTORY_CODE_ROOT=/path/to/PAGe PAGE_NHISTORY_AUTHORITY_ROOT=/path/to/page-authorities
export PAGE_WORKERS=48
bash scripts/launch_m2_nhistory_bcc_v2.sh full
```

The explicit `full` argument is treated as authorization for Gate 4/5 and sets `PAGE_FULL_LOSO=YES` only after Gates 0–3 pass.

For a detached shell when the cluster policy permits it:

```bash
nohup env PAGE_NHISTORY_CODE_ROOT=/path/to/PAGe PAGE_NHISTORY_AUTHORITY_ROOT=/path/to/page-authorities PAGE_WORKERS=48 \
  bash scripts/launch_m2_nhistory_bcc_v2.sh full \
  > bcc-full-nested-loso-v2.nohup.log 2>&1 &
```

If BCC uses a batch scheduler, request one node and set the scheduler CPU allocation equal to `PAGE_WORKERS`; do not add nested BLAS/OpenMP threads.

## Monitoring

```bash
bash scripts/status_m2_nhistory_bcc_v2.sh
```

Key progress counts:

- `upstream_rds`: target 231
- `context_rds`: target 616
- `stage_a_groups`: target 550 (=55 unordered pairs × 10 N options)
- stage-B/boundary group counts are adaptive

The controller is resumable. Rerun the same command after an interruption; hash-valid checkpoints are reused and invalid/corrupt checkpoints are recomputed.

## Important outputs

Gate artifacts:

- `preflight_report.json`
- `stage_b_contract.csv`
- `smoke_manifest.json`
- `gate3_report.json`
- `gate4_report.json`
- `gate5_report.json`

Inner search:

- `inner/stage_a_scores.rds`
- `inner/stage_b_scores.rds`
- `inner/inner_fold_scores.rds`
- `inner/ordinary_selection.csv`
- `inner/paired_n_selection.csv`
- `inner/selected_n_by_outer_horizon.csv`
- `inner/selected_config_by_outer_horizon.csv`
- `inner/boundary_report.csv`

Outer replay:

- `outer/sealed_predictions/outer_predictions_sealed.csv`
- `outer/SEALED_COMPLETE`
- `outer/outer_predictions_scored.csv`
- `outer/outer_per_season_metrics.csv`
- `outer/paired_outer_differences.csv`
- `outer/selection_frequency.csv`

Terminal markers:

- `summary.md`
- `sha256sums.csv`
- `COMPLETE`

## Stop conditions

Do not interpret a partial run as scientific evidence. Stop and investigate if any of the following occurs:

- Gate 0/1/2 is not PASS on BCC;
- Gate 3 does not produce exactly 231 upstream sets and 616 replay contexts;
- pair/triple exclusion provenance differs from the declared context;
- causal peak/CI fields are absent or invalid;
- candidate row/weight hashes differ within a comparison;
- the all-off robustness baseline is incomplete;
- any selected N option lacks all 10 inner validation seasons;
- canonical protection hashes change;
- outer prediction files contain `y_target` or `N_target` before `SEALED_COMPLETE`.

Boundary candidates that remain at an improving edge after the two predeclared rounds are retained but explicitly labeled `unresolved_boundary_cap`; they must not be described as bracketed optima.

## Governance

This run is research only. A favorable result does not promote N, alter canonical v3, update the API default, or modify deployment registries. The fixed-A1 nested N result, this full M1-offset subset result, canonical v3, and the prospective A1+EXP050 shadow remain distinct estimands.
