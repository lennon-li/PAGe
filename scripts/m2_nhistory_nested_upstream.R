nh_split_set <- function(x) {
  if (!length(x) || is.na(x) || !nzchar(x)) character() else strsplit(x, "\\|", fixed = FALSE)[[1L]]
}

nh_assert_fold_contract <- function(fold_row, protocol = nh_protocol()) {
  seasons <- protocol$principal_seasons
  outer <- as.character(fold_row$outer_season)
  validation <- as.character(fold_row$validation_season)
  evaluated <- as.character(fold_row$evaluated_row_season)
  role <- as.character(fold_row$fold_role)
  excluded <- nh_split_set(as.character(fold_row$upstream_excluded_seasons))
  expected <- switch(role,
    outer = outer,
    inner_validation = c(outer, validation),
    inner_training_row = c(outer, validation, evaluated),
    outer_training_row = c(outer, evaluated),
    stop("Unknown fold role: ", role, call. = FALSE)
  )
  expected <- sort(unique(expected[!is.na(expected) & nzchar(expected)]))
  if (!identical(sort(excluded), expected)) {
    stop("Fold exclusion mismatch for role ", role, ": expected ",
         paste(expected, collapse = "|"), " but saw ", paste(sort(excluded), collapse = "|"), call. = FALSE)
  }
  allowed <- setdiff(seasons, expected)
  declared <- nh_split_set(as.character(fold_row$upstream_training_seasons))
  if (!identical(sort(declared), sort(allowed))) {
    stop("Fold upstream training set does not equal all seasons minus exclusions.", call. = FALSE)
  }
  invisible(TRUE)
}

nh_assert_all_fold_contracts <- function(fold_index, protocol = nh_protocol()) {
  for (i in seq_len(nrow(fold_index))) nh_assert_fold_contract(fold_index[i, , drop = FALSE], protocol)
  invisible(TRUE)
}

nh_assert_label_subset <- function(labels, allowed_seasons, evaluated_seasons = character()) {
  if (is.null(labels)) return(invisible(TRUE))
  if (!is.data.frame(labels) || !"season" %in% names(labels)) stop("Labels must have a season column.", call. = FALSE)
  lbl <- unique(as.character(labels$season))
  bad <- setdiff(lbl, allowed_seasons)
  if (length(bad)) stop("Poisoned labels include forbidden season(s): ", paste(bad, collapse = ", "), call. = FALSE)
  poisoned_eval <- intersect(lbl, evaluated_seasons)
  if (length(poisoned_eval)) stop("Labels include evaluated row season(s): ", paste(poisoned_eval, collapse = ", "), call. = FALSE)
  invisible(TRUE)
}

nh_upstream_key <- function(excluded_seasons, data_hash, label_hash, recipe_hash,
                            protocol_hash, controls_hash, source_hash) {
  digest::digest(list(
    excluded_seasons = sort(unique(as.character(excluded_seasons))), data_hash = data_hash,
    label_hash = label_hash, recipe_hash = recipe_hash, protocol_hash = protocol_hash,
    controls_hash = controls_hash, source_hash = source_hash
  ), algo = "sha256")
}

nh_upstream_cache_valid <- function(x, key) {
  if (!is.list(x) || !identical(x$upstream_key, key) || !is.character(x$cache_sha256) ||
      length(x$cache_sha256) != 1L) return(FALSE)
  probe <- x; probe$cache_sha256 <- NULL
  identical(x$cache_sha256, nh_hash_object(probe))
}

nh_load_page_source <- function(root = nh_repo_root()) {
  package_dir <- file.path(root, "PAGe")
  if (!file.exists(file.path(package_dir, "DESCRIPTION"))) stop("Invalid PAGe source root.", call. = FALSE)
  marker <- paste0(".page_nhistory_loaded_", digest::digest(normalizePath(package_dir), algo = "xxhash64"))
  if (exists(marker, envir = .GlobalEnv, inherits = FALSE)) return(invisible(TRUE))
  files <- sort(list.files(file.path(package_dir, "R"), pattern = "[.]R$", full.names = TRUE))
  for (f in files) sys.source(f, envir = .GlobalEnv)
  assign(marker, TRUE, envir = .GlobalEnv)
  invisible(TRUE)
}

