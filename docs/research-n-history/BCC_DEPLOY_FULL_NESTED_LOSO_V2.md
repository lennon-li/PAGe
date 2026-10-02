# BCC deployment — strict full nested LOSO v2

Status: **READY_FOR_GATE3 / READY TO DEPLOY**

Run ID: `m2-a-full-ntrend-v2-locked-20260930`

Route: `research_m1_offset_subset_nhistory`

Production eligible: `FALSE`

This package runs the strict full M1-offset-subset M2 ± N research experiment. It does not modify canonical v3 runtime/deployment state.

## Required layout

Place the two checkouts as siblings:

```text
<work-parent>/
  PAGe-m1-v2/      # PAGe source checkout
  PAGe-m2-a-full/  # this experiment package
```

The default source path is `../PAGe-m1-v2`. Override with `PAGE_NHISTORY_SOURCE_ROOT=/absolute/path/to/PAGe` if needed.

The source checkout must contain `PAGe/DESCRIPTION`. The launcher verifies/installs the bundled Git-ignored authority files from `bcc-source-overlay/` by SHA-256 and refuses to overwrite mismatched existing files.

## R dependencies

Required packages:

```text
digest
jsonlite
mgcv
gamm4
future
furrr
```

The launcher checks these before any scientific work.

## Pre-deployment evidence

Current local evidence:

- Gate 0: `PASS`
- Gate 1 contract/adversarial tests: `19/19 PASS`
- Gate 2 sealed-contract smoke: `PASS`
- strict pair exclusion: `TRUE`
- strict triple exclusion: `TRUE`
- real future invariance: `TRUE`
- OFF identity: `TRUE`
- outcome-free prediction: `TRUE`
- 1-worker vs 8-worker max prediction delta: `0`
- BCC dry-run status: `READY_FOR_GATE3`
- exclusion sets: `231`
- causal replay contexts: `616`
- unordered inner training sets: `55`
- Stage-A grid: `192 × 10 N options`
- initial Stage-A fits with pair symmetry: `105,600`
- Stage-B upper bound before deduplication: `15,400`

The launcher reruns Gates 0–2 on BCC before Gate 3 or the full search.

## Recommended deployment

From `PAGe-m2-a-full`:

```bash
export PAGE_WORKERS=32
bash scripts/launch_m2_nhistory_bcc_v2.sh prepare
```

This reruns Gate 0, Gate 1, Gate 2 and the BCC dry run only. It performs no Gate-3 cache build and no full search.

Then build the full strict upstream/cache layer:

```bash
export PAGE_WORKERS=32
bash scripts/launch_m2_nhistory_bcc_v2.sh gate3
```

Gate 3 is resumable. It builds the 231 strict upstream exclusion artifacts, 616 causal replay contexts, pair ledgers, and sealed outer ledgers.

After Gate 3 reports PASS, launch the full search:

```bash
export PAGE_WORKERS=32
bash scripts/launch_m2_nhistory_bcc_v2.sh full
```

`full` is the explicit human authorization for Gates 4–5. The launcher sets `PAGE_FULL_LOSO=YES` only after Gates 0–3 pass.

The launcher uses one BLAS/OpenMP thread per worker and automatically caps the requested worker count against visible scheduler CPUs and a 65% RAM guard. If BCC memory permits, request 48 or 64 workers; the guard will reduce the count when required.

## Slurm

A submit-ready template is provided:

```bash
sbatch deploy/bcc_m2_nhistory_full_v2.sbatch
```

It requests 32 CPUs and uses the same launcher. Adjust only scheduler resource directives if BCC policy requires different limits; do not change the scientific protocol.

## Status

From another shell/job:

```bash
bash scripts/launch_m2_nhistory_bcc_v2.sh status
```

The status command reports current gate status and checkpoint counts. Expected full-run counts begin with:

```text
upstream_rds=231 / 231
context_rds=616 / 616
stage_a_groups=550 / 550
```

Stage A has 550 grouped jobs because each of 55 unordered season pairs is evaluated under 10 N options; each grouped job contains the relevant spec fits.

## Resume behavior

All major outputs are hash-bound checkpoints. Re-run the same `gate3` or `full` command after interruption. Valid checkpoints are reused and corrupt/mismatched checkpoints are rejected/recomputed.

Do not use `--force` unless intentionally invalidating the cache.

## Scientific locks

The run is locked to:

- canonical observation authority: `artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv`
- timing authority: `artifacts/v3-joint-timing-contract-v4/timing_contract_v4.csv`
- principal 11-season universe in `protocol.json`
- strict singleton/pair/triple upstream exclusion
- no evaluated-row manual timing labels in predictors
- full 192-spec Stage-A M2 grid
- ten N options including OFF
- Stage B with causal peak/CI fields
- two boundary-expansion rounds, `max_specs=64`
- paired one-SE N-option selection
- sealed outer predictions before outer truth scoring

Do not edit these after results are visible.

## Output

Default output root:

`artifacts/m2-a-full-ntrend-nested-loso-v2/`

Terminal success requires:

```text
gate3_report.json : PASS
gate4_report.json : PASS
gate5_report.json : PASS
COMPLETE
```

Primary final outputs include:

```text
inner/ordinary_selection.csv
inner/paired_n_selection.csv
inner/selected_n_by_outer_horizon.csv
inner/selected_config_by_outer_horizon.csv
outer/sealed_predictions/outer_predictions_sealed.csv
outer/outer_predictions_scored.csv
outer/outer_per_season_metrics.csv
outer/paired_outer_differences.csv
outer/selection_frequency.csv
summary.md
sha256sums.csv
```

## Important

This is research evidence only. No production route, canonical release, weekly API, or deployment registry is modified or promoted by this run.
