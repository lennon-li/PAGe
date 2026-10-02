# Select a local future backend without requiring a TCP socket on Unix hosts.

.page_set_parallel_plan <- function(workers) {
  workers <- max(1L, as.integer(workers))
  if (workers == 1L) {
    return(future::plan(future::sequential))
  }

  requested <- tolower(trimws(Sys.getenv("PAGE_FUTURE_BACKEND", "auto")))
  if (!requested %in% c("auto", "multicore", "multisession")) {
    stop(
      "`PAGE_FUTURE_BACKEND` must be `auto`, `multicore`, or `multisession`.",
      call. = FALSE
    )
  }

  backend <- if (requested == "auto") {
    if (.Platform$OS.type != "windows" && future::supportsMulticore()) {
      "multicore"
    } else {
      "multisession"
    }
  } else {
    requested
  }

  if (backend == "multicore") {
    if (.Platform$OS.type == "windows" || !future::supportsMulticore()) {
      stop(
        "`PAGE_FUTURE_BACKEND=multicore` is unavailable on this host; use ",
        "`auto` or `multisession`.",
        call. = FALSE
      )
    }
    return(future::plan(future::multicore, workers = workers))
  }

  future::plan(future::multisession, workers = workers)
}
