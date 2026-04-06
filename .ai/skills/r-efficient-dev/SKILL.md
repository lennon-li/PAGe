---
name: r-efficient-dev
description: >
  Efficient R development guidance for this repository. Use when editing R code,
  refactoring, debugging, or working on package code with an emphasis on
  vectorization, minimal patches, concise output, and practical execution.
---

# R Efficient Development

This is the canonical repo-local skill. Sync generated copies to `.claude/skills`
and `.agents/skills` with `Rscript scripts/sync-agent-context.R`.

## Core Rules

- Prefer vectorized R and avoid loops unless a loop is clearly better for
  performance, clarity, or correctness.
- Prefer `data.table` when appropriate for performance-sensitive work.
- Make minimal patches and avoid unnecessary full-file rewrites.
- Read only the files and functions needed for the task, then inspect direct
  dependencies if needed.
- Prefer runnable code over long explanations.
- Keep outputs concise and summarize logs instead of dumping large raw output.

## Package Work

- Use roxygen2 for exported functions.
- Run `styler` on touched R files after package edits.
- Run `devtools::document()` when package documentation or exported interfaces
  change.

## Checks And Debugging

- When checks fail, summarize only the key failures.
- Report the first useful error, the failing test or check, and the next direct
  fix implied by the output.
- Debug incrementally with small, targeted inspection rather than broad data
  dumps.
