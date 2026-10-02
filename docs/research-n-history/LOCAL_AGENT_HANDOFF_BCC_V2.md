# Local-agent handoff: PAGe M2-A full nested LOSO v2

Use this handoff on BCC (preferred for compute) or Asgard for verification only.

## Objective

Continue the isolated research route `research_m1_offset_subset_nhistory`. Do not alter canonical v3, production/API routing, deployment registries, or promote N automatically. Do not commit or push unless explicitly authorized.

## Frozen local evidence

Read first:

- `artifacts/m2-a-full-ntrend-nested-loso-v2/readiness_20260930.md`
- `artifacts/m2-a-full-ntrend-nested-loso-v2/preflight_report.json`
- `artifacts/m2-a-full-ntrend-nested-loso-v2/gate1_manifest.json`
- `artifacts/m2-a-full-ntrend-nested-loso-v2/smoke_manifest.json`
- `artifacts/m2-a-full-ntrend-nested-loso-v2/bcc_dry_run.json`

Expected source hash:

`3b613a1d4c09bf7aad8415e96a4d46af2e215c10d699a16eb912dfabdaf046ed`

Expected protocol hash:

`fbe6fd6c6a8c27486e97d557e5c16c79543d7e2a6f817c290c40b49023a6edf1`

## BCC sequence

Set one numerical thread per worker:

```bash
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export PAGE_WORKERS=32
```

From the extracted `PAGe-m2-a-full` directory, with the sibling PAGe source checkout available as `../PAGe-m1-v2` (or set `PAGE_NHISTORY_SOURCE_ROOT` explicitly):

### 1. BCC prepare only

```bash
bash scripts/launch_m2_nhistory_bcc_v2.sh prepare
```

Require PASS for Gate 0, Gate 1, Gate 2, and dry-run. Confirm the newly generated Gate 0/1/2 source and protocol hashes agree with one another. Do not continue if any gate fails or hashes differ.

### 2. Gate 3 only

```bash
bash scripts/launch_m2_nhistory_bcc_v2.sh gate3
```

Require `artifacts/m2-a-full-ntrend-nested-loso-v2/gate3_report.json` status `PASS`, exactly 231 upstream sets, 616 replay contexts, 55 pair ledgers, 11 outer ledgers, strict pair/triple exclusion true, evaluated labels unused, and sealed outer outcomes. Inspect resource usage before increasing workers.

### 3. Full Gates 4–5 only after Gate 3 review

```bash
export PAGE_FULL_LOSO=YES
bash scripts/launch_m2_nhistory_bcc_v2.sh full
```

The launcher reruns pre-gates and resumes Gate 3 safely before entering full search. Do not bypass `PAGE_FULL_LOSO=YES`.

## Slurm option

If the extracted bundle includes `deploy/bcc_m2_nhistory_full_v2.sbatch`, use it only after the prepare/Gate-3 review above, or edit/copy it to invoke `prepare`/`gate3` first. Initial allocation is 32 CPUs and 64G; the launcher also applies a 65% visible-memory worker guard.

## Stop conditions

Stop and report rather than adapting the scientific protocol if any of the following occurs:

- Gate hash mismatch or stale gate evidence.
- Missing/invalid causal Stage-B peak or CI fields.
- Empty score joins, duplicate normalized score keys, or zero complete validation seasons.
- No complete candidate fits for an ordinary-selection context.
- Serial/parallel prediction delta above `1e-10`.
- Canonical protection hash changes.
- Gate 3 manifest counts differ from the frozen plan.
- Boundary remains unresolved after the frozen two-round cap; mark `unresolved_boundary` and do not extend the search.

Full LOSO outputs are research evidence only.
