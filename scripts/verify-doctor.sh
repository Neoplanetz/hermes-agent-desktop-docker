#!/usr/bin/env bash
set -euo pipefail
C=hermes-desktop
echo "[verify-doctor] hermes computer-use doctor (DISPLAY=:1)…"
docker exec "$C" su - hermes -c 'DISPLAY=:1 hermes computer-use doctor'
echo "[verify-doctor] exit 0 → PASS"
