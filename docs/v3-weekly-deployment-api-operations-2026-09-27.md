# PAGe weekly deployment API v4 operations

Date: 2026-09-28  
Status: current shadow-only operational contract

## Pinned stack

- API contract: `page-weekly-api-v4`.
- Forecast release: `artifacts/v3-shadow-release-v3/5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b/`.
- Authoritative launcher: `2026/run_weekly_shadow_release_v5.R`.
- Canonical minimum origin: weekF12.
- Deployment unit: `deploy/systemd/page-weekly-api-v4.service`.
- Trigger body: `deploy/systemd/page-weekly-trigger-body.json.example`.

API v4 preserves the hardened v2 request, idempotency, durable state, locking, worker isolation, transaction validation, and disclosure-safe projections. Its bootstrap manifest binds the exact v4 helpers, service, worker, preflight, versioned HTTP adapter `2026/page_weekly_api_v4.R`, and launcher v5. The HTTP paths retain `/v1` for wire compatibility; internal deployment contract/version is v4. The service runs loopback-only and is **shadow-only**. Successful result payloads include a disclosure-safe `monitoring` object sourced only from validated child-run CSV artifacts; the API does not recompute M0/M1/M2. This runbook does not enable a timer or authorize production promotion.

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
  --source-mode=auto \
  --season=2026-27 \
  --bind-host=127.0.0.1 \
  --port=8088 \
  --rscript=/usr/bin/Rscript \
  --forecast-release-dir=<REPO>/artifacts/v3-shadow-release-v3/5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b \
  --olis-fallback=<PRIVATE_OLIS_FALLBACK> \
  --max-runtime-seconds=1800 \
  --mode=production
```

The builder validates the exact release and emits a content-addressed deployment ID. Set `PAGE_API_DEPLOYMENT_DIR` to that immutable directory and configure `PAGE_RELEASE_DIR` to the exact release directory in `deploy/systemd/page-weekly-api-v4.env.example`. The v4 preflight verifies deployment identity, component hashes, environment, and release identity before startup. Do not use a mutable `latest` path.

## Run semantics

The trigger body must contain the configured season and exact release ID:

```json
{"season":"2026-27","expected_release_id":"5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b"}
```

Use a stable `Idempotency-Key` tied to the upstream publication cycle. Repeating the same key and request returns the existing run; reusing it for a different request is rejected. A worker invokes only `2026/run_weekly_shadow_release_v5.R`. The authoritative launcher fails closed before weekF12. A failed worker receipt must never be projected as a succeeded API result.

Successful results contain exactly four finite A/B × +1/+2 forecasts and disclosure-safe provenance. The source panel hash must match between result and provenance. The authoritative transaction remains on the private artifact share.

## Operating constraints

- Keep the API bound to loopback behind the approved same-host TLS/authentication proxy.
- Keep bearer credentials in a protected file or systemd credential, never in arguments or logs.
- Keep release/source mounts read-only; grant writes only to API job/output roots.
- Do not enable scheduling until a manual shadow run is reviewed by the responsible operator.
- Do not expose release switching, uploads, arbitrary replay, cancellation, raw artifacts, or production promotion.

Historical API v1/v2 runbooks and older release IDs are superseded; current deployment instructions are exclusively the v3 binding above.
