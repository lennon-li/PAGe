# scripts/get_current_data.R
# Fetches the current-season Influenza A lab-testing data from
# Public Health Ontario and prints a summary to the console.
#
# Usage:
#   Rscript scripts/get_current_data.R
#   Rscript scripts/get_current_data.R --out=results --virus="Influenza A"
#   Rscript scripts/get_current_data.R --out=results --virus="Influenza B"

args <- commandArgs(trailingOnly = TRUE)
get_kv <- function(prefix, default = NULL) {
  hit <- grep(paste0("^", prefix, "="), args, value = TRUE)
  if (length(hit) == 0L) return(default)
  sub(paste0("^", prefix, "="), "", hit[[1L]])
}

out_dir  <- get_kv("--out",   "results")
virus    <- get_kv("--virus", "Influenza A")

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("\n=== get_current_data.R ===\n")
cat("virus:  ", virus,   "\n")
cat("out:    ", out_dir, "\n\n")

# ---- load required packages ----
for (pkg in c("dplyr", "MMWRweek", "lubridate")) {
  if (!requireNamespace(pkg, quietly = TRUE))
    stop("Required package not installed: ", pkg)
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

# ---- source getCurrentD from the project R/ directory ----
r_file <- file.path("R", "getCurrentD.R")
if (!file.exists(r_file)) stop("Cannot find R/getCurrentD.R")
source(r_file, local = FALSE)

# ---- call getCurrentD() ----
cat("Calling getCurrentD(virus = \"", virus, "\") ...\n", sep = "")
currentD <- tryCatch(
  getCurrentD(virus = virus),
  error = function(e) {
    cat("ERROR fetching data:\n  ", conditionMessage(e), "\n")
    quit(save = "no", status = 1)
  }
)

# ---- show results ----
cat("\n--- Data summary ---\n")
cat("Rows:    ", nrow(currentD), "\n")
cat("Columns: ", paste(names(currentD), collapse = ", "), "\n")
cat("Seasons: ", paste(sort(unique(currentD$season)), collapse = ", "), "\n")
cat("Weeks:   ", min(currentD$week, na.rm = TRUE), "to",
    max(currentD$week, na.rm = TRUE), "\n")
cat("Date range: ", format(min(currentD$date, na.rm = TRUE)),
    "to", format(max(currentD$date, na.rm = TRUE)), "\n\n")

cat("--- Full data ---\n")
print(as.data.frame(currentD), digits = 4)

# ---- save ----
out_csv <- file.path(out_dir, "current_data.csv")
write.csv(currentD, out_csv, row.names = FALSE)
cat("\nSaved: ", out_csv, "\n")
cat("DONE\n")
