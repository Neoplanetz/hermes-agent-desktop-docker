#!/usr/bin/env bash
# Boot-hygiene gate: GTK_MODULES carries no legacy `gail` (config-state assertion,
# platform-independent). Run AFTER a fresh boot.
set -euo pipefail
C=hermes-desktop
echo "[verify-quiet-boot] GTK_MODULES has no gail (atk-bridge only)?"
docker exec "$C" su - hermes -c 'cat ~/.xprofile 2>/dev/null' | grep -E '^export GTK_MODULES' | grep -qw gail \
  && { echo "  FAIL gail still in GTK_MODULES"; exit 1; } || echo "  OK atk-bridge only (no gail)"
echo "[verify-quiet-boot] PASS"
