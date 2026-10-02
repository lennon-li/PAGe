# Asgard / AgentPorter tooling handoff

Date: 2026-09-28
Target: AgentPorter execution sandbox used by AsgardGPT / coding agents
Goal: expose the host development/navigation/reporting toolchain inside `exec_run` / agent subprocesses so repo work can be performed and verified directly.

## Repo-grounded requirements

PAGe `AGENTS.md` says:

- `docs/` contains Quarto documentation and `.qmd` files are first-class project artifacts.
- use the shared R-development rules / seasonal-forecast skill;
- use `Rscript` for pipeline execution;
- use `styler` after package R edits;
- use `devtools::document()` when package docs/interfaces change;
- prefer bounded local tooling and compact logs.

AgentPorter `docs/local-setup.md` explicitly requires:

- Linux / WSL2;
- Python 3.11+;
- `bubblewrap`;
- `ripgrep`;
- `patch`;
- `git`.

## Current sandbox visibility

Already visible:

- `rg` `/usr/bin/rg`
- `fdfind` `/usr/bin/fdfind`
- `fzf` `/usr/bin/fzf`
- `batcat` `/usr/bin/batcat`
- `jq` `/usr/bin/jq`
- `delta` `/usr/bin/delta`
- `shellcheck` `/usr/bin/shellcheck`
- `hyperfine` `/usr/bin/hyperfine`
- `python3` `/usr/bin/python3`
- `R`, `Rscript`
- `pandoc`
- `make`
- `git`, `patch`
- `bwrap`
- `rsync`, `curl`, `wget`
- `file`, `lsof`, `ss`, `findmnt`, `sha256sum`
- `tmux`

Missing from sandbox PATH:

- `quarto` **high priority**
- `rtk` (not found in PAGe or sibling repo guidance; if this is a local Asgard tool, expose its existing host binary/package and document its purpose)
- `fd` command alias (`fdfind` exists)
- `bat` command alias (`batcat` exists)
- `yq`
- `eza`
- `tree`
- `shfmt`
- `watchexec`
- `entr`
- `duckdb`
- `sqlite3`
- `uv`

## Requested exposure / installation priority

### P0 — required for current PAGe work

1. **Quarto CLI**
   - expose `quarto` in the AgentPorter sandbox PATH;
   - must support `quarto render docs/<file>.qmd`;
   - verify it can see the same `Rscript` and `pandoc` environment used by agents.

2. **R toolchain**
   - `R`, `Rscript` already exposed;
   - ensure R packages used by repo development are available in the governed library: `testthat`, `devtools`, `styler`, `roxygen2`, `data.table`, `digest`, plus project runtime dependencies;
   - expose a deterministic library path rather than relying on user-library shadowing.

3. **Core AgentPorter tools**
   - keep `bwrap`, `rg`, `patch`, `git`, `python3` visible inside the sandbox.

### P1 — navigation / inspection

Expose aliases/binaries:

- `fd` (currently only `fdfind`)
- `bat` (currently only `batcat`)
- `fzf`
- `eza`
- `tree`
- `jq`
- `yq`
- `delta`

These materially improve bounded repo navigation and reduce large `find`/`cat` outputs.

### P1 — shell / deployment validation

- `shellcheck`
- `shfmt`
- `curl`
- `wget`
- `rsync`
- `lsof`
- `ss`
- `findmnt`
- `file`
- `sha256sum`
- `tar`, `gzip`, `unzip`

PAGe now has systemd/API/NFS deployment work, so `findmnt`, networking inspection, hashing, and shell linting are important.

### P2 — development speed / observation

- `hyperfine`
- `watchexec`
- `entr`
- `tmux`
- `htop` / `btop` if available
- `strace`
- `time` (`/usr/bin/time` preferred)

Use for bounded performance tests, process supervision, and short-lived file/test watchers. Do not use watchers to bypass PAGe long-job supervision rules.

### P2 — data inspection

- `duckdb`
- `sqlite3`

Useful for large CSV/Parquet/artifact inspection without loading everything into R/Python.

### P2 — Python environment tooling

- `uv`
- `python3`

`uv` is preferred for fast isolated Python/tool environments when a repo task genuinely needs Python.

## `rtk`

`rtk` is currently:

- not found in the AgentPorter sandbox PATH;
- not referenced by PAGe `AGENTS.md`, `.ai/` skills, AgentPorter setup docs, or the searched sibling repo guidance.

If `rtk` is an Asgard-local tool Lennon expects agents to use, please:

1. identify the host binary with `command -v rtk` outside the sandbox;
2. expose that exact binary and required runtime files inside Bubblewrap;
3. add its intended usage to AgentPorter or repo agent guidance so agents know when to use it;
4. add it to `agentporter doctor` / tooling diagnostics.

Do not silently install an unrelated package named `rtk` based only on the command name.

## AgentPorter integration requirements

The important requirement is **sandbox visibility**, not merely host installation.

For each tool:

1. host `command -v <tool>` succeeds;
2. the binary and required shared/runtime files are visible under Bubblewrap;
3. `exec_run` with the same registered workspace sees the command;
4. delegated agents (`jax`, `claude`, `opencode`, `agy`) inherit the same PATH/tool visibility where appropriate;
5. tools that need config/cache directories get only the minimum required read/write mounts.

Prefer a stable explicit PATH in AgentPorter rather than shell-profile-only aliases.

For Debian/Ubuntu naming mismatches, provide stable aliases/symlinks:

```text
fd     -> fdfind
bat    -> batcat
```

## Suggested doctor check

Extend `agentporter doctor` or add a repo-local tool diagnostic that reports at least:

```text
quarto
R
Rscript
pandoc
rg
fd
fzf
bat
jq
yq
git
delta
shellcheck
shfmt
hyperfine
python3
uv
bwrap
patch
rsync
curl
lsof
ss
findmnt
sha256sum
rtk   # if this is a supported local tool
```

For Quarto/R, include versions:

```bash
quarto --version
Rscript --version
pandoc --version
Rscript --vanilla -e 'cat(R.version.string, "\n"); print(.libPaths())'
```

## Acceptance test for this handoff

From an AgentPorter `exec_run` sandbox in the PAGe workspace, the following should succeed:

```bash
command -v quarto rg fd fzf bat jq git shellcheck hyperfine Rscript pandoc
quarto --version
Rscript --vanilla -e 'cat(R.version.string, "\n")'
quarto render docs/pipeline_overview.qmd --to html
rg -n "M0|M1|M2" docs/pipeline_overview.qmd | head
fd -e qmd docs | head
bat --style=plain --line-range 1:30 AGENTS.md
```

If `rtk` is part of the supported workstation toolchain, also require:

```bash
command -v rtk
rtk --help
```

The tooling handoff is complete only when these commands work **inside the same sandbox used by AsgardGPT**, not only in a human login shell.