nh_m0_grid <- function(protocol = nh_protocol(), root = nh_authority_root(protocol)) {
  p <- file.path(root, protocol$upstream$m0_grid_artifact)
  if (!file.exists(p)) stop("Missing frozen M0 grid authority: ", p, call. = FALSE)
  x <- readRDS(p)
  g <- as.data.frame(x$folds[[1L]]$tuning_grid, stringsAsFactors = FALSE)
  if (nrow(g) != 36L) stop("Expected 36-row M0 grid authority.", call. = FALSE)
  g
}

nh_m0_training_data <- function(raw, timing, allowed) {
  d <- raw[as.character(raw$season) %in% allowed, , drop = FALSE]
  t <- timing[match(as.character(d$season), as.character(timing$season)), , drop = FALSE]
  if (any(!is.finite(t$ignition_weekF))) stop("Missing allowed-season ignition truth for M0 training.", call. = FALSE)
  d$p <- ifelse(d$N > 0, d$y / d$N, NA_real_)
  d$phase <- as.integer(d$weekF >= ceiling(t$ignition_weekF))
  d
}

nh_build_m1_reference <- function(raw, timing, allowed, protocol = nh_protocol()) {
  u <- protocol$upstream
  d <- raw[as.character(raw$season) %in% allowed, , drop = FALSE]
  tt <- timing[match(as.character(d$season), as.character(timing$season)), , drop = FALSE]
  if (any(!is.finite(tt$ignition_weekF))) stop("Missing allowed-season ignition truth for M1 reference.", call. = FALSE)
  d$iWeekF <- as.numeric(tt$ignition_weekF)
  d$iWeek <- ceiling(d$iWeekF)
  anchor <- stats::median(unique(data.frame(season=d$season, iWeekF=d$iWeekF))$iWeekF)
  d$newWeek <- as.numeric(d$weekF) - d$iWeekF + anchor
  d$phase <- as.integer(d$weekF >= ceiling(d$iWeekF))
  d$neg <- d$N - d$y
  d$fit <- ifelse(d$N > 0, d$y / d$N, NA_real_)
  attr(d, "anchorWeek") <- anchor
  attr(d, "ignD") <- unique(d[, c("season", "iWeek", "iWeekF"), drop = FALSE])
  # M1 uses a fixed 52-week aligned reference-template domain. This is not the
  # season calendar: raw weekF values remain keyed integers (including week 53)
  # and are never wrapped or inferred from this template length.
  attr(d, "template_weeks") <- 52L
  in_domain <- is.finite(d$newWeek) & d$newWeek >= 1 & d$newWeek <= 52
  available_k <- length(unique(d$newWeek[in_domain]))
  if (available_k < as.integer(u$m1_k_ref)) {
    stop("M1 reference support is smaller than frozen k_ref=", u$m1_k_ref,
         "; refusing silent basis shrinkage.", call. = FALSE)
  }
  ref <- estimateRef(d, exSeason = character(0), k = as.integer(u$m1_k_ref),
                     n_weeks = 52L, method = u$m1_ref_method,
                     timing_mode = u$timing_mode)
  hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
  list(ref = ref, hyper = hyper, aligned = d)
}

