#!/usr/bin/env bash
set -euo pipefail

# Venkata launcher. This script intentionally refuses to run until the
# single-fold gate run supplied in PAGE_GATE_RUN_DIR has completed.

: "${PAGE_REPO_ROOT:?Set PAGE_REPO_ROOT to the latest PAGe checkout on Venkata}"
: "${PAGE_PREP_DIR:?Set PAGE_PREP_DIR to the transferred all-season preparation directory}"
: "${PAGE_RUN_ROOT:?Set PAGE_RUN_ROOT to the Venkata artifact root}"
: "${PAGE_RUN_ID:?Set PAGE_RUN_ID to a new run identifier}"
: "${PAGE_GATE_RUN_DIR:?Set PAGE_GATE_RUN_DIR to the completed 2025-26 gate run}"

cd "$PAGE_REPO_ROOT"
export PAGE_REPO_ROOT
if [[ "$(uname -s)" == "MINGW"* || "$(uname -s)" == "Darwin"* ]]; then
  echo "This launcher requires a Linux Venkata host." >&2
  exit 1
fi

gate_status="$(awk -F '\\t' 'NR > 1 { last = $2 } END { print last }' "$PAGE_GATE_RUN_DIR/status.tsv" 2>/dev/null || true)"
if [[ "$gate_status" != "complete" ]]; then
  echo "Refusing Venkata launch: gate run is not complete (status=$gate_status)." >&2
  exit 1
fi

run_dir="$PAGE_RUN_ROOT/$PAGE_RUN_ID"
if [[ -e "$run_dir" ]]; then
  echo "Refusing to overwrite existing run: $run_dir" >&2
  exit 1
fi
mkdir -p "$run_dir"
printf '%s\n' "$$" > "$run_dir/launcher.pid"
export PAGE_RUN_DIR="$run_dir"
export PAGE_PACKAGE_LIBRARY="${PAGE_PACKAGE_LIBRARY:-$PAGE_REPO_ROOT/r-lib}"
export R_LIBS_USER="$PAGE_PACKAGE_LIBRARY"
export PAGE_FUTURE_BACKEND="multicore"

Rscript -e '
  repo <- normalizePath(Sys.getenv("PAGE_REPO_ROOT"), mustWork = TRUE)
  files <- sort(c(file.path(repo, "PAGe", "DESCRIPTION"),
    file.path(repo, "PAGe", "NAMESPACE"),
    list.files(file.path(repo, "PAGe", "R"), pattern = "[.]R$", full.names = TRUE)))
  hashes <- vapply(files, digest::digest, character(1), file = TRUE,
    algo = "sha256", serialize = FALSE)
  cat(digest::digest(paste(basename(files), hashes, collapse = "\n"), algo = "sha256"))
' > "$run_dir/source_manifest_before_install.txt"

mkdir -p "$PAGE_PACKAGE_LIBRARY"
R CMD INSTALL --library="$PAGE_PACKAGE_LIBRARY" --no-multiarch --with-keep.source PAGe \
  >"$run_dir/package_install.log" 2>&1

Rscript -e '
  repo <- normalizePath(Sys.getenv("PAGE_REPO_ROOT"), mustWork = TRUE)
  lib <- normalizePath(Sys.getenv("PAGE_PACKAGE_LIBRARY"), mustWork = TRUE)
  pkg <- normalizePath(find.package("PAGe", lib.loc = lib), mustWork = TRUE)
  if (!startsWith(pkg, paste0(lib, "/"))) stop("PAGe is outside PAGE_PACKAGE_LIBRARY")
  files <- sort(c(file.path(repo, "PAGe", "DESCRIPTION"),
    file.path(repo, "PAGe", "NAMESPACE"),
    list.files(file.path(repo, "PAGe", "R"), pattern = "[.]R$", full.names = TRUE)))
  hashes <- vapply(files, digest::digest, character(1), file = TRUE,
    algo = "sha256", serialize = FALSE)
  source_hash <- digest::digest(paste(basename(files), hashes, collapse = "\n"), algo = "sha256")
  expected <- trimws(readLines(file.path(Sys.getenv("PAGE_RUN_DIR"),
    "source_manifest_before_install.txt"), n = 1L))
  if (!identical(source_hash, expected)) stop("PAGe source changed during install")
  version <- read.dcf(file.path(pkg, "DESCRIPTION"))[1, "Version"]
  revision <- trimws(system2("git", c("-C", repo, "rev-parse", "HEAD"), stdout = TRUE))
  cat("verified PAGe ", version, " at ", pkg, " source_revision=", revision,
    " source_sha256=", source_hash, "\n", sep = "")
' > "$run_dir/package_revision_check.txt" 2>&1

cmd=(Rscript scripts/run_outer_holdouts_parallel.R
  --prepared "$PAGE_PREP_DIR"
  --output "$run_dir"
  --outer-workers "${PAGE_OUTER_WORKERS:-4}"
  --inner-cores "${PAGE_INNER_CORES:-1}")
if [[ -n "${PAGE_PROTOCOL_RDS:-}" ]]; then
  cmd+=(--protocol "$PAGE_PROTOCOL_RDS")
fi
"${cmd[@]}" >> "$run_dir/run.log" 2>&1
