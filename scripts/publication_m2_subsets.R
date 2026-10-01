#!/usr/bin/env Rscript
# Frozen-artifact M2 optional-term subset experiment.
#
# This development-only runner reuses archived M0/M1 artifacts, never tunes or
# refits M0/M1, and writes an immutable, private-forecast run directory. It
# does not source publication_m2_simplified.R because that script executes
# models while being sourced.

options(stringsAsFactors = FALSE)

root <- normalizePath(getwd(), mustWork = TRUE)
if (!file.exists(file.path(root, "PAGe", "DESCRIPTION"))) {
  stop("Run this runner from the PAGe repository root.", call. = FALSE)
}
source(file.path(root, "PAGe", "R", "m2_subset_correction.R"), local = TRUE)
source(file.path(root, "PAGe", "R", "stage_contracts.R"), local = TRUE)
source(file.path(root, "PAGe", "R", "m0_training.R"), local = TRUE)
source(file.path(root, "PAGe", "R", "m0_runtime.R"), local = TRUE)

registry_path <- file.path(root, "results/audit/holdout_reconciliation_principal.csv")
input_path <- "/home/yeli/FLU/flu_testing_data.csv"
replay_root <- file.path(
  root,
  "manuscript/results/publication-repair-20260908/replay/20260908T125939/private"
)
archive_root <- "/home/yeli/PAGe-bcc-artifacts"
previous_root <- file.path(
  root,
  "manuscript/results/publication-repair-20260908/m2-simplified-20260908-native-02"
)
output_default <- file.path(
  root,
  "manuscript/results/publication-repair-20260908/m2-subsets-20260908-native-01"
)
output <- Sys.getenv("PAGE_M2_SUBSETS_OUTPUT", output_default)

sha256 <- function(path) digest::digest(file = path, algo = "sha256")
write_json <- function(x, path) {
  jsonlite::write_json(x, path,
    auto_unbox = TRUE, pretty = TRUE,
    digits = 16, null = "null"
  )
}
logit_stable_local <- function(p, eps = 1e-6) {
  stats::qlogis(pmin(1 - eps, pmax(eps, as.numeric(p))))
}
clip_probability <- function(p) pmin(1 - 1e-12, pmax(1e-12, as.numeric(p)))

read_authorized_data <- function(path) {
  raw <- utils::read.csv(path, stringsAsFactors = FALSE)
  needed <- c("season", "week", "seasonstart", "pos_flua", "test_flu")
  missing <- setdiff(needed, names(raw))
  if (length(missing)) stop("Authorized input is missing: ", paste(missing, collapse = ", "))
  n_weeks <- 52L + as.integer(
    MMWRweek::MMWRweek(as.Date(paste0(raw$seasonstart, "-12-31")))$MMWRweek == 53L
  )
  out <- data.frame(
    season = as.character(raw$season),
    weekF = ((as.integer(raw$week) - 27L) %% n_weeks) + 1L,
    y = as.numeric(raw$pos_flua), N = as.numeric(raw$test_flu),
    stringsAsFactors = FALSE
  )
  if (anyDuplicated(paste(out$season, out$weekF, sep = ":"))) {
    stop("Authorized input has duplicate season-week rows.")
  }
  if (any(!is.finite(out$y) | !is.finite(out$N) | out$N <= 0 |
    out$y < 0 | out$y > out$N)) {
    stop("Authorized input has invalid counts.")
  }
  out[order(out$season, out$weekF), , drop = FALSE]
}

declaration_from_replay <- function(replay, season) {
  m0 <- replay$stages$m0
  d <- as.data.frame(m0$df)
  required <- c("weekF", "ignite_ok_now")
  if (!all(required %in% names(d))) stop("M0 declaration fields missing for ", season)
  recomputed <- suppressWarnings(min(d$weekF[as.logical(d$ignite_ok_now)], na.rm = TRUE))
  if (!is.finite(recomputed)) recomputed <- NA_integer_
  saved <- as.integer(m0$ign_week_locked)
  if (!isTRUE(all.equal(saved, as.integer(recomputed)))) {
    stop("Saved and recomputed M0 declaration differ for ", season)
  }
  replay_decl <- as.integer(replay$ignition_week)
  if (!isTRUE(all.equal(saved, replay_decl))) {
    stop("Replay and M0 declaration differ for ", season)
  }
  if (!is.finite(saved)) stop("No safe M0 declaration for ", season)
  list(
    week = saved,
    source = paste0(
      "season-specific unseen replay stages$m0; first ignite_ok_now; ",
      "saved ign_week_locked verified against replay ignition_week"
    ),
    rows_evaluated = nrow(d),
    positive_rows = sum(as.logical(d$ignite_ok_now), na.rm = TRUE)
  )
}

