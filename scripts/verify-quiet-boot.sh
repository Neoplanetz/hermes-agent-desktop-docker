#!/usr/bin/env bash
# Passes when a FRESH-volume boot logs neither cosmetic warning and cua still works.
# Run AFTER a `docker compose down -v && ./scripts/spike-up.sh` so first-boot ran.
set -euo pipefail
C=hermes-desktop
echo "[verify-quiet-boot] no cua 'did not complete' warning in boot log?"
docker logs "$C" 2>&1 | grep -qiE 'cua-driver installing did not complete|did not complete' \
  && { echo "  FAIL cua systemd warning present"; exit 1; } || echo "  OK no cua warning"
echo "[verify-quiet-boot] GTK_MODULES has no gail (config-state, platform-independent)?"
docker exec "$C" su - hermes -c 'cat ~/.xprofile 2>/dev/null' | grep -E '^export GTK_MODULES' | grep -qw gail \
  && { echo "  FAIL gail still in GTK_MODULES"; exit 1; } || echo "  OK atk-bridge only (no gail)"
echo "[verify-quiet-boot] computer_use still healthy (doctor exit 0)?"
docker exec "$C" su - hermes -c 'DISPLAY=:1 hermes computer-use doctor' >/dev/null \
  && echo "  OK doctor" || { echo "  FAIL doctor"; exit 1; }
echo "[verify-quiet-boot] PASS"
