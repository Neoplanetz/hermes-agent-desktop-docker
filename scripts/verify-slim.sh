#!/usr/bin/env bash
# Passes when build-only deps are absent from the final image and gvfs (GIO client module) is retained for desktop-trust.
set -euo pipefail
C=hermes-desktop
echo "[verify-slim] build-essential / dev headers purged?"
docker exec "$C" bash -c 'for p in build-essential python3-dev pkg-config libffi-dev; do dpkg -s "$p" >/dev/null 2>&1 && { echo "  present: $p"; exit 1; }; done; exit 0' \
  && echo "  OK build deps absent" || { echo "  FAIL a build dep remains"; exit 1; }
echo "[verify-slim] gvfs package (GIO client module for desktop-trust) retained?"
docker exec "$C" bash -c 'dpkg -s gvfs >/dev/null 2>&1' \
  && echo "  OK gvfs retained" || { echo "  FAIL gvfs missing (gio set metadata::trusted would break)"; exit 1; }
echo "[verify-slim] PASS"