read_bundles <- function(registry, seasons) {
  out <- vector("list", length(seasons))
  names(out) <- seasons
  for (s in seasons) {
    row <- registry[registry$season == s, , drop = FALSE]
    if (nrow(row) != 1L || row$status != "complete" || !isTRUE(row$exchangeable)) {
      stop("Registry row is not complete/exchangeable for ", s)
    }
    archive <- sub("/mnt/nfsv4/Users/yeli/PAGe-artifacts", archive_root,
      row$run_dir,
      fixed = TRUE
    )
    kit_path <- file.path(archive, "artifacts/candidate_pre_holdout.rds")
    replay_path <- file.path(replay_root, paste0(s, ".rds"))
    if (!file.exists(kit_path) || !file.exists(replay_path)) {
      stop("Missing frozen kit or replay for ", s)
    }
    kit <- readRDS(kit_path)
    replay <- readRDS(replay_path)
    if (!identical(replay$status, "unseen_replay_complete")) {
      stop("Replay is not complete for ", s)
    }
    training <- as.character(kit$m2_production$training_seasons)
    if (length(training) != 10L || s %in% training) {
      stop("Frozen training-season contract failed for ", s)
    }
    out[[s]] <- list(
      season = s, row = row, kit = kit, replay = replay,
      kit_path = kit_path, replay_path = replay_path,
      declaration = declaration_from_replay(replay, s),
      kit_sha256 = sha256(kit_path), replay_sha256 = sha256(replay_path)
    )
  }
  out
}

prefix_declaration <- function(obs, params, season, origins) {
  os <- obs[obs$season == season, c("season", "weekF", "y", "N"), drop = FALSE]
  if (!nrow(os)) stop("No training observations for prefix-only M0 inference: ", season)
  origins <- sort(unique(as.integer(origins)))
  if (!length(origins) || any(!is.finite(origins))) {
    stop("No finite M1 origins available for prefix-only M0 inference: ", season)
  }
  by_origin <- lapply(origins, function(origin) {
    m2_subset_prefix_declaration(os, params, origin_week = origin)
  })
  names(by_origin) <- as.character(origins)
  list(
    by_origin = by_origin,
    source = "corresponding outer kit frozen M0 applied to each training prefix"
  )
}

fallback_m1 <- function(x) {
  state <- if ("m1_state" %in% names(x)) as.character(x$m1_state) else ""
  !is.finite(x$m1_p_hat) | grepl("static|fallback", state, ignore.case = TRUE)
}

make_rows <- function(obs, m1_preds, seasons, declarations, alpha_state,
                      target_predictions = NULL) {
  rows <- list()
  losses <- list()
  for (s in seasons) {
    os <- obs[obs$season == s, c("season", "weekF", "y", "N"), drop = FALSE]
    if (!nrow(os)) stop("No observations for training/target season ", s)
    phase_declaration <- declarations[[s]]
    declaration_week <- if (is.null(phase_declaration$by_origin)) {
      phase_declaration$week
    } else {
      0
    }
    fs <- m2_subset_observed_features(os, declaration_week, alpha_state)
    mp <- as.data.frame(m1_preds[m1_preds$season == s, , drop = FALSE])
    if (!nrow(mp)) stop("No saved M1 rows for ", s)
    required <- c("eval_weekF", "target_weekF", "h", "m1_p_hat")
    if (length(setdiff(required, names(mp)))) stop("Saved M1 schema missing for ", s)
    key <- paste(mp$eval_weekF, mp$target_weekF, mp$h, sep = ":")
    if (anyDuplicated(key)) stop("Duplicate saved M1 keys for ", s)
    oi <- match(
      paste(s, mp$eval_weekF, sep = ":"),
      paste(fs$season, fs$weekF, sep = ":")
    )
    ti <- match(
      paste(s, mp$target_weekF, sep = ":"),
      paste(fs$season, fs$weekF, sep = ":")
    )
    m1_bad <- fallback_m1(mp)
    target_ok <- is.finite(ti) & mp$target_weekF == mp$eval_weekF + mp$h
    d_ok <- is.finite(oi) & is.finite(ti) & is.finite(fs$d[oi])
    origin_declarations <- phase_declaration$by_origin
    if (is.null(origin_declarations)) {
      u_origin <- fs$u[oi]
    } else {
      u_origin <- m2_subset_u_by_origin(mp$eval_weekF, origin_declarations)
    }
    keep <- is.finite(oi) & is.finite(ti) & is.finite(mp$m1_p_hat) &
      !m1_bad & target_ok & d_ok & is.finite(fs$z[oi]) & is.finite(u_origin) &
      u_origin >= 0
    losses[[s]] <- data.frame(
      season = s, m1_fallback_or_missing = sum(m1_bad),
      missing_origin = sum(!is.finite(oi)), missing_target = sum(!is.finite(ti)),
      nonadjacent_growth = sum(!d_ok & is.finite(oi) & is.finite(ti)),
      invalid_target_key = sum(!target_ok), missing_phase = sum(!is.finite(u_origin)),
      retained = sum(keep),
      stringsAsFactors = FALSE
    )
    if (!any(keep)) stop("No eligible rows for ", s)
    x <- data.frame(
      season = s, eval_weekF = as.integer(mp$eval_weekF[keep]),
      target_weekF = as.integer(mp$target_weekF[keep]), h = as.integer(mp$h[keep]),
      lead = factor(paste0("h", as.integer(mp$h[keep])), levels = c("h1", "h2")),
      m1_p = as.numeric(mp$m1_p_hat[keep]),
      m1_logit = logit_stable_local(mp$m1_p_hat[keep]),
      z = fs$z[oi[keep]], u = u_origin[keep], d = fs$d[oi[keep]],
      y_lead = fs$y[ti[keep]], N_lead = fs$N[ti[keep]],
      stringsAsFactors = FALSE
    )
    ignition_reference <- if (is.null(origin_declarations)) {
      as.numeric(phase_declaration$week)[1L]
    } else {
      declared <- vapply(origin_declarations, function(z) {
        as.numeric(z$week)[1L] %||% NA_real_
      }, numeric(1))
      declared <- declared[is.finite(declared)]
      if (length(declared)) min(declared) else NA_real_
    }
    observed_peak <- if (any(is.finite(os$y) & is.finite(os$N) & os$N > 0)) {
      valid_peak <- is.finite(os$y) & is.finite(os$N) & os$N > 0 & os$y >= 0 & os$y <= os$N
      os$weekF[valid_peak][which.max(os$y[valid_peak] / os$N[valid_peak])]
    } else {
      NA_real_
    }
    x$ignition_weekF <- ignition_reference
    x$observed_peak_weekF <- observed_peak
    scored <- page_phase_weights(
      x, page_scoring_weights(), season_col = "season",
      target_col = "target_weekF", ignition_col = "ignition_weekF",
      peak_col = "observed_peak_weekF", allow_censored = TRUE
    )
    x$phase <- scored$phase
    x$weight_page_v2 <- scored$weight
    x$weight_legacy <- m2_subset_phase_weights(
      x, early_weight = 2, early_max_t_since = 12,
      pre_ignition_weight = 0, late_weight = 1
    )
    if (!is.null(target_predictions)) {
      key_x <- paste(x$eval_weekF, x$h, sep = ":")
      key_t <- paste(target_predictions$eval_week, target_predictions$h, sep = ":")
      jj <- match(key_x, key_t)
      if (anyNA(jj)) stop("Target comparator keys do not match ", s)
      x$raw_m2 <- clip_probability(target_predictions$m2_raw[jj])
      x$complete_m2 <- clip_probability(target_predictions$m2_complete[jj])
    }
    rows[[s]] <- x
  }
  list(data = do.call(rbind, rows), losses = do.call(rbind, losses))
}

