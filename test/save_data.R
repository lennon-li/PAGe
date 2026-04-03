# save_data.R
# Run this ONCE locally to extract the necessary objects from data/data.RData
# and save them as test/test.RData for transfer to the server.
#
# Usage (from project root):
#   Rscript test/save_data.R

setwd(dirname(dirname(normalizePath(sys.frame(0)$ofile, mustWork = FALSE))))
if (!file.exists("data/data.RData")) stop("data/data.RData not found. Run from project root.")

e <- new.env(parent = emptyenv())
load("data/data.RData", envir = e)

alignedD    <- e$alignedD
template_df <- e$template_df
ignD        <- e$ignD

cat("alignedD:    ", nrow(alignedD),    "rows x", ncol(alignedD),    "cols\n")
cat("template_df: ", nrow(template_df), "rows x", ncol(template_df), "cols\n")
cat("ignD:        ", nrow(ignD),        "rows x", ncol(ignD),        "cols\n")
cat("Seasons in alignedD:", paste(sort(unique(alignedD$season)), collapse = ", "), "\n")

save(alignedD, template_df, ignD, file = "test/test.RData")
cat("Saved: test/test.RData\n")
