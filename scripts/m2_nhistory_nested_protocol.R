`%||%` <- function(x, y) if (is.null(x)) y else x

nh_repo_root <- function() {
  configured <- Sys.getenv("PAGE_NHISTORY_CODE_ROOT", "")
  legacy <- Sys.getenv("PAGE_NHISTORY_SOURCE_ROOT", "")
  candidates <- unique(Filter(nzchar, c(configured, ".", "../PAGe", legacy)))
  for (x in candidates) {
    root <- suppressWarnings(normalizePath(x, mustWork = FALSE))
    if (file.exists(file.path(root, "PAGe", "DESCRIPTION"))) return(root)
  }
  stop("Cannot locate the PAGe code root; set PAGE_NHISTORY_CODE_ROOT.", call. = FALSE)
}

nh_authority_root <- function(protocol = nh_protocol()) {
  configured <- Sys.getenv("PAGE_NHISTORY_AUTHORITY_ROOT", "")
  legacy <- Sys.getenv("PAGE_NHISTORY_SOURCE_ROOT", "")
  code_root <- nh_repo_root()
  candidates <- unique(Filter(nzchar, c(configured, legacy, code_root)))
  required <- c(unname(unlist(protocol$data_authority)), protocol$upstream$m0_grid_artifact)
  for (x in candidates) {
    root <- suppressWarnings(normalizePath(x, mustWork = FALSE))
    if (all(file.exists(file.path(root, required)))) return(root)
  }
  stop(
    "Cannot locate the locked N-history authority artifacts; set PAGE_NHISTORY_AUTHORITY_ROOT ",
    "to a directory containing the observation, timing, eligibility, and M0-grid authorities.",
    call. = FALSE
  )
}

nh_out_dir <- function() {
  Sys.getenv(
    "PAGE_NHISTORY_NESTED_OUT",
    "artifacts/m2-a-full-ntrend-nested-loso-v2"
  )
}

nh_protocol <- function(run_id = NULL) {
  if (is.null(run_id) || !nzchar(run_id)) {
    run_id <- paste0("m2-a-full-ntrend-v2-", format(Sys.time(), "%Y%m%dT%H%M%S%z"))
  }
  principal <- c(
    "2012-13", "2013-14", "2014-15", "2016-17", "2017-18", "2018-19",
    "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
  )
  excluded <- c("2011-12", "2015-16", "2020-21", "2021-22")
  list(
    protocol_id = "m2-a-full-ntrend-nested-loso-v2",
    run_id = run_id,
    route = "research_m1_offset_subset_nhistory",
    production_eligible = FALSE,
    principal_seasons = principal,
    excluded_seasons = excluded,
    min_origin_weekF = 13L,
    horizons = c(1L, 2L),
    required_history_offsets = 4:0,
    required_anchor_weekF = 8L,
    ordinary_grid = list(
      intercept = c(FALSE, TRUE),
      k_z = c(0L, 3L, 4L, 5L),
      k_u = c(0L, 7L, 8L, 9L),
      k_d = c(0L, 3L, 4L, 5L, 6L, 7L),
      k_tau_stage_a = 0L,
      conf_scale_stage_a = "none",
      alpha_state = 0.20,
      gamma = 1.40,
      fit_method = "REML",
      smooth_basis = "ts",
      online_bias_correction = "off"
    ),
    stage_b = list(
      retained = TRUE,
      top_stage_a_per_option = 2L,
      k_tau = c(0L, 3L, 4L, 5L),
      conf_scale = c("none", "peak_ci"),
      requires_causal_peak_ci = TRUE
    ),
    data_authority = list(
      observations = "artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv",
      timing = "artifacts/v3-joint-timing-contract-v4/timing_contract_v4.csv",
      eligibility = "artifacts/v3-joint-timing-contract-v4/modeling_eligibility_v4.csv"
    ),
    upstream = list(
      m0_grid_artifact = "artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds",
      m0_selection_policy = "legacy_fractional_loso_within_allowed_set",
      m0_tune_args = list(miss_penalty = 0, lambda = 20, kappa = 0, gamma = 25, gamma_late = 0, iWeek = TRUE),
      m1_k_ref = 30L,
      m1_ref_method = "fs",
      m1_temperature = 0.25,
      m1_rise_weight = 1.0,
      m1_trough_weight = 0.1,
      m1_peak_decay = 0.3,
      m1_slope_weight = 16,
      m1_slope_window = 6L,
      m1_dynamic_temp = FALSE,
      m1_dynamic_temp_pivot = 10L,
      m1_spread_method = "between",
      timing_mode = "fractional"
    ),
    boundary = list(
      enabled = TRUE,
      max_rounds = 2L,
      max_specs = 64L,
      adjacent_step = "half_observed_spacing",
      unresolved_after_cap = "unresolved_boundary",
      min_nll_gain = c(k_z = 0.00025, k_u = 0.00025, k_d = 0.00025, intercept = 0)
    ),
    n_options = c(
      "OFF", "EXP025", "EXP050", "EXP075", "EXP100",
      "ACCEL22", "REL8", "DL2", "SPLIT22", "EXP050_X_G1"
    ),
    scoring = list(
      ordinary_phase_weights = list(
        pre_ignition = 0, rise = 2, turning = 3, decline = 1
      ),
      ordinary_scale = "equal_week_then_equal_season",
      n_option_scale = "unweighted_equal_week_then_equal_season",
      selector = "paired_one_se_vs_raw_best_complexity_risk_loss_id"
    ),
    gates_authorized = c("gate0", "gate1", "gate2"),
    gate4_authorized = FALSE,
    full_loso_allowed_by_this_worker = FALSE
  )
}

