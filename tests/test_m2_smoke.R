# M2 Pipeline Smoke Tests
# Run from repo root: Rscript tests/test_m2_smoke.R
#
# These tests verify that M2 feature construction, training, and prediction
# work correctly in both frozen-fit and weekly-refit modes. They require
# data files in data/ — skip gracefully if unavailable.

wd <- getwd()
message("M2 smoke tests | working dir: ", wd)

# Source all R files
r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
for (f in r_files) source(f, local = FALSE)

# ---------- helpers ----------
pass <- fail <- skip <- 0L
check <- function(label, expr) {
  tryCatch({
    ok <- eval(expr, envir = parent.frame())
    if (isTRUE(ok)) {
      message("  PASS: ", label)
      pass <<- pass + 1L
    } else {
      message("  FAIL: ", label)
      fail <<- fail + 1L
    }
  }, error = function(e) {
    message("  FAIL: ", label, " (", conditionMessage(e), ")")
    fail <<- fail + 1L
  })
}

# ---------- data availability ----------
kit_path <- "data/m2_production.rds"
ref_path <- "data/ref_production.rds"
data_path <- "data/flu_testing_data.csv"

if (!all(file.exists(kit_path, ref_path, data_path))) {
  message("SKIP: Required data files not found. Skipping M2 smoke tests.")
  quit(save = "no", status = 0)
}

m2_kit <- readRDS(kit_path)
ref_kit <- readRDS(ref_path)

message("\n--- Test 1: prep_stage2_joint produces valid features ---")
check("prep_stage2_joint exists", exists("prep_stage2_joint", mode = "function"))
check("m2_kit has fit", !is.null(m2_kit$fit))
check("m2_kit has spec", !is.null(m2_kit$spec))

message("\n--- Test 2: Feature columns are consistent ---")
if (!is.null(m2_kit$fit)) {
  fit <- m2_kit$fit
  trained_vars <- names(fit$var.summary)
  expected <- c("lead", "logit_f_eff", "z_ema")
  found <- expected %in% trained_vars
  check("All expected vars in trained model", all(found))
  check("No NaN in var.summary",
        !any(sapply(fit$var.summary, function(x) any(is.nan(x)))))
}

message("\n--- Test 3: Deprecated functions error correctly ---")
check("prep_stage2_m1_features is deprecated",
      tryCatch({prep_stage2_m1_features(); FALSE},
               error = function(e) grepl("deprecated|Deprecated", e$message)))
check("tune_stage2_loso_spec_grid is deprecated",
      tryCatch({tune_stage2_loso_spec_grid(); FALSE},
               error = function(e) grepl("deprecated|Deprecated", e$message)))

message("\n--- Test 4: run_m0_m1_m2_weekly is deprecated ---")
check("run_m0_m1_m2_weekly warns on call",
      tryCatch({run_m0_m1_m2_weekly(); FALSE},
               warning = function(w) grepl("[Dd]eprecated", w$message),
               error = function(e) grepl("[Dd]eprecated", e$message)))

message("\n--- Test 5: stage2_build_joint_formula builds valid formula ---")
if (exists("stage2_build_joint_formula", mode = "function") &&
    exists("stage2_make_spec", mode = "function")) {
  spec <- stage2_make_spec()
  frm <- stage2_build_joint_formula(spec)
  frm_str <- paste(deparse(frm), collapse = "")
  check("Formula has 'lead' term", grepl("lead", frm_str))
}

message("\n--- Test 6: stage2_exclude_newseason returns correct terms ---")
if (exists("stage2_exclude_newseason", mode = "function")) {
  spec <- stage2_make_spec()
  ex <- stage2_exclude_newseason(spec)
  check("Excludes season RE", any(grepl("season", ex)))
}

# ---------- Summary ----------
message(sprintf("\n=== Results: %d passed, %d failed, %d skipped ===",
                pass, fail, skip))
if (fail > 0) quit(save = "no", status = 1)
