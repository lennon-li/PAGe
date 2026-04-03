#' Score an ignition-threshold grid on historical seasons
#'
#' Calibrates (in-sample) ignition thresholds by scoring each row of a parameter
#' grid against historical ignition weeks (`iWeek`) across all seasons in
#' `alignedD_prosp`.
#'
#' For each parameter row, this function loops over seasons and calls
#' [detectIgnition4()] to get an estimated ignition week. The loss is:
#' \deqn{\frac{1}{S}\sum_{s=1}^S \left[ I(\hat{iWeek}_s=\mathrm{NA})\cdot \mathrm{penalty} +
#' (1-I)\cdot |\hat{iWeek}_s - iWeek_s| \right]}
#' where `penalty` is applied if ignition is not detected.
#'
#' Parallel execution is Windows-safe using a PSOCK cluster via `parallel`.
#'
#' @param grid A `data.frame` containing one row per parameter setting. Must
#'   contain the columns: `cls_thr`, `p0_thr`, `p_thr`, `d1_thr`, `p_thr2`,
#'   `d1_thr2` (these are passed to [detectIgnition4()] as a list).
#' @param alignedD_prosp Historical dataset containing all seasons. Must include
#'   columns `season` and `iWeek`, plus whatever [detectIgnition4()] needs
#'   (e.g., `weekF`, `p`, `y`, `N`, `d1_link`, `d2_link`).
#' @param models_all Output from [fitIgnitionModels4()] fit ONCE on the full
#'   historical dataset.
#' @param penalty Numeric penalty added when ignition is not detected for a season.
#'   Default is `99`.
#' @param parallel Logical; if `TRUE`, use PSOCK parallelism to score rows of
#'   `grid`. Default `TRUE`.
#' @param ncores Integer number of worker processes to use when `parallel=TRUE`.
#'   Default is `detectCores()-1`.
#' @param chunked Logical; if `TRUE`, split work into `ncores` chunks to reduce
#'   per-task overhead. Default `TRUE`.
#' @param verbose Logical; print progress messages. Default `TRUE`.
#'
#' @return A numeric vector of length `nrow(grid)` giving the mean loss for each
#'   row of `grid`, in the same order as `grid`.
#'
#' @examples
#' \dontrun{
#' # 1) Fit models once on all historical data
#' models_all <- fitIgnitionModels4(alignedD_prosp, verbose = TRUE)
#'
#' # 2) Build a parameter grid to calibrate thresholds
#' grid <- expand.grid(
#'   cls_thr = seq(0.60, 0.85, by = 0.05),
#'   p0_thr  = seq(0.010, 0.040, by = 0.010),
#'   p_thr   = seq(0.010, 0.030, by = 0.005),
#'   d1_thr  = seq(0.001, 0.005, by = 0.001),
#'   p_thr2  = seq(0.005, 0.020, by = 0.005),
#'   d1_thr2 = seq(0.0005, 0.0030, by = 0.0005),
#'   KEEP.OUT.ATTRS = FALSE,
#'   stringsAsFactors = FALSE
#' )
#'
#' # 3) Score the grid (parallel on Windows-safe PSOCK)
#' grid$mean_loss <- score_params(
#'   grid = grid,
#'   alignedD_prosp = alignedD_prosp,
#'   models_all = models_all,
#'   penalty = 99,
#'   parallel = TRUE,
#'   ncores = 4,
#'   chunked = TRUE,
#'   verbose = TRUE
#' )
#'
#' # 4) Pick best parameters
#' best <- grid[which.min(grid$mean_loss), ]
#' params_hat <- as.list(best)
#' }
#'
#' @export
score_params <- function(
    grid,
    alignedD_prosp,
    models_all,
    penalty = 99,
    parallel = TRUE,
    ncores = max(1L, parallel::detectCores() - 1L),
    chunked = TRUE,
    verbose = TRUE
) {
  stopifnot(is.data.frame(grid), is.data.frame(alignedD_prosp))
  if (!all(c("season", "iWeek") %in% names(alignedD_prosp))) {
    stop("alignedD_prosp must have columns: season, iWeek")
  }
  
  seasons <- unique(alignedD_prosp$season)
  
  # single-row scorer (runs on workers)
  score_one_row <- function(row) {
    params <- as.list(row)
    err <- 0
    
    for (s in seasons) {
      print(paste0("Scoring season ", s, " with params: ", paste(names(params), params, collapse = ", ")))
      df_s <- alignedD_prosp[alignedD_prosp$season == s, ]
      iw_true <- unique(df_s$iWeek)[1]
      
      res <- detectIgnition4(
        df_one_season = df_s,
        models = models_all,
        params = params,
        verbose = FALSE
      )
      
      err <- err + if (is.na(res$iWeek_hat)) penalty else abs(res$iWeek_hat - iw_true)
    }
    
    err / length(seasons)
  }
  
  # serial
  if (!parallel || nrow(grid) == 0L || ncores <= 1L) {
    if (verbose) message("[score_params] scoring grid serially: n=", nrow(grid))
    return(as.numeric(apply(grid, 1, score_one_row)))
  }
  
  # Windows-safe parallel (PSOCK)
  if (verbose) message("[score_params] scoring grid in parallel (PSOCK): n=", nrow(grid),
                       " cores=", ncores, " chunked=", chunked)
  
  cl <- parallel::makeCluster(ncores)
  on.exit(parallel::stopCluster(cl), add = TRUE)
  
  parallel::clusterExport(
    cl,
    varlist = c("grid", "alignedD_prosp", "models_all", "detectIgnition4",
                "penalty", "seasons", "score_one_row"),
    envir = environment()
  )
  
  idx <- seq_len(nrow(grid))
  
  if (!chunked) {
    out <- parallel::parLapply(cl, idx, function(i) score_one_row(grid[i, ]))
    return(as.numeric(unlist(out)))
  }
  
  chunks <- split(idx, rep_len(seq_len(ncores), length(idx)))
  res <- parallel::parLapply(cl, chunks, function(ii) {
    vapply(ii, function(i) score_one_row(grid[i, ]), numeric(1))
  })
  
  as.numeric(unlist(res))
}