target_m1_predictions <- function(bundle) {
  m <- as.data.frame(bundle$replay$stages$m2_predictions)
  needed <- c("eval_week", "h", "target_weekF", "m1_p", "m2_eta_raw", "m2_p")
  if (length(setdiff(needed, names(m)))) stop("Replay M2 schema incomplete for ", bundle$season)
  data.frame(
    season = bundle$season, eval_week = as.integer(m$eval_week), h = as.integer(m$h),
    target_weekF = as.integer(m$target_weekF), m1_p = as.numeric(m$m1_p),
    m2_raw = stats::plogis(as.numeric(m$m2_eta_raw)),
    m2_complete = as.numeric(m$m2_p), m1_p_hat = as.numeric(m$m1_p),
    eval_weekF = as.integer(m$eval_week), m2_eta_raw = as.numeric(m$m2_eta_raw),
    stringsAsFactors = FALSE
  )
}

attach_previous <- function(x, season) {
  path <- file.path(previous_root, "private", paste0(season, ".rds"))
  x$previous_offset_intercept <- NA_real_
  x$previous_offset_smooth <- NA_real_
  x$previous_selected_m2 <- NA_real_
  if (!file.exists(path)) {
    return(list(data = x, matched = 0L))
  }
  old <- readRDS(path)$predictions
  j <- match(
    paste(x$eval_weekF, x$h, sep = ":"),
    paste(old$eval_week, old$h, sep = ":")
  )
  x$previous_offset_intercept <- old$offset_intercept[j]
  x$previous_offset_smooth <- old$offset_smooth[j]
  x$previous_selected_m2 <- old$selected_m2[j]
  list(data = x, matched = sum(is.finite(x$previous_selected_m2)))
}

primary_weighting <- Sys.getenv(
  "PAGE_M2_PRIMARY_WEIGHTING", "page_v2"
)
if (!primary_weighting %in% c("page_v2", "test_count_u0_12", "phase_equal_week")) {
  stop(
    "PAGE_M2_PRIMARY_WEIGHTING must be `page_v2`, `test_count_u0_12`, or `phase_equal_week`.",
    call. = FALSE
  )
}

score_vector <- function(data, p, horizon) {
  keep <- if (identical(primary_weighting, "page_v2")) {
    data$h == horizon & is.finite(p) & is.finite(data$weight_page_v2) & data$weight_page_v2 > 0
  } else if (identical(primary_weighting, "phase_equal_week")) {
    data$h == horizon & data$u >= 0 & is.finite(p)
  } else {
    data$h == horizon & data$u >= 0 & data$u <= 12 & is.finite(p)
  }
  x <- data[keep, , drop = FALSE]
  p <- clip_probability(p[keep])
  if (!nrow(x)) {
    return(data.frame(rows = 0L, trials = 0, nll = NA_real_, mae = NA_real_))
  }
  if (identical(primary_weighting, "page_v2")) {
    weights <- as.numeric(x$weight_page_v2)
    loss <- -(x$y_lead / x$N_lead) * log(p) -
      (1 - x$y_lead / x$N_lead) * log1p(-p)
    return(data.frame(
      rows = nrow(x), trials = sum(x$N_lead),
      nll = sum(weights * loss) / sum(weights),
      mae = sum(weights * abs(p - x$y_lead / x$N_lead)) / sum(weights)
    ))
  }
  if (identical(primary_weighting, "phase_equal_week")) {
    target_u <- as.numeric(x$u) + as.numeric(x$h)
    weights <- ifelse(target_u >= 0 & target_u <= 12, 2, 1)
    loss <- -(x$y_lead / x$N_lead) * log(p) -
      (1 - x$y_lead / x$N_lead) * log1p(-p)
    return(data.frame(
      rows = nrow(x), trials = sum(x$N_lead),
      nll = sum(weights * loss) / sum(weights),
      mae = sum(weights * abs(p - x$y_lead / x$N_lead)) / sum(weights)
    ))
  }
  trials <- sum(x$N_lead)
  data.frame(
    rows = nrow(x), trials = trials,
    nll = sum(-x$y_lead * log(p) - (x$N_lead - x$y_lead) * log1p(-p)) / trials,
    mae = sum(x$N_lead * abs(p - x$y_lead / x$N_lead)) / trials
  )
}

