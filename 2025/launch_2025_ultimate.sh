#!/usr/bin/env bash
set -euo pipefail

# Detached launcher for the 2025-26 ultimate outer-fold run.
# Requires PAGE_RUN_ID in the environment; refuses to reuse an existing run dir.
cd /home/yeli/repos/PAGe

export PAGE_FLU_HIST_FILE="${PAGE_FLU_HIST_FILE:-/home/yeli/FLU/flu_testing_data.csv}"
export PAGE_RUN_ROOT="${PAGE_RUN_ROOT:-/home/yeli/repos/PAGe/results/manuscript/nested-outer-2025-26-ultimate-20260911}"
: "${PAGE_RUN_ID:?PAGE_RUN_ID must be set}"

run_dir="$PAGE_RUN_ROOT/$PAGE_RUN_ID"
if [[ -e "$run_dir/status.tsv" || -d "$run_dir/artifacts" ]]; then
  echo "refusing to overwrite existing run: $run_dir" >&2
  exit 1
fi
mkdir -p "$run_dir"
export PAGE_RUN_DIR="$run_dir"
# Record a content hash of the source installed below before any package
# workers are allowed to start. The post-install check compares this value
# with the current source and records the installed package database hash.
Rscript -e '
  repo <- "/home/yeli/repos/PAGe"
  files <- sort(c(
    file.path(repo, "PAGe", "DESCRIPTION"),
    file.path(repo, "PAGe", "NAMESPACE"),
    list.files(file.path(repo, "PAGe", "R"), pattern = "[.]R$", full.names = TRUE)
  ))
  hashes <- vapply(files, digest::digest, character(1), file = TRUE,
    algo = "sha256", serialize = FALSE)
  cat(digest::digest(paste(basename(files), hashes, collapse = "\n"), algo = "sha256"))
' > "$run_dir/source_manifest_before_install.txt"
# Nested future workers load an installed package. Build the current source
# into a repo-local library so workers cannot silently use an older user-level
# installation than the source loaded by the runner.
mkdir -p /home/yeli/repos/PAGe/r-lib
R CMD INSTALL --library=/home/yeli/repos/PAGe/r-lib --no-multiarch --with-keep.source PAGe >/tmp/page-2025-package-install.log 2>&1
export R_LIBS_USER="/home/yeli/repos/PAGe/r-lib"
export PAGE_PACKAGE_LIBRARY="/home/yeli/repos/PAGe/r-lib"
# Verify the freshly installed package is the exact source revision before the
# model run starts. Rejects an install outside the repo-local library, a
# version mismatch, changed source contents, or an install that predates the
# current source edits.
Rscript -e '
  repo <- "/home/yeli/repos/PAGe"
  files <- sort(c(
    file.path(repo, "PAGe", "DESCRIPTION"),
    file.path(repo, "PAGe", "NAMESPACE"),
    list.files(file.path(repo, "PAGe", "R"), pattern = "[.]R$", full.names = TRUE)
  ))
  hashes <- vapply(files, digest::digest, character(1), file = TRUE,
    algo = "sha256", serialize = FALSE)
  source_hash <- digest::digest(
    paste(basename(files), hashes, collapse = "\n"), algo = "sha256"
  )
  expected_hash <- trimws(readLines(
    file.path(Sys.getenv("PAGE_RUN_DIR"), "source_manifest_before_install.txt"),
    n = 1L
  ))
  if (!identical(source_hash, expected_hash)) {
    stop("PAGe source changed during installation; rerun from a stable checkout.")
  }
  lib <- normalizePath(Sys.getenv("PAGE_PACKAGE_LIBRARY"), mustWork = TRUE)
  pkg_dir <- normalizePath(find.package("PAGe", lib.loc = lib), mustWork = TRUE)
  if (!startsWith(pkg_dir, paste0(lib, "/"))) {
    stop("installed PAGe is not in the repo-local library: ", pkg_dir)
  }
  files <- c(
    file.path(repo, "PAGe", "DESCRIPTION"),
    file.path(repo, "PAGe", "NAMESPACE"),
    list.files(file.path(repo, "PAGe", "R"), pattern = "[.]R$", full.names = TRUE)
  )
  files <- sort(files[file.exists(files)])
  installed_version <- unname(read.dcf(file.path(pkg_dir, "DESCRIPTION"))[1, "Version"])
  source_version <- unname(read.dcf(file.path(repo, "PAGe", "DESCRIPTION"))[1, "Version"])
  if (!identical(installed_version, source_version)) {
    stop("installed PAGe version ", installed_version, " != source ", source_version)
  }
  rdb <- file.info(file.path(pkg_dir, "R", "PAGe.rdb"))$mtime
  newest_source <- max(file.info(files)$mtime)
  if (!is.finite(as.numeric(rdb)) || rdb < newest_source) {
    stop("installed PAGe predates the current source; reinstall before launch.")
  }
  installed_hash <- digest::digest(file = file.path(pkg_dir, "R", "PAGe.rdb"),
    algo = "sha256", serialize = FALSE)
  revision <- tryCatch(
    trimws(system2("git", c("-C", repo, "rev-parse", "HEAD"), stdout = TRUE)),
    error = function(e) NA_character_
  )
  cat("verified installed PAGe ", installed_version, " at ", pkg_dir,
      " source_revision=", revision, " source_sha256=", source_hash,
      " installed_rdb_sha256=", installed_hash, "\n", sep = "")
' > "$run_dir/package_revision_check.txt" 2>&1
printf '%s\n' "$$" > "$run_dir/runner.pid"
exec Rscript 2025/run_2025_ultimate.R >> "$run_dir/run.log" 2>&1
