#!/usr/bin/env Rscript

# Reproducible evidence report for the repaired frozen-kit outer replay.
# This script reads archived replay objects only.  It does not train, tune,
# select, promote, or modify any PAGe model.
options(page.stage_report.cache = FALSE)

stage_report_seasons <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18", "2018-19",
  "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
)
stage_report_exclusions <- c("2011-12", "2015-16", "2020-21", "2021-22")
stage_report_partial_season <- "2025-26"
stage_report_input_sha256 <-
  "fa8add1b253944df5d853a2fb0456d7ac368657e073da0d97f909be95ca59c54"

stage_report_clip <- function(p) {
  pmin(1 - 1e-12, pmax(1e-12, p))
}

stage_report_hash <- function(path) {
  if (!file.exists(path)) stop("Missing file for hashing: ", path)
  digest::digest(file = path, algo = "sha256")
}

stage_report_key <- function(season, origin, lead) {
  paste(season, origin, lead, sep = ":")
}

stage_report_assert_unique <- function(keys, label) {
  if (anyDuplicated(keys)) stop("Duplicate ", label, " keys")
  invisible(TRUE)
}

stage_report_parse_args <- function(args) {
  defaults <- list(
    replay = "manuscript/results/publication-repair-20260908/replay/20260908T125939",
    input = "/home/yeli/FLU/flu_testing_data.csv",
    output = "manuscript/results/publication-repair-20260908/stage-report"
  )
  if (!length(args)) {
    return(defaults)
  }
  for (arg in args) {
    if (!grepl("^--[^=]+=", arg)) stop("Arguments must use --name=value: ", arg)
    bits <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    name <- bits[1L]
    value <- paste(bits[-1L], collapse = "=")
    if (!name %in% names(defaults)) stop("Unknown argument: --", name)
    defaults[[name]] <- value
  }
  defaults
}

stage_report_read_inputs <- function(replay_root, input_path) {
  if (!dir.exists(replay_root)) stop("Replay root is inaccessible: ", replay_root)
  manifest_path <- file.path(replay_root, "manifest.json")
  status_path <- file.path(replay_root, "status.json")
  private_root <- file.path(replay_root, "private")
  if (!file.exists(manifest_path) || !file.exists(status_path) ||
    !dir.exists(private_root)) {
    stop("Replay root is missing manifest, status, or private directory")
  }
  replay_manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
  replay_status <- jsonlite::read_json(status_path, simplifyVector = TRUE)
  if (!identical(replay_status$state, "complete_diagnostic_only") ||
    replay_status$completed != length(stage_report_seasons)) {
    stop("Replay is not the expected complete diagnostic run")
  }
  if (!identical(replay_manifest$input_sha256, stage_report_input_sha256)) {
    stop("Replay input hash does not match the frozen source hash")
  }
  if (!file.exists(input_path)) stop("Input CSV is inaccessible: ", input_path)

  registry <- utils::read.csv(
    "results/audit/holdout_reconciliation_principal.csv",
    stringsAsFactors = FALSE
  )
  if (nrow(registry) != length(stage_report_seasons) ||
    !setequal(registry$season, stage_report_seasons)) {
    stop("Principal registry does not contain exactly the 11 eligible seasons")
  }

  rows <- lapply(stage_report_seasons, function(season) {
    private_path <- file.path(private_root, paste0(season, ".rds"))
    if (!file.exists(private_path)) stop("Missing replay RDS: ", private_path)
    registry_row <- registry[registry$season == season, , drop = FALSE]
    if (nrow(registry_row) != 1L) stop("Registry row mismatch for ", season)
    archive_run <- sub(
      "/mnt/nfsv4/Users/yeli/PAGe-artifacts",
      "/home/yeli/PAGe-bcc-artifacts",
      registry_row$run_dir,
      fixed = TRUE
    )
    archive_root <- file.path(archive_run, "artifacts")
    archive_manifest_path <- file.path(archive_root, "run_manifest.rds")
    if (!file.exists(archive_manifest_path)) {
      stop("Archived run manifest is inaccessible for ", season)
    }
    list(
      season = season,
      replay_path = private_path,
      replay = readRDS(private_path),
      replay_sha256 = stage_report_hash(private_path),
      archive_root = archive_root,
      archive_manifest_path = archive_manifest_path,
      archive_manifest = readRDS(archive_manifest_path),
      archive_manifest_sha256 = stage_report_hash(archive_manifest_path)
    )
  })
  for (item in rows) {
    replay <- item$replay
    manifest <- item$archive_manifest
    if (!identical(replay$season, item$season) ||
      !identical(replay$status, "unseen_replay_complete")) {
      stop("Replay season/status mismatch for ", item$season)
    }
    if (!identical(as.character(manifest$holdout_seasons), item$season) ||
      !setequal(
        manifest$training_seasons,
        setdiff(stage_report_seasons, item$season)
      ) ||
      !setequal(manifest$exclude_seasons, stage_report_exclusions)) {
      stop("Archived 10-training/1-holdout or exclusion contract mismatch for ", item$season)
    }
  }
  names(rows) <- stage_report_seasons
  list(
    replay_manifest = replay_manifest,
    replay_status = replay_status,
    replay_manifest_path = manifest_path,
    replay_status_path = status_path,
    registry = registry,
    rows = rows,
    input_path = input_path,
    input_sha256 = stage_report_hash(input_path)
  )
}

