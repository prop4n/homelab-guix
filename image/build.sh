#!/usr/bin/env bash
# Build the generic homelab qcow2 image from systems/template.scm.
#
# Upload the resulting qcow2 somewhere Proxmox can reach by URL (a web server,
# an S3 bucket, a Proxmox "import" storage), then reference that URL from the
# proxmops manifests (spec.image.source).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO/image/homelab.qcow2}"
SIZE="${IMAGE_SIZE:-20G}"

echo "==> Building image from systems/template.scm (direct-mode load path)"
# -L .        makes (systems base) resolvable
# -L modules  makes (bitlatch services) and (metadata services nocloud) resolvable
STORE_IMG=$(guix system image -t qcow2 --image-size="$SIZE" \
  -L "$REPO" \
  -L "$REPO/modules" \
  "$REPO/systems/template.scm")

echo "==> Store image: $STORE_IMG"
cp "$STORE_IMG" "$OUT"
chmod +w "$OUT"
echo "==> Wrote $OUT ($(du -h "$OUT" | cut -f1))"
echo
echo "Next: upload $OUT and set spec.image.source in proxmox/*.yaml to its URL."
