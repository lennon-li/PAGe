# Long-job supervision policy

This policy governs long PAGe tuning, replay, simulation, and fitting jobs. Its
purpose is to preserve compute reliability without consuming an AI allowance
merely to observe an otherwise healthy local process.

## Default architecture

Use three distinct phases:

1. **AI-assisted launch:** validate inputs, record exact parameters and hashes,
   start the job and a detached OS-level watchdog, confirm the first checkpoint,
   then end the AI turn.
2. **Local supervision:** the watchdog performs all scheduled health checks
   without invoking an AI model. It appends one compact TSV/JSON row per check
   and creates a terminal or alert marker.
3. **AI-assisted exception or completion review:** invoke the AI only when the
   watchdog detects a failure/stall, when the user explicitly asks for status,
   or once the terminal marker exists.

Never keep a persistent AI goal or session active simply to poll a local job.
Never schedule periodic model wake-ups unless the user explicitly approves the
cadence and a token budget. The zero-token watchdog is the default.

## Watchdog record

Each local check should record only the information needed to diagnose health:

- timestamp and state (`running`, `alert`, `failed`, or `complete`);
- controller/main PID, worker count, active worker count, and compact CPU/RAM
  samples;
- current stage, fold, batch/spec, and the exact active parameter identifier;
- log and checkpoint age and byte size;
- checkpoint item count or last completed unit when cheaply available;
- artifact count and completion-marker state;
- counts of new warning categories and fatal signatures.

The watchdog may classify a stall only from multiple signals, such as a live
process combined with stale log, checkpoint, and CPU activity. A single quiet
CPU sample during aggregation is not a stall.

## Output limits

AI inspection must be intentionally bounded:

- prefer the compact watchdog record over the raw run log;
- use targeted `tail`, line-limited `rg`, or a small parser summary;
- always exclude generated HTML, caches, binary artifacts, and result trees
  from broad repository searches unless one is the explicit target;
- never load an entire warning stream or a generated summary that embeds all
  warnings;
- wrap R validators in `invisible()` or `capture.output()` when their return
  values are large;
- set conservative command-output limits and inspect a narrower second slice
  only when the first establishes a reason.

Truncated output is not harmless: producing or ingesting it can still waste
tokens and hide the relevant evidence.

## Failure and relaunch

On an alert, preserve the last valid checkpoint and all logs. Diagnose the first
useful error with bounded reads. Relaunch only after identifying a minimal fix,
and resume only from a checkpoint whose schema and provenance pass validation.
Do not restart a healthy run merely because historical numerical comparisons
differ; record those as reproducibility findings for a separate decision.

The watchdog itself should not attempt speculative code changes. It may stop
polling, write an alert marker, and preserve a concise diagnostic packet for the
next AI or human review.

## Budget gate

Before any model-assisted monitoring that extends beyond the launch turn, state
the expected duration, check frequency, model-invocation count, and token cap.
Obtain explicit user approval. Without that approval, use local monitoring and
return control to the user.

At completion, report compute duration separately from AI usage. A long local
run does not justify a long-running AI session.

## Incident lesson: July 29–30, 2026

A PAGe reproduction job ran locally for about 9 hours 53 minutes. Keeping a
persistent AI monitoring goal active around it consumed approximately 2.03
million tokens over 10 hours 16 minutes. Repeated continuations reprocessed
large context, warning-heavy logs were inspected too broadly, and one validator
printed large R objects. The local watchdog had already been sufficient to
record hourly health.

The corrective rule is permanent: local watchdog first, bounded AI review only
on exception or completion, and no recurring AI supervision without an explicit
budget.
