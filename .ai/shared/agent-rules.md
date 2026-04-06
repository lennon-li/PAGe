# Shared Agent Rules

## R Development

- Prefer vectorized R and avoid loops unless a loop is clearly better for
  performance, clarity, or correctness.
- Prefer `data.table` when appropriate for performance-sensitive joins,
  aggregations, and reshaping.
- Use the native pipe `|>` unless existing local code strongly suggests another
  style.
- Prefer explicit `package::function()` calls in non-trivial code paths.

## Editing Discipline

- Make minimal patches and avoid rewriting whole files unnecessarily.
- Read only the files and functions needed for the current task, then widen the
  search only when required.
- Debug incrementally by starting with the touched function and its nearest
  dependencies.
- Keep mirrored package files in `R/` and `flualign/R/` consistent when a task
  touches both copies.

## Package Work

- Use roxygen2 for exported package functions, including `@param`, `@return`,
  and `@export` where applicable.
- After package edits, run `styler` on touched R files.
- When package documentation or exported interfaces change, run
  `devtools::document()`.

## Output And Checks

- Prefer runnable code over long explanations.
- Keep outputs concise and summarize logs rather than pasting large raw output.
- When tests or checks fail, report only the key failures, including the first
  useful error and the failing test or check.

## Shared MCP

- Use the `openaiDeveloperDocs` MCP server for authoritative OpenAI API, model,
  and Codex documentation when that information is relevant to the task.