nh_fit_upstream <- function(raw_data, excluded_seasons, protocol = nh_protocol(),
                            labels = NULL, controls = list(), n_cores = 1L,
                            cache_dir = NULL, force = FALSE) {
  nh_load_page_source()
  excluded <- sort(unique(as.character(excluded_seasons)))
  allowed <- setdiff(protocol$principal_seasons, excluded)
  if (length(allowed) < 4L) stop("Strict upstream fit requires at least four allowed seasons.", call. = FALSE)
  timing <- labels %||% nh_read_timing(protocol = protocol)
  timing_allowed <- timing[as.character(timing$season) %in% allowed, , drop = FALSE]
  nh_assert_label_subset(timing_allowed, allowed, evaluated_seasons = excluded)
  if (!identical(sort(unique(as.character(timing_allowed$season))), sort(allowed))) {
    stop("Timing-label subset does not exactly equal allowed seasons.", call. = FALSE)
  }
  source_files <- c("PAGe/R/m0_training.R", "PAGe/R/m1_reference.R", "PAGe/R/pipeline_bridge.R")
  package_source_hashes <- vapply(file.path(nh_repo_root(), source_files), nh_hash_file, character(1))
  scratch_source <- "scripts/m2_nhistory_nested_upstream.R"
  scratch_source_hash <- if (file.exists(scratch_source)) nh_hash_file(scratch_source) else NA_character_
  source_hash <- nh_hash_object(list(package = package_source_hashes, scratch_upstream = scratch_source_hash))
  allowed_data <- raw_data[as.character(raw_data$season) %in% allowed, c("season","weekF","y","N"), drop=FALSE]
  key <- nh_upstream_key(excluded, nh_hash_object(allowed_data), nh_hash_object(timing_allowed),
                         nh_hash_object(protocol$upstream), nh_hash_object(protocol),
                         nh_hash_object(controls), source_hash)
  if (!is.null(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    cp <- file.path(cache_dir, paste0(key, ".rds"))
    if (!force && file.exists(cp)) {
      z <- tryCatch(readRDS(cp), error = function(e) NULL)
      if (nh_upstream_cache_valid(z, key)) return(z)
    }
  } else cp <- NULL
  md <- nh_m0_training_data(raw_data, timing_allowed, allowed)
  truth <- data.frame(season = allowed,
                      ignition_target_weekF = timing_allowed$ignition_weekF[match(allowed, timing_allowed$season)],
                      stringsAsFactors = FALSE)
  tune_args <- protocol$upstream$m0_tune_args
  tune_args$ncores <- as.integer(max(1L, n_cores))
  tune_args$verbose <- FALSE
  tune_args$progress_every <- 100000L
  m0 <- loso_M0v2(md, grid = nh_m0_grid(protocol), timing_truth = truth,
                  timing_mode = protocol$upstream$timing_mode,
                  selection_policy = "legacy", verbose = FALSE, tune_args = tune_args)
  if (is.null(m0$best_params)) stop("Local M0 LOSO did not produce best_params.", call. = FALSE)
  m1 <- nh_build_m1_reference(raw_data, timing_allowed, allowed, protocol)
  out <- list(
    upstream_key = key, excluded_seasons = excluded, allowed_seasons = allowed,
    m0_best_params = m0$best_params, m0_context_id = m0$context_id,
    m0_grid_hash = nh_hash_object(nh_m0_grid(protocol)),
    ref = m1$ref, hyper = m1$hyper,
    provenance = list(
      data_hash = nh_hash_object(allowed_data), label_hash = nh_hash_object(timing_allowed),
      source_hash = source_hash, protocol_hash = nh_hash_object(nh_scientific_protocol(protocol)),
      m0_selection = protocol$upstream$m0_selection_policy,
      m1_controls = protocol$upstream,
      evaluated_labels_used = FALSE
    )
  )
  out$cache_sha256 <- nh_hash_object(out)
  if (!is.null(cp)) {
    tmp <- paste0(cp, ".tmp-", Sys.getpid())
    saveRDS(out, tmp); if (!file.rename(tmp, cp)) stop("Failed atomic upstream cache write.", call. = FALSE)
  }
  out
}

nh_predict_prefix <- function(raw_data, upstream, row_season, origins = NULL,
                              horizons = c(1L,2L), protocol = nh_protocol()) {
  nh_load_page_source()
  row_season <- as.character(row_season)
  if (!row_season %in% protocol$principal_seasons) stop("Unknown row season.", call. = FALSE)
  if (!row_season %in% upstream$excluded_seasons) {
    stop("Cross-fitted row prediction requires its season to be excluded from the upstream fit.", call. = FALSE)
  }
  seasonD <- raw_data[as.character(raw_data$season) == row_season, , drop = FALSE]
  if (!nrow(seasonD)) stop("No row-season observations.", call. = FALSE)
  if (is.null(origins)) origins <- sort(unique(as.integer(seasonD$weekF)))
  u <- protocol$upstream
  pieces <- list()
  for (origin in as.integer(origins)) {
    prefix <- seasonD[is.finite(seasonD$weekF) & seasonD$weekF <= origin, , drop = FALSE]
    dec <- m2_subset_prefix_declaration(prefix, upstream$m0_best_params, origin,
                                        start_week = 1L, timing_mode = u$timing_mode)
    if (!is.finite(dec$week)) next
    pp <- m1_walkforward_predictions(
      seasonD = prefix, ref = upstream$ref, hyper = upstream$hyper, ign_out = NULL,
      params = upstream$m0_best_params, horizons = as.integer(horizons), eval_weeks = origin,
      use_ci = TRUE, temperature = u$m1_temperature, rise_weight = u$m1_rise_weight,
      trough_weight = u$m1_trough_weight, peak_decay = u$m1_peak_decay,
      slope_weight = u$m1_slope_weight, slope_window = u$m1_slope_window,
      dynamic_temp = u$m1_dynamic_temp, dynamic_temp_pivot = u$m1_dynamic_temp_pivot,
      spread_method = u$m1_spread_method, timing_mode = u$timing_mode,
      peak_stabilization = "causal"
    )
    pp <- as.data.frame(pp)
    if (!nrow(pp)) next
    obs <- m2_subset_observed_features(prefix, dec$week, protocol$ordinary_grid$alpha_state)
    f <- obs[obs$weekF == origin, c("z","u","d"), drop=FALSE]
    if (nrow(f) != 1L || any(!is.finite(unlist(f)))) next
    pp$row_season <- as.character(pp$season)
    pp$origin_weekF <- as.integer(pp$eval_weekF)
    pp$horizon <- as.integer(pp$h)
    pp$peak_weekF_origin <- as.numeric(pp$peak_weekF)
    pp$peak_ci_width <- as.numeric(pp$peak_weekF_hi) - as.numeric(pp$peak_weekF_lo)
    pp$declaration_weekF <- as.numeric(dec$week)
    pp$z <- as.numeric(f$z); pp$u <- as.numeric(f$u); pp$d <- as.numeric(f$d)
    pp$tau <- pmax(-6, pmin(6, as.numeric(pp$target_weekF) - pp$peak_weekF_origin))
    pp$m1_logit <- stats::qlogis(pmin(1 - 1e-12, pmax(1e-12, as.numeric(pp$m1_p_hat))))
    pp$m1_p <- as.numeric(pp$m1_p_hat)
    pp$lead <- paste0("h", pp$horizon)
    pp$upstream_key <- upstream$upstream_key
    pp$upstream_excluded_seasons <- paste(upstream$excluded_seasons, collapse = "|")
    pp$upstream_allowed_seasons <- paste(upstream$allowed_seasons, collapse = "|")
    pp$prefix_hash <- nh_hash_object(prefix[,c("season","weekF","y","N"),drop=FALSE])
    pieces[[length(pieces)+1L]] <- pp
  }
  if (!length(pieces)) return(data.frame())
  do.call(rbind, pieces)
}

nh_build_smoke_rows <- function(raw_data, outer_season, validation_season,
                                protocol = nh_protocol(), origins = c(18L,19L), horizons = c(1L,2L),
                                n_cores = 1L, cache_dir = NULL) {
  pair <- sort(c(outer_season, validation_season))
  up_val <- nh_fit_upstream(raw_data, pair, protocol, n_cores = n_cores, cache_dir = cache_dir)
  rows <- list(nh_predict_prefix(raw_data, up_val, validation_season, origins, horizons, protocol))
  train_seasons <- setdiff(protocol$principal_seasons, pair)
  for (s in utils::head(train_seasons, 2L)) {
    triple <- sort(c(pair, s))
    up_s <- nh_fit_upstream(raw_data, triple, protocol, n_cores = n_cores, cache_dir = cache_dir)
    rows[[length(rows)+1L]] <- nh_predict_prefix(raw_data, up_s, s, origins, horizons, protocol)
  }
  ans <- do.call(rbind, rows)
  if (!nrow(ans)) stop("Strict smoke produced no M1 forecasts.", call. = FALSE)
  ledger <- nh_raw_ledger(raw_data, protocol)
  keep <- c("row_season","origin_weekF","horizon","target_weekF","y_target","N_target","common_eligible")
  ans <- merge(ans, ledger[, keep], by=c("row_season","origin_weekF","horizon","target_weekF"), all.x=TRUE, sort=FALSE)
  ans <- ans[!is.na(ans$forecast_available) & ans$forecast_available, , drop=FALSE]
  ans <- nh_add_n_features(ans, raw_data, protocol, require_common = TRUE)
  nh_validate_stage_b_fields(ans)
  ans$row_hash <- nh_hash_object(ans[, c("row_season","origin_weekF","horizon","target_weekF")])
  ans$weight_hash <- nh_hash_object(rep(1, nrow(ans)))
  ans
}