nh_n_options <- function(protocol = nh_protocol()) {
  data.frame(
    n_option = protocol$n_options,
    n_complexity = c(0L, 1L, 1L, 1L, 1L, 1L, 1L, 2L, 2L, 2L),
    risk_order = c(0L, 1L, 1L, 1L, 1L, 2L, 3L, 2L, 2L, 3L),
    columns = c(
      "",
      "n_exp025",
      "n_exp050",
      "n_exp075",
      "n_exp100",
      "n_accel22",
      "n_rel8",
      "n_d1+n_d2",
      "n_recent2+n_older2",
      "n_exp050+n_exp050_x_growth1"
    ),
    definition = c(
      "No N-history covariate; delegates to the ordinary M1-offset subset M2 path.",
      "Exponentially weighted log-N changes with lambda 0.25.",
      "Exponentially weighted log-N changes with lambda 0.50.",
      "Exponentially weighted log-N changes with lambda 0.75.",
      "Exponentially weighted log-N changes with lambda 1.00.",
      "Recent two-week log-N change minus older two-week log-N change.",
      "log(N_t) - log(N_week8).",
      "Two columns: d1 and d2.",
      "Two columns: recent2 and older2.",
      "EXP050 plus EXP050 times raw stabilized-logit one-week positivity growth."
    ),
    stringsAsFactors = FALSE
  )
}

