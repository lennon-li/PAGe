#!/usr/bin/env Rscript

# Strict full nested LOSO controller for the isolated M1-offset-subset +/- N
# research experiment. This file never writes PAGe production/runtime state.

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default = NULL) {
  p <- paste0("--", name, "=")
  hit <- args[startsWith(args, p)]
  if (!length(hit)) return(default)
  sub(p, "", hit[[length(hit)]], fixed = TRUE)
}
arg_flag <- function(name) paste0("--", name) %in% args

mode <- arg_value("mode", "dry-run")
workers <- as.integer(arg_value("workers", Sys.getenv("PAGE_WORKERS", "32")))
if (!is.finite(workers) || workers < 1L) stop("--workers must be a positive integer.", call. = FALSE)
workers <- as.integer(workers)
force <- isTRUE(arg_flag("force"))

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)

helper_files <- c(
  "scripts/m2_nhistory_nested_protocol.R",
  "scripts/m2_nhistory_nested_features.R",
  "scripts/m2_nhistory_nested_upstream.R",
  "scripts/m2_nhistory_nested_models.R",
  "scripts/m2_nhistory_nested_selection.R",
  "scripts/m2_nhistory_nested_jobs.R"
)
for (f in helper_files) {
  if (!file.exists(f)) stop("Missing helper: ", f, call. = FALSE)
  source(f)
}

RUN_ID <- "m2-a-full-ntrend-v2-locked-20260930"
p <- nh_protocol(RUN_ID)
out <- nh_out_dir()
dir.create(out, recursive = TRUE, showWarnings = FALSE)
root <- nh_repo_root()
raw <- nh_read_flu_data(protocol = p, root = root)
timing <- nh_read_timing(protocol = p, root = root)
nh_load_page_source(root)

source_hash <- nh_gate_source_hash(root)
raw_hash <- nh_hash_object(raw[, c("season", "weekF", "y", "N"), drop = FALSE])
protocol_hash <- nh_hash_object(nh_scientific_protocol(p))

now_iso <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write_status <- function(stage, status = "running", extra = list()) {
  z <- c(list(
    run_id = RUN_ID, route = p$route, mode = mode, stage = stage,
    status = status, workers = workers, timestamp = now_iso(),
    source_hash = source_hash, protocol_hash = protocol_hash
  ), extra)
  nh_write_json(z, file.path(out, "run_status.json"))
  invisible(z)
}

read_json <- function(path) {
  if (!file.exists(path)) stop("Missing required gate artifact: ", path, call. = FALSE)
  jsonlite::read_json(path, simplifyVector = TRUE)
}
assert_pre_gates <- function() {
  g0 <- read_json(file.path(out, "preflight_report.json"))
  if (!identical(as.character(g0$status), "PASS")) stop("Gate 0 is not PASS.", call. = FALSE)
  if (!identical(as.character(g0$source_hash), source_hash) || !identical(as.character(g0$protocol_hash), protocol_hash)) {
    stop("Gate 0 evidence is stale for the current source/protocol hash.", call. = FALSE)
  }
  if (!identical(g0$source_tree_dirty, FALSE)) {
    stop("Gate 0 source-hashed files are not commit-clean; commit the scientific source before Gate 3/full.", call. = FALSE)
  }
  g1m <- read_json(file.path(out, "gate1_manifest.json"))
  if (!identical(as.character(g1m$status), "PASS") || !identical(as.character(g1m$source_hash), source_hash) ||
      !identical(as.character(g1m$protocol_hash), protocol_hash)) {
    stop("Gate 1 evidence is stale for the current source/protocol hash.", call. = FALSE)
  }
  g1p <- file.path(out, "stage_b_contract.csv")
  if (!file.exists(g1p)) stop("Missing Gate 1 machine-readable contract table.", call. = FALSE)
  g1 <- read.csv(g1p, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(c("test", "status") %in% names(g1)) || !nrow(g1) || any(g1$status != "PASS")) {
    stop("Gate 1 is not fully PASS.", call. = FALSE)
  }
  g2 <- read_json(file.path(out, "smoke_manifest.json"))
  if (!identical(as.character(g2$status), "PASS") ||
      !identical(as.character(g2$source_hash), source_hash) || !identical(as.character(g2$protocol_hash), protocol_hash) ||
      !isTRUE(g2$strict_pair_exclusion) || !isTRUE(g2$strict_triple_exclusion) ||
      !isTRUE(g2$off_identity) || !isTRUE(g2$real_future_invariance) ||
      !isTRUE(g2$outcome_free_prediction) || !isTRUE(g2$selection_self_test) ||
      !isTRUE(g2$score_cache_self_test) ||
      !is.finite(g2$max_prediction_delta) || g2$max_prediction_delta > 1e-10) {
    stop("Gate 2 smoke is not a strict PASS.", call. = FALSE)
  }
  invisible(TRUE)
}

protect_paths <- c(
  file.path(root, "PAGe/R/v3_runtime.R"),
  file.path(root, "2026/run_weekly_shadow_release_v5.R")
)
protect_before <- nh_source_manifest(protect_paths)
assert_protection <- function() {
  after <- nh_source_manifest(protect_paths)
  if (!identical(protect_before, after)) stop("Canonical protection hashes changed during research run.", call. = FALSE)
  invisible(TRUE)
}

excluded_key <- function(x) paste(sort(unique(as.character(x))), collapse = "|")
pair_key <- function(x) paste(sort(unique(as.character(x))), collapse = "__")
all_exclusion_sets <- function() {
  ss <- p$principal_seasons
  unlist(lapply(1:3, function(k) combn(ss, k, simplify = FALSE)), recursive = FALSE)
}
all_contexts <- function(sets) {
  do.call(rbind, lapply(sets, function(ex) {
    data.frame(
      excluded_key = excluded_key(ex),
      excluded_n = length(ex),
      evaluated_season = sort(ex),
      stringsAsFactors = FALSE
    )
  }))
}
parallel_map <- function(X, FUN, n = workers) {
  n <- max(1L, min(as.integer(n), length(X)))
  out <- if (n <= 1L) lapply(X, FUN) else parallel::mclapply(X, FUN, mc.cores = n, mc.preschedule = FALSE)
  bad <- which(vapply(out, inherits, logical(1), what = "try-error"))
  if (length(bad)) {
    msgs <- vapply(bad, function(i) paste0("[", i, "] ", as.character(out[[i]])[[1L]]), character(1))
    stop("Parallel worker failure(s): ", paste(msgs, collapse = " | "), call. = FALSE)
  }
  out
}

checkpoint_value <- function(path) {
  z <- readRDS(path)
  if (!is.list(z) || !isTRUE(z$complete) || is.null(z$value)) stop("Invalid checkpoint: ", path, call. = FALSE)
  if (!identical(z$sha256, nh_hash_object(z$value))) stop("Checkpoint value hash mismatch: ", path, call. = FALSE)
  z$value
}

atomic_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  write.csv(x, tmp, row.names = FALSE, na = "")
  if (!file.rename(tmp, path)) stop("Failed atomic CSV write: ", path, call. = FALSE)
  invisible(path)
}
atomic_rds <- function(x, path) nh_atomic_save_rds(x, path)

# ---------------- Gate 3: strict upstream cache and immutable row ledgers ----------------