score_rows <- function(data, p, variant, season, h, population = "primary",
                       status = "ok", error = "") {
  sc <- score_vector(data, p, h)
  data.frame(
    scope = "season", season = season, horizon = h, variant = variant,
    population = population, status = status, error = error,
    rows = sc$rows, trials = sc$trials, nll = sc$nll, mae = sc$mae,
    stringsAsFactors = FALSE
  )
}

prefix_audit <- function(obs, declaration, alpha_state, origins) {
  full <- m2_subset_observed_features(obs, declaration, alpha_state)
  checks <- lapply(origins, function(w) {
    pref <- m2_subset_observed_features(
      obs[obs$weekF <= w, , drop = FALSE],
      declaration, alpha_state
    )
    a <- full[full$weekF == w, c("z", "u", "d"), drop = FALSE]
    b <- pref[pref$weekF == w, c("z", "u", "d"), drop = FALSE]
    if (nrow(a) != 1L || nrow(b) != 1L) {
      return(FALSE)
    }
    all(vapply(seq_along(a), function(i) {
      if (is.na(a[[i]][1L]) || is.na(b[[i]][1L])) {
        is.na(a[[i]][1L]) == is.na(b[[i]][1L])
      } else {
        abs(a[[i]][1L] - b[[i]][1L]) <= 1e-12
      }
    }, logical(1)))
  })
  data.frame(
    origins_checked = length(origins), prefix_safe = all(unlist(checks)),
    failed_origins = sum(!unlist(checks)), stringsAsFactors = FALSE
  )
}

compact_warning <- function(x) {
  if (!length(x)) {
    return("")
  }
  paste(unique(substr(x, 1L, 300L)), collapse = " | ")
}

