# PAGe weekly deployment API v4 operations

Date: 2026-09-29
Status: current shadow-only operational contract

## Pinned stack

- API contract: `page-weekly-api-v4`.
- Forecast release: `artifacts/v3-shadow-release-v3/5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b/`.
- Authoritative launcher: `2026/run_weekly_shadow_release_v5.R`.
- Canonical minimum origin: weekF12.
- Deployment unit: `deploy/systemd/page-weekly-api-v4.service`.
- Trigger body: `deploy/systemd/page-weekly-trigger-body.json.example`.

API v4 preserves the hardened v2 request, idempotency, durable state, locking, worker isolation, transaction validation, and disclosure-safe projections. Its bootstrap manifest binds the exact v4 helpers, service, worker, preflight, versioned HTTP adapter `2026/page_weekly_api_v4.R`, and launcher v5. The HTTP paths retain `/v1` for wire compatibility; internal deployment contract/version is v4. The service runs loopback-only and is **shadow-only**. Successful result payloads include a disclosure-safe `monitoring` object sourced only from validated child-run CSV artifacts. API v4 can also compute an optional **shadow-only A+2 test-volume challenger** after the canonical transaction succeeds. The challenger is a frozen full-history A1-form + EXP050 fit, never replaces canonical A1, and is not used by the probability calibrator. This runbook does not enable a timer or authorize production promotion.

## Build and preflight

Run from the repository root in the governed R environment. Use the private artifact mount and machine-specific paths selected by the operator; do not put credentials in command arguments.

```sh
Rscript --vanilla scripts/build_v3_weekly_api_deployment_v4.R \
  --deployment-root=<ARTIFACT_MOUNT>/api-deployments \
  --artifact-mount=<ARTIFACT_MOUNT> \
  --artifact-fs-type=nfs4 \
  --artifact-mount-source=<MOUNT_SOURCE> \
  --job-root=<ARTIFACT_MOUNT>/weekly-api \
  --output-root=<ARTIFACT_MOUNT>/weekly-shadow \
  --source-mode=orvt \
  --season=2026-27 \
  --bind-host=127.0.0.1 \
  --port=8088 \
  --rscript=/usr/bin/Rscript \
  --forecast-release-dir=<REPO>/artifacts/v3-shadow-release-v3/5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b \
  --max-runtime-seconds=1800 \
  --mode=production
```

The builder validates the exact release and emits a content-addressed deployment ID. Set `PAGE_API_DEPLOYMENT_DIR` to that immutable directory and configure `PAGE_RELEASE_DIR` to the exact release directory in `deploy/systemd/page-weekly-api-v4.env.example`. The v4 preflight verifies deployment identity, component hashes, environment, and release identity before startup. Do not use a mutable `latest` path.

For official PHO publication runs, deploy with `source_mode=orvt` (the production env example does this), set `PAGE_REQUIRE_LIVE_ORVT=1`, and set `PAGE_ORVT_MIN_WEEKF` to the expected governed origin (WeekF12 for the 2026-10-02 publication). The installer source preflight exercises the same ORVT resolver and fails closed if the live feed has not reached that origin. The trigger independently sets `PAGE_TRIGGER_REQUIRE_SOURCE_MODE=orvt` and verifies the completed transaction provenance before reporting success. Use `auto`/OLIS fallback only for an explicitly reviewed contingency run, not as proof of official ORVT ingestion.

## Run semantics

The trigger body must contain the configured season and exact release ID. Omitting `a_shadow_option` is equivalent to `off`:

```json
{"season":"2026-27","expected_release_id":"5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b"}
```

To request the experimental A+2 test-volume challenger for the same canonical run:

```json
{"season":"2026-27","expected_release_id":"5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b","a_shadow_option":"exp050_h2"}
```

Allowed values are `off` and `exp050_h2`. `exp050_h2` leaves all four canonical v3 forecasts unchanged and adds `result.a_shadow.challenger`, containing the canonical A+2 forecast, the challenger A+2 forecast, their percentage-point delta, the current EXP050 feature, and the frozen shadow artifact identity. It is **not** an alternate production route.

Use a stable `Idempotency-Key` tied to the upstream publication cycle **and the requested option**. The option is included in the immutable request digest, so an idempotency key cannot be reused to switch between `off` and `exp050_h2`. The authoritative launcher still runs unchanged and fails closed before weekF12. After it succeeds, the API worker computes the challenger best-effort from the exact governed typed panel. A challenger failure does not invalidate the canonical run; it is projected as `a_shadow.status = "unavailable"`.

Successful results still contain exactly four finite canonical A/B × +1/+2 forecasts and disclosure-safe provenance. The source panel hash must match between result and provenance. When requested, the challenger is a separate shadow projection and never changes `forecasts`. The authoritative transaction remains on the private artifact share.

## Operating constraints

- Keep the API bound to loopback behind the approved same-host TLS/authentication proxy.
- Keep bearer credentials in a protected file or systemd credential, never in arguments or logs.
- Keep release/source mounts read-only; grant writes only to API job/output roots.
- Do not enable scheduling until a manual shadow run is reviewed by the responsible operator.
- Do not expose release switching, uploads, arbitrary replay, cancellation, raw artifacts, or production promotion.
- Do not treat `exp050_h2` as promoted: its nested historical A+2 MAE gain was about 1.55%, below the prior promotion threshold; it exists for prospective shadow evidence only.

Historical API v1/v2 runbooks and older release IDs are superseded; current deployment instructions are exclusively the v3 binding above.

## Friday official-ORVT publication gate

For the 2026-10-02 WeekF12 publication, do not substitute a manually supplied OLIS panel for the official-source check. From the canonical release-compatible deployment checkout, first run:

```sh
Rscript --vanilla 2026/run_page_orvt_source_preflight_v1.R \
  --season=2026-27 \
  --min-weekF=12 \
  --result-path=/tmp/page-orvt-week12.json
jq -e '.ok == true and .source_mode == "orvt" and .origin_weekF >= 12' /tmp/page-orvt-week12.json
```

For WeekF12, the expected latest week end is `2026-09-26`. Review the reported A/B `y`, `N`, `p`, raw SHA-256, selected official URL, and `week_end_date` before triggering. A stale feed exits non-zero.

The production API deployment must use `PAGE_SOURCE_MODE=orvt`; the installer template additionally sets `PAGE_REQUIRE_LIVE_ORVT=1` and `PAGE_ORVT_MIN_WEEKF=12`. After a successful API run, the installed trigger helper verifies `/v1/weekly-runs/<run_id>/provenance` and refuses success unless `source_mode=orvt`. Use a new protected publication-cycle ID for the Friday vintage; reusing a prior successful ID returns the prior idempotent run.

The installer provisions the trigger helper/unit/timer and protected trigger configuration, but deliberately leaves the timer disabled. Keep the run manual/reviewed until the exact PHO publication time is operationally established; the checked-in Sunday timer is not an assertion about PHO's Friday publication time.
