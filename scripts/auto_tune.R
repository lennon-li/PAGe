# scripts/auto_from_rdata.R
# Usage (PowerShell):
#   Rscript scripts/auto_from_rdata.R --rdata=data/inputs.RData --out=results --task=run_pipeline

args <- commandArgs(trailingOnly = TRUE)

get_kv <- function(prefix, default = NULL) {
  hit <- grep(paste0("^", prefix, "="), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0("^", prefix, "="), "", hit[[1]])
}
has_flag <- function(flag) any(tolower(args) == tolower(flag))

rdata_path <- get_kv("--rdata", "data/data.RData")
out_dir    <- get_kv("--out",   "results")
task_name  <- get_kv("--task",  "run_pipeline")
source_r   <- !has_flag("--no-source-r")
verbose    <- has_flag("--verbose")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("\n=== auto_from_rdata.R ===\n")
cat("rdata: ", rdata_path, "\n")
cat("out:   ", out_dir, "\n")
cat("task:  ", task_name, "\n")
cat("source R/: ", source_r, "\n\n", sep = "")

# --- 1) load .RData into a dedicated environment (avoid polluting global env) ---
if (!file.exists(rdata_path)) stop("RData file not found: ", rdata_path)

inputs <- new.env(parent = emptyenv())
loaded_names <- load(rdata_path, envir = inputs)

cat("Loaded objects (", length(loaded_names), "):\n  - ",
    paste(loaded_names, collapse = "\n  - "), "\n\n", sep = "")

# --- 2) source all functions under R/ (optional but recommended) ---
if (source_r) {
  if (!dir.exists("R")) stop("Folder 'R/' not found in project root.")
  
  r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE, recursive = TRUE)
  if (length(r_files) == 0) stop("No .R files found under R/")
  
  base <- basename(r_files)
  ord <- order(!grepl("^00_", base), base)
  r_files <- r_files[ord]
  
  cat("Sourcing ", length(r_files), " R files...\n", sep = "")
  for (f in r_files) {
    if (verbose) cat("  - ", f, "\n", sep = "")
    tryCatch(source(f, local = FALSE),
             error = function(e) stop("Error sourcing ", f, ":\n", e$message))
  }
  cat("Sourced all R/ files successfully.\n\n")
}

# --- 3) run entrypoint using inputs env ---
# Convention: entrypoint signature: function(inputs, out_dir, ...)
if (!exists(task_name, mode = "function")) {
  # Helpful suggestions
  all_funs <- ls(envir = .GlobalEnv)
  candidates <- grep("(^run_|^produce_|^prep_|^make_|^build_|^train_|^tune_)", all_funs, value = TRUE)
  stop(
    "Task function not found: ", task_name, "\n\n",
    "Define it in R/*.R (or load it via your RData).\n",
    "Candidate functions in session:\n  - ",
    paste(head(candidates, 30), collapse = "\n  - ")
  )
}

cat("Running task: ", task_name, "(inputs, out_dir)\n", sep = "")
task_fun <- get(task_name, mode = "function")

res <- task_fun(inputs = inputs, out_dir = out_dir)

saveRDS(
  list(
    task = task_name,
    rdata_path = rdata_path,
    out_dir = out_dir,
    loaded_objects = loaded_names,
    result_class = class(res),
    time = Sys.time()
  ),
  file.path(out_dir, "run_meta.rds")
)

cat("\n=== DONE ===\n")
if (!is.null(res)) cat("Returned: ", paste(class(res), collapse = ", "), "\n", sep = "")