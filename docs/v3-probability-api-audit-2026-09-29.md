# PAGe v3 probability API audit — 2026-09-29

## Disposition

**IMPLEMENTED AS AN EXPERIMENTAL API-SIDE DIAGNOSTIC. CANONICAL V3 RELEASE AND FORECAST ROUTING ARE UNCHANGED.**

The v4 weekly API now supports immutable, run-bound queries for:

- `P(p > x)` for A/B positivity at +1/+2 horizons;
- `P(T_peak < t)` for A/B peak timing when the current M1 passage posterior is available.

These probabilities are not used for ignition, timing passage, forecast routing, model selection, alerting, or promotion.

## Release-boundary decision

An early implementation placed the probability abstraction inside `PAGe/R`. That design was rejected during audit because canonical v3 release `5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b` binds the complete `PAGe/R/*.R` source closure. Adding a diagnostic file there would require a new v3 release even though the point forecast models were unchanged.

The final implementation therefore lives entirely in the API layer:

- `scripts/v3_probability_helpers_v1.R`
- `2026/run_page_probability_snapshot_v1.R`
- `governance/v3_probability_calibrator_v1.rds`

No probability-specific source remains in `PAGe/R`, no probability-specific NAMESPACE export is added, and `PAGe/R/v3_runtime.R` is unchanged by this feature.

This preserves the existing v3 release boundary while allowing the API deployment identity to bind the probability code and calibrator independently.

## Historical implementation located

Git history commit `9d5ce1ed0e3fab177122c3c0e8004122b370df3b` (`Add peak-week probability distribution API`) contains the earlier predictive-distribution design.

Two semantics from that implementation were retained:

1. `P(p > x)` must be computed from a predictive distribution rather than by transforming a point forecast;
2. peak-week probabilities must be exact weighted probabilities over peak-posterior atoms.

## Positivity probability calibrator

Builder:

`scripts/build_v3_probability_calibrator_v1.R`

Frozen API asset:

`governance/v3_probability_calibrator_v1.rds`

Calibrator ID:

`8ab551f5b663167620840f3e27333f4d305aa8c0fb99895335b5ebbae0142ccd`

Frozen asset SHA-256:

`89f752faa6f26c32aaa0d1af9ce2d184ec49b3ecdbddc4f3e9ec3c1f873cc636`

The calibrator is explicitly bound to canonical v3 release ID `5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b`.

### Residual construction

For a historical chronological/OOS point forecast `p_hat`, the stored residual is:

`r = logit((y + 0.5)/(N + 1)) - logit(p_hat)`

For a current v3 point forecast `p`, predictive atoms are:

`p_atom = plogis(logit(p) + r)`

Residual atoms are weighted so every historical season receives equal total probability mass, with equal mass per origin within a season.

### OOS source ledgers

A +1/+2 use:

`artifacts/m2-v2-c2-governed-chronological-v1/predictions.csv`

with `runtime_pred_base`. The replay implementation rebuilds each target-season fit from its recorded `prior_seasons` only and labels the replay scope `strict_prior_seasons_only`.

B +1/+2 use:

`artifacts/v3-m2-b-posterior-c2-chronological-v2/per_origin_predictions.csv`

with `pred_B1` for +1 and `pred_B2_posterior` for +2. The benchmark explicitly rejects state/timing training seasons that are not strictly earlier than the target season and rebuilds both state and timing components from those prior seasons.

Thus the residual pools use chronological/OOS forecasts rather than in-sample fitted values.

### Pool inventory

| Pool | Origins | Seasons | Historical range |
|---|---:|---:|---|
| A +1 | 313 | 8 | 2016-17 to 2025-26 |
| A +2 | 305 | 8 | 2016-17 to 2025-26 |
| B +1 | 274 | 7 | 2016-17 to 2025-26 |
| B +2 | 267 | 7 | 2016-17 to 2025-26 |

The runtime refuses to use the calibrator for a forecast season contained in or earlier than the calibration pool. It is therefore intended for 2026-27 and later under the current release.

## Chronological calibration validation

Each validation season was scored using residual atoms from strictly earlier seasons only.

