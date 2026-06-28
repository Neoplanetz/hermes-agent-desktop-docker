#!/usr/bin/env bash
set -euo pipefail
C=hermes-desktop
echo "[verify-hermes] hermes on PATH at /usr/local/bin?"
docker exec "$C" su - hermes -c 'command -v hermes' | grep -q '/usr/local/bin/hermes' \
  && echo "  OK path" || { echo "  FAIL path"; exit 1; }
echo "[verify-hermes] hermes --version runs?"
docker exec "$C" su - hermes -c 'hermes --version' \
  && echo "  OK version" || { echo "  FAIL version"; exit 1; }
echo "[verify-hermes] pinned to v0.17.0 (2026.6.19)?"
docker exec "$C" su - hermes -c 'hermes --version' | grep -q 'v0.17.0 (2026.6.19)' \
  && echo "  OK pinned version" || { echo "  FAIL version not pinned to v0.17.0 (2026.6.19)"; exit 1; }
echo "[verify-hermes] checkout pinned to dd0e4ab?"
docker exec "$C" git -C /usr/local/lib/hermes-agent rev-parse HEAD 2>/dev/null | grep -q '^dd0e4ab81abccf7df5b11c6c16853d5e5de9db69' \
  && echo "  OK pinned commit" || { echo "  FAIL checkout not at pinned commit"; exit 1; }
echo "[verify-hermes] PASS"
