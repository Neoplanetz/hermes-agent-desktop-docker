#!/usr/bin/env bash
set -euo pipefail
C=hermes-desktop; U="${HERMES_USER:-hermes}"
echo "[verify-config-seed] ~/.hermes/config.yaml + SOUL.md present?"
docker exec "$C" su - "$U" -c 'test -f ~/.hermes/config.yaml && test -f ~/.hermes/SOUL.md' \
  && echo "  OK seeded" || { echo "  FAIL missing"; exit 1; }
echo "[verify-config-seed] image seed pins no model (left for runtime)?"
docker exec "$C" bash -c 'grep -qiE "model:|provider:" /opt/hermes-defaults/.hermes/config.yaml' \
  && { echo "  FAIL model pinned in image seed"; exit 1; } || echo "  OK model unset in image seed"
echo "[verify-config-seed] PASS"
