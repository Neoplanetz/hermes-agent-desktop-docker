#!/usr/bin/env bash
# Passes when home is volume-backed, seeded on fresh volume, and persists.
set -euo pipefail
cd "$(dirname "$0")/.."
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-persistence] /home/$U is a mount (volume)?"
docker exec "$C" sh -c "mount | grep -q ' /home/$U '" && echo "  OK mounted" || { echo "  FAIL not a mount"; exit 1; }
echo "[verify-persistence] VNC startup + seeded ~/.hermes/config.yaml present?"
docker exec "$C" su - "$U" -c 'test -f ~/.vnc/xstartup && test -f ~/.hermes/config.yaml' \
  && echo "  OK seeded" || { echo "  FAIL not seeded"; exit 1; }
echo "[verify-persistence] write marker, recreate container, marker survives?"
docker exec "$C" su - "$U" -c 'echo persist-probe > ~/.persist-probe'
docker compose up -d --force-recreate >/dev/null
for i in $(seq 1 30); do
  docker exec "$C" su - "$U" -c 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1' && break
  sleep 1
  [ "$i" -eq 30 ] && { echo "  FAIL :1 never came up after recreate"; exit 1; }
done
docker exec "$C" su - "$U" -c 'grep -q persist-probe ~/.persist-probe' \
  && echo "  OK persisted across recreate" || { echo "  FAIL lost on recreate"; exit 1; }
echo "[verify-persistence] PASS"