| Type | Horizon | 50% coverage | 90% coverage | Mean PIT | Rows |
|---|---:|---:|---:|---:|---:|
| A | +1 | 0.485 | 0.929 | 0.512 | 196 |
| A | +2 | 0.492 | 0.906 | 0.505 | 191 |
| B | +1 | 0.611 | 0.943 | 0.507 | 157 |
| B | +2 | 0.529 | 0.948 | 0.501 | 153 |

The 90% intervals are modestly conservative and PIT means are close to 0.5. These results support experimental diagnostic use; they do not establish prospective decision-grade probability calibration.

Evidence:

- `artifacts/v3-probability-calibrator-v1/chronological_validation_rows.csv`
- `artifacts/v3-probability-calibrator-v1/chronological_validation_summary.csv`
- `artifacts/v3-probability-calibrator-v1/pool_inventory.csv`

## Peak probability

`P(T_peak < t)` is calculated from the current M1 passage-posterior atoms, not from confidence-interval endpoints.

A:

- uses the current M1-A passage posterior conditional on governed M0 ignition;
- exact posterior mass is retained in the probability snapshot.

B:

- uses causal B activity plus the current M1-B passage posterior;
- if B timing is inactive, peak probability is explicitly unavailable rather than fabricated.

Tests verify that, for both retained A and active-B fixtures, inclusive posterior mass `P(T_peak <= origin+1)` matches the existing `prob_peak_passed` monitoring value to numerical precision. A posterior mass over the next 1/2/3 weeks also matches the existing A monitoring quantities.

## Immutable probability snapshot

After the canonical forecast transaction succeeds, `2026/run_page_weekly_api_worker_v4.R` invokes:

`2026/run_page_probability_snapshot_v1.R`

The probability worker:

1. opens the already-completed governed transaction;
2. reads the transaction's exact `typed_ab_weekly.csv` and `v2_v3_comparison.csv`;
3. sources the unchanged canonical PAGe runtime plus the API-side probability helper;
4. reconstructs package-native v3 from the exact typed panel;
5. requires all four point forecasts and all four route names to match the issued transaction (`1e-12` tolerance for forecast values);
6. builds positivity and peak weighted atoms;
7. atomically writes private `probability_snapshot.rds` and `probability_snapshot.sha256` files.

Snapshot generation is best-effort and occurs only after the canonical transaction succeeds. A probability-layer failure does not invalidate the canonical forecast run.

## Snapshot validation and fail-closed behavior

`scripts/v3_weekly_api_helpers_v4.R` validates:

- snapshot and SHA sidecar both exist;
- SHA-256 matches exactly;
- top-level and distribution schemas match exactly;
- release ID, season, and origin match the governed transaction;
- positivity keys are exactly A/B x +1/+2;
- atoms and weights are finite, non-negative, within support, and weights sum to one;
- positivity scale/outcome semantics are correct;
- each snapshot point forecast and route exactly matches `v2_v3_comparison.csv`;
- peak keys and timing-availability semantics are valid.

The HTTP request uses the exact in-memory snapshot object that passed SHA/schema/route validation; it does not reread the RDS after validation.

If the snapshot is missing, partial, invalid, or tampered:

- the canonical forecast result remains valid;
- `result.probabilities.status` is `unavailable`;
- probability endpoints fail closed with `409 probability_unavailable`.

## HTTP API

Strict positivity exceedance:

`GET /v1/weekly-runs/{run_id}/probability/positivity?type=A&horizon=1&threshold=0.02`

returns `P(p > 0.02)`. Thresholds are proportions, so `0.02` means 2%.

Strict peak timing:

`GET /v1/weekly-runs/{run_id}/probability/peak?type=A&week=14`

returns `P(T_peak < 14)`.

The endpoints:

- require bearer authentication;
- require a succeeded weekly run;
- accept only exact query-parameter sets;
- reject duplicate/unexpected parameters;
- require A/B type;
- require horizon exactly 1 or 2 (`1.5` is rejected, not truncated);
- require positivity threshold in `[0,1]`;
- report the snapshot SHA and experimental calibration metadata.

Inactive timing returns HTTP 200 with `available=false`, `status=unavailable`, and `probability=null`.

