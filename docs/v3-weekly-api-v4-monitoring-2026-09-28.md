# PAGe API v4 monitoring surface

Date: 2026-09-28  
Status: **APPROVED for production-host shadow deployment testing; timer remains disabled until reviewed live weekF12+ run**

## Purpose

API v4 exposes the governed M0/M1 monitoring state that is already produced by the canonical weekF12 v3 child run, alongside the existing M2 forecasts. It does not fit, refit, rerun, or alter any forecasting model.

Canonical forecast release remains:

`5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b`

Canonical launcher remains:

`2026/run_weekly_shadow_release_v5.R`

API contract:

`page-weekly-api-v4`

All outputs remain `shadow_only`; production promotion is unchanged.

## Result contract

A successful `GET /v1/runs/<run_id>/result` returns the existing four A/B +1/+2 forecast rows plus a `monitoring` object.

### Influenza A / M0

`monitoring.A.m0` exposes:

- `ignited`
- `ignition_weekF` (fractional ignition location when available)
- `ignition_week` (integer week)
- `eligible_from_weekF` (= 12)
- ignition bracket lower/upper weeks
- fractional crossing method

The values are parsed only from the governed v3 child `m0_a_detection.csv` and are cross-checked against the full `m0_a_signals.csv` history. Summary/signal disagreement fails the entire transaction projection.

### Influenza A / M1

`monitoring.A.m1` exposes:

- `available`
- `state`
- `weeks_elapsed_since_activation`
- `weeks_to_peak`
- raw and calibrated/posterior peak mean weekF
- 90% lower and upper peak weekF
- 90% interval width
- `prob_peak_passed`
- `prob_peak_within_1w`
- `prob_peak_within_2w`
- `prob_peak_within_3w`
- `peak_passed`
- locked peak week when applicable

If M0 has not ignited, the canonical runner does not create `m1_a_timing.csv`. API v4 represents that state as `available=false`, `state=inactive_pre_ignition`, with timing quantities `null`. A missing M1 file is allowed only in that state. A symlink, malformed file, or missing M1 file after ignition fails closed.

### Influenza B / M1 timing

`monitoring.B.m1` is projected only from the governed B+2 row in `combined_predictions.csv` and exposes:

- timing availability/reason
- causal B activity weekF
- peak-passed probability
- posterior peak mean weekF
- posterior supported mass
- lower-bound mass / saturation
- B model version
- B+2 route

When B timing is available, the route must be `posterior_C2` and posterior peak/probability fields must be finite. Otherwise the route remains the exact B1 fallback and peak quantities may be null.

## Provenance and fail-closed behavior

The public provenance records SHA-256 hashes for all monitoring source files:

- `m0_a_detection.csv`
- `m0_a_signals.csv`
- `m1_a_timing.csv` when present
- `combined_predictions.csv`
- child `provenance.tsv`
- child `status.tsv`

The parent authoritative transaction is fully validated before monitoring projection. Missing, malformed, symlinked, season/origin-inconsistent, or internally inconsistent monitoring artifacts cause `transaction_validation_failed`; a partial result is never published.

No absolute child paths are exposed in the public result/provenance.

## Retained audit evidence

Evidence root:

`artifacts/v3-api-v4-monitoring-audit-2026-09-28-v2/`

The evidence bundle has a recursive 126-file SHA-256/size manifest.

Three retained executions are included:

1. **Real weekF11** — expected fail closed because current origin is below the weekF12 canonical issuance floor. Deployment ID:
   `7ae351efa09112f9d36c791e4c6fd0edc16d8cde1ee4acfa9a905a499e077321`

2. **Synthetic weekF12 with A ignition** — succeeds, M0 ignited, M1-A active, four finite forecasts. Deployment ID:
   `96573f27f2631e82a021e778fca846cd3e7be277e13d2b971b76a2c7c976b72c`

3. **Synthetic weekF12 without A ignition** — succeeds, M0 not ignited, M1-A unavailable, four finite forecasts still returned. Deployment ID:
   `2a740923a33a25dcd1cd40096c5542503f5c3a67c396867d2143111fab150687`

The synthetic fixtures validate execution/monitoring semantics only; they are not forecast-accuracy evidence.

## Test evidence

Final API v4 targeted tests:

- core/state/idempotency/transaction validation: **94/94**
- HTTP/auth/routes/disclosure behavior: **43/43**
- monitoring semantics/adversarial validation: **34/34**

Total: **171/171 assertions**, with zero failures, warnings, or skips in the retained final run.

## Operational use at weekF12

For the first real complete weekF12 source vintage:

1. trigger API v4 manually with the protected publication/cycle ID;
2. verify the run succeeded and release ID equals `5472d089...a853b`;
3. inspect `monitoring.A.m0.ignited`;
4. if true, inspect `monitoring.A.m1.peak_mean_weekF`, the 90% interval, weeks-to-peak, and passage probabilities;
5. inspect `monitoring.B.m1` for B timing availability;
6. review the four A/B +1/+2 forecasts and v2-v3 deltas;
7. retry the same publication ID and confirm idempotency returns the same run;
8. only after the reviewed live run should the weekly timer be enabled.

## Production-host installation

Use the audited installer:

`deploy/systemd/install-page-weekly-api-v4.sh`

First validate the host without changing systemd:

```bash
sudo ./deploy/systemd/install-page-weekly-api-v4.sh check /etc/page/weekly-api-v4.env
```

Then install/start API v4 with the timer still disabled:

```bash
sudo ./deploy/systemd/install-page-weekly-api-v4.sh install /etc/page/weekly-api-v4.env
```

The installer requires the exact private NFS type/source, canonical release, service account, token permissions, governed R environment, and source path; builds a content-addressed production deployment; runs preflight; installs the hardened systemd unit; starts only API v4; checks health/readiness; and explicitly keeps `page-weekly-trigger.timer` disabled. Health/readiness failure rolls the API service back to stopped/disabled.

Independent audit results:

- monitoring semantics: **APPROVE**;
- API/deployment evidence: **APPROVE WITH CAVEATS** limited to external host state / lack of real weekF12+ success;
- production-host installer: **APPROVE** after closing write-scope and rollback findings.

Actual production-host execution has not been performed from the AgentPorter sandbox because that sandbox has no private NFS mount, production `PAGE_*` environment, root service account context, or usable host systemd bus.
