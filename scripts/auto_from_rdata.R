# scripts/auto_from_rdata.R
# Usage (PowerShell):
#   Rscript .\scripts\auto_from_rdata.R --rdata=.\data\inputs.RData --out=.\results --mode=summary --verbose
#   Rscript .\scripts\auto_from_rdata.R --rdata=.\data\inputs.RData --out=.\results --mode=all
#   Rscript .\scripts\auto_from_rdata.R --rdata=.\data\inputs.RData --out=.\results --mode=all --cores=10

args <- commandArgs(trailingOnly = TRUE)

get_kv <- function(prefix, default = NULL) {
  hit <- grep(paste0("^", prefix, "="), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0("^", prefix, "="), "", hit[[1]])
}
has_flag <- function(flag) any(tolower(args) == tolower(flag))

rdata_path <- get_kv("--rdata", "data/inputs.RData")
# Fallback: if the specified path doesn't exist, try data/data.RData
if (!file.exists(rdata_path) && file.exists("data/data.RData")) {
  cat("Note: '", rdata_path, "' not found; falling back to 'data/data.RData'\n", sep = "")
  rdata_path <- "data/data.RData"
}
out_dir    <- get_kv("--out",   "results")
mode       <- tolower(get_kv("--mode", "summary"))
cores_str  <- get_kv("--cores", NULL)
if (!is.null(cores_str) && grepl("^[1-9][0-9]*$", trimws(cores_str))) {
  ncores <- as.integer(cores_str)
} else {
  if (!is.null(cores_str))
    warning("--cores value '", cores_str, "' is not a positive integer; using detectCores().")
  ncores <- parallel::detectCores(logical = TRUE)
}
if (is.na(ncores) || ncores < 1L) {
  warning("Core detection failed; defaulting to 10 cores.")
  ncores <- 10L
}
verbose    <- has_flag("--verbose")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("\n=== auto_from_rdata.R ===\n")
cat("rdata: ", rdata_path, "\n")
cat("out:   ", out_dir, "\n")
cat("mode:  ", mode, "\n")
cat("cores: ", ncores, "\n\n")

# ---- load .RData into dedicated env ----
if (!file.exists(rdata_path)) stop("RData file not found: ", rdata_path)

inputs <- new.env(parent = emptyenv())
loaded <- load(rdata_path, envir = inputs)

cat("Loaded objects (", length(loaded), ")\n", sep = "")
if (verbose) cat("  - ", paste(loaded, collapse = "\n  - "), "\n\n", sep = "") else cat("  (use --verbose to print names)\n\n")

exists_in <- function(nm) exists(nm, envir = inputs, inherits = FALSE)
get_in    <- function(nm) get(nm, envir = inputs, inherits = FALSE)

# ---- summary mode ----
if (mode == "summary") {
  core <- c("alignedD", "template_df", "ref", "g_ref_fun", "g_ref_mu_se", "res", "outs", "ignD", "allD", "theD")
  funs <- c("alignIgnition", "fitIgnition", "detectIgnitionBySeason_M0v2", "run_ignition_weekly",
            "loso_M0v2", "tuneIgnitionGrid_M0v2", "tuneIgnitionGrid")
  
  cat("Core objects present:\n")
  for (nm in core) cat(sprintf("  %-35s %s\n", nm, if (exists_in(nm)) "YES" else "no"))
  
  cat("\nKey functions present:\n")
  for (nm in funs) cat(sprintf("  %-35s %s\n", nm, if (exists_in(nm)) "YES" else "no"))
  
  cat("\nDONE (summary)\n")
  quit(save = "no", status = 0)
}

# ---- helpers ----
save_out <- function(obj, name) {
  saveRDS(obj, file.path(out_dir, paste0(name, ".rds")))
  invisible(obj)
}
require_in <- function(nms) {
  miss <- nms[!vapply(nms, exists_in, logical(1))]
  if (length(miss) > 0) stop("Missing in .RData: ", paste(miss, collapse = ", "))
}

