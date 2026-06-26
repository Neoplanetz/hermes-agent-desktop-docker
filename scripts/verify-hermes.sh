#!/usr/bin/env bash
set -euo pipefail
C=hermes-desktop
echo "[verify-hermes] hermes on PATH at /usr/local/bin?"
docker exec "$C" su - hermes -c 'command -v hermes' | grep -q '/usr/local/bin/hermes' \
  && echo "  OK path" || { echo "  FAIL path"; exit 1; }
echo "[verify-hermes] hermes --version runs?"
docker exec "$C" su - hermes -c 'hermes --version' \
  && echo "  OK version" || { echo "  FAIL version"; exit 1; }
echo "[verify-hermes] PASS"