build_gate3 <- function() {
  assert_pre_gates()
  write_status("gate3_upstream")
  sets <- all_exclusion_sets()
  if (length(sets) != 231L) stop("Expected exactly 231 singleton/pair/triple exclusion sets.", call. = FALSE)
  up_dir <- file.path(out, "upstream")
  dir.create(up_dir, recursive = TRUE, showWarnings = FALSE)

  up_rows <- parallel_map(seq_along(sets), function(i) {
    ex <- sets[[i]]
    u <- nh_fit_upstream(raw, ex, p, n_cores = 1L, cache_dir = up_dir, force = force)
    if (!identical(sort(u$excluded_seasons), sort(ex))) stop("Upstream exclusion mismatch.", call. = FALSE)
    if (length(intersect(u$allowed_seasons, ex))) stop("Forbidden season entered upstream allowed set.", call. = FALSE)
    f <- file.path(up_dir, paste0(u$upstream_key, ".rds"))
    data.frame(
      excluded_key = excluded_key(ex), excluded_n = length(ex),
      upstream_key = u$upstream_key, allowed_n = length(u$allowed_seasons),
      file = normalizePath(f), sha256 = nh_hash_file(f), stringsAsFactors = FALSE
    )
  })
  up_manifest <- do.call(rbind, up_rows)
  if (nrow(up_manifest) != 231L || anyDuplicated(up_manifest$excluded_key)) stop("Upstream manifest invariant failed.", call. = FALSE)
  atomic_csv(up_manifest, file.path(out, "upstream_manifest.csv"))

  contexts <- all_contexts(sets)
  if (nrow(contexts) != 616L || anyDuplicated(paste(contexts$excluded_key, contexts$evaluated_season))) {
    stop("Expected exactly 616 unique exclusion/evaluated-season replay contexts.", call. = FALSE)
  }
  ledger_raw <- nh_raw_ledger(raw, p)
  nh_validate_common_ledger(ledger_raw[ledger_raw$common_eligible %in% TRUE, , drop = FALSE])
  ctx_dir <- file.path(out, "ledgers", "contexts")
  dir.create(ctx_dir, recursive = TRUE, showWarnings = FALSE)

  ctx_rows <- parallel_map(seq_len(nrow(contexts)), function(i) {
    cr <- contexts[i, , drop = FALSE]
    upm <- up_manifest[up_manifest$excluded_key == cr$excluded_key, , drop = FALSE]
    if (nrow(upm) != 1L) stop("Cannot resolve unique upstream context.", call. = FALSE)
    eval_s <- as.character(cr$evaluated_season)
    ex <- strsplit(as.character(cr$excluded_key), "\\|", fixed = FALSE)[[1L]]
    if (!eval_s %in% ex) stop("Replay season is not excluded from its upstream fit.", call. = FALSE)
    ctx_id <- digest::digest(list(excluded = sort(ex), evaluated = eval_s, upstream_key = upm$upstream_key,
                                  raw_hash = raw_hash, protocol_hash = protocol_hash, source_hash = source_hash), algo = "sha256")
    path <- file.path(ctx_dir, paste0(ctx_id, ".rds"))
    payload <- list(excluded_key = cr$excluded_key, evaluated_season = eval_s,
                    upstream_key = upm$upstream_key, raw_hash = raw_hash,
                    source_hash = source_hash, protocol_hash = protocol_hash)
    value <- nh_run_cached("strict_context_rows", payload, path, function() {
      up <- readRDS(as.character(upm$file))
      ds <- raw[raw$season == eval_s, , drop = FALSE]
      origins <- sort(unique(as.integer(ds$weekF[ds$weekF >= p$min_origin_weekF])))
      pp <- nh_predict_prefix(raw, up, eval_s, origins = origins, horizons = p$horizons, protocol = p)
      if (!nrow(pp)) return(data.frame())
      keep <- c("row_season", "origin_weekF", "horizon", "target_weekF", "y_target", "N_target",
                "target_present", "target_valid", "target_scoreable", "common_scoreable",
                "scoreability_reason", "forecast_eligible", "common_eligible")
      z <- merge(pp, ledger_raw[, keep], by = c("row_season", "origin_weekF", "horizon", "target_weekF"), all.x = TRUE, sort = FALSE)
      z <- z[!is.na(z$forecast_available) & z$forecast_available & z$common_eligible %in% TRUE, , drop = FALSE]
      z <- nh_add_n_features(z, raw, p, require_common = TRUE)
      if (!nrow(z)) return(z)
      nh_validate_stage_b_fields(z)
      if (any(z$upstream_excluded_seasons != paste(sort(ex), collapse = "|"))) stop("Replay provenance exclusion mismatch.", call. = FALSE)
      target_idx <- match(paste(z$row_season, z$target_weekF), paste(raw$season, raw$weekF))
      if ("denominator_regime" %in% names(raw)) z$denominator_regime_target <- as.character(raw$denominator_regime[target_idx])
      z
    }, p)
    data.frame(
      context_id = ctx_id, excluded_key = cr$excluded_key, excluded_n = cr$excluded_n,
      evaluated_season = eval_s, upstream_key = upm$upstream_key,
      file = normalizePath(path), sha256 = nh_hash_file(path), rows = nrow(value), stringsAsFactors = FALSE
    )
  })
  ctx_manifest <- do.call(rbind, ctx_rows)
  if (nrow(ctx_manifest) != 616L || any(ctx_manifest$rows <= 0L)) stop("Context replay cache is incomplete or empty.", call. = FALSE)
  atomic_csv(ctx_manifest, file.path(out, "context_manifest.csv"))

  ctx_path <- function(ex, eval_s) {
    k <- excluded_key(ex)
    hit <- ctx_manifest[ctx_manifest$excluded_key == k & ctx_manifest$evaluated_season == eval_s, , drop = FALSE]
    if (nrow(hit) != 1L) stop("Missing unique context ledger for ", k, " / ", eval_s, call. = FALSE)
    as.character(hit$file)
  }
  ctx_value <- function(ex, eval_s) checkpoint_value(ctx_path(ex, eval_s))

  pairs <- combn(p$principal_seasons, 2L, simplify = FALSE)
  pair_dir <- file.path(out, "ledgers", "pairs")
  dir.create(pair_dir, recursive = TRUE, showWarnings = FALSE)
  pair_manifest <- do.call(rbind, lapply(pairs, function(pr) {
    pk <- pair_key(pr)
    path <- file.path(pair_dir, paste0(pk, ".rds"))
    payload <- list(pair = sort(pr), context_manifest_hash = nh_hash_file(file.path(out, "context_manifest.csv")), protocol_hash = protocol_hash)
    val <- nh_run_cached("pair_ledger", payload, path, function() {
      tr_seasons <- setdiff(p$principal_seasons, pr)
      tr_all <- do.call(rbind, lapply(tr_seasons, function(s) ctx_value(c(pr, s), s)))
      va <- do.call(rbind, lapply(sort(pr), function(s) ctx_value(pr, s)))
      tr <- tr_all[tr_all$target_scoreable %in% TRUE, , drop = FALSE]
      if (!nrow(tr) || !nrow(va)) stop("Pair ledger has empty train/validation rows.", call. = FALSE)
      for (s in tr_seasons) {
        z <- tr[tr$row_season == s, , drop = FALSE]
        exp_ex <- paste(sort(c(pr, s)), collapse = "|")
        if (!nrow(z) || any(z$upstream_excluded_seasons != exp_ex)) stop("Triple-excluded training ledger mismatch.", call. = FALSE)
      }
      for (s in pr) {
        z <- va[va$row_season == s, , drop = FALSE]
        exp_ex <- paste(sort(pr), collapse = "|")
        if (!nrow(z) || any(z$upstream_excluded_seasons != exp_ex)) stop("Pair-excluded validation ledger mismatch.", call. = FALSE)
      }
      list(train = tr, validation = va, pair = sort(pr),
           coverage = data.frame(train_forecast_rows=nrow(tr_all), train_scoreable_rows=nrow(tr),
                                 validation_forecast_rows=nrow(va), validation_scoreable_rows=sum(va$target_scoreable %in% TRUE)))
    }, p)
    data.frame(pair_key = pk, season_a = sort(pr)[1], season_b = sort(pr)[2], file = normalizePath(path),
               sha256 = nh_hash_file(path), train_rows = nrow(val$train), validation_rows = nrow(val$validation), stringsAsFactors = FALSE)
  }))
  if (nrow(pair_manifest) != 55L) stop("Expected 55 pair ledgers.", call. = FALSE)
  atomic_csv(pair_manifest, file.path(out, "pair_ledger_manifest.csv"))

  outer_dir <- file.path(out, "ledgers", "outer")
  dir.create(outer_dir, recursive = TRUE, showWarnings = FALSE)
  outer_manifest <- do.call(rbind, lapply(p$principal_seasons, function(o) {
    path <- file.path(outer_dir, paste0(o, ".rds"))
    payload <- list(outer = o, context_manifest_hash = nh_hash_file(file.path(out, "context_manifest.csv")), protocol_hash = protocol_hash)
    val <- nh_run_cached("outer_ledger", payload, path, function() {
      tr_seasons <- setdiff(p$principal_seasons, o)
      tr_all <- do.call(rbind, lapply(tr_seasons, function(s) ctx_value(c(o, s), s)))
      tr <- tr_all[tr_all$target_scoreable %in% TRUE, , drop = FALSE]
      ev <- ctx_value(o, o)
      if (!nrow(tr) || !nrow(ev)) stop("Outer ledger empty.", call. = FALSE)
      for (s in tr_seasons) {
        z <- tr[tr$row_season == s, , drop = FALSE]
        exp_ex <- paste(sort(c(o, s)), collapse = "|")
        if (!nrow(z) || any(z$upstream_excluded_seasons != exp_ex)) stop("Outer-training pair exclusion mismatch.", call. = FALSE)
      }
      if (any(ev$upstream_excluded_seasons != o)) stop("Outer evaluation singleton exclusion mismatch.", call. = FALSE)
      truth_cols <- intersect(c("row_season", "origin_weekF", "horizon", "target_weekF", "y_target", "N_target",
                                "target_present", "target_valid", "target_scoreable", "scoreability_reason",
                                "denominator_regime_target"), names(ev))
      truth <- ev[, truth_cols, drop = FALSE]
      features <- ev[, setdiff(names(ev), c("y_target", "N_target", "denominator_regime_target")), drop = FALSE]
      list(train = tr, eval_features = features, truth = truth, outer = o,
           coverage = data.frame(train_forecast_rows=nrow(tr_all), train_scoreable_rows=nrow(tr),
                                 eval_forecast_rows=nrow(ev), eval_scoreable_rows=sum(ev$target_scoreable %in% TRUE)))
    }, p)
    if (any(c("y_target", "N_target") %in% names(val$eval_features))) stop("Outer outcomes leaked into sealed feature ledger.", call. = FALSE)
    data.frame(outer_season = o, file = normalizePath(path), sha256 = nh_hash_file(path),
               train_rows = nrow(val$train), eval_rows = nrow(val$eval_features), stringsAsFactors = FALSE)
  }))
  atomic_csv(outer_manifest, file.path(out, "outer_ledger_manifest.csv"))

  report <- list(
    gate = "gate3", status = "PASS", upstream_sets = nrow(up_manifest), replay_contexts = nrow(ctx_manifest),
    pair_ledgers = nrow(pair_manifest), outer_ledgers = nrow(outer_manifest),
    upstream_manifest_sha256 = nh_hash_file(file.path(out, "upstream_manifest.csv")),
    context_manifest_sha256 = nh_hash_file(file.path(out, "context_manifest.csv")),
    pair_manifest_sha256 = nh_hash_file(file.path(out, "pair_ledger_manifest.csv")),
    outer_manifest_sha256 = nh_hash_file(file.path(out, "outer_ledger_manifest.csv")),
    strict_pair_exclusion = TRUE, strict_triple_exclusion = TRUE, evaluated_labels_used = FALSE,
    outer_outcomes_sealed = TRUE, completed = now_iso()
  )
  nh_write_json(report, file.path(out, "gate3_report.json"))
  assert_protection()
  write_status("gate3", "PASS", report)
  invisible(report)
}

