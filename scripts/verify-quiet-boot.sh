#!/usr/bin/env bash
# Passes when a FRESH-volume boot logs neither cosmetic warning and cua still works.
# Run AFTER a `docker compose down -v && ./scripts/spike-up.sh` so first-boot ran.
set -euo pipefail
C=hermes-desktop
echo "[verify-quiet-boot] no cua 'did not complete' warning in boot log?"
docker logs "$C" 2>&1 | grep -qiE 'cua-driver installing did not complete|did not complete' \
  && { echo "  FAIL cua systemd warning present"; exit 1; } || echo "  OK no cua warning"
echo "[verify-quiet-boot] no gail GTK module warning in the VNC session log?"
# xstartup/GTK output goes to ~/.vnc/*.log (the X session), not docker logs.
docker exec "$C" su - hermes -c 'cat ~/.vnc/*.log 2>/dev/null' | grep -qiE 'gail|Failed to load module .gail' \
  && { echo "  FAIL gail warning present"; exit 1; } || echo "  OK no gail warning"
echo "[verify-quiet-boot] computer_use still healthy (doctor exit 0)?"
docker exec "$C" su - hermes -c 'DISPLAY=:1 hermes computer-use doctor' >/dev/null \
  && echo "  OK doctor" || { echo "  FAIL doctor"; exit 1; }
echo "[verify-quiet-boot] PASS"
