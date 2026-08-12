# Disclosure-safe audit artifacts

This directory may contain only aggregate audit summaries and result manifests
in JSON, CSV, or Markdown. Do not add row-level predictions, surveillance data,
model objects, or source input files. Every result manifest must validate with
`PAGe::validate_result_manifest()` and use schema `page_result_manifest`.

The manual 2025-26 acceptance entry point writes one immutable run directory
per decision. It contains `candidate_*_metrics.csv`,
`incumbent_*_metrics.csv`, `candidate_*_diagnostics.csv`,
`incumbent_*_diagnostics.csv`, `gate_details.csv`, `decision.md`, and
`result_manifest.json`. The corresponding private directory contains replay
objects and `decision_bundle.rds`; do not copy those files into this directory.
