# BCC deployment — strict full nested LOSO v2

Status: READY FOR BCC GATE 3 / FULL CONTROLLER

Run ID: `m2-a-full-ntrend-v2-locked-20260930`

Expected locked hashes:

- protocol: `fbe6fd6c6a8c27486e97d557e5c16c79543d7e2a6f817c290c40b49023a6edf1`
- source: `f53fb39d7812a62bfee81fbb75d17f7809892ac113073969107720a516e9b68c`
- canonical protection: `ab94b974625463e2d2b3d402e7504b4af296d2b5a2f8cf6df801ba03e71c3be1`

Validated locally:

- Gate 0: PASS
- Gate 1: PASS, 15 checks
- Gate 2: PASS, 1-worker vs 8-worker prediction max delta `0`
- dry-run: `READY_FOR_GATE3`
- strict exclusion sets: 231
- replay contexts: 616
- unordered outer/inner pairs: 55
- Stage-A M2 specs: 192
- N options: 10
- initial Stage-A fits after pair symmetry: 105,600
- Stage-B maximum extra fits before dedup: 15,400

The launcher reruns Gates 0–2 on BCC before doing any full work. Gate 3 is resumable. Full mode explicitly authorizes Gates 4–5 only after Gate 3 succeeds.

## Required layout

The scratch research checkout and the canonical PAGe source checkout should be siblings, e.g.:

```text
/home/yeli/repos/PAGe
/home/yeli/repos/PAGe
```

If the canonical code checkout is elsewhere, set `PAGE_NHISTORY_CODE_ROOT`. Set `PAGE_NHISTORY_AUTHORITY_ROOT` separately when the locked authority artifacts are stored outside that checkout.

The bundled `bcc-source-overlay/` contains the Git-ignored locked observation/timing/M0 authorities and is SHA-verified by the launcher before Gate 0.

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

The launcher checks these before execution.

## Recommended BCC launch

From the scratch checkout:

```bash
cd /home/yeli/repos/PAGe

export PAGE_NHISTORY_CODE_ROOT=/home/yeli/repos/PAGe
export PAGE_NHISTORY_AUTHORITY_ROOT=/path/to/page-authorities
export PAGE_WORKERS=48
export PAGE_MIN_MB_PER_WORKER=1200

./scripts/launch_m2_nhistory_bcc_v2.sh full
```

The launcher forces these to one thread per worker:

```text
OMP_NUM_THREADS=1
OPENBLAS_NUM_THREADS=1
MKL_NUM_THREADS=1
VECLIB_MAXIMUM_THREADS=1
NUMEXPR_NUM_THREADS=1
```

It also caps `PAGE_WORKERS` against the scheduler CPU allocation and a 65% visible-memory guard. Request 48 workers initially; if the node allocation is smaller the launcher will reduce automatically.

For a staged launch instead:

```bash
./scripts/launch_m2_nhistory_bcc_v2.sh prepare
./scripts/launch_m2_nhistory_bcc_v2.sh gate3
./scripts/launch_m2_nhistory_bcc_v2.sh full
```

`gate3` is safe to resume. `full` reruns validation and Gate 3 before entering the scientific search.

## Status

In another shell:

```bash
cd /home/yeli/repos/PAGe
./scripts/launch_m2_nhistory_bcc_v2.sh status
```

Logs are written to:

```text
artifacts/m2-a-full-ntrend-nested-loso-v2/logs/
```

Primary output directory:

```text
artifacts/m2-a-full-ntrend-nested-loso-v2/
```

## Stop conditions

Do not bypass a gate. Stop if BCC reports any of the following:

- locked hash mismatch;
- exclusion/poison-label test failure;
- serial/parallel determinism failure;
- missing causal Stage-B peak/CI support;
- incomplete/duplicate validation keys;
- canonical protection hash drift;
- Gate 3 cache validation failure.

No production/canonical v3 deployment changes are authorized by this experiment.
