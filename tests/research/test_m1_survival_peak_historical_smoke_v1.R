#!/usr/bin/env Rscript

root <- normalizePath(".", mustWork = TRUE)
for (nm in c("protocol", "features", "model", "evaluate", "nested"))
  sys.source(file.path(root, "scripts", paste0("m1_survival_peak_", nm, ".R")), envir = .GlobalEnv)
adapter <- file.path(root, "scripts/run_m1_survival_peak_historical_smoke_v1.R")
invisible(parse(adapter))
sys.source(adapter, envir = .GlobalEnv)

must_fail <- function(expr, pattern) {
  err <- tryCatch({ force(expr); NULL }, error = identity)
  if (is.null(err) || !grepl(pattern, conditionMessage(err), fixed = TRUE))
    stop("Expected fail-closed error containing: ", pattern, call. = FALSE)
}

pre <- sp_m1sm_preflight(root)
stopifnot(length(pre$preflight$mature_seasons) == 11L,
  all(pre$labels$mature), all(pre$labels$season %in% sp_m1sm_seasons),
  identical(pre$calendar$W[match(sp_m1sm_seasons, pre$calendar$season)],
    c(52L, 52L, 53L, 52L, 52L, 52L, 52L, 52L, 52L, 52L, 53L)),
  all(nzchar(pre$calendar$source)), all(nzchar(pre$calendar$source_hash)),
  identical(as.integer(sp_round_peak(c(26.5, 26.49))), c(27L, 26L)))

bad_observations <- rbind(pre$observations,
  data.frame(season = "2012-13", weekF = 53, y = 1, N = 100))
must_fail(sp_preflight_panel(bad_observations, pre$labels, pre$calendar, pre$protocol),
  "Observed weekF/calendar mismatch")

script <- file.path("scripts", "run_m1_survival_peak_historical_smoke_v1.R")
unauthorized <- system2("Rscript", c(script), stdout = TRUE, stderr = TRUE)
if (is.null(attr(unauthorized, "status")) || attr(unauthorized, "status") == 0L ||
    !any(grepl("requires explicit --authorize-historical-smoke", unauthorized, fixed = TRUE)))
  stop("Adapter did not fail closed without explicit historical-smoke authorization.", call. = FALSE)
full <- system2("Rscript", c(script, "--authorize-historical-smoke", "--full-loso"), stdout = TRUE, stderr = TRUE)
if (is.null(attr(full, "status")) || attr(full, "status") == 0L ||
    !any(grepl("Full historical LOSO is refused", full, fixed = TRUE)))
  stop("Adapter did not refuse full historical LOSO.", call. = FALSE)

cat("PASS: historical smoke adapter preflight and fail-closed authorization\n")
