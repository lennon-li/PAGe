# Weekly operations for the frozen 2026-27 PAGe kit

Reference for the operator who produces the weekly forecast. Status: draft
2026-09-15. This workflow applies the already frozen, validated kit to current
surveillance data. It never refits, retunes or edits the kit.

**Review before publication.** The files written under the week directory are
unreviewed model output. They are not a publication or a release. A human must
review the forecast, ignition status and provenance before anything is shared.

## Prerequisites

- A Linux host shell on the chosen host (PID 1 is `systemd` or `init`). Never
  launch from inside an agent sandbox: `setsid` cannot detach there.
- R with the PAGe dependencies, GNU coreutils, `findutils`, `procps`,
  `util-linux` (`setsid`), and Bash.
- The frozen 2026-27 kit (`final_kit.rds`) and its expected SHA-256, e.g. from
  `final_kit.sha256` produced by `2026/run_2026_27_final_kit.R`.
- Network access to the PHO ORVT feed, or an authorized local CSV.

## Runtime functions used

- `PAGe::getCurrentD(cache_dir = ...)` (`PAGe/R/getCurrentD.R:165`) fetches and
  tidies current-season PHO respiratory surveillance data. It is called, never
  reimplemented. Its provenance attributes (`source_url_or_path`,
  `retrieved_utc`, `sha256`, `last_week_end_date`) are recorded.
- `PAGe::validate_page_kit(kit, mode = "frozen")` (`PAGe/R/public_results.R:16`)
  checks the frozen kit contract.
- `PAGe::run_prospective_pipeline(...)` (`PAGe/R/pipeline_runtime.R:877`) runs
  the frozen M0 -> M1 -> M2 walk-forward for one season in `mode = "frozen"`.
  This is the exported function that applies a frozen kit to current-season
  data; the runner calls it directly and does not refit or retune.

## Environment variables

| Variable | Required | Meaning |
|---|---|---|
| `PAGE_KIT_PATH` | yes | Path to the frozen `final_kit.rds`. |
| `PAGE_KIT_SHA256` | yes | Expected 64-hex SHA-256; a mismatch fails closed. |
| `PAGE_WEEKLY_OUT_ROOT` | yes | Root for weekly run directories. |
| `PAGE_FORECAST_RUN_ID` | yes | Fresh week/run identifier (letters, digits, `.`, `_`, `-`). |
| `PAGE_FORECAST_WEEK` | no | Forecast origin weekF in [1, 53]; default is the latest observed week. |
| `PAGE_ORVT_URL` | no | ORVT CSV URL or local path; default resolves the PHO feed. |
| `PAGE_MAX_STALENESS_DAYS` | no | Refuse when the latest observed week end is older than this many days (default `21`; `skip`/`none` disables). |
| `PAGE_PACKAGE_LIBRARY` | no | Run-local library to prepend to `.libPaths()`. |
| `PAGE_WEEKLY_INSTALL_LIB` | no | Launcher-only: set `1` to install PAGe into `$run_dir/r-lib` first. |
| `PAGE_WALK_START` | no | Minimum M1 evaluation week (default `5`). |
| `PAGE_TIMING_MODE` | no | `fractional` (default) or `legacy`. |
| `PAGE_WATCH_INTERVAL` | no | Watchdog sample interval seconds (default `60`). |

`PAGE_REPO_ROOT` defaults to the parent of `2026/`.

## Operator steps

Dry run first. It verifies the kit hash and kit contract, prints the resolved
plan, and stops before fetching data or forecasting:

```bash
set -euo pipefail
export PAGE_REPO_ROOT=/home/yeli/repos/PAGe
export PAGE_KIT_PATH=/path/to/final_kit.rds
export PAGE_KIT_SHA256="$(awk '{print $1}' "${PAGE_KIT_PATH%.rds}.sha256")"
export PAGE_WEEKLY_OUT_ROOT="$PAGE_REPO_ROOT/results/weekly-2026-27"
export PAGE_FORECAST_RUN_ID="2026-27-$(date -u +%Y%m%dT%H%M%SZ)"
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
bash "$PAGE_REPO_ROOT/2026/launch_weekly_forecast.sh" --dry-run
```

