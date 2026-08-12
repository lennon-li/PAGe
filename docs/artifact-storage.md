# Private artifact storage

Large tuning outputs, run checkpoints, logs, and rendered results must not be
written to the checkout's root filesystem on BCC.  The designated private
artifact location is:

```text
host:  pho-rdpdl-23 (BCC)
path:  /mnt/nfsv4/Users/yeli/PAGe-artifacts/
mount: NFS at /mnt/nfsv4/Users (not the local /dev/vda3 system disk)
```

The share is already mounted on BCC and is writable by `yeli`; no additional
local disk is currently attached.  Keep package source and small test fixtures
in `/home/yeli/repos/PAGe`, but place private run products under the artifact
directory.  Existing preserved material is organized as follows:

- `asgard-untracked-20260812/` — the 17 GB Asgard run-artifact bundle moved
  during the BCC synchronization;
- `bcc-pre-sync-20260812/scripts/` — five temporary BCC scripts preserved
  before the checkout fast-forward.

Asgard's local staging copy is on its separate data disk at
`/mnt/storage1/PAGe-artifacts/asgard-untracked-20260812/`; the main checkout
disk is not used for that bundle.

Do not commit private observations, model objects, checkpoints, or generated
result trees.  Record the artifact subdirectory and run identifier in the
corresponding disclosure-safe manifest.
