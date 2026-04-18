# R Package Migration Utility 
# 
# Authored by Lennon Li and Gemini  (November 27, 2025)
# This utility, defined by the migrate_r_packages() function, automates the complex, 
#      two-step process of transferring user-installed packages between two major versions of R. 
# Preparation (Old R): The script first launches the older $\text{R}$ installation (user specified),
#      which identifies and saves a complete list of non-base packages to a temporary file, along with a count for user reference.
# Installation (New R): Immediately after, the script launches the current (new) $\text{R}$ installation. 
#      This session reads the package list and initiates the installation of all missing packages, automatically resolving dependencies and compiling necessary binaries.
# Error Handling and Cleanup: All operational output is redirected to a log file for diagnostics. 
#      Upon completion, the utility prints a success or failure status and automatically removes all temporary files to leave the system clean.

# --- 0. Dependency Check and Setup ---
# Check for tcltk (needed for the GUI directory selector)
if (!requireNamespace("tcltk", quietly = TRUE)) {
  cat("The 'tcltk' package is required for the GUI file browser.\n")
  if (interactive()) {
    response <- readline("Would you like to install 'tcltk' now? (y/n): ")
    if (tolower(response) == "y") {
      tryCatch({
        install.packages("tcltk", quiet = TRUE)
      }, error = function(e) {
        stop("Failed to install 'tcltk'. Please install it manually and rerun the function.", call. = FALSE)
      })
    } else {
      stop("tcltk not installed. Migration aborted.", call. = FALSE)
    }
  } else {
    stop("tcltk is required. Please install it manually and rerun the function.", call. = FALSE)
  }
}
library(tcltk)

