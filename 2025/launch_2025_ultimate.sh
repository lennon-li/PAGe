#!/usr/bin/env bash
set -euo pipefail

# Detached launcher for the 2025-26 ultimate outer-fold run.
# Requires PAGE_RUN_ID in the environment; refuses to reuse an existing run dir.
# Invoke from the host: setsid/nohup cannot outlive teardown of a PID sandbox.
# Fail before installing or creating a run when PID 1 belongs to a sandbox.
# A bwrap --die-with-parent namespace kills even detached descendants.
host_init=$(cat /proc/1/comm)
if [[ "$host_init" != systemd && "$host_init" != init ]]; then
  echo "launch from a host shell (PID 1 must be systemd/init); setsid cannot escape a PID sandbox" >&2
  exit 1
fi
command -v setsid >/dev/null
command -v nohup >/dev/null
cd /home/yeli/repos/PAGe

export PAGE_FLU_HIST_FILE="${PAGE_FLU_HIST_FILE:-/home/yeli/FLU/flu_testing_data.csv}"
export PAGE_RUN_ROOT="${PAGE_RUN_ROOT:-/home/yeli/repos/PAGe/results/manuscript/nested-outer-2025-26-ultimate-20260911}"
: "${PAGE_RUN_ID:?PAGE_RUN_ID must be set}"

run_dir="$PAGE_RUN_ROOT/$PAGE_RUN_ID"
if [[ -e "$run_dir" ]]; then
  echo "refusing to overwrite existing run: $run_dir" >&2
  exit 1
fi
mkdir -p "$PAGE_RUN_ROOT"
mkdir "$run_dir"
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
# into a run-local library so workers cannot silently use an older user-level
# installation than the source loaded by the runner.
export PAGE_PACKAGE_LIBRARY="$run_dir/r-lib"
mkdir "$PAGE_PACKAGE_LIBRARY"
R CMD INSTALL --library="$PAGE_PACKAGE_LIBRARY" --no-multiarch --with-keep.source PAGe >"$run_dir/package_install.log" 2>&1
export R_LIBS_USER="$PAGE_PACKAGE_LIBRARY"
# Verify the freshly installed package is the exact source revision before the
# model run starts. Rejects an install outside the run-local library, a
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
    stop("installed PAGe is not in the run-local library: ", pkg_dir)
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
# The detached child records its own PID (setsid may fork), then exec retains
# that PID and start time. Publish the identity atomically for the watchdog.
setsid nohup bash -c '
  set -euo pipefail
  runner_script="$1"
  proc_stat=$(cat "/proc/$$/stat")
  proc_fields=${proc_stat##*) }
  start_ticks=$(awk "{print \$20}" <<< "$proc_fields")
  printf "%s\n" "$$" > "$PAGE_RUN_DIR/runner.pid"
  printf "pid\t%s\nstart_ticks\t%s\ncmd_marker\t%s\n" \
    "$$" "$start_ticks" "$runner_script" > "$PAGE_RUN_DIR/runner_identity.tsv.tmp"
  mv "$PAGE_RUN_DIR/runner_identity.tsv.tmp" "$PAGE_RUN_DIR/runner_identity.tsv"
  exec Rscript "$runner_script"
' page-2025-runner /home/yeli/repos/PAGe/2025/run_2025_ultimate.R \
  >> "$run_dir/run.log" 2>&1 < /dev/null &
# Wait only for the launch handshake, never for the model run.
for ((attempt = 0; attempt < 100; attempt++)); do
  if [[ -s "$run_dir/runner_identity.tsv" ]]; then
    printf 'launched pid=%s run_dir=%s\n' "$(cat "$run_dir/runner.pid")" "$run_dir"
    exit 0
  fi
  sleep 0.05
done
echo "runner identity was not published; inspect $run_dir/run.log" >&2
exit 1
