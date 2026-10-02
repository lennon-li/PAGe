# PAGe manuscript workspace

This directory is intentionally separate from the production R package and operational pipeline.

It contains manuscript protocols, drafts, reporting tables, publication-specific analyses, and manuscript execution scripts. Production package code belongs under `PAGe/`; operational deployment code belongs under `2026/` and `scripts/`; research model development belongs on the dedicated research branches.

## Structure

- `drafts/` — manuscript drafts and working specifications.
- `results/` — publication-specific result artifacts and audit outputs.
- `scripts/` — manuscript-only execution/replay scripts.
- top-level Markdown files — analysis protocol, methods/results working documents, governance decisions, literature review, and publication audit materials.

Manuscript code may call the supported PAGe public API. Historical publication reproductions may use package internals when necessary to reproduce a frozen analysis, but those calls are not part of the supported external R API.
