# PAGe weekly deployment API v4 plan

Date: 2026-09-28  
Status: current implementation and contract index

## Current binding

API v4 (`page-weekly-api-v4`) wraps the canonical, shadow-only forecast release `artifacts/v3-shadow-release-v3/5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b/`. Every API worker executes only `2026/run_weekly_shadow_release_v5.R`; the canonical minimum origin is weekF12. Forecast code and release contents are unchanged. API v4 adds only a validated monitoring projection from the published v3 child run: A M0 ignition, A M1 peak timing/probabilities, B M1 timing state, and the existing M2 forecasts.

The deployment is content-addressed. `scripts/build_v3_weekly_api_deployment_v4.R` binds the exact API helpers, service entrypoint, worker, preflight, versioned HTTP adapter, governance schemas/policy, deployment template, and launcher. Preflight verifies both the deployment identity and release identity. The versioned `2026/page_weekly_api_v4.R` adapter is bound into the v4 deployment manifest and launches only worker-v4/preflight-v4; forecast execution still goes exclusively through launcher v5.

## Preserved API behavior

The v3 copy preserves the hardened v2 durable state machine, idempotency semantics, single-flight locking, worker isolation, storage checks, environment sanitization, transaction schema validation, and disclosure-safe result/provenance projection. The public HTTP route prefix remains `/v1` for wire-schema continuity; the internal deployment contract is v3.

The API is loopback-only and **shadow-only**. It does not add model execution logic, direct M0/M1/M2 endpoints, caller-selected releases or paths, uploads, arbitrary historical replay, cancellation, raw artifact access, or production promotion. Forecast transaction validity remains governed by the unchanged release launcher and transaction schema.

## Versioned implementation

- Core: `scripts/v3_weekly_api_helpers_v4.R`.
- Deployment identity and validation: `scripts/v3_weekly_api_deployment_helpers_v4.R`.
- Deployment builder: `scripts/build_v3_weekly_api_deployment_v4.R`.
- Service, worker, preflight: `2026/run_page_weekly_api_v4.R`, `2026/run_page_weekly_api_worker_v4.R`, `2026/run_page_weekly_api_preflight_v4.R`.
- Policy and systemd template: `governance/v3_weekly_api_policy_v4.tsv`, `deploy/systemd/page-weekly-api-v4.service`.
- Request/transaction/environment schemas remain governed by their existing versioned files and are bound into the deployment manifest.
- Interface: `docs/v3-weekly-deployment-api-openapi-v1.yaml`.
- Operator steps: [API v4 operations runbook](v3-weekly-deployment-api-operations-2026-09-27.md).

## Acceptance evidence

The v3 binding test asserts the exact release and API contract, validates preflight/deployment identity, runs synthetic OLIS weekF12 through the API worker, checks four finite forecasts and panel/source provenance, and confirms weekF11 fails closed without a success projection. Core and HTTP v3 test variants exercise the unchanged API semantics against v3 constants.