# ---------------- Candidate identity, scoring, and selection ----------------

spec_id <- function(x) {
  sprintf("i%d_kz%d_ku%d_kd%d_ktau%d_cs%s_a%.2f_g%.2f",
          as.integer(as.logical(x$intercept)), as.integer(x$k_z), as.integer(x$k_u), as.integer(x$k_d),
          as.integer(x$k_tau), as.character(x$conf_scale), as.numeric(x$alpha_state), as.numeric(x$gamma))
}
normalize_spec <- function(x) {
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  x$intercept <- as.logical(x$intercept)
  for (nm in c("k_z", "k_u", "k_d", "k_tau")) x[[nm]] <- as.integer(x[[nm]])
  x$conf_scale <- as.character(x$conf_scale)
  x$alpha_state <- as.numeric(x$alpha_state); x$gamma <- as.numeric(x$gamma)
  x$enabled_count <- as.integer(x$intercept) + (x$k_z > 0) + (x$k_u > 0) + (x$k_d > 0) + (x$k_tau > 0)
  x$spec_id <- vapply(seq_len(nrow(x)), function(i) spec_id(x[i, , drop = FALSE]), character(1))
  x[, c("spec_id", "intercept", "k_z", "k_u", "k_d", "k_tau", "conf_scale", "alpha_state", "gamma", "enabled_count"), drop = FALSE]
}