nh_grid_stage_a <- function(protocol = nh_protocol()) {
  g <- expand.grid(
    intercept = protocol$ordinary_grid$intercept,
    k_z = protocol$ordinary_grid$k_z,
    k_u = protocol$ordinary_grid$k_u,
    k_d = protocol$ordinary_grid$k_d,
    k_tau = protocol$ordinary_grid$k_tau_stage_a,
    conf_scale = protocol$ordinary_grid$conf_scale_stage_a,
    alpha_state = protocol$ordinary_grid$alpha_state,
    gamma = protocol$ordinary_grid$gamma,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  g$enabled_count <- as.integer(g$intercept) +
    rowSums(g[c("k_z", "k_u", "k_d", "k_tau")] > 0)
  g$spec_id <- sprintf(
    "i%d_kz%d_ku%d_kd%d_ktau%d_cs%s_a%.2f_g%.2f",
    as.integer(g$intercept), g$k_z, g$k_u, g$k_d, g$k_tau,
    g$conf_scale, g$alpha_state, g$gamma
  )
  g <- g[order(g$enabled_count, g$spec_id), ]
  rownames(g) <- NULL
  g[, c(
    "spec_id", "intercept", "k_z", "k_u", "k_d", "k_tau",
    "conf_scale", "alpha_state", "gamma", "enabled_count"
  )]
}

nh_make_fold_index <- function(protocol = nh_protocol()) {
  seasons <- protocol$principal_seasons
  out <- list()
  for (outer in seasons) {
    train <- setdiff(seasons, outer)
    out[[length(out) + 1L]] <- data.frame(
      fold_role = "outer",
      outer_season = outer,
      validation_season = NA_character_,
      evaluated_row_season = outer,
      upstream_excluded_seasons = outer,
      upstream_training_seasons = paste(train, collapse = "|"),
      m2_training_seasons = paste(train, collapse = "|"),
      stringsAsFactors = FALSE
    )
    for (validation in train) {
      inner_train <- setdiff(seasons, c(outer, validation))
      out[[length(out) + 1L]] <- data.frame(
        fold_role = "inner_validation",
        outer_season = outer,
        validation_season = validation,
        evaluated_row_season = validation,
        upstream_excluded_seasons = paste(c(outer, validation), collapse = "|"),
        upstream_training_seasons = paste(inner_train, collapse = "|"),
        m2_training_seasons = paste(inner_train, collapse = "|"),
        stringsAsFactors = FALSE
      )
      for (row_season in inner_train) {
        out[[length(out) + 1L]] <- data.frame(
          fold_role = "inner_training_row",
          outer_season = outer,
          validation_season = validation,
          evaluated_row_season = row_season,
          upstream_excluded_seasons = paste(c(outer, validation, row_season), collapse = "|"),
          upstream_training_seasons = paste(setdiff(seasons, c(outer, validation, row_season)), collapse = "|"),
          m2_training_seasons = paste(inner_train, collapse = "|"),
          stringsAsFactors = FALSE
        )
      }
    }
    for (row_season in train) {
      out[[length(out) + 1L]] <- data.frame(
        fold_role = "outer_training_row",
        outer_season = outer,
        validation_season = NA_character_,
        evaluated_row_season = row_season,
        upstream_excluded_seasons = paste(c(outer, row_season), collapse = "|"),
        upstream_training_seasons = paste(setdiff(seasons, c(outer, row_season)), collapse = "|"),
        m2_training_seasons = paste(train, collapse = "|"),
        stringsAsFactors = FALSE
      )
    }
  }
  ans <- do.call(rbind, out)
  ans$row_id <- seq_len(nrow(ans))
  ans[, c("row_id", setdiff(names(ans), "row_id"))]
}

nh_hash_file <- function(path) {
  if (!file.exists(path)) {
    return(NA_character_)
  }
  digest::digest(file = path, algo = "sha256")
}

nh_hash_object <- function(x) {
  digest::digest(x, algo = "sha256")
}

nh_scientific_protocol <- function(protocol = nh_protocol()) {
  x <- protocol
  x$run_id <- NULL
  x
}

nh_write_json <- function(x, path, pretty = TRUE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = pretty, null = "null")
}

nh_authority_paths <- function(protocol = nh_protocol(), root = nh_authority_root(protocol)) {
  unlist(lapply(protocol$data_authority, function(x) file.path(root, x)), use.names = TRUE)
}