Then launch detached (same environment, after reviewing the dry run):

```bash
bash "$PAGE_REPO_ROOT/2026/launch_weekly_forecast.sh"
```

The launcher refuses an existing week directory, refuses a missing kit, requires
a host shell, detaches the runner with `setsid nohup`, and starts a detached
identity watchdog. The child publishes `runner.pid` and `runner_identity.tsv`
(PID, start ticks, command marker) atomically before `exec R`; the watchdog
checks PID, start ticks and command marker, never signals the process, and exits
on terminal completion/failure or identity loss.

Run-local library is optional: set `PAGE_WEEKLY_INSTALL_LIB=1` to install PAGe
into `$run_dir/r-lib` and pin it via `R_LIBS_USER`. Leave it unset to use an
ambient, already-installed PAGe.

## Outputs

Under `$PAGE_WEEKLY_OUT_ROOT/$PAGE_FORECAST_RUN_ID`:

- `status.tsv` - `started` -> `forecasting` -> `complete`, or `failed`.
- `runner.pid`, `runner_identity.tsv`, `watch.tsv`, `watch_terminal.txt`,
  `weekly_forecast.log`, `watchdog.log`, `launch_receipt.txt`.
- `data_cache/` - timestamped raw ORVT CSV downloaded by `getCurrentD()`.
- `<season>-weekF<NN>/` - the week directory, refused if it already exists:
  - `forecast_h1h2.tsv` - the latest origin's h1 and h2 M1 and M2 forecasts
    (`m1_p`/`m1_lo`/`m1_hi`, `m2_p`/`m2_lo`/`m2_hi`, `forecast_action`), with
    ignition status, decimal ignition `iWeek_hatF` and its one-week bracket, and
    peak timing fields (`peak_passed`, `peak_weekF`, `peak_weekF_lo`,
    `peak_weekF_hi`, `t_peak`).
  - `forecast_ledger.tsv` - every origin/horizon row evaluated.
  - `ignition.tsv` - ignition status/decimal/bracket and peak timing scalars.
  - `data_provenance.tsv` - source path/URL, retrieval time, data SHA-256,
    PHO layout, week counts and last week end date.
  - `manifest.rds`, `manifest.txt` - kit path/hash, data hash/source/retrieval,
    package version and path, platform/session info, forecast week, staleness
    policy, elapsed seconds.
  - `weekly_result.rds` - the full `run_prospective_pipeline()` result.

Health: read `tail -n 2 "$PAGE_WEEKLY_OUT_ROOT/$PAGE_FORECAST_RUN_ID/watch.tsv"`
and `status.tsv`. No recurring AI polling is needed.

## Failure handling

- **Nonzero before detach**: the launcher writes a `failed` status row. Inspect
  the message; a missing kit or hash mismatch is a hard stop. Do not reuse the
  run directory.
- **Missing or mismatched kit**: the runner fails before creating a week
  directory or fetching data (fail closed).
- **Stale data**: if the latest observed week is older than
  `PAGE_MAX_STALENESS_DAYS`, the run stops. Confirm the ORVT feed is current
  before relaxing the limit.
- **`FAILED` in `status.tsv`**: read `weekly_forecast.log` for the first error,
  resolve it, then launch with a new `PAGE_FORECAST_RUN_ID`.
- **`died_without_terminal_status`** in `watch_terminal.txt`: R cannot write its
  own failed status after a hard death; use the bounded `watch.tsv` and log tail.
- **Ignition not detected**: `ignition_status` is `not_detected` and the M1/M2
  fields are missing. This is a valid result, not an error; escalate for review.
- Known package gap: if the frozen M0 parameters set `use_cls = TRUE`, the
  runtime needs the M0 classifier object, which `assemble_kit()` does not store.
  Verify with the package owners before the first operational run.

## Review before publication

Before sharing any weekly output, confirm: the kit hash matches the approved
frozen kit; `data_provenance.tsv` and `manifest.rds` name the intended source,
retrieval time and data SHA-256; the forecast week is the intended origin; and a
human has reviewed the h1/h2 values, ignition status and peak timing. Hash
checks establish file identity only; they are not a claim of predictive
performance for the incoming season.
