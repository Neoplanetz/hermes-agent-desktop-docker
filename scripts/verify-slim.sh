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
echo "[verify-slim] transitive build toolchain (gcc/g++/make/cc) absent?"
docker exec "$C" bash -c 'for b in gcc g++ make cc; do command -v "$b" >/dev/null 2>&1 && { echo "  present: $b"; exit 1; }; done; exit 0' \
  && echo "  OK toolchain absent" || { echo "  FAIL a build-toolchain binary remains"; exit 1; }
echo "[verify-slim] npm cache not bloating the image (<25 MB)?"
docker exec "$C" bash -c 's=$(du -sm /root/.npm 2>/dev/null | cut -f1); [ -z "$s" ] && s=0; [ "$s" -lt 25 ]' \
  && echo "  OK npm cache trimmed" || { echo "  FAIL npm cache too large (build artifact leak)"; exit 1; }
echo "[verify-slim] PASS"
