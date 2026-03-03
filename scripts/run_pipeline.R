run_pipeline <- function(inputs, out_dir) {
  # Access objects from the RData like this:
  # inputs$alignedD, inputs$det_out, inputs$params_grid, etc.
  
  # Example: enforce required objects
  needed <- c("alignedD")   # edit to your real required objects
  miss <- needed[!vapply(needed, exists, logical(1), envir = inputs)]
  if (length(miss) > 0) stop("Missing in inputs (.RData): ", paste(miss, collapse = ", "))
  
  alignedD <- get("alignedD", envir = inputs)
  
  # ... call your existing functions (already sourced from R/)
  # out <- tune_stage2_loso_shift_template(dat = alignedD, ...)
  
  # Save artifacts
  saveRDS(alignedD, file.path(out_dir, "alignedD.rds"))
  
  list(status = "ok", saved = c("alignedD.rds"))
}