OpenAPI was updated to version 4.1.0 in `docs/v3-weekly-deployment-api-openapi-v1.yaml`.

## API deployment identity

The v4 API deployment manifest now binds the probability-specific layer:

- `2026/run_page_probability_snapshot_v1.R`
- `scripts/v3_probability_helpers_v1.R`
- `governance/v3_probability_calibrator_v1.rds`
- `PAGe/tests/testthat/test-v3-probability.R`
- the modified v4 API source/tests/OpenAPI files.

The canonical forecast release ID continues to bind its own PAGe runtime/model closure; the probability API does not duplicate or alter that release identity.

### Clean canonical deployment proof

A clean ephemeral source tree was reconstructed from the canonical release metadata commit:

`f982746ecb4bad7da7552af64f6d0afd1b318930`

All 123 release-manifest dependencies were hydrated/verified at their canonical hashes. Only the API-side probability overlay was then applied.

Results:

- canonical release validation: **PASS** for `5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b`;
- fresh test API deployment build: **PASS**;
- resulting deployment ID: `3230697c021721f7c3a7add5d5d6b46d974c8ccfdec818bbdde042028c293efb`.

This demonstrates that the probability API is deployable on the exact canonical v3 release without changing or re-signing the forecast release.

## Final focused regression tests

Tests were rerun after moving the probability layer outside `PAGe/R`:

- `PAGe/tests/testthat/test-v3-probability.R`: **26 assertions passed**;
- `PAGe/tests/testthat/test-v3-package-runtime.R`: **62 assertions passed**;
- `PAGe/tests/testthat/test-v3-weekly-api-v4-monitoring.R`: **64 assertions passed**;
- `PAGe/tests/testthat/test-v3-weekly-api-http-v4.R`: **43 assertions passed**;
- `PAGe/tests/testthat/test-v3-weekly-api-core-v4.R`: **94 assertions passed**.

Total focused assertions: **289/289**.

The retained weekF12 transaction was also used to generate a real immutable snapshot successfully after final externalization.

## Existing research-branch release drift

The current research branch contains package/research work newer than canonical release `5472...`. As expected, running `.v3_release_validate()` directly against the mutable research checkout reports pre-existing hash/source-closure drift.

This is not repaired by re-pinning the canonical release. The correct deployment proof uses the canonical source commit plus the separately content-addressed API overlay, as described above.

An independent Claude review also ran a broader v3/M2 test selection and reported no assertion failures but 14 release-binding errors, all attributable to those pre-existing pinned-hash/source-closure differences. No canonical hash was modified to bypass them.

## Independent-agent result

The requested Jax/GPT-6.1 Sol run did not actually execute successfully:

- a direct Jax dispatch returned a server error;
- a Codex dispatch accepted the requested `gpt-6.1-sol`, but AgentPorter reported the configured/actual worker as GPT-5.6 Luna and it failed before analysis because it started outside a trusted Git directory.

A Claude Code agent subsequently completed an independent read/test review. It made no edits and confirmed the focused probability/API suites passed, while flagging the existing release-hash drift described above.

No GPT-6.1 Sol review is claimed.

## Limitations

- Positivity distributions are empirical season-balanced residual distributions, not a full generative posterior.
- The calibration pool contains only 7-8 historical seasons depending on type/horizon.
- Historical denominator regimes differ from the current type-specific ORVT regime.
- Peak timing probabilities are model-conditional posterior probabilities and have not received prospective probability calibration.
- Probability endpoints remain experimental/shadow diagnostics and should not be used as operational probability gates without a separate prospective promotion audit.
- If an N-enabled M2 route is later promoted, `v3_probability_calibrator_v1` must be rebuilt/versioned for the new route; it must not be silently reused.

## Final interpretation

The historical probability interfaces were conceptually sound. The completed v4 integration preserves the important properties: chronological/OOS residual calibration for positivity, exact posterior mass for peak timing, immutable per-run snapshots, exact forecast/route parity, content-addressed validation, fail-closed behavior, and separation from canonical forecast routing.

**Final disposition: suitable for experimental/shadow API use; canonical v3 remains unchanged.**