# ---- Mode: all ----
if (mode == "all") {

  require_in(c("alignedD", "fitIgnition", "detectIgnitionBySeason_M0v2",
               "loso_M0v2", "tuneIgnitionGrid_M0v2"))

  # Attach all functions from .RData to global env so internal cross-calls work.
  for (.nm in loaded) {
    .obj <- get_in(.nm)
    if (is.function(.obj)) assign(.nm, .obj, envir = .GlobalEnv)
  }

  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need package: data.table")
  library(data.table)

  alignedD <- get_in("alignedD")

  # ---- shared args (mirrors task.md exactly) ----
  fit_args <- list(
    fit_base  = TRUE,  fit_slope = FALSE, fit_fs = FALSE,
    event_k   = 1L,   lead      = 1L,
    A_pre     = 6L,   B_post    = 6L,
    k_week    = 6L,   k_p       = 8L,   k_fs = 4L,
    select    = FALSE, verbose   = FALSE
  )

  tune_args <- list(
    miss_penalty   = 20,
    lambda         = 20,
    kappa          = 2,
    gamma          = 25,
    gamma_late     = 25,
    iWeek          = TRUE,
    ncores         = ncores,
    verbose        = FALSE,
    progress_every = 200L
  )

  param_cols <- c("cls_thr","p_thr","prev_thr","n_consec","L","eps",
                  "K_sum","p_sum_thr","N_req","w_min","w_max")

  # ---- build starting grid ----
  grid_loso <- data.table::CJ(
    cls_thr   = c(0.20, 0.22, 0.24, 0.26, 0.28),
    p_thr     = c(0.008, 0.009, 0.010),
    prev_thr  = c(0.005, 0.006, 0.007),
    n_consec  = c(4L, 5L, 6L),
    L         = 2L,
    eps       = 0,
    K_sum     = c(4L, 5L, 6L),
    p_sum_thr = c(0.045, 0.050, 0.055, 0.060),
    N_req     = 4L,
    w_min     = 13L,
    w_max     = 30L,
    sorted    = FALSE
  )
  cat("Starting grid size:", nrow(grid_loso), "\n")

  # ---- helper: build leaderboard for a grid ----
  # Runs tuneIgnitionGrid_M0v2 twice:
  #   1. exSeason="2015-16" -> loso_score (Q_tune, no 2015-16 in eval)
  #   2. exSeason=NULL      -> Q_all max/mean abs diff
  build_leaderboard <- function(grid_df, fit_all) {
    cat("  [leaderboard] Q_tune pass (excl 2015-16)...\n")
    tune_res <- do.call(tuneIgnitionGrid_M0v2, c(
      list(ign_fit   = fit_all,
           grid      = grid_df,
           score_col = "p_cls_p",
           exSeason  = "2015-16"),
      tune_args
    ))

    cat("  [leaderboard] Q_all pass (all seasons)...\n")
    all_res <- do.call(tuneIgnitionGrid_M0v2, c(
      list(ign_fit   = fit_all,
           grid      = grid_df,
           score_col = "p_cls_p",
           exSeason  = NULL),
      tune_args
    ))

    lb <- tune_res$results[, param_cols, drop = FALSE]
    lb$loso_score        <- tune_res$results$score
    lb$max_abs_diff_all  <- all_res$results$max_abs
    lb$mean_abs_diff_all <- all_res$results$mean_abs
    lb
  }

  # ---- step 1: LOSO tuning ----
  cat("\n--- Step 1: LOSO tuning (Q_tune, drop 2015-16) ---\n")
  tuned <- loso_M0v2(
    dat           = alignedD,
    grid          = as.data.frame(grid_loso),
    score_col     = "p_cls_p",
    drop_seasons  = c("2015-16"),
    exSeason_tune = NULL,
    fit_args      = fit_args,
    tune_args     = tune_args,
    verbose       = TRUE
  )
  cat("LOSO best params:\n")
  print(unlist(tuned$best_params))

  # ---- step 2: fit ignition on ALL seasons ----
  cat("\n--- Step 2: fitIgnition on ALL seasons ---\n")
  ign_fit_all <- fitIgnition(
    dat       = alignedD,
    fit_base  = TRUE,  fit_slope = FALSE, fit_fs = FALSE,
    event_k   = 1L,   lead      = 1L,
    A_pre     = 6L,   B_post    = 6L,
    k_week    = 6L,   k_p       = 8L,
    verbose   = TRUE
  )

  # ---- step 3: build leaderboard for starting grid ----
  cat("\n--- Step 3: building leaderboard ---\n")
  leaderboard <- build_leaderboard(as.data.frame(grid_loso), ign_fit_all)

  # ---- step 4: iterative grid expansion if constraint not met ----
  MAX_EXPAND   <- 2L
  expand_round <- 0L

  best_max <- min(leaderboard$max_abs_diff_all, na.rm = TRUE)
  constraint_satisfied <- isTRUE(best_max <= 2)

  while (!constraint_satisfied && expand_round < MAX_EXPAND) {
    expand_round <- expand_round + 1L
    cat("\n--- Expand round", expand_round,
        ": best max_abs_diff_all =", best_max, "---\n")

    # Top-5 rows as expansion seeds
    top5 <- leaderboard[order(leaderboard$max_abs_diff_all,
                              leaderboard$mean_abs_diff_all), ][
                          seq_len(min(5L, nrow(leaderboard))), ]

    nudge <- function(x, step, lo, hi) {
      vals <- sort(unique(c(x - step, x, x + step)))
      vals[vals >= lo & vals <= hi]
    }
    nudge_i <- function(x, step, lo, hi) {
      as.integer(unique(c(x - step, x, x + step)[
        c(x - step, x, x + step) >= lo & c(x - step, x, x + step) <= hi]))
    }

    cls_v  <- sort(unique(unlist(lapply(top5$cls_thr,   nudge,   0.01,  0.10, 0.50))))
    p_v    <- sort(unique(unlist(lapply(top5$p_thr,     nudge,   0.001, 0.001, 0.050))))
    pr_v   <- sort(unique(unlist(lapply(top5$prev_thr,  nudge,   0.001, 0.001, 0.050))))
    nc_v   <- sort(unique(unlist(lapply(top5$n_consec,  nudge_i, 1L,    2L,   12L))))
    ks_v   <- sort(unique(unlist(lapply(top5$K_sum,     nudge_i, 1L,    2L,   10L))))
    ps_v   <- sort(unique(unlist(lapply(top5$p_sum_thr, nudge,   0.005, 0.010, 0.150))))

    grid_exp <- data.table::CJ(
      cls_thr   = cls_v,
      p_thr     = p_v,
      prev_thr  = pr_v,
      n_consec  = nc_v,
      L         = 2L,
      eps       = 0,
      K_sum     = ks_v,
      p_sum_thr = ps_v,
      N_req     = 4L,
      w_min     = 13L,
      w_max     = 30L,
      sorted    = FALSE
    )
    cat("Expanded grid size:", nrow(grid_exp), "\n")

    lb_exp <- build_leaderboard(as.data.frame(grid_exp), ign_fit_all)

    # merge & deduplicate
    leaderboard <- rbind(leaderboard, lb_exp)
    leaderboard <- leaderboard[!duplicated(leaderboard[, param_cols]), ]

    best_max <- min(leaderboard$max_abs_diff_all, na.rm = TRUE)
    constraint_satisfied <- isTRUE(best_max <= 2)
  }

  if (!constraint_satisfied) {
    cat("\nWARNING: constraint max_abs_diff_all <= 2 not satisfied.",
        "Returning best achievable (max_abs_diff_all =", best_max, ").\n")
  }

  # ---- step 5: select best params ----
  if (constraint_satisfied) {
    cands <- leaderboard[
      !is.na(leaderboard$max_abs_diff_all) & leaderboard$max_abs_diff_all <= 2, ]
  } else {
    cands <- leaderboard
  }
  cands <- cands[order(cands$mean_abs_diff_all, cands$loso_score), ]
  best_row   <- cands[1L, ]
  best_params <- as.list(best_row[, param_cols, drop = FALSE])
  for (.nm in c("n_consec","L","K_sum","N_req","w_min","w_max"))
    best_params[[.nm]] <- as.integer(best_params[[.nm]])

  cat("\nSelected best params:\n")
  print(unlist(best_params))

  # ---- step 6: final detection on ALL seasons ----
  cat("\n--- Step 6: final detectIgnitionBySeason_M0v2 ---\n")
  det_final <- detectIgnitionBySeason_M0v2(
    ign_fit      = ign_fit_all,
    params       = best_params,
    score_col    = "p_cls_p",
    keep_signals = TRUE,
    iWeek        = TRUE,
    verbose      = TRUE
  )

  abs_diff_final    <- abs(det_final$compare$diff)
  max_abs_diff_all  <- max(abs_diff_final,  na.rm = TRUE)
  mean_abs_diff_all <- mean(abs_diff_final, na.rm = TRUE)

  cat("\ndet_all$compare:\n")
  print(det_final$compare)
  cat("max_abs_diff_all: ",  max_abs_diff_all,  "\n")
  cat("mean_abs_diff_all: ", mean_abs_diff_all, "\n")
  cat("Constraint satisfied (<=2):", isTRUE(max_abs_diff_all <= 2), "\n")

  # ---- step 7: save outputs ----
  leaderboard_out <- leaderboard[
    order(leaderboard$max_abs_diff_all,
          leaderboard$mean_abs_diff_all,
          leaderboard$loso_score), ]
  write.csv(leaderboard_out,
            file.path(out_dir, "leaderboard.csv"), row.names = FALSE)

  saveRDS(best_params, file.path(out_dir, "best_params.rds"))

  write.csv(det_final$compare,
            file.path(out_dir, "det_all_compare.csv"), row.names = FALSE)

  run_meta <- list(
    rdata_path          = rdata_path,
    out_dir             = out_dir,
    mode                = mode,
    time                = Sys.time(),
    grid_size_initial   = nrow(grid_loso),
    grid_size_final     = nrow(leaderboard),
    expand_rounds       = expand_round,
    constraint_satisfied = isTRUE(max_abs_diff_all <= 2),
    max_abs_diff_all    = max_abs_diff_all,
    mean_abs_diff_all   = mean_abs_diff_all,
    best_params         = best_params,
    n_seasons           = nrow(det_final$compare)
  )
  saveRDS(run_meta, file.path(out_dir, "run_meta.rds"))

  cat("\nSaved to", out_dir, ":\n")
  cat("  leaderboard.csv\n  best_params.rds\n  det_all_compare.csv\n  run_meta.rds\n")
  cat("DONE (all)\n")
  quit(save = "no", status = 0)
}

stop("Unknown --mode: ", mode, " (use summary or all)")