#' Migrates user-installed R packages from an old R version to the current (new) R version.
#'
#' Orchestrates the complete two-step migration (save list from old R, then install in new R) 
#' sequentially in a single execution of a generated batch file. Includes error logging.
#'
#' @param old_r_home Optional string. The full path to the root folder of 
#'   the OLD R installation (e.g., "C:/Program Files/R/R-4.2.3"). If missing or 
#'   invalid, a GUI browser will open to select the path.
#' @return Invisible NULL. The function executes the migration externally.
migrate_r_packages <- function(old_r_home = NULL) {
  
  message("--- R Package Migration Utility: Starting Process ---")
  
  # --- 1. Define Paths and Configuration ---
  NEW_R_HOME <- R.home()
  TEMP_DIR <- tempdir()
  
  # File Names
  SAVE_SCRIPT_NAME <- "R_migration_save.R"
  INSTALL_SCRIPT_NAME <- "R_migration_install.R"
  PACKAGE_LIST_FILE <- "R_packages_list.RData"
  COUNT_FILE_NAME <- "R_packages_count.txt" 
  BATCH_FILE_NAME <- "R_Package_Migration_Exec.bat"
  ERROR_LOG_FILE <- "R_migration_error.log" # Dedicated error log
  
  # Full Paths
  BATCH_FILE_PATH <- file.path(TEMP_DIR, BATCH_FILE_NAME)
  SAVE_SCRIPT_PATH <- file.path(TEMP_DIR, SAVE_SCRIPT_NAME)
  INSTALL_SCRIPT_PATH <- file.path(TEMP_DIR, INSTALL_SCRIPT_NAME)
  PACKAGE_LIST_PATH <- file.path(TEMP_DIR, PACKAGE_LIST_FILE)
  COUNT_FILE_PATH <- file.path(TEMP_DIR, COUNT_FILE_NAME)
  ERROR_LOG_PATH <- file.path(TEMP_DIR, ERROR_LOG_FILE)
  
  # CRITICAL FIX: Normalize paths for embedding in R script content
  PACKAGE_LIST_PATH_SAFE <- gsub("\\\\", "/", PACKAGE_LIST_PATH)
  COUNT_FILE_PATH_SAFE <- gsub("\\\\", "/", COUNT_FILE_PATH)
  ERROR_LOG_PATH_SAFE <- gsub("\\\\", "/", ERROR_LOG_PATH)
  
  # Delete previous log file if it exists
  if (file.exists(ERROR_LOG_PATH)) file.remove(ERROR_LOG_PATH)
  
  # --- 2. Sanity Check and Path Acquisition ---
  
  is_valid_r_home <- function(path) {
    if (is.null(path) || !is.character(path) || length(path) != 1) return(FALSE)
    path <- gsub("\\\\", "/", path)
    return(file.exists(file.path(path, "bin", "Rscript.exe")))
  }
  
  if (is_valid_r_home(old_r_home)) {
    OLD_R_HOME <- gsub("\\\\", "/", old_r_home)
  } else {
    cat("1. Launching GUI File Browser (Please select your OLD R Home folder)...\n")
    
    OLD_R_HOME_RAW <- tk_choose.dir(default = "", caption = "Select the root folder of your OLD R installation")
    
    if (is.na(OLD_R_HOME_RAW) || is.null(OLD_R_HOME_RAW) || OLD_R_HOME_RAW == "") {
      message("Directory selection cancelled by user. Migration aborted.")
      return(invisible(NULL))
    }
    
    OLD_R_HOME <- gsub("\\\\", "/", OLD_R_HOME_RAW) 
    
    if (!is_valid_r_home(OLD_R_HOME)) {
      stop("ERROR: Could not find 'Rscript.exe' in the selected OLD R path. Migration aborted.", call. = FALSE)
    }
  }
  
  cat(paste("2. Selected OLD R HOME (Source):", OLD_R_HOME, "\n"))
  cat(paste("   Detected NEW R HOME (Target):", NEW_R_HOME, "\n"))
  
  
  # --- 3. Generate the R Script Content (Save List and Count) ---
  SAVE_SCRIPT_CONTENT <- c(
    "# --- R Script (Step 1: Save Package List and Count) ---",
    paste0("package_file <- \"", PACKAGE_LIST_PATH_SAFE, "\""), 
    paste0("count_file <- \"", COUNT_FILE_PATH_SAFE, "\""),
    "message('--- R Package Migrator: STEP 1 (Saving package list from old R) ---')",
    "packages_to_save <- setdiff(",
    "  installed.packages(priority = 'NA')[, 'Package'], ",
    "  installed.packages(priority = 'base')[, 'Package']",
    ")",
    "save(packages_to_save, file = package_file)",
    "package_count <- length(packages_to_save)",
    "writeLines(as.character(package_count), con = count_file)", 
    "message(paste('Package list saved to:', package_file))",
    "message(paste('Found', package_count, 'packages to save.'))"
  )
  writeLines(SAVE_SCRIPT_CONTENT, SAVE_SCRIPT_PATH)
  
  
  # --- 4. Generate the R Script Content (Install List & Cleanup) ---
  INSTALL_SCRIPT_CONTENT <- c(
    "# --- R Script (Step 2: Install Packages) ---",
    paste0("package_file <- \"", PACKAGE_LIST_PATH_SAFE, "\""), 
    "if (file.exists(package_file)) {",
    "  message('--- R Package Migrator: STEP 2 (Starting installation in new R) ---')",
    "  load(package_file)",
    "  # Setting the CRAN repository explicitly",
    "  options(repos = c(CRAN = 'https://cran.rstudio.com'))",
    "  # Install packages (using dependencies=TRUE is crucial)",
    "  install.packages(packages_to_save, dependencies = TRUE)",
    "  message('Checking for updates and rebuilding packages...')",
    "  update.packages(checkBuilt = TRUE, ask = FALSE)",
    "  # Clean up the package list file after successful installation",
    "  file.remove(package_file)",
    "  message('Package installation and update complete. Temporary file removed.')",
    "} else {",
    "  stop('ERROR: Package list file not found. Step 2 aborted.')",
    "}"
  )
  writeLines(INSTALL_SCRIPT_CONTENT, INSTALL_SCRIPT_PATH)
  
  
  # --- 5. Generate the Batch File Content (The Unified Execution Handler) ---
  BATCH_FILE_CONTENT <- c(
    "@echo off",
    "setlocal enableDelayedExpansion",
    "Title R Package Migration Utility (Single-Run Sequence)",
    paste0("set \"OLD_R_HOME=", OLD_R_HOME, "\""), 
    paste0("set \"NEW_R_HOME=", NEW_R_HOME, "\""),
    paste0("set \"SAVE_SCRIPT=", SAVE_SCRIPT_PATH, "\""),
    paste0("set \"INSTALL_SCRIPT=", INSTALL_SCRIPT_PATH, "\""),
    paste0("set \"COUNT_FILE=", COUNT_FILE_PATH, "\""),
    paste0("set \"LOG_FILE=", ERROR_LOG_PATH, "\""),
    "set INSTALL_SUCCESS=0",
    "",
    "echo ==============================================================",
    "echo R Package Migration Execution Handler",
    "echo Source: %OLD_R_HOME%",
    "echo Target: %NEW_R_HOME%",
    "echo Log File: %LOG_FILE%",
    "echo ==============================================================",
    "",
    "rem --- EXECUTE STEP 1: SAVE LIST (Uses Old R) ---",
    "echo. ",
    "echo [STEP 1/2] Saving package list from Old R... (This should be fast)",
    "\"%OLD_R_HOME%\\bin\\Rscript.exe\" \"%SAVE_SCRIPT%\" 1>>\"%LOG_FILE%\" 2>>&1",
    "if errorlevel 1 goto error_step1",
    "",
    "rem --- READ PACKAGE COUNT ---",
    "set /p PACKAGE_COUNT=<\"%COUNT_FILE%\"",
    "if not defined PACKAGE_COUNT set PACKAGE_COUNT=Unknown",
    "",
    "rem --- EXECUTE STEP 2: INSTALL PACKAGES (Uses New R) ---",
    "echo. ",
    "echo ==============================================================",
    "echo [STEP 2/2] STARTING PACKAGE INSTALLATION IN NEW R...",
    "echo TOTAL PACKAGES TO INSTALL: !PACKAGE_COUNT!",
    "echo WARNING: This process can take significant time (up to 2+ hours).",
    "echo All R output and errors are being redirected to the log file.",
    "echo This window will CLOSE AUTOMATICALLY when installation finishes.",
    "echo ==============================================================",
    "echo. ",
    "\"%NEW_R_HOME%\\bin\\Rscript.exe\" \"%INSTALL_SCRIPT%\" 1>>\"%LOG_FILE%\" 2>>&1",
    "if errorlevel 0 set INSTALL_SUCCESS=1",
    "goto cleanup",
    "",
    ":error_step1",
    "echo.",
    "echo CRITICAL FAILURE: Step 1 (Saving the package list) failed.",
    "echo Check permissions or the existence of the Old R path.",
    "goto cleanup",
    "",
    ":error_step2",
    "echo.",
    "echo CRITICAL FAILURE: Step 2 (Installation) encountered an error.",
    "echo Please check the log file for details.",
    "goto cleanup",
    "",
    ":cleanup",
    "rem --- Cleanup Temporary R Scripts and Count File ---",
    "echo.",
    "echo Cleaning up temporary files...",
    "if exist \"%SAVE_SCRIPT%\" del /f \"%SAVE_SCRIPT%\"",
    "if exist \"%INSTALL_SCRIPT%\" del /f \"%INSTALL_SCRIPT%\"",
    "if exist \"%COUNT_FILE%\" del /f \"%COUNT_FILE%\"", 
    
    "echo.",
    "echo --- PROCESS COMPLETE ---",
    "if %INSTALL_SUCCESS% equ 1 (",
    "    echo SUCCESS: Package migration finished successfully!",
    ") else (",
    "    echo FAILURE: Migration process had errors.",
    "    echo REVIEW LOG FILE: %LOG_FILE%",
    ")",
    "echo Press any key to close the window.",
    "pause >nul",
    "goto end",
    
    ":end",
    "rem --- Final Cleanup of Batch File (Done by R function) ---",
    "endlocal"
  )
  
  writeLines(BATCH_FILE_CONTENT, BATCH_FILE_PATH)
  
  
  # --- 6. Execute the Batch File ---
  cat("\n3. Executing Batch File...\n")
  cat(paste("   Process Log: All R output is being written to:", ERROR_LOG_PATH, "\n"))
  cat("   A command window will open, execute the migration, and pause at the end.\n")
  
  # Execute the batch file
  result <- shell(paste("cmd.exe /c", shQuote(BATCH_FILE_PATH)), wait = TRUE, invisible = FALSE)
  
  # --- 7. Final Cleanup of the Batch File and Reporting ---
  if (file.exists(BATCH_FILE_PATH)) {
    file.remove(BATCH_FILE_PATH) 
  }
  
  cat("\n--- Migration Utility Finished ---\n")
  if (file.exists(ERROR_LOG_PATH) && any(grepl("ERROR|FAILURE|stop\\(", readLines(ERROR_LOG_PATH)))) {
    message(paste("FAILURE DETECTED: Review errors in the log file:", ERROR_LOG_PATH))
  } else if (!file.exists(file.path(TEMP_DIR, PACKAGE_LIST_FILE))) {
    message("SUCCESS: Package list file was removed, indicating a clean installation process.")
  } else {
    message("NOTE: The migration process was interrupted. Check the command window output for details.")
  }
  
  return(invisible(NULL))
}