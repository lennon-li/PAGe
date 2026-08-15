# Private artifact storage

Large tuning outputs, run checkpoints, logs, and rendered results must not be
written to the checkout's root filesystem on a remote compute host. The
designated private artifact location is:

```text
path:  a writable private NFS artifact share outside the checkout
mount: configured per machine in the private runbook (never the system disk)
```

Keep package source and small test fixtures in the checkout, but place private
run products under the configured artifact directory. The machine-specific
host, account, and mount path are intentionally kept out of this repository.
Existing preserved material is organized as follows:

- `holdouts-and-docs/` — the 2022–2024 holdout bundles and related documents;
- `data/` and `results/` — the former Asgard ignored artifact trees;
- `bcc-pre-sync/` — five temporary BCC scripts preserved before the checkout
  fast-forward;
- `2018/` — the active 2018–19 holdout cycle, including checkpoints and logs.
- `bcc-2018-19/` — the completed BCC artifact set audited on 2026-08-12;
  its metadata identifies a `2018-19` holdout (not a `2019-20` holdout).
- `bcc-2016-17-v1/`, `bcc-2016-17-v2/`, and `bcc-2017-18-v2/` — BCC
  installed-package holdout cycles and their replay artifacts. The `v1`
  2016–17 run is retained as the boundary-gate failure record; `v2` is its
  expanded-M1 retry.
- `2022-final-expanded-v3/` — the active Asgard 2022–23 staged cycle;
  its M0 settlement is reused and its expanded M1 gate must pass before M2.
- `legacy-checkout-artifacts-20260813/` — older ignored checkout artifacts
  moved out of the repository tree (including the prior check output).

The archive is accessed through a configured user-space mount; the checkout's
`data/` path may be a symlink into it. The tracked checkout `results/`
directory contains only its small documentation README; generated result trees
belong under the archive root. Machine-specific mount mappings and disk-health
notes belong in the private runbook, not in this repository.

Do not commit private observations, model objects, checkpoints, or generated
result trees.  Record the artifact subdirectory and run identifier in the
corresponding disclosure-safe manifest.