phase_weights <- function(rows) {
  I <- timing$ignition_weekF[match(rows$row_season, timing$season)]
  P <- timing$peak_weekF[match(rows$row_season, timing$season)]
  t <- as.numeric(rows$target_weekF)
  if (any(!is.finite(I) | !is.finite(P) | !is.finite(t))) stop("Scoring phase metadata incomplete.", call. = FALSE)
  ifelse(t < I, 0,
         ifelse(t < P - 1, 2,
                ifelse(t <= P + 3, 3, 1)))
}
score_predictions <- function(rows, p_hat = NULL, spec_id_value, n_option, fit_error = "") {
  rows <- as.data.frame(rows)
  if (!is.null(p_hat) && length(p_hat) != nrow(rows)) stop("Prediction length mismatch.", call. = FALSE)
  out_rows <- list()
  for (s in sort(unique(rows$row_season))) for (h in p$horizons) {
    take <- rows$row_season == s & rows$horizon == h
    z_all <- rows[take, , drop = FALSE]
    if (!nrow(z_all)) next
    pp_all <- if (is.null(p_hat)) rep(NA_real_, nrow(z_all)) else p_hat[take]
    sc <- z_all$target_scoreable %in% TRUE
    z <- z_all[sc, , drop = FALSE]
    pp <- pp_all[sc]
    if (!nrow(z)) {
      out_rows[[length(out_rows) + 1L]] <- data.frame(
        validation_season=s,horizon=as.integer(h),spec_id=spec_id_value,n_option=n_option,status="unscored",
        ordinary_loss=NA_real_,n_loss=NA_real_,mae=NA_real_,brier=NA_real_,rows=0L,
        forecast_rows=nrow(z_all),ordinary_weight_sum=NA_real_,row_hash=nh_hash_object(z[,c("row_season","origin_weekF","horizon","target_weekF"),drop=FALSE]),
        weight_hash=nh_hash_object(numeric()),fit_error=fit_error,stringsAsFactors=FALSE)
      next
    }
    ord_w <- phase_weights(z)
    keydf <- z[, c("row_season", "origin_weekF", "horizon", "target_weekF"), drop = FALSE]
    rh <- nh_hash_object(keydf)
    wh <- nh_hash_object(ord_w)
    status <- if (is.null(p_hat)) "failed" else "ok"
    if (!is.null(p_hat) && any(!is.finite(pp) | pp < 0 | pp > 1)) status <- "failed"
    loss <- if (status == "ok") nh_bernoulli_loss(z$y_target, z$N_target, pp) else rep(NA_real_, nrow(z))
    q <- z$y_target / z$N_target
    wsum <- sum(ord_w)
    if (status == "ok" && (!is.finite(wsum) || wsum <= 0)) status <- "unscored"
    out_rows[[length(out_rows) + 1L]] <- data.frame(
      validation_season = s, horizon = as.integer(h), spec_id = spec_id_value, n_option = n_option,
      status = status,
      ordinary_loss = if (status == "ok") sum(ord_w * loss) / wsum else NA_real_,
      n_loss = if (status == "ok") mean(loss) else NA_real_,
      mae = if (status == "ok") mean(abs(pp - q)) else NA_real_,
      brier = if (status == "ok") mean((pp - q)^2) else NA_real_,
      rows = nrow(z), forecast_rows = nrow(z_all), ordinary_weight_sum = wsum,
      row_hash = rh, weight_hash = wh, fit_error = fit_error,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, out_rows)
}

fit_score_one <- function(pair_obj, spec, n_option) {
  err <- ""
  fit <- tryCatch(nh_fit(pair_obj$train, spec, n_option, gamma = as.numeric(spec$gamma), protocol = p),
                  error = function(e) { err <<- conditionMessage(e); NULL })
  if (is.null(fit)) return(score_predictions(pair_obj$validation, NULL, spec$spec_id, n_option, err))
  pred <- tryCatch(nh_predict(fit, pair_obj$validation)$p_hat,
                   error = function(e) { err <<- conditionMessage(e); NULL })
  if (is.null(pred)) return(score_predictions(pair_obj$validation, NULL, spec$spec_id, n_option, err))
  score_predictions(pair_obj$validation, pred, spec$spec_id, n_option, "")
}

outer_slice <- function(scores, outer, n_option = NULL, horizon = NULL) {
  z <- scores[(scores$season_a == outer | scores$season_b == outer) & scores$validation_season != outer, , drop = FALSE]
  if (!is.null(n_option)) z <- z[z$n_option == n_option, , drop = FALSE]
  if (!is.null(horizon)) z <- z[z$horizon == horizon, , drop = FALSE]
  z
}

alloff_spec_id <- function(catalog) {
  z <- catalog[catalog$enabled_count == 0L & catalog$conf_scale == "none", , drop = FALSE]
  if (nrow(z) != 1L) stop("Cannot identify unique all-corrections-off spec.", call. = FALSE)
  z$spec_id[[1L]]
}

select_ordinary <- function(scores, candidate_map, catalog, outer, n_option, horizon, baseline_id) {
  cand <- candidate_map[candidate_map$outer_season == outer & candidate_map$n_option == n_option &
                          (candidate_map$horizon == 0L | candidate_map$horizon == horizon), , drop = FALSE]
  cand_ids <- unique(as.character(cand$spec_id))
  base <- outer_slice(scores, outer, "OFF", horizon)
  base <- base[base$spec_id == baseline_id & base$status == "ok", , drop = FALSE]
  expected_v <- sort(setdiff(p$principal_seasons, outer))
  if (nrow(base) != length(expected_v) || !identical(sort(base$validation_season), expected_v)) {
    stop("All-off robustness baseline is incomplete for outer ", outer, " h", horizon, call. = FALSE)
  }
  rows <- lapply(cand_ids, function(id) {
    z <- outer_slice(scores, outer, n_option, horizon)
    z <- z[z$spec_id == id & z$status == "ok", , drop = FALSE]
    if (nrow(z) != length(expected_v) || !identical(sort(z$validation_season), expected_v)) return(NULL)
    cand_guard <- z
    cand_guard$outer_season <- outer
    base_guard <- base
    base_guard$outer_season <- outer
    guard <- nh_robust_guard(cand_guard, base_guard, tol = 1e-15)
    if (length(guard$deltas) != length(expected_v)) stop("Robustness matched-ledger count mismatch.", call. = FALSE)
    pass <- isTRUE(guard$pass)
    meta <- catalog[catalog$spec_id == id, , drop = FALSE]
    if (nrow(meta) != 1L) stop("Spec catalog lookup failed: ", id, call. = FALSE)
    data.frame(spec_id = id, pass_robust = pass, mean_ordinary_loss = mean(z$ordinary_loss),
               enabled_count = meta$enabled_count, stringsAsFactors = FALSE)
  })
  tab <- if (length(Filter(Negate(is.null), rows))) do.call(rbind, Filter(Negate(is.null), rows)) else data.frame()
  if (!nrow(tab)) {
    stop("No complete candidate fits for ordinary selection: ", outer, " / ", n_option, " / h", horizon, call. = FALSE)
  }
  ok <- tab[tab$pass_robust, , drop = FALSE]
  if (!nrow(ok)) {
    return(data.frame(
      outer_season = outer, horizon = as.integer(horizon), requested_n_option = n_option,
      effective_n_option = "OFF", spec_id = baseline_id, mean_ordinary_loss = mean(base$ordinary_loss),
      enabled_count = 0L, fallback_to_alloff = TRUE, selection_status = "robust_fallback_alloff",
      stringsAsFactors = FALSE
    ))
  }
  ok <- ok[order(ok$mean_ordinary_loss, ok$enabled_count, ok$spec_id), , drop = FALSE]
  win <- ok[1L, , drop = FALSE]
  data.frame(
    outer_season = outer, horizon = as.integer(horizon), requested_n_option = n_option,
    effective_n_option = n_option, spec_id = win$spec_id, mean_ordinary_loss = win$mean_ordinary_loss,
    enabled_count = win$enabled_count, fallback_to_alloff = FALSE, selection_status = "selected",
    stringsAsFactors = FALSE
  )
}

# ---------------- Generic pair/spec score jobs ----------------

load_pair_manifest <- function() read.csv(file.path(out, "pair_ledger_manifest.csv"), stringsAsFactors = FALSE)
load_pair_obj <- function(pk) {
  pm <- load_pair_manifest(); hit <- pm[pm$pair_key == pk, , drop = FALSE]
  if (nrow(hit) != 1L) stop("Pair ledger not found: ", pk, call. = FALSE)
  checkpoint_value(as.character(hit$file))
}

validate_score_group <- function(value, req, pair_key_value, n_option_value, path = "<memory>") {
  value <- as.data.frame(value, stringsAsFactors = FALSE)
  req <- unique(as.data.frame(req, stringsAsFactors = FALSE)[, c("pair_key", "n_option", "spec_id"), drop = FALSE])
  required_cols <- c(
    "validation_season", "horizon", "spec_id", "n_option", "status",
    "ordinary_loss", "n_loss", "mae", "brier", "rows", "forecast_rows",
    "ordinary_weight_sum", "row_hash", "weight_hash", "fit_error",
    "pair_key", "season_a", "season_b"
  )
  missing_cols <- setdiff(required_cols, names(value))
  if (length(missing_cols)) {
    stop("Score-group cache missing required columns at ", path, ": ", paste(missing_cols, collapse = ", "), call. = FALSE)
  }
  if (!nrow(value)) stop("Score-group cache is empty at ", path, call. = FALSE)
  if (any(value$pair_key != pair_key_value)) stop("Score-group pair_key mismatch at ", path, call. = FALSE)
  if (any(value$n_option != n_option_value)) stop("Score-group n_option mismatch at ", path, call. = FALSE)
  expected_ids <- sort(unique(as.character(req$spec_id)))
  observed_ids <- sort(unique(as.character(value$spec_id)))
  if (!identical(observed_ids, expected_ids)) {
    missing_ids <- setdiff(expected_ids, observed_ids)
    extra_ids <- setdiff(observed_ids, expected_ids)
    stop(
      "Score-group spec coverage mismatch at ", path,
      "; missing=", if (length(missing_ids)) paste(missing_ids, collapse = "|") else "<none>",
      "; extra=", if (length(extra_ids)) paste(extra_ids, collapse = "|") else "<none>",
      call. = FALSE
    )
  }
  key <- value[, c("validation_season", "horizon", "spec_id"), drop = FALSE]
  if (anyDuplicated(key)) stop("Score-group cache contains duplicate validation/horizon/spec rows at ", path, call. = FALSE)

  # Every requested spec must score the identical validation-season/horizon
  # ledger. A truncated checkpoint can otherwise retain all spec IDs while
  # silently dropping one or more rows for a subset of specs, only failing much
  # later during Stage-A/B selection.
  ref_id <- expected_ids[[1L]]
  ref <- value[value$spec_id == ref_id, c("validation_season", "horizon"), drop = FALSE]
  ref <- unique(ref[order(ref$validation_season, ref$horizon), , drop = FALSE])
  rownames(ref) <- NULL
  for (id in expected_ids[-1L]) {
    got <- value[value$spec_id == id, c("validation_season", "horizon"), drop = FALSE]
    got <- unique(got[order(got$validation_season, got$horizon), , drop = FALSE])
    rownames(got) <- NULL
    if (!identical(got, ref)) {
      stop("Score-group cache has non-rectangular validation/horizon coverage at ", path,
           "; spec=", id, "; reference_spec=", ref_id, call. = FALSE)
    }
  }
  invisible(TRUE)
}

validate_score_layer_assembly <- function(scores, request_map, layer = "<layer>") {
  scores <- as.data.frame(scores, stringsAsFactors = FALSE)
  req <- unique(as.data.frame(request_map, stringsAsFactors = FALSE)[,
    c("pair_key", "n_option", "spec_id"), drop = FALSE])
  if (!nrow(scores)) stop("Assembled score layer is empty for ", layer, call. = FALSE)

  score_req <- unique(scores[, c("pair_key", "n_option", "spec_id"), drop = FALSE])
  score_req <- score_req[order(score_req$pair_key, score_req$n_option, score_req$spec_id), , drop = FALSE]
  req <- req[order(req$pair_key, req$n_option, req$spec_id), , drop = FALSE]
  rownames(score_req) <- NULL; rownames(req) <- NULL
  if (!identical(score_req, req)) {
    stop("Assembled score-layer request coverage mismatch for ", layer, call. = FALSE)
  }

  global_key <- scores[, c("pair_key", "n_option", "spec_id", "validation_season", "horizon"), drop = FALSE]
  if (anyDuplicated(global_key)) {
    stop("Assembled score layer contains duplicate pair/N/spec/validation/horizon rows for ", layer, call. = FALSE)
  }

  groups <- split(scores, paste(scores$pair_key, scores$n_option, sep = "\r"))
  for (gname in names(groups)) {
    z <- groups[[gname]]
    ids <- sort(unique(as.character(z$spec_id)))
    ref <- unique(z[z$spec_id == ids[[1L]], c("validation_season", "horizon"), drop = FALSE])
    ref <- ref[order(ref$validation_season, ref$horizon), , drop = FALSE]
    rownames(ref) <- NULL
    for (id in ids[-1L]) {
      got <- unique(z[z$spec_id == id, c("validation_season", "horizon"), drop = FALSE])
      got <- got[order(got$validation_season, got$horizon), , drop = FALSE]
      rownames(got) <- NULL
      if (!identical(got, ref)) {
        stop("Assembled score layer has non-rectangular group coverage for ", layer,
             "; group=", gname, "; spec=", id, call. = FALSE)
      }
    }
  }
  invisible(TRUE)
}

run_score_layer <- function(layer, request_map, catalog) {
  request_map <- unique(request_map[, c("pair_key", "n_option", "spec_id"), drop = FALSE])
  groups <- split(request_map, paste(request_map$pair_key, request_map$n_option, sep = "\r"))
  job_dir <- file.path(out, "jobs", layer)
  dir.create(job_dir, recursive = TRUE, showWarnings = FALSE)
  write_status(layer, "running", list(groups = length(groups), requested_fits = nrow(request_map)))
  done <- parallel_map(names(groups), function(gname) {
    req <- groups[[gname]]
    pk <- as.character(req$pair_key[[1L]]); no <- as.character(req$n_option[[1L]])
    ids <- sort(unique(as.character(req$spec_id)))
    pm <- load_pair_manifest(); ph <- pm$sha256[match(pk, pm$pair_key)]
    path <- file.path(job_dir, paste0(gsub("[^A-Za-z0-9_-]", "_", pk), "__", no, ".rds"))
    payload <- list(pair_key = pk, pair_ledger_sha256 = ph, n_option = no, spec_ids = ids,
                    spec_catalog_hash = nh_hash_object(catalog[catalog$spec_id %in% ids, , drop = FALSE]),
                    source_hash = source_hash, protocol_hash = protocol_hash)
    value <- nh_run_cached(layer, payload, path, function() {
      po <- load_pair_obj(pk)
      out_scores <- lapply(ids, function(id) {
        sp <- catalog[catalog$spec_id == id, , drop = FALSE]
        if (nrow(sp) != 1L) stop("Missing unique spec in catalog: ", id, call. = FALSE)
        fit_score_one(po, sp, no)
      })
      z <- do.call(rbind, out_scores)
      pr <- strsplit(pk, "__", fixed = TRUE)[[1L]]
      z$pair_key <- pk; z$season_a <- pr[[1L]]; z$season_b <- pr[[2L]]
      z
    }, p)
    validate_score_group(value, req, pk, no, path)
    data.frame(path = normalizePath(path), pair_key = pk, n_option = no, stringsAsFactors = FALSE)
  })
  manifest <- do.call(rbind, done)
  if (nrow(manifest) != length(groups)) stop("Score-group manifest row count mismatch for ", layer, call. = FALSE)
  if (anyDuplicated(manifest[, c("pair_key", "n_option"), drop = FALSE])) stop("Score-group manifest contains duplicate pair/N groups for ", layer, call. = FALSE)
  if (anyDuplicated(manifest$path)) stop("Score-group manifest contains duplicate checkpoint paths for ", layer, call. = FALSE)
  if (any(!file.exists(manifest$path))) stop("Score-group manifest references missing checkpoint files for ", layer, call. = FALSE)
  vals <- lapply(seq_len(nrow(manifest)), function(i) {
    value <- checkpoint_value(manifest$path[[i]])
    req <- groups[[paste(manifest$pair_key[[i]], manifest$n_option[[i]], sep = "\r")]]
    validate_score_group(value, req, manifest$pair_key[[i]], manifest$n_option[[i]], manifest$path[[i]])
    value
  })
  scores <- do.call(rbind, vals)
  validate_score_layer_assembly(scores, request_map, layer)
  atomic_csv(manifest, file.path(out, "jobs", paste0(layer, "_manifest.csv")))
  atomic_rds(scores, file.path(out, "inner", paste0(layer, "_scores.rds")))
  write_status(layer, "PASS", list(groups = nrow(manifest), score_rows = nrow(scores)))
  scores
}

# ---------------- Stage B and bounded boundary expansion ----------------

stage_b_for_outer <- function(stage_a_scores, stage_a_catalog, outer, n_option) {
  z <- outer_slice(stage_a_scores, outer, n_option, NULL)
  expected <- length(setdiff(p$principal_seasons, outer)) * length(p$horizons)
  agg <- lapply(unique(z$spec_id), function(id) {
    q <- z[z$spec_id == id & z$status == "ok", , drop = FALSE]
    if (nrow(q) != expected) return(NULL)
    meta <- stage_a_catalog[stage_a_catalog$spec_id == id, , drop = FALSE]
    data.frame(spec_id = id, mean_loss = mean(q$ordinary_loss), enabled_count = meta$enabled_count, stringsAsFactors = FALSE)
  })
  agg <- do.call(rbind, Filter(Negate(is.null), agg))
  if (!nrow(agg)) stop("No complete stage-A candidates for stage B: ", outer, " / ", n_option, call. = FALSE)
  agg <- agg[order(agg$mean_loss, agg$enabled_count, agg$spec_id), , drop = FALSE]
  top <- head(agg$spec_id, p$stage_b$top_stage_a_per_option)
  rows <- list()
  for (id in top) {
    base <- stage_a_catalog[stage_a_catalog$spec_id == id, , drop = FALSE]
    for (kt in p$stage_b$k_tau) for (cs in p$stage_b$conf_scale) {
      x <- base; x$k_tau <- as.integer(kt); x$conf_scale <- as.character(cs)
      rows[[length(rows) + 1L]] <- normalize_spec(x)
    }
  }
  unique(do.call(rbind, rows))
}

initial_candidate_map <- function(catalog) {
  do.call(rbind, lapply(p$principal_seasons, function(o) do.call(rbind, lapply(p$n_options, function(no) {
    data.frame(outer_season = o, n_option = no, horizon = 0L, spec_id = catalog$spec_id,
               stage = "stage_a", stringsAsFactors = FALSE)
  }))))
}

make_boundary_requests <- function(selections, catalog, round) {
  # Governed practical-gain caps exist for the ordinary subset axes k_z/u/d.
  # Stage-B k_tau is a fixed finalist axis, not an adaptive boundary axis.
  base_max <- c(k_z = max(p$ordinary_grid$k_z), k_u = max(p$ordinary_grid$k_u),
                k_d = max(p$ordinary_grid$k_d))
  rows <- list()
  for (i in seq_len(nrow(selections))) {
    s <- selections[i, , drop = FALSE]
    if (isTRUE(s$fallback_to_alloff)) next
    sp <- catalog[catalog$spec_id == s$spec_id, , drop = FALSE]
    if (nrow(sp) != 1L) stop("Boundary selected spec absent from catalog.", call. = FALSE)
    for (ax in names(base_max)) {
      edge <- base_max[[ax]] + (round - 1L)
      if (as.integer(sp[[ax]]) != as.integer(edge)) next
      nx <- sp; nx[[ax]] <- as.integer(sp[[ax]]) + 1L; nx <- normalize_spec(nx)
      rows[[length(rows) + 1L]] <- data.frame(
        outer_season = s$outer_season, requested_n_option = s$requested_n_option,
        horizon = s$horizon, parent_spec_id = s$spec_id, spec_id = nx$spec_id,
        axis = ax, round = as.integer(round), gain_threshold = as.numeric(p$boundary$min_nll_gain[[ax]] %||% 0),
        stringsAsFactors = FALSE
      )
      attr(rows[[length(rows)]], "spec") <- nx
    }
  }
  if (!length(rows)) return(list(requests = data.frame(), specs = data.frame()))
  req <- do.call(rbind, lapply(rows, function(x) x))
  specs <- unique(do.call(rbind, lapply(rows, function(x) attr(x, "spec"))))
  list(requests = req, specs = specs)
}

# ---------------- Full inner search and sealed outer replay ----------------

run_full <- function() {
  assert_pre_gates()
  g3p <- file.path(out, "gate3_report.json")
  if (!file.exists(g3p) || !identical(as.character(read_json(g3p)$status), "PASS")) build_gate3()
  if (!identical(Sys.getenv("PAGE_FULL_LOSO", "NO"), "YES")) {
    stop("Full LOSO requires explicit PAGE_FULL_LOSO=YES after Gate 3 PASS.", call. = FALSE)
  }
  nh_write_json(list(authorized = TRUE, mechanism = "PAGE_FULL_LOSO=YES", timestamp = now_iso(),
                     gate3_sha256 = nh_hash_file(g3p), protocol_hash = protocol_hash),
                file.path(out, "gate4_authorization.json"))

  inner_dir <- file.path(out, "inner"); dir.create(inner_dir, recursive = TRUE, showWarnings = FALSE)
  stage_a_catalog <- normalize_spec(nh_grid_stage_a(p))
  baseline_id <- alloff_spec_id(stage_a_catalog)
  pairs <- read.csv(file.path(out, "pair_ledger_manifest.csv"), stringsAsFactors = FALSE)
  request_a <- do.call(rbind, lapply(seq_len(nrow(pairs)), function(i) do.call(rbind, lapply(p$n_options, function(no) {
    data.frame(pair_key = pairs$pair_key[i], n_option = no, spec_id = stage_a_catalog$spec_id, stringsAsFactors = FALSE)
  }))))
  stage_a_scores <- run_score_layer("stage_a", request_a, stage_a_catalog)
  candidate_map <- initial_candidate_map(stage_a_catalog)
  catalog <- stage_a_catalog

  sb_specs <- list(); sb_map <- list()
  for (o in p$principal_seasons) for (no in p$n_options) {
    zz <- stage_b_for_outer(stage_a_scores, stage_a_catalog, o, no)
    sb_specs[[length(sb_specs) + 1L]] <- zz
    sb_map[[length(sb_map) + 1L]] <- data.frame(outer_season = o, n_option = no, horizon = 0L,
                                                spec_id = zz$spec_id, stage = "stage_b", stringsAsFactors = FALSE)
  }
  sb_catalog <- unique(do.call(rbind, sb_specs))
  catalog <- unique(rbind(catalog, sb_catalog))
  sb_map <- do.call(rbind, sb_map)
  candidate_map <- unique(rbind(candidate_map, sb_map))
  extra_sb <- setdiff(sb_catalog$spec_id, stage_a_catalog$spec_id)
  request_b_rows <- list()
  for (i in seq_len(nrow(pairs))) {
    pk <- pairs$pair_key[i]; endpoints <- c(pairs$season_a[i], pairs$season_b[i])
    for (no in p$n_options) {
      ids <- unique(sb_map$spec_id[sb_map$outer_season %in% endpoints & sb_map$n_option == no])
      ids <- intersect(ids, extra_sb)
      if (length(ids)) request_b_rows[[length(request_b_rows) + 1L]] <- data.frame(pair_key = pk, n_option = no, spec_id = ids, stringsAsFactors = FALSE)
    }
  }
  stage_b_scores <- if (length(request_b_rows)) run_score_layer("stage_b", do.call(rbind, request_b_rows), catalog) else stage_a_scores[0, ]
  all_scores <- rbind(stage_a_scores, stage_b_scores)

  select_all <- function(scores, cmap, cat) {
    do.call(rbind, lapply(p$principal_seasons, function(o) do.call(rbind, lapply(p$n_options, function(no) do.call(rbind, lapply(p$horizons, function(h) {
      select_ordinary(scores, cmap, cat, o, no, h, baseline_id)
    }))))))
  }
  selections <- select_all(all_scores, candidate_map, catalog)
  selections$boundary_status <- "not_checked"
  boundary_report <- list()

  for (round in seq_len(p$boundary$max_rounds)) {
    br <- make_boundary_requests(selections, catalog, round)
    if (!nrow(br$requests)) {
      selections$boundary_status[selections$boundary_status == "not_checked"] <- "settled_interior_or_null"
      break
    }
    prev <- selections
    catalog <- unique(rbind(catalog, br$specs))
    add_map <- data.frame(outer_season = br$requests$outer_season,
                          n_option = br$requests$requested_n_option,
                          horizon = br$requests$horizon,
                          spec_id = br$requests$spec_id,
                          stage = paste0("boundary_r", round), stringsAsFactors = FALSE)
    candidate_map <- unique(rbind(candidate_map, add_map))
    rq <- list()
    for (i in seq_len(nrow(br$requests))) {
      r <- br$requests[i, , drop = FALSE]
      others <- setdiff(p$principal_seasons, r$outer_season)
      for (v in others) rq[[length(rq) + 1L]] <- data.frame(pair_key = pair_key(c(r$outer_season, v)), n_option = r$requested_n_option, spec_id = r$spec_id, stringsAsFactors = FALSE)
    }
    bs <- run_score_layer(paste0("boundary_r", round), unique(do.call(rbind, rq)), catalog)
    all_scores <- rbind(all_scores, bs)
    newsel <- select_all(all_scores, candidate_map, catalog)
    newsel$boundary_status <- "settled_no_outward_gain"
    for (i in seq_len(nrow(newsel))) {
      key <- prev$outer_season == newsel$outer_season[i] & prev$horizon == newsel$horizon[i] &
        prev$requested_n_option == newsel$requested_n_option[i]
      old <- prev[key, , drop = FALSE]
      req <- br$requests[br$requests$outer_season == newsel$outer_season[i] &
                           br$requests$requested_n_option == newsel$requested_n_option[i] &
                           br$requests$horizon == newsel$horizon[i] &
                           br$requests$spec_id == newsel$spec_id[i], , drop = FALSE]
      if (nrow(req) && nrow(old) == 1L && newsel$spec_id[i] != old$spec_id) {
        gain <- old$mean_ordinary_loss - newsel$mean_ordinary_loss[i]
        if (!is.finite(gain)) stop("Non-finite boundary matched gain.", call. = FALSE)
        if (gain <= req$gain_threshold[1L] + 1e-15) {
          keep_status <- paste0("stop_small_gain_", req$axis[1L], "_gain_", format(gain, scientific = TRUE))
          repl <- old; repl$boundary_status <- keep_status
          newsel[i, names(repl)] <- repl[1, names(repl)]
        } else {
          newsel$boundary_status[i] <- paste0("accepted_", req$axis[1L], "_gain_", format(gain, scientific = TRUE))
        }
        boundary_report[[length(boundary_report) + 1L]] <- data.frame(
          outer_season = newsel$outer_season[i], n_option = newsel$requested_n_option[i], horizon = newsel$horizon[i],
          round = round, parent_spec_id = old$spec_id, proposed_spec_id = req$spec_id[1L], axis = req$axis[1L],
          gain = gain, threshold = req$gain_threshold[1L], accepted = gain > req$gain_threshold[1L] + 1e-15,
          stringsAsFactors = FALSE)
      }
    }
    selections <- newsel
  }
  if (length(boundary_report)) {
    boundary_report <- do.call(rbind, boundary_report)
    atomic_csv(boundary_report, file.path(inner_dir, "boundary_report.csv"))
  } else atomic_csv(data.frame(), file.path(inner_dir, "boundary_report.csv"))

  # If the final accepted winner is still one step beyond the last explored edge,
  # retain it but mark the computational boundary honestly.
  if (p$boundary$max_rounds > 0L) {
    base_max <- c(k_z = max(p$ordinary_grid$k_z), k_u = max(p$ordinary_grid$k_u),
                  k_d = max(p$ordinary_grid$k_d))
    for (i in seq_len(nrow(selections))) {
      sp <- catalog[catalog$spec_id == selections$spec_id[i], , drop = FALSE]
      if (!nrow(sp)) next
      unresolved <- names(base_max)[vapply(names(base_max), function(ax) as.integer(sp[[ax]]) >= base_max[[ax]] + p$boundary$max_rounds, logical(1))]
      if (length(unresolved) && startsWith(selections$boundary_status[i], "accepted_")) {
        selections$boundary_status[i] <- paste0("unresolved_boundary_cap:", paste(unresolved, collapse = "+"))
      }
    }
  }

  # N-option paired one-SE selection after each option's ordinary M2 profile is frozen.
  paired_rows <- list(); n_selected <- list()
  for (o in p$principal_seasons) for (h in p$horizons) {
    ns <- list()
    for (no in p$n_options) {
      sel <- selections[selections$outer_season == o & selections$horizon == h & selections$requested_n_option == no, , drop = FALSE]
      if (nrow(sel) != 1L) stop("Ordinary selection table is not unique.", call. = FALSE)
      z <- outer_slice(all_scores, o, sel$effective_n_option, h)
      z <- z[z$spec_id == sel$spec_id & z$status == "ok", , drop = FALSE]
      expected_v <- sort(setdiff(p$principal_seasons, o))
      if (nrow(z) != length(expected_v) || !identical(sort(z$validation_season), expected_v)) stop("Selected option has incomplete N-loss folds.", call. = FALSE)
      ns[[length(ns) + 1L]] <- data.frame(validation_season = z$validation_season, n_option = no,
                                            n_loss = z$n_loss, row_hash = z$row_hash, weight_hash = z$weight_hash,
                                            stringsAsFactors = FALSE)
    }
    ns <- do.call(rbind, ns)
    dec <- nh_select_n(ns, nh_n_options(p))
    tab <- dec$table; tab$outer_season <- o; tab$horizon <- h; tab$raw_best <- dec$raw_best; tab$selected <- dec$selected
    paired_rows[[length(paired_rows) + 1L]] <- tab
    n_selected[[length(n_selected) + 1L]] <- data.frame(outer_season = o, horizon = h,
                                                         raw_best_n_option = dec$raw_best, selected_n_option = dec$selected,
                                                         stringsAsFactors = FALSE)
  }
  paired_table <- do.call(rbind, paired_rows); nsel <- do.call(rbind, n_selected)
  atomic_csv(selections, file.path(inner_dir, "ordinary_selection.csv"))
  atomic_csv(paired_table, file.path(inner_dir, "paired_n_selection.csv"))
  atomic_csv(nsel, file.path(inner_dir, "selected_n_by_outer_horizon.csv"))
  atomic_csv(candidate_map, file.path(inner_dir, "candidate_map.csv"))
  atomic_csv(catalog, file.path(inner_dir, "spec_catalog.csv"))
  atomic_rds(all_scores, file.path(inner_dir, "inner_fold_scores.rds"))

  final_cfg <- list()
  for (o in p$principal_seasons) for (h in p$horizons) {
    a <- selections[selections$outer_season == o & selections$horizon == h & selections$requested_n_option == "OFF", , drop = FALSE]
    no <- nsel$selected_n_option[nsel$outer_season == o & nsel$horizon == h]
    b <- selections[selections$outer_season == o & selections$horizon == h & selections$requested_n_option == no, , drop = FALSE]
    for (arm in c("A", "B")) {
      s <- if (arm == "A") a else b
      final_cfg[[length(final_cfg) + 1L]] <- data.frame(
        outer_season = o, horizon = h, arm = arm,
        requested_n_option = if (arm == "A") "OFF" else no,
        effective_n_option = s$effective_n_option, spec_id = s$spec_id,
        fallback_to_alloff = s$fallback_to_alloff, boundary_status = s$boundary_status,
        stringsAsFactors = FALSE)
    }
  }
  final_cfg <- do.call(rbind, final_cfg)
  atomic_csv(final_cfg, file.path(inner_dir, "selected_config_by_outer_horizon.csv"))
  nh_write_json(list(gate = "gate4", status = "PASS", inner_selections_frozen = TRUE,
                     outer_scores_opened = FALSE, stage_a_score_rows = nrow(stage_a_scores),
                     stage_b_score_rows = nrow(stage_b_scores), total_inner_score_rows = nrow(all_scores),
                     completed = now_iso()), file.path(out, "gate4_report.json"))
  write_status("gate4", "PASS", list(inner_selections_frozen = TRUE, outer_scores_opened = FALSE))

  # Gate 5: sealed outer predictions first, then truth join/scoring.
  outer_manifest <- read.csv(file.path(out, "outer_ledger_manifest.csv"), stringsAsFactors = FALSE)
  pred_dir <- file.path(out, "outer", "sealed_predictions"); dir.create(pred_dir, recursive = TRUE, showWarnings = FALSE)
  pred_rows <- list()
  for (o in p$principal_seasons) {
    om <- outer_manifest[outer_manifest$outer_season == o, , drop = FALSE]
    obj <- checkpoint_value(as.character(om$file))
    cfg <- final_cfg[final_cfg$outer_season == o, , drop = FALSE]
    fitted <- new.env(parent = emptyenv())
    for (i in seq_len(nrow(cfg))) {
      c <- cfg[i, , drop = FALSE]
      fk <- paste(c$effective_n_option, c$spec_id, sep = "\r")
      if (!exists(fk, envir = fitted, inherits = FALSE)) {
        sp <- catalog[catalog$spec_id == c$spec_id, , drop = FALSE]
        fit <- nh_fit(obj$train, sp, c$effective_n_option, gamma = sp$gamma, protocol = p)
        assign(fk, fit, envir = fitted)
      }
      fit <- get(fk, envir = fitted, inherits = FALSE)
      ev <- obj$eval_features[obj$eval_features$horizon == c$horizon, , drop = FALSE]
      pr <- nh_predict(fit, ev)
      pred_rows[[length(pred_rows) + 1L]] <- data.frame(
        outer_season = o, row_season = ev$row_season, origin_weekF = ev$origin_weekF,
        horizon = ev$horizon, target_weekF = ev$target_weekF, arm = c$arm,
        requested_n_option = c$requested_n_option, effective_n_option = c$effective_n_option,
        spec_id = c$spec_id, m1_p = pr$m1_p, p_hat = pr$p_hat,
        correction_logit = pr$correction_logit, stringsAsFactors = FALSE)
    }
  }
  outer_pred <- do.call(rbind, pred_rows)
  if (any(c("y_target", "N_target") %in% names(outer_pred))) stop("Sealed outer prediction file contains truth columns.", call. = FALSE)
  atomic_rds(outer_pred, file.path(pred_dir, "outer_predictions_sealed.rds"))
  atomic_csv(outer_pred, file.path(pred_dir, "outer_predictions_sealed.csv"))
  writeLines(c("SEALED_OUTER_PREDICTIONS_COMPLETE", paste0("timestamp=", now_iso()),
               paste0("sha256=", nh_hash_file(file.path(pred_dir, "outer_predictions_sealed.csv")))),
             file.path(out, "outer", "SEALED_COMPLETE"))

  truth_rows <- lapply(seq_len(nrow(outer_manifest)), function(i) checkpoint_value(as.character(outer_manifest$file[i]))$truth)
  truth <- do.call(rbind, truth_rows)
  scored <- merge(outer_pred, truth, by = c("outer_season", "row_season", "origin_weekF", "horizon", "target_weekF"), all.x = TRUE, sort = FALSE)
  if (any(is.na(scored$target_scoreable))) stop("Outer truth/scoreability join incomplete.", call. = FALSE)
  scored$loss <- NA_real_; scored$abs_error <- NA_real_; scored$brier <- NA_real_
  si <- scored$target_scoreable %in% TRUE
  if (any(!is.finite(scored$y_target[si]) | !is.finite(scored$N_target[si]) | scored$N_target[si] <= 0)) stop("Scoreable outer truth is invalid.", call. = FALSE)
  scored$loss[si] <- nh_bernoulli_loss(scored$y_target[si], scored$N_target[si], scored$p_hat[si])
  scored$abs_error[si] <- abs(scored$p_hat[si] - scored$y_target[si] / scored$N_target[si])
  scored$brier[si] <- (scored$p_hat[si] - scored$y_target[si] / scored$N_target[si])^2
  scored_eval <- scored[si, , drop = FALSE]
  metrics <- do.call(rbind, lapply(split(scored_eval, interaction(scored_eval$outer_season, scored_eval$horizon, scored_eval$arm, drop = TRUE)), function(z) {
    data.frame(outer_season = z$outer_season[1], horizon = z$horizon[1], arm = z$arm[1],
               loss = mean(z$loss), mae = mean(z$abs_error), brier = mean(z$brier), rows = nrow(z), stringsAsFactors = FALSE)
  }))
  wideA <- metrics[metrics$arm == "A", c("outer_season", "horizon", "loss", "mae", "brier")]
  wideB <- metrics[metrics$arm == "B", c("outer_season", "horizon", "loss", "mae", "brier")]
  names(wideA)[3:5] <- paste0(c("loss", "mae", "brier"), "_A"); names(wideB)[3:5] <- paste0(c("loss", "mae", "brier"), "_B")
  delta <- merge(wideA, wideB, by = c("outer_season", "horizon"), sort = FALSE)
  delta$loss_delta_B_minus_A <- delta$loss_B - delta$loss_A
  delta$mae_delta_B_minus_A <- delta$mae_B - delta$mae_A
  delta$brier_delta_B_minus_A <- delta$brier_B - delta$brier_A
  outer_dir <- file.path(out, "outer"); atomic_csv(scored, file.path(outer_dir, "outer_predictions_scored.csv"))
  atomic_csv(metrics, file.path(outer_dir, "outer_per_season_metrics.csv")); atomic_csv(delta, file.path(outer_dir, "paired_outer_differences.csv"))
  sel_freq <- as.data.frame(table(nsel$horizon, nsel$selected_n_option), stringsAsFactors = FALSE)
  names(sel_freq) <- c("horizon", "n_option", "count"); atomic_csv(sel_freq, file.path(outer_dir, "selection_frequency.csv"))

  summary_lines <- c(
    "# Full strict nested LOSO terminal summary", "",
    paste0("Run: `", RUN_ID, "`"), paste0("Route: `", p$route, "`"),
    "Production eligible: FALSE", "",
    paste0("Outer folds: ", length(p$principal_seasons)),
    paste0("Stage-A initial candidate fits planned under symmetry: ", 55L * nrow(stage_a_catalog) * length(p$n_options)),
    paste0("N selections h1: ", paste(names(table(nsel$selected_n_option[nsel$horizon == 1])), table(nsel$selected_n_option[nsel$horizon == 1]), collapse = ", ")),
    paste0("N selections h2: ", paste(names(table(nsel$selected_n_option[nsel$horizon == 2])), table(nsel$selected_n_option[nsel$horizon == 2]), collapse = ", ")),
    "", "Paired outer B-A deltas are in `outer/paired_outer_differences.csv`.",
    "This is research evidence only; canonical v3 and deployment routing are unchanged."
  )
  writeLines(summary_lines, file.path(out, "summary.md"))
  assert_protection()
  final_files <- list.files(out, recursive = TRUE, full.names = TRUE)
  final_files <- final_files[file.info(final_files)$isdir %in% FALSE]
  sha <- data.frame(path = sub(paste0("^", normalizePath(out), "/?"), "", normalizePath(final_files)),
                    sha256 = vapply(final_files, nh_hash_file, character(1)), stringsAsFactors = FALSE)
  atomic_csv(sha, file.path(out, "sha256sums.csv"))
  writeLines(c("COMPLETE", paste0("timestamp=", now_iso()), paste0("run_id=", RUN_ID)), file.path(out, "COMPLETE"))
  nh_write_json(list(gate = "gate5", status = "PASS", outer_predictions_sealed_before_scoring = TRUE,
                     production_eligible = FALSE, completed = now_iso()), file.path(out, "gate5_report.json"))
  write_status("gate5", "PASS", list(complete = TRUE))
  invisible(TRUE)
}

score_cache_self_test <- function() {
  req <- data.frame(
    pair_key = rep("S1__S2", 2L), n_option = rep("EXP050", 2L),
    spec_id = c("spec_a", "spec_b"), stringsAsFactors = FALSE
  )
  row <- function(spec, h = 1L) data.frame(
    validation_season = "S2", horizon = as.integer(h), spec_id = spec,
    n_option = "EXP050", status = "ok", ordinary_loss = 0.1, n_loss = 0.1,
    mae = 0.01, brier = 0.001, rows = 1L, forecast_rows = 1L,
    ordinary_weight_sum = 1, row_hash = "row", weight_hash = "weight", fit_error = "",
    pair_key = "S1__S2", season_a = "S1", season_b = "S2", stringsAsFactors = FALSE
  )
  good <- rbind(row("spec_a"), row("spec_b"))
  validate_score_group(good, req, "S1__S2", "EXP050", "self-test-good")

  expect_fail <- function(value, pattern) {
    e <- tryCatch({
      validate_score_group(value, req, "S1__S2", "EXP050", "self-test-bad")
      NULL
    }, error = function(e) e)
    if (is.null(e) || !grepl(pattern, conditionMessage(e), fixed = TRUE)) {
      stop("Score-cache self-test did not fail as expected: ", pattern, call. = FALSE)
    }
  }
  expect_fail(good[good$spec_id == "spec_a", , drop = FALSE], "spec coverage mismatch")
  extra <- rbind(good, transform(row("spec_c"), spec_id = "spec_c"))
  expect_fail(extra, "spec coverage mismatch")
  dup <- rbind(good, good[good$spec_id == "spec_a", , drop = FALSE])
  expect_fail(dup, "duplicate validation/horizon/spec rows")
  bad_pair <- good; bad_pair$pair_key[[1L]] <- "S1__S3"
  expect_fail(bad_pair, "pair_key mismatch")
  bad_schema <- good[, setdiff(names(good), "ordinary_loss"), drop = FALSE]
  expect_fail(bad_schema, "missing required columns")

  # A cache can contain every requested spec ID yet still be truncated for one
  # spec. This must fail at the cache boundary, before Stage-A assembly.
  good2 <- rbind(
    row("spec_a", 1L), row("spec_a", 2L),
    row("spec_b", 1L), row("spec_b", 2L)
  )
  validate_score_group(good2, req, "S1__S2", "EXP050", "self-test-rectangular-good")
  truncated <- good2[-which(good2$spec_id == "spec_b" & good2$horizon == 2L), , drop = FALSE]
  expect_fail(truncated, "non-rectangular validation/horizon coverage")

  req2 <- rbind(req, transform(req, pair_key = "S1__S3"))
  layer_good <- rbind(good2, transform(good2, pair_key = "S1__S3", season_b = "S3"))
  validate_score_layer_assembly(layer_good, req2, "self-test-layer-good")
  layer_dup <- rbind(layer_good, layer_good[1L, , drop = FALSE])
  e_layer <- tryCatch({ validate_score_layer_assembly(layer_dup, req2, "self-test-layer-dup"); NULL }, error = function(e) e)
  if (is.null(e_layer) || !grepl("duplicate pair/N/spec/validation/horizon rows", conditionMessage(e_layer), fixed = TRUE)) {
    stop("Score-cache self-test did not reject duplicate assembled rows.", call. = FALSE)
  }

  pe <- tryCatch({
    parallel_map(1:2, function(i) { if (i == 2L) stop("forced_parallel_failure", call. = FALSE); i }, n = 2L)
    NULL
  }, error = function(e) e)
  if (is.null(pe) || !grepl("Parallel worker failure", conditionMessage(pe), fixed = TRUE) ||
      !grepl("forced_parallel_failure", conditionMessage(pe), fixed = TRUE)) {
    stop("Score-cache self-test did not fail closed on a parallel worker error.", call. = FALSE)
  }
  cat("Score-cache self-test PASS\n")
  invisible(TRUE)
}

selection_self_test <- function() {
  outer <- p$principal_seasons[[1L]]
  vals <- setdiff(p$principal_seasons, outer)
  mk_spec <- function(intercept) normalize_spec(data.frame(
    intercept=intercept,k_z=0L,k_u=0L,k_d=0L,k_tau=0L,conf_scale="none",
    alpha_state=p$ordinary_grid$alpha_state,gamma=p$ordinary_grid$gamma,stringsAsFactors=FALSE))
  base_spec <- mk_spec(FALSE); cand_spec <- mk_spec(TRUE)
  catalog <- unique(rbind(base_spec,cand_spec)); baseline_id <- base_spec$spec_id[[1L]]
  make_scores <- function(spec, n_option, failed=FALSE) {
    do.call(rbind,lapply(vals,function(v){
      pk <- pair_key(c(outer,v)); pr <- strsplit(pk,"__",fixed=TRUE)[[1L]]
      peak <- timing$peak_weekF[match(v,timing$season)]; target <- as.integer(max(14,ceiling(peak)+4L))
      rr <- data.frame(row_season=v,origin_weekF=target-1L,horizon=1L,target_weekF=target,
                       target_scoreable=TRUE,y_target=10,N_target=100,stringsAsFactors=FALSE)
      z <- score_predictions(rr, if(failed) NULL else 0.10, spec$spec_id[[1L]], n_option, if(failed) "forced_self_test_failure" else "")
      z$pair_key <- pk; z$season_a <- pr[[1L]]; z$season_b <- pr[[2L]]; z
    }))
  }
  base <- make_scores(base_spec,"OFF",FALSE); cand <- make_scores(cand_spec,"EXP050",FALSE)
  cmap <- data.frame(outer_season=outer,n_option="EXP050",horizon=0L,spec_id=cand_spec$spec_id[[1L]],stage="self_test",stringsAsFactors=FALSE)
  sel <- select_ordinary(rbind(base,cand),cmap,catalog,outer,"EXP050",1L,baseline_id)
  if(nrow(sel)!=1L || isTRUE(sel$fallback_to_alloff) || sel$effective_n_option!="EXP050") stop("Selection self-test did not retain valid candidate.",call.=FALSE)
  failed <- make_scores(cand_spec,"EXP050",TRUE)
  e <- tryCatch({select_ordinary(rbind(base,failed),cmap,catalog,outer,"EXP050",1L,baseline_id);NULL},error=function(e)e)
  if(is.null(e) || !grepl("No complete candidate fits",conditionMessage(e),fixed=TRUE)) stop("Selection self-test did not fail closed on all-failed candidates.",call.=FALSE)
  cat("Selection self-test PASS\n")
  invisible(TRUE)
}

# ---------------- entrypoint ----------------

if (mode == "self-test-selection") {
  selection_self_test()
  quit(save = "no", status = 0L, runLast = FALSE)
}
if (mode == "self-test-score-cache") {
  score_cache_self_test()
  quit(save = "no", status = 0L, runLast = FALSE)
}

assert_pre_gates()
if (mode == "status") {
  cat(jsonlite::toJSON(read_json(file.path(out, "smoke_manifest.json")), auto_unbox = TRUE, pretty = TRUE), "\n")
  if (file.exists(file.path(out, "run_status.json"))) cat(readLines(file.path(out, "run_status.json")), sep = "\n")
} else if (mode == "dry-run") {
  sets <- all_exclusion_sets(); contexts <- all_contexts(sets)
  plan <- list(
    status = "READY_FOR_GATE3", run_id = RUN_ID, workers = workers,
    exclusion_sets = length(sets), replay_contexts = nrow(contexts), unordered_pairs = choose(length(p$principal_seasons), 2),
    stage_a_specs = nrow(nh_grid_stage_a(p)), n_options = length(p$n_options),
    stage_a_initial_fits_with_pair_symmetry = choose(length(p$principal_seasons), 2) * nrow(nh_grid_stage_a(p)) * length(p$n_options),
    stage_b_max_extra_fits_without_dedup = length(p$principal_seasons) * (length(p$principal_seasons) - 1L) * 14L * length(p$n_options),
    canonical_protection_sha256 = nh_hash_object(protect_before), source_hash = source_hash, protocol_hash = protocol_hash,
    full_requires = "PAGE_FULL_LOSO=YES"
  )
  nh_write_json(plan, file.path(out, "bcc_dry_run.json")); print(plan)
} else if (mode == "gate3") {
  build_gate3()
} else if (mode == "full") {
  run_full()
} else {
  stop("Unknown --mode. Use dry-run, status, gate3, full, self-test-selection, or self-test-score-cache.", call. = FALSE)
}
