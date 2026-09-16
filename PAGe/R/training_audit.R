# Reproduction evidence for runners; never changes an initialized RNG stream.
.page_rng_snapshot <- function() {
  list(kind = RNGkind(), state = if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) {
    get(".Random.seed", .GlobalEnv, inherits = FALSE)
  } else NULL, seed = getOption("page.run_seed", NULL))
}

.page_dependency_versions <- function() {
  installed <- utils::installed.packages()
  dependencies <- tools::package_dependencies("PAGe", db = installed,
    which = c("Depends", "Imports", "LinkingTo"), recursive = TRUE)[["PAGe"]]
  packages <- sort(unique(c("PAGe", dependencies, loadedNamespaces())))
  packages <- intersect(packages, rownames(installed))
  stats::setNames(as.character(installed[packages, "Version"]), packages)
}

.page_training_audit <- function(expr, directory, max_messages = 50L) {
  # Initialize R's default stream only when none exists, then save the exact
  # state immediately before training. An explicit runner seed is optional.
  if (!exists(".Random.seed", .GlobalEnv, inherits = FALSE)) invisible(stats::runif(1L))
  start <- .page_rng_snapshot()
  old <- options(page.run_rng_start = start)
  on.exit(options(old), add = TRUE)
  counts <- integer()
  overflow <- 0L
  success <- FALSE
  manifest <- function() list(
    rng_start = start, rng_current = .page_rng_snapshot(),
    package_versions = .page_dependency_versions(), session_info = utils::sessionInfo(),
    captured_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  saveRDS(manifest(), file.path(directory, "training_start_manifest.rds"))
  on.exit({
    summary <- list(messages = data.frame(message = names(counts), count = unname(counts)),
      overflow_count = overflow, total = sum(counts) + overflow)
    post <- manifest()
    post$success <- success
    post$warnings <- summary
    saveRDS(post, file.path(directory, "post_training_manifest.rds"))
    saveRDS(summary, file.path(directory, "warning_summary.rds"))
    if (summary$total > 0L) {
      message("Training warnings: ", summary$total, " total; ", length(counts),
        " retained messages; ", overflow, " overflow. See warning_summary.rds.")
    }
  }, add = TRUE)
  result <- withCallingHandlers(force(expr), warning = function(w) {
    key <- substr(conditionMessage(w), 1L, 1000L)
    if (key %in% names(counts)) {
      counts[[key]] <<- counts[[key]] + 1L
    } else if (length(counts) < max_messages) {
      counts[[key]] <<- 1L
    } else {
      overflow <<- overflow + 1L
    }
    invokeRestart("muffleWarning")
  })
  success <- TRUE
  result
}
