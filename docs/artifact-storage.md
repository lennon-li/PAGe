# Private artifact storage

Large tuning outputs, run checkpoints, logs, and rendered results must not be
written to the checkout's root filesystem on BCC.  The designated private
artifact location is:

```text
host:  pho-rdpdl-23 (BCC)
path:  /mnt/nfsv4/Users/yeli/PAGe-artifacts/asgard-archive-20260812/
mount: NFS at /mnt/nfsv4/Users (not the local /dev/vda3 system disk)
```

The share is already mounted on BCC and is writable by `yeli`; no additional
local disk is currently attached.  Keep package source and small test fixtures
in `/home/yeli/repos/PAGe`, but place private run products under the artifact
directory.  Existing preserved material is organized as follows:

- `holdouts-and-docs/` — the 2022–2024 holdout bundles and related documents;
- `data/` and `results/` — the former Asgard ignored artifact trees;
- `bcc-pre-sync/` — five temporary BCC scripts preserved before the checkout
  fast-forward;
- `2018/` — the active 2018–19 holdout cycle, including checkpoints and logs.

Asgard accesses this archive through the user-space mount
`/home/yeli/PAGe-bcc-artifacts/`; the checkout-level `data/` and `results/`
paths are symlinks into it.  Asgard's local `/mnt/storage1` disk (`/dev/sdb`)
entered emergency read-only mode after hardware I/O errors on 2026-08-12.  It
is not an active destination; older copies there remain only until an
administrator repairs and verifies the disk.

Do not commit private observations, model objects, checkpoints, or generated
result trees.  Record the artifact subdirectory and run identifier in the
corresponding disclosure-safe manifest.