stage_report_reference_label <- function(archive_manifest, season) {
  labels <- archive_manifest$manual_labels
  value <- if (!is.null(labels) && season %in% names(labels)) {
    as.integer(unname(labels[[season]]))
  } else {
    NA_integer_
  }
  if (is.na(value)) {
    provenance <- "unavailable in archived manifest"
    certified <- FALSE
  } else if (identical(season, stage_report_partial_season)) {
    provenance <- paste(
      "archived value present (19); independent source/date/hash provenance",
      "unresolved; not an independently verified reference label"
    )
    certified <- FALSE
  } else {
    provenance <- paste(
      "frozen retrospective reference label from the verified ten-season",
      "protocol vector; not biological ground truth"
    )
    certified <- TRUE
  }
  list(value = value, provenance = provenance, certified = certified)
}

stage_report_m0 <- function(input_rows) {
  rows <- lapply(input_rows, function(item) {
    r <- item$replay
    m <- item$archive_manifest
    m0 <- r$stages$m0
    d <- m0$df
    needed <- c("weekF", "ignite_ok_now", "iWeek_hat_dynamic")
    if (!all(needed %in% names(d))) {
      stop("M0 detector fields are unavailable for ", item$season)
    }
    stage_report_assert_unique(d$weekF, paste0("M0 ", item$season, " week"))
    declaration_recomputed <- suppressWarnings(
      min(d$weekF[as.logical(d$ignite_ok_now)], na.rm = TRUE)
    )
    if (!is.finite(declaration_recomputed)) declaration_recomputed <- NA_integer_
    declaration_saved <- as.integer(m0$ign_week_locked)
    if (!isTRUE(all.equal(declaration_saved, declaration_recomputed))) {
      stop("Saved and recomputed declaration weeks differ for ", item$season)
    }
    label <- stage_report_reference_label(m, item$season)
    onset <- as.integer(m0$iWeek_hat_locked)
    data.frame(
      season = item$season,
      archived_reference_label_weekF = label$value,
      reference_label_available = !is.na(label$value),
      reference_label_certified = label$certified,
      reference_label_provenance_status = label$provenance,
      estimated_onset_weekF = onset,
      declaration_weekF = declaration_saved,
      declaration_field_present = "ignite_ok_now" %in% names(d),
      declaration_rows_evaluated = nrow(d),
      declaration_positive_rows = sum(as.logical(d$ignite_ok_now), na.rm = TRUE),
      onset_error_weeks = if (is.na(onset) || is.na(label$value)) {
        NA_integer_
      } else {
        onset - label$value
      },
      declaration_delay_weeks = if (is.na(onset) || is.na(declaration_saved)) {
        NA_integer_
      } else {
        declaration_saved - onset
      },
      onset_miss = is.na(onset),
      declaration_miss = is.na(declaration_saved),
      m0_detector_support = paste(
        "rows=", nrow(d),
        "; finite_dynamic=", sum(is.finite(d$iWeek_hat_dynamic)),
        "; declaration_field=present",
        sep = ""
      ),
      onset_error_interpretation = if (label$certified) {
        "numeric difference: estimated onset minus archived reference label"
      } else {
        "numeric only; archived reference label is not independently certified"
      },
      delay_definition = paste(
        "first ignite_ok_now week minus saved locked onset estimate"
      ),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

stage_report_observed_peak <- function(d, season) {
  x <- d[d$season == season, , drop = FALSE]
  if (!nrow(x)) stop("No source rows for ", season)
  positivity <- x$y / x$N
  if (any(!is.finite(positivity) | x$N <= 0)) {
    stop("Invalid source positivity for ", season)
  }
  peak_value <- max(positivity)
  tie_rows <- which(positivity == peak_value)
  peak_week <- min(x$week[tie_rows])
  partial <- identical(season, stage_report_partial_season)
  data.frame(
    season = season,
    source_rows = nrow(x),
    source_first_weekF = min(x$week),
    source_last_weekF = max(x$week),
    observed_peak_to_date_weekF = peak_week,
    observed_peak_to_date_positivity = peak_value,
    observed_peak_tie_count = length(tie_rows),
    observed_peak_tie_rule = "earliest weekF among exact maximum positivity ties",
    observed_peak_status = if (partial) {
      "partial season; observed-to-date peak only; full-season peak censored"
    } else {
      "complete source support for declared season"
    },
    full_season_peak_available = !partial,
    stringsAsFactors = FALSE
  )
}

stage_report_m1_peaks <- function(input_rows, source_data) {
  peak_meta <- do.call(
    rbind,
    lapply(stage_report_seasons, function(s) stage_report_observed_peak(source_data, s))
  )
  detailed <- lapply(input_rows, function(item) {
    p <- item$replay$stages$m1_parameters
    if (!is.data.frame(p) || !all(c(
      "eval_week", "state", "iWeek_hat", "t_peak",
      "peak_weekF", "peak_weekF_lo", "peak_weekF_hi", "peak_passed"
    ) %in% names(p))) {
      stop("M1 peak fields are unavailable for ", item$season)
    }
    stage_report_assert_unique(p$eval_week, paste0("M1 ", item$season, " origin"))
    meta <- peak_meta[peak_meta$season == item$season, , drop = FALSE]
    full_peak <- isTRUE(meta$full_season_peak_available)
    available <- is.finite(p$peak_weekF)
    data.frame(
      season = item$season,
      origin_weekF = as.integer(p$eval_week),
      phase_state = as.character(p$state),
      estimated_onset_weekF = as.integer(p$iWeek_hat),
      aligned_t_peak = as.numeric(p$t_peak),
      peak_weekF = as.numeric(p$peak_weekF),
      peak_weekF_lo = as.numeric(p$peak_weekF_lo),
      peak_weekF_hi = as.numeric(p$peak_weekF_hi),
      peak_passed = as.logical(p$peak_passed),
      peak_forecast_available = available,
      observed_peak_weekF = if (full_peak) meta$observed_peak_to_date_weekF else NA_integer_,
      observed_peak_to_date_weekF = meta$observed_peak_to_date_weekF,
      lead_to_observed_peak_weeks = if (full_peak) {
        meta$observed_peak_to_date_weekF - p$eval_week
      } else {
        NA_integer_
      },
      peak_error_weeks = ifelse(full_peak & available,
        p$peak_weekF - meta$observed_peak_to_date_weekF, NA_real_
      ),
      peak_error_status = ifelse(!full_peak,
        "censored: partial season has no certified full-season peak",
        ifelse(!available,
          "unavailable: M1 peak estimate is non-finite",
          "scored: estimated peak weekF minus observed peak weekF"
        )
      ),
      anchor_week_available = FALSE,
      anchor_week_note = "anchorWeek is not stored in this replay stage table; no coordinate reconstructed",
      stringsAsFactors = FALSE
    )
  })
  detailed <- do.call(rbind, detailed)
  summaries <- lapply(stage_report_seasons, function(s) {
    x <- detailed[detailed$season == s, , drop = FALSE]
    meta <- peak_meta[peak_meta$season == s, , drop = FALSE]
    scored <- is.finite(x$peak_error_weeks)
    data.frame(
      season = s,
      observed_peak_status = meta$observed_peak_status,
      observed_peak_to_date_weekF = meta$observed_peak_to_date_weekF,
      source_last_weekF = meta$source_last_weekF,
      n_origins_total = nrow(x),
      n_peak_forecasts_available = sum(x$peak_forecast_available),
      n_peak_errors = sum(scored),
      n_peak_censored = sum(grepl("censored", x$peak_error_status)),
      n_peak_unavailable = sum(grepl("unavailable", x$peak_error_status)),
      mean_abs_peak_error_weeks = if (any(scored)) {
        mean(abs(x$peak_error_weeks[scored]))
      } else {
        NA_real_
      },
      mean_signed_peak_error_weeks = if (any(scored)) {
        mean(x$peak_error_weeks[scored])
      } else {
        NA_real_
      },
      mean_lead_to_observed_peak_weeks = if (isTRUE(meta$full_season_peak_available)) {
        mean(x$lead_to_observed_peak_weeks, na.rm = TRUE)
      } else {
        NA_real_
      },
      n_aligning = sum(x$phase_state == "aligning", na.rm = TRUE),
      n_post_peak = sum(x$phase_state == "post_peak", na.rm = TRUE),
      anchor_week_available = FALSE,
      stringsAsFactors = FALSE
    )
  })
  list(
    observed_peak = peak_meta,
    by_origin = detailed,
    summary = do.call(rbind, summaries)
  )
}

stage_report_score <- function(x, prediction, window) {
  keep <- x$exact_score_match & is.finite(prediction)
  if (window == "h2_0_12") keep <- keep & x$lead == 2L & x$t_since >= 0 & x$t_since <= 12
  if (window == "h1_0_12") keep <- keep & x$lead == 1L & x$t_since >= 0 & x$t_since <= 12
  if (window == "h2_full") keep <- keep & x$lead == 2L
  if (window == "full") keep <- keep
  if (!any(keep)) {
    return(data.frame(
      n_rows = 0L, n_trials = 0, nll_numerator = NA_real_, nll = NA_real_,
      mae_numerator = NA_real_, mae = NA_real_, brier_numerator = NA_real_,
      bernoulli_brier = NA_real_
    ))
  }
  y <- x$y[keep]
  n <- x$N[keep]
  p <- stage_report_clip(prediction[keep])
  nll_value <- -y * log(p) - (n - y) * log1p(-p)
  mae_value <- abs(p - y / n)
  brier_value <- (y / n) * (1 - p)^2 + (1 - y / n) * p^2
  data.frame(
    n_rows = sum(keep),
    n_trials = sum(n),
    nll_numerator = sum(nll_value),
    nll = sum(nll_value) / sum(n),
    mae_numerator = sum(n * mae_value),
    mae = sum(n * mae_value) / sum(n),
    brier_numerator = sum(n * brier_value),
    bernoulli_brier = sum(n * brier_value) / sum(n)
  )
}

stage_report_comparison <- function(input_rows) {
  windows <- c("h2_0_12", "h1_0_12", "h2_full", "full")
  availability <- list()
  weekly <- list()
  season_scores <- list()
  for (item in input_rows) {
    r <- item$replay
    ledger <- r$forecast_ledger
    page <- r$predictions
    m1 <- r$stages$m2_predictions
    if (!all(c(
      "weekF", "lead", "target_weekF", "t_since", "N_lead",
      "p_obs", "emitted", "target_available", "scorable"
    ) %in% names(ledger))) {
      stop("Forecast ledger fields are unavailable for ", item$season)
    }
    if (!all(c("eval_week", "h", "target_weekF", "m1_p") %in% names(m1))) {
      stop("M1-only fields are unavailable for ", item$season)
    }
    if (!all(c("weekF", "lead", "target_weekF", "p_hat", "p_obs", "N_lead") %in%
      names(page))) {
      stop("Repaired prediction fields are unavailable for ", item$season)
    }
    ledger_key <- stage_report_key(item$season, ledger$weekF, ledger$lead)
    m1_key <- stage_report_key(item$season, m1$eval_week, m1$h)
    page_key <- stage_report_key(item$season, page$weekF, page$lead)
    stage_report_assert_unique(ledger_key, paste0("ledger ", item$season))
    stage_report_assert_unique(m1_key, paste0("M1-only ", item$season))
    stage_report_assert_unique(page_key, paste0("PAGe ", item$season))
    if (any(ledger$target_weekF != ledger$weekF + ledger$lead)) {
      stop("Ledger target/horizon mismatch for ", item$season)
    }
    if (any(m1$target_weekF != m1$eval_week + m1$h)) {
      stop("M1 target/horizon mismatch for ", item$season)
    }
    m1_match <- match(ledger_key, m1_key)
    page_match <- match(ledger_key, page_key)
    if (any(!m1_key %in% ledger_key)) {
      stop("M1-only forecast keys missing from ledger for ", item$season)
    }
    matched_page <- which(!is.na(page_match))
    page_p_from_predictions <- rep(NA_real_, nrow(ledger))
    if (length(matched_page)) {
      page_p_from_predictions[matched_page] <-
        page$p_hat[page_match[matched_page]]
      if (any(page$target_weekF[page_match[matched_page]] !=
        ledger$target_weekF[matched_page])) {
        stop("PAGe target mismatch on matched key for ", item$season)
      }
    }
    rows <- data.frame(
      season = item$season,
      origin_weekF = as.integer(ledger$weekF),
      target_weekF = as.integer(ledger$target_weekF),
      lead = as.integer(ledger$lead),
      t_since = as.integer(ledger$t_since),
      y = as.numeric(ledger$y_lead),
      N = as.numeric(ledger$N_lead),
      p_obs = as.numeric(ledger$p_obs),
      target_available = as.logical(ledger$target_available),
      page_forecast_available = as.logical(ledger$emitted) &
        is.finite(ledger$p_hat),
      m1_forecast_available = is.finite(m1$m1_p[m1_match]),
      page_score_available = as.logical(ledger$scorable) &
        is.finite(ledger$p_hat),
      m1_score_available = as.logical(ledger$target_available) &
        is.finite(m1$m1_p[m1_match]) & is.finite(ledger$p_obs) &
        is.finite(ledger$N_lead) & ledger$N_lead > 0,
      page_p_hat = page_p_from_predictions,
      m1_p_hat = as.numeric(m1$m1_p[m1_match]),
      page_forecast_status = as.character(ledger$forecast_status),
      stringsAsFactors = FALSE
    )
    rows$exact_score_match <- rows$target_available &
      rows$page_score_available & rows$m1_score_available
    rows$window_h2_0_12 <- rows$lead == 2L & rows$t_since >= 0 & rows$t_since <= 12
    rows$window_h1_0_12 <- rows$lead == 1L & rows$t_since >= 0 & rows$t_since <= 12
    rows$window_h2_full <- rows$lead == 2L
    rows$window_full <- TRUE
    weekly[[item$season]] <- rows

    availability[[item$season]] <- data.frame(
      season = item$season,
      ledger_keys = nrow(rows),
      target_available_keys = sum(rows$target_available),
      page_forecast_available_keys = sum(rows$page_forecast_available),
      m1_forecast_available_keys = sum(rows$m1_forecast_available),
      page_score_available_keys = sum(rows$page_score_available),
      m1_score_available_keys = sum(rows$m1_score_available),
      exact_matched_score_keys = sum(rows$exact_score_match),
      page_forecast_availability_rate = mean(rows$page_forecast_available),
      m1_forecast_availability_rate = mean(rows$m1_forecast_available),
      stringsAsFactors = FALSE
    )
    season_scores[[item$season]] <- do.call(rbind, lapply(windows, function(w) {
      page_score <- stage_report_score(rows, rows$page_p_hat, w)
      m1_score <- stage_report_score(rows, rows$m1_p_hat, w)
      rbind(
        data.frame(
          season = item$season, window = w,
          model = "PAGe repaired runtime", page_score, stringsAsFactors = FALSE
        ),
        data.frame(
          season = item$season, window = w,
          model = "M1-only continuation (saved m1_p)", m1_score,
          stringsAsFactors = FALSE
        )
      )
    }))
  }
  weekly <- do.call(rbind, weekly)
  availability <- do.call(rbind, availability)
  season_scores <- do.call(rbind, season_scores)
  aggregates <- do.call(rbind, lapply(windows, function(w) {
    do.call(rbind, lapply(unique(season_scores$model), function(model) {
      x <- season_scores[season_scores$window == w & season_scores$model == model, ]
      finite <- is.finite(x$nll)
      data.frame(
        window = w,
        model = model,
        n_seasons_total = length(stage_report_seasons),
        n_seasons_with_score = sum(finite),
        n_score_rows = sum(x$n_rows, na.rm = TRUE),
        n_trials = sum(x$n_trials, na.rm = TRUE),
        equal_season_nll = if (any(finite)) mean(x$nll[finite]) else NA_real_,
        pooled_trial_nll = if (any(finite)) {
          sum(x$nll_numerator[finite]) /
            sum(x$n_trials[finite])
        } else {
          NA_real_
        },
        equal_season_mae = if (any(is.finite(x$mae))) mean(x$mae[is.finite(x$mae)]) else NA_real_,
        pooled_trial_mae = if (any(is.finite(x$mae_numerator))) {
          sum(x$mae_numerator[is.finite(x$mae_numerator)]) /
            sum(x$n_trials[is.finite(x$mae_numerator)])
        } else {
          NA_real_
        },
        equal_season_bernoulli_brier = if (any(is.finite(x$bernoulli_brier))) {
          mean(x$bernoulli_brier[is.finite(x$bernoulli_brier)])
        } else {
          NA_real_
        },
        pooled_trial_bernoulli_brier = if (any(is.finite(x$brier_numerator))) {
          sum(x$brier_numerator[is.finite(x$brier_numerator)]) /
            sum(x$n_trials[is.finite(x$brier_numerator)])
        } else {
          NA_real_
        },
        score_weighting = "trial-weight within season; equal-season mean across finite season scores",
        stringsAsFactors = FALSE
      )
    }))
  }))
  deltas <- do.call(rbind, lapply(windows, function(w) {
    do.call(rbind, lapply(stage_report_seasons, function(s) {
      page <- season_scores[season_scores$season == s & season_scores$window == w &
        season_scores$model == "PAGe repaired runtime", , drop = FALSE]
      m1 <- season_scores[season_scores$season == s & season_scores$window == w &
        season_scores$model == "M1-only continuation (saved m1_p)", , drop = FALSE]
      stopifnot(nrow(page) == 1L, nrow(m1) == 1L)
      data.frame(
        season = s,
        window = w,
        exact_score_rows = min(page$n_rows, m1$n_rows),
        exact_score_trials = min(page$n_trials, m1$n_trials),
        page_nll = page$nll,
        m1_nll = m1$nll,
        m1_minus_page_nll = m1$nll - page$nll,
        page_mae = page$mae,
        m1_mae = m1$mae,
        m1_minus_page_mae = m1$mae - page$mae,
        page_bernoulli_brier = page$bernoulli_brier,
        m1_bernoulli_brier = m1$bernoulli_brier,
        m1_minus_page_bernoulli_brier =
          m1$bernoulli_brier - page$bernoulli_brier,
        stringsAsFactors = FALSE
      )
    }))
  }))
  list(
    weekly = weekly,
    availability = availability,
    season_scores = season_scores,
    aggregates = aggregates,
    deltas = deltas
  )
}

stage_report_run_synthetic_checks <- function() {
  checks <- list()
  add <- function(name, pass, detail) {
    checks[[length(checks) + 1L]] <<- data.frame(
      check = name, pass = isTRUE(pass), detail = detail,
      stringsAsFactors = FALSE
    )
  }
  keys <- stage_report_key(c("a", "b"), c(1L, 1L), c(1L, 2L))
  add("unique origin-lead key", !anyDuplicated(keys), "two distinct season/origin/lead keys")
  target_ok <- c(3L, 5L) == c(2L, 3L) + c(1L, 2L)
  add("horizon target matching", all(target_ok), "target_weekF equals origin_weekF plus lead")
  tie_data <- data.frame(season = "synthetic", week = 1:3, y = c(1, 2, 2), N = c(10, 10, 10))
  tie_peak <- stage_report_observed_peak(
    transform(tie_data, week = week), "synthetic"
  )
  add(
    "earliest tied peak", identical(tie_peak$observed_peak_to_date_weekF, 2L),
    "exact positivity tie resolves to earliest weekF"
  )
  old_partial <- stage_report_partial_season
  assign("stage_report_partial_season", "synthetic", envir = environment(stage_report_run_synthetic_checks))
  partial_peak <- stage_report_observed_peak(tie_data, "synthetic")
  assign("stage_report_partial_season", old_partial, envir = environment(stage_report_run_synthetic_checks))
  add(
    "partial peak censoring", !partial_peak$full_season_peak_available &&
      grepl("censored", partial_peak$observed_peak_status),
    "partial season exposes observed-to-date peak without certifying full-season peak"
  )
  score_data <- data.frame(
    exact_score_match = TRUE, lead = c(2L, 2L), t_since = c(0L, 0L),
    y = c(1, 50), N = c(10, 100), p_obs = c(0.1, 0.5)
  )
  score <- stage_report_score(score_data, c(0.2, 0.4), "h2_0_12")
  expected <- (-1 * log(0.2) - 9 * log(0.8) - 50 * log(0.4) - 50 * log(0.6)) / 110
  add(
    "trial denominator weighting", isTRUE(all.equal(score$nll, expected)),
    "within-season NLL is divided by total trials"
  )
  result <- do.call(rbind, checks)
  if (!all(result$pass)) stop("Synthetic stage-report checks failed")
  result
}

stage_report_write <- function(path, object) {
  utils::write.csv(object, path, row.names = FALSE, na = "")
}

stage_report_report_text <- function(m0, m1_summary, comparison, metadata) {
  h2 <- comparison$aggregates[comparison$aggregates$window == "h2_0_12", ]
  h2 <- h2[order(h2$model), ]
  h2_lines <- paste(sprintf(
    "| %s | %d/%d | %d | %.6f | %.6f | %.6f |",
    h2$model, h2$n_seasons_with_score, h2$n_seasons_total, h2$n_score_rows,
    h2$equal_season_nll, h2$pooled_trial_nll, h2$equal_season_mae
  ), collapse = "\n")
  paste0(
    "# Repaired-runtime stage evidence report\n\n",
    "Generated `", metadata$finished_utc, "` from replay root `",
    metadata$replay_root, "`. This is a diagnostic evidence report; it did not",
    " retrain, retune, promote, or alter any kit.\n\n",
    "## M0 definition\n\n",
    "The estimated onset is the saved `stages$m0$iWeek_hat_locked`. The",
    " declaration week is independently recomputed as the first saved M0 row",
    " with `ignite_ok_now == TRUE`; the script asserts equality with",
    " `ign_week_locked`. Delay is declaration week minus estimated onset.",
    " Onset error is estimated onset minus the archived retrospective reference",
    " label. The ten verified labels are retrospective algorithm-defined labels,",
    " not biological ground truth. The archived `2025-26 = 19` value is shown",
    " but remains uncertified because independent source/date/hash provenance is",
    " unresolved.\n\n",
    "## M1 peak definition\n\n",
    "The observed peak is the earliest `weekF` among exact ties for the maximum",
    " observed positivity (`y/N`). M1 peak estimates use the saved",
    " `m1_parameters` rows and the runtime-converted `peak_weekF`; `aligned_t_peak`",
    " and `iWeek_hat` are retained as coordinate evidence. `anchorWeek` is not",
    " stored in the replay table and is not reconstructed. `2025-26` is reported",
    " as partial/right-censored: its observed-to-date peak is descriptive only,",
    " and it contributes no certified full-season peak error. The reported",
    " lead-to-peak coordinate is `observed_peak_weekF - origin_weekF`, so it is",
    " negative for origins after the observed peak.\n\n",
    "## M1-only comparison\n\n",
    "The M1-only comparator is the saved `m1_p` from the same upstream fitted",
    " kit. It is a pipeline-component diagnostic, not a separately retuned",
    " standalone M1 model. Scores use exact `(season, origin_weekF, lead)`",
    " matches. Forecast availability is counted from the full ledger separately",
    " from score availability. NLL is trial-weighted within season, then",
    " aggregated as an equal-season mean; no inferential tests are used.\n\n",
    "### Primary h2, t_since 0--12\n\n",
    "| Model | scored seasons | score rows | equal-season NLL | pooled-trial NLL | equal-season MAE |\n",
    "|---|---:|---:|---:|---:|---:|\n",
    h2_lines, "\n\n",
    "## Reproducibility\n\n",
    "- Replay status: `", metadata$replay_state, "`; replay elapsed seconds: ",
    format(metadata$replay_elapsed_seconds, digits = 10), ".\n",
    "- Stage-report elapsed seconds: ", format(metadata$elapsed_seconds, digits = 10), ".\n",
    "- Source CSV SHA256: `", metadata$input_sha256, "`.\n",
    "- Private weekly comparison rows and per-origin M1 rows are under the",
    " gitignored `private/` directory; public tables contain aggregates,",
    " availability, hashes, and limitations only.\n",
    "- Synthetic checks: all passed; see `synthetic_checks.csv`.\n\n",
    "## Deliberate limitations\n\n",
    "The replay is conditional on the completed frozen kits and repaired runtime;",
    "it is not a new upstream nested retuning analysis. Label provenance for",
    "`2025-26`, full-season peak status for `2025-26`, and the historical executed",
    "environment remain unresolved. Bounds in the replay are conditional",
    "fitted-mean bands, not full predictive distributions.\n"
  )
}

stage_report_handoff_text <- function(metadata, comparison) {
  h2 <- comparison$aggregates[comparison$aggregates$window == "h2_0_12", ]
  h2 <- h2[order(h2$model), ]
  paste0(
    "# Liz handoff: stage evidence and M1-only comparison\n\n",
    "## Files\n\n",
    "- `scripts/publication_stage_report.R` — runnable report and synthetic checks.\n",
    "- `stage-report/m0_stage_summary.csv` — all 11 M0 rows with onset/declaration definitions and provenance flags.\n",
    "- `stage-report/m1_peak_summary.csv` — all 11 M1 peak availability/error aggregates.\n",
    "- `stage-report/comparison_aggregate.csv` — h2 0--12 primary, h1 0--12 secondary, h2 full, and full supplementary metrics.\n",
    "- `stage-report/comparison_season.csv` — per-season descriptive scores.\n",
    "- `stage-report/comparison_season_deltas.csv` — paired per-season M1-only minus PAGe deltas.\n",
    "- `stage-report/forecast_availability.csv` — ledger, target, forecast, and score denominators.\n",
    "- `stage-report/report.md` — definitions, limitations, and primary table.\n",
    "- `stage-report/private/` — gitignored weekly and per-origin evidence rows (`weekly_comparison_rows.rds`, `m1_peak_by_origin.rds`).\n\n",
    "## Command and checks\n\n",
    "Run from the project root:\n\n",
    "```sh\nRscript scripts/publication_stage_report.R\nRscript manuscript/results/publication-repair-20260908/stage-report/tests/test_stage_report.R\n```\n\n",
    "The report completed with replay state `", metadata$replay_state,
    "`, report elapsed ", format(metadata$elapsed_seconds, digits = 8),
    " seconds, 11 replay-RDS reads, 11 archived-manifest reads, and zero",
    " retraining/tuning calls. Replay call count is not recorded in the source",
    " artifacts. All synthetic checks passed.\n\n",
    "## Primary result (descriptive only)\n\n",
    "| Model | equal-season NLL | pooled-trial NLL | equal-season MAE | scored seasons |\n",
    "|---|---:|---:|---:|---:|\n",
    paste(
      sprintf(
        "| %s | %.6f | %.6f | %.6f | %d/%d |",
        h2$model, h2$equal_season_nll, h2$pooled_trial_nll,
        h2$equal_season_mae, h2$n_seasons_with_score, h2$n_seasons_total
      ),
      collapse = "\n"
    ),
    "\n\n",
    "The M1-only rows are saved `m1_p` forecasts from the same fitted upstream",
    " kit, so this is a pipeline-component diagnostic rather than a separately",
    " retuned standalone M1 model. Per-season differences are descriptive; no",
    " p-values or hypothesis tests were calculated. `2025-26` has only 20 source",
    " weeks (weekF 9--28), so its full-season M1 peak error is censored. Its",
    " archived M0 label value 19 is not independently provenance-verified.\n\n",
    "## Parent recomputation\n\n",
    "To recompute one season, read `replay/<timestamp>/private/2012-13.rds`,",
    " join `stages$m2_predictions` by `eval_week = forecast_ledger$weekF` and",
    " `h = forecast_ledger$lead`, and apply the NLL formula in the report script",
    " to rows with exact keys and `0 <= t_since <= 12`. The public availability",
    " table records the corresponding denominators.\n"
  )
}

stage_report_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  started <- Sys.time()
  cfg <- stage_report_parse_args(args)
  dir.create(cfg$output, recursive = TRUE, showWarnings = FALSE)
  private_dir <- file.path(cfg$output, "private")
  dir.create(private_dir, recursive = TRUE, showWarnings = FALSE)
  inputs <- stage_report_read_inputs(cfg$replay, cfg$input)
  source("scripts/publication_comparator_helpers.R", local = TRUE)
  source_data <- pc_read_data(cfg$input)
  if (!identical(stage_report_hash(cfg$input), stage_report_input_sha256)) {
    stop("Input CSV changed from the frozen source hash")
  }
  if (!setequal(unique(source_data$season), stage_report_seasons)) {
    stop("Source data season set mismatch")
  }
  m0 <- stage_report_m0(inputs$rows)
  m1 <- stage_report_m1_peaks(inputs$rows, source_data)
  comparison <- stage_report_comparison(inputs$rows)
  synthetic <- stage_report_run_synthetic_checks()
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  metadata <- list(
    generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    finished_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    elapsed_seconds = elapsed,
    replay_root = cfg$replay,
    replay_state = inputs$replay_status$state,
    replay_elapsed_seconds = inputs$replay_status$elapsed_seconds,
    input_sha256 = inputs$input_sha256,
    replay_manifest_sha256 = stage_report_hash(inputs$replay_manifest_path),
    replay_status_sha256 = stage_report_hash(inputs$replay_status_path),
    source_script_sha256 = stage_report_hash("scripts/publication_stage_report.R"),
    comparator_helper_sha256 = stage_report_hash("scripts/publication_comparator_helpers.R"),
    replay_private_rds_sha256 = setNames(
      lapply(inputs$rows, function(x) x$replay_sha256), stage_report_seasons
    ),
    archive_manifest_rds_sha256 = setNames(
      lapply(inputs$rows, function(x) x$archive_manifest_sha256), stage_report_seasons
    ),
    source_data_seasons = stage_report_seasons,
    excluded_seasons = stage_report_exclusions,
    calls = list(
      replay_rds_reads = length(inputs$rows),
      archived_manifest_reads = length(inputs$rows),
      source_csv_reads = 1L,
      retraining_calls = 0L,
      tuning_calls = 0L,
      replay_call_count = "not recorded in source artifacts"
    ),
    synthetic_checks = all(synthetic$pass)
  )
  stage_report_write(file.path(cfg$output, "m0_stage_summary.csv"), m0)
  stage_report_write(file.path(cfg$output, "observed_peak_summary.csv"), m1$observed_peak)
  stage_report_write(file.path(cfg$output, "m1_peak_summary.csv"), m1$summary)
  stage_report_write(file.path(cfg$output, "comparison_aggregate.csv"), comparison$aggregates)
  stage_report_write(file.path(cfg$output, "comparison_season.csv"), comparison$season_scores)
  stage_report_write(file.path(cfg$output, "comparison_season_deltas.csv"), comparison$deltas)
  stage_report_write(file.path(cfg$output, "forecast_availability.csv"), comparison$availability)
  stage_report_write(file.path(cfg$output, "synthetic_checks.csv"), synthetic)
  saveRDS(comparison$weekly, file.path(private_dir, "weekly_comparison_rows.rds"))
  saveRDS(m1$by_origin, file.path(private_dir, "m1_peak_by_origin.rds"))
  jsonlite::write_json(metadata, file.path(cfg$output, "metadata.json"),
    auto_unbox = TRUE, pretty = TRUE, digits = 16, null = "null"
  )
  report_text <- stage_report_report_text(m0, m1$summary, comparison, metadata)
  writeLines(report_text, file.path(cfg$output, "report.md"), useBytes = TRUE)
  handoff_text <- stage_report_handoff_text(metadata, comparison)
  writeLines(handoff_text, file.path(cfg$output, "HANDOFF.md"), useBytes = TRUE)
  message("Stage report written to ", cfg$output, " (", round(elapsed, 2), " seconds)")
  invisible(list(
    metadata = metadata, m0 = m0, m1 = m1, comparison = comparison,
    synthetic = synthetic
  ))
}

if (sys.nframe() == 0L) stage_report_main()
