#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY="$ROOT/bcc-source-overlay"
TARGET="${PAGE_NHISTORY_SOURCE_ROOT:-${1:-}}"
if [[ -z "$TARGET" ]]; then
  echo "Set PAGE_NHISTORY_SOURCE_ROOT or pass the PAGe source checkout as argument." >&2
  exit 2
fi
TARGET="$(cd "$TARGET" && pwd)"
[[ -f "$TARGET/PAGe/DESCRIPTION" ]] || { echo "Invalid PAGe source root: $TARGET" >&2; exit 3; }
[[ -f "$OVERLAY/SHA256SUMS" ]] || { echo "Missing overlay SHA256SUMS" >&2; exit 3; }
(cd "$OVERLAY" && sha256sum -c SHA256SUMS)
while read -r sha rel; do
  [[ -n "$rel" ]] || continue
  src="$OVERLAY/$rel"
  dst="$TARGET/$rel"
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]]; then
    got="$(sha256sum "$dst" | awk '{print $1}')"
    if [[ "$got" != "$sha" ]]; then
      echo "Refusing to overwrite mismatched authority: $dst" >&2
      echo "expected=$sha actual=$got" >&2
      exit 4
    fi
    echo "verified existing $rel"
  else
    cp "$src" "$dst"
    got="$(sha256sum "$dst" | awk '{print $1}')"
    [[ "$got" == "$sha" ]] || { echo "Post-copy SHA mismatch: $dst" >&2; exit 5; }
    echo "installed $rel"
  fi
done < "$OVERLAY/SHA256SUMS"
echo "BCC source overlay PASS: $TARGET"
