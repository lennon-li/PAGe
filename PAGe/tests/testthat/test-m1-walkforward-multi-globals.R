# m1_walkforward_multi() used to subset allD/season_references/season_ignition
# INSIDE the mapped lambda. Under furrr that makes all three whole objects
# globals of the worker closure, so future tried to export the entire
# season_references cache (>600 MiB on an 11-season fit) to every worker. That
# both tripped future's 500 MiB maxSizeOfObjects guard -- killing the 2022-23
# outer fold at the M2 stage after M0/M1 had already completed -- and, had the
# guard been raised instead, would have shipped the full cache to all 16 cores
# on every call. Tasks are now materialised per season before mapping.

wfm_globals_test_data <- function(seasons = c("A", "B")) {
  data.frame(
    season = rep(seasons, each = 4L),
    weekF = rep(seq_len(4L), length(seasons)),
    y = rep(c(1, 2, 3, 4), length(seasons)),
    N = 10,
    nW_true = 4L,
    stringsAsFactors = FALSE
  )
}

# A per-season cache whose entries are individually small but whose total is
# large, so capturing the whole list is measurably different from capturing
# one slice.
wfm_globals_test_refs <- function(seasons = c("A", "B"), payload_n = 3e5) {
  stats::setNames(
    lapply(seasons, function(s) {
      list(
        ref = list(season = s, bulk = stats::runif(payload_n)),
        hyper = list(season = s)
      )
    }),
    seasons
  )
}

test_that("the mapped closure does not capture the whole season_references cache", {
  captured <- new.env(parent = emptyenv())
  seasons <- c("A", "B")
  refs <- wfm_globals_test_refs(seasons)
  big <- as.numeric(utils::object.size(refs))

  local_mocked_bindings(
    map = function(.x, .f, ...) {
      captured$fn <- .f
      captured$x <- .x
      lapply(.x, .f)
    },
    .package = "purrr"
  )
  local_mocked_bindings(
    m1_walkforward_predictions = function(seasonD, ref, hyper, ...) {
      data.frame(season = ref$season, stringsAsFactors = FALSE)
    }
  )

  out <- PAGe:::m1_walkforward_multi(
    allD = wfm_globals_test_data(seasons),
    ref = NULL, hyper = NULL, params = list(),
    seasons = seasons,
    season_references = refs,
    parallel = FALSE,
    verbose = FALSE
  )

  expect_equal(sort(out$season), sort(seasons))

  # The closure's enclosing frame is m1_walkforward_multi()'s own environment.
  # It must no longer hold the cache, the raw data, or the ignition list.
  env <- environment(captured$fn)
  for (nm in c("allD", "season_references", "season_ignition", "ref", "hyper")) {
    expect_null(get0(nm, envir = env, inherits = FALSE))
  }

  # Each mapped element carries exactly one season's slice, so the per-task
  # payload stays far below the size of the full cache.
  expect_length(captured$x, length(seasons))
  per_task <- max(vapply(captured$x, function(t) {
    as.numeric(utils::object.size(t))
  }, numeric(1)))
  expect_lt(per_task, big * 0.75)
})

test_that("each season is routed its own reference and ignition entry", {
  seen <- new.env(parent = emptyenv())
  seen$rows <- list()
  seasons <- c("A", "B")

  local_mocked_bindings(
    m1_walkforward_predictions = function(seasonD, ref, hyper, ign_out, ...) {
      seen$rows[[length(seen$rows) + 1L]] <- list(
        ref = ref$season, hyper = hyper$season, ign = ign_out,
        n_rows = nrow(seasonD),
        data_seasons = unique(as.character(seasonD$season))
      )
      data.frame(season = ref$season, stringsAsFactors = FALSE)
    }
  )

  PAGe:::m1_walkforward_multi(
    allD = wfm_globals_test_data(seasons),
    ref = NULL, hyper = NULL, params = list(),
    seasons = seasons,
    season_references = wfm_globals_test_refs(seasons, payload_n = 10L),
    season_ignition = list(A = "ign-A", B = "ign-B"),
    parallel = FALSE,
    verbose = FALSE
  )

  expect_length(seen$rows, 2L)
  for (i in seq_along(seasons)) {
    r <- seen$rows[[i]]
    expect_equal(r$ref, seasons[i])
    expect_equal(r$hyper, seasons[i])
    expect_equal(r$ign, paste0("ign-", seasons[i]))
    expect_equal(r$data_seasons, seasons[i])
    expect_equal(r$n_rows, 4L)
  }
})

test_that("a season missing its reference still fails fast", {
  expect_error(
    PAGe:::m1_walkforward_multi(
      allD = wfm_globals_test_data(c("A", "B")),
      ref = NULL, hyper = NULL, params = list(),
      seasons = c("A", "B"),
      season_references = list(A = list(ref = list(), hyper = list())),
      parallel = FALSE,
      verbose = FALSE
    ),
    "Missing M1 reference for season: B"
  )
})
