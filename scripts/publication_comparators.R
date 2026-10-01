#!/usr/bin/env Rscript
# Run from the repository root. Independent of package exports under repair.
# Existing result directories are never reused; --output must stay in scope.
source("scripts/publication_comparator_helpers.R")

pc_run <- function(output, input = "/home/yeli/FLU/flu_testing_data.csv") {
  started <- Sys.time()
  set.seed(20260908L)
  options(warn = 1)
  root <- normalizePath("manuscript/results/publication-repair-20260908/comparators",
    mustWork = TRUE)
  output <- normalizePath(output, mustWork = TRUE)
  if (!startsWith(paste0(output, "/"), paste0(root, "/"))) {
    stop("Output outside authorized comparator directory")
  }
  if (file.exists(file.path(output, "manifest.json"))) stop("Output already used")
  write_json <- function(x, name) {
    jsonlite::write_json(x, file.path(output, name), auto_unbox = TRUE,
      pretty = TRUE, null = "null", digits = 16)
  }
  warnings <- character()
  write_json(list(status = "running", started_utc = format(started, tz = "UTC")),
    "status.json")
  tryCatch(withCallingHandlers({
    input_hash <- digest::digest(file = input, algo = "sha256")
    d <- pc_read_data(input)
    principal_path <- "results/audit/holdout_reconciliation_principal.csv"
    principal <- utils::read.csv(principal_path, stringsAsFactors = FALSE)
    if (nrow(principal) != 11L || !setequal(principal$season, pc_seasons)) {
      stop("Principal archive universe mismatch")
    }
    principal <- principal[match(pc_seasons, principal$season), ]
    rows <- provenance <- vector("list", 11L)
    for (j in seq_along(pc_seasons)) {
      s <- pc_seasons[j]
      run_dir <- sub("/mnt/nfsv4/Users/yeli/PAGe-artifacts",
        "/home/yeli/PAGe-bcc-artifacts", principal$run_dir[j], fixed = TRUE)
      artifact <- file.path(run_dir, "artifacts")
      prediction_path <- file.path(artifact,
        paste0("holdout_", gsub("-", "_", s), "_predictions.csv"))
      manifest_path <- file.path(artifact, "run_manifest.rds")
      selection_path <- file.path(artifact, "season_selection.rds")
      m <- readRDS(manifest_path)
      sel <- readRDS(selection_path)
      train <- setdiff(pc_seasons, s)
      if (!identical(m$input_sha256, input_hash) ||
        principal$input_sha256[j] != input_hash ||
        !setequal(m$training_seasons, train) ||
        !setequal(sel$training_seasons, train) ||
        !setequal(m$exclude_seasons, pc_exclusions) ||
        !setequal(sel$exclude_seasons, pc_exclusions) ||
        !identical(as.character(sel$holdout_seasons), s) ||
        !identical(as.character(m$holdout_seasons), s)) {
        stop("Archive provenance mismatch: ", s)
      }
      a <- utils::read.csv(prediction_path, stringsAsFactors = FALSE)
      a$archive_row <- seq_len(nrow(a))
      a <- a[a$lead == 2L & a$t_since >= 0 & a$t_since <= 12, ]
      a <- a[order(a$weekF), ]
      expected <- if (s == "2025-26") 8L else 13L
      if (nrow(a) != expected || any(a$season != s) ||
        anyDuplicated(a$weekF) ||
        !identical(as.integer(a$t_since), seq_len(expected) - 1L) ||
        any(a$weekF - a$t_since != principal$ignition_week[j])) {
        stop("Archive row-window mismatch: ", s)
      }
      a$origin <- a$weekF
      t <- pc_targets(d, a)
      if (anyNA(t$y) || any(a$y_lead != t$y | a$N_lead != t$N) ||
        any(abs(a$p_obs - t$y / t$N) > 1e-12)) {
        stop("Archive target mismatch: ", s)
      }
      pc_nll(a$y_lead, a$N_lead, a$p_hat)
      a$run_id <- principal$run_id[j]
      a$archive_commit <- principal$commit[j]
      a$input_sha256 <- input_hash
      rows[[j]] <- a
      provenance[[j]] <- list(season = s, run_dir = run_dir,
        predictions_sha256 = digest::digest(file = prediction_path, algo = "sha256"),
        manifest_sha256 = digest::digest(file = manifest_path, algo = "sha256"),
        selection_sha256 = digest::digest(file = selection_path, algo = "sha256"),
        training_seasons = train,
        archived_manifest_contains_target_label = s %in% names(m$manual_labels),
        rows = nrow(a))
    }
    windows <- do.call(rbind, rows)
    utils::write.csv(windows, file.path(output, "archive_rows.csv"), row.names = FALSE)
    write_json(list(status = "preflight_pass", paired_rows = nrow(windows)), "status.json")
    grids <- list(calendar = pc_grid("calendar"), analogue = pc_grid("analogue"))
    write_json(list(seed = 20260908L, grids = grids,
      training = "all available h1/h2 origin-lag-target rows in permitted training seasons",
      inner_scoring = "h2 archived ignition offsets 0:12, observed targets only",
      cyclic_knots = c(0.5, 53.5), logit_clip = 1e-12,
      calendar_formula = paste("cbind(y,N-y) ~ horizon +",
        "s(target_week,bs='cc',k=k_week,by=horizon) +",
        "s(z,bs='tp',k=k_signal,by=horizon) +",
        "s(dz,bs='tp',k=k_signal,by=horizon)"),
      calendar_method = "REML", analogue_distance = "mean squared logit difference",
      analogue_complexity = "more neighbours first, then shorter window",
      boundary_policy = "frozen protocol grid; flag boundary winners, no expansion in diagnostic"),
      "configuration.json")
    frozen <- timings <- predictions <- inner <- vector("list", 11L)
    for (j in seq_along(pc_seasons)) {
      s <- pc_seasons[j]
      clock <- proc.time()[["elapsed"]]
      train_seasons <- setdiff(pc_seasons, s)
      train <- pc_training(d, train_seasons, s)
      tuned <- lapply(names(grids), function(model) {
        pc_tune(d, train_seasons, s, windows, model, grids[[model]])
      })
      names(tuned) <- names(grids)
      configs <- lapply(tuned, function(t) t$grid[t$selection$index, ])
      fit <- pc_fit_calendar(train, configs$calendar)
      train_seconds <- proc.time()[["elapsed"]] - clock
      clock <- proc.time()[["elapsed"]]
      q <- windows[windows$season == s, ]
      # Predict using origin-time features only; no coefficients update here.
      p <- list(persistence = pc_persistence(d, q),
        seasonal_naive = pc_naive(train, q),
        calendar_gam = pc_predict_calendar(fit, d, q),
        analogue = pc_analogue(train, d, q, configs$analogue$k, configs$analogue$window),
        PAGe_archived_pre_repair = q$p_hat)
      predictions[[j]] <- do.call(rbind, lapply(names(p), function(model) {
        x <- q
        x$model <- model
        x$prediction <- p[[model]]
        x
      }))
      prediction_seconds <- proc.time()[["elapsed"]] - clock
      frozen[[j]] <- list(season = s, training_seasons = train_seasons,
        configs = configs, selection = lapply(tuned, `[[`, "selection"),
        calendar_coefficient_sha256 = digest::digest(stats::coef(fit), algo = "sha256"),
        selected_at_grid_edge = lapply(names(grids), function(model) {
          axes <- setdiff(names(grids[[model]]), c("id", "complexity"))
          setNames(lapply(axes, function(axis) {
            configs[[model]][[axis]] %in% range(grids[[model]][[axis]])
          }), axes)
        }))
      names(frozen[[j]]$selected_at_grid_edge) <- names(grids)
      inner[[j]] <- tuned
      timings[[j]] <- data.frame(season = s, training_seconds = train_seconds,
        prediction_batch_seconds = prediction_seconds,
        seconds_per_origin_all_models = prediction_seconds / nrow(q))
      saveRDS(list(fit = fit, frozen = frozen[[j]], inner = tuned),
        file.path(output, paste0("frozen_", s, ".rds")))
      write_json(list(status = "running", completed_folds = j, last_season = s),
        "status.json")
      message(s, ": trained and frozen; ", nrow(q), " paired h2 rows; ",
        round(train_seconds, 2), " training seconds")
    }
    p <- do.call(rbind, predictions)
    groups <- split(p, interaction(p$season, p$model, drop = TRUE))
    per_season <- do.call(rbind, lapply(groups, function(x) {
      data.frame(season = x$season[1], model = x$model[1], rows = nrow(x),
        trials = sum(x$N_lead), nll = pc_nll(x$y_lead, x$N_lead, x$prediction),
        weighted_mae = stats::weighted.mean(abs(x$y_lead / x$N_lead - x$prediction),
          x$N_lead))
    }))
    aggregate <- do.call(rbind, lapply(split(per_season, per_season$model), function(x) {
      data.frame(model = x$model[1], seasons = nrow(x), rows = sum(x$rows),
        equal_season_nll = mean(x$nll), pooled_trial_nll = weighted.mean(x$nll, x$trials),
        equal_season_weighted_mae = mean(x$weighted_mae))
    }))
    archived <- per_season[per_season$model == "PAGe_archived_pre_repair", ]
    differences <- per_season[per_season$model != "PAGe_archived_pre_repair", ]
    differences$delta_archived_minus_comparator <-
      archived$nll[match(differences$season, archived$season)] - differences$nll
    descriptive <- lapply(split(differences, differences$model), function(x) {
      z <- x$delta_archived_minus_comparator
      list(mean = mean(z), median = stats::median(z), sd = stats::sd(z),
        iqr = stats::IQR(z), min = min(z), max = max(z),
        leave_one_season_out_mean = setNames((sum(z) - z) / (length(z) - 1), x$season))
    })
    utils::write.csv(p, file.path(output, "paired_predictions.csv"), row.names = FALSE)
    utils::write.csv(per_season, file.path(output, "season_scores.csv"), row.names = FALSE)
    write_json(list(aggregate = aggregate, season_scores = per_season,
      differences = differences, descriptive_differences = descriptive), "summary.json")
    write_json(frozen, "frozen_configurations.json")
    write_json(do.call(rbind, timings), "runtimes.json")
    write_json(lapply(inner, function(t) lapply(t, function(m) {
      list(grid = m$grid, scores = as.data.frame(m$scores), selection = m$selection)
    })), "inner_scores.json")
    elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    write_json(list(status = "complete_diagnostic_only", input = input,
      input_sha256 = input_hash, principal_sha256 = digest::digest(file = principal_path,
        algo = "sha256"), protocol_sha256 = digest::digest(
        file = "manuscript/ANALYSIS_PROTOCOL.md", algo = "sha256"),
      scripts_sha256 = lapply(c("scripts/publication_comparators.R",
        "scripts/publication_comparator_helpers.R"), function(f) {
        list(path = f, sha256 = digest::digest(file = f, algo = "sha256"))
      }), source_rows = as.list(table(d$season)), principal_seasons = pc_seasons,
      exclusions = pc_exclusions, archives = provenance, frozen = frozen,
      warnings = unique(warnings), provenance_failures = character(),
      elapsed_seconds = elapsed, R = R.version.string,
      mgcv = as.character(utils::packageVersion("mgcv")),
      session = capture.output(utils::sessionInfo()),
      limitations = c("Final-data retrospective replay; no vintage reconstruction/backfill analysis.",
        "PAGe points are archived pre-repair outputs, not newly trained or repaired predictions.",
        "Inner evaluation conditions on archived ignition windows, not freshly nested M0 windows; archival M0 provenance may involve the outer target.",
        "Archive manifests include global manual-label metadata; absence from actual historical fit is not established by this sidecar.",
        "Basis-grid edge flags are unresolved diagnostic findings; no boundary expansion or publication-ready freeze is claimed.",
        "Formula, 53-week cyclic support and analogue complexity ordering are explicit sidecar interpretations of underspecified protocol details.",
        "Only four requested comparators implemented; elastic net, boosted tree and repaired full PAGe are outside scope.")),
      "manifest.json")
    write_json(list(status = "complete_diagnostic_only", elapsed_seconds = elapsed,
      paired_rows = nrow(windows), models = length(unique(p$model))), "status.json")
    print(aggregate, row.names = FALSE)
    invisible(aggregate)
  }, warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }), error = function(e) {
    write_json(list(status = "failed", error = conditionMessage(e),
      warnings = unique(warnings), elapsed_seconds = as.numeric(
        difftime(Sys.time(), started, units = "secs"))), "failure.json")
    write_json(list(status = "failed", error = conditionMessage(e)), "status.json")
    stop(e)
  })
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  output <- "manuscript/results/publication-repair-20260908/comparators"
  if (length(args)) {
    if (length(args) != 1L || !startsWith(args, "--output=")) {
      stop("Usage: Rscript scripts/publication_comparators.R [--output=directory]")
    }
    output <- sub("^--output=", "", args)
  }
  pc_run(output)
}