nh_read_flu_data <- function(path = NULL, protocol = nh_protocol(), root = nh_authority_root(protocol)) {
  if (is.null(path)) path <- nh_authority_paths(protocol, root)[["observations"]]
  d <- read.csv(path, stringsAsFactors = FALSE)
  required <- c("season", "weekF", "y_A", "N_A")
  missing <- setdiff(required, names(d))
  if (length(missing)) stop("Canonical A input missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
  d$season <- as.character(d$season)
  d$weekF <- as.integer(d$weekF)
  d$y <- as.numeric(d$y_A)
  d$N <- as.numeric(d$N_A)
  d$neg <- d$N - d$y
  d$fit <- ifelse(d$N > 0, d$y / d$N, NA_real_)
  d <- d[order(d$season, d$weekF), ]
  rownames(d) <- NULL
  d
}

nh_read_timing <- function(path = NULL, protocol = nh_protocol(), root = nh_authority_root(protocol)) {
  if (is.null(path)) path <- nh_authority_paths(protocol, root)[["timing"]]
  x <- read.csv(path, stringsAsFactors = FALSE)
  required <- c("season", "A_ignition_weekF", "A_peak_weekF")
  missing <- setdiff(required, names(x))
  if (length(missing)) stop("Timing authority missing: ", paste(missing, collapse = ", "), call. = FALSE)
  data.frame(season = as.character(x$season), ignition_weekF = as.numeric(x$A_ignition_weekF),
             peak_weekF = as.numeric(x$A_peak_weekF), stringsAsFactors = FALSE)
}

nh_input_manifest <- function(paths) {
  data.frame(
    path = paths,
    exists = file.exists(paths),
    bytes = ifelse(file.exists(paths), file.info(paths)$size, NA_real_),
    sha256 = vapply(paths, nh_hash_file, character(1)),
    stringsAsFactors = FALSE
  )
}

nh_source_manifest <- function(paths) {
  data.frame(
    path = paths,
    exists = file.exists(paths),
    sha256 = vapply(paths, nh_hash_file, character(1)),
    stringsAsFactors = FALSE
  )
}

nh_gate_source_manifest <- function(root = nh_repo_root()) {
  scratch_sources <- c(
    sort(list.files("scripts", "^m2_nhistory_nested_.*[.]R$", full.names = TRUE)),
    "scripts/run_m2_nhistory_gate0_v2.R",
    "scripts/run_m2_nhistory_full_nested_loso_v2.R",
    "test/m2-nhistory-nested/run_gate1.R",
    "test/m2-nhistory-nested/run_gate2_smoke.R"
  )
  package_sources <- c(
    "PAGe/R/m0_training.R", "PAGe/R/m1_reference.R", "PAGe/R/pipeline_bridge.R",
    "PAGe/R/m2_subset_correction.R", "PAGe/R/pipeline_orchestrator.R"
  )
  scratch_sources <- unique(scratch_sources)
  physical_paths <- c(scratch_sources, file.path(root, package_sources))
  m <- nh_source_manifest(physical_paths)
  # Hash identities must be portable across Asgard/BCC checkout locations.
  m$path <- c(scratch_sources, package_sources)
  m
}

nh_gate_source_hash <- function(root = nh_repo_root()) {
  m <- nh_gate_source_manifest(root)
  if (any(!m$exists) || anyNA(m$sha256)) stop("Gate source manifest is incomplete.", call. = FALSE)
  payload <- paste(paste(as.character(m$path), as.character(m$sha256), sep = "\t"), collapse = "\n")
  digest::digest(payload, algo = "sha256", serialize = FALSE)
}

nh_validate_inputs <- function(protocol = nh_protocol(), data_path = NULL) {
  d <- nh_read_flu_data(data_path, protocol = protocol)
  seasons <- sort(unique(as.character(d$season)))
  poison <- intersect(protocol$excluded_seasons, protocol$principal_seasons)
  if (length(poison)) {
    stop("Protocol has seasons both included and excluded: ", paste(poison, collapse = ", "), call. = FALSE)
  }
  missing_principal <- setdiff(protocol$principal_seasons, seasons)
  if (length(missing_principal)) {
    stop("Principal season(s) absent from input: ", paste(missing_principal, collapse = ", "), call. = FALSE)
  }
  overlap_excluded <- intersect(protocol$excluded_seasons, protocol$principal_seasons)
  duplicate_keys <- anyDuplicated(paste(d$season, d$weekF))
  if (duplicate_keys) {
    stop("Input has duplicate (season, weekF) keys.", call. = FALSE)
  }
  cov <- aggregate(weekF ~ season, d, function(x) {
    paste0(min(x), "-", max(x), " (n=", length(unique(x)), ")")
  })
  names(cov)[2L] <- "weekF_coverage"
  cov$principal <- cov$season %in% protocol$principal_seasons
  cov$excluded <- cov$season %in% protocol$excluded_seasons
  cov2025 <- cov$weekF_coverage[cov$season == "2025-26"]
  list(
    status = "pass",
    seasons_present = seasons,
    principal_count = length(protocol$principal_seasons),
    excluded_count = length(protocol$excluded_seasons),
    overlap_excluded = overlap_excluded,
    coverage = cov,
    coverage_2025_26 = cov2025,
    input_hash = nh_hash_file(if (is.null(data_path)) nh_authority_paths(protocol)[["observations"]] else data_path),
    allowed_data_hash = nh_hash_object(d[d$season %in% protocol$principal_seasons, c("season", "weekF", "y", "N")])
  )
}

nh_planned_jobs <- function(protocol = nh_protocol()) {
  n_outer <- length(protocol$principal_seasons)
  n_inner <- n_outer * (n_outer - 1L)
  stage_a_specs <- nrow(nh_grid_stage_a(protocol))
  n_opts <- nrow(nh_n_options(protocol))
  data.frame(
    job_layer = c(
      "gate0_preflight",
      "gate1_synthetic_contracts",
      "gate2_bounded_smoke",
      "gate3_upstream_cache_not_launched",
      "gate4_stage_a_initial_not_launched",
      "gate4_stage_b_max_extra_not_launched"
    ),
    planned_units = c(1L, NA_integer_, NA_integer_, 231L, choose(n_outer, 2L) * stage_a_specs * n_opts, n_inner * 14L * n_opts),
    status = c("authorized", "authorized", "authorized", "not_launched", "not_authorized", "not_authorized"),
    stringsAsFactors = FALSE
  )
}

nh_write_gate0 <- function(out_dir = nh_out_dir(), protocol = nh_protocol()) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  root <- nh_repo_root()
  authority_root <- nh_authority_root(protocol)
  source_manifest <- nh_gate_source_manifest(root)
  source_hash <- nh_gate_source_hash(root)
  protocol_hash <- nh_hash_object(nh_scientific_protocol(protocol))
  auth <- nh_authority_paths(protocol, authority_root)
  inputs <- c(auth, file.path(authority_root, protocol$upstream$m0_grid_artifact))
  validation <- nh_validate_inputs(protocol)
  timing <- nh_read_timing(protocol=protocol,root=authority_root)
  missing_timing <- setdiff(protocol$principal_seasons, as.character(timing$season[is.finite(timing$ignition_weekF) & is.finite(timing$peak_weekF)]))
  if(length(missing_timing)) stop("Principal seasons missing finite ignition/peak scoring labels: ",paste(missing_timing,collapse=", "),call.=FALSE)
  fold_index <- nh_make_fold_index(protocol); nh_assert_all_fold_contracts(fold_index,protocol)
  grid <- nh_grid_stage_a(protocol); nopts <- nh_n_options(protocol)
  if(nrow(grid)!=192L||nrow(nopts)!=10L||nrow(fold_index)!=1221L) stop("Protocol count invariant failed.",call.=FALSE)
  git <- function(args) tryCatch(system2("git", c("-C", root, args), stdout=TRUE, stderr=TRUE), error=function(e) NA_character_)
  source_paths <- as.character(source_manifest$path)
  source_status <- git(c("status", "--porcelain", "--untracked-files=no", "--", source_paths))
  source_status <- source_status[!is.na(source_status) & nzchar(source_status)]
  source_tree_dirty <- length(source_status) > 0L
  preflight <- list(
    gate="gate0", status="PASS", run_id=protocol$run_id,
    code_root=normalizePath(root), authority_root=normalizePath(authority_root),
    source_root=normalizePath(root),
    branch=git(c("branch","--show-current"))[1], head=git(c("rev-parse","HEAD"))[1],
    source_tree_dirty=source_tree_dirty, source_tree_status=source_status,
    source_hash=source_hash, protocol_hash=protocol_hash,
    stage_a_spec_count=nrow(grid), n_option_count=nrow(nopts), stage_a_joint_candidate_count=nrow(grid)*nrow(nopts),
    fold_roles=nrow(fold_index), inner_validation_contexts=110L,
    authoritative_observations=normalizePath(auth[["observations"]]), authoritative_timing=normalizePath(auth[["timing"]]),
    upstream_recipe="local M0 36-grid LOSO + local fractional M1 reference/hyper; evaluated-row labels forbidden",
    boundary_policy=protocol$boundary, validation=validation[names(validation)!="coverage"],
    full_loso_launched=FALSE, gate4_authorized=FALSE,
    notes=c("Experiment code is explicitly bound to the current PAGe code root and source-hashed.",
            "Locked observations/timing/M0 authorities may live under a separate authority root and are independently hashed.",
            "Gate 0 performs zero scientific M2 fits.","Canonical v3 runtime/deployment files are read-only inputs to source protection hashes.")
  )
  nh_write_json(protocol,file.path(out_dir,"protocol.json")); write.csv(nh_input_manifest(inputs),file.path(out_dir,"input_manifest.csv"),row.names=FALSE)
  write.csv(source_manifest,file.path(out_dir,"source_manifest.csv"),row.names=FALSE)
  writeLines(capture.output(sessionInfo()),file.path(out_dir,"environment.txt")); write.csv(fold_index,file.path(out_dir,"fold_index.csv"),row.names=FALSE)
  write.csv(grid,file.path(out_dir,"grid_stage_a.csv"),row.names=FALSE); write.csv(nopts,file.path(out_dir,"n_options.csv"),row.names=FALSE)
  write.csv(nh_planned_jobs(protocol),file.path(out_dir,"planned_jobs.csv"),row.names=FALSE); write.csv(validation$coverage,file.path(out_dir,"input_coverage.csv"),row.names=FALSE)
  nh_write_json(preflight,file.path(out_dir,"preflight_report.json")); invisible(preflight)
}