run_experiment <- function() {
  if (!file.exists(registry_path) || !file.exists(input_path)) {
    stop("Missing registry or authorized input.")
  }
  registry <- utils::read.csv(registry_path, stringsAsFactors = FALSE)
  target_seasons <- as.character(registry$season[
    registry$status == "complete" & registry$exchangeable
  ])
  if (length(target_seasons) != 11L) stop("Expected 11 eligible exchangeable seasons.")
  exclusions <- c("2011-12", "2015-16", "2020-21", "2021-22")
  if (any(target_seasons %in% exclusions)) stop("Fixed exclusions entered eligible seasons.")
  if (dir.exists(output) && file.exists(file.path(output, "status.json"))) {
    old_status <- tryCatch(jsonlite::read_json(file.path(output, "status.json"),
      simplifyVector = TRUE
    ), error = function(e) NULL)
    if (!is.null(old_status) && identical(old_status$status, "complete_diagnostic_only")) {
      stop("Refusing to overwrite completed output: ", output)
    }
  }
  dir.create(file.path(output, "private"), recursive = TRUE, showWarnings = FALSE)
  writeLines("*", file.path(output, "private", ".gitignore"))
  started <- Sys.time()
  input_hash <- sha256(input_path)
  registry_hash <- sha256(registry_path)
  bundles <- read_bundles(registry, target_seasons)
  authorized <- read_authorized_data(input_path)
  parse_integer_grid <- function(name, default) {
    raw <- Sys.getenv(name, "")
    if (!nzchar(raw)) return(default)
    values <- suppressWarnings(as.integer(trimws(strsplit(raw, ",", fixed = TRUE)[[1L]])))
    if (!length(values) || anyNA(values)) stop("Invalid integer grid in ", name, ".")
    values
  }
  grid <- m2_subset_grid(
    k_z_values = parse_integer_grid("PAGE_M2_K_Z_VALUES", c(0L, 3L, 4L, 5L, 6L, 7L, 8L)),
    k_u_values = parse_integer_grid("PAGE_M2_K_U_VALUES", c(0L, 3L, 4L, 5L, 6L, 7L, 8L)),
    k_d_values = parse_integer_grid("PAGE_M2_K_D_VALUES", c(0L, 3L, 4L, 5L, 6L, 7L, 8L))
  )
  all_off_id <- grid$id[grid$enabled_count == 0L]
  if (length(all_off_id) != 1L) stop("Subset grid must contain exactly one all-off M1 baseline.")
  utils::write.csv(grid, file.path(output, "grid.csv"), row.names = FALSE)
  source_files <- c(
    "PAGe/R/m2_subset_correction.R", "scripts/publication_m2_subsets.R",
    "scripts/publication_m2_simplified.R", "scripts/publication_m2_offset_two_seasons.R",
    "scripts/publication_m2_subsets_watchdog.sh"
  )
  source_hashes <- setNames(lapply(file.path(root, source_files), sha256), source_files)
  protocol <- list(
    status = "running", purpose = "M2 development-only optional-term subset experiment",
    grid = grid, exact_grid_size = nrow(grid),
    offset = "saved M1 logit; no M1 coefficient",
    terms = c(
      "horizon intercept", "z EMA logit positivity",
      "u weeks since first M0 declaration", "d adjacent observed-week z difference"
    ),
    term_basis_values = sort(unique(c(grid$k_z, grid$k_u, grid$k_d))),
    smooth_basis = "ts", method = "REML", gamma = unique(grid$gamma),
    alpha_state = unique(grid$alpha_state),
    intercept_penalty = "mgcv paraPen ridge on included lead factor; REML-estimated sp",
    selection = "minimum equal-season inner Bernoulli NLL separately by horizon; ties fewer enabled terms then id",
    all_off = "exact M1 offset; no GAM fit",
    fit_weighting = "equal total trial weight per season",
    primary_weighting = primary_weighting,
    phase_weight_definition = if (identical(primary_weighting, "phase_equal_week")) {
      "target t_since=u+h in 0:12 has weight 2; later post-ignition targets have weight 1; equal-week within season; equal-season across validations"
    } else {
      "Bernoulli loss weighted by target test count within u in 0:12; equal-season across validations"
    },
    fit_window = if (identical(primary_weighting, "phase_equal_week")) {
      "all eligible origins u >= 0; primary scoring all post-ignition target weeks"
    } else {
      "all eligible origins u >= 0; primary scoring u in 0:12"
    },
    feature_definition = paste(
      "z EMA of clipped observed y/N initialized at first observed logit;",
      "d before any range clamp only when adjacent weekF;",
      "u=weekF-first saved M0 ignite_ok_now declaration"
    ),
    declaration_provenance = paste(
      "training phase uses corresponding outer kit frozen M0 applied to each",
      "training prefix through each M1 origin; target uses its own unseen replay",
      "declaration; no retrospective phase label used"
    ),
    exclusions = exclusions, target_seasons = target_seasons,
    input_sha256 = input_hash, registry_sha256 = registry_hash,
    previous_run = previous_root, source_sha256 = source_hashes,
    kit_sha256 = lapply(bundles, function(x) x$kit_sha256),
    replay_sha256 = lapply(bundles, function(x) x$replay_sha256),
    no_m0_refit = TRUE, no_m1_refit = TRUE, no_promotion = TRUE,
    outer_outcomes_used_for_primary_selection = FALSE,
    session = capture.output(utils::sessionInfo())
  )
  if (!file.exists(file.path(output, "protocol.json"))) {
    write_json(protocol, file.path(output, "protocol.json"))
  }
  write_status <- function(state, completed, last = NA_character_, error = NULL) {
    write_json(list(
      status = state, completed_outer_seasons = completed,
      total_outer_seasons = length(target_seasons), last_season = last,
      elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      error = error
    ), file.path(output, "status.json"))
  }
  write_status("running", 0L)

  all_inner <- list()
  all_selected <- list()
  all_outer <- list()
  all_timing <- list()
  all_losses <- list()
  completed <- 0L
  for (s in target_seasons) {
    checkpoint_path <- file.path(output, "private", paste0(s, ".rds"))
    if (file.exists(checkpoint_path)) {
      cp <- readRDS(checkpoint_path)
      all_inner[[s]] <- cp$inner_rows
      all_selected[[s]] <- cp$selection
      all_outer[[s]] <- cp$outer_rows
      all_timing[[s]] <- cp$timing
      all_losses[[s]] <- cp$losses
      completed <- completed + 1L
      write_status("running", completed, s)
      next
    }
    clock <- Sys.time()
    bundle <- bundles[[s]]
    kit <- bundle$kit
    alpha_state <- as.numeric(kit$m2_production$spec$alpha_state)
    train_seasons <- as.character(kit$m2_production$training_seasons)
    train_obs <- as.data.frame(kit$hist_data)
    train_obs <- train_obs[, c("season", "weekF", "y", "N"), drop = FALSE]
    m1_train <- as.data.frame(kit$m1_train_preds)
    train_origins <- lapply(train_seasons, function(ts) {
      sort(unique(m1_train$eval_weekF[m1_train$season == ts]))
    })
    declarations <- lapply(seq_along(train_seasons), function(i) {
      prefix_declaration(
        train_obs, kit$m0_params, train_seasons[i], train_origins[[i]]
      )
    })
    names(declarations) <- train_seasons
    declarations[[s]] <- bundle$declaration
    declaration_rows <- do.call(rbind, lapply(train_seasons, function(ts) {
      dts <- declarations[[ts]]$by_origin
      do.call(rbind, lapply(dts, function(x) {
        data.frame(
          outer_season = s, training_season = ts, origin_weekF = x$origin_week,
          declaration_weekF = x$week, rows_evaluated = x$rows_evaluated,
          positive_rows = x$positive_rows, source = x$source,
          stringsAsFactors = FALSE
        )
      }))
    }))
    train <- make_rows(train_obs, m1_train, train_seasons, declarations, alpha_state)
    if (any(train$data$season == s) ||
      !setequal(unique(train$data$season), train_seasons)) {
      stop("Outer target/training season isolation failed for ", s)
    }
    target_m1 <- target_m1_predictions(bundle)
    target_bundle <- make_rows(authorized, target_m1, s, declarations, alpha_state,
      target_predictions = target_m1
    )
    target <- attach_previous(target_bundle$data, s)$data
    target_loss <- target_bundle$losses
    audit_origins <- sort(unique(target$eval_weekF[target$u >= 0 & target$u <= 12]))
    audit <- prefix_audit(
      authorized[authorized$season == s, c("season", "weekF", "y", "N")],
      bundle$declaration$week, alpha_state, audit_origins
    )
    if (!isTRUE(audit$prefix_safe)) stop("Prefix feature audit failed for ", s)

    inner_rows <- list()
    inner_fit_seconds <- setNames(numeric(nrow(grid)), grid$id)
    inner_failed <- setNames(integer(nrow(grid)), grid$id)
    validations <- sort(unique(train$data$season))
    for (v in validations) {
      tr <- train$data[train$data$season != v, , drop = FALSE]
      va <- train$data[train$data$season == v & train$data$u <= 12, , drop = FALSE]
      if (!nrow(va) || any(tr$season == v) || any(tr$season == s)) {
        stop("Inner isolation failed for ", s, "/", v)
      }
      for (i in seq_len(nrow(grid))) {
        spec <- grid[i, , drop = FALSE]
        fit_started <- Sys.time()
        fit <- NULL
        err <- ""
        status <- "ok"
        fit <- tryCatch(m2_subset_fit(tr, spec), error = function(e) {
          err <<- conditionMessage(e)
          NULL
        })
        inner_fit_seconds[spec$id] <- inner_fit_seconds[spec$id] +
          as.numeric(difftime(Sys.time(), fit_started, units = "secs"))
        if (is.null(fit)) {
          status <- "failed"
          inner_failed[spec$id] <- inner_failed[spec$id] + 1L
        }
        for (h in 1:2) {
          if (status == "failed") {
            inner_rows[[length(inner_rows) + 1L]] <- data.frame(
              scope = "inner", outer_season = s, validation_season = v,
              horizon = h, config_id = spec$id, enabled_count = spec$enabled_count,
              status = status, error = err, rows = 0L, trials = 0,
              nll = NA_real_, mae = NA_real_, stringsAsFactors = FALSE
            )
          } else {
            pr <- tryCatch(m2_subset_predict(fit, va), error = function(e) {
              err <<- conditionMessage(e)
              NULL
            })
            if (is.null(pr)) {
              status <- "failed"
              inner_failed[spec$id] <- inner_failed[spec$id] + 1L
              inner_rows[[length(inner_rows) + 1L]] <- data.frame(
                scope = "inner", outer_season = s, validation_season = v,
                horizon = h, config_id = spec$id, enabled_count = spec$enabled_count,
                status = status, error = err, rows = 0L, trials = 0,
                nll = NA_real_, mae = NA_real_, stringsAsFactors = FALSE
              )
            } else {
              sc <- score_vector(va, pr$p_hat, h)
              inner_rows[[length(inner_rows) + 1L]] <- data.frame(
                scope = "inner", outer_season = s, validation_season = v,
                horizon = h, config_id = spec$id, enabled_count = spec$enabled_count,
                status = "ok", error = "", rows = sc$rows, trials = sc$trials,
                nll = sc$nll, mae = sc$mae, stringsAsFactors = FALSE
              )
            }
          }
        }
      }
    }
    inner_df <- do.call(rbind, inner_rows)
    selected <- list()
    for (h in 1:2) {
      z <- inner_df[inner_df$horizon == h & inner_df$status == "ok", , drop = FALSE]
      counts <- table(z$config_id)
      complete_ids <- names(counts)[counts == length(validations)]
      means <- aggregate(
        nll ~ config_id + enabled_count,
        z[z$config_id %in% complete_ids, , drop = FALSE], mean
      )
      if (!nrow(means)) stop("No complete inner configurations for ", s, " h", h)
      means <- means[order(means$nll, means$enabled_count, means$config_id), , drop = FALSE]
      best <- means[1L, , drop = FALSE]
      selected[[h]] <- data.frame(
        outer_season = s, horizon = h, selected_id = as.character(best$config_id),
        selected_enabled_count = best$enabled_count, inner_equal_season_nll = best$nll,
        complete_config_count = length(complete_ids),
        failed_config_count = nrow(grid) - length(complete_ids),
        selection_rule = "inner equal-season NLL; fewer enabled terms; id",
        stringsAsFactors = FALSE
      )
    }
    selection <- do.call(rbind, selected)
    final_fits <- vector("list", nrow(grid))
    names(final_fits) <- grid$id
    final_preds <- vector("list", nrow(grid))
    names(final_preds) <- grid$id
    timing_rows <- list()
    for (i in seq_len(nrow(grid))) {
      spec <- grid[i, , drop = FALSE]
      fit_started <- Sys.time()
      err <- ""
      fit <- tryCatch(m2_subset_fit(train$data, spec), error = function(e) {
        err <<- conditionMessage(e)
        NULL
      })
      elapsed <- as.numeric(difftime(Sys.time(), fit_started, units = "secs"))
      final_fits[[spec$id]] <- fit
      if (is.null(fit)) {
        final_preds[[spec$id]] <- rep(NA_real_, nrow(target))
      } else {
        final_preds[[spec$id]] <- tryCatch(m2_subset_predict(fit, target)$p_hat,
          error = function(e) {
            err <<- conditionMessage(e)
            rep(NA_real_, nrow(target))
          }
        )
      }
      timing_rows[[i]] <- data.frame(
        outer_season = s, config_id = spec$id, enabled_count = spec$enabled_count,
        inner_fit_count = length(validations), inner_failed_count = inner_failed[spec$id],
        inner_elapsed_seconds = inner_fit_seconds[spec$id],
        outer_elapsed_seconds = elapsed,
        outer_status = if (is.null(fit) || any(!is.finite(final_preds[[spec$id]]))) "failed" else "ok",
        converged = if (is.null(fit)) FALSE else isTRUE(fit$converged),
        total_edf = if (is.null(fit)) NA_real_ else fit$total_edf,
        edf = if (is.null(fit)) {
          ""
        } else {
          paste(names(fit$edf), signif(fit$edf, 8),
            sep = "=", collapse = ";"
          )
        },
        warnings = if (is.null(fit)) err else compact_warning(fit$warnings),
        stringsAsFactors = FALSE
      )
    }
    pred <- target
    for (id in names(final_preds)) pred[[paste0("cfg_", id)]] <- final_preds[[id]]
    pred$selected_grid <- vapply(seq_len(nrow(pred)), function(j) {
      id <- selection$selected_id[match(pred$h[j], selection$horizon)]
      pred[[paste0("cfg_", id)]][j]
    }, numeric(1))
    best_ids <- setNames(character(2), c("1", "2"))
    for (h in 1:2) {
      vals <- vapply(grid$id, function(id) {
        score_vector(pred, pred[[paste0("cfg_", id)]], h)$nll
      }, numeric(1))
      ok <- is.finite(vals)
      if (!any(ok)) stop("No finite outer subset for ", s, " h", h)
      cc <- grid[match(grid$id[ok], grid$id), , drop = FALSE]
      best_ids[as.character(h)] <- cc$id[order(vals[ok], cc$enabled_count, cc$id)][1L]
    }
    pred$best_observed_subset <- vapply(seq_len(nrow(pred)), function(j) {
      pred[[paste0("cfg_", best_ids[as.character(pred$h[j])])]][j]
    }, numeric(1))
    pred$previous_offset_intercept <- clip_probability(pred$previous_offset_intercept)
    pred$previous_offset_smooth <- clip_probability(pred$previous_offset_smooth)
    pred$previous_selected_m2 <- clip_probability(pred$previous_selected_m2)
    if (max(abs(pred[[paste0("cfg_", all_off_id)]] - pred$m1_p)) > 0) {
      stop("All-off is not exact M1 for ", s)
    }
    variants <- c(
      paste0("cfg_", grid$id), "selected_grid", "best_observed_subset",
      "m1_p", "raw_m2", "complete_m2", "previous_offset_intercept",
      "previous_offset_smooth", "previous_selected_m2"
    )
    outer_rows <- list()
    oi <- 0L
    for (v in variants) {
      for (h in 1:2) {
        population <- if (grepl("^previous_", v)) "matched_previous" else "primary"
        ss <- score_rows(pred, pred[[v]], v, s, h,
          population = population,
          status = if (all(!is.finite(pred[[v]][pred$h == h & pred$u <= 12]))) "failed" else "ok"
        )
        oi <- oi + 1L
        outer_rows[[oi]] <- ss
      }
    }
    outer_df <- do.call(rbind, outer_rows)
    m1_sc <- outer_df[outer_df$variant == "m1_p" & outer_df$population == "primary",
      c("horizon", "nll"),
      drop = FALSE
    ]
    outer_df$nll_delta_m1 <- outer_df$nll -
      m1_sc$nll[match(outer_df$horizon, m1_sc$horizon)]
    outer_df$best_observed_id <- best_ids[as.character(outer_df$horizon)]
    losses <- rbind(train$losses, target_loss)
    timing <- do.call(rbind, timing_rows)
    checkpoint <- list(
      target_season = s, training_seasons = train_seasons,
      predictions = pred, fits = final_fits, selection = selection,
      best_observed_id = best_ids, inner_rows = inner_df, outer_rows = outer_df,
      timing = timing, losses = losses, prefix_audit = audit,
      declaration = bundle$declaration, alpha_state = alpha_state,
      m1_fallback_rows_training = sum(train$losses$m1_fallback_or_missing),
      target_rows_primary = sum(pred$u >= 0 & pred$u <= 12),
      previous_match_rows = sum(is.finite(pred$previous_selected_m2)),
      source_sha256 = source_hashes, input_sha256 = input_hash,
      training_declarations = declaration_rows
    )
    saveRDS(checkpoint, checkpoint_path)
    all_inner[[s]] <- inner_df
    all_selected[[s]] <- selection
    all_outer[[s]] <- outer_df
    all_timing[[s]] <- timing
    all_losses[[s]] <- losses
    completed <- completed + 1L
    write_status("running", completed, s)
    message(s, ": complete")
  }
  inner_df <- do.call(rbind, all_inner)
  selected_df <- do.call(rbind, all_selected)
  outer_df <- do.call(rbind, all_outer)
  timing_df <- do.call(rbind, all_timing)
  losses_df <- do.call(rbind, all_losses)
  declarations_df <- do.call(rbind, lapply(target_seasons, function(s) {
    cp <- readRDS(file.path(output, "private", paste0(s, ".rds")))
    cp$training_declarations
  }))
  utils::write.csv(inner_df, file.path(output, "inner.csv"), row.names = FALSE)
  utils::write.csv(selected_df, file.path(output, "selected.csv"), row.names = FALSE)
  utils::write.csv(outer_df, file.path(output, "outer.csv"), row.names = FALSE)
  utils::write.csv(timing_df, file.path(output, "timing.csv"), row.names = FALSE)
  utils::write.csv(losses_df, file.path(output, "lost_rows.csv"), row.names = FALSE)
  utils::write.csv(
    declarations_df, file.path(output, "training_declarations.csv"),
    row.names = FALSE
  )
  aggregate_df <- aggregate(
    cbind(nll, mae) ~ horizon + variant + population, outer_df,
    function(x) mean(x, na.rm = TRUE)
  )
  names(aggregate_df)[names(aggregate_df) == "nll"] <- "equal_season_nll"
  names(aggregate_df)[names(aggregate_df) == "mae"] <- "equal_season_mae"
  counts <- aggregate(
    cbind(rows, trials) ~ horizon + variant + population, outer_df,
    function(x) sum(x, na.rm = TRUE)
  )
  names(counts)[names(counts) == "rows"] <- "total_rows"
  names(counts)[names(counts) == "trials"] <- "total_trials"
  aggregate_df <- merge(aggregate_df, counts,
    by = c("horizon", "variant", "population"), all = TRUE
  )
  m1agg <- aggregate_df[aggregate_df$variant == "m1_p" & aggregate_df$population == "primary",
    c("horizon", "equal_season_nll"),
    drop = FALSE
  ]
  aggregate_df$nll_delta_m1 <- aggregate_df$equal_season_nll -
    m1agg$equal_season_nll[match(aggregate_df$horizon, m1agg$horizon)]
  aggregate_df <- aggregate_df[order(
    aggregate_df$horizon, aggregate_df$equal_season_nll,
    aggregate_df$variant
  ), , drop = FALSE]
  utils::write.csv(aggregate_df, file.path(output, "aggregate.csv"), row.names = FALSE)
  selected_grid <- merge(
    selected_df,
    grid[, c("id", "k_z", "k_u", "k_d"), drop = FALSE],
    by.x = "selected_id", by.y = "id", all.x = TRUE, sort = FALSE
  )
  boundary_rows <- do.call(rbind, lapply(c("k_z", "k_u", "k_d"), function(nm) {
    positive <- grid[[nm]][grid[[nm]] > 0]
    data.frame(
      parameter = nm,
      minimum_positive = min(positive), maximum_tested = max(positive),
      selected_at_minimum = selected_grid[[nm]] == min(positive),
      selected_at_maximum = selected_grid[[nm]] == max(positive),
      selected_value = selected_grid[[nm]],
      outer_season = selected_grid$outer_season,
      horizon = selected_grid$horizon,
      selected_id = selected_grid$selected_id,
      stringsAsFactors = FALSE
    )
  }))
  boundary_rows$positive_boundary <-
    (boundary_rows$selected_at_minimum | boundary_rows$selected_at_maximum) &
    boundary_rows$selected_value > 0
  utils::write.csv(boundary_rows, file.path(output, "boundary_audit.csv"), row.names = FALSE)
  boundary_status <- if (any(boundary_rows$positive_boundary)) "review_required" else "clear"
  status <- list(
    status = "complete_diagnostic_only", boundary_status = boundary_status,
    completed_outer_seasons = completed,
    total_outer_seasons = length(target_seasons),
    elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    input_sha256 = input_hash, registry_sha256 = registry_hash,
    source_sha256 = source_hashes, aggregate_path = file.path(output, "aggregate.csv"),
    session = capture.output(utils::sessionInfo())
  )
  write_json(status, file.path(output, "status.json"))
  report <- c(
    "# M2 optional-term subset development experiment", "",
    "This is a conditional development artifact using frozen M0/M1 artifacts. It is not a promotion or confirmation result.", "",
    paste0("Run directory: ", output),
    paste0(
      "Outer seasons: ", length(target_seasons), "; configurations: ", nrow(grid), "; elapsed seconds: ",
      signif(status$elapsed_seconds, 6)
    ), "",
    "## Locked specification", "",
    "The saved M1 logit is the mandatory binomial offset and the all-zero candidate is exact M1. The grid searches a ridge-penalized horizon intercept plus per-term k_z, k_u, and k_d values; zero omits a term and positive values create horizon-specific shrinkage smooths for z (EMA logit positivity), u (weeks since the first M0 declaration), and d (adjacent-week z growth). The tested basis values are ", paste(sort(unique(c(grid$k_z, grid$k_u, grid$k_d))), collapse = ", "), "; REML estimates smoothing penalties and EDF. Training seasons receive equal total trial weight.", "",
    paste0("Boundary audit status: ", boundary_status, ". See boundary_audit.csv; a selected positive edge requires an expanded pre-holdout run."), "",
    "Selection is minimum equal-season inner NLL separately by horizon, with ties resolved by fewer enabled components and deterministic configuration ID. The all-off candidate is exactly M1 and is not fitted.", "",
    "## Results", "",
    "See aggregate.csv, selected.csv, outer.csv, timing.csv, lost_rows.csv, and training_declarations.csv. best_observed_subset is exploratory only and was not used for primary selection.", "",
    "## Provenance and limitations", "",
    "For every outer season, training phase was recomputed at each saved M1 origin by applying that outer kit's frozen M0 parameters to the corresponding training prefix through that origin. The outer target used its own completed unseen replay declaration only. No retrospective phase labels, M0/M1 refits, or outer outcomes entered configuration selection; historical outer seasons and upstream M0/M1 choices remain conditional development context.", "",
    "Previous native-02 offset columns were joined on matched season-origin-horizon keys and are reported with population=matched_previous. Training declaration lineage is in training_declarations.csv; static-template/fallback M1 rows, unavailable phase rows, and nonadjacent growth rows are reported in lost_rows.csv; no candidate failures are silently omitted."
  )
  writeLines(report, file.path(output, "REPORT.md"))
  print(aggregate_df, row.names = FALSE)
  invisible(status)
}

if (sys.nframe() == 0L) run_experiment()
